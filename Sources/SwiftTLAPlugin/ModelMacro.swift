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

        return [
            DeclSyntax(stringLiteral: "private var _state: State = State(from: Self.runtime.initialStates().first!)"),
            DeclSyntax(stringLiteral: Self.generateVariablesEnum(variables: parsed.variables)),
            DeclSyntax(stringLiteral: Self.generateActionsEnum(actions: parsed.actions)),
            DeclSyntax(stringLiteral: Self.generateStateStruct(variables: parsed.variables)),
            DeclSyntax(stringLiteral: Self.generateVariableProperties(variables: parsed.variables)),
            DeclSyntax(stringLiteral: Self.generateActionMethods(actions: parsed.actions)),
            DeclSyntax(stringLiteral: Self.generateApplyHelper()),
            DeclSyntax(stringLiteral: "public static var runtime: SpecRuntime { SpecRuntime(spec: spec) }"),
        ]
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

    // MARK: - Type mapping helpers

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

    static func tlaValueConstructor(for initial: TLAValue, value: String) -> String {
        switch initial {
        case .int:     return ".int(\(value))"
        case .bool:    return ".bool(\(value))"
        case .string:  return ".string(\(value))"
        case .set:     return ".set(Set(\(value).map { .int($0) }))"
        case .tuple:   return ".tuple(\(value))"
        case .record:  return ".record(\(value))"
        case .function: return ".function(\(value))"
        case .constant: return ".constant(\(value))"
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

    // MARK: - Code generation

    static func generateVariablesEnum(variables: [(name: String, initial: TLAValue, initialSet: StateExpr?)]) -> String {
        let cases = variables.map { "        case \($0.name)" }.joined(separator: "\n")
        return """
        public enum Variables: String, CaseIterable {
        \(cases)
        }
        """
    }

    static func generateActionsEnum(actions: [(name: String, body: ActionExpr)]) -> String {
        let cases = actions.map { "        case \($0.name) = \"\($0.name)\"" }.joined(separator: "\n")
        return """
        public enum Actions: String, CaseIterable {
        \(cases)
        }
        """
    }

    static func generateStateStruct(variables: [(name: String, initial: TLAValue, initialSet: StateExpr?)]) -> String {
        let fields = variables.map { v in
            "        public var \(v.name): \(swiftType(for: v.initial))"
        }.joined(separator: "\n")

        let initAssignments = variables.map { v in
            "            self.\(v.name) = dict[Variables.\(v.name).rawValue]!.\(tlaValueExtractor(for: v.initial))"
        }.joined(separator: "\n")

        let dictAssignments = variables.map { v in
            "            d[Variables.\(v.name).rawValue] = \(tlaValueConstructor(for: v.initial, value: v.name))"
        }.joined(separator: "\n")

        return """
        public struct State {
        \(fields)

            public init(from dict: [String: TLAValue]) {
        \(initAssignments)
            }

            public var asDictionary: [String: TLAValue] {
                var d: [String: TLAValue] = [:]
        \(dictAssignments)
                return d
            }
        }
        """
    }

    static func generateVariableProperties(variables: [(name: String, initial: TLAValue, initialSet: StateExpr?)]) -> String {
        variables.map { v in
            "        public var \(v.name): \(swiftType(for: v.initial)) { _state.\(v.name) }"
        }.joined(separator: "\n")
    }

    static func generateActionMethods(actions: [(name: String, body: ActionExpr)]) -> String {
        actions.map { a in
            """
                public mutating func apply\(a.name)() {
                    _state = _apply(.\(a.name))
                }
            """
        }.joined(separator: "\n")
    }

    static func generateApplyHelper() -> String {
        """
            private func _apply(_ action: Actions) -> State {
                let next = try! Self.runtime.apply(actionName: action.rawValue, to: _state.asDictionary)
                return State(from: next)
            }
        """
    }
}
