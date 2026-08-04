import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA
import SwiftTLAGeneration

public struct ModelMacro: PeerMacro, MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else { throw SimpleError("@TLAModel on structs only") }
        let typeName = structDecl.name.text
        let parsed = parseStruct(structDecl)

        let spec = TLASpec(name: typeName, variables: parsed.variables.map { NamedVar(name: $0.0, initial: $0.1) }, actions: parsed.actions.map { NamedAction(name: $0.0, body: $0.1) }, invariants: parsed.invariants.map { NamedInvariant(name: $0.0, body: $0.1) }, temporalProperties: parsed.temporal.map { NamedTemporal(name: $0.0, expr: $0.1) }, fairness: parsed.fairness)

        let checker = ModelChecker(spec: spec, maxStates: 10_000)
        if case .invariantViolated(let inv, _, let trace) = (try? checker.check()) {
            throw SimpleError("Invariant '\(inv)' violated:\n\(trace.map{"\($0)"}.joined(separator:"\n"))")
        }
        guard let graph = try? checker.exploreGraph() else { throw SimpleError("Could not explore state graph") }
        let code = (try? StateMachineGenerator(graph: graph).generate()) ?? ""
        let renamed = code
            .replacingOccurrences(of: "struct \(typeName)", with: "struct TLAStateMachine")
            .replacingOccurrences(of: "static let initial = \(typeName)(", with: "static let initial = TLAStateMachine(")
        return Parser.parse(source: renamed).statements.compactMap { $0.item.as(DeclSyntax.self) }
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else { return [] }
        let typeName = structDecl.name.text
        let parsed = parseStruct(structDecl)
        let spec = TLASpec(name: typeName,
            variables: parsed.variables.map { NamedVar(name: $0.0, initial: $0.1) },
            actions: parsed.actions.map { NamedAction(name: $0.0, body: $0.1) },
            invariants: parsed.invariants.map { NamedInvariant(name: $0.0, body: $0.1) },
            temporalProperties: parsed.temporal.map { NamedTemporal(name: $0.0, expr: $0.1) },
            fairness: parsed.fairness)
        let b64 = spec.base64JSON
        return [DeclSyntax(stringLiteral: """
            static var spec: TLASpec { TLASpec.decode(base64: "\(b64)") }
            """)]
    }

    private struct ParseResult {
        var variables: [(String, TLAValue)] = []
        var actions: [(String, ActionExpr)] = []
        var invariants: [(String, StateExpr)] = []
        var temporal: [(String, TemporalExpr)] = []
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
                            if let expr = parseExprInGetter(body) { result.invariants.append((name, expr)) }
                        } else if returnType.hasPrefix("TemporalExpr"), let body = getterBody {
                            if let t = parseTemporal(body) { result.temporal.append((name, t)) }
                        } else if returnType == "FairnessCondition", let body = getterBody {
                            if let f = parseFairness(body) { result.fairness.append(f) }
                        }
                    } else {
                        let val = extractVarInit(binding.initializer?.value)
                        result.variables.append((name, val))
                    }
                }
            } else if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let name = funcDecl.name.text
                if let body = funcDecl.body {
                    let clauses = parseBody(body.statements)
                    if clauses.isEmpty {
                        result.actions.append((name, .guard_(.value(.bool(true)))))
                    } else {
                        result.actions.append((name, clauses.dropFirst().reduce(clauses[0]) { .and($0, $1) }))
                    }
                } else {
                    result.actions.append((name, .guard_(.value(.bool(true)))))
                }
            }
        }
        return result
    }

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

    private static func parseTemporal(_ body: CodeBlockItemListSyntax) -> TemporalExpr? {
        for stmt in body {
            guard case .expr(let e) = stmt.item else { continue }
            let text = e.description.trimmingCharacters(in: .whitespaces)
            if text.contains(".alwaysEventually") { return .alwaysEventually(.value(.bool(true))) }
            if text.contains(".leadsTo") { return .leadsTo(.value(.bool(true)), .value(.bool(true))) }
            if text.contains(".eventuallyAlways") { return .eventuallyAlways(.value(.bool(true))) }
            if text.contains(".eventually") { return .eventually(.value(.bool(true))) }
            if text.contains(".always") { return .always(.value(.bool(true))) }
        }
        return nil
    }

    private static func parseFairness(_ body: CodeBlockItemListSyntax) -> FairnessCondition? {
        for stmt in body {
            guard case .expr(let e) = stmt.item else { continue }
            let text = e.description.trimmingCharacters(in: .whitespaces)
            if text.contains(".weakFairness") {
                let name = text.components(separatedBy: "\"").dropFirst().first ?? "Act"
                return .weakFairness(name)
            }
            if text.contains(".strongFairness") {
                let name = text.components(separatedBy: "\"").dropFirst().first ?? "Act"
                return .strongFairness(name)
            }
        }
        return nil
    }

    private static func parseBody(_ s: CodeBlockItemListSyntax) -> [ActionExpr] {
        s.compactMap { stmt -> ActionExpr? in guard case .expr(let e) = stmt.item else { return nil }; return parseBecomesChain(e) }
    }

    private static func parseBecomesChain(_ e: ExprSyntax) -> ActionExpr? {
        guard let call = e.as(FunctionCallExprSyntax.self) else { return nil }
        let chain = unwrapWhen(call)
        guard let (vn, v) = parseBecomes(chain.call) else { return nil }
        let a = ActionExpr.assign(vn, v)
        return chain.condition.map { .and(.guard_($0), a) } ?? a
    }

    private struct Chain { let call: FunctionCallExprSyntax; let condition: StateExpr? }
    private static func unwrapWhen(_ c: FunctionCallExprSyntax) -> Chain {
        if let ma = c.calledExpression.as(MemberAccessExprSyntax.self), ma.declName.baseName.text == "when", let base = ma.base?.as(FunctionCallExprSyntax.self) {
            let cond = parseStateExpr(c.arguments.first?.expression)
            let inner = unwrapWhen(base)
            if let cd = cond, let inr = inner.condition { return Chain(call: inner.call, condition: .and(cd, inr)) }
            return Chain(call: inner.call, condition: cond ?? inner.condition)
        }
        return Chain(call: c, condition: nil)
    }

    private static func parseBecomes(_ c: FunctionCallExprSyntax) -> (String, StateExpr)? {
        guard let ma = c.calledExpression.as(MemberAccessExprSyntax.self), ma.declName.baseName.text == "becomes", let base = ma.base?.as(DeclReferenceExprSyntax.self), let arg = c.arguments.first?.expression else { return nil }
        return (base.baseName.text, parseStateExpr(arg) ?? .value(.int(0)))
    }

    private static func parseStateExpr(_ e: ExprSyntax?) -> StateExpr? {
        guard let e else { return nil }
        if let il = e.as(IntegerLiteralExprSyntax.self) { return .value(.int(Int(il.literal.text) ?? 0)) }
        if let dr = e.as(DeclReferenceExprSyntax.self) { return .variable(dr.baseName.text) }
        if let io = e.as(InfixOperatorExprSyntax.self), let l = parseStateExpr(io.leftOperand), let r = parseStateExpr(io.rightOperand) {
            switch io.operator.as(BinaryOperatorExprSyntax.self)?.operator.text {
            case "+": return .add(l, r); case "-": return .subtract(l, r); case "*": return .multiply(l, r); case "/": return .divide(l, r)
            case "<": return .lessThan(l, r); case "<=": return .lessOrEqual(l, r); case ">": return .greaterThan(l, r); case ">=": return .greaterOrEqual(l, r)
            case "==": return .equal(l, r); case "!=": return .notEqual(l, r); case "%": return .modulo(l, r)
            case "&&": return .and(l, r); case "||": return .or(l, r)
            default: return nil
            }
        }
        if let se = e.as(SequenceExprSyntax.self) {
            let components = Array(se.elements)
            guard components.count == 3 else { return nil }
            let lhs = parseStateExpr(components[0])
            let op = components[1].as(BinaryOperatorExprSyntax.self)?.operator.text
            let rhs = parseStateExpr(components[2])
            guard let l = lhs, let r = rhs, let o = op else { return nil }
            switch o {
            case "+": return .add(l, r); case "-": return .subtract(l, r); case "*": return .multiply(l, r); case "/": return .divide(l, r)
            case "<": return .lessThan(l, r); case "<=": return .lessOrEqual(l, r); case ">": return .greaterThan(l, r); case ">=": return .greaterOrEqual(l, r)
            case "==": return .equal(l, r); case "!=": return .notEqual(l, r); case "%": return .modulo(l, r)
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

    private static func extractVarInit(_ e: ExprSyntax?) -> TLAValue {
        guard let e else { return .int(0) }
        if let il = e.as(IntegerLiteralExprSyntax.self) { return .int(Int(il.literal.text) ?? 0) }
        if let c = e.as(FunctionCallExprSyntax.self), c.arguments.count >= 2, let s = c.arguments[c.arguments.index(c.arguments.startIndex, offsetBy: 1)].expression.as(IntegerLiteralExprSyntax.self) { return .int(Int(s.literal.text) ?? 0) }
        return .int(0)
    }
}
