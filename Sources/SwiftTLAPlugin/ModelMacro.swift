import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA
import SwiftTLAGeneration

public struct ModelMacro: MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else { return [] }
        let typeName = structDecl.name.text
        let parsed = parseStruct(structDecl)
        let spec = TLASpec(name: typeName, variables: parsed.variables, actions: parsed.actions, invariants: parsed.invariants, temporalProperties: parsed.temporal, fairness: parsed.fairness)

        let checker = ModelChecker(spec: spec, maxStates: 1_000)
        if case .invariantViolated(let inv, _, let trace) = (try? checker.check()) {
            throw SimpleError("""
                Invariant '\(inv)' violated:
                \(trace.map { "\($0)" }.joined(separator: "\n"))
                """)
        }

        var members: [DeclSyntax] = []
        let b64 = spec.base64JSON
        members.append(DeclSyntax(stringLiteral: "public static var spec: TLASpec { TLASpec.decode(base64: \"\(b64)\") }"))

        if let graph = try? checker.exploreGraph(),
           let code = try? StateMachineGenerator(graph: graph).generate() {
            let renamed = code
                .replacingOccurrences(of: "struct \(typeName)", with: "struct Machine")
                .replacingOccurrences(of: "static let initial = \(typeName)(", with: "static let initial = Machine(")
            let decls = Parser.parse(source: renamed).statements.compactMap { $0.item.as(DeclSyntax.self) }
            members.append(contentsOf: decls)
        }
        return members
    }

    // MARK: - Struct parsing

    private struct ParseResult {
        var variables: [NamedVar] = []
        var actions: [NamedAction] = []
        var invariants: [NamedInvariant] = []
        var temporal: [NamedTemporal] = []
        var fairness: [FairnessCondition] = []
    }

    private static func parseStruct(_ structDecl: StructDeclSyntax) -> ParseResult {
        var result = ParseResult()
        for member in structDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                    if let returnType = binding.typeAnnotation?.type.description.trimmingCharacters(in: .whitespaces) {
                        let getterBody = extractGetter(binding)
                        if returnType == "StateExpr", let body = getterBody {
                            if let expr = parseExprInGetter(body) { result.invariants.append(NamedInvariant(name: name, body: expr)) }
                        } else if returnType.hasPrefix("TemporalExpr"), let body = getterBody {
                            if let t = parseTemporal(body) { result.temporal.append(NamedTemporal(name: name, expr: t)) }
                        } else if returnType == "FairnessCondition", let body = getterBody {
                            if let f = parseFairness(body) { result.fairness.append(f) }
                        }
                    } else {
                        let val = extractVarInit(binding.initializer?.value)
                        result.variables.append(NamedVar(name: name, initial: val))
                    }
                }
            } else if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let name = funcDecl.name.text
                let body = funcDecl.body.map { parseActionBody($0.statements) } ?? .guard_(.value(.bool(true)))
                result.actions.append(NamedAction(name: name, body: body))
            }
        }
        return result
    }

    // MARK: - Action parsing

    // -> ActionExpr body: full expression language (||, &&, becomes, stays)
    private static func parseActionBody(_ s: CodeBlockItemListSyntax) -> ActionExpr {
        let actions: [ActionExpr] = s.compactMap { stmt -> ActionExpr? in
            let expr: ExprSyntax? =
                if case .expr(let e) = stmt.item { e }
                else if case .stmt(let st) = stmt.item, let ret = st.as(ReturnStmtSyntax.self) { ret.expression }
                else { nil }
            return expr.flatMap { parseAction($0) }
        }
        if actions.isEmpty { return .guard_(.value(.bool(true))) }
        return actions.dropFirst().reduce(actions[0]) { .and($0, $1) }
    }

    private static func parseAction(_ e: ExprSyntax) -> ActionExpr? {
        if let io = e.as(InfixOperatorExprSyntax.self) {
            let op = io.operator.as(BinaryOperatorExprSyntax.self)?.operator.text
            if op == "||", let l = parseAction(io.leftOperand), let r = parseAction(io.rightOperand) {
                return .or(l, r)
            }
            if op == "&&" {
                let lhsExpr = parseStateExpr(io.leftOperand)
                let rhsExpr = parseStateExpr(io.rightOperand)
                let lhsAction = lhsExpr == nil ? parseAction(io.leftOperand) : nil
                let rhsAction = rhsExpr == nil ? parseAction(io.rightOperand) : nil
                if let s = lhsExpr, let a = rhsAction { return .and(.guard_(s), a) }
                if let a = lhsAction, let s = rhsExpr { return .and(a, .guard_(s)) }
                if let l = lhsAction, let r = rhsAction { return .and(l, r) }
            }
        }
        if let call = e.as(FunctionCallExprSyntax.self), let chain = parseBecomesChain(call) { return chain }
        if let ma = e.as(MemberAccessExprSyntax.self), ma.declName.baseName.text == "stays",
           let base = ma.base?.as(DeclReferenceExprSyntax.self) { return .unchanged(base.baseName.text) }
        if let s = parseStateExpr(e) { return .guard_(s) }
        return nil
    }


    private static func parseBecomesChain(_ call: FunctionCallExprSyntax) -> ActionExpr? {
        let chain = unwrapWhen(call)
        guard let (vn, v) = parseBecomes(chain.call) else { return nil }
        let a = ActionExpr.assign(vn, v)
        return chain.condition.map { .and(.guard_($0), a) } ?? a
    }

    private struct Chain { let call: FunctionCallExprSyntax; let condition: StateExpr? }
    private static func unwrapWhen(_ c: FunctionCallExprSyntax) -> Chain {
        if let ma = c.calledExpression.as(MemberAccessExprSyntax.self), ma.declName.baseName.text == "when",
           let base = ma.base?.as(FunctionCallExprSyntax.self) {
            let cond = parseStateExpr(c.arguments.first?.expression)
            let inner = unwrapWhen(base)
            if let cd = cond, let inr = inner.condition { return Chain(call: inner.call, condition: .and(cd, inr)) }
            return Chain(call: inner.call, condition: cond ?? inner.condition)
        }
        return Chain(call: c, condition: nil)
    }

    private static func parseBecomes(_ c: FunctionCallExprSyntax) -> (String, StateExpr)? {
        guard let ma = c.calledExpression.as(MemberAccessExprSyntax.self), ma.declName.baseName.text == "becomes",
              let base = ma.base?.as(DeclReferenceExprSyntax.self), let arg = c.arguments.first?.expression else { return nil }
        return (base.baseName.text, parseStateExpr(arg) ?? .value(.int(0)))
    }

    // MARK: - State expression parsing

    private static func parseStateExpr(_ e: ExprSyntax?) -> StateExpr? {
        guard let e else { return nil }
        if let il = e.as(IntegerLiteralExprSyntax.self) { return .value(.int(Int(il.literal.text) ?? 0)) }
        if let dr = e.as(DeclReferenceExprSyntax.self) { return .variable(dr.baseName.text) }
        if let io = e.as(InfixOperatorExprSyntax.self), let l = parseStateExpr(io.leftOperand), let r = parseStateExpr(io.rightOperand) {
            switch io.operator.as(BinaryOperatorExprSyntax.self)?.operator.text {
            case "+": return .add(l, r); case "-": return .subtract(l, r)
            case "*": return .multiply(l, r); case "/": return .divide(l, r); case "%": return .modulo(l, r)
            case "<": return .lessThan(l, r); case "<=": return .lessOrEqual(l, r)
            case ">": return .greaterThan(l, r); case ">=": return .greaterOrEqual(l, r)
            case "==": return .equal(l, r); case "!=": return .notEqual(l, r)
            case "&&": return .and(l, r); case "||": return .or(l, r)
            default: return nil
            }
        }
        if let se = e.as(SequenceExprSyntax.self) {
            let c = Array(se.elements)
            guard c.count == 3, let l = parseStateExpr(c[0]),
                  let op = c[1].as(BinaryOperatorExprSyntax.self)?.operator.text,
                  let r = parseStateExpr(c[2]) else { return nil }
            switch op {
            case "+": return .add(l, r); case "-": return .subtract(l, r)
            case "*": return .multiply(l, r); case "/": return .divide(l, r); case "%": return .modulo(l, r)
            case "<": return .lessThan(l, r); case "<=": return .lessOrEqual(l, r)
            case ">": return .greaterThan(l, r); case ">=": return .greaterOrEqual(l, r)
            case "==": return .equal(l, r); case "!=": return .notEqual(l, r)
            case "&&": return .and(l, r); case "||": return .or(l, r)
            default: return nil
            }
        }
        if let pe = e.as(PrefixOperatorExprSyntax.self) {
            let op = pe.operator.text
            let rhs = parseStateExpr(pe.expression)
            if op == "!" { if let r = rhs { return .not(r) } }
            if op == "-" { if let r = rhs { return .negate(r) } }
        }
        return nil
    }

    // MARK: - Getter parsing

    private static func extractGetter(_ binding: PatternBindingSyntax) -> CodeBlockItemListSyntax? {
        guard let accessors = binding.accessorBlock?.accessors else { return nil }
        if let list = accessors.as(CodeBlockItemListSyntax.self) { return list }
        if let decls = accessors.as(AccessorDeclListSyntax.self) {
            for d in decls where d.accessorSpecifier.text == "get" { return d.body?.statements }
        }
        return nil
    }

    private static func parseExprInGetter(_ body: CodeBlockItemListSyntax) -> StateExpr? {
        for stmt in body {
            guard case .expr(let e) = stmt.item else { continue }
            return parseStateExpr(e)
        }
        return nil
    }

    // MARK: - Temporal & fairness

    private static func parseTemporal(_ body: CodeBlockItemListSyntax) -> TemporalExpr? {
        for stmt in body {
            guard case .expr(let e) = stmt.item else { continue }
            if let temporal = extractTemporal(e) { return temporal }
        }
        return nil
    }

    private static func extractTemporal(_ e: ExprSyntax) -> TemporalExpr? {
        if let call = e.as(FunctionCallExprSyntax.self),
           let ma = call.calledExpression.as(MemberAccessExprSyntax.self) {
            let method = ma.declName.baseName.text
            let arg = call.arguments.first?.expression
            let expr = arg.flatMap { parseStateExpr($0) }
            switch method {
            case "always": if let e = expr { return .always(e) }
            case "eventually": if let e = expr { return .eventually(e) }
            case "alwaysEventually": if let e = expr { return .alwaysEventually(e) }
            case "eventuallyAlways": if let e = expr { return .eventuallyAlways(e) }
            case "leadsTo":
                if let base = ma.base.flatMap({ parseStateExpr($0) }), let target = expr {
                    return .leadsTo(base, target)
                }
            default: break
            }
        }
        if let call = e.as(FunctionCallExprSyntax.self) {
            let text = call.calledExpression.description.trimmingCharacters(in: .whitespaces)
            if text == "always", let arg = parseStateExpr(call.arguments.first?.expression) { return .always(arg) }
            if text == "eventually", let arg = parseStateExpr(call.arguments.first?.expression) { return .eventually(arg) }
            if text == "alwaysEventually", let arg = parseStateExpr(call.arguments.first?.expression) { return .alwaysEventually(arg) }
            if text == "eventuallyAlways", let arg = parseStateExpr(call.arguments.first?.expression) { return .eventuallyAlways(arg) }
        }
        return nil
    }

    private static func parseFairness(_ body: CodeBlockItemListSyntax) -> FairnessCondition? {
        for stmt in body {
            guard case .expr(let e) = stmt.item else { continue }
            if let call = e.as(FunctionCallExprSyntax.self),
               let ma = call.calledExpression.as(MemberAccessExprSyntax.self) {
                let method = ma.declName.baseName.text
                if method == "weakFairness" || method == "strongFairness",
                   let name = call.arguments.first?.expression.as(StringLiteralExprSyntax.self)?.segments.first,
                   case .stringSegment(let seg) = name {
                    return method == "weakFairness" ? .weakFairness(seg.content.text) : .strongFairness(seg.content.text)
                }
            }
        }
        return nil
    }

    // MARK: - Variable init extraction

    private static func extractVarInit(_ e: ExprSyntax?) -> TLAValue {
        guard let e else { return .int(0) }
        if let il = e.as(IntegerLiteralExprSyntax.self) { return .int(Int(il.literal.text) ?? 0) }
        if let c = e.as(FunctionCallExprSyntax.self), c.arguments.count >= 2,
           let s = c.arguments[c.arguments.index(c.arguments.startIndex, offsetBy: 1)].expression.as(IntegerLiteralExprSyntax.self) {
            return .int(Int(s.literal.text) ?? 0)
        }
        return .int(0)
    }
}
