extension Algorithm {
    /// Lowers a validated bounded algorithm into the ordinary executable TLA+ model.
    public func lower() throws -> TLASpec {
        try requireValid()
        return AlgorithmLowerer.lower(model)
    }
}

private enum AlgorithmLowerer {
    private static let controlVariable = "pc"
    private static let processBinding = "self"
    private static let builderProcessIdentifier = "__pcal_self"

    static func lower(_ algorithm: AlgorithmModel) -> TLASpec {
        let processes = algorithm.processes
        let shared = algorithm.components.compactMap { component -> AlgorithmStateModel? in
            guard case .shared(let state) = component else { return nil }
            return state
        }
        let localStates = processes.flatMap { process in
            process.components.compactMap { component -> AlgorithmStateModel? in
                guard case .local(let state) = component else { return nil }
                return state
            }
        }

        var variables = shared.map { NamedVar(name: $0.root, initial: $0.initial) }
        for process in processes {
            for local in process.components {
                guard case .local(let state) = local else { continue }
                variables.append(
                    NamedVar(name: state.root, initial: constantFunction(domain: process.domain, value: state.initial)))
            }
        }

        let controlInitial = Dictionary(uniqueKeysWithValues: processes.flatMap { process in
            guard let first = process.steps.first else { return [(TLAValue, TLAValue)]() }
            return process.domain.map { ($0, .string(first.label.name)) }
        })
        variables.append(NamedVar(name: controlVariable, initial: .function(controlInitial)))

        let variableNames = variables.map(\.name)
        let localRoots = Set(localStates.map(\.root))
        let actions = processes.flatMap { process in
            process.steps.map { atomic in
                let guardExpression = StateExpr.equal(
                    .functionApply(.variable(controlVariable), .variable(processBinding)),
                    .value(.string(atomic.label.name)))
                let body = lower(
                    atomic.statements,
                    localRoots: localRoots,
                    processDomain: process.domain)
                return NamedAction(
                    name: atomic.label.name,
                    body: completeAction(.and(.guard_(guardExpression), body), allVars: variableNames),
                    bindings: [ActionBinding(name: processBinding, values: process.domain)])
            }
        }

        return TLASpec(
            name: algorithm.name,
            variables: variables,
            actions: actions,
            invariants: [])
    }

    private static func constantFunction(domain: [TLAValue], value: TLAValue) -> TLAValue {
        .function(Dictionary(uniqueKeysWithValues: domain.map { ($0, value) }))
    }

    private static func lower(
        _ statements: [AlgorithmStatementModel],
        localRoots: Set<String>,
        processDomain: [TLAValue]
    ) -> ActionExpr {
        statements.reduce(.guard_(.value(.bool(true)))) { partial, statement in
            .and(partial, lower(statement, localRoots: localRoots, processDomain: processDomain))
        }
    }

    private static func lower(
        _ statement: AlgorithmStatementModel,
        localRoots: Set<String>,
        processDomain: [TLAValue]
    ) -> ActionExpr {
        switch statement {
        case .await(let condition):
            return .guard_(rewrite(condition, localRoots: localRoots))
        case .set(let target, let value):
            let value = rewrite(value, localRoots: localRoots)
            switch target {
            case .root(let root) where localRoots.contains(root):
                return .assign(
                    root,
                    .except(.variable(root), .variable(processBinding), value))
            case .root(let root):
                return .assign(root, value)
            case .function(let root, let key):
                return .assign(
                    root,
                    .except(
                        .variable(root),
                        rewrite(key, localRoots: localRoots),
                        value))
            }
        case .ifElse(let condition, let then, let otherwise):
            return .ifElse(
                rewrite(condition, localRoots: localRoots),
                lower(then, localRoots: localRoots, processDomain: processDomain),
                lower(otherwise, localRoots: localRoots, processDomain: processDomain))
        case .either(let first, let second):
            return .or(
                lower(first, localRoots: localRoots, processDomain: processDomain),
                lower(second, localRoots: localRoots, processDomain: processDomain))
        case .choose(let variable, let domain, let body):
            return .existsAction(
                variable,
                .setLiteral(domain.map { .value($0) }),
                lower(body, localRoots: localRoots, processDomain: processDomain))
        case .goto(let label):
            return .assign(
                controlVariable,
                .except(
                    .variable(controlVariable),
                    .variable(processBinding),
                    .value(.string(label.name))))
        case .stop:
            // Keep a terminated process in place so its final atomic action is a self loop.
            return .unchanged(controlVariable)
        }
    }

