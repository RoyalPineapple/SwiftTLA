enum AlgorithmAssignmentTargetPolicy {
    case preserve
    case replaceWhenVariable
    case reject(AlgorithmDiagnosticCode)
}

extension AlgorithmStatementModel {
    func replacingProcessLocalFamily(
        named name: String,
        with replacement: StateExpr
    ) -> AlgorithmStatementModel {
        replacingExpressions(with: replacement) {
            $0.replacingProcessLocalFamily(named: name, with: replacement)
        }
    }

    func replacingCurrentProcess(with replacement: StateExpr) -> AlgorithmStatementModel {
        replacingExpressions(with: replacement) { $0.replacingCurrentProcess(with: replacement) }
    }

    private func replacingExpressions(
        with replacement: StateExpr,
        _ transform: (StateExpr) -> StateExpr
    ) -> AlgorithmStatementModel {
        func expression(_ value: StateExpr) -> StateExpr { transform(value) }

        func target(_ value: AlgorithmLValueModel) -> AlgorithmLValueModel {
            switch value {
            case .root:
                value
            case .function(let root, let key):
                .function(root: root, key: expression(key))
            }
        }

        func scopedBody(
            variable: String,
            body: [AlgorithmStatementModel]
        ) -> (variable: String, body: [AlgorithmStatementModel]) {
            guard replacement.freeVariableNames.contains(variable) else {
                return (variable, body.map { $0.replacingExpressions(with: replacement, transform) })
            }
            let fresh = StateExpr.freshBoundName(
                variable,
                avoiding: body.algorithmScopeNames
                    .union(replacement.freeVariableNames)
                    .union([variable])
            )
            let renamed = body.map {
                $0.substitutingVariable(
                    variable,
                    with: .variable(fresh),
                    assignmentTargets: .replaceWhenVariable
                )
            }
            return (fresh, renamed.map { $0.replacingExpressions(with: replacement, transform) })
        }

        return switch self {
        case .rejected, .goto, .return, .stop, .skip:
            self
        case .await(let value):
            .await(expression(value))
        case .assert(let value):
            .assert(expression(value))
        case .set(let originalTarget, let value):
            .set(target: target(originalTarget), value: expression(value))
        case .letBinding(let variable, let value, let body):
            { () -> AlgorithmStatementModel in
                let scoped = scopedBody(variable: variable, body: body)
                return .letBinding(variable: scoped.variable, value: expression(value), scoped.body)
            }()
        case .with(let variable, let source, let body):
            { () -> AlgorithmStatementModel in
                let scoped = scopedBody(variable: variable, body: body)
                return .with(variable: scoped.variable, source: expression(source), scoped.body)
            }()
        case .ifElse(let condition, let then, let otherwise):
            .ifElse(
                expression(condition),
                then.map { $0.replacingExpressions(with: replacement, transform) },
                otherwise.map { $0.replacingExpressions(with: replacement, transform) }
            )
        case .either(let first, let second):
            .either(
                first.map { $0.replacingExpressions(with: replacement, transform) },
                second.map { $0.replacingExpressions(with: replacement, transform) }
            )
        case .choose(let variable, let domain, let body):
            { () -> AlgorithmStatementModel in
                let scoped = scopedBody(variable: variable, body: body)
                return .choose(variable: scoped.variable, domain: domain, scoped.body)
            }()
        case .call(let target, let arguments):
            .call(target: target, arguments: arguments.map(expression))
        }
    }

