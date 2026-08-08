import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct TypedVarMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self),
              let genericClause = structDecl.genericParameterClause,
              let typeParam = genericClause.parameters.first?.name.text else {
            return []
        }
        // TLAValueType conformers: Int, Bool, String, TLAFunctionType
        switch typeParam {
        case "T": return generateOperators(for: "Int") + generateOperators(for: "Bool") + generateOperators(for: "String") + generateFunctionOps()
        default: return []
        }
    }
}

private func generateOperators(for swiftType: String) -> [DeclSyntax] {
    let base: [DeclSyntax]
    switch swiftType {
    case "Int":
        base = intOps() + intComparisons()
    case "Bool":
        base = boolOps() + boolComparisons()
    case "String":
        base = []
    default:
        base = []
    }
    return wrapInExtension(base, type: swiftType)
}

private func wrapInExtension(_ decls: [DeclSyntax], type: String) -> [DeclSyntax] {
    guard !decls.isEmpty else { return [] }
    let ext = DeclSyntax(stringLiteral: """
    extension Var where T == \(type) {
        \(decls.map { $0.description }.joined(separator: "\n    "))
    }
    """)
    return [ext]
}

private func intOps() -> [DeclSyntax] {
    let ops: [(String, String)] = [
        ("+", ".add"), ("-", ".subtract"), ("*", ".multiply"), ("/", ".divide"), ("%", ".modulo"),
    ]
    var decls: [DeclSyntax] = []
    for (op, state) in ops {
        decls.append(DeclSyntax(stringLiteral: "public static func \(op)(_ lhs: Var, _ rhs: Int) -> Expr<Int> { Expr(\(state)(lhs, .int(rhs))) }"))
        decls.append(DeclSyntax(stringLiteral: "public static func \(op)(_ lhs: Var, _ rhs: Var) -> Expr<Int> { Expr(\(state)(lhs, rhs)) }"))
        decls.append(DeclSyntax(stringLiteral: "public static func \(op)(_ lhs: Var, _ rhs: Expr<Int>) -> Expr<Int> { Expr(\(state)(lhs, rhs.raw)) }"))
    }
    decls.append(DeclSyntax(stringLiteral: "public static prefix func -(_ x: Var) -> Expr<Int> { Expr(.negate(x)) }"))
    return decls
}

private func intComparisons() -> [DeclSyntax] {
    let cmps: [(String, String)] = [
        ("<", ".lessThan"), (">", ".greaterThan"),
        ("<=", ".lessOrEqual"), (">=", ".greaterOrEqual"),
        ("==", ".equal"), ("!=", ".notEqual"),
    ]
    return cmps.flatMap { (op, state) in [
        DeclSyntax(stringLiteral: "public static func \(op)(_ lhs: Var, _ rhs: Int) -> StateExpr { \(state)(lhs, .int(rhs)) }"),
        DeclSyntax(stringLiteral: "public static func \(op)(_ lhs: Var, _ rhs: Var) -> StateExpr { \(state)(lhs, rhs) }"),
    ]}
}

private func boolOps() -> [DeclSyntax] {
    [
        DeclSyntax(stringLiteral: "public static prefix func !(_ x: Var) -> Expr<Bool> { Expr(.not(x)) }"),
        DeclSyntax(stringLiteral: "public static func &&(_ lhs: Var, _ rhs: Var) -> Expr<Bool> { Expr(.and(lhs, rhs)) }"),
        DeclSyntax(stringLiteral: "public static func &&(_ lhs: Var, _ rhs: Expr<Bool>) -> Expr<Bool> { Expr(.and(lhs, rhs.raw)) }"),
        DeclSyntax(stringLiteral: "public static func ||(_ lhs: Var, _ rhs: Var) -> Expr<Bool> { Expr(.or(lhs, rhs)) }"),
        DeclSyntax(stringLiteral: "public static func ||(_ lhs: Var, _ rhs: Expr<Bool>) -> Expr<Bool> { Expr(.or(lhs, rhs.raw)) }"),
    ]
}

private func boolComparisons() -> [DeclSyntax] {
    [
        DeclSyntax(stringLiteral: "public static func ==(_ lhs: Var, _ rhs: Bool) -> StateExpr { .equal(lhs, .bool(rhs)) }"),
        DeclSyntax(stringLiteral: "public static func ==(_ lhs: Var, _ rhs: Var) -> StateExpr { .equal(lhs, rhs) }"),
        DeclSyntax(stringLiteral: "public static func !=(_ lhs: Var, _ rhs: Bool) -> StateExpr { .notEqual(lhs, .bool(rhs)) }"),
    ]
}

private func generateFunctionOps() -> [DeclSyntax] {
    let decls: [DeclSyntax] = [
        DeclSyntax(stringLiteral: "public func updated(at key: some StateExprConvertible, to value: some StateExprConvertible) -> Expr<TLAFunctionType> { Expr(.except(self, key.stateExpr, value.stateExpr)) }"),
        DeclSyntax(stringLiteral: "public func applying(_ key: some StateExprConvertible) -> StateExpr { .functionApply(self, key.stateExpr) }"),
        DeclSyntax(stringLiteral: "public func union(_ other: some StateExprConvertible) -> Expr<TLAFunctionType> { Expr(.union(self, other.stateExpr)) }"),
    ]
    return wrapInExtension(decls, type: "TLAFunctionType")
}
