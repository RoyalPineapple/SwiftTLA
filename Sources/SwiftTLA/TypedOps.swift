// MARK: - Declarative operator set

public enum TypedOp: String, CaseIterable, Sendable {
    case add, subtract, multiply, divide, modulo, negate
    case not, and, or
    case lessThan, greaterThan, lessOrEqual, greaterOrEqual, equal, notEqual
}

/// Types that support typed operators declare their supported set.
/// The code generator reads `ops` and produces the operator overloads below.
protocol GenerableOps {
    static var ops: Set<TypedOp> { get }
}
extension GenerableOps {
    static var ops: Set<TypedOp> { [] }
}

extension Int: GenerableOps {
    static let ops: Set<TypedOp> = [.add, .subtract, .multiply, .divide, .modulo, .negate,
                                     .lessThan, .greaterThan, .lessOrEqual, .greaterOrEqual,
                                     .equal, .notEqual]
}
extension Bool: GenerableOps {
    static let ops: Set<TypedOp> = [.not, .and, .or, .equal, .notEqual]
}
extension String: GenerableOps {
    static let ops: Set<TypedOp> = [.add, .equal, .notEqual]
}

// MARK: - Generated operators

extension Var where T == Int {
    public static func +(_ lhs: Var, _ rhs: Int) -> Expr<Int> { Expr(.add(lhs.stateExpr, .int(rhs))) }
    public static func +(_ lhs: Var, _ rhs: Var) -> Expr<Int> { Expr(.add(lhs.stateExpr, rhs.stateExpr)) }
    public static func +(_ lhs: Var, _ rhs: Expr<Int>) -> Expr<Int> { Expr(.add(lhs.stateExpr, rhs.raw)) }
    public static func -(_ lhs: Var, _ rhs: Int) -> Expr<Int> { Expr(.subtract(lhs.stateExpr, .int(rhs))) }
    public static func -(_ lhs: Var, _ rhs: Var) -> Expr<Int> { Expr(.subtract(lhs.stateExpr, rhs.stateExpr)) }
    public static func -(_ lhs: Var, _ rhs: Expr<Int>) -> Expr<Int> { Expr(.subtract(lhs.stateExpr, rhs.raw)) }
    public static func *(_ lhs: Var, _ rhs: Int) -> Expr<Int> { Expr(.multiply(lhs.stateExpr, .int(rhs))) }
    public static func *(_ lhs: Var, _ rhs: Var) -> Expr<Int> { Expr(.multiply(lhs.stateExpr, rhs.stateExpr)) }
    public static func *(_ lhs: Var, _ rhs: Expr<Int>) -> Expr<Int> { Expr(.multiply(lhs.stateExpr, rhs.raw)) }
    public static func /(_ lhs: Var, _ rhs: Int) -> Expr<Int> { Expr(.divide(lhs.stateExpr, .int(rhs))) }
    public static func /(_ lhs: Var, _ rhs: Var) -> Expr<Int> { Expr(.divide(lhs.stateExpr, rhs.stateExpr)) }
    public static func %(_ lhs: Var, _ rhs: Int) -> Expr<Int> { Expr(.modulo(lhs.stateExpr, .int(rhs))) }
    public static prefix func -(_ x: Var) -> Expr<Int> { Expr(.negate(x.stateExpr)) }
    public static func <(_ lhs: Var, _ rhs: Int) -> StateExpr { .lessThan(lhs.stateExpr, .int(rhs)) }
    public static func <(_ lhs: Var, _ rhs: Var) -> StateExpr { .lessThan(lhs.stateExpr, rhs.stateExpr) }
    public static func >(_ lhs: Var, _ rhs: Int) -> StateExpr { .greaterThan(lhs.stateExpr, .int(rhs)) }
    public static func >(_ lhs: Var, _ rhs: Var) -> StateExpr { .greaterThan(lhs.stateExpr, rhs.stateExpr) }
    public static func <=(_ lhs: Var, _ rhs: Int) -> StateExpr { .lessOrEqual(lhs.stateExpr, .int(rhs)) }
    public static func <=(_ lhs: Var, _ rhs: Var) -> StateExpr { .lessOrEqual(lhs.stateExpr, rhs.stateExpr) }
    public static func >=(_ lhs: Var, _ rhs: Int) -> StateExpr { .greaterOrEqual(lhs.stateExpr, .int(rhs)) }
    public static func >=(_ lhs: Var, _ rhs: Var) -> StateExpr { .greaterOrEqual(lhs.stateExpr, rhs.stateExpr) }
    public static func ==(_ lhs: Var, _ rhs: Int) -> StateExpr { .equal(lhs.stateExpr, .int(rhs)) }
    public static func ==(_ lhs: Var, _ rhs: Var) -> StateExpr { .equal(lhs.stateExpr, rhs.stateExpr) }
    public static func !=(_ lhs: Var, _ rhs: Int) -> StateExpr { .notEqual(lhs.stateExpr, .int(rhs)) }
    public static func !=(_ lhs: Var, _ rhs: Var) -> StateExpr { .notEqual(lhs.stateExpr, rhs.stateExpr) }
}

