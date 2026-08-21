extension ParserSession {
    /// A Swift `let` is an authoring alias. Substitute it before constructing
    /// the algorithm model so the parser and runtime builder describe the
    /// same formal action.
    func substituteAlgorithmVariable(
        _ statement: AlgorithmStatementModel,
        from name: String,
        with replacement: StateExpr
    ) -> AlgorithmStatementModel {
        func expression(_ value: StateExpr) -> StateExpr {
            StateExpr.substituteVariable(name, with: replacement, in: value)
        }
        switch statement {
        case .rejected: return statement
        case .await(let value): return .await(expression(value))
        case .assert(let value): return .assert(expression(value))
        case .set(let target, let value):
            let rewritten: AlgorithmLValueModel
            switch target {
            case .root(let root):
                if root == name, case .variable(let replacementRoot) = replacement {
                    rewritten = .root(replacementRoot)
                } else {
                    rewritten = .root(root)
                }
            case .function(let root, let key):
                let rewrittenRoot: String
                if root == name, case .variable(let replacementRoot) = replacement {
                    rewrittenRoot = replacementRoot
                } else {
                    rewrittenRoot = root
                }
                rewritten = .function(root: rewrittenRoot, key: expression(key))
            }
            return .set(target: rewritten, value: expression(value))
        case .letBinding(let variable, let value, let body):
            return .letBinding(
                variable: variable,
                value: expression(value),
                variable == name ? body : body.map { substituteAlgorithmVariable($0, from: name, with: replacement) }
            )
        case .with(let variable, let source, let body):
            return .with(
                variable: variable,
                source: expression(source),
                variable == name ? body : body.map { substituteAlgorithmVariable($0, from: name, with: replacement) }
            )
        case .ifElse(let condition, let then, let otherwise):
            return .ifElse(
                expression(condition),
                then.map { substituteAlgorithmVariable($0, from: name, with: replacement) },
                otherwise.map { substituteAlgorithmVariable($0, from: name, with: replacement) }
            )
        case .either(let first, let second):
            return .either(
                first.map { substituteAlgorithmVariable($0, from: name, with: replacement) },
                second.map { substituteAlgorithmVariable($0, from: name, with: replacement) }
            )
        case .choose(let variable, let domain, let body):
            return .choose(
                variable: variable,
                domain: domain,
                variable == name ? body : body.map { substituteAlgorithmVariable($0, from: name, with: replacement) }
            )
        case .call(let target, let arguments): return .call(target: target, arguments: arguments.map(expression))
        case .goto, .return, .stop, .skip: return statement
        }
    }
}
