import SwiftSyntax
import SwiftParser
import SwiftBasicFormat

extension SpecParser {
    static func parseDictionaryVarDecl(
        _ binding: PatternBindingSyntax,
        into result: inout ParsedSpecComponents
    ) -> Bool {
        guard let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
              let specialization = call.calledExpression.as(GenericSpecializationExprSyntax.self),
              specialization.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == "DictionaryVar"
        else { return false }

        let typeArguments = Array(specialization.genericArgumentClause.arguments)
        let arguments = Array(call.arguments)
        guard typeArguments.count == 2,
              let nameLiteral = arguments.first?.expression.as(StringLiteralExprSyntax.self),
              let scope = dictionaryScope(in: arguments),
              let initial = dictionaryDefaultValue(
                for: typeArguments[1].argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
              )
        else {
            result.diagnostics.append(.init(
                message: "DictionaryVar requires key and value types, a string literal name, an integer literal scope, "
                    + "and a supported value default.",
                source: call.description
            ))
            return true
        }

        let name = nameLiteral.segments.description.replacingOccurrences(of: "\"", with: "")
        let elementType = typeArguments[0].argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let valueType = typeArguments[1].argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard scope > 0 else {
            result.variables.append((name, .function([:]), nil, valueType))
            return true
        }

        let declaration = SymmetricCollectionDecl(name: name, verificationScope: scope, initial: initial)
        result.symmetricCollections.append(.init(
            name: name,
            elementType: elementType,
            valueType: valueType,
            verificationScope: scope,
            source: call.description,
            declaration: declaration
        ))
        result.variables.append((name, declaration.variable.initial, nil, valueType))
        return true
    }

    private static func dictionaryScope(in arguments: [LabeledExprSyntax]) -> Int? {
        guard let expression = arguments.first(where: { $0.label?.text == "scope" })?.expression else {
            return 4
        }
        guard let literal = expression.as(IntegerLiteralExprSyntax.self) else { return nil }
        return Int(literal.literal.text)
    }

    private static func dictionaryDefaultValue(for valueType: String) -> TLAValue? {
        switch valueType {
        case "Int", "TLAValue":
            return .int(0)
        case "Bool":
            return .bool(false)
        case "String":
            return .string("")
        default:
            if valueType.hasPrefix("Function<") { return .function([:]) }
            if valueType.hasPrefix("Record<") { return .record([:]) }
            if valueType.hasPrefix("SetExpr<") { return .set([]) }
            if let finiteDefault = _enumDomains[valueType]?.first { return finiteDefault }
            return nil
        }
    }

    static func collectSymmetricCollectionTypes(
        in closure: ClosureExprSyntax
    ) -> [String: (element: String, value: String)] {
        var types: [String: (element: String, value: String)] = [:]
        for statement in closure.statements {
            guard case .decl(let declaration) = statement.item,
                  let variable = declaration.as(VariableDeclSyntax.self)
            else { continue }
            for binding in variable.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                      let specialization = call.calledExpression.as(GenericSpecializationExprSyntax.self),
                      specialization.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == "SymmetricCollectionVar"
                else { continue }
                let arguments = Array(specialization.genericArgumentClause.arguments)
                guard arguments.count == 2 else { continue }
                types[name] = (
                    arguments[0].argument.description.trimmingCharacters(in: .whitespacesAndNewlines),
                    arguments[1].argument.description.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
        return types
    }

    static func parseSymmetricCollectionDecl(
        _ call: FunctionCallExprSyntax,
        into result: inout ParsedSpecComponents,
        collectionTypes: [String: (element: String, value: String)]
    ) {
        let arguments = Array(call.arguments)
        guard let collectionName = arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let types = collectionTypes[collectionName],
              let scopeArgument = arguments.first(where: { $0.label?.text == "verificationScope" })?.expression,
              let scopeLiteral = scopeArgument.as(IntegerLiteralExprSyntax.self),
              let scope = Int(scopeLiteral.literal.text),
              let initialExpression = arguments.first(where: { $0.label?.text == "initial" })?.expression,
              let initial = parseLiteralValue(initialExpression)
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
            elementType: types.element,
            valueType: types.value,
            verificationScope: scope,
            source: call.description,
            declaration: declaration
        ))
        result.variables.append((collectionName, declaration.variable.initial, nil, nil))
    }

