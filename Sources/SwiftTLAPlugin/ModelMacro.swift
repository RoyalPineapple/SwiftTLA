import SwiftCompilerPlugin
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA

// MARK: - Shared parsing and verification

struct ParsedMacroModel {
    let typeName: String
    let variables: [(String, TLAValue, StateExpr?)]
    let actions: [(String, ActionExpr)]
    let symmetricCollections: [SpecParser.ParsedSymmetricCollection]
    let collectionActions: [SpecParser.ParsedCollectionAction]
}

struct MacroExpander {
    let isActor: Bool

    func parseAndVerify(_ declaration: some DeclGroupSyntax) throws -> ParsedMacroModel {
        let typeName: String
        let memberList: MemberBlockItemListSyntax

        if isActor, let a = declaration.as(ActorDeclSyntax.self) {
            typeName = a.name.text; memberList = a.memberBlock.members
        } else if let s = declaration.as(StructDeclSyntax.self) {
            typeName = s.name.text; memberList = s.memberBlock.members
        } else if let c = declaration.as(ClassDeclSyntax.self) {
            typeName = c.name.text; memberList = c.memberBlock.members
        } else {
            throw SimpleError(isActor ? "@TLAActor on actors only" : "Must be applied to a struct or class")
        }

        guard let closure = Self.findSpec(in: memberList) else {
            throw SimpleError("Could not find 'TLASpec' builder in '\(typeName)'")
        }

        let rewritten = rewriteVarNames(in: closure)
        let parsed = SpecParser.parseSpecClosure(rewritten)
        if let diagnostic = parsed.diagnostics.first {
            throw diagnostic
        }
        if parsed.variables.isEmpty { throw SimpleError("No variables in spec") }

        let spec = TLASpec(
            name: typeName,
            variables: parsed.variables.map { NamedVar(name: $0.name, initial: $0.initial, initialSet: $0.initialSet) },
            constants: parsed.constants,
            actions: parsed.actions.map { NamedAction(name: $0.name, body: $0.body) },
            invariants: parsed.invariants.map { NamedInvariant(name: $0.name, body: $0.body) },
            temporalProperties: parsed.temporal.map { NamedTemporal(name: $0.name, expr: $0.expr) },
            fairness: parsed.fairness,
            symmetricCollections: parsed.symmetricCollections.map(\.declaration)
        )

        let result = try ModelChecker(spec: spec, maxStates: 1_000_000).check()
        switch result {
        case .invariantViolated(let inv, _, let trace):
            throw SimpleError("Invariant '\(inv)' violated:\n\(trace.map(String.init(describing:)).joined(separator: "\n"))")
        case .error(let msg): throw SimpleError("Checker error: \(msg)")
        case .deadlocked(let s): throw SimpleError("Deadlock at: \(s)")
        case .depthExceeded(let c, let l): throw SimpleError("Depth exceeded: \(c)/\(l)")
        case .livenessViolated(let msg): throw SimpleError("Liveness violated: \(msg)")
        case .ok: SpecRegistry.register(spec)
        case .bounded(_, let outcome):
            guard case .ok = outcome else {
                throw SimpleError("Checker error: \(outcome)")
            }
            SpecRegistry.register(spec)
        }

        return ParsedMacroModel(
            typeName: typeName,
            variables: parsed.variables,
            actions: parsed.actions,
            symmetricCollections: parsed.symmetricCollections,
            collectionActions: parsed.collectionActions
        )
    }

