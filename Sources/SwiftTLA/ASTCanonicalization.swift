func alphaKey(_ action: ActionExpr) -> String {
    alphaKey(action, bindingNames: [])
}

func alphaKey(_ action: ActionExpr, bindingNames: [String]) -> String {
    var next = 0
    var environment: [String: String] = [:]
    for name in bindingNames {
        let (_, extended) = fresh(name, environment: environment, next: &next)
        environment = extended
    }
    let branches = semanticBranches(action)
    return "or[\(branches.map { actionKey($0, environment: environment, next: &next) }.joined(separator: ","))]"
}

/// Gives action disjunction one canonical representation. In particular,
/// `(a \/ b) /\ c` and `(a /\ c) \/ (b /\ c)` are the same transition
/// relation, whether the disjunction originated as a Swift boolean guard or
/// as an `ActionBuilder` branch.
private func semanticBranches(_ action: ActionExpr) -> [ActionExpr] {
    switch action {
    case .or(let left, let right):
        return semanticBranches(left) + semanticBranches(right)
    case .guard_(let condition):
        return semanticStateBranches(condition).map(ActionExpr.guard_)
    case .and(let left, let right):
        return semanticBranches(left).flatMap { leftBranch in
            semanticBranches(right).map { rightBranch in .and(leftBranch, rightBranch) }
        }
    case .ifElse(let condition, let then, let otherwise):
        return semanticBranches(.and(.guard_(condition), then))
            + semanticBranches(.and(.guard_(.not(condition)), otherwise))
    case .existsAction(let variable, let set, let body):
        return semanticBranches(body).map { .existsAction(variable, set, $0) }
    case .define(let variable, let value, let body):
        return semanticBranches(body).map { .define(variable, value, $0) }
    default:
        return [action]
    }
}

/// Splits only disjunctions that occur inside a Boolean guard. Swift can group
/// `a && (b || c)` into one `StateExpr` before that condition meets an action
/// update, while the syntax parser retains separate action guards. Both spell
/// the same transition relation.
private func semanticStateBranches(_ expression: StateExpr) -> [StateExpr] {
    switch expression {
    case .sourceIssue:
        return [expression]
    case .or(let left, let right):
        return semanticStateBranches(left) + semanticStateBranches(right)
    case .and(let left, let right):
        return semanticStateBranches(left).flatMap { leftBranch in
            semanticStateBranches(right).map { rightBranch in
                .and(leftBranch, rightBranch)
            }
        }
    default:
        return [expression]
    }
}

func alphaKey(_ expression: StateExpr) -> String {
    var next = 0
    return stateKey(expression, environment: [:], next: &next)
}

func alphaKey(_ expression: TemporalExpr) -> String {
    switch expression {
    case .always(let state): return "always(\(alphaKey(state)))"
    case .eventually(let state): return "eventually(\(alphaKey(state)))"
    case .alwaysEventually(let state): return "alwaysEventually(\(alphaKey(state)))"
    case .eventuallyAlways(let state): return "eventuallyAlways(\(alphaKey(state)))"
    case .leadsTo(let from, let to): return "leadsTo(\(alphaKey(from)),\(alphaKey(to)))"
    }
}

func fresh(_ name: String, environment: [String: String], next: inout Int) -> (String, [String: String]) {
    let canonical = "@\(next)"
    next += 1
    var extended = environment
    extended[name] = canonical
    return (canonical, extended)
}

