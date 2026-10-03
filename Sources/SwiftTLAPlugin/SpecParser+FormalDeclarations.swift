import SwiftTLA
import SwiftSyntax

extension ParserSession {
    func parseLiteralValue(_ expression: ExprSyntax) -> TLAValue? {
        if let integer = SourceIntegerLiteral.value(expression) {
            return .int(integer)
        }
        if let boolean = expression.as(BooleanLiteralExprSyntax.self) {
            return .bool(boolean.literal.text == "true")
        }
        if let string = expression.as(StringLiteralExprSyntax.self) {
            return string.representedLiteralValue.map(TLAValue.string)
        }
        return nil
    }

    func extractStringArg(
        _ call: FunctionCallExprSyntax,
        index: Int,
        loopVar: String? = nil,
        loopValue: Int? = nil
    ) -> String? {
        let args = Array(call.arguments)
        guard index < args.count else { return nil }
        guard let stringLit = args[index].expression.as(StringLiteralExprSyntax.self) else { return nil }
        guard let loopVar, let loopValue else { return stringLit.representedLiteralValue }
        var value = ""
        for segment in stringLit.segments {
            if let text = segment.as(StringSegmentSyntax.self)?.content.text {
                value += text
                continue
            }
            guard let expression = segment.as(ExpressionSegmentSyntax.self),
                  expression.expressions.count == 1,
                  let reference = expression.expressions.first?.expression.as(DeclReferenceExprSyntax.self),
                  reference.baseName.text == loopVar
            else { return nil }
            value += "\(loopValue)"
        }
        return value
    }

    func parseVariableDecl(_ call: FunctionCallExprSyntax, into components: inout TLASpec) {
        let arguments = Array(call.arguments)
        let isReference = arguments.count == 1 && arguments.first?.label == nil
        let isInitializer = arguments.count == 2 && arguments[0].label == nil
            && [nil, "in"].contains(arguments[1].label?.text)
        let isDomain = arguments.count == 2 && arguments[0].label?.text == "from"
            && arguments[1].label == nil
        guard isReference || isInitializer || isDomain,
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty
        else {
            components.diagnostics.append(.init(message: "Malformed Variable declaration", source: call))
            return
        }
        guard let name = parsedVariableName(arguments[0].expression) else {
            components.diagnostics.append(.init(
                message: "Variable requires a declared variable binding.", source: call,
                expected: "Variable(variable) or Variable(variable, initialValue)"))
            return
        }
        if isReference {
            guard arguments[0].expression.is(DeclReferenceExprSyntax.self),
                  components.variables.contains(where: { $0.name == name }) else {
                components.diagnostics.append(.init(
                    message: "Variable '\(name)' is not bound by a prior Var declaration", source: call))
                return
            }
            return
        }
        let initializer = arguments[1].expression
        if isDomain || arguments[1].label?.text == "in" {
            guard let domain = decodeStateExpr(initializer) else {
                components.diagnostics.append(.init(
                    message: "Variable '\(name)' requires a supported initial domain.", source: call))
                return
            }
            components.variables.append(.init(name: name, initialization: .memberOf(domain), origin: .source))
        } else if let value = parseInitialExpr(initializer) {
            components.variables.append(.init(name: name, initial: value))
        } else if let value = decodeTypedFacadeValue(initializer, scope: sourceScope) {
            components.variables.append(.init(name: name, initialization: .expression(value), origin: .source))
        } else {
            components.diagnostics.append(.init(
                message: "Variable '\(name)' requires a supported initial formal value.", source: call,
                expected: "an integer, boolean, string, supported TLAValue constructor, or finite initial-state expression"))
        }
    }

    func parsedVariableName(_ expression: ExprSyntax) -> String? {
        if let literal = expression.as(StringLiteralExprSyntax.self) {
            return literal.representedLiteralValue
        }
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if let member = expression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "name",
           let reference = member.base?.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        return nil
    }

    func parseTLAValueConstructor(name: String, call: FunctionCallExprSyntax) -> TLAValue? {
        guard call.arguments.count == 1,
              call.trailingClosure == nil,
              call.additionalTrailingClosures.isEmpty,
              let argument = call.arguments.first,
              argument.label == nil
        else { return nil }
        switch name {
        case "set", "tuple":
            guard let array = argument.expression.as(ArrayExprSyntax.self), array.elements.isEmpty else { return nil }
            return name == "set" ? .set([]) : .tuple([])
        case "record", "function":
            guard let dictionary = argument.expression.as(DictionaryExprSyntax.self),
                  case .colon = dictionary.content
            else { return nil }
            return name == "record" ? .record([:]) : .function([:])
        default:
            return nil
        }
    }

    func parseConstantDecl(_ call: FunctionCallExprSyntax, into components: inout TLASpec) {
        let args = Array(call.arguments)
        guard args.count == 2, args.allSatisfy({ $0.label == nil }),
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              let name = extractStringArg(call, index: 0)
        else {
            components.diagnostics.append(.init(
                message: "Constant requires a literal name and a static TLA+ value.",
                source: call,
                expected: "Constant(\"Name\", value)",
                nextSafeAction: "Use a literal constant name and a static typed value."
            ))
            return
        }
        guard let expression = decodeTypedFacadeValue(args[1].expression, scope: .empty),
              let value = staticConstantValue(expression)
        else {
            components.diagnostics.append(.init(
                message: "Constant '\(name)' must be static; dynamic formal expressions are not constant values.",
                source: args[1].expression,
                expected: "a literal value or SetExpr<Element>(...) with static members",
                nextSafeAction: "Use a closed typed value such as SetExpr<Element>(.first, .second)."
            ))
            return
        }
        components.constants.append(ConstantDecl(name, value))
    }

    private func staticConstantValue(_ expression: StateExpr) -> TLAValue? {
        switch expression {
        case .sourceIssue:
            return nil
        case .value(let value):
            return value
        case .setLiteral(let elements):
            let values = elements.compactMap(staticConstantValue)
            guard values.count == elements.count else { return nil }
            return .set(Set(values))
        default:
            return nil
        }
    }
}
