import SwiftCompilerPlugin
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA

// MARK: - Shared parsing and verification

struct ParsedEnumInfo {
    let typeName: String
    let cases: [(name: String, value: TLAValue)]
    init(typeName: String, cases: [(String, TLAValue)]) {
        self.typeName = typeName
        self.cases = cases
    }
    var domain: Set<TLAValue> { Set(cases.map(\.value)) }
}

struct ParsedMacroModel {
    let typeName: String
    let variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)]
    let actions: [(String, ActionExpr)]
    let symmetricCollections: [SpecParser.ParsedSymmetricCollection]
    let collectionActions: [SpecParser.ParsedCollectionAction]
    let enumInfos: [ParsedEnumInfo]
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

        let collectionVarTypes = Self.collectCollectionVarTypes(in: closure)
        let enrichedVariables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)] = parsed.variables.map { v in
            let swiftType = collectionVarTypes[v.name] ?? v.swiftTypeName
            return (v.name, v.initial, v.initialSet, swiftType)
        }

        let enumInfos = Self.collectEnumStateVars(from: memberList)

        var allInvariants = parsed.invariants.map { NamedInvariant(name: $0.name, body: $0.body) }
        for variable in enrichedVariables {
            if let swiftTypeName = variable.swiftTypeName,
               let enumInfo = enumInfos.first(where: { $0.typeName == swiftTypeName }) {
                let domainValues = TLAValue.sorted(enumInfo.domain)
                let invariantName = "\(variable.name)InDomain"
                let body = StateExpr.in(.variable(variable.name),
                                         .setLiteral(domainValues.map { .value($0) }))
                allInvariants.append(NamedInvariant(name: invariantName, body: body))
            }
        }

        let spec = TLASpec(
            name: typeName,
            variables: enrichedVariables.map { NamedVar(name: $0.name, initial: $0.initial, initialSet: $0.initialSet) },
            constants: parsed.constants,
            actions: parsed.actions.map { NamedAction(name: $0.name, body: $0.body) },
            invariants: allInvariants,
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
            variables: enrichedVariables,
            actions: parsed.actions,
            symmetricCollections: parsed.symmetricCollections,
            collectionActions: parsed.collectionActions,
            enumInfos: enumInfos
        )
    }

    func generateMembers(
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        actions: [(name: String, body: ActionExpr)],
        symmetricCollections: [SpecParser.ParsedSymmetricCollection] = [],
        collectionActions: [SpecParser.ParsedCollectionAction] = [],
        enumInfos: [ParsedEnumInfo] = []
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
            let baseName = callee.as(DeclReferenceExprSyntax.self)?.baseName.text
                ?? callee.as(GenericSpecializationExprSyntax.self)?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text
            let isVar = baseName == "Var"
            let isValue = baseName == "Value"
            let isStateVar = baseName == "StateVar"
            let isArrayVar = baseName == "ArrayVar"
            let isSetVar = baseName == "SetVar"
            let isDictVar = baseName == "DictionaryVar"

            if isStateVar {
                if let firstArg = fc.arguments.first,
                   let label = firstArg.label?.text,
                   label == "in" || label == "values" {
                    let hasNameArg = fc.arguments.contains { $0.label?.text == "name" }
                    if hasNameArg { newBindings.append(binding); continue }

                    var newArgs = fc.arguments
                    newArgs.append(LabeledExprSyntax(
                        label: "name",
                        colon: .colonToken(),
                        expression: StringLiteralExprSyntax(content: patternName)
                    ))
                    let newFC = fc.with(\.arguments, newArgs)
                    let newInit = initializer.with(\.value, ExprSyntax(newFC))
                    let newBinding = binding.with(\.initializer, newInit)
                    newBindings.append(newBinding)
                    bindingsChanged = true
                } else {
                    let hasStringArg = fc.arguments.contains { arg in
                        arg.label == nil && arg.expression.is(StringLiteralExprSyntax.self)
                    }
                    if hasStringArg { newBindings.append(binding); continue }

                    var newArgs = fc.arguments
                    newArgs.insert(LabeledExprSyntax(
                        expression: StringLiteralExprSyntax(content: patternName)
                    ), at: newArgs.startIndex)
                    let newFC = fc.with(\.arguments, newArgs)
                    let newInit = initializer.with(\.value, ExprSyntax(newFC))
                    let newBinding = binding.with(\.initializer, newInit)
                    newBindings.append(newBinding)
                    bindingsChanged = true
                }
                continue
            }

            guard isVar || isValue || isArrayVar || isSetVar || isDictVar
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

    static func generateVariablesEnum(variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)]) -> EnumDeclSyntax {
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

    static func generateStateStruct(variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)]) -> StructDeclSyntax {
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
                            typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: .identifier(v.swiftTypeName ?? swiftType(for: v.initial))))
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
                            if let typeName = v.swiftTypeName, needsBridgeInit(typeName) {
                                ExprSyntax(stringLiteral: Self.bridgedInitExpr(variable: v))
                            } else if let typeName = v.swiftTypeName {
                                ExprSyntax(stringLiteral: "self.\(v.name) = \(typeName)(rawValue: dict[Variables.\(v.name).rawValue]!.\(extractor(for: v.initial)))!")
                            } else {
                                ExprSyntax(stringLiteral: "self.\(v.name) = dict[Variables.\(v.name).rawValue]!.\(extractor(for: v.initial))")
                            }
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
                                    if let typeName = v.swiftTypeName, needsBridgeInit(typeName) {
                                        ExprSyntax(stringLiteral: Self.bridgedAsDictExpr(variable: v))
                                    } else {
                                        ExprSyntax(stringLiteral: "d[Variables.\(v.name).rawValue] = \(constructor(for: v.initial, value: v.name))")
                                    }
                                }
                                StmtSyntax(stringLiteral: "return d")
                            }
                        ))
                    )]
                )
            }
        )
    }

    static func generateVariableProperties(variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)]) -> [VariableDeclSyntax] {
        variables.map { v in
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(v.name)),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: .identifier(v.swiftTypeName ?? swiftType(for: v.initial)))),
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
            FunctionDeclSyntax(
                modifiers: isActor
                    ? [DeclModifierSyntax(name: visibility)]
                    : [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.mutating))],
                name: isActor ? .identifier("\(a.0)") : .identifier("apply\(a.0)"),
                signature: FunctionSignatureSyntax(parameterClause: FunctionParameterClauseSyntax(parameters: [])),
                body: CodeBlockSyntax { ExprSyntax(stringLiteral: "_state = _apply(.\(a.0))") }
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
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        actions: [(name: String, body: ActionExpr)]
    ) -> [DeclSyntax] {
        var decls: [DeclSyntax] = []

        for v in variables {
            let typeStr = v.swiftTypeName ?? Self.swiftType(for: v.initial)
            let initStr: String
            if let typeName = v.swiftTypeName, Self.needsBridgeInit(typeName) {
                initStr = Self.collectionDefaultValue(for: typeName)
            } else if v.swiftTypeName != nil {
                initStr = "\(typeStr)(rawValue: \(Self.literalExpr(for: v.initial)))!"
            } else {
                initStr = Self.literalExpr(for: v.initial)
            }
            let storedVar = DeclSyntax(
                VariableDeclSyntax(
                    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                    bindingSpecifier: .keyword(.var),
                    bindings: [PatternBindingSyntax(
                        pattern: IdentifierPatternSyntax(identifier: .identifier(v.name)),
                        typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: .identifier(typeStr))),
                        initializer: InitializerClauseSyntax(value: ExprSyntax(stringLiteral: initStr))
                    )]
                )
            )
            decls.append(storedVar)
        }

        for a in actions {
            let callbackName = "on" + a.0.prefix(1).capitalized + a.0.dropFirst()
            let callbackVar = DeclSyntax(
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
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)],
        actions: [(name: String, body: ActionExpr)]
    ) -> [FunctionDeclSyntax] {
        actions.map { a in
            let callbackName = "on" + a.0.prefix(1).capitalized + a.0.dropFirst()
            var bodyExprs: [ExprSyntax] = [
                ExprSyntax(stringLiteral: "let from = _state"),
                ExprSyntax(stringLiteral: "_state = _apply(.\(a.0))")
            ]
            for v in variables {
                bodyExprs.append(ExprSyntax(stringLiteral: "\(v.name) = _state.\(v.name)"))
            }
            bodyExprs.append(ExprSyntax(stringLiteral: "if let h = \(callbackName) { Task { await h(from, _state) } }"))
            return FunctionDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                name: .identifier("_\(a.0)"),
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
            let callbackName = "on" + a.0.prefix(1).capitalized + a.0.dropFirst()
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

    // MARK: - Collection var type detection

    /// Walks the spec closure AST and extracts Swift type information
    /// from ArrayVar<T>, SetVar<T>, DictionaryVar<K,V> declarations.
    /// Returns a mapping from variable name to Swift type string.
    static func collectCollectionVarTypes(in closure: ClosureExprSyntax) -> [String: String] {
        var typeMap: [String: String] = [:]
        for statement in closure.statements {
            guard case .decl(let decl) = statement.item,
                  let varDecl = decl.as(VariableDeclSyntax.self)
            else { continue }

            for binding in varDecl.bindings {
                guard let patternName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let initializer = binding.initializer?.value,
                      let fc = initializer.as(FunctionCallExprSyntax.self),
                      let genSpec = fc.calledExpression.as(GenericSpecializationExprSyntax.self),
                      let baseName = genSpec.expression.as(DeclReferenceExprSyntax.self)?.baseName.text
                else { continue }

                let genericArgs = Array(genSpec.genericArgumentClause.arguments)

                switch baseName {
                case "ArrayVar":
                    guard let firstArg = genericArgs.first else { continue }
                    typeMap[patternName] = "[\(firstArg.argument.description.trimmingCharacters(in: .whitespacesAndNewlines))]"
                case "SetVar":
                    guard let firstArg = genericArgs.first else { continue }
                    typeMap[patternName] = "Set<\(firstArg.argument.description.trimmingCharacters(in: .whitespacesAndNewlines))>"
                case "DictionaryVar":
                    guard genericArgs.count >= 2 else { continue }
                    let key = genericArgs[0].argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = genericArgs[1].argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
                    typeMap[patternName] = "[\(key): \(value)]"
                default:
                    break
                }
            }
        }
        return typeMap
    }

    /// Returns true if the swiftTypeName represents a collection type that needs
    /// TLABridgeable-based conversion (not an enum/concrete type).
    static func needsBridgeInit(_ typeName: String) -> Bool {
        typeName.hasPrefix("[") || typeName.hasPrefix("Set<")
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

    /// Collect enums conforming to `TLAValueType` + `CaseIterable` with their case names and raw values.
    static func collectEnumStateVars(from members: MemberBlockItemListSyntax) -> [ParsedEnumInfo] {
        var result: [ParsedEnumInfo] = []
        for member in members {
            guard let enumDecl = member.decl.as(EnumDeclSyntax.self) else { continue }
            guard let inheritance = enumDecl.inheritanceClause else { continue }

            let inheritedNames = inheritance.inheritedTypes.compactMap {
                $0.type.as(IdentifierTypeSyntax.self)?.name.text
            }

            guard inheritedNames.contains("TLAValueType") else { continue }

            let intBacked = inheritedNames.contains("Int")
            let stringBacked = inheritedNames.contains("String")
            guard intBacked || stringBacked else { continue }

            var cases: [(name: String, value: TLAValue)] = []
            var idx = 0
            for caseMember in enumDecl.memberBlock.members {
                guard let caseDecl = caseMember.decl.as(EnumCaseDeclSyntax.self) else { continue }
                for element in caseDecl.elements {
                    let value: TLAValue
                    if let raw = element.rawValue?.value.as(IntegerLiteralExprSyntax.self),
                       let val = Int(raw.literal.text) {
                        value = .int(val)
                        idx = val + 1
                    } else if let raw = element.rawValue?.value.as(StringLiteralExprSyntax.self) {
                        value = .string(raw.representedLiteralValue ?? raw.segments.description)
                    } else if intBacked {
                        value = .int(idx)
                        idx += 1
                    } else {
                        value = .string(element.name.text)
                    }
                    cases.append((element.name.text, value))
                }
            }

            result.append(ParsedEnumInfo(
                typeName: enumDecl.name.text,
                cases: cases
            ))
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

    /// Generates the init-from-dict expression for a collection-typed variable
    /// backed by ArrayVar or SetVar. Uses TLABridgeable for element conversion.
    static func bridgedInitExpr(variable v: (name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)) -> String {
        guard let swiftType = v.swiftTypeName else {
            return "self.\(v.name) = dict[Variables.\(v.name).rawValue]!.\(extractor(for: v.initial))"
        }
        let key = "dict[Variables.\(v.name).rawValue]"
        if swiftType.hasPrefix("[") {
            let inner = String(swiftType.dropFirst().dropLast())
            return "self.\(v.name) = (\(key)?.tupleValue ?? []).compactMap { \(inner)(tlaValue: $0) }"
        }
        if swiftType.hasPrefix("Set<") {
            let inner = String(swiftType.dropFirst(4).dropLast())
            return "self.\(v.name) = { var s = Set<\(inner)>(); for e in \(key)?.setValue ?? [] { s.insert(\(inner)(tlaValue: e)) }; return s }()"
        }
        return "self.\(v.name) = dict[Variables.\(v.name).rawValue]!.\(extractor(for: v.initial))"
    }

    /// Generates the as-dictionary expression for a collection-typed variable.
    static func bridgedAsDictExpr(variable v: (name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)) -> String {
        guard let swiftType = v.swiftTypeName else {
            return "d[Variables.\(v.name).rawValue] = \(constructor(for: v.initial, value: v.name))"
        }
        let key = "Variables.\(v.name).rawValue"
        if swiftType.hasPrefix("[") {
            return "d[\(key)] = .tuple(\(v.name).map(\\.tlaValue))"
        }
        if swiftType.hasPrefix("Set<") {
            return "d[\(key)] = { var s = Set<TLAValue>(); for e in \(v.name) { s.insert(e.tlaValue) }; return .set(s) }()"
        }
        return "d[\(key)] = \(constructor(for: v.initial, value: v.name))"
    }

    /// Returns an empty-collection default literal for a collection Swift type.
    static func collectionDefaultValue(for swiftType: String) -> String {
        if swiftType.hasPrefix("[") && swiftType.contains(":") { return "[:]" }
        if swiftType.hasPrefix("[") { return "[]" }
        if swiftType.hasPrefix("Set<") { return "[]" }
        return "[]"
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
            collectionActions: parsed.collectionActions,
            enumInfos: parsed.enumInfos
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
            collectionActions: parsed.collectionActions,
            enumInfos: parsed.enumInfos
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
