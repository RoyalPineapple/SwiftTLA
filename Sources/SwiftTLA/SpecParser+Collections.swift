import SwiftSyntax

extension ParserSession {
    struct SymmetricCollectionSourceTypes {
        let element: TypeSyntax
        let value: TypeSyntax
    }

    func collectSymmetricCollectionTypes(
        in closure: ClosureExprSyntax
    ) -> [String: SymmetricCollectionSourceTypes] {
        var types: [String: SymmetricCollectionSourceTypes] = [:]
        for statement in closure.statements {
            guard case .decl(let declaration) = statement.item,
                  let variable = declaration.as(VariableDeclSyntax.self)
            else { continue }
            for binding in variable.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                  let specialization = call.calledExpression.as(GenericSpecializationExprSyntax.self),
                  terminalTypeName(in: specialization.expression) == "SymmetricCollectionVar"
                else { continue }
                let arguments = Array(specialization.genericArgumentClause.arguments)
                guard arguments.count == 2 else { continue }
                types[name] = .init(
                    element: arguments[0].argument,
                    value: arguments[1].argument
                )
            }
        }
        return types
    }

    func parseSymmetricCollectionDecl(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents,
        collectionTypes: [String: SymmetricCollectionSourceTypes]
    ) {
        let arguments = Array(call.arguments)
        guard let collectionName = arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let types = collectionTypes[collectionName],
              let scopeArgument = arguments.first(where: { $0.label?.text == "verificationScope" })?.expression,
              let scopeLiteral = scopeArgument.as(IntegerLiteralExprSyntax.self),
              let scope = Int(scopeLiteral.literal.text),
              let initialExpression = arguments.first(where: { $0.label?.text == "initial" })?.expression,
              let initial = parseLiteralValue(initialExpression),
              let elementType = sourceTypeSpelling(types.element),
              let valueType = sourceTypeSpelling(types.value)
        else {
            result.diagnostics.append(.init(
                message: "Symmetric collections require SymmetricCollectionVar<Element, Value>, "
                    + "a positive integer literal scope, and a literal uniform initial value.",
                source: call.description
            ))
            return
        }

        let declaration = SymmetricCollectionDecl(name: collectionName, verificationScope: scope, initial: initial)
        result.symmetricCollections.append(.init(
            name: collectionName,
            elementType: elementType,
            valueType: valueType,
            verificationScope: scope,
            source: call.description,
            declaration: declaration
        ))
        result.variables.append(.init(formal: declaration.variable))
    }

    func parseCollectionAction(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents
    ) {
        let arguments = Array(call.arguments)
        guard let actionName = extractStringArg(call, index: 0),
              let collectionName = arguments.first(where: { $0.label?.text == "on" })?.expression
                .as(DeclReferenceExprSyntax.self)?.baseName.text,
              let closure = call.trailingClosure
        else { return }

        guard let memberName = collectionActionMemberName(in: closure) else {
            result.diagnostics.append(.init(
                message: "Collection action '\(actionName)' requires one named opaque member parameter.",
                source: closure.description
            ))
            return
        }
        let member = memberName
        let diagnosticCount = result.diagnostics.count
        validateMemberUses(
            memberName,
            in: closure,
            owning: collectionName,
            action: actionName,
            into: &result
        )
        guard let actionBody = parseCollectionActionBody(
            closure,
            collection: collectionName,
            member: memberName,
            binding: member
        ) else {
            if result.diagnostics.count == diagnosticCount {
                result.diagnostics.append(.init(
                    message: "Collection action '\(actionName)' contains an unsupported action expression.",
                    source: closure.description
                ))
            }
            return
        }
        result.collectionActions.append(.init(
            name: actionName,
            collectionName: collectionName,
            source: call.description
        ))
        result.actions.append(.init(name: actionName, body: .existsAction(
            member,
            .domain(.variable(collectionName)),
            actionBody
        )))
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
        into result: inout ParsedSpecComponents
    ) {
        let validator = CollectionMemberUseValidator(member: member, collection: collection)
        validator.walk(Syntax(closure))
        for violation in validator.violations {
            result.diagnostics.append(identityDiagnostic(
                collection: collection, action: action, source: violation.source,
                detail: violation.detail
            ))
        }
    }

    func identityDiagnostic(
        collection: String,
        action: String,
        source: String,
        detail: String
    ) -> SymmetricCollectionParseDiagnostic {
        .init(
            message: "\(detail) for symmetric collection '\(collection)' in action '\(action)': "
                + "member identity is opaque and may only select or update its owning collection. "
                + "Model the distinction as member state or use a non-symmetric collection.",
            source: source
        )
    }

    func parseCollectionActionBody(
        _ closure: ClosureExprSyntax,
        collection: String,
        member: String,
        binding: String
    ) -> ActionExpr? {
        let actions = closure.statements.compactMap { statement -> ActionExpr? in
            guard case .expr(let expression) = statement.item else { return nil }
            return parseCollectionActionExpression(
                expression,
                collection: collection,
                member: member,
                binding: binding
            )
        }
        guard !actions.isEmpty else { return nil }
        return actions.dropFirst().reduce(actions[0]) { .and($0, $1) }
    }

    func parseCollectionActionExpression(
        _ expression: ExprSyntax,
        collection: String,
        member: String,
        binding: String
    ) -> ActionExpr? {
        let unwrapped = unwrapSingleElementTuple(expression)
        if unwrapped != expression {
            return parseCollectionActionExpression(
                unwrapped,
                collection: collection,
                member: member,
                binding: binding
            )
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            return parseCollectionActionSequence(
                Array(sequence.elements),
                collection: collection,
                member: member,
                binding: binding
            )
        }
        if let update = collectionUpdate(expression, collection: collection, member: member) {
            guard let value = decodeStateExpr(update.expression) else { return nil }
            return .assign(collection, .except(.variable(collection), .variable(binding), value))
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let op = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text,
           let left = parseCollectionActionExpression(infix.leftOperand, collection: collection, member: member, binding: binding),
           let right = parseCollectionActionExpression(infix.rightOperand, collection: collection, member: member, binding: binding) {
            if op == "&&" { return .and(left, right) }
            if op == "||" { return .or(left, right) }
        }
        return decodeStateExpr(expression).map(ActionExpr.guard_)
    }

    func parseCollectionActionSequence(
        _ elements: [ExprSyntax],
        collection: String,
        member: String,
        binding: String
    ) -> ActionExpr? {
        guard !elements.isEmpty, elements.count % 2 == 1 else { return nil }
        if elements.count == 1 {
            return parseCollectionActionExpression(
                elements[0],
                collection: collection,
                member: member,
                binding: binding
            )
        }
        let operators = stride(from: 1, to: elements.count, by: 2)
        let splitIndex = operators.first {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "||"
        } ?? operators.first {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "&&"
        }
        guard let splitIndex else {
            return decodeInfixExpr(elements).map(ActionExpr.guard_)
        }
        guard let operation = elements[splitIndex].as(BinaryOperatorExprSyntax.self)?.operator.text,
              let left = parseCollectionActionSequence(
                  Array(elements[..<splitIndex]),
                  collection: collection,
                  member: member,
                  binding: binding
              ),
              let right = parseCollectionActionSequence(
                  Array(elements[(splitIndex + 1)...]),
                  collection: collection,
                  member: member,
                  binding: binding
              )
        else { return nil }
        return operation == "&&" ? .and(left, right) : .or(left, right)
    }

    func collectionUpdate(
        _ expression: ExprSyntax,
        collection: String,
        member: String
    ) -> LabeledExprSyntax? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let access = call.calledExpression.as(MemberAccessExprSyntax.self),
              access.declName.baseName.text == "update",
              access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == collection,
              let selector = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
              selector.baseName.text == member
        else { return nil }
        return call.arguments.first(where: { $0.label?.text == "to" })
    }

    private final class CollectionMemberUseValidator: SyntaxVisitor {
        struct Violation {
            let detail: String
            let source: String
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
                    source: node.description
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
                        source: node.description
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
                    source: node.description
                ))
            }
            return .visitChildren
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            guard node.baseName.text == member else { return .visitChildren }
            if closureDepth > 1 {
                violations.append(.init(
                    detail: "Capturing a member token in a nested closure is unavailable",
                    source: node.description
                ))
            } else if !permittedMemberOffsets.contains(node.positionAfterSkippingLeadingTrivia.utf8Offset) {
                violations.append(.init(
                    detail: "Member identity observation or cross-collection use is unavailable",
                    source: node.description
                ))
            }
            return .visitChildren
        }
    }

    func parseLiteralValue(_ expression: ExprSyntax) -> TLAValue? {
        if let integer = expression.as(IntegerLiteralExprSyntax.self) {
            return Int(integer.literal.text).map(TLAValue.int)
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

        // Build string from segments, substituting loop variable
        var result = ""
        for segment in stringLit.segments {
            if let text = segment.as(StringSegmentSyntax.self)?.content.text {
                result += text
            } else if let expr = segment.as(ExpressionSegmentSyntax.self),
                      let loopVar, let loopValue,
                      let expr0 = expr.expressions.first?.expression,
                      let declRef = expr0.as(DeclReferenceExprSyntax.self),
                      declRef.baseName.text == loopVar {
                result += "\(loopValue)"
            }
        }
        return result
    }

    func parseVariableDecl(_ call: FunctionCallExprSyntax, into result: inout ParsedSpecComponents) {
        let args = Array(call.arguments)
        if args.first?.label?.text == "from",
           args.count >= 2,
           let name = parsedVariableName(args[0].expression),
           let range = decodeStateExpr(args[1].expression) {
            result.variables.append(.init(name: name, initial: .int(0), lazySet: range))
            return
        }
        if args.first?.label?.text == "computed",
           let name = parsedVariableName(args[0].expression),
           let expression = call.trailingClosure?.statements.first.flatMap({ statement -> ExprSyntax? in
               guard case .expr(let expression) = statement.item else { return nil }
               return expression
           }),
           let initial = decodeStateExpr(expression) {
            result.variables.append(.init(name: name, initial: .int(0), initExpr: initial))
            return
        }
        guard let firstName = args.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text
            ?? args.first?.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
        else { return }

        // Variable(name, in: set)
        if args.count >= 2 {
            let label = args[1].label?.text
            if label == "in" {
                if let setExpr = decodeStateExpr(args[1].expression) {
                    result.variables.append(.init(name: firstName, initial: .int(0), initialSet: setExpr))
                    return
                }
            }
        }

        // Variable(name, value)
        if args.count >= 2 {
            let valExpr = args[1].expression
            if let intVal = valExpr.as(IntegerLiteralExprSyntax.self) {
                result.variables.append(.init(name: firstName, initial: .int(Int(intVal.literal.text) ?? 0)))
                return
            }
            if let boolVal = valExpr.as(BooleanLiteralExprSyntax.self) {
                result.variables.append(.init(name: firstName, initial: .bool(boolVal.literal.text == "true")))
                return
            }
            if let stringVal = valExpr.as(StringLiteralExprSyntax.self) {
                guard let value = stringVal.representedLiteralValue else { return }
                result.variables.append(.init(name: firstName, initial: .string(value)))
                return
            }
            // TLAValue.set([]), TLAValue.tuple([]), etc.
            if let fc = valExpr.as(FunctionCallExprSyntax.self),
               let memberAccess = fc.calledExpression.as(MemberAccessExprSyntax.self),
               let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
               base.baseName.text == "TLAValue" {
                let name = memberAccess.declName.baseName.text
                if let parsed = parseTLAValueConstructor(name: name, call: fc) {
                    result.variables.append(.init(name: firstName, initial: parsed))
                    return
                }
            }
        }

        // Variable(name, initializerExpr) — fallback
        if args.count >= 2 {
            let initial: TLAValue = .int(0)
            result.variables.append(.init(name: firstName, initial: initial))
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
        switch name {
        case "set":     return .set([])
        case "tuple":   return .tuple([])
        case "record":  return .record([:])
        case "function": return .function([:])
        default:        return nil
        }
    }

    func parseConstantDecl(_ call: FunctionCallExprSyntax, into result: inout ParsedSpecComponents) {
        let args = Array(call.arguments)
        guard args.count >= 2,
              let name = extractStringArg(call, index: 0)
        else {
            result.diagnostics.append(.init(
                message: "Constant requires a literal name and a static TLA+ value.",
                source: call.description,
                expected: "Constant(\"Name\", value)",
                nextSafeAction: "Use a literal constant name and a static typed value."
            ))
            return
        }
        guard let expression = decodeTypedFacadeValue(args[1].expression, scope: .empty),
              let value = staticConstantValue(expression)
        else {
            result.diagnostics.append(.init(
                message: "Constant '\(name)' must be static; dynamic formal expressions are not constant values.",
                source: args[1].expression.description,
                expected: "a literal value or SetExpr<Element>(...) with static members",
                nextSafeAction: "Use a closed typed value such as SetExpr<Element>(.first, .second)."
            ))
            return
        }
        result.constants.append(ConstantDecl(name, value))
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
