/// A temporal requirement over predicates, shared by compilation and native checking.
public enum TemporalCondition<Expression: Sendable>: Sendable {
    case always(Expression)
    case eventually(Expression)
    case alwaysEventually(Expression)
    case eventuallyAlways(Expression)
    case leadsTo(Expression, Expression)

    public var predicates: [Expression] {
        switch self {
        case .always(let value), .eventually(let value), .alwaysEventually(let value), .eventuallyAlways(let value): [value]
        case .leadsTo(let source, let target): [source, target]
        }
    }

    public func map<Result: Sendable>(
        _ transform: (Expression) throws -> Result
    ) rethrows -> TemporalCondition<Result> {
        switch self {
        case .always(let predicate): .always(try transform(predicate))
        case .eventually(let predicate): .eventually(try transform(predicate))
        case .alwaysEventually(let predicate): .alwaysEventually(try transform(predicate))
        case .eventuallyAlways(let predicate): .eventuallyAlways(try transform(predicate))
        case .leadsTo(let source, let target): .leadsTo(try transform(source), try transform(target))
        }
    }
}

