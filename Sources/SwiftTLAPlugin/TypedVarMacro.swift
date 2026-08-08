import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser

public enum TypedVarMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        return [
            DeclSyntax(stringLiteral: intVarOps),
            DeclSyntax(stringLiteral: intExprOps),
            DeclSyntax(stringLiteral: boolVarOps),
            DeclSyntax(stringLiteral: boolExprOps),
            DeclSyntax(stringLiteral: stringVarOps),
            DeclSyntax(stringLiteral: stringExprOps),
            DeclSyntax(stringLiteral: functionVarOps),
            DeclSyntax(stringLiteral: functionExprOps),
        ]
    }
}

private let intVarOps = """
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
"""

private let intExprOps = """
extension Expr where T == Int {
    public static func +(_ lhs: Expr, _ rhs: Int) -> Expr { Expr(.add(lhs.raw, .int(rhs))) }
    public static func +(_ lhs: Expr, _ rhs: Var<Int>) -> Expr { Expr(.add(lhs.raw, rhs.stateExpr)) }
    public static func +(_ lhs: Expr, _ rhs: Expr) -> Expr { Expr(.add(lhs.raw, rhs.raw)) }
    public static func -(_ lhs: Expr, _ rhs: Int) -> Expr { Expr(.subtract(lhs.raw, .int(rhs))) }
    public static func -(_ lhs: Expr, _ rhs: Var<Int>) -> Expr { Expr(.subtract(lhs.raw, rhs.stateExpr)) }
    public static func *(_ lhs: Expr, _ rhs: Int) -> Expr { Expr(.multiply(lhs.raw, .int(rhs))) }
    public static func *(_ lhs: Expr, _ rhs: Var<Int>) -> Expr { Expr(.multiply(lhs.raw, rhs.stateExpr)) }
    public static func /(_ lhs: Expr, _ rhs: Int) -> Expr { Expr(.divide(lhs.raw, .int(rhs))) }
    public static func %(_ lhs: Expr, _ rhs: Int) -> Expr { Expr(.modulo(lhs.raw, .int(rhs))) }

    public static func <(_ lhs: Expr, _ rhs: Int) -> StateExpr { .lessThan(lhs.raw, .int(rhs)) }
    public static func >(_ lhs: Expr, _ rhs: Int) -> StateExpr { .greaterThan(lhs.raw, .int(rhs)) }
    public static func <=(_ lhs: Expr, _ rhs: Int) -> StateExpr { .lessOrEqual(lhs.raw, .int(rhs)) }
    public static func >=(_ lhs: Expr, _ rhs: Int) -> StateExpr { .greaterOrEqual(lhs.raw, .int(rhs)) }
    public static func ==(_ lhs: Expr, _ rhs: Int) -> StateExpr { .equal(lhs.raw, .int(rhs)) }
    public static func !=(_ lhs: Expr, _ rhs: Int) -> StateExpr { .notEqual(lhs.raw, .int(rhs)) }
}
"""

private let boolVarOps = """
extension Var where T == Bool {
    public static func && (_ lhs: Var, _ rhs: Var) -> StateExpr { .and(lhs.stateExpr, rhs.stateExpr) }
    public static func || (_ lhs: Var, _ rhs: Var) -> StateExpr { .or(lhs.stateExpr, rhs.stateExpr) }
    public static prefix func !(_ x: Var) -> StateExpr { .not(x.stateExpr) }
    public static func ==(_ lhs: Var, _ rhs: Bool) -> StateExpr { .equal(lhs.stateExpr, .bool(rhs)) }
    public static func ==(_ lhs: Var, _ rhs: Var) -> StateExpr { .equal(lhs.stateExpr, rhs.stateExpr) }
    public static func !=(_ lhs: Var, _ rhs: Bool) -> StateExpr { .notEqual(lhs.stateExpr, .bool(rhs)) }
    public static func !=(_ lhs: Var, _ rhs: Var) -> StateExpr { .notEqual(lhs.stateExpr, rhs.stateExpr) }
}
"""

private let boolExprOps = """
extension Expr where T == Bool {
    public static func && (_ lhs: Expr, _ rhs: Var<Bool>) -> StateExpr { .and(lhs.raw, rhs.stateExpr) }
    public static func || (_ lhs: Expr, _ rhs: Var<Bool>) -> StateExpr { .or(lhs.raw, rhs.stateExpr) }
    public static prefix func !(_ x: Expr) -> StateExpr { .not(x.raw) }
    public static func ==(_ lhs: Expr, _ rhs: Bool) -> StateExpr { .equal(lhs.raw, .bool(rhs)) }
    public static func !=(_ lhs: Expr, _ rhs: Bool) -> StateExpr { .notEqual(lhs.raw, .bool(rhs)) }
}
"""

private let stringVarOps = """
extension Var where T == String {
    public static func +(_ lhs: Var, _ rhs: String) -> Expr<String> { Expr(.add(lhs.stateExpr, .value(.string(rhs)))) }
    public static func +(_ lhs: Var, _ rhs: Var) -> Expr<String> { Expr(.add(lhs.stateExpr, rhs.stateExpr)) }
    public static func ==(_ lhs: Var, _ rhs: String) -> StateExpr { .equal(lhs.stateExpr, .value(.string(rhs))) }
    public static func ==(_ lhs: Var, _ rhs: Var) -> StateExpr { .equal(lhs.stateExpr, rhs.stateExpr) }
    public static func !=(_ lhs: Var, _ rhs: String) -> StateExpr { .notEqual(lhs.stateExpr, .value(.string(rhs))) }
    public static func !=(_ lhs: Var, _ rhs: Var) -> StateExpr { .notEqual(lhs.stateExpr, rhs.stateExpr) }
}
"""

private let stringExprOps = """
extension Expr where T == String {
    public static func +(_ lhs: Expr, _ rhs: String) -> Expr { Expr(.add(lhs.raw, .value(.string(rhs)))) }
    public static func +(_ lhs: Expr, _ rhs: Var<String>) -> Expr { Expr(.add(lhs.raw, rhs.stateExpr)) }
    public static func ==(_ lhs: Expr, _ rhs: String) -> StateExpr { .equal(lhs.raw, .value(.string(rhs))) }
    public static func !=(_ lhs: Expr, _ rhs: String) -> StateExpr { .notEqual(lhs.raw, .value(.string(rhs))) }
}
"""

private let functionVarOps = """
extension Var where T == TLAFunctionType {
    public func updated(at key: some StateExprConvertible, to value: some StateExprConvertible) -> Expr<TLAFunctionType> {
        Expr(.except(stateExpr, key.stateExpr, value.stateExpr))
    }
    public func applying(_ argument: some StateExprConvertible) -> StateExpr {
        .functionApply(stateExpr, argument.stateExpr)
    }
}
"""

private let functionExprOps = """
extension Expr where T == TLAFunctionType {
    public func updated(at key: some StateExprConvertible, to value: some StateExprConvertible) -> Expr {
        Expr(.except(raw, key.stateExpr, value.stateExpr))
    }
    public func applying(_ argument: some StateExprConvertible) -> StateExpr {
        .functionApply(raw, argument.stateExpr)
    }
}
"""
