import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA
import SwiftTLAGeneration

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
        let specification = TLASpec(
            name: typeName,
            variables: parsed.variables.map { NamedVar(name: $0.name, initial: $0.initial) },
            actions: parsed.actions.map { NamedAction(name: $0.name, body: $0.body) },
            invariants: parsed.invariants.map { NamedInvariant(name: $0.name, body: $0.body) },
            temporalProperties: [],
            fairness: []
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
            .replacingOccurrences(of: "struct " + typeName, with: "struct Machine")
            .replacingOccurrences(of: "static let initial = " + typeName + "(", with: "static let initial = Machine(")
        members.append(contentsOf: Parser.parse(source: renamed).statements.compactMap { $0.item.as(DeclSyntax.self) })

        return members
    }

    private struct ParsedSpec {
        var variables: [(name: String, initial: TLAValue)] = []
        var actions: [(name: String, body: ActionExpr)] = []
        var invariants: [(name: String, body: StateExpr)] = []
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
                        return parseBuilderBody(closure.statements)
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

    private static func parseBuilderBody(_ statements: CodeBlockItemListSyntax) -> ParsedSpec {
        var result = ParsedSpec()
        for statement in statements {
            switch statement.item {
            case .decl(let declaration):
                if let variableDeclaration = declaration.as(VariableDeclSyntax.self),
                   let binding = variableDeclaration.bindings.first,
                   let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                   let initCall = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                   let callee = initCall.calledExpression.as(DeclReferenceExprSyntax.self),
                   callee.baseName.text == "Var",
                   let value = parseInitialValue(initCall.arguments.first?.expression) {
                    result.variables.append((name, value))
                }
            case .expr(let expression):
                guard let call = expression.as(FunctionCallExprSyntax.self),
                      let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) else { continue }
                switch reference.baseName.text {
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
        return nil
    }

    private static func parseActionFrom(_ closure: ClosureExprSyntax) -> ActionExpr? {
        let actions = closure.statements.compactMap { statement -> ActionExpr? in
            guard case .expr(let inner) = statement.item else { return nil }
            return parseSingleAction(inner)
        }
        if actions.isEmpty { return .guard_(.value(.bool(true))) }
        return actions.dropFirst().reduce(actions[0]) { .and($0, $1) }
    }

    private static func parseSingleAction(_ expression: ExprSyntax) -> ActionExpr? {
        if let infix = expression.as(InfixOperatorExprSyntax.self) {
            let operatorText = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text
            if operatorText == "||", let left = parseSingleAction(infix.leftOperand), let right = parseSingleAction(infix.rightOperand) {
                return .or(left, right)
            }
            if operatorText == "&&" {
                let leftState = parseStateExpr(infix.leftOperand)
                let rightState = parseStateExpr(infix.rightOperand)
                let leftAction = leftState == nil ? parseSingleAction(infix.leftOperand) : nil
                let rightAction = rightState == nil ? parseSingleAction(infix.rightOperand) : nil
                if let guardCondition = leftState, let action = rightAction { return .and(.guard_(guardCondition), action) }
                if let action = leftAction, let guardCondition = rightState { return .and(action, .guard_(guardCondition)) }
                if let left = leftAction, let right = rightAction { return .and(left, right) }
            }
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3,
                  let operatorText = elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text,
                  let left = parseSingleAction(elements[0]),
                  let right = parseSingleAction(elements[2]) else { return nil }
            if operatorText == "||" { return .or(left, right) }
            if operatorText == "&&" { return .and(left, right) }
        }
        if let call = expression.as(FunctionCallExprSyntax.self), let chain = parseBecomesChain(call) { return chain }
        if let memberAccess = expression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "stays",
           let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
            return .unchanged(base.baseName.text)
        }
        return nil
    }

    private static func parseBecomesChain(_ call: FunctionCallExprSyntax) -> ActionExpr? {
        let chain = unwrapWhen(call)
        guard let (variableName, value) = parseBecomes(chain.call) else { return nil }
        let action = ActionExpr.assign(variableName, value)
        return chain.condition.map { .and(.guard_($0), action) } ?? action
    }

    private struct Chain { let call: FunctionCallExprSyntax; let condition: StateExpr? }

    private static func unwrapWhen(_ call: FunctionCallExprSyntax) -> Chain {
        if let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "when",
           let base = memberAccess.base?.as(FunctionCallExprSyntax.self) {
            let condition = parseStateExpr(call.arguments.first?.expression)
            let inner = unwrapWhen(base)
            if let outerCondition = condition, let innerCondition = inner.condition {
                return Chain(call: inner.call, condition: .and(outerCondition, innerCondition))
            }
            return Chain(call: inner.call, condition: condition ?? inner.condition)
        }
        return Chain(call: call, condition: nil)
    }

    private static func parseBecomes(_ call: FunctionCallExprSyntax) -> (String, StateExpr)? {
        guard let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "becomes",
              let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
              let argument = call.arguments.first?.expression else { return nil }
        return (base.baseName.text, parseStateExpr(argument) ?? .value(.int(0)))
    }

    // MARK: - State expression parsing

    private static func parseStateExpr(_ expression: ExprSyntax?) -> StateExpr? {
        guard let expression else { return nil }
        if let int = expression.as(IntegerLiteralExprSyntax.self) { return .value(.int(Int(int.literal.text) ?? 0)) }
        if let bool = expression.as(BooleanLiteralExprSyntax.self) { return .value(.bool(bool.literal.text == "true")) }
        if let reference = expression.as(DeclReferenceExprSyntax.self) { return .variable(reference.baseName.text) }
        if let call = expression.as(FunctionCallExprSyntax.self) { return parseMethodCall(call) }
        if let memberAccess = expression.as(MemberAccessExprSyntax.self) { return parseMemberAccess(memberAccess) }
        if let tuple = expression.as(TupleExprSyntax.self), let single = tuple.elements.first?.expression { return parseStateExpr(single) }
        if let infix = expression.as(InfixOperatorExprSyntax.self), let left = parseStateExpr(infix.leftOperand), let right = parseStateExpr(infix.rightOperand) {
            switch infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text {
            case "+": return .add(left, right); case "-": return .subtract(left, right)
            case "*": return .multiply(left, right); case "/": return .divide(left, right); case "%": return .modulo(left, right)
            case "<": return .lessThan(left, right); case "<=": return .lessOrEqual(left, right)
            case ">": return .greaterThan(left, right); case ">=": return .greaterOrEqual(left, right)
            case "==": return .equal(left, right); case "!=": return .notEqual(left, right)
            case "&&": return .and(left, right); case "||": return .or(left, right)
            default: return nil
            }
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3, let left = parseStateExpr(elements[0]),
                  let operatorText = elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text,
                  let right = parseStateExpr(elements[2]) else { return nil }
            switch operatorText {
            case "+": return .add(left, right); case "-": return .subtract(left, right)
            case "*": return .multiply(left, right); case "/": return .divide(left, right); case "%": return .modulo(left, right)
            case "<": return .lessThan(left, right); case "<=": return .lessOrEqual(left, right)
            case ">": return .greaterThan(left, right); case ">=": return .greaterOrEqual(left, right)
            case "==": return .equal(left, right); case "!=": return .notEqual(left, right)
            case "&&": return .and(left, right); case "||": return .or(left, right)
            default: return nil
            }
        }
        if let prefix = expression.as(PrefixOperatorExprSyntax.self) {
            let operand = parseStateExpr(prefix.expression)
            if prefix.operator.text == "!", let operand { return .not(operand) }
            if prefix.operator.text == "-", let operand { return .negate(operand) }
        }
        return nil
    }

    // MARK: - DSL method/property parsing

    private static func parseMethodCall(_ call: FunctionCallExprSyntax) -> StateExpr? {
        guard let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }
        let method = memberAccess.declName.baseName.text
        let firstArg = call.arguments.first?.expression
        let base = memberAccess.base

        switch method {
        case "isIn":
            guard let base, let selfExpr = parseStateExpr(base), let arg = parseStateExpr(firstArg) else { return nil }
            return .in(selfExpr, arg)
        case "union":
            guard let base, let selfExpr = parseStateExpr(base), let arg = parseStateExpr(firstArg) else { return nil }
            return .union(selfExpr, arg)
        case "intersection":
            guard let base, let selfExpr = parseStateExpr(base), let arg = parseStateExpr(firstArg) else { return nil }
            return .intersection(selfExpr, arg)
        case "subtracting":
            guard let base, let selfExpr = parseStateExpr(base), let arg = parseStateExpr(firstArg) else { return nil }
            return .setDifference(selfExpr, arg)
        case "isSubset":
            guard let base, let selfExpr = parseStateExpr(base), let arg = parseStateExpr(firstArg) else { return nil }
            return .subset(selfExpr, arg)
        case "updated":
            guard let base, let selfExpr = parseStateExpr(base) else { return nil }
            let args = Array(call.arguments)
            guard args.count >= 2, let key = parseStateExpr(args[0].expression), let value = parseStateExpr(args[1].expression) else { return nil }
            return .except(selfExpr, key, value)
        case "applying":
            guard let base, let selfExpr = parseStateExpr(base), let arg = parseStateExpr(firstArg) else { return nil }
            return .functionApply(selfExpr, arg)
        case "filtering":
            guard let base, let selfExpr = parseStateExpr(base), let predicate = parseStateExpr(firstArg) else { return nil }
            return .setFilter(selfExpr, predicate)
        case "mapping":
            guard let base, let selfExpr = parseStateExpr(base), let expression = parseStateExpr(firstArg) else { return nil }
            return .setMap(expression, selfExpr)
        case "appending":
            guard let base, let selfExpr = parseStateExpr(base), let element = parseStateExpr(firstArg) else { return nil }
            return .tupleAppend(selfExpr, element)
        case "concatenating":
            guard let base, let selfExpr = parseStateExpr(base), let other = parseStateExpr(firstArg) else { return nil }
            return .tupleConcatenate(selfExpr, other)
        default:
            if let refBase = memberAccess.base?.as(DeclReferenceExprSyntax.self), refBase.baseName.text == "StateExpr" {
                return parseStaticCall(memberAccess: memberAccess, arguments: Array(call.arguments), method: method)
            }
            return nil
        }
    }

    private static func parseStaticCall(memberAccess: MemberAccessExprSyntax, arguments: [LabeledExprSyntax], method: String) -> StateExpr? {
        switch method {
        case "set":
            let elements = arguments.first?.expression.as(ArrayExprSyntax.self)?.elements.compactMap { parseStateExpr($0.expression) } ?? []
            return .setLiteral(elements)
        case "tuple":
            let elements = arguments.first?.expression.as(ArrayExprSyntax.self)?.elements.compactMap { parseStateExpr($0.expression) } ?? []
            return .tupleLiteral(elements)
        case "record":
            var fields: [String: StateExpr] = [:]
            for arg in arguments {
                guard let label = arg.label?.text, let value = parseStateExpr(arg.expression) else { return nil }
                fields[label] = value
            }
            return .recordLiteral(fields)
        case "if":
            guard arguments.count >= 3,
                  let condition = parseStateExpr(arguments[0].expression),
                  let thenValue = parseStateExpr(arguments[1].expression),
                  let elseValue = parseStateExpr(arguments[2].expression) else { return nil }
            return .ifThenElse(condition, thenValue, elseValue)
        case "enabled":
            let name = arguments.first?.expression.as(StringLiteralExprSyntax.self)?.segments.description.replacingOccurrences(of: "\"", with: "") ?? ""
            return .enabledAction(name)
        case "function":
            guard arguments.count >= 2,
                  let domain = parseStateExpr(arguments[0].expression),
                  let body = parseStateExpr(arguments[1].expression) else { return nil }
            return .functionLiteral(domain, body)
        case "for":
            guard arguments.count >= 2,
                  let set = parseStateExpr(arguments[0].expression),
                  let predicate = parseStateExpr(arguments[1].expression) else { return nil }
            return .forAll(set, predicate)
        case "exists":
            guard arguments.count >= 2,
                  let set = parseStateExpr(arguments[0].expression),
                  let predicate = parseStateExpr(arguments[1].expression) else { return nil }
            return .exists(set, predicate)
        case "choose":
            guard arguments.count >= 2,
                  let set = parseStateExpr(arguments[0].expression),
                  let predicate = parseStateExpr(arguments[1].expression) else { return nil }
            return .choose(set, predicate)
        default: return nil
        }
    }

    private static func parseMemberAccess(_ memberAccess: MemberAccessExprSyntax) -> StateExpr? {
        let property = memberAccess.declName.baseName.text
        guard let baseExpr = memberAccess.base, let selfExpr = parseStateExpr(baseExpr) else { return nil }
        switch property {
        case "cardinality": return .cardinality(selfExpr)
        case "flattened": return .unionAll(selfExpr)
        case "subsets": return .powerSet(selfExpr)
        case "domain": return .domain(selfExpr)
        case "count": return .tupleLength(selfExpr)
        default: return nil
        }
    }
}
