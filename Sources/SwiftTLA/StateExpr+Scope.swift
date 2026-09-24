extension StateExpr {
    /// Names that this expression reads from its surrounding formal scope.
    ///
    /// Quantifiers, functions, local operators, and formal lambdas remove their
    /// bound names. Substitution uses this set to avoid binder capture.
    package var freeVariableNames: Set<String> {
        var pending: [(StateExpr, Set<String>)] = [(self, [])]
        var names: Set<String> = []
        func schedule(_ values: [StateExpr], bound: Set<String>) {
            pending.append(contentsOf: values.map { ($0, bound) })
        }
        func schedule(_ operation: FormalOperator, bound: Set<String>) {
            if case .lambda(let lambda) = operation {
                pending.append((lambda.body, bound.union(lambda.parameters)))
            }
        }
        while let (expression, bound) = pending.popLast() {
            switch expression {
            case .sourceIssue, .value, .integerSet, .parameter, .checkingRegister, .checkingLevel, .currentProcess, .programCounter, .procedureStack, .controlLocation, .enabledAction:
                break
            case .setCheckingRegister(_, let value):
                pending.append((value, bound))
            case .variable(let name):
                if !bound.contains(name) { names.insert(name) }
            case .processLocalFamily(let name):
                if !bound.contains(name) { names.insert(name) }
            case .stutteringStep(let lhs, let rhs), .add(let lhs, let rhs), .subtract(let lhs, let rhs),
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
                schedule([lhs, rhs], bound: bound)
            case .assertView(let value, _), .nextState(let value), .negate(let value), .not(let value), .cardinality(let value),
                 .powerSet(let value), .sequenceSet(let value), .unionAll(let value), .tupleLength(let value),
                 .tupleHead(let value), .tupleTail(let value), .domain(let value),
                 .sequenceFromSet(let value):
                pending.append((value, bound))
            case .ifThenElse(let condition, let then, let otherwise):
                schedule([condition, then, otherwise], bound: bound)
            case .setLiteral(let values), .tupleLiteral(let values):
                schedule(values, bound: bound)
            case .in(let value, let set):
                schedule([value, set], bound: bound)
            case .integerRange(let lower, let upper), .tupleDynamicAccess(let lower, let upper):
                schedule([lower, upper], bound: bound)
            case .except(let function, let key, let value):
                schedule([function, key, value], bound: bound)
            case .tupleAccess(let value, _):
                pending.append((value, bound))
            case .tupleRemoving(let tuple, let index):
                schedule([tuple, index], bound: bound)
            case .sequenceSelect(let sequence, let name, let predicate):
                pending.append((sequence, bound))
                pending.append((predicate, bound.union([name])))
            case .recordLiteral(let fields):
                schedule(fields.fields.map(\.value), bound: bound)
            case .recordAccess(let value, _):
                pending.append((value, bound))
            case .caseExpr(let pairs, let fallback):
                schedule(pairs, bound: bound)
                if let fallback { pending.append((fallback, bound)) }
            case .setFilter(let set, let name, let predicate):
                pending.append((set, bound))
                pending.append((predicate, bound.union([name])))
            case .setMap(let value, let name, let set):
                pending.append((set, bound))
                pending.append((value, bound.union([name])))
            case .functionLiteral(let domain, let name, let body):
                pending.append((domain, bound))
                pending.append((body, bound.union([name])))
            case .forAll(let set, let name, let predicate),
                 .exists(let set, let name, let predicate),
                 .choose(let set, let name, let predicate):
                pending.append((set, bound))
                pending.append((predicate, bound.union([name])))
            case .setSum(let function, let set):
                schedule([function, set], bound: bound)
            case .foldFunction(let operation, let initial, let sequence):
                pending.append((operation.body, bound.union(operation.parameters)))
                schedule([initial, sequence], bound: bound)
            case .operatorApplication(let operation, let arguments):
                schedule(operation, bound: bound)
                for argument in arguments {
                    switch argument {
                    case .value(let value): pending.append((value, bound))
                    case .operator(let operation): schedule(operation, bound: bound)
                    }
                }
            case .recursiveCall(_, let arguments):
                schedule(arguments, bound: bound)
            case .letValue(let name, let value, let body):
                pending.append((value, bound))
                pending.append((body, bound.union([name])))
            case .letIn(let operators, let body):
                for operation in operators {
                    if let domain = operation.domain { pending.append((domain, bound)) }
                    pending.append((operation.body, bound.union(operation.parameters)))
                }
                pending.append((body, bound))
            }
        }
        return names
    }

    package static func freshBoundName(_ preferred: String, avoiding names: Set<String>) -> String {
        guard names.contains(preferred) else { return preferred }
        var suffix = 1
        while names.contains("\(preferred)_\(suffix)") {
            suffix += 1
        }
        return "\(preferred)_\(suffix)"
    }
}
