import SwiftSyntax
import SwiftParser
import SwiftBasicFormat

/// Parses SwiftSyntax AST nodes into DSL types (StateExpr, ActionExpr, etc.).
/// Every AST pattern maps deterministically to a DSL value.
/// Tests live in SpecParserTests.
public enum SpecParser {

    // MARK: - State expressions

    /// Local constants collected during parsing (for `Value` / `let` bindings).
    nonisolated(unsafe) private static var _constants: [String: TLAValue] = [:]

    /// Parses any Swift expression that represents a state-level value (no primes, no assignments).
    /// Returns nil if the expression cannot be interpreted as a state expression.
    public static func parseStateExpr(_ expression: ExprSyntax?, localConstants: [String: TLAValue] = [:]) -> StateExpr? {
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
            let name = variableReference.baseName.text
            if let resolved = localConstants[name] { return .value(resolved) }
            return .variable(name)
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
    public static func parseActionFrom(
        _ closure: ClosureExprSyntax,
        localConstants: [String: TLAValue] = [:],
        symmetricCollections: Set<String> = []
    ) -> ActionExpr? {
        var actions: [ActionExpr] = []
        for statement in closure.statements {
            guard case .expr(let expression) = statement.item else { continue }
            guard let action = parseSingleAction(expression, symmetricCollections: symmetricCollections) else {
                return nil
            }
            actions.append(action)
        }
        guard let first = actions.first else { return .guard_(.value(.bool(true))) }
        return actions.dropFirst().reduce(first) { .and($0, $1) }
    }

    public static func parseInvariantFrom(_ closure: ClosureExprSyntax) -> StateExpr? {
        parseStateExprFrom(closure)
    }

    private static func parseStateExprFrom(_ closure: ClosureExprSyntax) -> StateExpr? {
        let exprs = closure.statements.compactMap { statement -> StateExpr? in
            guard case .expr(let inner) = statement.item else { return nil }
            return parseStateExpr(inner)
        }
        if exprs.isEmpty { return .value(.bool(true)) }
        return exprs.dropFirst().reduce(exprs[0]) { .and($0, $1) }
    }

    /// Parses a single action expression (one step in a transition).
    /// Handles: guard conditions, assignments, unchanged, OR/AND between actions.
    public static func parseSingleAction(
        _ expression: ExprSyntax,
        symmetricCollections: Set<String> = []
    ) -> ActionExpr? {
        if let infixOperator = expression.as(InfixOperatorExprSyntax.self) {
            let operatorText = infixOperator.operator.as(BinaryOperatorExprSyntax.self)?.operator.text

            if operatorText == "||" {
                let leftResult = parseSingleAction(infixOperator.leftOperand, symmetricCollections: symmetricCollections)
                let rightResult = parseSingleAction(infixOperator.rightOperand, symmetricCollections: symmetricCollections)
                let leftState = parseInvariantExpression(infixOperator.leftOperand, symmetricCollections: symmetricCollections)
                let rightState = parseInvariantExpression(infixOperator.rightOperand, symmetricCollections: symmetricCollections)

                let leftAction = leftState == nil ? leftResult : nil
                let rightAction = rightState == nil ? rightResult : nil

                if let guardExpr = leftState, let actionExpr = rightResult { return .or(.guard_(guardExpr), actionExpr) }
                if let actionExpr = leftResult, let guardExpr = rightState { return .or(actionExpr, .guard_(guardExpr)) }
                if let leftAction, let rightAction { return .or(leftAction, rightAction) }
            }

            if operatorText == "&&" {
                let leftState = parseInvariantExpression(infixOperator.leftOperand, symmetricCollections: symmetricCollections)
                let rightState = parseInvariantExpression(infixOperator.rightOperand, symmetricCollections: symmetricCollections)
                let leftAction = leftState == nil ? parseSingleAction(infixOperator.leftOperand, symmetricCollections: symmetricCollections) : nil
                let rightAction = rightState == nil ? parseSingleAction(infixOperator.rightOperand, symmetricCollections: symmetricCollections) : nil

                if let guardExpr = leftState, let actionExpr = rightAction { return .and(.guard_(guardExpr), actionExpr) }
                if let actionExpr = leftAction, let guardExpr = rightState { return .and(actionExpr, .guard_(guardExpr)) }
                if let leftAction, let rightAction { return .and(leftAction, rightAction) }
            }
        }

        if let sequence = expression.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            if elements.count == 3 {
                let operatorText = elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text
                if let leftAction = parseLeafAsAction(elements[0], symmetricCollections: symmetricCollections),
                   let rightAction = parseLeafAsAction(elements[2], symmetricCollections: symmetricCollections) {
                    if operatorText == "||" { return .or(leftAction, rightAction) }
                    if operatorText == "&&" { return .and(leftAction, rightAction) }
                }
            } else if elements.count > 3 {
                return foldActionSequence(elements, symmetricCollections: symmetricCollections)
            }
        }

        if let functionCall = expression.as(FunctionCallExprSyntax.self),
            let becomesChain = parseBecomesChain(functionCall, symmetricCollections: symmetricCollections) {
            return becomesChain
        }

        if let functionCall = expression.as(FunctionCallExprSyntax.self) {
            if let becomesChain = parseBecomesChain(functionCall, symmetricCollections: symmetricCollections) {
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
    private static func foldActionSequence(
        _ elements: [ExprSyntax],
        symmetricCollections: Set<String>
    ) -> ActionExpr? {
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
            return foldAndGroup(elements, symmetricCollections: symmetricCollections)
        }

        var groups: [ActionExpr] = []
        var start = 0
        for splitIndex in orSplitIndices {
            if let group = foldAndGroup(Array(elements[start..<splitIndex]), symmetricCollections: symmetricCollections) {
                groups.append(group)
            }
            start = splitIndex + 1
        }
        if start < elements.count, let group = foldAndGroup(Array(elements[start...]), symmetricCollections: symmetricCollections) {
            groups.append(group)
        }

        guard !groups.isEmpty else { return nil }
        return groups.dropFirst().reduce(groups[0]) { .or($0, $1) }
    }

    /// Folds a sequence containing only && operators (or a single leaf) into an ActionExpr.
    private static func foldAndGroup(
        _ elements: [ExprSyntax],
        symmetricCollections: Set<String>
    ) -> ActionExpr? {
        guard elements.count >= 1 else { return nil }
        if elements.count == 1 { return parseLeafAsAction(elements[0], symmetricCollections: symmetricCollections) }

        var andSplitIndices: [Int] = []
        for index in stride(from: 1, to: elements.count, by: 2) {
            if elements[index].as(BinaryOperatorExprSyntax.self)?.operator.text == "&&" {
                andSplitIndices.append(index)
            }
        }

        if andSplitIndices.isEmpty {
            return parseAndLeaf(elements, symmetricCollections: symmetricCollections)
        }

        var leafActions: [ActionExpr] = []
        var start = 0
        for splitIndex in andSplitIndices {
            if let leaf = parseAndLeaf(Array(elements[start..<splitIndex]), symmetricCollections: symmetricCollections) {
                leafActions.append(leaf)
            }
            start = splitIndex + 1
        }
        if start < elements.count, let leaf = parseAndLeaf(Array(elements[start...]), symmetricCollections: symmetricCollections) {
            leafActions.append(leaf)
        }

        guard !leafActions.isEmpty else { return nil }
        return leafActions.dropFirst().reduce(leafActions[0]) { .and($0, $1) }
    }

    /// Parses a leaf slice (one or more ExprSyntax elements) as an action or guard.
    private static func parseAndLeaf(
        _ slice: [ExprSyntax],
        symmetricCollections: Set<String>
    ) -> ActionExpr? {
        if slice.count == 1 {
            return parseLeafAsAction(slice[0], symmetricCollections: symmetricCollections)
        }
        let source = slice.map { $0.description }.joined()
        guard let reconstructed = SwiftParser.Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self) else {
            return nil
        }
        return parseLeafAsAction(reconstructed, symmetricCollections: symmetricCollections)
    }

    /// Tries to parse a single expression as either an action or a guard (state expression).
    private static func parseLeafAsAction(
        _ expression: ExprSyntax,
        symmetricCollections: Set<String>
    ) -> ActionExpr? {
        if let action = parseSingleAction(expression, symmetricCollections: symmetricCollections) { return action }
        if let state = parseInvariantExpression(expression, symmetricCollections: symmetricCollections) { return .guard_(state) }
        return nil
    }

    // MARK: - Becomes chain (assignment with optional .when guards)

    private struct GuardedAssignment {
        let call: FunctionCallExprSyntax
        let condition: StateExpr?
    }

    /// Unwraps nested `.when(...)` calls from a `.becomes(...)` chain.
    /// `x.becomes(1).when(x < 5)` → call = `x.becomes(1)`, condition = `x < 5`
    private static func unwrapGuards(
        _ functionCall: FunctionCallExprSyntax,
        symmetricCollections: Set<String>
    ) -> GuardedAssignment {
        if let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "when",
           let innerCall = memberAccess.base?.as(FunctionCallExprSyntax.self) {
            let outerCondition = functionCall.arguments.first.flatMap {
                parseInvariantExpression($0.expression, symmetricCollections: symmetricCollections)
            }
            let inner = unwrapGuards(innerCall, symmetricCollections: symmetricCollections)
            if let outer = outerCondition, let innerCondition = inner.condition {
                return GuardedAssignment(call: inner.call, condition: .and(outer, innerCondition))
            }
            return GuardedAssignment(call: inner.call, condition: outerCondition ?? inner.condition)
        }
        return GuardedAssignment(call: functionCall, condition: nil)
    }

    /// Parses a `.becomes(...)` call (possibly wrapped in `.when(...)` chains).
    /// Detects whether the assignment is deterministic or nondeterministic (CHOOSE).
    private static func parseBecomesChain(
        _ functionCall: FunctionCallExprSyntax,
        symmetricCollections: Set<String>
    ) -> ActionExpr? {
        let guarded = unwrapGuards(functionCall, symmetricCollections: symmetricCollections)
        guard let (variableName, assignment) = parseBecomesArgument(guarded.call) else { return nil }

        let action: ActionExpr
        if case .choose(let chosenSet, _, _) = assignment {
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

    private enum TemporalMethod: String {
        case leadsTo
        case always
        case eventually
        case alwaysEventually
        case eventuallyAlways
    }

    public static func parseTemporal(_ expression: ExprSyntax) -> TemporalExpr? {
        guard let functionCall = expression.as(FunctionCallExprSyntax.self),
              let memberRef = functionCall.calledExpression.as(MemberAccessExprSyntax.self)
        else { return nil }

        let firstArgument = functionCall.arguments.first.flatMap { parseStateExpr($0.expression) }

        guard let method = TemporalMethod(rawValue: memberRef.declName.baseName.text) else { return nil }

        switch method {
        case .leadsTo:
            let source = parseStateExpr(memberRef.base) ?? .value(.bool(true))
            return firstArgument.map { .leadsTo(source, $0) }
        case .always:           return firstArgument.map { .always($0) }
        case .eventually:       return firstArgument.map { .eventually($0) }
        case .alwaysEventually:  return firstArgument.map { .alwaysEventually($0) }
        case .eventuallyAlways:  return firstArgument.map { .eventuallyAlways($0) }
        }
    }

    // MARK: - Fairness conditions

    private enum FairnessMethod: String {
        case weakFairness
        case strongFairness
    }

    public static func parseFairnessExpr(_ expression: ExprSyntax) -> FairnessCondition? {
        guard let functionCall = expression.as(FunctionCallExprSyntax.self),
              let memberRef = functionCall.calledExpression.as(MemberAccessExprSyntax.self)
        else { return nil }

        let name = functionCall.arguments.first?.expression
            .as(StringLiteralExprSyntax.self)?
            .segments.description
            .replacingOccurrences(of: "\"", with: "")
            ?? ""

        guard let method = FairnessMethod(rawValue: memberRef.declName.baseName.text) else { return nil }

        switch method {
        case .weakFairness:   return .weakFairness(name)
        case .strongFairness: return .strongFairness(name)
        }
    }

    // MARK: - Method calls on state expressions

    private enum StateMethod: String {
        case isIn
        case union
        case intersection
        case subtracting
        case isSubset
        case applying
        case filtering
        case mapping
        case appending
        case concatenating
        case integerDivided
        case updated
        case at
    }

    private static func parseMethodCall(_ functionCall: FunctionCallExprSyntax) -> StateExpr? {
        guard let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self)
        else { return nil }

        let methodName = memberAccess.declName.baseName.text
        let firstArgument = functionCall.arguments.first?.expression
        let baseExpression = memberAccess.base

        guard let method = StateMethod(rawValue: methodName) else {
            // Check for static StateExpr calls
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

        switch method {
        case .isIn:         return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .in($0, $1) })
        case .union:        return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .union($0, $1) })
        case .intersection:  return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .intersection($0, $1) })
        case .subtracting:  return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .setDifference($0, $1) })
        case .isSubset:     return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .subset($0, $1) })
        case .applying:     return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .functionApply($0, $1) })
        case .filtering:    return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .setFilter($0, .fresh(), $1) })
        case .mapping:      return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .setMap($1, .fresh(), $0) })
        case .appending:    return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .tupleAppend($0, $1) })
        case .concatenating: return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .tupleConcatenate($0, $1) })
        case .integerDivided: return parseBinaryMethod(base: baseExpression, argument: firstArgument, combine: { .integerDivide($0, $1) })
        case .updated:
            guard let baseExpression,
                  let selfExpr = parseStateExpr(baseExpression)
            else { return nil }
            let allArguments = Array(functionCall.arguments)
            guard allArguments.count >= 2,
                  let keyExpr = parseStateExpr(allArguments[0].expression),
                  let valueExpr = parseStateExpr(allArguments[1].expression)
            else { return nil }
            return .except(selfExpr, keyExpr, valueExpr)
        case .at:
            guard let baseExpression,
                  let selfExpr = parseStateExpr(baseExpression),
                  let index = functionCall.arguments.first?.expression
                    .as(IntegerLiteralExprSyntax.self)
                    .flatMap({ Int($0.literal.text) })
            else { return nil }
            return .tupleAccess(selfExpr, index)
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

    // MARK: - DSL dispatch tables

    private enum DSLStaticMethod: String, CaseIterable {
        case set, tuple, record, `if`, enabled, function, `for`, exists, choose, any, firstMatch, singleton, functionLiteral

        func build(_ args: [StateExpr]) -> StateExpr? {
            switch self {
            case .set:    return .setLiteral(args)
            case .tuple:  return .tupleLiteral(args)
            case .record: return nil  // labeled args, handled separately
            case .if:     return args.count >= 3 ? .ifThenElse(args[0], args[1], args[2]) : nil
            case .enabled: return nil  // string arg, handled separately
            case .function: return args.count >= 2 ? .functionLiteral(args[0], .fresh(), args[1]) : nil
            case .for:    return args.count >= 2 ? .forAll(args[0], .fresh(), args[1]) : nil
            case .exists: return args.count >= 2 ? .exists(args[0], .fresh(), args[1]) : nil
            case .choose: return args.count >= 2 ? .choose(args[0], .fresh(), args[1]) : nil
            case .any:    return args.count >= 1 ? .choose(args[0], .fresh(), .value(.bool(true))) : nil
            case .firstMatch: return nil  // tuple pairs, handled separately
            case .singleton: return args.count >= 1 ? .setLiteral(args) : nil
            case .functionLiteral: return args.count >= 2 ? .functionLiteral(args[0], .fresh(), args[1]) : nil
            }
        }
    }

    private enum DSLProperty: String, CaseIterable {
        case cardinality, flattened, subsets, domain, count, head, tail

        func build(_ expr: StateExpr) -> StateExpr {
            switch self {
            case .cardinality: return .cardinality(expr)
            case .flattened:   return .unionAll(expr)
            case .subsets:     return .powerSet(expr)
            case .domain:      return .domain(expr)
            case .count:       return .tupleLength(expr)
            case .head:        return .tupleHead(expr)
            case .tail:        return .tupleTail(expr)
            }
        }
    }

    // MARK: - Static calls on StateExpr

    /// Parses static method calls like `StateExpr.set([...])`, `StateExpr.choose(from:matching:)`, etc.
    private static func parseStaticCall(
        memberAccess: MemberAccessExprSyntax,
        arguments: [LabeledExprSyntax],
        method: String
    ) -> StateExpr? {
        guard let staticMethod = DSLStaticMethod(rawValue: method) else { return nil }

        switch staticMethod {
        case .set, .tuple, .singleton:
            let elements = arguments.first?.expression
                .as(ArrayExprSyntax.self)?.elements
                .compactMap { parseStateExpr($0.expression) }
                ?? (staticMethod == .singleton
                    ? [arguments.first.flatMap { parseStateExpr($0.expression) }].compactMap { $0 }
                    : [])
            return staticMethod == .set ? .setLiteral(elements)
                : staticMethod == .tuple ? .tupleLiteral(elements)
                : .setLiteral(elements)
        case .record:
            var fields: [String: StateExpr] = [:]
            for argument in arguments {
                guard let label = argument.label?.text,
                      let value = parseStateExpr(argument.expression)
                else { return nil }
                fields[label] = value
            }
            return .recordLiteral(fields)
        case .enabled:
            let actionName = arguments.first?.expression
                .as(StringLiteralExprSyntax.self)?
                .segments.description
                .replacingOccurrences(of: "\"", with: "")
                ?? ""
            return .enabledAction(actionName)
        case .firstMatch:
            var flatPairs: [StateExpr] = []
            var fallbackExpr: StateExpr?
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
        default:
            let exprs = arguments.compactMap { parseStateExpr($0.expression) }
            return staticMethod.build(exprs)
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

        if let property = DSLProperty(rawValue: propertyName) {
            return property.build(selfExpr)
        }
        return .recordAccess(selfExpr, propertyName)
    }

    // MARK: - Unified spec builder parser

    public struct ParsedSpecComponents {
        public var variables: [(name: String, initial: TLAValue, initialSet: StateExpr?, swiftTypeName: String?)] = []
        public var actions: [(name: String, body: ActionExpr)] = []
        public var symmetricCollections: [ParsedSymmetricCollection] = []
        public var collectionActions: [ParsedCollectionAction] = []
        public var diagnostics: [SymmetricCollectionParseDiagnostic] = []
        public var invariants: [(name: String, body: StateExpr)] = []
        public var temporal: [(name: String, expr: TemporalExpr)] = []
        public var fairness: [FairnessCondition] = []
        public var constants: [String: TLAValue] = [:]
        /// Local named values (from NamedValue declarations, resolved in expressions)
        public var localConstants: [String: TLAValue] = [:]
    }

    public struct ParsedSymmetricCollection {
        public let name: String
        public let elementType: String
        public let valueType: String
        public let verificationScope: Int
        public let source: String
        public let declaration: SymmetricCollectionDecl
    }

    public struct ParsedCollectionAction {
        public struct RuntimeBranch {
            public let guardExpressions: [String]
            public let updateExpression: String?
        }

        public let name: String
        public let collectionName: String
        public let body: ActionExpr
        public let runtimeBranches: [RuntimeBranch]
        public let source: String
    }

    public struct SymmetricCollectionParseDiagnostic: Error, CustomStringConvertible {
        public let message: String
        public let source: String
        public let sourceOffset: Int?

        public init(message: String, source: String, sourceOffset: Int? = nil) {
            self.message = message
            self.source = source
            self.sourceOffset = sourceOffset
        }

        public init<Node: SyntaxProtocol>(message: String, source: Node) {
            self.init(
                message: message,
                source: source.description,
                sourceOffset: source.positionAfterSkippingLeadingTrivia.utf8Offset
            )
        }

        public var description: String { message }
    }

      public static func parseSpecClosure(_ closure: ClosureExprSyntax) -> ParsedSpecComponents {
        var result = ParsedSpecComponents()
        let collectionTypes = collectSymmetricCollectionTypes(in: closure)
        for statement in closure.statements {
            if case .expr(let expression) = statement.item,
               let fc = expression.as(FunctionCallExprSyntax.self) {
                parseBuilderCall(fc, into: &result, collectionTypes: collectionTypes)
            } else if let forStmt = statement.item.as(ForStmtSyntax.self) {
                parseForLoop(forStmt, into: &result)
            } else if case .decl(let decl) = statement.item,
                      let varDecl = decl.as(VariableDeclSyntax.self) {
                parseStateVarDecl(varDecl, into: &result)
            }
        }
        return result
    }

    private static func parseForLoop(_ forStmt: ForStmtSyntax, into result: inout ParsedSpecComponents) {
        guard let pattern = forStmt.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let sequence = forStmt.sequence.as(SequenceExprSyntax.self)
        else { return }

        // Extract range: 1...N → start=1, end=N (from literal or variable)
        let elements = Array(sequence.elements)
        guard elements.count == 3 else { return }

        // Evaluate start and end from sibling expressions
        var start = 1, end = 3
        if let startExpr = elements[0].as(IntegerLiteralExprSyntax.self) {
            start = Int(startExpr.literal.text) ?? 1
        }
        if let endExpr = elements[2].as(IntegerLiteralExprSyntax.self) {
            end = Int(endExpr.literal.text) ?? 3
        }

        let body = forStmt.body.statements
        for i in start...end {
            for bodyStmt in body {
                guard case .expr(let expr) = bodyStmt.item,
                      let fc = expr.as(FunctionCallExprSyntax.self)
                else { continue }
                parseBuilderCall(fc, into: &result, loopVar: pattern, loopValue: i)
            }
        }
    }

    /// Parses `let x = StateVar(...)` bindings into `ParsedSpecComponents.variables`.
    /// Handles both raw `StateVar(0)` and rewrites where ModelMacro injected a string name.
    private static func parseStateVarDecl(_ varDecl: VariableDeclSyntax, into result: inout ParsedSpecComponents) {
        for binding in varDecl.bindings {
            guard let patternName = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let initializer = binding.initializer?.value,
                  let fc = initializer.as(FunctionCallExprSyntax.self),
                  let calledName = fc.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
                  calledName == "StateVar"
            else { continue }

            let args = Array(fc.arguments)

            if let rangeExpr = args.first(where: { $0.label?.text == "in" })?.expression {
                let lowerBound = parseRangeLowerBound(rangeExpr)
                result.variables.append((patternName, .int(lowerBound), nil, nil))
                continue
            }

            if let valuesArg = args.first(where: { $0.label?.text == "values" })?.expression {
                let firstValue = parseValuesFirst(valuesArg)
                result.variables.append((patternName, .string(firstValue), nil, nil))
                continue
            }

            guard !args.isEmpty else { continue }

            if let stringLit = args[0].expression.as(StringLiteralExprSyntax.self) {
                let varName = stringLit.segments.description.replacingOccurrences(of: "\"", with: "")
                let initial: TLAValue = args.count >= 2 ? parseInitialExpr(args[1].expression) : .int(0)
                let typeName = args.count >= 2 ? enumCaseTypeName(from: args[1].expression) : nil
                result.variables.append((varName, initial, nil, typeName))
            } else {
                let initial: TLAValue = parseInitialExpr(args[0].expression)
                let typeName = enumCaseTypeName(from: args[0].expression)
                result.variables.append((patternName, initial, nil, typeName))
            }
        }
    }

    /// Extracts the lower bound from a range expression like `1...12`.
    private static func parseRangeLowerBound(_ expression: ExprSyntax) -> Int {
        if let seq = expression.as(SequenceExprSyntax.self) {
            let elements = Array(seq.elements)
            if let firstInt = elements.first?.as(IntegerLiteralExprSyntax.self),
               let lower = Int(firstInt.literal.text) {
                return lower
            }
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let firstInt = infix.leftOperand.as(IntegerLiteralExprSyntax.self),
           let lower = Int(firstInt.literal.text) {
            return lower
        }
        return 0
    }

    /// Extracts the first string value from `["a", "b"]`.
    private static func parseValuesFirst(_ expression: ExprSyntax) -> String {
        if let array = expression.as(ArrayExprSyntax.self),
           let first = array.elements.first?.expression.as(StringLiteralExprSyntax.self) {
            return first.segments.description.replacingOccurrences(of: "\"", with: "")
        }
        return ""
    }

    /// Converts a Swift initializer expression to a TLAValue.
    private static func parseInitialExpr(_ expression: ExprSyntax) -> TLAValue {
        if let intVal = expression.as(IntegerLiteralExprSyntax.self) {
            return .int(Int(intVal.literal.text) ?? 0)
        }
        if let boolVal = expression.as(BooleanLiteralExprSyntax.self) {
            return .bool(boolVal.literal.text == "true")
        }
        if let stringLit = expression.as(StringLiteralExprSyntax.self) {
            return .string(stringLit.segments.description.replacingOccurrences(of: "\"", with: ""))
        }
        if let fc = expression.as(FunctionCallExprSyntax.self),
           let memberAccess = fc.calledExpression.as(MemberAccessExprSyntax.self),
           let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text == "TLAValue" {
            return parseTLAValueConstructor(name: memberAccess.declName.baseName.text, call: fc) ?? .int(0)
        }
        return .int(0)
    }

    /// Returns the enum type name if `expression` is an enum case reference.
    /// `.idle` → `nil` (implicit member, type unknown from this AST).
    /// `CameraMode.idle` → `"CameraMode"` (explicit member, type known).
    private static func enumCaseTypeName(from expression: ExprSyntax) -> String? {
        guard let memberAccess = expression.as(MemberAccessExprSyntax.self) else { return nil }
        if let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
            return base.baseName.text
        }
        return nil
    }

    private static func parseBuilderCall(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents,
        loopVar: String? = nil,
        loopValue: Int? = nil,
        collectionTypes: [String: (element: String, value: String)] = [:]
    ) {
        guard let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text else { return }

        switch name {
        case "SymmetricCollection":
            parseSymmetricCollectionDecl(call, into: &result, collectionTypes: collectionTypes)
        case "CollectionAction":
            parseCollectionAction(call, into: &result)
        case "Variable":
            parseVariableDecl(call, into: &result)
        case "Action":
            if let actionName = extractStringArg(call, index: 0, loopVar: loopVar, loopValue: loopValue),
                let body = call.trailingClosure.flatMap({
                    parseActionFrom(
                        $0,
                        symmetricCollections: Set(result.symmetricCollections.map(\.name))
                    )
                }) {
                result.actions.append((actionName, body))
            } else if let actionName = extractStringArg(call, index: 0, loopVar: loopVar, loopValue: loopValue),
                      let closure = call.trailingClosure {
                result.diagnostics.append(.init(
                    message: "Action '\(actionName)' contains an unsupported action expression.",
                    source: closure
                ))
            }
        case "Invariant":
            parseInvariant(call, into: &result)
        case "Constant":
            parseConstantDecl(call, into: &result)
        case "LeadsTo", "Eventually", "Always", "AlwaysEventually", "EventuallyAlways":
            if let expr = parseTemporal(ExprSyntax(call)) {
                result.temporal.append((name, expr))
            }
        case "WeakFairness", "StrongFairness":
            if let fc = parseFairnessExpr(ExprSyntax(call)) {
                result.fairness.append(fc)
            }
        case "Value":
            if let name = extractStringArg(call, index: 0),
               parseNamedValueConstant(call, name: name, into: &result) { }
        case "UseSpec":
            if let name = extractStringArg(call, index: 0),
               let spec = SpecRegistry.lookup(name) {
                result.variables += spec.variables.map { (name: $0.name, initial: $0.initial, initialSet: $0.initialSet, swiftTypeName: nil) }
                result.invariants += spec.invariants.map { (name: $0.name, body: $0.body) }
                result.actions += spec.actions.map { (name: $0.name, body: $0.body) }
            }
        default:
            break
        }
    }

    private static func parseInvariant(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        guard let name = extractStringArg(call, index: 0), let closure = call.trailingClosure else {
            result.diagnostics.append(.init(
                message: "Invariant declaration requires a name and a supported invariant expression.",
                source: call.description
            ))
            return
        }
        guard let body = parseInvariantBody(
            closure,
            symmetricCollections: Set(result.symmetricCollections.map(\.name))
        ) else {
            let unsupported = unsupportedInvariantExpression(
                in: closure,
                symmetricCollections: Set(result.symmetricCollections.map(\.name))
            )
            if let unsupported {
                result.diagnostics.append(.init(
                    message: "Invariant '\(name)' contains an unsupported invariant expression.",
                    source: unsupported
                ))
            } else {
                result.diagnostics.append(.init(
                    message: "Invariant '\(name)' contains an unsupported invariant expression.",
                    source: closure
                ))
            }
            return
        }
        result.invariants.append((name, body))
    }

    private static func parseInvariantBody(
        _ closure: ClosureExprSyntax,
        symmetricCollections: Set<String>
    ) -> StateExpr? {
        var expressions: [StateExpr] = []
        for statement in closure.statements {
            guard case .expr(let expression) = statement.item,
                  let parsed = parseInvariantExpression(
                    expression,
                    symmetricCollections: symmetricCollections
                  )
            else { return nil }
            expressions.append(parsed)
        }
        guard let first = expressions.first else { return nil }
        return expressions.dropFirst().reduce(first, StateExpr.and)
    }

    private static func unsupportedInvariantExpression(
        in closure: ClosureExprSyntax,
        symmetricCollections: Set<String>
    ) -> ExprSyntax? {
        for statement in closure.statements {
            guard case .expr(let expression) = statement.item else { continue }
            if parseInvariantExpression(expression, symmetricCollections: symmetricCollections) == nil {
                return expression
            }
        }
        return nil
    }

    private static func parseInvariantExpression(
        _ expression: ExprSyntax,
        symmetricCollections: Set<String>
    ) -> StateExpr? {
        if let predicate = parseCollectionPredicate(
            expression,
            symmetricCollections: symmetricCollections
        ) {
            return predicate
        }
        if let tuple = expression.as(TupleExprSyntax.self),
           tuple.elements.count == 1,
           let nested = tuple.elements.first?.expression {
            return parseInvariantExpression(nested, symmetricCollections: symmetricCollections)
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let operatorText = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text,
           let left = parseInvariantExpression(infix.leftOperand, symmetricCollections: symmetricCollections),
           let right = parseInvariantExpression(infix.rightOperand, symmetricCollections: symmetricCollections) {
            return parseInfixOperation(
                leftOperand: left,
                rightOperand: right,
                operatorText: operatorText
            )
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            return parseInvariantSequence(Array(sequence.elements), symmetricCollections: symmetricCollections)
        }
        return parseStateExpr(expression)
    }

    private static func parseInvariantSequence(
        _ elements: [ExprSyntax],
        symmetricCollections: Set<String>
    ) -> StateExpr? {
        guard elements.count >= 3, elements.count % 2 == 1 else { return nil }
        let operatorIndices = Array(stride(from: 1, to: elements.count, by: 2))
        let splitIndex = operatorIndices.first {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "||"
        } ?? operatorIndices.first {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "&&"
        } ?? operatorIndices.first
        guard let splitIndex,
              let operatorText = elements[splitIndex].as(BinaryOperatorExprSyntax.self)?.operator.text,
              let left = parseInvariantElements(
                Array(elements[0..<splitIndex]),
                symmetricCollections: symmetricCollections
              ),
              let right = parseInvariantElements(
                Array(elements[(splitIndex + 1)..<elements.count]),
                symmetricCollections: symmetricCollections
              )
        else { return nil }
        return parseInfixOperation(leftOperand: left, rightOperand: right, operatorText: operatorText)
    }

    private static func parseInvariantElements(
        _ elements: [ExprSyntax],
        symmetricCollections: Set<String>
    ) -> StateExpr? {
        if elements.count == 1 {
            return parseInvariantExpression(elements[0], symmetricCollections: symmetricCollections)
        }
        return parseInvariantSequence(elements, symmetricCollections: symmetricCollections)
    }

    private static func parseCollectionPredicate(
        _ expression: ExprSyntax,
        symmetricCollections: Set<String>
    ) -> StateExpr? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let access = call.calledExpression.as(MemberAccessExprSyntax.self),
              let collection = access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
              symmetricCollections.contains(collection),
              let kind = CollectionPredicate(rawValue: access.declName.baseName.text),
              let closure = call.trailingClosure
                ?? call.arguments.first?.expression.as(ClosureExprSyntax.self),
              let parameter = collectionPredicateParameter(in: closure)
        else { return nil }

        let member = QuantVar.fresh()
        let rewrittenStatements = closure.statements.map { statement in
            PredicateValueRewriter(
                parameter: parameter,
                replacement: "\(collection).applying(\(member.name))"
            ).visit(statement)
        }
        let rewrittenClosure = closure.with(\.statements, CodeBlockItemListSyntax(rewrittenStatements))
        guard let body = parseInvariantBody(
            rewrittenClosure,
            symmetricCollections: symmetricCollections
        ) else { return nil }

        let domain = StateExpr.domain(.variable(collection))
        switch kind {
        case .allSatisfy: return .forAll(domain, member, body)
        case .contains: return .exists(domain, member, body)
        }
    }

    private static func collectionPredicateParameter(in closure: ClosureExprSyntax) -> String? {
        guard let parameters = closure.signature?.parameterClause else { return "$0" }
        switch parameters {
        case .simpleInput(let list):
            guard list.count == 1 else { return nil }
            return list.first?.name.text
        case .parameterClause(let clause):
            guard clause.parameters.count == 1, let parameter = clause.parameters.first else { return nil }
            return parameter.secondName?.text ?? parameter.firstName.text
        }
    }

    private enum CollectionPredicate: String {
        case allSatisfy
        case contains
    }

    private final class PredicateValueRewriter: SyntaxRewriter {
        let parameter: String
        let replacement: String
        var closureDepth = 0

        init(parameter: String, replacement: String) {
            self.parameter = parameter
            self.replacement = replacement
        }

        override func visit(_ node: ClosureExprSyntax) -> ExprSyntax {
            if closureDepth > 0, collectionPredicateParameter(in: node) == parameter {
                return ExprSyntax(node)
            }
            closureDepth += 1
            defer { closureDepth -= 1 }
            return super.visit(node)
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
            guard node.baseName.text == parameter else { return super.visit(node) }
            return ExprSyntax(stringLiteral: replacement)
        }
    }

    private static func collectSymmetricCollectionTypes(
        in closure: ClosureExprSyntax
    ) -> [String: (element: String, value: String)] {
        var types: [String: (element: String, value: String)] = [:]
        for statement in closure.statements {
            guard case .decl(let declaration) = statement.item,
                  let variable = declaration.as(VariableDeclSyntax.self)
            else { continue }
            for binding in variable.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                      let specialization = call.calledExpression.as(GenericSpecializationExprSyntax.self),
                      specialization.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == "SymmetricCollectionVar"
                else { continue }
                let arguments = Array(specialization.genericArgumentClause.arguments)
                guard arguments.count == 2 else { continue }
                types[name] = (
                    arguments[0].argument.description.trimmingCharacters(in: .whitespacesAndNewlines),
                    arguments[1].argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
        return types
    }

    private static func parseSymmetricCollectionDecl(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents,
        collectionTypes: [String: (element: String, value: String)]
    ) {
        let arguments = Array(call.arguments)
        guard let collectionName = arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let types = collectionTypes[collectionName],
              let scopeArgument = arguments.first(where: { $0.label?.text == "verificationScope" })?.expression,
              let scopeLiteral = scopeArgument.as(IntegerLiteralExprSyntax.self),
              let scope = Int(scopeLiteral.literal.text),
              let initialExpression = arguments.first(where: { $0.label?.text == "initial" })?.expression,
              let initial = parseLiteralValue(initialExpression)
        else {
            result.diagnostics.append(.init(
                message: "Symmetric collections require SymmetricCollectionVar<Element, Value>, "
                    + "a positive integer literal scope, and a literal uniform initial value.",
                source: call.description
            ))
            return
        }

        let declaration = SymmetricCollectionDecl(name: collectionName, verificationScope: scope, initial: initial)
        result.symmetricCollections.append(.init(
            name: collectionName,
            elementType: types.element,
            valueType: types.value,
            verificationScope: scope,
            source: call.description,
            declaration: declaration
        ))
        result.variables.append((collectionName, declaration.variable.initial, nil, nil))
    }

    private static func parseCollectionAction(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        let arguments = Array(call.arguments)
        guard let actionName = extractStringArg(call, index: 0),
              let collectionName = arguments.first(where: { $0.label?.text == "on" })?.expression
                .as(DeclReferenceExprSyntax.self)?.baseName.text,
              let closure = call.trailingClosure
        else { return }

        guard let memberName = collectionActionMemberName(in: closure) else {
            result.diagnostics.append(.init(
                message: "Collection action '\(actionName)' requires one named opaque member parameter.",
                source: closure.description
            ))
            return
        }
        let member = QuantVar.fresh()
        let diagnosticCount = result.diagnostics.count
        validateMemberUses(
            memberName,
            in: closure,
            owning: collectionName,
            action: actionName,
            into: &result
        )
        guard let actionBody = parseCollectionActionBody(
            closure,
            collection: collectionName,
            member: memberName,
            binding: member.name
        ) else {
            if result.diagnostics.count == diagnosticCount {
                result.diagnostics.append(.init(
                    message: "Collection action '\(actionName)' contains an unsupported action expression.",
                    source: closure.description
                ))
            }
            return
        }
        result.collectionActions.append(.init(
            name: actionName,
            collectionName: collectionName,
            body: .existsAction(member.name, .domain(.variable(collectionName)), actionBody),
            runtimeBranches: runtimeBranches(
                in: closure,
                collection: collectionName,
                member: memberName,
                runtimeVariables: Set(result.variables.map(\.name))
            ),
            source: call.description
        ))
        result.actions.append((actionName, .existsAction(
            member.name,
            .domain(.variable(collectionName)),
            actionBody
        )))
    }

    private static func collectionActionMemberName(in closure: ClosureExprSyntax) -> String? {
        guard let parameters = closure.signature?.parameterClause else { return nil }
        switch parameters {
        case .simpleInput(let list):
            return list.first?.name.text
        case .parameterClause(let clause):
            guard let parameter = clause.parameters.first else { return nil }
            return parameter.secondName?.text ?? parameter.firstName.text
        }
    }

    private static func validateMemberUses(
        _ member: String,
        in closure: ClosureExprSyntax,
        owning collection: String,
        action: String,
        into result: inout ParsedSpecComponents
    ) {
        let validator = CollectionMemberUseValidator(member: member, collection: collection)
        validator.walk(Syntax(closure))
        for violation in validator.violations {
            result.diagnostics.append(identityDiagnostic(
                collection: collection, action: action, source: violation.source,
                detail: violation.detail
            ))
        }
    }

    private static func identityDiagnostic(
        collection: String,
        action: String,
        source: String,
        detail: String
    ) -> SymmetricCollectionParseDiagnostic {
        .init(
            message: "\(detail) for symmetric collection '\(collection)' in action '\(action)': "
                + "member identity is opaque and may only select or update its owning collection. "
                + "Model the distinction as member state or use a non-symmetric collection.",
            source: source
        )
    }

    private static func parseCollectionActionBody(
        _ closure: ClosureExprSyntax,
        collection: String,
        member: String,
        binding: String
    ) -> ActionExpr? {
        let actions = closure.statements.compactMap { statement -> ActionExpr? in
            guard case .expr(let expression) = statement.item else { return nil }
            return parseCollectionActionExpression(
                expression,
                collection: collection,
                member: member,
                binding: binding
            )
        }
        guard !actions.isEmpty else { return nil }
        return actions.dropFirst().reduce(actions[0]) { .and($0, $1) }
    }

    private static func parseCollectionActionExpression(
        _ expression: ExprSyntax,
        collection: String,
        member: String,
        binding: String
    ) -> ActionExpr? {
        if let tuple = expression.as(TupleExprSyntax.self),
           tuple.elements.count == 1,
           let nested = tuple.elements.first?.expression {
            return parseCollectionActionExpression(
                nested,
                collection: collection,
                member: member,
                binding: binding
            )
        }
        if let sequence = expression.as(SequenceExprSyntax.self),
           let split = collectionActionSequenceSplit(Array(sequence.elements)) {
            let left = parseCollectionActionExpression(
                split.left,
                collection: collection,
                member: member,
                binding: binding
            )
            let right = parseCollectionActionExpression(
                split.right,
                collection: collection,
                member: member,
                binding: binding
            )
            guard let left, let right else { return nil }
            return split.operatorText == "&&" ? .and(left, right) : .or(left, right)
        }
        if let update = collectionUpdate(expression, collection: collection, member: member) {
            let rewritten = CollectionReadRewriter(
                collection: collection,
                member: member,
                replacement: binding
            ).visit(update.expression)
            guard let value = parseStateExpr(rewritten) else { return nil }
            return .assign(collection, .except(.variable(collection), .variable(binding), value))
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let op = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text,
           let left = parseCollectionActionExpression(infix.leftOperand, collection: collection, member: member, binding: binding),
           let right = parseCollectionActionExpression(infix.rightOperand, collection: collection, member: member, binding: binding) {
            if op == "&&" { return .and(left, right) }
            if op == "||" { return .or(left, right) }
        }
        let rewritten = CollectionReadRewriter(
            collection: collection,
            member: member,
            replacement: binding
        ).visit(expression)
        return parseStateExpr(rewritten).map(ActionExpr.guard_)
    }

    private static func collectionActionSequenceSplit(
        _ elements: [ExprSyntax]
    ) -> (left: ExprSyntax, operatorText: String, right: ExprSyntax)? {
        guard elements.count >= 3, elements.count % 2 == 1 else { return nil }
        let operators = stride(from: 1, to: elements.count, by: 2)
        let splitIndex = operators.first {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "||"
        } ?? operators.first {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "&&"
        }
        guard let splitIndex,
              let operatorText = elements[splitIndex].as(BinaryOperatorExprSyntax.self)?.operator.text,
              let left = parseExpression(elements[0..<splitIndex]),
              let right = parseExpression(elements[(splitIndex + 1)..<elements.count])
        else { return nil }
        return (left, operatorText, right)
    }

    private static func parseExpression(_ elements: ArraySlice<ExprSyntax>) -> ExprSyntax? {
        let source = elements.map(\.description).joined()
        return SwiftParser.Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self)
    }

    private static func collectionUpdate(
        _ expression: ExprSyntax,
        collection: String,
        member: String
    ) -> LabeledExprSyntax? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let access = call.calledExpression.as(MemberAccessExprSyntax.self),
              access.declName.baseName.text == "update",
              access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == collection,
              let selector = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
              selector.baseName.text == member
        else { return nil }
        return call.arguments.first(where: { $0.label?.text == "to" })
    }

    private static func runtimeBranches(
        in closure: ClosureExprSyntax,
        collection: String,
        member: String,
        runtimeVariables: Set<String>
    ) -> [ParsedCollectionAction.RuntimeBranch] {
        let expressions = closure.statements.compactMap { statement -> ExprSyntax? in
            guard case .expr(let expression) = statement.item else { return nil }
            return expression
        }
        guard let first = expressions.first else { return [] }
        return expressions.dropFirst().reduce(
            runtimeBranches(
                for: first,
                collection: collection,
                member: member,
                runtimeVariables: runtimeVariables
            )
        ) { partial, expression in
            combineRuntimeBranches(
                partial,
                runtimeBranches(
                    for: expression,
                    collection: collection,
                    member: member,
                    runtimeVariables: runtimeVariables
                )
            )
        }
    }

    private static func runtimeBranches(
        for expression: ExprSyntax,
        collection: String,
        member: String,
        runtimeVariables: Set<String>
    ) -> [ParsedCollectionAction.RuntimeBranch] {
        if let tuple = expression.as(TupleExprSyntax.self),
           tuple.elements.count == 1,
           let nested = tuple.elements.first?.expression {
            return runtimeBranches(
                for: nested,
                collection: collection,
                member: member,
                runtimeVariables: runtimeVariables
            )
        }
        if let sequence = expression.as(SequenceExprSyntax.self),
           let split = collectionActionSequenceSplit(Array(sequence.elements)) {
            let left = runtimeBranches(
                for: split.left,
                collection: collection,
                member: member,
                runtimeVariables: runtimeVariables
            )
            let right = runtimeBranches(
                for: split.right,
                collection: collection,
                member: member,
                runtimeVariables: runtimeVariables
            )
            return split.operatorText == "&&"
                ? combineRuntimeBranches(left, right)
                : left + right
        }
        if let update = collectionUpdate(expression, collection: collection, member: member) {
            let runtimeUpdate = CollectionReadRewriter(
                collection: collection,
                member: member,
                replacement: "entry.value",
                asStateExpression: false,
                runtimeVariables: runtimeVariables
            ).visit(update.expression).formatted().description
            return [.init(guardExpressions: [], updateExpression: runtimeUpdate)]
        }
        let runtimeGuard = CollectionRuntimeGuardRewriter(
            collection: collection,
            member: member,
            runtimeVariables: runtimeVariables
        ).visit(expression).formatted().description
        return [.init(guardExpressions: [runtimeGuard], updateExpression: nil)]
    }

    private static func combineRuntimeBranches(
        _ left: [ParsedCollectionAction.RuntimeBranch],
        _ right: [ParsedCollectionAction.RuntimeBranch]
    ) -> [ParsedCollectionAction.RuntimeBranch] {
        left.flatMap { lhs in
            right.compactMap { rhs in
                guard lhs.updateExpression == nil || rhs.updateExpression == nil else { return nil }
                return .init(
                    guardExpressions: lhs.guardExpressions + rhs.guardExpressions,
                    updateExpression: lhs.updateExpression ?? rhs.updateExpression
                )
            }
        }
    }

    private final class CollectionRuntimeGuardRewriter: SyntaxRewriter {
        let collection: String
        let member: String
        let runtimeVariables: Set<String>

        init(collection: String, member: String, runtimeVariables: Set<String>) {
            self.collection = collection
            self.member = member
            self.runtimeVariables = runtimeVariables
        }

        override func visit(_ node: SubscriptCallExprSyntax) -> ExprSyntax {
            guard node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == collection,
                  node.arguments.count == 1,
                  node.arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == member
            else { return super.visit(node) }
            return ExprSyntax(stringLiteral: "(entry.value)")
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
            guard runtimeVariables.contains(node.baseName.text) else { return super.visit(node) }
            return ExprSyntax(stringLiteral: "_state.\(node.baseName.text)")
        }
    }

    private final class CollectionReadRewriter: SyntaxRewriter {
        let collection: String
        let member: String
        let replacement: String
        let asStateExpression: Bool
        let runtimeVariables: Set<String>

        init(
            collection: String,
            member: String,
            replacement: String,
            asStateExpression: Bool = true,
            runtimeVariables: Set<String> = []
        ) {
            self.collection = collection
            self.member = member
            self.replacement = replacement
            self.asStateExpression = asStateExpression
            self.runtimeVariables = runtimeVariables
        }

        override func visit(_ node: SubscriptCallExprSyntax) -> ExprSyntax {
            guard node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == collection,
                  node.arguments.count == 1,
                  node.arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == member
            else { return super.visit(node) }
            if asStateExpression {
                return ExprSyntax(stringLiteral: "\(collection).applying(\(replacement))")
            }
            return ExprSyntax(stringLiteral: "(\(replacement)) ")
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
            guard !asStateExpression, runtimeVariables.contains(node.baseName.text)
            else { return super.visit(node) }
            return ExprSyntax(stringLiteral: "_state.\(node.baseName.text)")
        }
    }

    private final class CollectionMemberUseValidator: SyntaxVisitor {
        struct Violation {
            let detail: String
            let source: String
        }

        let member: String
        let collection: String
        var closureDepth = 0
        var permittedMemberOffsets: Set<Int> = []
        var violations: [Violation] = []

        init(member: String, collection: String) {
            self.member = member
            self.collection = collection
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
            closureDepth += 1
            return .visitChildren
        }

        override func visitPost(_ node: ClosureExprSyntax) {
            closureDepth -= 1
        }

        override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
            if node.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == collection,
               node.declName.baseName.text == "domain" {
                violations.append(.init(
                    detail: "Raw verification-domain access is unavailable",
                    source: node.description
                ))
            }
            return .visitChildren
        }

        override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
            if node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == collection,
               let selector = node.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
               node.arguments.count == 1,
               selector.baseName.text == member {
                permittedMemberOffsets.insert(selector.positionAfterSkippingLeadingTrivia.utf8Offset)
            }
            return .visitChildren
        }

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            if let access = node.calledExpression.as(MemberAccessExprSyntax.self),
               access.declName.baseName.text == "update",
               let selector = node.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
               selector.baseName.text == member {
                permittedMemberOffsets.insert(selector.positionAfterSkippingLeadingTrivia.utf8Offset)
                if let target = access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
                   target != collection {
                    violations.append(.init(
                        detail: "Cross-collection member use is unavailable (including '\(target)')",
                        source: node.description
                    ))
                }
            }
            return .visitChildren
        }

        override func visit(_ node: ExpressionSegmentSyntax) -> SyntaxVisitorContinueKind {
            if let expression = node.expressions.first?.expression.as(DeclReferenceExprSyntax.self),
               expression.baseName.text == member {
                violations.append(.init(
                    detail: "String interpolation of a member token is unavailable",
                    source: node.description
                ))
            }
            return .visitChildren
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            guard node.baseName.text == member else { return .visitChildren }
            if closureDepth > 1 {
                violations.append(.init(
                    detail: "Capturing a member token in a nested closure is unavailable",
                    source: node.description
                ))
            } else if !permittedMemberOffsets.contains(node.positionAfterSkippingLeadingTrivia.utf8Offset) {
                violations.append(.init(
                    detail: "Member identity observation or cross-collection use is unavailable",
                    source: node.description
                ))
            }
            return .visitChildren
        }
    }

    private static func parseLiteralValue(_ expression: ExprSyntax) -> TLAValue? {
        if let integer = expression.as(IntegerLiteralExprSyntax.self) {
            return Int(integer.literal.text).map(TLAValue.int)
        }
        if let boolean = expression.as(BooleanLiteralExprSyntax.self) {
            return .bool(boolean.literal.text == "true")
        }
        if let string = expression.as(StringLiteralExprSyntax.self) {
            return .string(string.segments.description.replacingOccurrences(of: "\"", with: ""))
        }
        return nil
    }

    private static func extractStringArg(
        _ call: FunctionCallExprSyntax,
        index: Int,
        loopVar: String? = nil,
        loopValue: Int? = nil
    ) -> String? {
        let args = Array(call.arguments)
        guard index < args.count else { return nil }
        guard let stringLit = args[index].expression.as(StringLiteralExprSyntax.self) else { return nil }

        // Build string from segments, substituting loop variable
        var result = ""
        for segment in stringLit.segments {
            if let text = segment.as(StringSegmentSyntax.self)?.content.text {
                result += text
            } else if let expr = segment.as(ExpressionSegmentSyntax.self),
                      let loopVar, let loopValue,
                      let expr0 = expr.expressions.first?.expression,
                      let declRef = expr0.as(DeclReferenceExprSyntax.self),
                      declRef.baseName.text == loopVar {
                result += "\(loopValue)"
            }
        }
        return result
    }

    private static func parseVariableDecl(_ call: FunctionCallExprSyntax, into result: inout ParsedSpecComponents) {
        let args = Array(call.arguments)
        guard let firstName = args.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text
            ?? args.first?.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
        else { return }

        // Variable(name, in: set)
        if args.count >= 2 {
            let label = args[1].label?.text
            if label == "in" {
                if let setExpr = parseStateExpr(args[1].expression) {
                    result.variables.append((firstName, .set([]), setExpr, nil))
                    return
                }
            }
        }

        // Variable(name, value)
        if args.count >= 2 {
            let valExpr = args[1].expression
            if let intVal = valExpr.as(IntegerLiteralExprSyntax.self) {
                result.variables.append((firstName, .int(Int(intVal.literal.text) ?? 0), nil, nil))
                return
            }
            if let boolVal = valExpr.as(BooleanLiteralExprSyntax.self) {
                result.variables.append((firstName, .bool(boolVal.literal.text == "true"), nil, nil))
                return
            }
            // TLAValue.set([]), TLAValue.tuple([]), etc.
            if let fc = valExpr.as(FunctionCallExprSyntax.self),
               let memberAccess = fc.calledExpression.as(MemberAccessExprSyntax.self),
               let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
               base.baseName.text == "TLAValue" {
                let name = memberAccess.declName.baseName.text
                if let parsed = parseTLAValueConstructor(name: name, call: fc) {
                    result.variables.append((firstName, parsed, nil, nil))
                    return
                }
            }
        }

        // Variable(name, initializerExpr) — fallback
        if args.count >= 2 {
            let initial: TLAValue = .int(0)
            result.variables.append((firstName, initial, nil, nil))
        }
    }

    private static func parseTLAValueConstructor(name: String, call: FunctionCallExprSyntax) -> TLAValue? {
        switch name {
        case "set":     return .set([])
        case "tuple":   return .tuple([])
        case "record":  return .record([:])
        case "function": return .function([:])
        default:        return nil
        }
    }

    private static func parseConstantDecl(_ call: FunctionCallExprSyntax, into result: inout ParsedSpecComponents) {
        let args = Array(call.arguments)
        guard args.count >= 2,
              let name = extractStringArg(call, index: 0)
        else { return }
        if let intVal = args[1].expression.as(IntegerLiteralExprSyntax.self) {
            result.constants[name] = .int(Int(intVal.literal.text) ?? 0)
        } else if let boolVal = args[1].expression.as(BooleanLiteralExprSyntax.self) {
            result.constants[name] = .bool(boolVal.literal.text == "true")
        } else if args[1].expression.as(StringLiteralExprSyntax.self) != nil {
            result.constants[name] = .string(extractStringArg(call, index: 1) ?? "")
        }
    }

    /// Parse `NamedValue("poweredOn", 5)` → register in localConstants
    private static func parseNamedValueConstant(_ call: FunctionCallExprSyntax, name: String, into result: inout ParsedSpecComponents) -> Bool {
        let args = Array(call.arguments)
        guard args.count >= 2 else { return false }
        if let intVal = args[1].expression.as(IntegerLiteralExprSyntax.self), let v = Int(intVal.literal.text) {
            result.localConstants[name] = .int(v); return true
        }
        if let boolVal = args[1].expression.as(BooleanLiteralExprSyntax.self) {
            result.localConstants[name] = .bool(boolVal.literal.text == "true"); return true
        }
        return false
    }
}