    func substitutingVariable(
        _ name: String,
        with replacement: StateExpr,
        assignmentTargets: AlgorithmAssignmentTargetPolicy
    ) -> AlgorithmStatementModel {
        func expression(_ value: StateExpr) -> StateExpr {
            StateExpr.substituteVariable(name, with: replacement, in: value)
        }

        func target(_ value: AlgorithmLValueModel) -> AlgorithmLValueModel? {
            func substitutedRoot(_ root: String) -> String? {
                guard root == name else { return root }
                switch assignmentTargets {
                case .preserve:
                    return root
                case .replaceWhenVariable:
                    guard case .variable(let replacementRoot) = replacement else { return root }
                    return replacementRoot
                case .reject(_):
                    guard case .variable(let replacementRoot) = replacement else { return nil }
                    return replacementRoot
                }
            }

            switch value {
            case .root(let targetRoot):
                return substitutedRoot(targetRoot).map(AlgorithmLValueModel.root)
            case .function(let targetRoot, let key):
                return substitutedRoot(targetRoot).map { .function(root: $0, key: expression(key)) }
            }
        }

        func scopedBody(
            variable: String,
            body: [AlgorithmStatementModel]
        ) -> (variable: String, body: [AlgorithmStatementModel]) {
            guard variable != name else { return (variable, body) }
            guard replacement.freeVariableNames.contains(variable) else {
                return (
                    variable,
                    body.map {
                        $0.substitutingVariable(
                            name,
                            with: replacement,
                            assignmentTargets: assignmentTargets
                        )
                    }
                )
            }

            let fresh = StateExpr.freshBoundName(
                variable,
                avoiding: body.algorithmScopeNames
                    .union(replacement.freeVariableNames)
                    .union([name, variable])
            )
            let renamed = body.map {
                $0.substitutingVariable(
                    variable,
                    with: .variable(fresh),
                    assignmentTargets: .replaceWhenVariable
                )
            }
            return (
                fresh,
                renamed.map {
                    $0.substitutingVariable(
                        name,
                        with: replacement,
                        assignmentTargets: assignmentTargets
                    )
                }
            )
        }

        switch self {
        case .rejected, .goto, .return, .stop, .skip:
            return self
        case .await(let value):
            return .await(expression(value))
        case .assert(let value):
            return .assert(expression(value))
        case .set(let originalTarget, let value):
            guard let substitutedTarget = target(originalTarget) else {
                guard case .reject(let diagnostic) = assignmentTargets else {
                    return self
                }
                return .rejected(diagnostic)
            }
            return .set(target: substitutedTarget, value: expression(value))
        case .letBinding(let variable, let value, let body):
            let scoped = scopedBody(variable: variable, body: body)
            return .letBinding(variable: scoped.variable, value: expression(value), scoped.body)
        case .with(let variable, let source, let body):
            let scoped = scopedBody(variable: variable, body: body)
            return .with(variable: scoped.variable, source: expression(source), scoped.body)
        case .ifElse(let condition, let then, let otherwise):
            return .ifElse(
                expression(condition),
                then.map { $0.substitutingVariable(name, with: replacement, assignmentTargets: assignmentTargets) },
                otherwise.map { $0.substitutingVariable(name, with: replacement, assignmentTargets: assignmentTargets) }
            )
        case .either(let first, let second):
            return .either(
                first.map { $0.substitutingVariable(name, with: replacement, assignmentTargets: assignmentTargets) },
                second.map { $0.substitutingVariable(name, with: replacement, assignmentTargets: assignmentTargets) }
            )
        case .choose(let variable, let domain, let body):
            let scoped = scopedBody(variable: variable, body: body)
            return .choose(variable: scoped.variable, domain: domain, scoped.body)
        case .call(let target, let arguments):
            return .call(target: target, arguments: arguments.map(expression))
        }
    }
}

private extension Array where Element == AlgorithmStatementModel {
    var algorithmScopeNames: Set<String> {
        reduce(into: []) { names, statement in
            switch statement {
            case .await(let value), .assert(let value):
                names.formUnion(value.freeVariableNames)
            case .set(let target, let value):
                names.insert(target.root)
                names.formUnion(value.freeVariableNames)
                if case .function(_, let key) = target {
                    names.formUnion(key.freeVariableNames)
                }
            case .letBinding(let variable, let value, let body):
                names.insert(variable)
                names.formUnion(value.freeVariableNames)
                names.formUnion(body.algorithmScopeNames)
            case .with(let variable, let source, let body):
                names.insert(variable)
                names.formUnion(source.freeVariableNames)
                names.formUnion(body.algorithmScopeNames)
            case .choose(let variable, _, let body):
                names.insert(variable)
                names.formUnion(body.algorithmScopeNames)
            case .ifElse(let condition, let then, let otherwise):
                names.formUnion(condition.freeVariableNames)
                names.formUnion(then.algorithmScopeNames)
                names.formUnion(otherwise.algorithmScopeNames)
            case .either(let then, let otherwise):
                names.formUnion(then.algorithmScopeNames)
                names.formUnion(otherwise.algorithmScopeNames)
            case .call(_, let arguments):
                arguments.forEach { names.formUnion($0.freeVariableNames) }
            case .rejected, .goto, .return, .stop, .skip:
                break
            }
        }
    }
}
