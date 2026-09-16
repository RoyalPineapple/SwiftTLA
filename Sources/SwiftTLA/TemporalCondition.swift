/// A temporal requirement over predicates, shared by compilation and native checking.
public enum TemporalCondition<Expression: Sendable>: Sendable {
    case always(Expression)
    case eventually(Expression)
    case alwaysEventually(Expression)
    case eventuallyAlways(Expression)
    case leadsTo(Expression, Expression)
    case all([Self])

    public var predicates: [Expression] {
        switch self {
        case .always(let value), .eventually(let value), .alwaysEventually(let value), .eventuallyAlways(let value): [value]
        case .leadsTo(let source, let target): [source, target]
        case .all(let conditions): conditions.flatMap(\.predicates)
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
        case .all(let conditions): .all(try conditions.map { try $0.map(transform) })
        }
    }
}

extension TemporalCondition: Equatable where Expression: Equatable {}
extension TemporalCondition: Hashable where Expression: Hashable {}

extension TemporalCondition: CustomStringConvertible where Expression: CustomStringConvertible {
    public var description: String {
        switch self {
        case .always(let predicate): "[](\(predicate))"
        case .eventually(let predicate): "<>(\(predicate))"
        case .alwaysEventually(let predicate): "[]<>(\(predicate))"
        case .eventuallyAlways(let predicate): "<>[](\(predicate))"
        case .leadsTo(let source, let target): "(\(source) ~> \(target))"
        case .all(let conditions): conditions.isEmpty ? "TRUE" : "(" + conditions.map(\.description).joined(separator: " /\\ ") + ")"
        }
    }
}

extension TypedExpression where ExpressionValue == Bool {
    public func leadsTo(_ target: some TypedExpression<Bool>) -> TemporalCondition<StateExpr> {
        .leadsTo(stateExpr, target.stateExpr)
    }
}
