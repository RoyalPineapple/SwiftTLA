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
    var keys: [String] = []
    for branch in branches {
        keys.append(actionKey(branch, environment: environment, next: &next))
    }
    return "or[\(keys.joined(separator: ","))]"
}

/// Gives action disjunction one canonical representation. In particular,
/// `(a \/ b) /\ c` and `(a /\ c) \/ (b /\ c)` are the same transition
/// relation, whether the disjunction originated as a Swift boolean guard or
/// as an `ActionBuilder` branch.
private enum SemanticActionBranchTask {
    case expression(ActionExpr)
    case concatenate
    case conjoin
    case wrapExistential(String, StateExpr)
    case wrapDefinition(String, StateExpr)
}

private func semanticBranches(_ action: ActionExpr) -> [ActionExpr] {
    var tasks = [SemanticActionBranchTask.expression(action)]
    var branches: [[ActionExpr]] = []
    while let task = tasks.popLast() {
        switch task {
        case .expression(let expression):
            switch expression {
            case .or(let left, let right):
                tasks.append(.concatenate)
                tasks.append(.expression(right))
                tasks.append(.expression(left))
            case .guard_(let condition):
                branches.append(semanticStateBranches(condition).map(ActionExpr.guard_))
            case .and(let left, let right):
                tasks.append(.conjoin)
                tasks.append(.expression(right))
                tasks.append(.expression(left))
            case .ifElse(let condition, let then, let otherwise):
                tasks.append(.concatenate)
                tasks.append(.expression(.and(.guard_(.not(condition)), otherwise)))
                tasks.append(.expression(.and(.guard_(condition), then)))
            case .existsAction(let variable, let set, let body):
                tasks.append(.wrapExistential(variable, set))
                tasks.append(.expression(body))
            case .define(let variable, let value, let body):
                tasks.append(.wrapDefinition(variable, value))
                tasks.append(.expression(body))
            default:
                branches.append([expression])
            }
        case .concatenate:
            let right = branches.removeLast()
            let left = branches.removeLast()
            branches.append(left + right)
        case .conjoin:
            let right = branches.removeLast()
            let left = branches.removeLast()
            branches.append(left.flatMap { leftBranch in
                right.map { rightBranch in .and(leftBranch, rightBranch) }
            })
        case .wrapExistential(let variable, let set):
            branches.append(branches.removeLast().map { .existsAction(variable, set, $0) })
        case .wrapDefinition(let variable, let value):
            branches.append(branches.removeLast().map { .define(variable, value, $0) })
        }
    }
    return branches[0]
}

/// Splits only disjunctions that occur inside a Boolean guard. Swift can group
/// `a && (b || c)` into one `StateExpr` before that condition meets an action
/// update, while the syntax parser retains separate action guards. Both spell
/// the same transition relation.
private enum SemanticStateBranchTask {
    case expression(StateExpr)
    case concatenate
    case conjoin
}