private func actionKey(_ action: ActionExpr, environment: [String: String], next: inout Int) -> String {
    func state(_ expression: StateExpr) -> String { stateKey(expression, environment: environment, next: &next) }
    func associative(_ operation: String, _ action: ActionExpr) -> String {
        func flatten(_ action: ActionExpr) -> [ActionExpr] {
            switch (operation, action) {
            case ("and", .and(let left, let right)), ("or", .or(let left, let right)):
                return flatten(left) + flatten(right)
            case ("and", .guard_(let condition)):
                return flattenGuard(condition)
            default:
                return [action]
            }
        }
        func flattenGuard(_ condition: StateExpr) -> [ActionExpr] {
            guard operation == "and", case .and(let left, let right) = condition else {
                return [.guard_(condition)]
            }
            return flattenGuard(left) + flattenGuard(right)
        }
        return "\(operation)[\(flatten(action).map { actionKey($0, environment: environment, next: &next) }.joined(separator: ","))]"
    }
    switch action {
    case .assign(let variable, let value): return "assign(\(variable),\(state(value)))"
    case .unchanged(let variable): return "unchanged(\(variable))"
    case .guard_(let condition): return "guard(\(state(condition)))"
    case .chooseAction(let variable, let set): return "chooseAction(\(variable),\(state(set)))"
    case .existsAction(let variable, let set, let body):
        let setKey = state(set)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "existsAction(\(canonical),\(setKey),\(actionKey(body, environment: extended, next: &next)))"
    case .define(let variable, let value, let body):
        let valueKey = state(value)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "define(\(canonical),\(valueKey),\(actionKey(body, environment: extended, next: &next)))"
    case .ifElse(let condition, let then, let otherwise):
        return "if(\(state(condition)),\(actionKey(then, environment: environment, next: &next)),\(actionKey(otherwise, environment: environment, next: &next)))"
    case .and: return associative("and", action)
    case .or: return associative("or", action)
    }
}

private enum StateKeyTask {
    case expression(StateExpr, environment: [String: String])
    case text(String)
}