    func generateMembers(
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?)],
        actions: [(name: String, body: ActionExpr)],
        symmetricCollections: [SpecParser.ParsedSymmetricCollection] = [],
        collectionActions: [SpecParser.ParsedCollectionAction] = []
    ) -> [DeclSyntax] {
        var decls: [DeclSyntax] = []

        decls.append(DeclSyntax(
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.private))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: "_state"),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: "State")),
                    initializer: InitializerClauseSyntax(value: ExprSyntax(stringLiteral: "State(from: runtime.initialStates().first!)"))
                )]
            )
        ))

        decls.append(DeclSyntax(Self.generateVariablesEnum(variables: variables)))
        decls.append(DeclSyntax(Self.generateActionsEnum(actions: actions)))
        decls.append(DeclSyntax(Self.generateStateStruct(variables: variables)))
        decls.append(contentsOf: generateCollectionRuntimeMembers(symmetricCollections))
        let ordinaryVariables = variables.filter { variable in
            !symmetricCollections.contains(where: { $0.name == variable.name })
        }
        decls.append(contentsOf: Self.generateVariableProperties(variables: ordinaryVariables).map(DeclSyntax.init))
        decls.append(contentsOf: generateActionMethods(
            actions: actions,
            collectionActions: collectionActions,
            symmetricCollections: symmetricCollections
        ).map(DeclSyntax.init))
        decls.append(DeclSyntax(generateApplyHelper(symmetricCollections: symmetricCollections)))
        decls.append(DeclSyntax(
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.static))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: "runtime"),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: "SpecRuntime")),
                    accessorBlock: AccessorBlockSyntax(accessors: .getter(
                        CodeBlockItemListSyntax { ExprSyntax(stringLiteral: "SpecRuntime(spec: spec)") }
                    ))
                )]
            )
        ))

        return decls
    }

    // MARK: - Var name injection

    private func rewriteVarNames(in closure: ClosureExprSyntax) -> ClosureExprSyntax {
        var newStatements: [CodeBlockItemSyntax] = []
        for item in closure.statements {
            newStatements.append(rewriteVarBinding(in: item))
        }
        return closure.with(\.statements, CodeBlockItemListSyntax(newStatements))
    }

    private func rewriteVarBinding(in item: CodeBlockItemSyntax) -> CodeBlockItemSyntax {
        guard case .decl(let decl) = item.item,
              let varDecl = decl.as(VariableDeclSyntax.self)
        else { return item }

        var bindingsChanged = false
        var newBindings: [PatternBindingSyntax] = []
        for binding in varDecl.bindings {
            guard let patternName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let initializer = binding.initializer,
                  let fc = initializer.value.as(FunctionCallExprSyntax.self)
            else { newBindings.append(binding); continue }

            let callee = fc.calledExpression
            let isVar = callee.as(DeclReferenceExprSyntax.self)?.baseName.text == "Var"
                     || callee.as(GenericSpecializationExprSyntax.self)?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Var"
            let isValue = callee.as(DeclReferenceExprSyntax.self)?.baseName.text == "Value"
            guard isVar || isValue
            else { newBindings.append(binding); continue }

            let hasStringArg = fc.arguments.contains { arg in
                arg.label == nil && arg.expression.is(StringLiteralExprSyntax.self)
            }
            if hasStringArg { newBindings.append(binding); continue }

            let nameArg = LabeledExprSyntax(
                expression: StringLiteralExprSyntax(content: patternName)
            )
            var newArgs = fc.arguments
            if let firstArg = newArgs.first, firstArg.label?.text == "value" {
                newArgs.insert(nameArg, at: newArgs.startIndex)
            } else {
                newArgs.insert(nameArg, at: newArgs.startIndex)
            }

            let newFC = fc.with(\.arguments, newArgs)
            let newInit = initializer.with(\.value, ExprSyntax(newFC))
            let newBinding = binding.with(\.initializer, newInit)
            newBindings.append(newBinding)
            bindingsChanged = true
        }

        guard bindingsChanged else { return item }
        let newDecl = varDecl.with(\.bindings, PatternBindingListSyntax(newBindings))
        return item.with(\.item, .decl(DeclSyntax(newDecl)))
    }

    // MARK: - Code generation

    static func generateVariablesEnum(variables: [(name: String, initial: TLAValue, initialSet: StateExpr?)]) -> EnumDeclSyntax {
        EnumDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public))],
            name: "Variables",
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeListSyntax {
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "String"))
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "CaseIterable"))
                }
            },
            memberBlock: MemberBlockSyntax {
                for v in variables {
                    EnumCaseDeclSyntax { EnumCaseElementSyntax(name: .identifier(v.name)) }
                }
            }
        )
    }

    static func generateActionsEnum(actions: [(name: String, body: ActionExpr)]) -> EnumDeclSyntax {
        EnumDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public))],
            name: "Actions",
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeListSyntax {
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "String"))
                    InheritedTypeSyntax(type: IdentifierTypeSyntax(name: "CaseIterable"))
                }
            },
            memberBlock: MemberBlockSyntax {
                for a in actions {
                    EnumCaseDeclSyntax {
                        EnumCaseElementSyntax(
                            name: .identifier(a.name),
                            rawValue: InitializerClauseSyntax(value: StringLiteralExprSyntax(content: a.name))
                        )
                    }
                }
            }
        )
    }

    static func generateStateStruct(variables: [(name: String, initial: TLAValue, initialSet: StateExpr?)]) -> StructDeclSyntax {
        StructDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public))],
            name: "State",
            memberBlock: MemberBlockSyntax {
                for v in variables {
                    VariableDeclSyntax(
                        modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                        bindingSpecifier: .keyword(.var),
                        bindings: [PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(identifier: .identifier(v.name)),
                            typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: .identifier(swiftType(for: v.initial))))
                        )]
                    )
                }
                InitializerDeclSyntax(
                    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                    signature: FunctionSignatureSyntax(
                        parameterClause: FunctionParameterClauseSyntax {
                            FunctionParameterSyntax(
                                firstName: "from", secondName: "dict",
                                type: TypeSyntax(stringLiteral: "[String: TLAValue]")
                            )
                        }
                    ),
                    body: CodeBlockSyntax {
                        for v in variables {
                            ExprSyntax(stringLiteral: "self.\(v.name) = dict[Variables.\(v.name).rawValue]!.\(extractor(for: v.initial))")
                        }
                    }
                )
                VariableDeclSyntax(
                    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                    bindingSpecifier: .keyword(.var),
                    bindings: [PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: "asDictionary"),
                        typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "[String: TLAValue]")),
                        accessorBlock: AccessorBlockSyntax(accessors: .getter(
                            CodeBlockItemListSyntax {
                                DeclSyntax(stringLiteral: "var d: [String: TLAValue] = [:]")
                                for v in variables {
                                    ExprSyntax(stringLiteral: "d[Variables.\(v.name).rawValue] = \(constructor(for: v.initial, value: v.name))")
                                }
                                StmtSyntax(stringLiteral: "return d")
                            }
                        ))
                    )]
                )
            }
        )
    }

    static func generateVariableProperties(variables: [(name: String, initial: TLAValue, initialSet: StateExpr?)]) -> [VariableDeclSyntax] {
        variables.map { v in
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(v.name)),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: .identifier(swiftType(for: v.initial)))),
                    accessorBlock: AccessorBlockSyntax(accessors: .getter(
                        CodeBlockItemListSyntax { ExprSyntax(stringLiteral: "_state.\(v.name)") }
                    ))
                )]
            )
        }
    }

    func generateActionMethods(
        actions: [(name: String, body: ActionExpr)],
        collectionActions: [SpecParser.ParsedCollectionAction],
        symmetricCollections: [SpecParser.ParsedSymmetricCollection]
    ) -> [FunctionDeclSyntax] {
        let visibility = isActor ? TokenSyntax.keyword(.fileprivate) : TokenSyntax.keyword(.public)
        return actions.map { a in
            if let collectionAction = collectionActions.first(where: { $0.name == a.name }),
               let collection = symmetricCollections.first(where: { $0.name == collectionAction.collectionName }) {
                let actionNotEnabled = "SymmetricCollectionRuntimeError.actionNotEnabled(collection: \"\(collection.name)\", action: \"\(a.name)\")"
                let liveBranches = collectionAction.runtimeBranches.map { branch in
                    let condition = branch.guardExpressions.isEmpty
                        ? "true"
                        : branch.guardExpressions.map { "(\($0))" }.joined(separator: " && ")
                    let update = branch.updateExpression.map {
                        "try \(collection.name).update(id: id, action: \"\(a.name)\") { entry in \($0) }"
                    } ?? ""
                    return """
                    if \(condition) {
                        \(update)
                        return
                    }
                    """
                }.joined(separator: "\n")
                let source = """
                \(isActor ? "fileprivate" : "public mutating") func \(a.name)(id: \(collection.elementType).ID) throws {
                    let entry = try \(collection.name).entry(for: id, action: "\(a.name)")
                    \(liveBranches)
                    throw \(actionNotEnabled)
                }
                """
                return DeclSyntax(stringLiteral: source).as(FunctionDeclSyntax.self)!
            }
            return FunctionDeclSyntax(
                modifiers: isActor
                    ? [DeclModifierSyntax(name: visibility)]
                    : [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.mutating))],
                name: isActor ? .identifier(a.name) : .identifier("apply\(a.name)"),
                signature: FunctionSignatureSyntax(parameterClause: FunctionParameterClauseSyntax(parameters: [])),
                body: CodeBlockSyntax { ExprSyntax(stringLiteral: "_state = _apply(.\(a.name))") }
            )
        }
    }

    func generateCollectionRuntimeMembers(
        _ collections: [SpecParser.ParsedSymmetricCollection]
    ) -> [DeclSyntax] {
        var declarations = collections.map { collection in
            DeclSyntax(stringLiteral: """
            public var \(collection.name) = IdentifiedModelCollection<\(collection.elementType), \(collection.valueType)>(
                name: \"\(collection.name)\",
                verificationScope: \(collection.verificationScope),
                initial: \(Self.literalExpr(for: collection.declaration.initial))
            )
            """)
        }
        guard !collections.isEmpty else { return declarations }
        let scopes = collections.map {
            "SymmetricCollectionScope(collectionName: \"\($0.name)\", verificationScope: \($0.verificationScope))"
        }.joined(separator: ", ")
        declarations.append(DeclSyntax(stringLiteral: """
        public static let symmetricCollectionScopes: [SymmetricCollectionScope] = [\(scopes)]
        """))
        return declarations
    }

    func generateApplyHelper(
        symmetricCollections: [SpecParser.ParsedSymmetricCollection] = []
    ) -> FunctionDeclSyntax {
        if symmetricCollections.isEmpty {
            return FunctionDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.private))],
                name: "_apply",
                signature: FunctionSignatureSyntax(
                    parameterClause: FunctionParameterClauseSyntax {
                        FunctionParameterSyntax(
                            firstName: "_", secondName: "action",
                            type: IdentifierTypeSyntax(name: "Actions")
                        )
                    },
                    returnClause: ReturnClauseSyntax(type: IdentifierTypeSyntax(name: "State"))
                ),
                body: CodeBlockSyntax {
                    ExprSyntax(stringLiteral: """
                    guard let next = try? Self.runtime.apply(
                        actionName: action.rawValue,
                        to: _state.asDictionary
                    ) else { return _state }
                    """)
                    StmtSyntax(stringLiteral: "return State(from: next)")
                }
            )
        }
        let liveStateProjection = symmetricCollections.map { collection in
            """
            liveState[Variables.\(collection.name).rawValue] = \(collection.name).projectedModelValue(
                preserving: boundedState[Variables.\(collection.name).rawValue]!.functionValue.keys.sorted()
            )
            """
        }.joined(separator: "\n")
        let boundedStateRestoration = symmetricCollections.map { collection in
            "next[Variables.\(collection.name).rawValue] = boundedState[Variables.\(collection.name).rawValue]"
        }.joined(separator: "\n")
        return FunctionDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.private))],
            name: "_apply",
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax {
                    FunctionParameterSyntax(
                        firstName: "_", secondName: "action",
                        type: IdentifierTypeSyntax(name: "Actions")
                    )
                },
                returnClause: ReturnClauseSyntax(type: IdentifierTypeSyntax(name: "State"))
            ),
            body: CodeBlockSyntax {
                ExprSyntax(stringLiteral: """
                let boundedState = _state.asDictionary
                var liveState = boundedState
                \(liveStateProjection)
                guard var next = try? Self.runtime.apply(
                    actionName: action.rawValue,
                    to: liveState
                ) else { return _state }
                \(boundedStateRestoration)
                """)
                StmtSyntax(stringLiteral: "return State(from: next)")
            }
        )
    }

    // MARK: - Observable code generation

    func generateObservableMembers(
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?)],
        actions: [(name: String, body: ActionExpr)]
    ) -> [DeclSyntax] {
        var decls: [DeclSyntax] = []

        for v in variables {
            let storedVar: DeclSyntax = DeclSyntax(
                VariableDeclSyntax(
                    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                    bindingSpecifier: .keyword(.var),
                    bindings: [PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier(v.name)),
                        typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: .identifier(Self.swiftType(for: v.initial)))),
                        initializer: InitializerClauseSyntax(value: ExprSyntax(stringLiteral: Self.literalExpr(for: v.initial)))
                    )]
                )
            )
            decls.append(storedVar)
        }

        for a in actions {
            let callbackName = "on" + a.0.dropFirst().prefix(1).capitalized + a.0.dropFirst(2)
            let callbackVar: DeclSyntax = DeclSyntax(
                VariableDeclSyntax(
                    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                    bindingSpecifier: .keyword(.var),
                    bindings: [PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier(callbackName)),
                        typeAnnotation: TypeAnnotationSyntax(type: TypeSyntax(stringLiteral: "((State, State) async -> Void)?"))
                    )]
                )
            )
            decls.append(callbackVar)
        }

        decls.append(DeclSyntax(
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.private))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: "_state"),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: "State")),
                    initializer: InitializerClauseSyntax(value: ExprSyntax(stringLiteral: "State(from: runtime.initialStates().first!)"))
                )]
            )
        ))

        decls.append(DeclSyntax(Self.generateVariablesEnum(variables: variables)))
        decls.append(DeclSyntax(Self.generateActionsEnum(actions: actions)))
        decls.append(DeclSyntax(Self.generateStateStruct(variables: variables)))
        decls.append(contentsOf: generateObservableActionMethods(variables: variables, actions: actions).map(DeclSyntax.init))
        decls.append(DeclSyntax(generateApplyHelper()))
        decls.append(DeclSyntax(
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.static))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: "runtime"),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: "SpecRuntime")),
                    accessorBlock: AccessorBlockSyntax(accessors: .getter(
                        CodeBlockItemListSyntax { ExprSyntax(stringLiteral: "SpecRuntime(spec: spec)") }
                    ))
                )]
            )
        ))

        return decls
    }

    func generateObservableActionMethods(
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?)],
        actions: [(name: String, body: ActionExpr)]
    ) -> [FunctionDeclSyntax] {
        actions.map { a in
            let callbackName = "on" + a.0.dropFirst().prefix(1).capitalized + a.0.dropFirst(2)
            var bodyExprs: [ExprSyntax] = [
                ExprSyntax(stringLiteral: "let from = _state"),
                ExprSyntax(stringLiteral: "_state = _apply(.\(a.0))")
            ]
            for v in variables {
                bodyExprs.append(ExprSyntax(stringLiteral: "\(v.name) = _state.\(v.name)"))
            }
            bodyExprs.append(ExprSyntax(stringLiteral: "Task { await \(callbackName)?(from, _state) }"))
            return FunctionDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                name: .identifier(a.0),
                signature: FunctionSignatureSyntax(parameterClause: FunctionParameterClauseSyntax(parameters: [])),
                body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(bodyExprs.map {
                    CodeBlockItemSyntax(item: .expr($0))
                }))
            )
        }
    }

    static func literalExpr(for initial: TLAValue) -> String {
        switch initial {
        case .int(let v): "\(v)"
        case .bool(let v): "\(v)"
        case .string(let v): "\"\(v)\""
        case .set(let v): "[\(v.map(String.init).joined(separator: ", "))]"
        default: "0"
        }
    }

    func generateCallbackProtocol(typeName: String, actions: [(String, ActionExpr)]) throws -> [DeclSyntax] {
        let protoName = "\(typeName)Actions"
        var callbackDecls: [String] = []
        var defaultDecls: [String] = []

        for a in actions {
            let callbackName = "on" + a.0.dropFirst().prefix(1).capitalized + a.0.dropFirst(2)
            callbackDecls.append("func \(callbackName)()")
            defaultDecls.append("""
                func \(callbackName)() {
                    runtimeWarning("\(typeName).\(callbackName)() not overridden")
                }
                """)
        }

        let protoCode = """
            protocol \(protoName) {
                \(callbackDecls.joined(separator: "\n    "))
            }
            """
        let extCode = """
            extension \(protoName) {
                \(defaultDecls.joined(separator: "\n    "))
            }
            """

        let conformanceCode = """
            extension \(typeName): \(protoName) {}
            """

        return [
            DeclSyntax(stringLiteral: protoCode),
            DeclSyntax(stringLiteral: extCode),
            DeclSyntax(stringLiteral: conformanceCode)
        ]
    }

    // MARK: - Helpers

    static func findSpec(in members: MemberBlockItemListSyntax) -> ClosureExprSyntax? {
        for member in members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = varDecl.bindings.first,
                  binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "spec"
            else { continue }

            if let closure = binding.accessorBlock?.accessors.as(CodeBlockItemListSyntax.self) {
                for stmt in closure {
                    if case .expr(let e) = stmt.item,
                       let fc = e.as(FunctionCallExprSyntax.self),
                       fc.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "TLASpec" {
                        return fc.trailingClosure ?? fc.arguments.last?.expression.as(ClosureExprSyntax.self)
                    }
                }
            }
            if let accessors = binding.accessorBlock?.accessors.as(AccessorDeclListSyntax.self) {
                for acc in accessors where acc.accessorSpecifier.tokenKind == .keyword(.get) {
                    for stmt in acc.body?.statements ?? [] {
                        if case .expr(let e) = stmt.item,
                           let fc = e.as(FunctionCallExprSyntax.self),
                           fc.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "TLASpec" {
                            return fc.trailingClosure ?? fc.arguments.last?.expression.as(ClosureExprSyntax.self)
                        }
                    }
                }
            }
        }
        return nil
    }

    /// Collect `enum Foo: Int { case a, b = 5, c }` → `["a": 0, "b": 5, "c": 6]`.
    /// Also handles `enum Foo: String` where case names ARE the raw values.
    static func collectEnumPhases(from members: MemberBlockItemListSyntax) -> [String: Int] {
        var result: [String: Int] = [:]
        for member in members {
            guard let enumDecl = member.decl.as(EnumDeclSyntax.self) else { continue }
            guard let inheritance = enumDecl.inheritanceClause,
                  inheritance.inheritedTypes.count == 1,
                  inheritance.inheritedTypes.first?.type.as(IdentifierTypeSyntax.self)?.name.text == "Int"
            else { continue }

            var idx = 0
            for caseMember in enumDecl.memberBlock.members {
                guard let caseDecl = caseMember.decl.as(EnumCaseDeclSyntax.self) else { continue }
                for element in caseDecl.elements {
                    if let raw = element.rawValue?.value.as(IntegerLiteralExprSyntax.self),
                       let val = Int(raw.literal.text) {
                        result[element.name.text] = val
                        idx = val + 1
                    } else {
                        result[element.name.text] = idx
                        idx += 1
                    }
                }
            }
        }
        return result
    }

    static func swiftType(for initial: TLAValue) -> String {
        switch initial {
        case .int: "Int"; case .bool: "Bool"; case .string: "String"
        case .set: "Set<Int>"; case .tuple: "[TLAValue]"
        case .record: "[String: TLAValue]"; case .function: "[TLAValue: TLAValue]"
        case .constant: "String"
        }
    }

    static func extractor(for initial: TLAValue) -> String {
        switch initial {
        case .int: "intValue"; case .bool: "boolValue"; case .string: "stringValue"
        case .set: "intSetValue"; case .tuple: "tupleValue"
        case .record: "recordValue"; case .function: "functionValue"
        case .constant: "stringValue"
        }
    }

    static func constructor(for initial: TLAValue, value: String) -> String {
        switch initial {
        case .int: ".int(\(value))"; case .bool: ".bool(\(value))"; case .string: ".string(\(value))"
        case .set: ".set(Set(\(value).map { .int($0) }))"; case .tuple: ".tuple(\(value))"
        case .record: ".record(\(value))"; case .function: ".function(\(value))"
        case .constant: ".constant(\(value))"
        }
    }
}

