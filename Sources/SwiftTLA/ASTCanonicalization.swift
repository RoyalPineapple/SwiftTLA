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

func stateKey(_ expression: StateExpr, environment: [String: String], next: inout Int) -> String {
    func key(_ expression: StateExpr, environment: [String: String] = environment) -> String {
        stateKey(expression, environment: environment, next: &next)
    }
    func pair(_ name: String, _ left: StateExpr, _ right: StateExpr) -> String { "\(name)(\(key(left)),\(key(right)))" }
    func associative(_ operation: String, _ expression: StateExpr) -> String {
        func flatten(_ expression: StateExpr) -> [StateExpr] {
            switch (operation, expression) {
            case ("and", .and(let left, let right)), ("or", .or(let left, let right)):
                return flatten(left) + flatten(right)
            default:
                return [expression]
            }
        }
        return "\(operation)[\(flatten(expression).map { key($0) }.joined(separator: ","))]"
    }
    switch expression {
    case .sourceIssue(let issue): return "sourceIssue(\(issue))"
    case .value(let value): return "value(\(value))"
    case .variable(let name): return "var(\(environment[name] ?? name))"
    case .processLocalFamily(let name): return "processLocalFamily(\(environment[name] ?? name))"
    case .currentProcess: return "currentProcess"
    case .programCounter: return "programCounter"
    case .procedureStack: return "procedureStack"
    case .controlLocation(let reference):
        return "control(\(reference.owner?.canonicalEncoding ?? "source"),\(reference.sourceName))"
    case .add(let a, let b): return pair("add", a, b)
    case .subtract(let a, let b): return pair("subtract", a, b)
    case .multiply(let a, let b): return pair("multiply", a, b)
    case .divide(let a, let b): return pair("divide", a, b)
    case .modulo(let a, let b): return pair("modulo", a, b)
    case .negate(let value): return "negate(\(key(value)))"
    case .integerDivide(let a, let b): return pair("integerDivide", a, b)
    case .equal(let a, let b): return pair("equal", a, b)
    case .notEqual(let a, let b): return pair("notEqual", a, b)
    case .lessThan(let a, let b): return pair("lessThan", a, b)
    case .lessOrEqual(let a, let b): return pair("lessOrEqual", a, b)
    case .greaterThan(let a, let b): return pair("greaterThan", a, b)
    case .greaterOrEqual(let a, let b): return pair("greaterOrEqual", a, b)
    case .and: return associative("and", expression)
    case .or: return associative("or", expression)
    case .not(let value): return "not(\(key(value)))"
    case .ifThenElse(let c, let t, let f): return "if(\(key(c)),\(key(t)),\(key(f)))"
    case .setLiteral(let values): return "set[\(values.map { key($0) }.sorted().joined(separator: ","))]"
    case .in(let a, let b): return pair("in", a, b)
    case .subset(let a, let b): return pair("subset", a, b)
    case .union(let a, let b): return pair("union", a, b)
    case .intersection(let a, let b): return pair("intersection", a, b)
    case .setDifference(let a, let b): return pair("difference", a, b)
    case .cardinality(let value): return "cardinality(\(key(value)))"
    case .setFilter(let set, let variable, let predicate):
        let setKey = key(set)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "filter(\(setKey),\(canonical),\(key(predicate, environment: extended)))"
    case .setMap(let mapped, let variable, let set):
        let setKey = key(set)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "map(\(key(mapped, environment: extended)),\(canonical),\(setKey))"
    case .powerSet(let value): return "powerSet(\(key(value)))"
    case .unionAll(let value): return "unionAll(\(key(value)))"
    case .integerRange(let lower, let upper): return pair("integerRange", lower, upper)
    case .tupleLiteral(let values): return "tuple[\(values.map { key($0) }.joined(separator: ","))]"
    case .tupleAccess(let tuple, let index): return "tupleAccess(\(key(tuple)),\(index))"
    case .tupleDynamicAccess(let tuple, let index): return pair("tupleDynamicAccess", tuple, index)
    case .tupleLength(let tuple): return "tupleLength(\(key(tuple)))"
    case .tupleAppend(let tuple, let value): return pair("tupleAppend", tuple, value)
    case .tupleHead(let tuple): return "tupleHead(\(key(tuple)))"
    case .tupleTail(let tuple): return "tupleTail(\(key(tuple)))"
    case .tupleConcatenate(let a, let b): return pair("tupleConcat", a, b)
    case .recordLiteral(let fields):
        return "record[\(fields.fields.map { "\($0.name):\(key($0.value))" }.joined(separator: ","))]"
    case .recordAccess(let record, let field): return "recordAccess(\(key(record)),\(field))"
    case .domain(let function): return "domain(\(key(function)))"
    case .functionLiteral(let domain, let variable, let body):
        let domainKey = key(domain)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "function(\(domainKey),\(canonical),\(key(body, environment: extended)))"
    case .functionApply(let function, let argument): return pair("apply", function, argument)
    case .except(let function, let keyExpression, let value): return "except(\(key(function)),\(key(keyExpression)),\(key(value)))"
    case .caseExpr(let cases, let fallback):
        return "case[\(cases.map { key($0) }.joined(separator: ","))]/\(fallback.map { key($0) } ?? "none")"
    case .forAll(let set, let variable, let predicate):
        let setKey = key(set)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "forall(\(setKey),\(canonical),\(key(predicate, environment: extended)))"
    case .exists(let set, let variable, let predicate):
        let setKey = key(set)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "exists(\(setKey),\(canonical),\(key(predicate, environment: extended)))"
    case .choose(let set, let variable, let predicate):
        let setKey = key(set)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "choose(\(setKey),\(canonical),\(key(predicate, environment: extended)))"
    case .enabledAction(let name): return "enabled(\(name))"
    case .sequenceFromSet(let value): return "sequence(\(key(value)))"
    case .setSum(let function, let set): return pair("sum", function, set)
    case .functionSet(let domain, let range): return pair("functionSet", domain, range)
    case .foldFunction(let operation, let initial, let sequence):
        var lambdaEnvironment = environment
        let parameters = operation.parameters.map { parameter -> String in
            let (canonical, extended) = fresh(parameter, environment: lambdaEnvironment, next: &next)
            lambdaEnvironment = extended
            return canonical
        }
        return "fold([\(parameters.joined(separator: ","))],\(key(operation.body, environment: lambdaEnvironment)),\(key(initial)),\(key(sequence)))"
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
    return "apply(\(operationKey),[\(argumentKeys.joined(separator: ","))])"
    case .recursiveCall(let name, let arguments): return "recursive(\(name),\(arguments.map { key($0) }.joined(separator: ",")))"
    case .letValue(let name, let value, let body):
        let valueKey = key(value)
        let (canonical, extended) = fresh(name, environment: environment, next: &next)
        return "letValue(\(canonical),\(valueKey),\(key(body, environment: extended)))"
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
        return "letIn([\(declarations)],\(key(body)))"
    }
}
