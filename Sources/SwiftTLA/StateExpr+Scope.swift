extension StateExpr {
    /// Names that this expression reads from its surrounding formal scope.
    ///
    /// Bound names from quantifiers, functions, local operators, and formal
    /// lambdas are removed here. This gives substitution one source of truth
    /// for deciding when it must rename a binder to avoid capture.
    var freeVariableNames: Set<String> {
        return switch self {
        case .sourceIssue, .value, .programCounter, .controlLocation, .enabledAction:
            []
        case .variable(let name):
            [name]
        case .add(let lhs, let rhs), .subtract(let lhs, let rhs),
             .multiply(let lhs, let rhs), .divide(let lhs, let rhs),
             .modulo(let lhs, let rhs), .integerDivide(let lhs, let rhs),
             .equal(let lhs, let rhs), .notEqual(let lhs, let rhs),
             .lessThan(let lhs, let rhs), .lessOrEqual(let lhs, let rhs),
             .greaterThan(let lhs, let rhs), .greaterOrEqual(let lhs, let rhs),
             .and(let lhs, let rhs), .or(let lhs, let rhs),
             .subset(let lhs, let rhs), .union(let lhs, let rhs),
             .intersection(let lhs, let rhs), .setDifference(let lhs, let rhs),
             .tupleAppend(let lhs, let rhs), .tupleConcatenate(let lhs, let rhs),
             .functionApply(let lhs, let rhs), .functionSet(let lhs, let rhs):
            lhs.freeVariableNames.union(rhs.freeVariableNames)
        case .negate(let value), .not(let value), .cardinality(let value),
             .powerSet(let value), .unionAll(let value), .tupleLength(let value),
             .tupleHead(let value), .tupleTail(let value), .domain(let value),
             .sequenceFromSet(let value):
            value.freeVariableNames
        case .ifThenElse(let condition, let then, let otherwise):
            condition.freeVariableNames
                .union(then.freeVariableNames)
                .union(otherwise.freeVariableNames)
        case .setLiteral(let values), .tupleLiteral(let values):
            values.reduce(into: Set<String>()) { $0.formUnion($1.freeVariableNames) }
        case .in(let value, let set):
            value.freeVariableNames.union(set.freeVariableNames)
        case .integerRange(let lower, let upper), .tupleDynamicAccess(let lower, let upper):
            lower.freeVariableNames.union(upper.freeVariableNames)
        case .except(let function, let key, let value):
            function.freeVariableNames
                .union(key.freeVariableNames)
                .union(value.freeVariableNames)
        case .tupleAccess(let value, _):
            value.freeVariableNames
        case .recordLiteral(let fields):
            fields.fields.reduce(into: Set<String>()) { $0.formUnion($1.value.freeVariableNames) }
        case .recordAccess(let value, _):
            value.freeVariableNames
        case .caseExpr(let pairs, let fallback):
            pairs.reduce(into: fallback?.freeVariableNames ?? []) {
                $0.formUnion($1.freeVariableNames)
            }
        case .setFilter(let set, let name, let predicate):
            set.freeVariableNames.union(predicate.freeVariableNames.subtracting([name]))
        case .setMap(let value, let name, let set):
            set.freeVariableNames.union(value.freeVariableNames.subtracting([name]))
        case .functionLiteral(let domain, let name, let body):
            domain.freeVariableNames.union(body.freeVariableNames.subtracting([name]))
        case .forAll(let set, let name, let predicate),
             .exists(let set, let name, let predicate),
             .choose(let set, let name, let predicate):
            set.freeVariableNames.union(predicate.freeVariableNames.subtracting([name]))
        case .setSum(let function, let set):
            function.freeVariableNames.union(set.freeVariableNames)
        case .foldFunction(let operation, let initial, let sequence):
            operation.body.freeVariableNames
                .subtracting(Set(operation.parameters))
                .union(initial.freeVariableNames)
                .union(sequence.freeVariableNames)
        case .operatorApplication(let operation, let arguments):
            {
                let operatorVariables: Set<String>
                switch operation {
                case .lambda(let lambda):
                    operatorVariables = lambda.body.freeVariableNames.subtracting(Set(lambda.parameters))
                case .reference:
                    operatorVariables = []
                }
                return arguments.reduce(into: operatorVariables) { $0.formUnion($1.freeVariableNames) }
            }()
        case .recursiveCall(_, let arguments):
            arguments.reduce(into: Set<String>()) { $0.formUnion($1.freeVariableNames) }
        case .letValue(let name, let value, let body):
            value.freeVariableNames.union(body.freeVariableNames.subtracting([name]))
        case .letIn(let operators, let body):
            {
                let operatorVariables = operators.reduce(into: Set<String>()) { names, operation in
                    names.formUnion(operation.domain?.freeVariableNames ?? [])
                    names.formUnion(operation.body.freeVariableNames.subtracting(Set(operation.parameters)))
                }
                return operatorVariables.union(body.freeVariableNames)
            }()
        }
    }

    static func freshBoundName(_ preferred: String, avoiding names: Set<String>) -> String {
        guard names.contains(preferred) else { return preferred }
        var suffix = 1
        while names.contains("\(preferred)_\(suffix)") {
            suffix += 1
        }
        return "\(preferred)_\(suffix)"
    }
}

private extension FormalCallArgument {
    var freeVariableNames: Set<String> {
        switch self {
        case .value(let expression): expression.freeVariableNames
        case .operator(.lambda(let lambda)):
            lambda.body.freeVariableNames.subtracting(Set(lambda.parameters))
        case .operator(.reference): []
        }
    }
}
