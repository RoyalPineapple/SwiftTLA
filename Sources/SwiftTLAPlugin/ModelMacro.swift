import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA
import SwiftTLAGeneration

public struct ModelMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else {
            throw SimpleError("@TLAModel on structs only")
        }
        let typeName = structDeclaration.name.text

        let parsed = try parseSpecFromMembers(structDeclaration.memberBlock.members, typeName: typeName)
        let specification = TLASpec(
            name: typeName,
            variables: parsed.variables.map { NamedVar(name: $0.name, initial: $0.initial) },
            actions: parsed.actions.map { NamedAction(name: $0.name, body: $0.body) },
            invariants: parsed.invariants.map { NamedInvariant(name: $0.name, body: $0.body) },
            temporalProperties: [],
            fairness: []
        )

        let checker = ModelChecker(spec: specification, maxStates: 10_000)
        if case .invariantViolated(let invariant, let state, let trace) = (try? checker.check()) {
            let description = trace.map { String(describing: $0) }.joined(separator: "\n")
            throw SimpleError("Invariant '" + invariant + "' violated:\n" + description)
        }

        var generatedMembers: [DeclSyntax] = []

        if let graph = try? checker.exploreGraph(),
           let code = try? StateMachineGenerator(graph: graph).generate() {
            let renamed = code
                .replacingOccurrences(of: "struct " + typeName, with: "struct Machine")
                .replacingOccurrences(of: "static let initial = " + typeName + "(", with: "static let initial = Machine(")
            let machineDeclarations = Parser.parse(source: renamed).statements.compactMap {
                $0.item.as(DeclSyntax.self)
            }
            generatedMembers.append(contentsOf: machineDeclarations)
        }

        return generatedMembers
    }

    private struct ParsedSpec {
        var variables: [(name: String, initial: TLAValue)] = []
        var actions: [(name: String, body: ActionExpr)] = []
        var invariants: [(name: String, body: StateExpr)] = []
    }

    private static func parseSpecFromMembers(_ members: MemberBlockItemListSyntax, typeName: String) throws -> ParsedSpec {
        for member in members {
            guard let variableDeclaration = member.decl.as(VariableDeclSyntax.self),
                  variableDeclaration.modifiers.contains(where: { $0.name.text == "static" }),
                  let binding = variableDeclaration.bindings.first,
                  binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "spec"
            else { continue }

            // TLASpec("Name") { ... } direct init
            if let initializer = binding.initializer?.value.as(FunctionCallExprSyntax.self),
               let callee = initializer.calledExpression.as(DeclReferenceExprSyntax.self),
               callee.baseName.text == "TLASpec",
               let trailingClosure = initializer.trailingClosure {
                let name = extractStringLiteral(initializer.arguments.first?.expression) ?? typeName
                return parseBuilderBody(trailingClosure.statements, typeName: name)
            }

            // static var spec: TLASpec { ... } getter
            if let getter = extractGetterBody(binding) {
                return parseBuilderBody(getter, typeName: typeName)
            }
        }
        throw SimpleError("@TLAModel struct must contain 'static var spec = TLASpec(\"Name\") { ... }' or 'static var spec: TLASpec { ... }'")
    }

    private static func extractGetterBody(_ binding: PatternBindingSyntax) -> CodeBlockItemListSyntax? {
        guard let accessors = binding.accessorBlock?.accessors else { return nil }
        if let list = accessors.as(CodeBlockItemListSyntax.self) { return list }
        if let declarationList = accessors.as(AccessorDeclListSyntax.self) {
            for declaration in declarationList where declaration.accessorSpecifier.text == "get" {
                return declaration.body?.statements
            }
        }
        return nil
    }

    private static func parseBuilderBody(_ statements: CodeBlockItemListSyntax, typeName: String) -> ParsedSpec {
        var result = ParsedSpec()
        for statement in statements {
            switch statement.item {
            case .decl(let declaration):
                if let variableDeclaration = declaration.as(VariableDeclSyntax.self),
                   let binding = variableDeclaration.bindings.first,
                   let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                   let initializerCall = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                   let callee = initializerCall.calledExpression.as(DeclReferenceExprSyntax.self),
                   callee.baseName.text == "Var",
                   let value = parseInitialValue(initializerCall.arguments.first?.expression) {
                    result.variables.append((name, value))
                }
            case .expr(let expression):
                guard let call = expression.as(FunctionCallExprSyntax.self),
                      let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) else { continue }
                switch reference.baseName.text {
                case "Action":
                    guard let name = extractStringLiteral(call.arguments.first?.expression),
                          let body = parseActionClosure(call.arguments.dropFirst().first?.expression) else { continue }
                    result.actions.append((name, body))
                case "Invariant":
                    guard let name = extractStringLiteral(call.arguments.first?.expression),
                          let body = parseStateExpr(call.arguments.dropFirst().first?.expression) else { continue }
                    result.invariants.append((name, body))
                default: continue
                }
            case .stmt: continue
            }
        }
        return result
    }

    private static func extractStringLiteral(_ expression: ExprSyntax?) -> String? {
        expression?.as(StringLiteralExprSyntax.self)?.segments.description.replacingOccurrences(of: "\"", with: "")
    }

    private static func parseInitialValue(_ expression: ExprSyntax?) -> TLAValue? {
        guard let expression else { return nil }
        if let integerLiteral = expression.as(IntegerLiteralExprSyntax.self) {
            return .int(Int(integerLiteral.literal.text) ?? 0)
        }
        if let booleanLiteral = expression.as(BooleanLiteralExprSyntax.self) {
            return .bool(booleanLiteral.literal.text == "true")
        }
        return nil
    }

    private static func parseActionClosure(_ expression: ExprSyntax?) -> ActionExpr? {
        guard let expression, let closure = expression.as(ClosureExprSyntax.self) else { return nil }
        let actions = closure.statements.compactMap { statement -> ActionExpr? in
            guard case .expr(let inner) = statement.item else { return nil }
            return parseSingleAction(inner)
        }
        if actions.isEmpty { return .guard_(.value(.bool(true))) }
        return actions.dropFirst().reduce(actions[0]) { .and($0, $1) }
    }

    private static func parseSingleAction(_ expression: ExprSyntax) -> ActionExpr? {
        if let call = expression.as(FunctionCallExprSyntax.self), let chain = parseBecomesChain(call) { return chain }
        if let memberAccess = expression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "stays",
           let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
            return .unchanged(base.baseName.text)
        }
        return nil
    }

    private static func parseBecomesChain(_ call: FunctionCallExprSyntax) -> ActionExpr? {
        let chain = unwrapWhen(call)
        guard let (variableName, value) = parseBecomes(chain.call) else { return nil }
        let action = ActionExpr.assign(variableName, value)
        return chain.condition.map { .and(.guard_($0), action) } ?? action
    }

    private struct Chain { let call: FunctionCallExprSyntax; let condition: StateExpr? }

    private static func unwrapWhen(_ call: FunctionCallExprSyntax) -> Chain {
        if let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "when",
           let base = memberAccess.base?.as(FunctionCallExprSyntax.self) {
            let condition = parseStateExpr(call.arguments.first?.expression)
            let inner = unwrapWhen(base)
            if let outerCondition = condition, let innerCondition = inner.condition {
                return Chain(call: inner.call, condition: .and(outerCondition, innerCondition))
            }
            return Chain(call: inner.call, condition: condition ?? inner.condition)
        }
        return Chain(call: call, condition: nil)
    }

    private static func parseBecomes(_ call: FunctionCallExprSyntax) -> (String, StateExpr)? {
        guard let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "becomes",
              let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
              let argument = call.arguments.first?.expression else { return nil }
        return (base.baseName.text, parseStateExpr(argument) ?? .value(.int(0)))
    }

    private static func parseStateExpr(_ expression: ExprSyntax?) -> StateExpr? {
        guard let expression else { return nil }
        if let integerLiteral = expression.as(IntegerLiteralExprSyntax.self) { return .value(.int(Int(integerLiteral.literal.text) ?? 0)) }
        if let reference = expression.as(DeclReferenceExprSyntax.self) { return .variable(reference.baseName.text) }
        if let tuple = expression.as(TupleExprSyntax.self), let single = tuple.elements.first?.expression { return parseStateExpr(single) }
        if let infix = expression.as(InfixOperatorExprSyntax.self), let left = parseStateExpr(infix.leftOperand), let right = parseStateExpr(infix.rightOperand) {
            switch infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text {
            case "+": return .add(left, right); case "-": return .subtract(left, right)
            case "*": return .multiply(left, right); case "/": return .divide(left, right); case "%": return .modulo(left, right)
            case "<": return .lessThan(left, right); case "<=": return .lessOrEqual(left, right)
            case ">": return .greaterThan(left, right); case ">=": return .greaterOrEqual(left, right)
            case "==": return .equal(left, right); case "!=": return .notEqual(left, right)
            case "&&": return .and(left, right); case "||": return .or(left, right)
            default: return nil
            }
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3, let left = parseStateExpr(elements[0]),
                  let operatorText = elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text,
                  let right = parseStateExpr(elements[2]) else { return nil }
            switch operatorText {
            case "+": return .add(left, right); case "-": return .subtract(left, right)
            case "*": return .multiply(left, right); case "/": return .divide(left, right); case "%": return .modulo(left, right)
            case "<": return .lessThan(left, right); case "<=": return .lessOrEqual(left, right)
            case ">": return .greaterThan(left, right); case ">=": return .greaterOrEqual(left, right)
            case "==": return .equal(left, right); case "!=": return .notEqual(left, right)
            case "&&": return .and(left, right); case "||": return .or(left, right)
            default: return nil
            }
        }
        if let prefix = expression.as(PrefixOperatorExprSyntax.self) {
            let operand = parseStateExpr(prefix.expression)
            if prefix.operator.text == "!", let operand { return .not(operand) }
            if prefix.operator.text == "-", let operand { return .negate(operand) }
        }
        return nil
    }
}