extension Var where T == Bool {
    public static prefix func !(_ x: Var) -> Expr<Bool> { Expr(.not(x.stateExpr)) }
    public static func &&(_ lhs: Var, _ rhs: Var) -> Expr<Bool> { Expr(.and(lhs.stateExpr, rhs.stateExpr)) }
    public static func &&(_ lhs: Var, _ rhs: Expr<Bool>) -> Expr<Bool> { Expr(.and(lhs.stateExpr, rhs.raw)) }
    public static func ||(_ lhs: Var, _ rhs: Var) -> Expr<Bool> { Expr(.or(lhs.stateExpr, rhs.stateExpr)) }
    public static func ||(_ lhs: Var, _ rhs: Expr<Bool>) -> Expr<Bool> { Expr(.or(lhs.stateExpr, rhs.raw)) }
    public static func ==(_ lhs: Var, _ rhs: Bool) -> StateExpr { .equal(lhs.stateExpr, .bool(rhs)) }
    public static func ==(_ lhs: Var, _ rhs: Var) -> StateExpr { .equal(lhs.stateExpr, rhs.stateExpr) }
    public static func !=(_ lhs: Var, _ rhs: Bool) -> StateExpr { .notEqual(lhs.stateExpr, .bool(rhs)) }
}

extension Var where T == String {
    public static func +(_ lhs: Var, _ rhs: String) -> Expr<String> { Expr(.add(lhs.stateExpr, .value(.string(rhs)))) }
    public static func +(_ lhs: Var, _ rhs: Var) -> Expr<String> { Expr(.add(lhs.stateExpr, rhs.stateExpr)) }
    public static func ==(_ lhs: Var, _ rhs: String) -> StateExpr { .equal(lhs.stateExpr, .value(.string(rhs))) }
    public static func !=(_ lhs: Var, _ rhs: String) -> StateExpr { .notEqual(lhs.stateExpr, .value(.string(rhs))) }
}

// MARK: - Free-floating

extension Expr where T == Bool {
    public static prefix func !(_ value: Expr<Bool>) -> Expr<Bool> {
        Expr(.not(value.raw))
    }

    public static func ifThenElse(_ cond: some StateExprConvertible, _ then: Bool, _ else: Var<Bool>) -> Expr {
        Expr(.ifThenElse(cond.stateExpr, .value(.bool(then)), `else`.stateExpr))
    }
    public static func ifThenElse(_ cond: some StateExprConvertible, _ then: StateExpr, _ else: StateExpr) -> Expr {
        Expr(.ifThenElse(cond.stateExpr, then, `else`))
    }
}

extension Expr {
    /// Builds a typed formal conditional without leaving the typed DSL.
    public static func ifThenElse(
        _ condition: some StateExprConvertible,
        then: T,
        else otherwise: T
    ) -> Expr<T> {
        Expr<T>(.ifThenElse(
            condition.stateExpr,
            .value(then.tlaValue),
            .value(otherwise.tlaValue)
        ))
    }

    /// Builds a typed conditional when one branch is already a formal expression.
    public static func ifThenElse(
        _ condition: some StateExprConvertible,
        then: T,
        else otherwise: Expr<T>
    ) -> Expr<T> {
        Expr<T>(.ifThenElse(
            condition.stateExpr,
            .value(then.tlaValue),
            otherwise.raw
        ))
    }

    /// Builds a typed conditional when one branch is already a formal expression.
    public static func ifThenElse(
        _ condition: some StateExprConvertible,
        then: Expr<T>,
        else otherwise: T
    ) -> Expr<T> {
        Expr<T>(.ifThenElse(
            condition.stateExpr,
            then.raw,
            .value(otherwise.tlaValue)
        ))
    }
}

extension Expr where T == String {
    public static func ifThenElse(_ cond: some StateExprConvertible, _ then: String, _ else: Var<String>) -> Expr {
        Expr(.ifThenElse(cond.stateExpr, .value(.string(then)), `else`.stateExpr))
    }
}

public func +(_ lhs: Expr<Int>, _ rhs: Int) -> Expr<Int> { Expr(.add(lhs.raw, .int(rhs))) }
public func -(_ lhs: Expr<Int>, _ rhs: Int) -> Expr<Int> { Expr(.subtract(lhs.raw, .int(rhs))) }
public func -(_ lhs: Int, _ rhs: Var<Int>) -> Expr<Int> { Expr(.subtract(.int(lhs), rhs.stateExpr)) }
public func -(_ lhs: Int, _ rhs: Expr<Int>) -> Expr<Int> { Expr(.subtract(.int(lhs), rhs.raw)) }
public func +(_ lhs: Expr<Int>, _ rhs: Var<Int>) -> Expr<Int> { Expr(.add(lhs.raw, rhs.stateExpr)) }
public func %(_ lhs: Expr<Int>, _ rhs: Int) -> Expr<Int> { Expr(.modulo(lhs.raw, .int(rhs))) }
