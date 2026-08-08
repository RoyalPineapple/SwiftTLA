// Generated typed operators for Var<T>.  One file per type for clarity.
// Int operators: arithmetic → Expr<Int>, comparisons → StateExpr

extension Var where T == Int {
    // -- Arithmetic → Expr<Int> --
    public static func +(_ lhs: Var, _ rhs: Int) -> Expr<Int> { Expr(.add(lhs, .int(rhs))) }
    public static func +(_ lhs: Var, _ rhs: Var) -> Expr<Int> { Expr(.add(lhs, rhs)) }
    public static func +(_ lhs: Var, _ rhs: Expr<Int>) -> Expr<Int> { Expr(.add(lhs, rhs.raw)) }
    public static func -(_ lhs: Var, _ rhs: Int) -> Expr<Int> { Expr(.subtract(lhs, .int(rhs))) }
    public static func -(_ lhs: Var, _ rhs: Var) -> Expr<Int> { Expr(.subtract(lhs, rhs)) }
    public static func -(_ lhs: Var, _ rhs: Expr<Int>) -> Expr<Int> { Expr(.subtract(lhs, rhs.raw)) }
    public static func *(_ lhs: Var, _ rhs: Int) -> Expr<Int> { Expr(.multiply(lhs, .int(rhs))) }
    public static func *(_ lhs: Var, _ rhs: Var) -> Expr<Int> { Expr(.multiply(lhs, rhs)) }
    public static func *(_ lhs: Var, _ rhs: Expr<Int>) -> Expr<Int> { Expr(.multiply(lhs, rhs.raw)) }
    public static func /(_ lhs: Var, _ rhs: Int) -> Expr<Int> { Expr(.divide(lhs, .int(rhs))) }
    public static func /(_ lhs: Var, _ rhs: Var) -> Expr<Int> { Expr(.divide(lhs, rhs)) }
    public static func %(_ lhs: Var, _ rhs: Int) -> Expr<Int> { Expr(.modulo(lhs, .int(rhs))) }
    public static prefix func -(_ x: Var) -> Expr<Int> { Expr(.negate(x)) }

    // -- Comparisons → StateExpr --
    public static func <(_ lhs: Var, _ rhs: Int) -> StateExpr { .lessThan(lhs, .int(rhs)) }
    public static func <(_ lhs: Var, _ rhs: Var) -> StateExpr { .lessThan(lhs, rhs) }
    public static func >(_ lhs: Var, _ rhs: Int) -> StateExpr { .greaterThan(lhs, .int(rhs)) }
    public static func >(_ lhs: Var, _ rhs: Var) -> StateExpr { .greaterThan(lhs, rhs) }
    public static func <=(_ lhs: Var, _ rhs: Int) -> StateExpr { .lessOrEqual(lhs, .int(rhs)) }
    public static func <=(_ lhs: Var, _ rhs: Var) -> StateExpr { .lessOrEqual(lhs, rhs) }
    public static func >=(_ lhs: Var, _ rhs: Int) -> StateExpr { .greaterOrEqual(lhs, .int(rhs)) }
    public static func >=(_ lhs: Var, _ rhs: Var) -> StateExpr { .greaterOrEqual(lhs, rhs) }
    public static func ==(_ lhs: Var, _ rhs: Int) -> StateExpr { .equal(lhs, .int(rhs)) }
    public static func ==(_ lhs: Var, _ rhs: Var) -> StateExpr { .equal(lhs, rhs) }
    public static func !=(_ lhs: Var, _ rhs: Int) -> StateExpr { .notEqual(lhs, .int(rhs)) }
    public static func !=(_ lhs: Var, _ rhs: Var) -> StateExpr { .notEqual(lhs, rhs) }
}

extension Expr where T == Int {
    public static func +(_ lhs: Expr, _ rhs: Int) -> Expr { Expr(.add(lhs.raw, .int(rhs))) }
    public static func +(_ lhs: Expr, _ rhs: Var<Int>) -> Expr { Expr(.add(lhs.raw, rhs)) }
    public static func +(_ lhs: Expr, _ rhs: Expr) -> Expr { Expr(.add(lhs.raw, rhs.raw)) }
    public static func -(_ lhs: Expr, _ rhs: Int) -> Expr { Expr(.subtract(lhs.raw, .int(rhs))) }
    public static func -(_ lhs: Expr, _ rhs: Var<Int>) -> Expr { Expr(.subtract(lhs.raw, rhs)) }
    public static func *(_ lhs: Expr, _ rhs: Int) -> Expr { Expr(.multiply(lhs.raw, .int(rhs))) }
    public static func *(_ lhs: Expr, _ rhs: Var<Int>) -> Expr { Expr(.multiply(lhs.raw, rhs)) }
    public static func /(_ lhs: Expr, _ rhs: Int) -> Expr { Expr(.divide(lhs.raw, .int(rhs))) }
    public static func %(_ lhs: Expr, _ rhs: Int) -> Expr { Expr(.modulo(lhs.raw, .int(rhs))) }

    // Comparisons
    public static func <(_ lhs: Expr, _ rhs: Int) -> StateExpr { .lessThan(lhs.raw, .int(rhs)) }
    public static func >(_ lhs: Expr, _ rhs: Int) -> StateExpr { .greaterThan(lhs.raw, .int(rhs)) }
    public static func <=(_ lhs: Expr, _ rhs: Int) -> StateExpr { .lessOrEqual(lhs.raw, .int(rhs)) }
    public static func >=(_ lhs: Expr, _ rhs: Int) -> StateExpr { .greaterOrEqual(lhs.raw, .int(rhs)) }
    public static func ==(_ lhs: Expr, _ rhs: Int) -> StateExpr { .equal(lhs.raw, .int(rhs)) }
    public static func !=(_ lhs: Expr, _ rhs: Int) -> StateExpr { .notEqual(lhs.raw, .int(rhs)) }
}
