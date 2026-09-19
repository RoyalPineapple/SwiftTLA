// Integer arithmetic preserves its value type across every expression source.
public func +(_ lhs: some TypedExpression<Int>, _ rhs: some TypedExpression<Int>) -> Expr<Int> {
    Expr(.add(lhs.stateExpr, rhs.stateExpr))
}

public func -(_ lhs: some TypedExpression<Int>, _ rhs: some TypedExpression<Int>) -> Expr<Int> {
    Expr(.subtract(lhs.stateExpr, rhs.stateExpr))
}

public func *(_ lhs: some TypedExpression<Int>, _ rhs: some TypedExpression<Int>) -> Expr<Int> {
    Expr(.multiply(lhs.stateExpr, rhs.stateExpr))
}

public func /(_ lhs: some TypedExpression<Int>, _ rhs: some TypedExpression<Int>) -> Expr<Int> {
    Expr(.divide(lhs.stateExpr, rhs.stateExpr))
}

public func %(_ lhs: some TypedExpression<Int>, _ rhs: some TypedExpression<Int>) -> Expr<Int> {
    Expr(.modulo(lhs.stateExpr, rhs.stateExpr))
}

public prefix func -(_ value: some TypedExpression<Int>) -> Expr<Int> {
    Expr(.negate(value.stateExpr))
}

public func <(_ lhs: some TypedExpression<Int>, _ rhs: some TypedExpression<Int>) -> Expr<Bool> {
    Expr(.lessThan(lhs.stateExpr, rhs.stateExpr))
}

public func <=(_ lhs: some TypedExpression<Int>, _ rhs: some TypedExpression<Int>) -> Expr<Bool> {
    Expr(.lessOrEqual(lhs.stateExpr, rhs.stateExpr))
}

public func >(_ lhs: some TypedExpression<Int>, _ rhs: some TypedExpression<Int>) -> Expr<Bool> {
    Expr(.greaterThan(lhs.stateExpr, rhs.stateExpr))
}

public func >=(_ lhs: some TypedExpression<Int>, _ rhs: some TypedExpression<Int>) -> Expr<Bool> {
    Expr(.greaterOrEqual(lhs.stateExpr, rhs.stateExpr))
}

public func ==<Left: TypedExpression, Right: TypedExpression>(
    _ lhs: Left, _ rhs: Right
) -> Expr<Bool> where Left.ExpressionValue == Right.ExpressionValue {
    Expr(.equal(lhs.stateExpr, rhs.stateExpr))
}

public func ==<Expression: TypedExpression>(_ lhs: Expression, _ rhs: Expression.ExpressionValue) -> Expr<Bool> {
    Expr(.equal(lhs.stateExpr, rhs.stateExpr))
}

public func ==<Expression: TypedExpression>(_ lhs: Expression.ExpressionValue, _ rhs: Expression) -> Expr<Bool> {
    Expr(.equal(lhs.stateExpr, rhs.stateExpr))
}

public func !=<Left: TypedExpression, Right: TypedExpression>(
    _ lhs: Left, _ rhs: Right
) -> Expr<Bool> where Left.ExpressionValue == Right.ExpressionValue {
    Expr(.notEqual(lhs.stateExpr, rhs.stateExpr))
}

public func !=<Expression: TypedExpression>(_ lhs: Expression, _ rhs: Expression.ExpressionValue) -> Expr<Bool> {
    Expr(.notEqual(lhs.stateExpr, rhs.stateExpr))
}

public func !=<Expression: TypedExpression>(_ lhs: Expression.ExpressionValue, _ rhs: Expression) -> Expr<Bool> {
    Expr(.notEqual(lhs.stateExpr, rhs.stateExpr))
}

public func &&(_ lhs: some TypedExpression<Bool>, _ rhs: some TypedExpression<Bool>) -> Expr<Bool> {
    Expr(.and(lhs.stateExpr, rhs.stateExpr))
}

public func ||(_ lhs: some TypedExpression<Bool>, _ rhs: some TypedExpression<Bool>) -> Expr<Bool> {
    Expr(.or(lhs.stateExpr, rhs.stateExpr))
}

public prefix func !(_ value: some TypedExpression<Bool>) -> Expr<Bool> {
    Expr(.not(value.stateExpr))
}

// Integer-backed finite identities retain their domain when compared.
public func <<Value: FiniteTLAValueDomain & RawRepresentable>(
    _ lhs: some TypedExpression<Value>, _ rhs: some TypedExpression<Value>
) -> Expr<Bool> where Value.RawValue == Int {
    Expr(.lessThan(lhs.stateExpr, rhs.stateExpr))
}

public func <=<Value: FiniteTLAValueDomain & RawRepresentable>(
    _ lhs: some TypedExpression<Value>, _ rhs: some TypedExpression<Value>
) -> Expr<Bool> where Value.RawValue == Int {
    Expr(.lessOrEqual(lhs.stateExpr, rhs.stateExpr))
}

public func ><Value: FiniteTLAValueDomain & RawRepresentable>(
    _ lhs: some TypedExpression<Value>, _ rhs: some TypedExpression<Value>
) -> Expr<Bool> where Value.RawValue == Int {
    Expr(.greaterThan(lhs.stateExpr, rhs.stateExpr))
}

public func >=<Value: FiniteTLAValueDomain & RawRepresentable>(
    _ lhs: some TypedExpression<Value>, _ rhs: some TypedExpression<Value>
) -> Expr<Bool> where Value.RawValue == Int {
    Expr(.greaterOrEqual(lhs.stateExpr, rhs.stateExpr))
}
