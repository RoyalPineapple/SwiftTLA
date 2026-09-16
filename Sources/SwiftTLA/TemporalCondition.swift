/// A temporal requirement over predicates, shared by compilation and native checking.
public enum TemporalCondition<Expression: Sendable>: Sendable {
    case always(Expression)
    case eventually(Expression)
    case alwaysEventually(Expression)
    case eventuallyAlways(Expression)
    case leadsTo(Expression, Expression)
    case all([Self])
    indirect case conditional(Expression, then: Self, else: Self)

    public var predicates: [Expression] {
        switch self {
        case .always(let value), .eventually(let value), .alwaysEventually(let value), .eventuallyAlways(let value): [value]
        case .leadsTo(let source, let target): [source, target]
        case .all(let conditions): conditions.flatMap(\.predicates)
        case .conditional(let predicate, let yes, let no): [predicate] + yes.predicates + no.predicates
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
        case .conditional(let predicate, let yes, let no):
            .conditional(try transform(predicate), then: try yes.map(transform), else: try no.map(transform))
        }
    }
}

extension TemporalCondition: Equatable where Expression: Equatable {}
extension TemporalCondition where Expression == Expr<Bool> {
    public static func alwaysStep<Value: TLAValueType>(
        on value: some TypedExpression<Value>,
        _ predicate: (Expr<Value>, Expr<Value>) -> some TypedExpression<Bool>
    ) -> Self {
        let next = Expr<Value>(.nextState(value.stateExpr))
        return .always(Expr(.or(.equal(value.stateExpr, next.stateExpr),
            predicate(value.expr, next).stateExpr)))
    }

    @_disfavoredOverload
    public static func always(_ predicate: some TypedExpression<Bool>) -> Self { .always(predicate.expr) }
    @_disfavoredOverload
    public static func eventually(_ predicate: some TypedExpression<Bool>) -> Self { .eventually(predicate.expr) }
    @_disfavoredOverload
    public static func alwaysEventually(_ predicate: some TypedExpression<Bool>) -> Self { .alwaysEventually(predicate.expr) }
    @_disfavoredOverload
    public static func eventuallyAlways(_ predicate: some TypedExpression<Bool>) -> Self { .eventuallyAlways(predicate.expr) }
    @_disfavoredOverload
    public static func leadsTo(_ source: some TypedExpression<Bool>, _ target: some TypedExpression<Bool>) -> Self {
        .leadsTo(source.expr, target.expr)
    }
    @_disfavoredOverload
    public static func conditional(_ predicate: some TypedExpression<Bool>, then yes: Self, else no: Self) -> Self {
        .conditional(predicate.expr, then: yes, else: no)
    }
}
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
        case .conditional(let predicate, let yes, let no): "(IF \(predicate) THEN \(yes) ELSE \(no))"
        }
    }
}

extension TypedExpression where ExpressionValue == Bool {
    public func leadsTo(_ target: some TypedExpression<Bool>) -> TemporalCondition<Expr<Bool>> {
        .leadsTo(expr, target.expr)
    }
}