struct SimpleError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Macros

public struct ModelMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                  providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                  in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard let ext = ("""
            extension \(type.trimmed): TLAModelType {}
            """ as DeclSyntax).as(ExtensionDeclSyntax.self) else { return [] }
        return [ext]
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                  in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let expander = MacroExpander(isActor: false)
        let parsed: ParsedMacroModel
        do {
            parsed = try expander.parseAndVerify(declaration)
        } catch let diagnostic as SpecParser.SymmetricCollectionParseDiagnostic {
            context.diagnose(parserDiagnostic(diagnostic, in: declaration))
            return []
        }
        return expander.generateMembers(
            variables: parsed.variables,
            actions: parsed.actions,
            symmetricCollections: parsed.symmetricCollections,
            collectionActions: parsed.collectionActions
        )
    }
}

public struct TLAActorMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax,
                                  providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax],
                                  in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard let ext = ("""
            extension \(type.trimmed): TLAModelType {}
            """ as DeclSyntax).as(ExtensionDeclSyntax.self) else { return [] }
        return [ext]
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                  in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let expander = MacroExpander(isActor: true)
        let parsed: ParsedMacroModel
        do {
            parsed = try expander.parseAndVerify(declaration)
        } catch let diagnostic as SpecParser.SymmetricCollectionParseDiagnostic {
            context.diagnose(parserDiagnostic(diagnostic, in: declaration))
            return []
        }
        return expander.generateMembers(
            variables: parsed.variables,
            actions: parsed.actions,
            symmetricCollections: parsed.symmetricCollections,
            collectionActions: parsed.collectionActions
        )
    }
}

