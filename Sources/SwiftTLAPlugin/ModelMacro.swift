import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA

public struct ModelMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let ext = ("""
            extension \(type.trimmed): TLAModelType {}
            """ as DeclSyntax).as(ExtensionDeclSyntax.self) else {
            return []
        }
        return [ext]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else {
            throw SimpleError("@TLAModel on structs only")
        }
        let typeName = structDeclaration.name.text

        let parsed = try parseSpecBody(structDeclaration.memberBlock.members, typeName: typeName)
        if parsed.variables.isEmpty { throw SimpleError("parsed.variables is empty") }

        let specification = TLASpec(
            name: typeName,
            variables: parsed.variables.map { NamedVar(name: $0.name, initial: $0.initial, initialSet: $0.initialSet) },
            constants: parsed.constants,
            actions: parsed.actions.map { NamedAction(name: $0.name, body: $0.body) },
            invariants: parsed.invariants.map { NamedInvariant(name: $0.name, body: $0.body) },
            temporalProperties: parsed.temporal.map { NamedTemporal(name: $0.name, expr: $0.expr) },
            fairness: parsed.fairness
        )

        let checker = ModelChecker(spec: specification, maxStates: 10_000)
        let checkResult: CheckResult
        do {
            checkResult = try checker.check()
        } catch {
            throw SimpleError("Checker failed: \(error)")
        }

        switch checkResult {
        case .invariantViolated(let invariant, _, let trace):
            let description = trace.map { String(describing: $0) }.joined(separator: "\n")
            throw SimpleError("Invariant '\(invariant)' violated:\n\(description)")
        case .error(let message):
            throw SimpleError("Checker error: \(message)")
        case .deadlocked(let state):
            throw SimpleError("Deadlock at: \(state)")
        case .depthExceeded(let count, let limit):
            throw SimpleError("Depth exceeded: \(count) states (limit \(limit))")
        case .ok:
            break
        }

        return [DeclSyntax(stringLiteral: """
        public static var runtime: SpecRuntime { SpecRuntime(spec: spec) }
        """)]
    }

    private struct ParsedSpec {
        var variables: [(name: String, initial: TLAValue, initialSet: StateExpr?)] = []
        var actions: [(name: String, body: ActionExpr)] = []
        var invariants: [(name: String, body: StateExpr)] = []
        var temporal: [(name: String, expr: TemporalExpr)] = []
        var fairness: [FairnessCondition] = []
        var constants: [String: TLAValue] = [:]
    }

    private static func parseSpecBody(_ members: MemberBlockItemListSyntax, typeName: String) throws -> ParsedSpec {
        for member in members {
            guard let variableDeclaration = member.decl.as(VariableDeclSyntax.self),
                  let binding = variableDeclaration.bindings.first,
                  binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "spec",
                  let getter = extractGetterBody(binding)
            else { continue }

            for statement in getter {
                guard case .expr(let expression) = statement.item else { continue }
                if let functionCall = expression.as(FunctionCallExprSyntax.self),
                   let callee = functionCall.calledExpression.as(DeclReferenceExprSyntax.self),
                   callee.baseName.text == "TLASpec" {
                    let closure = functionCall.trailingClosure ?? functionCall.arguments.last?.expression.as(ClosureExprSyntax.self)
                    if let closure {
                        return try parseBuilderBody(closure.statements)
                    }
                }
            }
        }
        throw SimpleError("Could not find 'TLASpec' builder in struct '\(typeName)'")
    }

    private static func extractGetterBody(_ binding: PatternBindingSyntax) -> CodeBlockItemListSyntax? {
        if let closure = binding.accessorBlock?.accessors.as(CodeBlockItemListSyntax.self) {
            return closure
        }
        if let accessors = binding.accessorBlock?.accessors.as(AccessorDeclListSyntax.self) {
            for accessor in accessors {
                if accessor.accessorSpecifier.tokenKind == .keyword(.get) {
                    return accessor.body?.statements
                }
            }
        }
        return nil
    }

    private static func parseBuilderBody(_ statements: CodeBlockItemListSyntax) throws -> ParsedSpec {
        var result = ParsedSpec()
        for statement in statements {
            guard case .expr(let expression) = statement.item else { continue }
            if let fc = expression.as(FunctionCallExprSyntax.self) {
                let name = fc.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
                if name == "Variable" {
                    if let args = try? parseVariableArgs(fc) {
                        result.variables.append(args)
                    }
                } else if name == "Action" {
                    let actionName = fc.arguments.first?.expression.as(StringLiteralExprSyntax.self)?.segments.first?.as(StringSegmentSyntax.self)?.content.text ?? ""
                    if let body = fc.trailingClosure {
                        if let actionExpr = SpecParser.parseActionFrom(body) {
                            result.actions.append((actionName, actionExpr))
                        }
                    }
                } else if name == "Invariant" {
                    let invName = fc.arguments.first?.expression.as(StringLiteralExprSyntax.self)?.segments.first?.as(StringSegmentSyntax.self)?.content.text ?? ""
                    if let body = fc.trailingClosure {
                        if let stateExpr = SpecParser.parseInvariantFrom(body) {
                            result.invariants.append((invName, stateExpr))
                        }
                    }
                } else if name == "Constant" {
                    try parseConstantArgs(fc, into: &result)
                }
            } else if let fc = expression.as(MemberAccessExprSyntax.self) {
                // Handle Extends("Naturals") etc.
            }
        }
        return result
    }

    private static func parseVariableArgs(_ call: FunctionCallExprSyntax) throws -> (name: String, initial: TLAValue, initialSet: StateExpr?)? {
        let args = call.arguments
        if args.count == 2 {
            let name = args.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text ?? ""
            if let intVal = args.last?.expression.as(IntegerLiteralExprSyntax.self) {
                return (name, .int(Int(intVal.literal.text) ?? 0), nil)
            }
            if let boolVal = args.last?.expression.as(BooleanLiteralExprSyntax.self) {
                return (name, .bool(boolVal.literal.text == "true"), nil)
            }
            if let strVal = args.last?.expression.as(StringLiteralExprSyntax.self) {
                return (name, .string(strVal.segments.first?.as(StringSegmentSyntax.self)?.content.text ?? ""), nil)
            }
        }
        return nil
    }

    private static func parseConstantArgs(_ call: FunctionCallExprSyntax, into parsed: inout ParsedSpec) throws {
        let args = call.arguments
        if args.count == 2 {
            let name = args.first?.expression.as(StringLiteralExprSyntax.self)?.segments.first?.as(StringSegmentSyntax.self)?.content.text ?? ""
            if let strVal = args.last?.expression.as(StringLiteralExprSyntax.self) {
                let val = strVal.segments.first?.as(StringSegmentSyntax.self)?.content.text ?? ""
                parsed.constants[name] = .string(val)
            }
        }
    }

    struct SimpleError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
