import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA

public struct ModelMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let ext = ("""
            extension \(type.trimmed): TLAModelType {}
            """ as DeclSyntax).as(ExtensionDeclSyntax.self) else { return [] }
        return [ext]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw SimpleError("@TLAModel on structs only")
        }
        let typeName = structDecl.name.text

        guard let closure = findSpecClosure(in: structDecl.memberBlock.members) else {
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

        return generateMembers(variables: parsed.variables, actions: parsed.actions)
    }

    static func generateMembers(
        variables: [(name: String, initial: TLAValue, initialSet: StateExpr?)],
        actions: [(name: String, body: ActionExpr)]
    ) -> [DeclSyntax] {
        var decls: [DeclSyntax] = []

        // _state field
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

        // Variables enum
        decls.append(DeclSyntax(generateVariablesEnum(variables: variables)))
        // Actions enum
        decls.append(DeclSyntax(generateActionsEnum(actions: actions)))
        // State struct
        decls.append(DeclSyntax(generateStateStruct(variables: variables)))
        // Variable properties
        decls.append(contentsOf: generateVariableProperties(variables: variables).map(DeclSyntax.init))
        // Action methods
        decls.append(contentsOf: generateActionMethods(actions: actions).map(DeclSyntax.init))
        // _apply helper
        decls.append(DeclSyntax(generateApplyHelper()))
        // runtime accessor
        decls.append(DeclSyntax(
            VariableDeclSyntax(
                modifiers: [DeclModifierSyntax(name: .keyword(.public)), DeclModifierSyntax(name: .keyword(.static))],
                bindingSpecifier: .keyword(.var),
                bindings: [PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: "runtime"),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: "SpecRuntime")),
                    accessorBlock: AccessorBlockSyntax(accessors: .getter([
                        "SpecRuntime(spec: spec)"
                    ]))
                )]
            )
        ))

        return decls
    }

    private static func findSpecClosure(in members: MemberBlockItemListSyntax) -> ClosureExprSyntax? {
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
                        return (fc.trailingClosure ?? fc.arguments.last?.expression.as(ClosureExprSyntax.self))
                    }
                }
            }
            if let accessors = binding.accessorBlock?.accessors.as(AccessorDeclListSyntax.self) {
                for acc in accessors where acc.accessorSpecifier.tokenKind == .keyword(.get) {
                    for stmt in acc.body?.statements ?? [] {
                        if case .expr(let e) = stmt.item,
                           let fc = e.as(FunctionCallExprSyntax.self),
                           fc.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "TLASpec" {
                            return (fc.trailingClosure ?? fc.arguments.last?.expression.as(ClosureExprSyntax.self))
                        }
                    }
                }
            }
        }
        return nil
    }

    struct SimpleError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    // MARK: - Var name injection

    static func rewriteVarNames(in closure: ClosureExprSyntax) -> ClosureExprSyntax {
        var newStatements: [CodeBlockItemSyntax] = []
        for item in closure.statements {
            newStatements.append(rewriteVarBinding(in: item))
        }
        return closure.with(\.statements, CodeBlockItemListSyntax(newStatements))
    }

    private static func rewriteVarBinding(in item: CodeBlockItemSyntax) -> CodeBlockItemSyntax {
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

    // MARK: - Type mapping

    static func swiftType(for initial: TLAValue) -> String {
        switch initial {
        case .int:     return "Int"
        case .bool:    return "Bool"
        case .string:  return "String"
        case .set:     return "Set<Int>"
        case .tuple:   return "[TLAValue]"
        case .record:  return "[String: TLAValue]"
        case .function: return "[TLAValue: TLAValue]"
        case .constant: return "String"
        }
    }

    static func tlaValueExtractor(for initial: TLAValue) -> String {
        switch initial {
        case .int:     return "intValue"
        case .bool:    return "boolValue"
        case .string:  return "stringValue"
        case .set:     return "intSetValue"
        case .tuple:   return "tupleValue"
        case .record:  return "recordValue"
        case .function: return "functionValue"
        case .constant: return "stringValue"
        }
    }

    // MARK: - SwiftSyntax Code Generation

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
                    EnumCaseDeclSyntax {
                        EnumCaseElementSyntax(name: .identifier(v.name))
                    }
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
                            rawValue: InitializerClauseSyntax(
                                value: StringLiteralExprSyntax(content: a.name)
                            )
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
                // Fields
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
                // init(from:)
                InitializerDeclSyntax(
                    modifiers: [DeclModifierSyntax(name: .keyword(.public))],
                    signature: FunctionSignatureSyntax(
                        parameterClause: FunctionParameterClauseSyntax {
                            FunctionParameterSyntax(
                                firstName: "from",
                                secondName: "dict",
                                type: TypeSyntax(stringLiteral: "[String: TLAValue]")
                            )
                        }
                    ),
                    body: CodeBlockSyntax {
                        for v in variables {
                            ExprSyntax(stringLiteral: "self.\(v.name) = dict[Variables.\(v.name).rawValue]!.\(tlaValueExtractor(for: v.initial))")
                        }
                    }
                )
                // asDictionary
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
                                    ExprSyntax(stringLiteral: "d[Variables.\(v.name).rawValue] = \(tlaValueHelper(v))")
                                }
                                StmtSyntax(stringLiteral: "return d")
                            }
                        ))
                    )]
                )
            }
        )
    }

    static func tlaValueHelper(_ v: (name: String, initial: TLAValue, initialSet: StateExpr?)) -> String {
        switch v.initial {
        case .int:     return ".int(\(v.name))"
        case .bool:    return ".bool(\(v.name))"
        case .string:  return ".string(\(v.name))"
        case .set:     return ".set(Set(\(v.name).map { .int($0) }))"
        case .tuple:   return ".tuple(\(v.name))"
        case .record:  return ".record(\(v.name))"
        case .function: return ".function(\(v.name))"
        case .constant: return ".constant(\(v.name))"
        }
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
                        CodeBlockItemListSyntax {
                            ExprSyntax(stringLiteral: "_state.\(v.name)")
                        }
                    ))
                )]
            )
        }
    }

    static func generateActionMethods(actions: [(name: String, body: ActionExpr)]) -> [FunctionDeclSyntax] {
        actions.map { a in
            FunctionDeclSyntax(
                modifiers: [
                    DeclModifierSyntax(name: .keyword(.public)),
                    DeclModifierSyntax(name: .keyword(.mutating))
                ],
                name: .identifier("apply\(a.name)"),
                signature: FunctionSignatureSyntax(
                    parameterClause: FunctionParameterClauseSyntax(parameters: [])
                ),
                body: CodeBlockSyntax { ExprSyntax(stringLiteral: "_state = _apply(.\(a.name))") }
            )
        }
    }

    static func generateApplyHelper() -> FunctionDeclSyntax {
        FunctionDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.private))],
            name: "_apply",
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax {
                    FunctionParameterSyntax(
                        firstName: "_",
                        secondName: "action",
                        type: IdentifierTypeSyntax(name: "Actions")
                    )
                },
                returnClause: ReturnClauseSyntax(type: IdentifierTypeSyntax(name: "State"))
            ),
            body: CodeBlockSyntax {
                "let next = try! Self.runtime.apply(actionName: action.rawValue, to: _state.asDictionary)"
                "return State(from: next)"
            }
        )
    }
}