    private static func rewrite(_ expression: StateExpr, localRoots: Set<String>) -> StateExpr {
        func rewritten(_ expression: StateExpr, localRoots: Set<String>) -> StateExpr {
            switch expression {
            case .value:
                return expression
            case .variable(let name):
                if name == builderProcessIdentifier { return .variable(processBinding) }
                if localRoots.contains(name) {
                    return .functionApply(.variable(name), .variable(processBinding))
                }
                return expression
            case .add(let lhs, let rhs): return .add(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .subtract(let lhs, let rhs): return .subtract(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .multiply(let lhs, let rhs): return .multiply(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .divide(let lhs, let rhs): return .divide(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .modulo(let lhs, let rhs): return .modulo(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .negate(let value): return .negate(rewritten(value, localRoots: localRoots))
            case .integerDivide(let lhs, let rhs): return .integerDivide(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .equal(let lhs, let rhs): return .equal(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .notEqual(let lhs, let rhs): return .notEqual(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .lessThan(let lhs, let rhs): return .lessThan(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .lessOrEqual(let lhs, let rhs): return .lessOrEqual(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .greaterThan(let lhs, let rhs): return .greaterThan(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .greaterOrEqual(let lhs, let rhs): return .greaterOrEqual(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .and(let lhs, let rhs): return .and(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .or(let lhs, let rhs): return .or(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .not(let value): return .not(rewritten(value, localRoots: localRoots))
            case .ifThenElse(let condition, let then, let otherwise):
                return .ifThenElse(rewritten(condition, localRoots: localRoots), rewritten(then, localRoots: localRoots), rewritten(otherwise, localRoots: localRoots))
            case .setLiteral(let elements): return .setLiteral(elements.map { rewritten($0, localRoots: localRoots) })
            case .in(let value, let set): return .in(rewritten(value, localRoots: localRoots), rewritten(set, localRoots: localRoots))
            case .subset(let lhs, let rhs): return .subset(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .union(let lhs, let rhs): return .union(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .intersection(let lhs, let rhs): return .intersection(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .setDifference(let lhs, let rhs): return .setDifference(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .cardinality(let set): return .cardinality(rewritten(set, localRoots: localRoots))
            case .setFilter(let set, let variable, let predicate):
                return .setFilter(rewritten(set, localRoots: localRoots), variable, rewritten(predicate, localRoots: localRoots.subtracting([variable])))
            case .setMap(let value, let variable, let set):
                return .setMap(rewritten(value, localRoots: localRoots.subtracting([variable])), variable, rewritten(set, localRoots: localRoots))
            case .powerSet(let set): return .powerSet(rewritten(set, localRoots: localRoots))
            case .unionAll(let set): return .unionAll(rewritten(set, localRoots: localRoots))
            case .tupleLiteral(let elements): return .tupleLiteral(elements.map { rewritten($0, localRoots: localRoots) })
            case .tupleAccess(let tuple, let index): return .tupleAccess(rewritten(tuple, localRoots: localRoots), index)
            case .tupleLength(let tuple): return .tupleLength(rewritten(tuple, localRoots: localRoots))
            case .tupleAppend(let tuple, let value): return .tupleAppend(rewritten(tuple, localRoots: localRoots), rewritten(value, localRoots: localRoots))
            case .tupleHead(let tuple): return .tupleHead(rewritten(tuple, localRoots: localRoots))
            case .tupleTail(let tuple): return .tupleTail(rewritten(tuple, localRoots: localRoots))
            case .tupleConcatenate(let lhs, let rhs): return .tupleConcatenate(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .recordLiteral(let fields): return .recordLiteral(fields.mapValues { rewritten($0, localRoots: localRoots) })
            case .recordAccess(let record, let field): return .recordAccess(rewritten(record, localRoots: localRoots), field)
            case .domain(let function): return .domain(rewritten(function, localRoots: localRoots))
            case .functionLiteral(let domain, let variable, let body):
                return .functionLiteral(rewritten(domain, localRoots: localRoots), variable, rewritten(body, localRoots: localRoots.subtracting([variable])))
            case .functionApply(let function, let argument): return .functionApply(rewritten(function, localRoots: localRoots), rewritten(argument, localRoots: localRoots))
            case .except(let function, let key, let value):
                return .except(rewritten(function, localRoots: localRoots), rewritten(key, localRoots: localRoots), rewritten(value, localRoots: localRoots))
            case .caseExpr(let cases, let fallback):
                return .caseExpr(cases.map { rewritten($0, localRoots: localRoots) }, fallback.map { rewritten($0, localRoots: localRoots) })
            case .forAll(let set, let variable, let predicate):
                return .forAll(rewritten(set, localRoots: localRoots), variable, rewritten(predicate, localRoots: localRoots.subtracting([variable])))
            case .exists(let set, let variable, let predicate):
                return .exists(rewritten(set, localRoots: localRoots), variable, rewritten(predicate, localRoots: localRoots.subtracting([variable])))
            case .choose(let set, let variable, let predicate):
                return .choose(rewritten(set, localRoots: localRoots), variable, rewritten(predicate, localRoots: localRoots.subtracting([variable])))
            case .enabledAction:
                return expression
            case .sequenceFromSet(let set): return .sequenceFromSet(rewritten(set, localRoots: localRoots))
            case .setSum(let function, let set): return .setSum(rewritten(function, localRoots: localRoots), rewritten(set, localRoots: localRoots))
            case .functionSet(let domain, let range): return .functionSet(rewritten(domain, localRoots: localRoots), rewritten(range, localRoots: localRoots))
            case .recursiveCall(let name, let arguments): return .recursiveCall(name, arguments.map { rewritten($0, localRoots: localRoots) })
            }
        }

        return rewritten(expression, localRoots: localRoots)
    }
}