func stateKey(_ expression: StateExpr, environment: [String: String], next: inout Int) -> String {
    var tasks = [StateKeyTask.expression(expression, environment: environment)]
    var parts: [String] = []

    func schedule(_ name: String, _ expressions: [StateExpr], environment: [String: String]) {
        parts.append("\(name)(")
        tasks.append(.text(")"))
        for (index, expression) in expressions.enumerated().reversed() {
            tasks.append(.expression(expression, environment: environment))
            if index > 0 {
                tasks.append(.text(","))
            }
        }
    }

    while let task = tasks.popLast() {
        switch task {
        case .text(let text):
            parts.append(text)
        case .expression(let expression, let environment):
            func key(_ expression: StateExpr, environment: [String: String] = environment) -> String {
                stateKey(expression, environment: environment, next: &next)
            }
            switch expression {
            case .add(let lhs, let rhs): schedule("add", [lhs, rhs], environment: environment)
            case .subtract(let lhs, let rhs): schedule("subtract", [lhs, rhs], environment: environment)
            case .multiply(let lhs, let rhs): schedule("multiply", [lhs, rhs], environment: environment)
            case .divide(let lhs, let rhs): schedule("divide", [lhs, rhs], environment: environment)
            case .modulo(let lhs, let rhs): schedule("modulo", [lhs, rhs], environment: environment)
            case .integerDivide(let lhs, let rhs): schedule("integerDivide", [lhs, rhs], environment: environment)
            case .equal(let lhs, let rhs): schedule("equal", [lhs, rhs], environment: environment)
            case .notEqual(let lhs, let rhs): schedule("notEqual", [lhs, rhs], environment: environment)
            case .lessThan(let lhs, let rhs): schedule("lessThan", [lhs, rhs], environment: environment)
            case .lessOrEqual(let lhs, let rhs): schedule("lessOrEqual", [lhs, rhs], environment: environment)
            case .greaterThan(let lhs, let rhs): schedule("greaterThan", [lhs, rhs], environment: environment)
            case .greaterOrEqual(let lhs, let rhs): schedule("greaterOrEqual", [lhs, rhs], environment: environment)
            case .in(let lhs, let rhs): schedule("in", [lhs, rhs], environment: environment)
            case .subset(let lhs, let rhs): schedule("subset", [lhs, rhs], environment: environment)
            case .union(let lhs, let rhs): schedule("union", [lhs, rhs], environment: environment)
            case .intersection(let lhs, let rhs): schedule("intersection", [lhs, rhs], environment: environment)
            case .setDifference(let lhs, let rhs): schedule("difference", [lhs, rhs], environment: environment)
            case .integerRange(let lhs, let rhs): schedule("integerRange", [lhs, rhs], environment: environment)
            case .tupleDynamicAccess(let lhs, let rhs): schedule("tupleDynamicAccess", [lhs, rhs], environment: environment)
            case .tupleAppend(let lhs, let rhs): schedule("tupleAppend", [lhs, rhs], environment: environment)
            case .tupleConcatenate(let lhs, let rhs): schedule("tupleConcat", [lhs, rhs], environment: environment)
            case .functionApply(let lhs, let rhs): schedule("apply", [lhs, rhs], environment: environment)
            case .setSum(let lhs, let rhs): schedule("sum", [lhs, rhs], environment: environment)
            case .functionSet(let lhs, let rhs): schedule("functionSet", [lhs, rhs], environment: environment)
            case .negate(let value): schedule("negate", [value], environment: environment)
            case .not(let value): schedule("not", [value], environment: environment)
            case .cardinality(let value): schedule("cardinality", [value], environment: environment)
            case .powerSet(let value): schedule("powerSet", [value], environment: environment)
            case .unionAll(let value): schedule("unionAll", [value], environment: environment)
            case .tupleLength(let value): schedule("tupleLength", [value], environment: environment)
            case .tupleHead(let value): schedule("tupleHead", [value], environment: environment)
            case .tupleTail(let value): schedule("tupleTail", [value], environment: environment)
            case .domain(let value): schedule("domain", [value], environment: environment)
            case .sequenceFromSet(let value): schedule("sequence", [value], environment: environment)
            case .ifThenElse(let condition, let then, let otherwise):
                schedule("if", [condition, then, otherwise], environment: environment)
            case .and, .or:
                let operation: String
                if case .and = expression { operation = "and" } else { operation = "or" }
                var remaining = [expression]
                var operands: [StateExpr] = []
                while let candidate = remaining.popLast() {
                    switch (operation, candidate) {
                    case ("and", .and(let lhs, let rhs)), ("or", .or(let lhs, let rhs)):
                        remaining.append(rhs)
                        remaining.append(lhs)
                    default:
                        operands.append(candidate)
                    }
                }
                parts.append("\(operation)[")
                tasks.append(.text("]"))
                for (index, operand) in operands.enumerated().reversed() {
                    tasks.append(.expression(operand, environment: environment))
                    if index > 0 {
                        tasks.append(.text(","))
                    }
                }
            case .sourceIssue(let issue): parts.append("sourceIssue(\(issue))")
            case .value(let value): parts.append("value(\(value))")
            case .variable(let name): parts.append("var(\(environment[name] ?? name))")
            case .processLocalFamily(let name): parts.append("processLocalFamily(\(environment[name] ?? name))")
            case .currentProcess: parts.append("currentProcess")
            case .programCounter: parts.append("programCounter")
            case .procedureStack: parts.append("procedureStack")
            case .controlLocation(let reference):
                parts.append("control(\(reference.owner?.canonicalEncoding ?? "source"),\(reference.sourceName))")
            case .setLiteral(let values):
                parts.append("set[\(values.map { key($0) }.sorted().joined(separator: ","))]")
            case .setFilter(let set, let variable, let predicate):
                let setKey = key(set)
                let (canonical, extended) = fresh(variable, environment: environment, next: &next)
                parts.append("filter(\(setKey),\(canonical),\(key(predicate, environment: extended)))")
            case .setMap(let mapped, let variable, let set):
                let setKey = key(set)
                let (canonical, extended) = fresh(variable, environment: environment, next: &next)
                parts.append("map(\(key(mapped, environment: extended)),\(canonical),\(setKey))")
            case .tupleLiteral(let values):
                parts.append("tuple[\(values.map { key($0) }.joined(separator: ","))]")
            case .tupleAccess(let tuple, let index):
                parts.append("tupleAccess(\(key(tuple)),\(index))")
            case .recordLiteral(let fields):
                let fields = fields.fields.map { "\($0.name):\(key($0.value))" }.joined(separator: ",")
                parts.append("record[\(fields)]")
            case .recordAccess(let record, let field):
                parts.append("recordAccess(\(key(record)),\(field))")
            case .functionLiteral(let domain, let variable, let body):
                let domainKey = key(domain)
                let (canonical, extended) = fresh(variable, environment: environment, next: &next)
                parts.append("function(\(domainKey),\(canonical),\(key(body, environment: extended)))")
            case .except(let function, let keyExpression, let value):
                parts.append("except(\(key(function)),\(key(keyExpression)),\(key(value)))")
            case .caseExpr(let cases, let fallback):
                let cases = cases.map { key($0) }.joined(separator: ",")
                parts.append("case[\(cases)]/\(fallback.map { key($0) } ?? "none")")
            case .forAll(let set, let variable, let predicate):
                let setKey = key(set)
                let (canonical, extended) = fresh(variable, environment: environment, next: &next)
                parts.append("forall(\(setKey),\(canonical),\(key(predicate, environment: extended)))")
            case .exists(let set, let variable, let predicate):
                let setKey = key(set)
                let (canonical, extended) = fresh(variable, environment: environment, next: &next)
                parts.append("exists(\(setKey),\(canonical),\(key(predicate, environment: extended)))")
            case .choose(let set, let variable, let predicate):
                let setKey = key(set)
                let (canonical, extended) = fresh(variable, environment: environment, next: &next)
                parts.append("choose(\(setKey),\(canonical),\(key(predicate, environment: extended)))")
            case .enabledAction(let name): parts.append("enabled(\(name))")
            case .foldFunction(let operation, let initial, let sequence):
                var lambdaEnvironment = environment
                let parameters = operation.parameters.map { parameter -> String in
                    let (canonical, extended) = fresh(parameter, environment: lambdaEnvironment, next: &next)
                    lambdaEnvironment = extended
                    return canonical
                }
                parts.append("fold([\(parameters.joined(separator: ","))],\(key(operation.body, environment: lambdaEnvironment)),\(key(initial)),\(key(sequence)))")
            case .operatorApplication(let operation, let arguments):
                let operationKey: String
                switch operation {
                case .lambda(let lambda):
                    var lambdaEnvironment = environment
                    let parameters = lambda.parameters.map { parameter -> String in
                        let (canonical, extended) = fresh(parameter, environment: lambdaEnvironment, next: &next)
                        lambdaEnvironment = extended
                        return canonical
                    }
                    operationKey = "lambda([\(parameters.joined(separator: ","))],\(key(lambda.body, environment: lambdaEnvironment)))"
                case .reference(let name, let arity):
                    operationKey = "operator(\(environment[name] ?? name),\(arity))"
                }
                let argumentKeys = arguments.map { argument -> String in
                    switch argument {
                    case .value(let expression): return "value(\(key(expression)))"
                    case .operator(.reference(let name, let arity)):
                        return "operator(\(environment[name] ?? name),\(arity))"
                    case .operator(.lambda(let lambda)):
                        var lambdaEnvironment = environment
                        let parameters = lambda.parameters.map { parameter -> String in
                            let (canonical, extended) = fresh(parameter, environment: lambdaEnvironment, next: &next)
                            lambdaEnvironment = extended
                            return canonical
                        }
                        return "operatorLambda([\(parameters.joined(separator: ","))],\(key(lambda.body, environment: lambdaEnvironment)))"
                    }
                }
                parts.append("apply(\(operationKey),[\(argumentKeys.joined(separator: ","))])")
            case .recursiveCall(let name, let arguments):
                parts.append("recursive(\(name),\(arguments.map { key($0) }.joined(separator: ",")))")
            case .letValue(let name, let value, let body):
                let valueKey = key(value)
                let (canonical, extended) = fresh(name, environment: environment, next: &next)
                parts.append("letValue(\(canonical),\(valueKey),\(key(body, environment: extended)))")
            case .letIn(let operators, let body):
                let declarations = operators.map { operation in
                    var operatorEnvironment = environment
                    let domainKey = operation.domain.map { key($0, environment: operatorEnvironment) } ?? "unbounded"
                    let parameterNames = operation.parameters.map { parameter -> String in
                        let (canonical, extended) = fresh(parameter, environment: operatorEnvironment, next: &next)
                        operatorEnvironment = extended
                        return canonical
                    }
                    return "local(\(operation.name),[\(parameterNames.joined(separator: ","))],\(domainKey),\(key(operation.body, environment: operatorEnvironment)))"
                }.joined(separator: ",")
                parts.append("letIn([\(declarations)],\(key(body)))")
            }
        }
    }
    return parts.joined()
}
