/// One formal value that may have either of two declared shapes.
///
/// TLA+ values are not tagged when they belong to a union. `OneOf` preserves
/// that representation: `.first(value)` and `.second(value)` lower to the
/// contained formal value without adding a wrapper record. Use
/// `assumingFirst(_:)` or `assumingSecond(_:)` only where the algorithm's control flow establishes the
/// expected shape, as in a PlusCal variable that is used as a process ID in
/// one labeled region and as a set of process IDs in another.
public enum OneOf<First: TLAValueType, Second: TLAValueType>: TLAValueType, Sendable {
    case first(First)
    case second(Second)

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
    public static func first(_ value: Expr<First>) -> Expr<Self> {
        Expr(value.raw)
    }

    /// Lifts a symbolic value into the second formal alternative.
    public static func second(_ value: Expr<Second>) -> Expr<Self> {
        Expr(value.raw)
    }
}

extension Expr {
    /// Views a formal union as a known alternative in this control path.
    ///
    /// This is a formal type assertion, not a Swift runtime cast. The
    /// resulting expression has the same TLA+ value and is safe only when
    /// the surrounding labeled algorithm region establishes `Value`.
    public func assumingFirst<Value: TLAValueType, Other: TLAValueType>(
        _ type: Value.Type
    ) -> Expr<Value> where T == OneOf<Value, Other> {
        Expr<Value>(raw)
    }

    /// Views a formal union as its second known alternative.
    public func assumingSecond<First: TLAValueType, Value: TLAValueType>(
        _ type: Value.Type
    ) -> Expr<Value> where T == OneOf<First, Value> {
        Expr<Value>(raw)
    }
}