public struct TLAObservableMacro: MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                  in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let expander = MacroExpander(isActor: false)
        let parsed: ParsedMacroModel
        do {
            parsed = try expander.parseAndVerify(declaration)
        } catch let diagnostic as SpecParser.SymmetricCollectionParseDiagnostic {
            context.diagnose(parserDiagnostic(diagnostic, in: declaration))
            return []
        }
        return expander.generateObservableMembers(variables: parsed.variables, actions: parsed.actions)
    }
}

private struct ParserDiagnosticMessage: DiagnosticMessage {
    let message: String
    let diagnosticID = MessageID(domain: "SwiftTLA", id: "unsupported-spec-expression")
    let severity: DiagnosticSeverity = .error
}

private func parserDiagnostic(
    _ diagnostic: SpecParser.SymmetricCollectionParseDiagnostic,
    in declaration: some DeclGroupSyntax
) -> Diagnostic {
    let finder = ParserDiagnosticNodeFinder(
        source: diagnostic.source,
        offset: diagnostic.sourceOffset
    )
    finder.walk(Syntax(declaration))
    return Diagnostic(
        node: finder.node ?? Syntax(declaration),
        message: ParserDiagnosticMessage(message: diagnostic.message)
    )
}

private final class ParserDiagnosticNodeFinder: SyntaxAnyVisitor {
    let source: String
    let offset: Int?
    var node: Syntax?

    init(source: String, offset: Int?) {
        self.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        self.offset = offset
        super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ candidate: Syntax) -> SyntaxVisitorContinueKind {
        guard node == nil else { return .skipChildren }
        let matchesOffset = offset.map {
            candidate.positionAfterSkippingLeadingTrivia.utf8Offset == $0
        } ?? false
        let matchesSource = candidate.description.trimmingCharacters(in: .whitespacesAndNewlines) == source
        if matchesOffset && matchesSource {
            node = candidate
            return .skipChildren
        }
        return .visitChildren
    }
}
