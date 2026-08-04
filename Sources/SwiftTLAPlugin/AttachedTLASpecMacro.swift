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
        var variables: [(name: String, initial: StateExpr)] = []
        var actions: [(name: String, body: ActionExpr)] = []

        for member in structDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                    let val = parseExpression(binding.initializer?.value) ?? .value(.int(0))
                    variables.append((name, val))
                }
            } else if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let actName = funcDecl.name.text
                if let body = funcDecl.body {
                    let actionBody = parseActionBody(from: body.statements)
                    actions.append((actName, actionBody))
                }
            }
        }

        let spec = TLASpec(
            name: typeName,
            variables: variables.map { NamedVar(name: $0.name, initial: evaluateSimple($0.initial)) },
            actions: actions.map { NamedAction(name: $0.name, body: $0.body) },
            invariants: []
        )

        let checker = ModelChecker(spec: spec, maxStates: 10_000)
        if case .invariantViolated(let inv, _, let trace) = (try? checker.check()) {
            let traceStr = trace.map { "  \($0)" }.joined(separator: "\n")
            throw SimpleError("Invariant '\(inv)' violated\n\(traceStr)")
        }
        if case .depthExceeded = (try? checker.check()) {
            throw SimpleError("State space exceeded limit")
        }

        guard let graph = try? checker.exploreGraph() else {
            throw SimpleError("Could not explore state graph")
        }

        let code = (try? StateMachineGenerator(graph: graph).generate()) ?? ""
        let renamed = code.replacingOccurrences(of: "struct \(typeName)", with: "struct TLAStateMachine")
        let source = Parser.parse(source: renamed)
        return source.statements.compactMap { $0.item.as(DeclSyntax.self) }
    }

    private static func parseActionBody(from statements: CodeBlockItemListSyntax) -> ActionExpr {
        let clauses = statements.compactMap { $0.item.as(ExprSyntax.self) }.compactMap(parseBecomesChain)
        if clauses.isEmpty { return .guard_(.value(.bool(false))) }
        return clauses.dropFirst().reduce(clauses[0]) { .and($0, $1) }
    }

    private static func parseBecomesChain(_ expr: ExprSyntax) -> ActionExpr? {
        guard let call = expr.as(FunctionCallExprSyntax.self) else { return nil }
        let chain = unwrapWhenChain(call)
        guard let (varName, value) = parseBecomesCall(chain.call) else { return nil }
        let assign = ActionExpr.assign(varName, value)
        if let condition = chain.condition {
            return .and(.guard_(condition), assign)
        }
        return assign
    }

    private struct BecomesChain { let call: FunctionCallExprSyntax; let condition: StateExpr? }

    private static func unwrapWhenChain(_ call: FunctionCallExprSyntax) -> BecomesChain {
        if let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "when",
           let base = memberAccess.base?.as(FunctionCallExprSyntax.self) {
            let condition = parseExpression(call.arguments.first?.expression)
            let inner = unwrapWhenChain(base)
            let combined: StateExpr? = if let c = condition, let i = inner.condition { .and(c, i) }
                else { condition ?? inner.condition }
            return BecomesChain(call: inner.call, condition: combined)
        }
        return BecomesChain(call: call, condition: nil)
    }

    private static func parseBecomesCall(_ call: FunctionCallExprSyntax) -> (String, StateExpr)? {
        guard let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "becomes",
              let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
              let arg = call.arguments.first?.expression else { return nil }
        return (base.baseName.text, parseExpression(arg) ?? .value(.int(0)))
    }

    private static func parseExpression(_ expr: ExprSyntax?) -> StateExpr? {
        guard let expr else { return nil }
        if let intLiteral = expr.as(IntegerLiteralExprSyntax.self) {
            return .value(.int(Int(intLiteral.literal.text) ?? 0))
        }
        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return .variable(declRef.baseName.text)
        }
        if let infixOp = expr.as(InfixOperatorExprSyntax.self) {
            guard let left = parseExpression(infixOp.leftOperand),
                  let right = parseExpression(infixOp.rightOperand) else { return nil }
            switch infixOp.operator.as(BinaryOperatorExprSyntax.self)?.operator.text {
            case "+": return .add(left, right); case "-": return .subtract(left, right)
            case "*": return .multiply(left, right);  case "/": return .divide(left, right)
            case "<": return .lessThan(left, right);  case "<=": return .lessOrEqual(left, right)
            case ">": return .greaterThan(left, right); case ">=": return .greaterOrEqual(left, right)
            case "==": return .equal(left, right);    case "!=": return .notEqual(left, right)
            default: return nil
            }
        }
        return nil
    }

    private static func evaluateSimple(_ expr: StateExpr) -> TLAValue {
        if case .value(let v) = expr { return v }
        return .int(0)
    }
}
