/// One formal value that may have either of two declared shapes.
///
/// `OneOf` preserves the underlying TLA+ value representation. Use
/// `assuming(_:)` where the algorithm's control
/// flow establishes the expected shape.
public enum OneOf<First: TLAValueType, Second: TLAValueType>: TLAValueType, Sendable {
    case first(First)
    case second(Second)

    public static var formalValueShape: FormalValueShape { .union(First.formalValueShape, Second.formalValueShape) }

    public static var defaultValue: Self { .first(First.defaultValue) }

    public init?(formalValue: TLAValue) {
        if let first = First(formalValue: formalValue) {
            self = .first(first)
        } else if let second = Second(formalValue: formalValue) {
            self = .second(second)
        } else {
            return nil
        }
    }

    public var tlaValue: TLAValue {
        switch self {
        case .first(let value): value.tlaValue
        case .second(let value): value.tlaValue
        }
    }

    /// Lifts a symbolic value into the first formal alternative.
    public static func first(_ value: some TypedExpression<First>) -> Expr<Self> {
        Expr(value.stateExpr)
    }

    /// Lifts a symbolic value into the second formal alternative.
    public static func second(_ value: some TypedExpression<Second>) -> Expr<Self> {
        Expr(value.stateExpr)
    }
}

extension OneOf: Equatable where First: Equatable, Second: Equatable {}

extension TypedExpression {
    /// Checks that the formal value has the requested shape before exposing it
    /// through a typed expression. A mismatched value fails during execution.
    public func assuming<Expected: TLAValueType>(_ type: Expected.Type) -> Expr<Expected> {
        Expr<Expected>(.assertView(stateExpr, Expected.formalValueShape))
    }
}
