import SwiftTLA
import SwiftSyntax

extension ParserSession {
    struct ModelCollectionSourceTypes {
        let formalName: String
        let element: TypeSyntax
        let value: TypeSyntax
    }

    func collectModelCollectionTypes(
        in closure: ClosureExprSyntax
    ) -> [String: ModelCollectionSourceTypes] {
        var types: [String: ModelCollectionSourceTypes] = [:]
        for statement in closure.statements {
            guard case .decl(let declaration) = statement.item,
                  let variable = declaration.as(VariableDeclSyntax.self)
            else { continue }
            for binding in variable.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                  let type = typedFacadeType(call.calledExpression),
                  type.name == "CollectionVar",
                  let formalName = call.arguments.first?.expression
                    .as(StringLiteralExprSyntax.self)?.representedLiteralValue
                else { continue }
                guard let element = type.argument(at: 0),
                      let value = type.argument(at: 1),
                      type.arguments.count == 2
                else { continue }
                types[name] = .init(
                    formalName: formalName,
                    element: element,
                    value: value
                )
            }
        }
        return types
    }

    func parseModelCollectionDecl(
        _ call: FunctionCallExprSyntax,
        into components: inout TLASpec,
        collectionTypes: [String: ModelCollectionSourceTypes]
    ) {
        let arguments = Array(call.arguments)
        guard arguments.map({ $0.label?.text }) == [nil, "verificationScope", "initial"],
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              let collectionReference = arguments[0].expression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let types = collectionTypes[collectionReference],
              let scopeLiteral = arguments[1].expression.as(IntegerLiteralExprSyntax.self),
              let scope = SourceIntegerLiteral.value(scopeLiteral),
              let initial = parseLiteralValue(arguments[2].expression),
              let elementType = Self.sourceTypeSpelling(types.element),
              let valueType = Self.sourceTypeSpelling(types.value)
        else {
            components.diagnostics.append(.init(
                message: "Model collections require CollectionVar<Element, Value>, "
                    + "a positive integer literal scope, and a literal uniform initial value.",
                source: call
            ))
            return
        }

        let declaration = ModelCollectionDecl(
            name: types.formalName,
            verificationScope: scope,
            initial: initial,
            generatedElementType: elementType,
            generatedValueType: valueType
        )
        components.collections.append(declaration)
        components.variables.append(declaration.variable)
    }

    func parseCollectionAction(
        _ call: FunctionCallExprSyntax,
        into components: inout TLASpec,
        collectionTypes: [String: ModelCollectionSourceTypes]
    ) {
        let arguments = Array(call.arguments)
        guard let actionName = extractStringArg(call, index: 0),
              let collectionReference = arguments.first(where: { $0.label?.text == "on" })?.expression
                .as(DeclReferenceExprSyntax.self)?.baseName.text,
              let collection = collectionTypes[collectionReference],
              let closure = call.trailingClosure
        else {
            components.diagnostics.append(.init(
                message: "CollectionAction requires a literal name, a declared collection binding, and a builder body.",
                source: call,
                expected: "CollectionAction(\"update\", on: collection) { member in ... }"
            ))
            return
        }

        guard let memberName = collectionActionMemberName(in: closure) else {
            components.diagnostics.append(.init(
                message: "Collection action '\(actionName)' requires one named opaque member parameter.",
                source: closure
            ))
            return
        }
        let member = generatedBinderName(
            line: UInt(closure.positionAfterSkippingLeadingTrivia.utf8Offset), column: 0
        )
        let diagnosticCount = components.diagnostics.count
        validateMemberUses(
            memberName,
            in: closure,
            owning: collectionReference,
            action: actionName,
            into: &components
        )
        let actionScope = typedFacadeScope(sourceScope, binding: memberName, to: .variable(member))
        let actionBody: ActionExpr
        do {
            actionBody = try decodeActionFromClosure(closure, scope: actionScope,
                context: "Collection action '\(actionName)'")
        } catch {
            if components.diagnostics.count == diagnosticCount {
                components.diagnostics.append(error)
            }
            return
        }
        components.actions.append(.init(
            name: actionName,
            body: .existsAction(
                member,
                .domain(.variable(collection.formalName)),
                actionBody
            ),
            controlOwner: nil
        ))
    }

    func collectionActionMemberName(in closure: ClosureExprSyntax) -> String? {
        guard let parameters = closure.signature?.parameterClause else { return nil }
        switch parameters {
        case .simpleInput(let list):
            return list.first?.name.text
        case .parameterClause(let clause):
            guard let parameter = clause.parameters.first else { return nil }
            return parameter.secondName?.text ?? parameter.firstName.text
        }
    }

    func validateMemberUses(
        _ member: String,
        in closure: ClosureExprSyntax,
        owning collection: String,
        action: String,
        into components: inout TLASpec
    ) {
        let validator = CollectionMemberUseValidator(member: member, collection: collection)
        validator.walk(Syntax(closure))
        for violation in validator.violations {
            components.diagnostics.append(identityDiagnostic(
                collection: collection, action: action, source: violation.source,
                detail: violation.detail
            ))
        }
    }

    func identityDiagnostic(
        collection: String,
        action: String,
        source: Syntax,
        detail: String
    ) -> SourceParseDiagnostic {
        .init(
            message: "\(detail) for model collection '\(collection)' in action '\(action)': "
                + "member identity is opaque and may only select or update its owning collection. "
                + "Model the distinction as member state or use a non-model collection.",
            source: source
        )
    }

    private final class CollectionMemberUseValidator: SyntaxVisitor {
        struct Violation {
            let detail: String
            let source: Syntax
        }

        let member: String
        let collection: String
        var closureDepth = 0
        var permittedMemberOffsets: Set<Int> = []
        var violations: [Violation] = []

        init(member: String, collection: String) {
            self.member = member
            self.collection = collection
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
            closureDepth += 1
            return .visitChildren
        }

        override func visitPost(_ node: ClosureExprSyntax) {
            closureDepth -= 1
        }

        override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
            if node.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == collection,
               node.declName.baseName.text == "domain" {
                violations.append(.init(
                    detail: "Raw verification-domain access is unavailable",
                    source: Syntax(node)
                ))
            }
            return .visitChildren
        }

        override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
            if node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == collection,
               let selector = node.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
               node.arguments.count == 1,
               selector.baseName.text == member {
                permittedMemberOffsets.insert(selector.positionAfterSkippingLeadingTrivia.utf8Offset)
            }
            return .visitChildren
        }

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            if let access = node.calledExpression.as(MemberAccessExprSyntax.self),
               access.declName.baseName.text == "update",
               let selector = node.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
               selector.baseName.text == member {
                permittedMemberOffsets.insert(selector.positionAfterSkippingLeadingTrivia.utf8Offset)
                if let target = access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
                   target != collection {
                    violations.append(.init(
                        detail: "Cross-collection member use is unavailable (including '\(target)')",
                        source: Syntax(node)
                    ))
                }
            }
            return .visitChildren
        }

        override func visit(_ node: ExpressionSegmentSyntax) -> SyntaxVisitorContinueKind {
            if let expression = node.expressions.first?.expression.as(DeclReferenceExprSyntax.self),
               expression.baseName.text == member {
                violations.append(.init(
                    detail: "String interpolation of a member token is unavailable",
                    source: Syntax(node)
                ))
            }
            return .visitChildren
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            guard node.baseName.text == member else { return .visitChildren }
            if closureDepth > 1 {
                violations.append(.init(
                    detail: "Capturing a member token in a nested closure is unavailable",
                    source: Syntax(node)
                ))
            } else if !permittedMemberOffsets.contains(node.positionAfterSkippingLeadingTrivia.utf8Offset) {
                violations.append(.init(
                    detail: "Member identity observation or cross-collection use is unavailable",
                    source: Syntax(node)
                ))
            }
            return .visitChildren
        }
    }

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