    static func parseCollectionAction(
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
        let member = FreshVarName.fresh()
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
            body: .existsAction(member, .domain(.variable(collectionName)), actionBody),
            runtimeBranches: runtimeBranches(
                in: closure,
                collection: collectionName,
                member: memberName,
                runtimeVariables: Set(result.variables.map(\.name))
            ),
            source: call.description
        ))
        result.actions.append(.init(name: actionName, body: .existsAction(
            member,
            .domain(.variable(collectionName)),
            actionBody
        )))
    }

    static func collectionActionMemberName(in closure: ClosureExprSyntax) -> String? {
        guard let parameters = closure.signature?.parameterClause else { return nil }
        switch parameters {
        case .simpleInput(let list):
            return list.first?.name.text
        case .parameterClause(let clause):
            guard let parameter = clause.parameters.first else { return nil }
            return parameter.secondName?.text ?? parameter.firstName.text
        }
    }

    static func validateMemberUses(
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

    static func identityDiagnostic(
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

    static func parseCollectionActionBody(
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

    static func parseCollectionActionExpression(
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
        if let sequence = expression.as(SequenceExprSyntax.self),
           let split = collectionActionSequenceSplit(Array(sequence.elements)) {
            let left = parseCollectionActionExpression(
                split.left,
                collection: collection,
                member: member,
                binding: binding
            )
            let right = parseCollectionActionExpression(
                split.right,
                collection: collection,
                member: member,
                binding: binding
            )
            guard let left, let right else { return nil }
            return split.operatorText == "&&" ? .and(left, right) : .or(left, right)
        }
        if let update = collectionUpdate(expression, collection: collection, member: member) {
            let rewritten = CollectionReadRewriter(
                collection: collection,
                member: member,
                replacement: binding
            ).visit(update.expression)
            guard let value = decodeStateExpr(rewritten) else { return nil }
            return .assign(collection, .except(.variable(collection), .variable(binding), value))
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let op = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text,
           let left = parseCollectionActionExpression(infix.leftOperand, collection: collection, member: member, binding: binding),
           let right = parseCollectionActionExpression(infix.rightOperand, collection: collection, member: member, binding: binding) {
            if op == "&&" { return .and(left, right) }
            if op == "||" { return .or(left, right) }
        }
        let rewritten = CollectionReadRewriter(
            collection: collection,
            member: member,
            replacement: binding
        ).visit(expression)
        return decodeStateExpr(rewritten).map(ActionExpr.guard_)
    }

    static func collectionActionSequenceSplit(
        _ elements: [ExprSyntax]
    ) -> (left: ExprSyntax, operatorText: String, right: ExprSyntax)? {
        guard elements.count >= 3, elements.count % 2 == 1 else { return nil }
        let operators = stride(from: 1, to: elements.count, by: 2)
        let splitIndex = operators.first {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "||"
        } ?? operators.first {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "&&"
        }
        guard let splitIndex,
              let operatorText = elements[splitIndex].as(BinaryOperatorExprSyntax.self)?.operator.text,
              let left = parseExpression(elements[0..<splitIndex]),
              let right = parseExpression(elements[(splitIndex + 1)..<elements.count])
        else { return nil }
        return (left, operatorText, right)
    }

    static func parseExpression(_ elements: ArraySlice<ExprSyntax>) -> ExprSyntax? {
        let source = elements.map(\.description).joined()
        return SwiftParser.Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self)
    }

    static func collectionUpdate(
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

    static func runtimeBranches(
        in closure: ClosureExprSyntax,
        collection: String,
        member: String,
        runtimeVariables: Set<String>
    ) -> [ParsedCollectionAction.RuntimeBranch] {
        let expressions = closure.statements.compactMap { statement -> ExprSyntax? in
            guard case .expr(let expression) = statement.item else { return nil }
            return expression
        }
        guard let first = expressions.first else { return [] }
        return expressions.dropFirst().reduce(
            runtimeBranches(
                for: first,
                collection: collection,
                member: member,
                runtimeVariables: runtimeVariables
            )
        ) { partial, expression in
            combineRuntimeBranches(
                partial,
                runtimeBranches(
                    for: expression,
                    collection: collection,
                    member: member,
                    runtimeVariables: runtimeVariables
                )
            )
        }
    }

    static func runtimeBranches(
        for expression: ExprSyntax,
        collection: String,
        member: String,
        runtimeVariables: Set<String>
    ) -> [ParsedCollectionAction.RuntimeBranch] {
        if let tuple = expression.as(TupleExprSyntax.self),
           tuple.elements.count == 1,
           let nested = tuple.elements.first?.expression {
            return runtimeBranches(
                for: nested,
                collection: collection,
                member: member,
                runtimeVariables: runtimeVariables
            )
        }
        if let sequence = expression.as(SequenceExprSyntax.self),
           let split = collectionActionSequenceSplit(Array(sequence.elements)) {
            let left = runtimeBranches(
                for: split.left,
                collection: collection,
                member: member,
                runtimeVariables: runtimeVariables
            )
            let right = runtimeBranches(
                for: split.right,
                collection: collection,
                member: member,
                runtimeVariables: runtimeVariables
            )
            return split.operatorText == "&&"
                ? combineRuntimeBranches(left, right)
                : left + right
        }
        if let update = collectionUpdate(expression, collection: collection, member: member) {
            let runtimeUpdate = CollectionReadRewriter(
                collection: collection,
                member: member,
                replacement: "entry.value",
                asStateExpression: false,
                runtimeVariables: runtimeVariables
            ).visit(update.expression).formatted().description
            return [.init(guardExpressions: [], updateExpression: runtimeUpdate)]
        }
        let runtimeGuard = CollectionRuntimeGuardRewriter(
            collection: collection,
            member: member,
            runtimeVariables: runtimeVariables
        ).visit(expression).formatted().description
        return [.init(guardExpressions: [runtimeGuard], updateExpression: nil)]
    }

    static func combineRuntimeBranches(
        _ left: [ParsedCollectionAction.RuntimeBranch],
        _ right: [ParsedCollectionAction.RuntimeBranch]
    ) -> [ParsedCollectionAction.RuntimeBranch] {
        left.flatMap { lhs in
            right.compactMap { rhs in
                guard lhs.updateExpression == nil || rhs.updateExpression == nil else { return nil }
                return .init(
                    guardExpressions: lhs.guardExpressions + rhs.guardExpressions,
                    updateExpression: lhs.updateExpression ?? rhs.updateExpression
                )
            }
        }
    }

    private final class CollectionRuntimeGuardRewriter: SyntaxRewriter {
        let collection: String
        let member: String
        let runtimeVariables: Set<String>

        init(collection: String, member: String, runtimeVariables: Set<String>) {
            self.collection = collection
            self.member = member
            self.runtimeVariables = runtimeVariables
        }

        override func visit(_ node: SubscriptCallExprSyntax) -> ExprSyntax {
            guard node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == collection,
                  node.arguments.count == 1,
                  node.arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == member
            else { return super.visit(node) }
            return ExprSyntax(stringLiteral: "(entry.value)")
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
            guard runtimeVariables.contains(node.baseName.text) else { return super.visit(node) }
            return ExprSyntax(stringLiteral: "_state.\(node.baseName.text)")
        }
    }

    private final class CollectionReadRewriter: SyntaxRewriter {
        let collection: String
        let member: String
        let replacement: String
        let asStateExpression: Bool
        let runtimeVariables: Set<String>

        init(
            collection: String,
            member: String,
            replacement: String,
            asStateExpression: Bool = true,
            runtimeVariables: Set<String> = []
        ) {
            self.collection = collection
            self.member = member
            self.replacement = replacement
            self.asStateExpression = asStateExpression
            self.runtimeVariables = runtimeVariables
        }

        override func visit(_ node: SubscriptCallExprSyntax) -> ExprSyntax {
            guard node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == collection,
                  node.arguments.count == 1,
                  node.arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text == member
            else { return super.visit(node) }
            if asStateExpression {
                return ExprSyntax(stringLiteral: "\(collection).applying(\(replacement))")
            }
            return ExprSyntax(stringLiteral: "(\(replacement)) ")
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
            guard !asStateExpression, runtimeVariables.contains(node.baseName.text)
            else { return super.visit(node) }
            return ExprSyntax(stringLiteral: "_state.\(node.baseName.text)")
        }
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

    static func parseLiteralValue(_ expression: ExprSyntax) -> TLAValue? {
        if let integer = expression.as(IntegerLiteralExprSyntax.self) {
            return Int(integer.literal.text).map(TLAValue.int)
        }
        if let boolean = expression.as(BooleanLiteralExprSyntax.self) {
            return .bool(boolean.literal.text == "true")
        }
        if let string = expression.as(StringLiteralExprSyntax.self) {
            return .string(string.segments.description.replacingOccurrences(of: "\"", with: ""))
        }
        return nil
    }

    static func extractStringArg(
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

    static func parseVariableDecl(_ call: FunctionCallExprSyntax, into result: inout ParsedSpecComponents) {
        let args = Array(call.arguments)
        guard let firstName = args.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text
            ?? args.first?.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
        else { return }

        // Variable(name, in: set)
        if args.count >= 2 {
            let label = args[1].label?.text
            if label == "in" {
                if let setExpr = decodeStateExpr(args[1].expression) {
                    result.variables.append((firstName, .set([]), setExpr, nil))
                    return
                }
            }
        }

        // Variable(name, value)
        if args.count >= 2 {
            let valExpr = args[1].expression
            if let intVal = valExpr.as(IntegerLiteralExprSyntax.self) {
                result.variables.append((firstName, .int(Int(intVal.literal.text) ?? 0), nil, nil))
                return
            }
            if let boolVal = valExpr.as(BooleanLiteralExprSyntax.self) {
                result.variables.append((firstName, .bool(boolVal.literal.text == "true"), nil, nil))
                return
            }
            if let stringVal = valExpr.as(StringLiteralExprSyntax.self) {
                result.variables.append((firstName, .string(stringVal.segments.description), nil, nil))
                return
            }
            // TLAValue.set([]), TLAValue.tuple([]), etc.
            if let fc = valExpr.as(FunctionCallExprSyntax.self),
               let memberAccess = fc.calledExpression.as(MemberAccessExprSyntax.self),
               let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
               base.baseName.text == "TLAValue" {
                let name = memberAccess.declName.baseName.text
                if let parsed = parseTLAValueConstructor(name: name, call: fc) {
                    result.variables.append((firstName, parsed, nil, nil))
                    return
                }
            }
        }

        // Variable(name, initializerExpr) — fallback
        if args.count >= 2 {
            let initial: TLAValue = .int(0)
            result.variables.append((firstName, initial, nil, nil))
        }
    }

    static func parseTLAValueConstructor(name: String, call: FunctionCallExprSyntax) -> TLAValue? {
        switch name {
        case "set":     return .set([])
        case "tuple":   return .tuple([])
        case "record":  return .record([:])
        case "function": return .function([:])
        default:        return nil
        }
    }

    static func parseConstantDecl(_ call: FunctionCallExprSyntax, into result: inout ParsedSpecComponents) {
        let args = Array(call.arguments)
        guard args.count >= 2,
              let name = extractStringArg(call, index: 0)
        else { return }
        if let intVal = args[1].expression.as(IntegerLiteralExprSyntax.self) {
            result.constants[name] = .int(Int(intVal.literal.text) ?? 0)
        } else if let boolVal = args[1].expression.as(BooleanLiteralExprSyntax.self) {
            result.constants[name] = .bool(boolVal.literal.text == "true")
        } else if args[1].expression.as(StringLiteralExprSyntax.self) != nil {
            result.constants[name] = .string(extractStringArg(call, index: 1) ?? "")
        }
    }

    /// Parse `NamedValue("poweredOn", 5)` → register in localConstants
    static func parseNamedValueConstant(_ call: FunctionCallExprSyntax, name: String, into result: inout ParsedSpecComponents) -> Bool {
        let args = Array(call.arguments)
        guard args.count >= 2 else { return false }
        if let intVal = args[1].expression.as(IntegerLiteralExprSyntax.self), let v = Int(intVal.literal.text) {
            result.localConstants[name] = .int(v); return true
        }
        if let boolVal = args[1].expression.as(BooleanLiteralExprSyntax.self) {
            result.localConstants[name] = .bool(boolVal.literal.text == "true"); return true
        }
        return false
    }

}
