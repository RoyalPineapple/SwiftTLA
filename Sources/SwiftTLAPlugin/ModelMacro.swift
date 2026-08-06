import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA

public struct ModelMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else {
            throw SimpleError("@TLAModel on structs only")
        }
        let typeName = structDeclaration.name.text

        let parsed = try parseSpecBody(structDeclaration.memberBlock.members, typeName: typeName)
        if parsed.variables.isEmpty { throw SimpleError("parsed.variables is empty after parseSpecBody") }
        let variableNames = parsed.variables.map(\.name)
        let actionsWithUnchanged = parsed.actions.map { a -> NamedAction in
            let assigned = assignedVars(a.body)
            let explicit = explicitUnchanged(a.body)
            var body = a.body
            for v in variableNames where !assigned.contains(v) && !explicit.contains(v) {
                body = .and(body, .unchanged(v))
            }
            return NamedAction(name: a.name, body: body)
        }
        let specification = TLASpec(
            name: typeName,
            variables: parsed.variables.map { NamedVar(name: $0.name, initial: $0.initial, initialSet: $0.initialSet) },
            constants: parsed.constants,
            actions: actionsWithUnchanged,
            invariants: parsed.invariants.map { NamedInvariant(name: $0.name, body: $0.body) },
            temporalProperties: parsed.temporal.map { NamedTemporal(name: $0.name, expr: $0.expr) },
            fairness: parsed.fairness
        )

        let checker = ModelChecker(spec: specification, maxStates: 10_000)
        if case .invariantViolated(let invariant, _, let trace) = (try? checker.check()) {
            let description = trace.map { String(describing: $0) }.joined(separator: "\n")
            throw SimpleError("Invariant '" + invariant + "' violated:\n" + description)
        }

        var members: [DeclSyntax] = []

        let graph: StateGraph
        do {
            graph = try checker.exploreGraph()
        } catch {
            throw SimpleError("Checker exploration failed: " + String(describing: error))
        }

        guard !graph.states.isEmpty else {
            throw SimpleError("No states in graph.")
        }

        let actions = Set(graph.transitions.values.flatMap { $0.map(\.action) }).sorted()
        guard !actions.isEmpty else {
            let sample = specification.actions.first.map { String(describing: $0.body) } ?? "none"
            throw SimpleError("No transitions found. States: " + String(graph.states.count) + ". Variables: " + specification.variables.map(\.name).joined(separator: ", ") + ". Action sample: " + sample)
        }

        guard let code = try? StateMachineGenerator(graph: graph).generate() else {
            throw SimpleError("StateMachineGenerator failed")
        }

        let renamed = code
            .replacingOccurrences(of: "struct " + typeName, with: "struct StateMachine")
            .replacingOccurrences(of: "static let initial = " + typeName + "(", with: "static let initial = StateMachine(")
        members.append(contentsOf: Parser.parse(source: renamed).statements.compactMap { $0.item.as(DeclSyntax.self) })

        return members
    }

    private struct ParsedSpec {
        var variables: [(name: String, initial: TLAValue, initialSet: StateExpr?)] = []
        var actions: [(name: String, body: ActionExpr)] = []
        var invariants: [(name: String, body: StateExpr)] = []
        var temporal: [(name: String, expr: TemporalExpr)] = []
        var fairness: [FairnessCondition] = []
        var constants: [String: TLAValue] = [:]
    }

    private static func parseSpecBody(_ members: MemberBlockItemListSyntax, typeName: String) throws -> ParsedSpec {
        for member in members {
            guard let variableDeclaration = member.decl.as(VariableDeclSyntax.self),
                  let binding = variableDeclaration.bindings.first,
                  binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "spec",
                  let getter = extractGetterBody(binding)
            else { continue }

            for statement in getter {
                guard case .expr(let expression) = statement.item else { continue }
                if let functionCall = expression.as(FunctionCallExprSyntax.self),
                   let callee = functionCall.calledExpression.as(DeclReferenceExprSyntax.self),
                   callee.baseName.text == "TLASpec" {
                    let closure = functionCall.trailingClosure ?? functionCall.arguments.last?.expression.as(ClosureExprSyntax.self)
                    if let closure {
                        return try parseBuilderBody(closure.statements)
                    }
                }
            }
        }
        throw SimpleError("@TLAModel struct must contain 'static var spec: TLASpec { TLASpec(\"Name\") { ... } }'")
    }

    private static func extractGetterBody(_ binding: PatternBindingSyntax) -> CodeBlockItemListSyntax? {
        guard let accessors = binding.accessorBlock?.accessors else { return nil }
        if let list = accessors.as(CodeBlockItemListSyntax.self) { return list }
        if let declarationList = accessors.as(AccessorDeclListSyntax.self) {
            for declaration in declarationList where declaration.accessorSpecifier.text == "get" {
                return declaration.body?.statements
            }
        }
        return nil
    }

    private static func parseBuilderBody(_ statements: CodeBlockItemListSyntax) throws -> ParsedSpec {
        var result = ParsedSpec()
        for statement in statements {
            switch statement.item {
            case .decl: continue  // let declarations are type-checked by Swift — no parsing needed
            case .expr(let expression):
                guard let call = expression.as(FunctionCallExprSyntax.self),
                      let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) else { continue }
                switch reference.baseName.text {
                case "Variable":
                    guard let ref = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self) else { continue }
                    if call.arguments.count >= 2, call.arguments[call.arguments.index(call.arguments.startIndex, offsetBy: 1)].label?.text == "in" {
                        let rangeExpr = call.arguments.dropFirst().first?.expression
                        let values = parseRangeValues(rangeExpr)
                        let stateSet: StateExpr? = rangeExpr.flatMap { expr in parseStateExpr(expr) }
                        result.variables.append((ref.baseName.text, .set(values), stateSet))
                    } else {
                        guard let value = parseInitialValue(call.arguments.dropFirst().first?.expression) else { continue }
                        result.variables.append((ref.baseName.text, value, nil))
                    }
                case "Action":
                    guard let name = extractStringLiteral(call.arguments.first?.expression),
                          let closure = call.trailingClosure else { continue }
                    let action = parseActionFrom(closure) ?? .guard_(.value(.bool(true)))
                    result.actions.append((name, action))
                case "Invariant":
                    guard let name = extractStringLiteral(call.arguments.first?.expression),
                          let stateExpr = call.trailingClosure?.statements.lazy.compactMap({ (stmt: CodeBlockItemSyntax) -> StateExpr? in
                              guard case .expr(let expr) = stmt.item else { return nil }
                              return parseStateExpr(expr)
                          }).first else { continue }
                    result.invariants.append((name, stateExpr))
                case "Temporal":
                    guard let name = extractStringLiteral(call.arguments.first?.expression),
                          let closure = call.trailingClosure else { continue }
                    for stmt in closure.statements {
                        if case .expr(let expr) = stmt.item { if let t = parseTemporal(expr) { result.temporal.append((name, t)); break } }
                    }
                case "Fairness":
                    guard let closure = call.trailingClosure else { continue }
                    for stmt in closure.statements {
                        if case .expr(let expr) = stmt.item { if let f = parseFairnessExpr(expr) { result.fairness.append(f); break } }
                    }
                case "Constant":
                    guard let name = extractStringLiteral(call.arguments.first?.expression),
                          let value = parseInitialValue(call.arguments.dropFirst().first?.expression) else { continue }
                    result.constants[name] = value
                default: continue
                }
            case .stmt: continue
            }
        }
        return result
    }

    private static func extractStringLiteral(_ expression: ExprSyntax?) -> String? {
        expression?.as(StringLiteralExprSyntax.self)?.segments.description.replacingOccurrences(of: "\"", with: "")
    }

    private static func parseInitialValue(_ expression: ExprSyntax?) -> TLAValue? {
        guard let expression else { return nil }
        if let int = expression.as(IntegerLiteralExprSyntax.self) { return .int(Int(int.literal.text) ?? 0) }
        if let bool = expression.as(BooleanLiteralExprSyntax.self) { return .bool(bool.literal.text == "true") }
        if let string = expression.as(StringLiteralExprSyntax.self) {
            let text = string.segments.description
            return .string(text)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
           let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text == "TLAValue" {
            let method = memberAccess.declName.baseName.text
            switch method {
            case "int":
                guard let intExpr = call.arguments.first?.expression.as(IntegerLiteralExprSyntax.self),
                      let value = Int(intExpr.literal.text)
                else { return nil }
                return .int(value)
            case "bool":
                guard let boolExpr = call.arguments.first?.expression.as(BooleanLiteralExprSyntax.self)
                else { return nil }
                return .bool(boolExpr.literal.text == "true")
            case "string":
                guard let stringExpr = call.arguments.first?.expression.as(StringLiteralExprSyntax.self)
                else { return nil }
                return .string(stringExpr.segments.description)
            case "set":
                let elements = call.arguments.first?.expression
                    .as(ArrayExprSyntax.self)?
                    .elements.compactMap { parseInitialValue($0.expression) } ?? []
                return .set(Set(elements))
            case "function":
                let pairs = call.arguments.first?.expression
                    .as(DictionaryExprSyntax.self)?
                    .content.as(DictionaryElementListSyntax.self)?
                    .compactMap { element -> (TLAValue, TLAValue)? in
                        guard let key = parseInitialValue(element.key.as(ExprSyntax.self)),
                              let value = parseInitialValue(element.value.as(ExprSyntax.self))
                        else { return nil }
                        return (key, value)
                    } ?? []
                var mapping: [TLAValue: TLAValue] = [:]
                for (key, value) in pairs { mapping[key] = value }
                return .function(mapping)
            case "tuple":
                let elements = call.arguments.first?.expression
                    .as(ArrayExprSyntax.self)?
                    .elements.compactMap { parseInitialValue($0.expression) } ?? []
                return .tuple(elements)
            default: return nil
            }
        }
        return nil
    }

    private static func parseActionFrom(_ closure: ClosureExprSyntax) -> ActionExpr? {
        return SpecParser.parseActionFrom(closure)
    }

    private static func parseRangeValues(_ expression: ExprSyntax?) -> Set<TLAValue> {
        guard let sequence = expression?.as(SequenceExprSyntax.self) else { return [] }
        let elements = Array(sequence.elements)
        guard elements.count == 3,
              elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text == "...",
              let start = elements[0].as(IntegerLiteralExprSyntax.self),
              let end = elements[2].as(IntegerLiteralExprSyntax.self),
              let startVal = Int(start.literal.text),
              let endVal = Int(end.literal.text) else { return [] }
        return Set((startVal...endVal).map { .int($0) })
    }

    // MARK: - State expression parsing

    private static func parseStateExpr(_ expression: ExprSyntax?) -> StateExpr? {
        return SpecParser.parseStateExpr(expression)
    }

    private static func parseTemporal(_ expr: ExprSyntax) -> TemporalExpr? {
        return SpecParser.parseTemporal(expr)
    }

    private static func parseFairnessExpr(_ expr: ExprSyntax) -> FairnessCondition? {
        return SpecParser.parseFairnessExpr(expr)
    }

}
