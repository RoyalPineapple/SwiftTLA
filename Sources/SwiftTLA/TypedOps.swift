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
}

public func +(_ lhs: Expr<Int>, _ rhs: Int) -> Expr<Int> { Expr(.add(lhs.raw, .int(rhs))) }
public func +(_ lhs: Expr<Int>, _ rhs: Expr<Int>) -> Expr<Int> { Expr(.add(lhs.raw, rhs.raw)) }
public func -(_ lhs: Expr<Int>, _ rhs: Int) -> Expr<Int> { Expr(.subtract(lhs.raw, .int(rhs))) }
public func -(_ lhs: Expr<Int>, _ rhs: Expr<Int>) -> Expr<Int> { Expr(.subtract(lhs.raw, rhs.raw)) }
public func *(_ lhs: Expr<Int>, _ rhs: Expr<Int>) -> Expr<Int> { Expr(.multiply(lhs.raw, rhs.raw)) }
public func *(_ lhs: Expr<Int>, _ rhs: Int) -> Expr<Int> { Expr(.multiply(lhs.raw, .int(rhs))) }
public func -(_ lhs: Int, _ rhs: Var<Int>) -> Expr<Int> { Expr(.subtract(.int(lhs), rhs.stateExpr)) }
public func -(_ lhs: Int, _ rhs: Expr<Int>) -> Expr<Int> { Expr(.subtract(.int(lhs), rhs.raw)) }
public func +(_ lhs: Expr<Int>, _ rhs: Var<Int>) -> Expr<Int> { Expr(.add(lhs.raw, rhs.stateExpr)) }
public func %(_ lhs: Expr<Int>, _ rhs: Int) -> Expr<Int> { Expr(.modulo(lhs.raw, .int(rhs))) }
public func <(_ lhs: Expr<Int>, _ rhs: Expr<Int>) -> StateExpr { .lessThan(lhs.raw, rhs.raw) }
public func >(_ lhs: Expr<Int>, _ rhs: Expr<Int>) -> StateExpr { .greaterThan(lhs.raw, rhs.raw) }
public func <=(_ lhs: Expr<Int>, _ rhs: Expr<Int>) -> StateExpr { .lessOrEqual(lhs.raw, rhs.raw) }
public func >=(_ lhs: Expr<Int>, _ rhs: Expr<Int>) -> StateExpr { .greaterOrEqual(lhs.raw, rhs.raw) }
public func <(_ lhs: Expr<Int>, _ rhs: LocalVariable<Int>) -> StateExpr { .lessThan(lhs.raw, rhs.stateExpr) }
public func >(_ lhs: Expr<Int>, _ rhs: LocalVariable<Int>) -> StateExpr { .greaterThan(lhs.raw, rhs.stateExpr) }
public func <=(_ lhs: Expr<Int>, _ rhs: LocalVariable<Int>) -> StateExpr { .lessOrEqual(lhs.raw, rhs.stateExpr) }
public func >=(_ lhs: Expr<Int>, _ rhs: LocalVariable<Int>) -> StateExpr { .greaterOrEqual(lhs.raw, rhs.stateExpr) }
public func == <T: TLAValueType>(_ lhs: Expr<T>, _ rhs: Expr<T>) -> StateExpr { .equal(lhs.raw, rhs.raw) }
public func != <T: TLAValueType>(_ lhs: Expr<T>, _ rhs: Expr<T>) -> StateExpr { .notEqual(lhs.raw, rhs.raw) }
public func == <T: TLAValueType>(_ lhs: Expr<T>, _ rhs: LocalVariable<T>) -> StateExpr { .equal(lhs.raw, rhs.stateExpr) }
public func != <T: TLAValueType>(_ lhs: Expr<T>, _ rhs: LocalVariable<T>) -> StateExpr { .notEqual(lhs.raw, rhs.stateExpr) }
