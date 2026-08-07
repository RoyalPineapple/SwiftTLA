import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA

// MARK: - Shared parsing and verification

struct MacroExpander {
    let isActor: Bool

    func parseAndVerify(_ declaration: some DeclGroupSyntax) throws -> (
        typeName: String, variables: [(String, TLAValue, StateExpr?)], actions: [(String, ActionExpr)]
    ) {
        let typeName: String
        let memberList: MemberBlockItemListSyntax

        if isActor, let a = declaration.as(ActorDeclSyntax.self) {
            typeName = a.name.text; memberList = a.memberBlock.members
        } else if let s = declaration.as(StructDeclSyntax.self) {
            typeName = s.name.text; memberList = s.memberBlock.members
        } else {
            throw SimpleError(isActor ? "@TLAActor on actors only" : "@TLAModel on structs only")
        }

        guard let closure = Self.findSpec(in: memberList) else {
            throw SimpleError("Could not find 'TLASpec' builder in '\(typeName)'")
        }

        let rewritten = rewriteVarNames(in: closure)
        let parsed = SpecParser.parseSpecClosure(rewritten)
        if parsed.variables.isEmpty { throw SimpleError("No variables in spec") }

        let spec = TLASpec(
            name: typeName,
            variables: parsed.variables.map { NamedVar(name: $0.name, initial: $0.initial, initialSet: $0.initialSet) },
            constants: parsed.constants,
            actions: parsed.actions.map { NamedAction(name: $0.name, body: $0.body) },
            invariants: parsed.invariants.map { NamedInvariant(name: $0.name, body: $0.body) },
            temporalProperties: parsed.temporal.map { NamedTemporal(name: $0.name, expr: $0.expr) },
            fairness: parsed.fairness
        )

        let result = try ModelChecker(spec: spec, maxStates: 10_000).check()
        switch result {
        case .invariantViolated(let inv, _, let trace):
            throw SimpleError("Invariant '\(inv)' violated:\n\(trace.map(String.init(describing:)).joined(separator: "\n"))")
        case .error(let msg): throw SimpleError("Checker error: \(msg)")
        case .deadlocked(let s): throw SimpleError("Deadlock at: \(s)")
        case .depthExceeded(let c, let l): throw SimpleError("Depth exceeded: \(c)/\(l)")
        case .livenessViolated(let msg): throw SimpleError("Liveness violated: \(msg)")
        case .ok: break
        }

        return (typeName, parsed.variables, parsed.actions)
    }

    func generateMembers(
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?)],
        actions: [(name: String, body: ActionExpr)]
    ) -> [DeclSyntax] {
        var decls: [DeclSyntax] = []

        decls.append(DeclSyntax(
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.private))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: "_state"),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: "State")),
                    initializer: InitializerClauseSyntax(value: ExprSyntax(stringLiteral: "State(from: Self.runtime.initialStates().first!)"))
                )]
            )
        ))

        decls.append(DeclSyntax(Self.generateVariablesEnum(variables: variables)))
        decls.append(DeclSyntax(Self.generateActionsEnum(actions: actions)))
        decls.append(DeclSyntax(Self.generateStateStruct(variables: variables)))
        decls.append(contentsOf: Self.generateVariableProperties(variables: variables).map(DeclSyntax.init))
        decls.append(contentsOf: generateActionMethods(actions: actions).map(DeclSyntax.init))
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
            guard callee.as(DeclReferenceExprSyntax.self)?.baseName.text == "Var"
               || callee.as(GenericSpecializationExprSyntax.self)?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Var"
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

    func generateActionMethods(actions: [(name: String, body: ActionExpr)]) -> [FunctionDeclSyntax] {
        actions.map { a in
            FunctionDeclSyntax(
                modifiers: isActor
                    ? [DeclModifierSyntax(name: .keyword(.public))]
                    : [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.mutating))],
                name: isActor ? .identifier(a.name) : .identifier("apply\(a.name)"),
                signature: FunctionSignatureSyntax(parameterClause: FunctionParameterClauseSyntax(parameters: [])),
                body: CodeBlockSyntax { ExprSyntax(stringLiteral: "_state = _apply(.\(a.name))") }
            )
        }
    }

    func generateApplyHelper() -> FunctionDeclSyntax {
        FunctionDeclSyntax(
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
                ExprSyntax(stringLiteral: "let next = try! Self.runtime.apply(actionName: action.rawValue, to: _state.asDictionary)")
                StmtSyntax(stringLiteral: "return State(from: next)")
            }
        )
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
        let parsed = try expander.parseAndVerify(declaration)
        return expander.generateMembers(variables: parsed.variables, actions: parsed.actions)
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
        let parsed = try expander.parseAndVerify(declaration)
        return expander.generateMembers(variables: parsed.variables, actions: parsed.actions)
    }
}
