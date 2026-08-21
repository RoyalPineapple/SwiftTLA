extension StateExpr {
    public static func substituteVariable(_ name: String, _ value: TLAValue, in expr: StateExpr) -> StateExpr {
        substituteVariable(name, with: .value(value), in: expr)
    }

    public static func substituteVariable(
        _ name: String,
        with replacement: StateExpr,
        in expr: StateExpr
    ) -> StateExpr {
        let replacementFreeVariables = replacement.freeVariableNames

        func underBinder(_ binder: String, body: StateExpr) -> (name: String, body: StateExpr) {
            guard binder != name else { return (binder, body) }
            guard replacementFreeVariables.contains(binder) else {
                return (binder, Self.substituteVariable(name, with: replacement, in: body))
            }

            let fresh = Self.freshBoundName(
                binder,
                avoiding: body.freeVariableNames
                    .union(replacementFreeVariables)
                    .union([name, binder])
            )
            let renamed = Self.substituteVariable(binder, with: .variable(fresh), in: body)
            return (fresh, Self.substituteVariable(name, with: replacement, in: renamed))
        }

        func underParameters(
            _ parameters: [String],
            body: StateExpr
        ) -> (parameters: [String], body: StateExpr) {
            guard !parameters.contains(name) else { return (parameters, body) }
            var renamedParameters = parameters
            var renamedBody = body
            for index in renamedParameters.indices where replacementFreeVariables.contains(renamedParameters[index]) {
                let oldName = renamedParameters[index]
                let fresh = Self.freshBoundName(
                    oldName,
                    avoiding: renamedBody.freeVariableNames
                        .union(replacementFreeVariables)
                        .union(Set(renamedParameters))
                        .union([name])
                )
                renamedBody = Self.substituteVariable(oldName, with: .variable(fresh), in: renamedBody)
                renamedParameters[index] = fresh
            }
            return (
                renamedParameters,
                Self.substituteVariable(name, with: replacement, in: renamedBody)
            )
        }

        switch expr {
        case .variable(let n) where n == name: return replacement
        case .variable: return expr
        case .value, .enabledAction: return expr
        case .add(let l, let r): return .add(sub(l), sub(r))
        case .subtract(let l, let r): return .subtract(sub(l), sub(r))
        case .multiply(let l, let r): return .multiply(sub(l), sub(r))
        case .divide(let l, let r): return .divide(sub(l), sub(r))
        case .modulo(let l, let r): return .modulo(sub(l), sub(r))
        case .negate(let x): return .negate(sub(x))
        case .integerDivide(let l, let r): return .integerDivide(sub(l), sub(r))
        case .equal(let l, let r): return .equal(sub(l), sub(r))
        case .notEqual(let l, let r): return .notEqual(sub(l), sub(r))
        case .lessThan(let l, let r): return .lessThan(sub(l), sub(r))
        case .lessOrEqual(let l, let r): return .lessOrEqual(sub(l), sub(r))
        case .greaterThan(let l, let r): return .greaterThan(sub(l), sub(r))
        case .greaterOrEqual(let l, let r): return .greaterOrEqual(sub(l), sub(r))
        case .and(let l, let r): return .and(sub(l), sub(r))
        case .or(let l, let r): return .or(sub(l), sub(r))
        case .not(let x): return .not(sub(x))
        case .ifThenElse(let c, let t, let e): return .ifThenElse(sub(c), sub(t), sub(e))
        case .setLiteral(let es): return .setLiteral(es.map(sub))
        case .in(let e, let s): return .in(sub(e), sub(s))
        case .subset(let a, let b): return .subset(sub(a), sub(b))
        case .union(let a, let b): return .union(sub(a), sub(b))
        case .intersection(let a, let b): return .intersection(sub(a), sub(b))
        case .setDifference(let a, let b): return .setDifference(sub(a), sub(b))
        case .cardinality(let s): return .cardinality(sub(s))
        case .setFilter(let set, let binder, let predicate):
            let scoped = underBinder(binder, body: predicate)
            return .setFilter(sub(set), scoped.name, scoped.body)
        case .setMap(let value, let binder, let set):
            let scoped = underBinder(binder, body: value)
            return .setMap(scoped.body, scoped.name, sub(set))
        case .powerSet(let s): return .powerSet(sub(s))
        case .unionAll(let s): return .unionAll(sub(s))
        case .integerRange(let lower, let upper): return .integerRange(sub(lower), sub(upper))
        case .tupleLiteral(let es): return .tupleLiteral(es.map(sub))
        case .tupleAccess(let t, let i): return .tupleAccess(sub(t), i)
        case .tupleDynamicAccess(let tuple, let index): return .tupleDynamicAccess(sub(tuple), sub(index))
        case .tupleLength(let t): return .tupleLength(sub(t))
        case .tupleAppend(let t, let e): return .tupleAppend(sub(t), sub(e))
        case .tupleHead(let t): return .tupleHead(sub(t))
        case .tupleTail(let t): return .tupleTail(sub(t))
        case .tupleConcatenate(let a, let b): return .tupleConcatenate(sub(a), sub(b))
        case .recordLiteral(let record):
            return .recordLiteral(.init(record.fields.map { .init(name: $0.name, value: sub($0.value)) }))
        case .recordAccess(let r, let f): return .recordAccess(sub(r), f)
        case .domain(let f): return .domain(sub(f))
        case .functionLiteral(let domain, let binder, let body):
            let scoped = underBinder(binder, body: body)
            return .functionLiteral(sub(domain), scoped.name, scoped.body)
        case .functionApply(let f, let x): return .functionApply(sub(f), sub(x))
        case .except(let f, let x, let e): return .except(sub(f), sub(x), sub(e))
        case .caseExpr(let ps, let fb): return .caseExpr(ps.map(sub), fb.map(sub))
        case .forAll(let set, let binder, let predicate):
            let scoped = underBinder(binder, body: predicate)
            return .forAll(sub(set), scoped.name, scoped.body)
        case .exists(let set, let binder, let predicate):
            let scoped = underBinder(binder, body: predicate)
            return .exists(sub(set), scoped.name, scoped.body)
        case .choose(let set, let binder, let predicate):
            let scoped = underBinder(binder, body: predicate)
            return .choose(sub(set), scoped.name, scoped.body)
        case .sequenceFromSet(let s): return .sequenceFromSet(sub(s))
        case .setSum(let f, let s): return .setSum(sub(f), sub(s))
        case .functionSet(let d, let r): return .functionSet(sub(d), sub(r))
        case .foldFunction(let operation, let initial, let sequence):
            let scoped = underParameters(operation.parameters, body: operation.body)
            return .foldFunction(
                FormalLambda(parameters: scoped.parameters, body: scoped.body),
                initial: sub(initial),
                sequence: sub(sequence)
            )
        case .operatorApplication(let operation, let arguments):
            let substitutedOperator: FormalOperator
            switch operation {
            case .lambda(let lambda):
                let scoped = underParameters(lambda.parameters, body: lambda.body)
                substitutedOperator = .lambda(FormalLambda(parameters: scoped.parameters, body: scoped.body))
            case .reference:
                substitutedOperator = operation
            }
            return .operatorApplication(substitutedOperator, arguments.map { argument -> FormalCallArgument in
                switch argument {
                case .value(let value): return .value(sub(value))
                case .operator(.reference(let name, let arity)):
                    return .operator(.reference(name, arity: arity))
                case .operator(.lambda(let lambda)):
                    let scoped = underParameters(lambda.parameters, body: lambda.body)
                    return .operator(.lambda(FormalLambda(parameters: scoped.parameters, body: scoped.body)))
                }
            })
        case .recursiveCall(let n, let a): return .recursiveCall(n, a.map(sub))
        case .letValue(let binder, let value, let body):
            let scoped = underBinder(binder, body: body)
            return .letValue(scoped.name, sub(value), scoped.body)
        case .letIn(let operators, let body):
            return .letIn(
                operators.map { operation in
                    let scoped = underParameters(operation.parameters, body: operation.body)
                    return LocalOperator(
                        operation.name,
                        parameters: scoped.parameters,
                        domain: operation.domain.map(sub),
                        body: scoped.body
                    )
                },
                sub(body)
            )
        }

        func sub(_ expression: StateExpr) -> StateExpr {
            Self.substituteVariable(name, with: replacement, in: expression)
        }
    }

    static func renamingRecursiveCalls(
        in expression: StateExpr,
        using rename: (String) -> String,
        lowerAnonymousLambdaApplications: Bool = false,
        lowerLocalFunctionApplications: [String: String] = [:]
    ) -> StateExpr {
        var activeLocalFunctionApplications = lowerLocalFunctionApplications
        func visitUnderBindings(_ names: Set<String>, _ expression: StateExpr) -> StateExpr {
            let outerApplications = activeLocalFunctionApplications
            activeLocalFunctionApplications = outerApplications.filter { !names.contains($0.key) }
            let result = visit(expression)
            activeLocalFunctionApplications = outerApplications
            return result
        }
        func visit(_ expression: StateExpr) -> StateExpr {
            switch expression {
            case .value, .variable, .enabledAction: return expression
            case .add(let a, let b): return .add(visit(a), visit(b))
            case .subtract(let a, let b): return .subtract(visit(a), visit(b))
            case .multiply(let a, let b): return .multiply(visit(a), visit(b))
            case .divide(let a, let b): return .divide(visit(a), visit(b))
            case .modulo(let a, let b): return .modulo(visit(a), visit(b))
            case .negate(let value): return .negate(visit(value))
            case .integerDivide(let a, let b): return .integerDivide(visit(a), visit(b))
            case .equal(let a, let b): return .equal(visit(a), visit(b))
            case .notEqual(let a, let b): return .notEqual(visit(a), visit(b))
            case .lessThan(let a, let b): return .lessThan(visit(a), visit(b))
            case .lessOrEqual(let a, let b): return .lessOrEqual(visit(a), visit(b))
            case .greaterThan(let a, let b): return .greaterThan(visit(a), visit(b))
            case .greaterOrEqual(let a, let b): return .greaterOrEqual(visit(a), visit(b))
            case .and(let a, let b): return .and(visit(a), visit(b))
            case .or(let a, let b): return .or(visit(a), visit(b))
            case .not(let value): return .not(visit(value))
            case .ifThenElse(let c, let t, let e): return .ifThenElse(visit(c), visit(t), visit(e))
            case .setLiteral(let values): return .setLiteral(values.map(visit))
            case .in(let value, let set): return .in(visit(value), visit(set))
            case .subset(let a, let b): return .subset(visit(a), visit(b))
            case .union(let a, let b): return .union(visit(a), visit(b))
            case .intersection(let a, let b): return .intersection(visit(a), visit(b))
            case .setDifference(let a, let b): return .setDifference(visit(a), visit(b))
            case .cardinality(let value): return .cardinality(visit(value))
            case .setFilter(let set, let name, let body): return .setFilter(visit(set), name, visitUnderBindings([name], body))
            case .setMap(let value, let name, let set): return .setMap(visitUnderBindings([name], value), name, visit(set))
            case .powerSet(let value): return .powerSet(visit(value))
            case .unionAll(let value): return .unionAll(visit(value))
            case .integerRange(let lower, let upper): return .integerRange(visit(lower), visit(upper))
            case .tupleLiteral(let values): return .tupleLiteral(values.map(visit))
            case .tupleAccess(let value, let index): return .tupleAccess(visit(value), index)
            case .tupleDynamicAccess(let value, let index): return .tupleDynamicAccess(visit(value), visit(index))
            case .tupleLength(let value): return .tupleLength(visit(value))
            case .tupleAppend(let tuple, let value): return .tupleAppend(visit(tuple), visit(value))
            case .tupleHead(let value): return .tupleHead(visit(value))
            case .tupleTail(let value): return .tupleTail(visit(value))
            case .tupleConcatenate(let a, let b): return .tupleConcatenate(visit(a), visit(b))
            case .recordLiteral(let record):
                return .recordLiteral(.init(record.fields.map { .init(name: $0.name, value: visit($0.value)) }))
            case .recordAccess(let value, let field): return .recordAccess(visit(value), field)
            case .domain(let value): return .domain(visit(value))
            case .functionLiteral(let domain, let name, let body): return .functionLiteral(visit(domain), name, visitUnderBindings([name], body))
            case .functionApply(.variable(let name), let value):
                if let localName = activeLocalFunctionApplications[name] {
                    return .recursiveCall(localName, [visit(value)])
                }
                return .functionApply(.variable(name), visit(value))
            case .functionApply(let function, let value): return .functionApply(visit(function), visit(value))
            case .except(let function, let value, let update): return .except(visit(function), visit(value), visit(update))
            case .caseExpr(let pairs, let fallback): return .caseExpr(pairs.map(visit), fallback.map(visit))
            case .forAll(let set, let name, let body): return .forAll(visit(set), name, visitUnderBindings([name], body))
            case .exists(let set, let name, let body): return .exists(visit(set), name, visitUnderBindings([name], body))
            case .choose(let set, let name, let body): return .choose(visit(set), name, visitUnderBindings([name], body))
            case .sequenceFromSet(let value): return .sequenceFromSet(visit(value))
            case .setSum(let function, let set): return .setSum(visit(function), visit(set))
            case .functionSet(let domain, let range): return .functionSet(visit(domain), visit(range))
            case .foldFunction(let operation, let initial, let sequence):
                return .foldFunction(
                    FormalLambda(parameters: operation.parameters, body: visitUnderBindings(Set(operation.parameters), operation.body)),
                    initial: visit(initial),
                    sequence: visit(sequence)
                )
            case .operatorApplication(let operation, let arguments):
                let renamedOperator: FormalOperator
                switch operation {
                case .lambda(let lambda):
                    renamedOperator = .lambda(FormalLambda(
                        parameters: lambda.parameters,
                        body: visitUnderBindings(Set(lambda.parameters), lambda.body)
                    ))
                case .reference(let name, let arity):
                    renamedOperator = .reference(rename(name), arity: arity)
                }
                let renamedArguments = arguments.map { argument -> FormalCallArgument in
                    switch argument {
                    case .value(let value): return .value(visit(value))
                    case .operator(.reference(let name, let arity)):
                        return .operator(.reference(rename(name), arity: arity))
                    case .operator(.lambda(let lambda)):
                        return .operator(.lambda(FormalLambda(
                            parameters: lambda.parameters,
                            body: visitUnderBindings(Set(lambda.parameters), lambda.body)
                        )))
                    }
                }
                if lowerAnonymousLambdaApplications,
                   case .lambda(let lambda) = renamedOperator,
                   lambda.parameters.count == renamedArguments.count,
                   renamedArguments.allSatisfy({
                       if case .value = $0 { return true }
                       return false
                   }) {
                    return zip(lambda.parameters, renamedArguments).reduce(lambda.body) { body, binding in
                        guard case .value(let argument) = binding.1 else { return body }
                        return Self.substituteVariable(binding.0, with: argument, in: body)
                    }
                }
                return .operatorApplication(renamedOperator, renamedArguments)
            case .recursiveCall(let name, let arguments): return .recursiveCall(rename(name), arguments.map(visit))
            case .letValue(let name, let value, let body):
                return .letValue(name, visit(value), visitUnderBindings([name], body))
            case .letIn(let operators, let body):
                let shadowed = Set(operators.map(\.name))
                let nestedApplications = activeLocalFunctionApplications.filter { !shadowed.contains($0.key) }
                let boundedOperators = Dictionary(
                    uniqueKeysWithValues: operators.compactMap { operation in
                        operation.domain == nil ? nil : (operation.name, operation.name)
                    }
                )
                let localApplications = nestedApplications.merging(boundedOperators) { _, inner in inner }
                let outerApplications = activeLocalFunctionApplications
                activeLocalFunctionApplications = nestedApplications
                let domains = operators.map { operation in operation.domain.map(visit) }
                activeLocalFunctionApplications = localApplications
                let bodies = operators.map { visitUnderBindings(Set($0.parameters), $0.body) }
                let loweredBody = visit(body)
                activeLocalFunctionApplications = outerApplications
                return .letIn(
                    zip(operators, zip(domains, bodies)).map { operation, lowered in
                        LocalOperator(
                            rename(operation.name),
                            parameters: operation.parameters,
                            domain: lowered.0,
                            body: lowered.1
                        )
                    },
                    loweredBody
                )
            }
        }
        return visit(expression)
    }
}
