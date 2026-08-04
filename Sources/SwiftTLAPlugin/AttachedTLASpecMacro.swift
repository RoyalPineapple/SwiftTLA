import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA
import SwiftTLAGenerator

public struct AttachedTLASpecMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw SimpleError("@TLA on structs only")
        }

        let typeName = structDecl.name.text
        var variables: [(name: String, initial: TLAValue)] = []
        var actions: [(name: String, body: ActionExpr)] = []

        for member in structDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                    let val = extractVarInit(binding.initializer?.value)
                    variables.append((name, val))
                }
            } else if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let actName = funcDecl.name.text
                if let body = funcDecl.body {
                    let clauses = parseBody(body.statements)
                    if !clauses.isEmpty {
                        let combined = clauses.dropFirst().reduce(clauses[0]) { .and($0, $1) }
                        actions.append((actName, combined))
                    }
                }
            }
        }

        guard !variables.isEmpty, !actions.isEmpty else {
            return [DeclSyntax(stringLiteral: "/* @TLA needs Var<Int> properties and methods */")]
        }

        let spec = TLASpec(name: typeName, variables: variables.map { NamedVar(name: $0.name, initial: $0.initial) }, actions: actions.map { NamedAction(name: $0.name, body: $0.body) }, invariants: [])

        let checker = ModelChecker(spec: spec, maxStates: 10_000)
        if case .invariantViolated(let inv, _, let trace) = (try? checker.check()) {
            let traceStr = trace.map { "  \($0)" }.joined(separator: "\n")
            return [DeclSyntax(stringLiteral: "/* Invariant '\(inv)' violated:\n\(traceStr)\n*/")]
        }
        guard let graph = try? checker.exploreGraph() else { return [] }

        let code = (try? StateMachineGenerator(graph: graph).generate()) ?? ""
        let source = Parser.parse(source: code)
        if let structDecl = source.statements.first?.item.as(StructDeclSyntax.self) {
            return structDecl.memberBlock.members.compactMap { member in
                if let decl = member.decl.as(EnumDeclSyntax.self), decl.name.text == "Action" {
                    return DeclSyntax(decl)
                }
                if let decl = member.decl.as(VariableDeclSyntax.self), decl.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "transitions" {
                    return DeclSyntax(decl)
                }
                if let decl = member.decl.as(FunctionDeclSyntax.self), decl.name.text == "apply" {
                    return DeclSyntax(decl)
                }
                if let decl = member.decl.as(VariableDeclSyntax.self), let name = decl.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text, name == "availableActions" || name == "initial" {
                    return DeclSyntax(decl)
                }
                return nil
            }
        }
        return []
    }

    private static func parseBody(_ statements: CodeBlockItemListSyntax) -> [ActionExpr] {
        statements.compactMap { statement -> ActionExpr? in
            guard case .expr(let expr) = statement.item else { return nil }
            return parseBecomesChain(expr)
        }
    }

    private static func parseBecomesChain(_ expr: ExprSyntax) -> ActionExpr? {
        guard let call = expr.as(FunctionCallExprSyntax.self) else { return nil }
        let chain = unwrapWhen(call)
        guard let (varName, value) = parseBecomes(chain.call) else { return nil }
        let assign = ActionExpr.assign(varName, value)
        if let condition = chain.condition { return .and(.guard_(condition), assign) }
        return assign
    }

    private struct Chain { let call: FunctionCallExprSyntax; let condition: StateExpr? }

    private static func unwrapWhen(_ call: FunctionCallExprSyntax) -> Chain {
        if let ma = call.calledExpression.as(MemberAccessExprSyntax.self), ma.declName.baseName.text == "when", let base = ma.base?.as(FunctionCallExprSyntax.self) {
            let cond = parseExpr(call.arguments.first?.expression)
            let inner = unwrapWhen(base)
            let combined: StateExpr? = if let c = cond, let i = inner.condition { .and(c, i) } else { cond ?? inner.condition }
            return Chain(call: inner.call, condition: combined)
        }
        return Chain(call: call, condition: nil)
    }

    private static func parseBecomes(_ call: FunctionCallExprSyntax) -> (String, StateExpr)? {
        guard let ma = call.calledExpression.as(MemberAccessExprSyntax.self), ma.declName.baseName.text == "becomes", let base = ma.base?.as(DeclReferenceExprSyntax.self), let arg = call.arguments.first?.expression else { return nil }
        return (base.baseName.text, parseExpr(arg) ?? .value(.int(0)))
    }

    private static func parseExpr(_ expr: ExprSyntax?) -> StateExpr? {
        guard let expr else { return nil }
        if let intLit = expr.as(IntegerLiteralExprSyntax.self) { return .value(.int(Int(intLit.literal.text) ?? 0)) }
        if let ref = expr.as(DeclReferenceExprSyntax.self) { return .variable(ref.baseName.text) }
        if let infix = expr.as(InfixOperatorExprSyntax.self) {
            guard let l = parseExpr(infix.leftOperand), let r = parseExpr(infix.rightOperand) else { return nil }
            switch infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text {
            case "+": return .add(l, r); case "-": return .subtract(l, r); case "*": return .multiply(l, r); case "/": return .divide(l, r)
            case "<": return .lessThan(l, r); case "<=": return .lessOrEqual(l, r); case ">": return .greaterThan(l, r); case ">=": return .greaterOrEqual(l, r); case "==": return .equal(l, r); case "!=": return .notEqual(l, r)
            default: return nil
            }
        }
        return nil
    }

    private static func extractVarInit(_ expr: ExprSyntax?) -> TLAValue {
        guard let expr else { return .int(0) }
        if let intLit = expr.as(IntegerLiteralExprSyntax.self) { return .int(Int(intLit.literal.text) ?? 0) }
        if let call = expr.as(FunctionCallExprSyntax.self), call.arguments.count >= 2, let second = call.arguments[call.arguments.index(call.arguments.startIndex, offsetBy: 1)].expression.as(IntegerLiteralExprSyntax.self) { return .int(Int(second.literal.text) ?? 0) }
        return .int(0)
    }
}