private func semanticStateBranches(_ expression: StateExpr) -> [StateExpr] {
    var tasks = [SemanticStateBranchTask.expression(expression)]
    var branches: [[StateExpr]] = []
    while let task = tasks.popLast() {
        switch task {
        case .expression(let expression):
            switch expression {
            case .or(let left, let right):
                tasks.append(.concatenate)
                tasks.append(.expression(right))
                tasks.append(.expression(left))
            case .and(let left, let right):
                tasks.append(.conjoin)
                tasks.append(.expression(right))
                tasks.append(.expression(left))
            default:
                branches.append([expression])
            }
        case .concatenate:
            let right = branches.removeLast()
            let left = branches.removeLast()
            branches.append(left + right)
        case .conjoin:
            let right = branches.removeLast()
            let left = branches.removeLast()
            branches.append(left.flatMap { leftBranch in
                right.map { rightBranch in .and(leftBranch, rightBranch) }
            })
        }
    }
    return branches[0]
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

private enum ActionKeyTask {
    case expression(ActionExpr, environment: [String: String])
    case finish(Int, ([String]) -> String)
}

private enum ActionAssociativeOperation: String {
    case and
    case or
}

private func actionKey(_ action: ActionExpr, environment: [String: String], next: inout Int) -> String {
    var tasks = [ActionKeyTask.expression(action, environment: environment)]
    var parts: [String] = []
    while let task = tasks.popLast() {
        switch task {
        case .finish(let count, let formatter):
            let start = parts.count - count
            let values = Array(parts[start...])
            parts.removeSubrange(start...)
            parts.append(formatter(values))
        case .expression(let expression, let environment):
            func state(_ value: StateExpr) -> String {
                stateKey(value, environment: environment, next: &next)
            }
            switch expression {
            case .assign(let variable, let value):
                parts.append("assign(\(variable),\(state(value)))")
            case .unchanged(let variable):
                parts.append("unchanged(\(variable))")
            case .guard_(let condition):
                parts.append("guard(\(state(condition)))")
            case .chooseAction(let variable, let set):
                parts.append("chooseAction(\(variable),\(state(set)))")
            case .existsAction(let variable, let set, let body):
                let setKey = state(set)
                let (canonical, extended) = fresh(variable, environment: environment, next: &next)
                tasks.append(.finish(1) { "existsAction(\(canonical),\(setKey),\($0[0]))" })
                tasks.append(.expression(body, environment: extended))
            case .define(let variable, let value, let body):
                let valueKey = state(value)
                let (canonical, extended) = fresh(variable, environment: environment, next: &next)
                tasks.append(.finish(1) { "define(\(canonical),\(valueKey),\($0[0]))" })
                tasks.append(.expression(body, environment: extended))
            case .ifElse(let condition, let then, let otherwise):
                let conditionKey = state(condition)
                tasks.append(.finish(2) { "if(\(conditionKey),\($0[0]),\($0[1]))" })
                tasks.append(.expression(otherwise, environment: environment))
                tasks.append(.expression(then, environment: environment))
            case .and:
                scheduleKeyOperands(.and, expression, environment: environment, tasks: &tasks)
            case .or:
                scheduleKeyOperands(.or, expression, environment: environment, tasks: &tasks)
            }
        }
    }
    return parts[0]
}

private func scheduleKeyOperands(
    _ operation: ActionAssociativeOperation,
    _ action: ActionExpr,
    environment: [String: String],
    tasks: inout [ActionKeyTask]
) {
    var pending = [action]
    var operands: [ActionExpr] = []
    while let expression = pending.popLast() {
        switch (operation, expression) {
        case (.and, .and(let left, let right)), (.or, .or(let left, let right)):
            pending.append(right)
            pending.append(left)
        case (.and, .guard_(let condition)):
            var conditions = [condition]
            while let candidate = conditions.popLast() {
                if case .and(let left, let right) = candidate {
                    conditions.append(right)
                    conditions.append(left)
                } else {
                    operands.append(.guard_(candidate))
                }
            }
        default:
            operands.append(expression)
        }
    }
    tasks.append(.finish(operands.count) {
        "\(operation.rawValue)[\($0.joined(separator: ","))]"
    })
    for operand in operands.reversed() {
        tasks.append(.expression(operand, environment: environment))
    }
}

private enum StateKeyTask {
    case expression(StateExpr, environment: [String: String])
    case finish(Int, ([String]) -> String)
    case bind(StateKeyBinding, variable: String, body: StateExpr, environment: [String: String])
    case formalOperator(FormalOperator, environment: [String: String], style: FormalOperatorKeyStyle)
    case formalArgument(FormalCallArgument, environment: [String: String])
    case letOperators([LocalOperator], index: Int, body: StateExpr, environment: [String: String], declarations: [String])
    case letOperatorAfterDomain([LocalOperator], index: Int, body: StateExpr, environment: [String: String], declarations: [String])
    case letOperatorAfterBody([LocalOperator], index: Int, body: StateExpr, environment: [String: String], declarations: [String], domain: String, parameters: [String])
}

private enum StateKeyBinding {
    case filter
    case map
    case function
    case forall
    case exists
    case choose
    case letValue
}

private enum FormalOperatorKeyStyle {
    case operation
    case argument
}

func stateKey(_ expression: StateExpr, environment: [String: String], next: inout Int) -> String {
    var tasks = [StateKeyTask.expression(expression, environment: environment)]
    var parts: [String] = []

    func schedule(
        _ expressions: [StateExpr],
        environment: [String: String],
        formatter: @escaping ([String]) -> String
    ) {
        tasks.append(.finish(expressions.count, formatter))
        for expression in expressions.reversed() {
            tasks.append(.expression(expression, environment: environment))
        }
    }

    func schedule(_ name: String, _ expressions: [StateExpr], environment: [String: String]) {
        schedule(expressions, environment: environment) { "\(name)(\($0.joined(separator: ",")))" }
    }

    func allocate(_ parameters: [String], environment: [String: String]) -> ([String], [String: String]) {
        var extended = environment
        var canonical: [String] = []
        for parameter in parameters {
            let (name, nextEnvironment) = fresh(parameter, environment: extended, next: &next)
            canonical.append(name)
            extended = nextEnvironment
        }
        return (canonical, extended)
    }

    while let task = tasks.popLast() {
        switch task {
        case .finish(let count, let formatter):
            let start = parts.count - count
            let values = Array(parts[start...])
            parts.removeSubrange(start...)
            parts.append(formatter(values))
        case .bind(let binding, let variable, let body, let environment):
            let (canonical, extended) = fresh(variable, environment: environment, next: &next)
            tasks.append(.finish(2) { values in
                switch binding {
                case .filter: "filter(\(values[0]),\(canonical),\(values[1]))"
                case .map: "map(\(values[1]),\(canonical),\(values[0]))"
                case .function: "function(\(values[0]),\(canonical),\(values[1]))"
                case .forall: "forall(\(values[0]),\(canonical),\(values[1]))"
                case .exists: "exists(\(values[0]),\(canonical),\(values[1]))"
                case .choose: "choose(\(values[0]),\(canonical),\(values[1]))"
                case .letValue: "letValue(\(canonical),\(values[0]),\(values[1]))"
                }
            })
            tasks.append(.expression(body, environment: extended))
        case .formalOperator(let operation, let environment, let style):
            switch operation {
            case .reference(let name, let arity):
                parts.append("operator(\(environment[name] ?? name),\(arity))")
            case .lambda(let lambda):
                let (parameters, extended) = allocate(lambda.parameters, environment: environment)
                tasks.append(.finish(1) { values in
                    let name = switch style {
                    case .operation: "lambda"
                    case .argument: "operatorLambda"
                    }
                    return "\(name)([\(parameters.joined(separator: ","))],\(values[0]))"
                })
                tasks.append(.expression(lambda.body, environment: extended))
            }
        case .formalArgument(let argument, let environment):
            switch argument {
            case .value(let expression):
                tasks.append(.finish(1) { "value(\($0[0]))" })
                tasks.append(.expression(expression, environment: environment))
            case .operator(let operation):
                tasks.append(.formalOperator(operation, environment: environment, style: .argument))
            }
        case .letOperators(let operators, let index, let body, let environment, let declarations):
            guard index < operators.count else {
                tasks.append(.finish(1) { "letIn([\(declarations.joined(separator: ","))],\($0[0]))" })
                tasks.append(.expression(body, environment: environment))
                continue
            }
            if let domain = operators[index].domain {
                tasks.append(.letOperatorAfterDomain(operators, index: index, body: body, environment: environment, declarations: declarations))
                tasks.append(.expression(domain, environment: environment))
            } else {
                let (parameters, extended) = allocate(operators[index].parameters, environment: environment)
                tasks.append(.letOperatorAfterBody(operators, index: index, body: body, environment: environment, declarations: declarations, domain: "unbounded", parameters: parameters))
                tasks.append(.expression(operators[index].body, environment: extended))
            }
        case .letOperatorAfterDomain(let operators, let index, let body, let environment, let declarations):
            let domain = parts.removeLast()
            let (parameters, extended) = allocate(operators[index].parameters, environment: environment)
            tasks.append(.letOperatorAfterBody(operators, index: index, body: body, environment: environment, declarations: declarations, domain: domain, parameters: parameters))
            tasks.append(.expression(operators[index].body, environment: extended))
        case .letOperatorAfterBody(let operators, let index, let body, let environment, let declarations, let domain, let parameters):
            let operation = operators[index]
            let operationBody = parts.removeLast()
            let declaration = "local(\(operation.name),[\(parameters.joined(separator: ","))],\(domain),\(operationBody))"
            tasks.append(.letOperators(operators, index: index + 1, body: body, environment: environment, declarations: declarations + [declaration]))
        case .expression(let expression, let environment):
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
                schedule(operands, environment: environment) { "\(operation)[\($0.joined(separator: ","))]" }
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
                schedule(values, environment: environment) { "set[\($0.sorted().joined(separator: ","))]" }
            case .setFilter(let set, let variable, let predicate):
                tasks.append(.bind(.filter, variable: variable, body: predicate, environment: environment))
                tasks.append(.expression(set, environment: environment))
            case .setMap(let mapped, let variable, let set):
                tasks.append(.bind(.map, variable: variable, body: mapped, environment: environment))
                tasks.append(.expression(set, environment: environment))
            case .tupleLiteral(let values):
                schedule(values, environment: environment) { "tuple[\($0.joined(separator: ","))]" }
            case .tupleAccess(let tuple, let index):
                schedule([tuple], environment: environment) { "tupleAccess(\($0[0]),\(index))" }
            case .recordLiteral(let fields):
                let names = fields.fields.map(\.name)
                schedule(fields.fields.map(\.value), environment: environment) { values in
                    "record[\(zip(names, values).map { "\($0):\($1)" }.joined(separator: ","))]"
                }
            case .recordAccess(let record, let field):
                schedule([record], environment: environment) { "recordAccess(\($0[0]),\(field))" }
            case .functionLiteral(let domain, let variable, let body):
                tasks.append(.bind(.function, variable: variable, body: body, environment: environment))
                tasks.append(.expression(domain, environment: environment))
            case .except(let function, let keyExpression, let value):
                schedule("except", [function, keyExpression, value], environment: environment)
            case .caseExpr(let cases, let fallback):
                let expressions = cases + (fallback.map { [$0] } ?? [])
                schedule(expressions, environment: environment) { values in
                    let caseValues = values.prefix(cases.count).joined(separator: ",")
                    let fallbackValue = fallback == nil ? "none" : values[cases.count]
                    return "case[\(caseValues)]/\(fallbackValue)"
                }
            case .forAll(let set, let variable, let predicate):
                tasks.append(.bind(.forall, variable: variable, body: predicate, environment: environment))
                tasks.append(.expression(set, environment: environment))
            case .exists(let set, let variable, let predicate):
                tasks.append(.bind(.exists, variable: variable, body: predicate, environment: environment))
                tasks.append(.expression(set, environment: environment))
            case .choose(let set, let variable, let predicate):
                tasks.append(.bind(.choose, variable: variable, body: predicate, environment: environment))
                tasks.append(.expression(set, environment: environment))
            case .enabledAction(let name): parts.append("enabled(\(name))")
            case .foldFunction(let operation, let initial, let sequence):
                let (parameters, extended) = allocate(operation.parameters, environment: environment)
                tasks.append(.finish(3) {
                    "fold([\(parameters.joined(separator: ","))],\($0.joined(separator: ",")))"
                })
                tasks.append(.expression(sequence, environment: environment))
                tasks.append(.expression(initial, environment: environment))
                tasks.append(.expression(operation.body, environment: extended))
            case .operatorApplication(let operation, let arguments):
                tasks.append(.finish(arguments.count + 1) { values in
                    "apply(\(values[0]),[\(values.dropFirst().joined(separator: ","))])"
                })
                for argument in arguments.reversed() {
                    tasks.append(.formalArgument(argument, environment: environment))
                }
                tasks.append(.formalOperator(operation, environment: environment, style: .operation))
            case .recursiveCall(let name, let arguments):
                schedule(arguments, environment: environment) {
                    "recursive(\(name),\($0.joined(separator: ",")))"
                }
            case .letValue(let name, let value, let body):
                tasks.append(.bind(.letValue, variable: name, body: body, environment: environment))
                tasks.append(.expression(value, environment: environment))
            case .letIn(let operators, let body):
                tasks.append(.letOperators(
                    operators,
                    index: 0,
                    body: body,
                    environment: environment,
                    declarations: []
                ))
            }
        }
    }
    return parts.joined()
}
