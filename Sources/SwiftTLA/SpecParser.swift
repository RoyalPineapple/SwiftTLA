import SwiftSyntax
import SwiftParser

/// Parses SwiftSyntax AST nodes into DSL types (StateExpr, ActionExpr, etc.).
/// Every AST pattern maps deterministically to a DSL value.
/// Tests live in SpecParserTests.
public enum SpecParser {

    // MARK: - State expressions

    /// Parses any Swift expression that represents a state-level value (no primes, no assignments).
    /// Returns nil if the expression cannot be interpreted as a state expression.
    public static func parseStateExpr(_ expression: ExprSyntax?) -> StateExpr? {
        guard let expression else { return nil }

        if let integerLiteral = expression.as(IntegerLiteralExprSyntax.self) {
            return .value(.int(Int(integerLiteral.literal.text) ?? 0))
        }
        if let booleanLiteral = expression.as(BooleanLiteralExprSyntax.self) {
            return .value(.bool(booleanLiteral.literal.text == "true"))
        }
        if let stringLiteral = expression.as(StringLiteralExprSyntax.self) {
            let text = stringLiteral.segments.description
            return .value(.string(text))
        }
        if let variableReference = expression.as(DeclReferenceExprSyntax.self) {
            return .variable(variableReference.baseName.text)
        }
        if let functionCall = expression.as(FunctionCallExprSyntax.self) {
            return parseMethodCall(functionCall)
        }
        if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
            return parseMemberAccess(memberAccess)
        }
        if let tupleExpression = expression.as(TupleExprSyntax.self),
           let singleElement = tupleExpression.elements.first?.expression {
            return parseStateExpr(singleElement)
        }
        if let infixOperator = expression.as(InfixOperatorExprSyntax.self),
           let leftOperand = parseStateExpr(infixOperator.leftOperand),
           let rightOperand = parseStateExpr(infixOperator.rightOperand) {
            let operatorText = infixOperator.operator.as(BinaryOperatorExprSyntax.self)?.operator.text
            return parseInfixOperation(leftOperand: leftOperand, rightOperand: rightOperand, operatorText: operatorText)
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3,
                  let leftOperand = parseStateExpr(elements[0]),
                  let operatorText = elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text,
                  let rightOperand = parseStateExpr(elements[2])
            else { return nil }
            return parseInfixOperation(leftOperand: leftOperand, rightOperand: rightOperand, operatorText: operatorText)
        }
        if let prefix = expression.as(PrefixOperatorExprSyntax.self) {
            let operand = parseStateExpr(prefix.expression)
            if prefix.operator.text == "!", let operand { return .not(operand) }
            if prefix.operator.text == "-", let operand { return .negate(operand) }
        }
        return nil
    }

    /// Maps an infix operator and its two operands to the correct StateExpr case.
    private static func parseInfixOperation(
        leftOperand: StateExpr,
        rightOperand: StateExpr,
        operatorText: String?
    ) -> StateExpr? {
        switch operatorText {
        case "+":  return .add(leftOperand, rightOperand)
        case "-":  return .subtract(leftOperand, rightOperand)
        case "*":  return .multiply(leftOperand, rightOperand)
        case "/":  return .divide(leftOperand, rightOperand)
        case "%":  return .modulo(leftOperand, rightOperand)
        case "<":  return .lessThan(leftOperand, rightOperand)
        case "<=": return .lessOrEqual(leftOperand, rightOperand)
        case ">":  return .greaterThan(leftOperand, rightOperand)
        case ">=": return .greaterOrEqual(leftOperand, rightOperand)
        case "==": return .equal(leftOperand, rightOperand)
        case "!=": return .notEqual(leftOperand, rightOperand)
        case "&&": return .and(leftOperand, rightOperand)
        case "||": return .or(leftOperand, rightOperand)
        case "...":
            guard case .value(.int(let first)) = leftOperand,
                  case .value(.int(let last)) = rightOperand
            else { return nil }
            let rangeValues = (first...last).map { StateExpr.value(.int($0)) }
            return .setLiteral(rangeValues)
        default: return nil
        }
    }

    // MARK: - Action parsing

    /// Parses a closure body containing action expressions (connected by implicit AND).
    public static func parseActionFrom(_ closure: ClosureExprSyntax) -> ActionExpr? {
        let actions = closure.statements.compactMap { statement -> ActionExpr? in
            guard case .expr(let inner) = statement.item else { return nil }
            return parseSingleAction(inner)
        }
        if actions.isEmpty { return .guard_(.value(.bool(true))) }
        return actions.dropFirst().reduce(actions[0]) { .and($0, $1) }
    }

    /// Parses a single action expression (one step in a transition).
    /// Handles: guard conditions, assignments, unchanged, OR/AND between actions.
    public static func parseSingleAction(_ expression: ExprSyntax) -> ActionExpr? {
        if let infixOperator = expression.as(InfixOperatorExprSyntax.self) {
            let operatorText = infixOperator.operator.as(BinaryOperatorExprSyntax.self)?.operator.text

            if operatorText == "||" {
                let leftResult = parseSingleAction(infixOperator.leftOperand)
                let rightResult = parseSingleAction(infixOperator.rightOperand)
                let leftState = parseStateExpr(infixOperator.leftOperand)
                let rightState = parseStateExpr(infixOperator.rightOperand)

                let leftAction = leftState == nil ? leftResult : nil
                let rightAction = rightState == nil ? rightResult : nil

                if let guardExpr = leftState, let actionExpr = rightResult { return .or(.guard_(guardExpr), actionExpr) }
                if let actionExpr = leftResult, let guardExpr = rightState { return .or(actionExpr, .guard_(guardExpr)) }
                if let leftAction, let rightAction { return .or(leftAction, rightAction) }
            }

            if operatorText == "&&" {
                let leftState = parseStateExpr(infixOperator.leftOperand)
                let rightState = parseStateExpr(infixOperator.rightOperand)
                let leftAction = leftState == nil ? parseSingleAction(infixOperator.leftOperand) : nil
                let rightAction = rightState == nil ? parseSingleAction(infixOperator.rightOperand) : nil

                if let guardExpr = leftState, let actionExpr = rightAction { return .and(.guard_(guardExpr), actionExpr) }
                if let actionExpr = leftAction, let guardExpr = rightState { return .and(actionExpr, .guard_(guardExpr)) }
                if let leftAction, let rightAction { return .and(leftAction, rightAction) }
            }
        }

        if let sequence = expression.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            if elements.count == 3 {
                let operatorText = elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text
                if let leftAction = parseSingleAction(elements[0]),
                   let rightAction = parseSingleAction(elements[2]) {
                    if operatorText == "||" { return .or(leftAction, rightAction) }
                    if operatorText == "&&" { return .and(leftAction, rightAction) }
                }
            } else if elements.count > 3 {
                return foldActionSequence(elements)
            }
        }

        if let functionCall = expression.as(FunctionCallExprSyntax.self),
           let becomesChain = parseBecomesChain(functionCall) {
            return becomesChain
        }

        if let functionCall = expression.as(FunctionCallExprSyntax.self) {
            if let becomesChain = parseBecomesChain(functionCall) {
                return becomesChain
            }
            if let chooseAction = parseChooseCall(functionCall) {
                return chooseAction
            }
        }

        if let memberAccess = expression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "stays",
           let baseReference = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
            return .unchanged(baseReference.baseName.text)
        }

        return nil
    }

    /// Parses `choose(variable, from: set)` into `.chooseAction(name, set)`.
    private static func parseChooseCall(_ call: FunctionCallExprSyntax) -> ActionExpr? {
        guard let ref = call.calledExpression.as(DeclReferenceExprSyntax.self),
              ref.baseName.text == "choose",
              let variableArg = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
              let fromArg = call.arguments.dropFirst().first?.expression,
              let setExpr = parseStateExpr(fromArg)
        else { return nil }
        return .chooseAction(variableArg.baseName.text, setExpr)
    }

    /// Folds a multi-element SequenceExprSyntax (5+ elements) into an ActionExpr
    /// by splitting on || (lowest precedence) then && within each group.
    private static func foldActionSequence(_ elements: [ExprSyntax]) -> ActionExpr? {
        // The sequence alternates: leaf, operator, leaf, operator, leaf, ...
        // Operator positions: 1, 3, 5, ...   Leaf positions: 0, 2, 4, ...
        guard elements.count >= 3, elements.count % 2 == 1 else { return nil }

        var orSplitIndices: [Int] = []
        for index in stride(from: 1, to: elements.count, by: 2) {
            if elements[index].as(BinaryOperatorExprSyntax.self)?.operator.text == "||" {
                orSplitIndices.append(index)
            }
        }

        if orSplitIndices.isEmpty {
            return foldAndGroup(elements)
        }

        var groups: [ActionExpr] = []
        var start = 0
        for splitIndex in orSplitIndices {
            if let group = foldAndGroup(Array(elements[start..<splitIndex])) {
                groups.append(group)
            }
            start = splitIndex + 1
        }
        if start < elements.count, let group = foldAndGroup(Array(elements[start...])) {
            groups.append(group)
        }

        guard !groups.isEmpty else { return nil }
        return groups.dropFirst().reduce(groups[0]) { .or($0, $1) }
    }

    /// Folds a sequence containing only && operators (or a single leaf) into an ActionExpr.
    private static func foldAndGroup(_ elements: [ExprSyntax]) -> ActionExpr? {
        guard elements.count >= 1 else { return nil }
        if elements.count == 1 { return parseLeafAsAction(elements[0]) }

        var andSplitIndices: [Int] = []
        for index in stride(from: 1, to: elements.count, by: 2) {
            if elements[index].as(BinaryOperatorExprSyntax.self)?.operator.text == "&&" {
                andSplitIndices.append(index)
            }
        }

        if andSplitIndices.isEmpty {
            return parseAndLeaf(elements)
        }

        var leafActions: [ActionExpr] = []
        var start = 0
        for splitIndex in andSplitIndices {
            if let leaf = parseAndLeaf(Array(elements[start..<splitIndex])) {
                leafActions.append(leaf)
            }
            start = splitIndex + 1
        }
        if start < elements.count, let leaf = parseAndLeaf(Array(elements[start...])) {
            leafActions.append(leaf)
        }

        guard !leafActions.isEmpty else { return nil }
        return leafActions.dropFirst().reduce(leafActions[0]) { .and($0, $1) }
    }

    /// Parses a leaf slice (one or more ExprSyntax elements) as an action or guard.
    private static func parseAndLeaf(_ slice: [ExprSyntax]) -> ActionExpr? {
        if slice.count == 1 {
            return parseLeafAsAction(slice[0])
        }
        let source = slice.map { $0.description }.joined()
        guard let reconstructed = SwiftParser.Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self) else {
            return nil
        }
        return parseLeafAsAction(reconstructed)
    }

    /// Tries to parse a single expression as either an action or a guard (state expression).
    private static func parseLeafAsAction(_ expression: ExprSyntax) -> ActionExpr? {
        if let action = parseSingleAction(expression) { return action }
        if let state = parseStateExpr(expression) { return .guard_(state) }
        return nil
    }

    // MARK: - Becomes chain (assignment with optional .when guards)

    private struct GuardedAssignment {
        let call: FunctionCallExprSyntax
        let condition: StateExpr?
    }

    /// Unwraps nested `.when(...)` calls from a `.becomes(...)` chain.
    /// `x.becomes(1).when(x < 5)` → call = `x.becomes(1)`, condition = `x < 5`
    private static func unwrapGuards(_ functionCall: FunctionCallExprSyntax) -> GuardedAssignment {
        if let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "when",
           let innerCall = memberAccess.base?.as(FunctionCallExprSyntax.self) {
            let outerCondition = parseStateExpr(functionCall.arguments.first?.expression)
            let inner = unwrapGuards(innerCall)
            if let outer = outerCondition, let innerCondition = inner.condition {
                return GuardedAssignment(call: inner.call, condition: .and(outer, innerCondition))
            }
            return GuardedAssignment(call: inner.call, condition: outerCondition ?? inner.condition)
        }
        return GuardedAssignment(call: functionCall, condition: nil)
    }

    /// Parses a `.becomes(...)` call (possibly wrapped in `.when(...)` chains).
    /// Detects whether the assignment is deterministic or nondeterministic (CHOOSE).
    private static func parseBecomesChain(_ functionCall: FunctionCallExprSyntax) -> ActionExpr? {
        let guarded = unwrapGuards(functionCall)
        guard let (variableName, assignment) = parseBecomesArgument(guarded.call) else { return nil }

        let action: ActionExpr
        if case .choose(let chosenSet, _) = assignment {
            action = .chooseAction(variableName, chosenSet)
        } else {
            action = .assign(variableName, assignment)
        }

        return guarded.condition.map { .and(.guard_($0), action) } ?? action
    }

    /// Extracts the variable name and value expression from a `.becomes(expr)` call.
    private static func parseBecomesArgument(_ functionCall: FunctionCallExprSyntax) -> (String, StateExpr)? {
        guard let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "becomes",
              let baseReference = memberAccess.base?.as(DeclReferenceExprSyntax.self),
              let argument = functionCall.arguments.first?.expression
        else { return nil }

        let variableName = baseReference.baseName.text
        let value = parseStateExpr(argument) ?? .value(.int(0))
        return (variableName, value)
    }

    // MARK: - Temporal properties

    public static func parseTemporal(_ expression: ExprSyntax) -> TemporalExpr? {
        guard let functionCall = expression.as(FunctionCallExprSyntax.self),
              let memberRef = functionCall.calledExpression.as(MemberAccessExprSyntax.self)
        else { return nil }

        let method = memberRef.declName.baseName.text
        let firstArgument = functionCall.arguments.first.flatMap { parseStateExpr($0.expression) }

        switch method {
        case "leadsTo":
            let source = parseStateExpr(memberRef.base) ?? .value(.bool(true))
            return firstArgument.map { .leadsTo(source, $0) }
        case "always":           return firstArgument.map { .always($0) }
        case "eventually":       return firstArgument.map { .eventually($0) }
        case "alwaysEventually":  return firstArgument.map { .alwaysEventually($0) }
        case "eventuallyAlways":  return firstArgument.map { .eventuallyAlways($0) }
        default: return nil
        }
    }

    // MARK: - Fairness conditions

    public static func parseFairnessExpr(_ expression: ExprSyntax) -> FairnessCondition? {
        guard let functionCall = expression.as(FunctionCallExprSyntax.self),
              let memberRef = functionCall.calledExpression.as(MemberAccessExprSyntax.self)
        else { return nil }

        let method = memberRef.declName.baseName.text
        let name = functionCall.arguments.first?.expression
            .as(StringLiteralExprSyntax.self)?
            .segments.description
            .replacingOccurrences(of: "\"", with: "")
            ?? ""

        switch method {
        case "weakFairness":   return .weakFairness(name)
        case "strongFairness": return .strongFairness(name)
        default: return nil
        }
    }

    // MARK: - Method calls on state expressions

    /// Parses method calls like `x.isIn(someSet)`, `x.union(other)`, `x.at(3)`, etc.
    private static func parseMethodCall(_ functionCall: FunctionCallExprSyntax) -> StateExpr? {
        guard let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self)
        else { return nil }

        let methodName = memberAccess.declName.baseName.text
        let firstArgument = functionCall.arguments.first?.expression
        let baseExpression = memberAccess.base

        switch methodName {
        case "isIn":         return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .in($0, $1) })
        case "union":        return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .union($0, $1) })
        case "intersection":  return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .intersection($0, $1) })
        case "subtracting":  return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .setDifference($0, $1) })
        case "isSubset":     return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .subset($0, $1) })
        case "applying":     return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .functionApply($0, $1) })
        case "filtering":    return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .setFilter($0, $1) })
        case "mapping":      return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .setMap($1, $0) })
        case "appending":    return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .tupleAppend($0, $1) })
        case "concatenating": return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .tupleConcatenate($0, $1) })
        case "integerDivided": return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .integerDivide($0, $1) })
        case "updated":
            guard let baseExpression,
                  let selfExpr = parseStateExpr(baseExpression)
            else { return nil }
            let allArguments = Array(functionCall.arguments)
            guard allArguments.count >= 2,
                  let keyExpr = parseStateExpr(allArguments[0].expression),
                  let valueExpr = parseStateExpr(allArguments[1].expression)
            else { return nil }
            return .except(selfExpr, keyExpr, valueExpr)
        case "at":
            guard let baseExpression,
                  let selfExpr = parseStateExpr(baseExpression),
                  let index = functionCall.arguments.first?.expression
                    .as(IntegerLiteralExprSyntax.self)
                    .flatMap({ Int($0.literal.text) })
            else { return nil }
            return .tupleAccess(selfExpr, index)
        default:
            if let referenceBase = memberAccess.base?.as(DeclReferenceExprSyntax.self),
               referenceBase.baseName.text == "StateExpr" {
                return parseStaticCall(
                    memberAccess: memberAccess,
                    arguments: Array(functionCall.arguments),
                    method: methodName
                )
            }
            return nil
        }
    }

    /// Helper for methods that take exactly one argument: `receiver.method(argument)`.
    private static func parseBinaryMethod(
        base: ExprSyntax?,
        argument: ExprSyntax?,
        combine: (StateExpr, StateExpr) -> StateExpr
    ) -> StateExpr? {
        guard let base,
              let selfExpr = parseStateExpr(base),
              let argumentExpr = parseStateExpr(argument)
        else { return nil }
        return combine(selfExpr, argumentExpr)
    }

    // MARK: - Static calls on StateExpr

    /// Parses static method calls like `StateExpr.set([...])`, `StateExpr.choose(from:matching:)`, etc.
    private static func parseStaticCall(
        memberAccess: MemberAccessExprSyntax,
        arguments: [LabeledExprSyntax],
        method: String
    ) -> StateExpr? {
        switch method {
        case "set":
            let elements = arguments.first?.expression
                .as(ArrayExprSyntax.self)?
                .elements
                .compactMap { parseStateExpr($0.expression) }
                ?? []
            return .setLiteral(elements)

        case "tuple":
            let elements = arguments.first?.expression
                .as(ArrayExprSyntax.self)?
                .elements
                .compactMap { parseStateExpr($0.expression) }
                ?? []
            return .tupleLiteral(elements)

        case "record":
            var fields: [String: StateExpr] = [:]
            for argument in arguments {
                guard let label = argument.label?.text,
                      let value = parseStateExpr(argument.expression)
                else { return nil }
                fields[label] = value
            }
            return .recordLiteral(fields)

        case "if":
            guard arguments.count >= 3,
                  let condition = parseStateExpr(arguments[0].expression),
                  let thenValue = parseStateExpr(arguments[1].expression),
                  let elseValue = parseStateExpr(arguments[2].expression)
            else { return nil }
            return .ifThenElse(condition, thenValue, elseValue)

        case "enabled":
            let actionName = arguments.first?.expression
                .as(StringLiteralExprSyntax.self)?
                .segments.description
                .replacingOccurrences(of: "\"", with: "")
                ?? ""
            return .enabledAction(actionName)

        case "function":
            guard arguments.count >= 2,
                  let domain = parseStateExpr(arguments[0].expression),
                  let body = parseStateExpr(arguments[1].expression)
            else { return nil }
            return .functionLiteral(domain, body)

        case "for":
            guard arguments.count >= 2,
                  let setExpr = parseStateExpr(arguments[0].expression),
                  let predicate = parseStateExpr(arguments[1].expression)
            else { return nil }
            return .forAll(setExpr, predicate)

        case "exists":
            guard arguments.count >= 2,
                  let setExpr = parseStateExpr(arguments[0].expression),
                  let predicate = parseStateExpr(arguments[1].expression)
            else { return nil }
            return .exists(setExpr, predicate)

        case "choose":
            guard arguments.count >= 2,
                  let setExpr = parseStateExpr(arguments[0].expression),
                  let predicate = parseStateExpr(arguments[1].expression)
            else { return nil }
            return .choose(setExpr, predicate)

        case "any":
            guard let setExpr = arguments.first.flatMap({ parseStateExpr($0.expression) })
            else { return nil }
            return .choose(setExpr, .value(.bool(true)))

        case "firstMatch":
            var flatPairs: [StateExpr] = []
            var fallbackExpr: StateExpr? = nil
            for argument in arguments {
                if argument.label?.text == "fallback" {
                    fallbackExpr = parseStateExpr(argument.expression)
                } else if let tupleExpr = argument.expression.as(TupleExprSyntax.self) {
                    for element in tupleExpr.elements {
                        guard let parsed = parseStateExpr(element.expression) else { return nil }
                        flatPairs.append(parsed)
                    }
                } else {
                    return nil
                }
            }
            return .caseExpr(flatPairs, fallbackExpr)

        case "singleton":
            guard let element = parseStateExpr(arguments.first?.expression) else { return nil }
            return .setLiteral([element])

        case "functionLiteral":
            guard arguments.count >= 2,
                  let domain = parseStateExpr(arguments[0].expression),
                  let body = parseStateExpr(arguments[1].expression)
            else { return nil }
            return .functionLiteral(domain, body)

        default:
            return nil
        }
    }

    // MARK: - Member access (dot notation)

    /// Parses dot-notation property access like `expr.cardinality`, `expr.domain`,
    /// or arbitrary record field access like `msg.type`, `node.value`.
    private static func parseMemberAccess(_ memberAccess: MemberAccessExprSyntax) -> StateExpr? {
        let propertyName = memberAccess.declName.baseName.text
        guard let baseExpression = memberAccess.base,
              let selfExpr = parseStateExpr(baseExpression)
        else { return nil }

        switch propertyName {
        case "cardinality": return .cardinality(selfExpr)
        case "flattened":   return .unionAll(selfExpr)
        case "subsets":     return .powerSet(selfExpr)
        case "domain":      return .domain(selfExpr)
        case "count":       return .tupleLength(selfExpr)
        default:
            // Any unknown property name is treated as record field access.
            // For example, `msg.type` becomes `.recordAccess(.variable("msg"), "type")`.
            return .recordAccess(selfExpr, propertyName)
        }
    }
}
