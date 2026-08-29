import SwiftSyntax
import SwiftParser
import SwiftBasicFormat
import Foundation

/// Enumeration facts used while the macro front end decodes one model.
package struct ParserEnumDefinition: Sendable {
    let typeName: String
    let cases: TLARecord
    let finiteValues: [TLAValue]

    package init(typeName: String, cases: TLARecord, finiteValues: [TLAValue]? = nil) {
        self.typeName = typeName
        self.cases = cases
        self.finiteValues = finiteValues ?? cases.fields.map(\.value)
    }

    func value(named name: String) -> TLAValue? {
        cases.value(named: name)
    }
}

final class ParserSession {
    enum FormalModuleProvider: Equatable {
        case folds
        case functions
        case keyValueStoreUtil
        case clientCentric
        case zeroBasedSequences

        init?(sourceType: String) {
            switch sourceType {
            case "Folds": self = .folds
            case "FunctionsModule": self = .functions
            case "KeyValueStoreUtil": self = .keyValueStoreUtil
            case "ClientCentric": self = .clientCentric
            case "ZSequences": self = .zeroBasedSequences
            default: return nil
            }
        }

        var module: TLASpec {
            switch self {
            case .folds: Folds.module
            case .functions: FunctionsModule.module
            case .keyValueStoreUtil: KeyValueStoreUtil.module
            case .clientCentric: ClientCentric.module
            case .zeroBasedSequences: ZSequences.module
            }
        }
    }

    indirect enum TypedFacadeValueShape: Sendable {
        case enumeration(String)
        case function(TypedFacadeValueShape)
        case tuple
        case zeroBasedSequence
        case set(TypedFacadeValueShape)

        var selectedElement: TypedFacadeValueShape? {
            guard case .set(let element) = self else { return nil }
            return element
        }

        var enumerationType: String? {
            guard case .enumeration(let type) = self else { return nil }
            return type
        }
    }

    /// The lexical bindings visible while decoding one typed facade expression.
    struct TypedFacadeScope: Sendable {
        private enum Meaning: Sendable {
            case value(StateExpr)
            case recursiveOperator(String)
        }

        private struct Binding: Sendable {
            let sourceName: String
            let meaning: Meaning
            let shape: TypedFacadeValueShape?
        }

        static let empty = Self(bindings: [])

        private let bindings: [Binding]

        var isEmpty: Bool { bindings.isEmpty }

        private init(bindings: [Binding]) {
            self.bindings = bindings
        }

        func value(for reference: DeclReferenceExprSyntax) -> StateExpr? {
            guard let binding = bindings.last(where: { $0.sourceName == reference.baseName.text }),
                  case .value(let value) = binding.meaning
            else { return nil }
            return value
        }

        func recursiveOperator(for reference: DeclReferenceExprSyntax) -> String? {
            guard let binding = bindings.last(where: { $0.sourceName == reference.baseName.text }),
                  case .recursiveOperator(let name) = binding.meaning
            else { return nil }
            return name
        }

        func shape(for reference: DeclReferenceExprSyntax) -> TypedFacadeValueShape? {
            bindings.last(where: { $0.sourceName == reference.baseName.text })?.shape
        }

        func extending(
            _ bindings: [(sourceName: String, value: StateExpr)]
        ) -> Self {
            Self(bindings: self.bindings + bindings.map {
                Binding(sourceName: $0.sourceName, meaning: .value($0.value), shape: nil)
            })
        }

        func extending(
            sourceName: String,
            value: StateExpr,
            shape: TypedFacadeValueShape?
        ) -> Self {
            Self(bindings: bindings + [Binding(sourceName: sourceName, meaning: .value(value), shape: shape)])
        }

        func extending(recursiveOperator sourceName: String, named name: String) -> Self {
            Self(bindings: bindings + [Binding(
                sourceName: sourceName,
                meaning: .recursiveOperator(name),
                shape: nil
            )])
        }

    }

    func typedFacadeScope(
        _ scope: TypedFacadeScope,
        binding sourceName: String,
        to value: StateExpr,
        shape: TypedFacadeValueShape? = nil
    ) -> TypedFacadeScope {
        scope.extending(sourceName: sourceName, value: value, shape: shape)
    }

    func typedFacadeScope(
        _ scope: TypedFacadeScope,
        recursiveOperator sourceName: String,
        named name: String
    ) -> TypedFacadeScope {
        scope.extending(recursiveOperator: sourceName, named: name)
    }

    func typedFacadeScope(
        _ scope: TypedFacadeScope,
        bindings: [(sourceName: String, value: StateExpr)]
    ) -> TypedFacadeScope {
        bindings.reduce(scope) { scope, binding in
            typedFacadeScope(scope, binding: binding.sourceName, to: binding.value)
        }
    }

    /// Facts scoped to one syntax tree and macro expansion.
    var constants: [ConstantDecl] = []
    let enumDefinitions: [ParserEnumDefinition]
    /// Tuple-shaped algorithm state currently in scope. This lets the parser
    /// distinguish `sequence[index]` from a finite-function lookup without
    /// exposing raw type maps to authors.
    var algorithmTupleVariables: Set<String> = []
    /// Source bindings visible to the source expression currently being parsed.
    var sourceScope = TypedFacadeScope.empty
    var sourceActionBindings: [String: NamedAction] = [:]
    var algorithmParseFailure: String?
    var algorithmSourceDiagnostic: SourceParseDiagnostic?

    init(
        enumDefinitions: [ParserEnumDefinition] = []
    ) {
        self.enumDefinitions = enumDefinitions
    }

    func enumDefinition(named typeName: String) -> ParserEnumDefinition? {
        enumDefinitions.first { $0.typeName == typeName }
    }

    private func decodeLocalRecursion(
        _ expression: ExprSyntax,
        scope: TypedFacadeScope
    ) -> StateExpr? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "LetRec",
              let name = extractStringArg(call, index: 0), !name.isEmpty,
              let inputType = call.arguments.first(where: { $0.label?.text == "taking" })?.expression,
              isMetatype(inputType),
              let domainSyntax = call.arguments.first(where: { $0.label?.text == "over" })?.expression,
              let domain = decodeTypedFacadeValue(domainSyntax, scope: scope),
              let definition = call.arguments.dropFirst().first(where: { $0.label == nil })?.expression.as(ClosureExprSyntax.self),
              let body = call.arguments.first(where: { $0.label?.text == "in" })?.expression.as(ClosureExprSyntax.self),
              definition.statements.count == 1,
              body.statements.count == 1,
              case .expr(let definitionExpression) = definition.statements.first?.item,
              case .expr(let bodyExpression) = body.statements.first?.item
        else { return nil }

        let definitionParameters = closureParameterNames(in: definition)
        let bodyParameters = closureParameterNames(in: body)
        guard definitionParameters.count == 2, bodyParameters.count == 1 else { return nil }

        let inputName = definitionParameters[1]
        let definitionScope = typedFacadeScope(
            typedFacadeScope(
                scope,
                recursiveOperator: definitionParameters[0],
                named: name
            ),
            binding: inputName,
            to: .variable(inputName)
        )
        let bodyScope = typedFacadeScope(
            scope,
            recursiveOperator: bodyParameters[0],
            named: name
        )
        guard let decodedDefinition = decodeTypedFacadeValue(
            definitionExpression, scope: definitionScope
        ) else {
            algorithmParseFailure = algorithmParseFailure
                ?? "LetRec '\(name)' could not decode its bounded recursive body."
            return nil
        }
        guard let decodedBody = decodeTypedFacadeValue(bodyExpression, scope: bodyScope) else {
            algorithmParseFailure = algorithmParseFailure
                ?? "LetRec '\(name)' could not decode its result expression."
            return nil
        }
        return .letIn([LocalOperator(
            name,
            parameters: [inputName],
            domain: domain,
            body: decodedDefinition
        )], decodedBody)
    }

    func isMetatype(_ expression: ExprSyntax) -> Bool {
        guard let member = expression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "self",
              member.base != nil
        else { return false }
        return true
    }

    // MARK: - Compact expression decoder

    static func integerLiteralValue(_ literal: IntegerLiteralExprSyntax) -> Int? {
        Int(literal.literal.text.filter { $0 != "_" })
    }

    func decodeStateExpr(_ expression: ExprSyntax) -> StateExpr? {
        if let precedingMembers = decodePrecedingFormalMembers(expression) {
            return precedingMembers
        }
        if let controlLocation = decodeControlLocation(expression) {
            return controlLocation
        }
        if let finished = decodeFinishedControlLocation(expression) {
            return finished
        }
        if let sequences = decodeBoundedSequenceDomain(expression) {
            return sequences
        }
        if let filledSequence = decodeZeroBasedSequenceFill(expression) {
            return filledSequence
        }
        if let subsets = decodeBoundedSubsetDomain(expression) {
            return subsets
        }
        if let functions = decodeBoundedFunctionDomain(expression) {
            return functions
        }
        if let choice = decodeStaticFormalChoice(expression) {
            return choice
        }
        if let filtered = decodeBoundedFilteredDomain(expression) {
            return filtered
        }
        if let boundedQuantifier = decodeAlgorithmDomainQuantifier(expression) {
            return boundedQuantifier
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "If",
           let conditionSyntax = call.arguments.first?.expression,
           let thenSyntax = call.arguments.first(where: { $0.label?.text == "then" })?.expression,
           let elseSyntax = call.arguments.first(where: { $0.label?.text == "else" })?.expression,
           let condition = decodeStateExpr(conditionSyntax),
           let thenValue = decodeStateExpr(thenSyntax),
           let elseValue = decodeStateExpr(elseSyntax) {
            return .ifThenElse(condition, thenValue, elseValue)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
           name == "Exists" || name == "ForAll" || name == "All",
           let domainSyntax = call.arguments.first(where: { $0.label?.text == "in" })?.expression,
           let domain = decodeStateExpr(domainSyntax),
           let closure = call.trailingClosure,
           closure.statements.count == 1,
           case .expr(let bodySyntax) = closure.statements.first?.item,
           let parameter = closureParameterNames(in: closure).first,
           closureParameterNames(in: closure).count == 1,
           let predicate = decodeTypedFacadeValue(
               bodySyntax,
               scope: typedFacadeScope(.empty, binding: parameter, to: .variable(parameter))
           ) {
            return name == "Exists"
                ? .exists(domain, parameter, predicate)
                : .forAll(domain, parameter, predicate)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "IntRange",
           let lower = call.arguments.first?.expression,
           let upper = call.arguments.first(where: { $0.label?.text == "through" })?.expression,
           let lowerExpression = decodeStateExpr(lower),
           let upperExpression = decodeStateExpr(upper) {
            return .integerRange(lowerExpression, upperExpression)
        }
        // Empty typed formal values are ordinary initializers in the Swift
        // surface. Decode them directly so the source parser and runtime
        // builder agree on the same collection-shaped initial state.
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.arguments.isEmpty,
           call.trailingClosure == nil,
           let constructor = typedFacadeType(call.calledExpression) {
            if constructor.name == "SetExpr" { return .value(.set([])) }
            if constructor.name == "TupleExpr" { return .value(.tuple([])) }
        }
        if let typedFacadeExpr = decodeTypedFacadeExpr(expression, scope: .empty) {
            return typedFacadeExpr
        }
        if let subscriptCall = expression.as(SubscriptCallExprSyntax.self),
           subscriptCall.arguments.count == 1,
           let function = decodeStateExpr(subscriptCall.calledExpression),
           let argumentSyntax = subscriptCall.arguments.first?.expression,
           let argument = decodeStateExpr(argumentSyntax) {
            return .functionApply(function, argument)
        }
        if let intLit = expression.as(IntegerLiteralExprSyntax.self) {
            guard let value = Self.integerLiteralValue(intLit) else { return nil }
            return .value(.int(value))
        }
        if let boolLit = expression.as(BooleanLiteralExprSyntax.self) {
            return .value(.bool(boolLit.literal.text == "true"))
        }
        if let stringLit = expression.as(StringLiteralExprSyntax.self) {
            guard let value = stringLit.representedLiteralValue else { return nil }
            return .value(.string(value))
        }
        if let ref = expression.as(DeclReferenceExprSyntax.self) {
            let name = ref.baseName.text
            if let resolved = constants.value(named: name) { return .value(resolved) }
            return .variable(name)
        }
        if let enumCase = decodeEnumCase(expression) { return enumCase }
        if let member = expression.as(MemberAccessExprSyntax.self),
           let type = terminalTypeName(in: member.base),
           enumDefinition(named: type) != nil {
            return nil
        }
        if let memberAccess = expression.as(MemberAccessExprSyntax.self),
           let base = memberAccess.base,
           let selfExpr = decodeStateExpr(base) {
            let propName = memberAccess.declName.baseName.text
            switch propName {
            case "stateExpr": return selfExpr
            case "expr": return selfExpr
            case "cardinality": return .cardinality(selfExpr)
            case "flattened": return .unionAll(selfExpr)
            case "subsets": return .powerSet(selfExpr)
            case "domain": return .domain(selfExpr)
            case "count": return .tupleLength(selfExpr)
            case "head": return .tupleHead(selfExpr)
            case "tail": return .tupleTail(selfExpr)
            case "isEmpty": return .equal(.cardinality(selfExpr), .value(.int(0)))
            default: return .recordAccess(selfExpr, propName)
            }
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
            if let result = decodeCollectionPredicate(call) { return result }
            return decodeMethodCall(memberAccess, call)
        }
        if let tuple = expression.as(TupleExprSyntax.self),
           let single = tuple.elements.first?.expression {
            return decodeStateExpr(single)
        }
        if let seq = expression.as(SequenceExprSyntax.self) {
            return decodeInfixExpr(Array(seq.elements))
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let opText = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text,
           let lhs = decodeStateExpr(infix.leftOperand),
           let rhs = decodeStateExpr(infix.rightOperand) {
            return applyInfixOp(opText, lhs, rhs)
        }
        if let prefix = expression.as(PrefixOperatorExprSyntax.self) {
            let operand = decodeStateExpr(prefix.expression)
            if prefix.operator.text == "!", let operand { return .not(operand) }
            if prefix.operator.text == "-", let operand {
                // Keep a spelled negative literal identical to the runtime
                // builder's integer literal. This matters to the parser-tree
                // check even though both forms evaluate to the same value.
                if case .value(.int(let value)) = operand {
                    return .value(.int(-value))
                }
                return .negate(operand)
            }
        }
        return nil
    }

    /// Parses `Domain.all.members(before: process)` as the finite formal set
    /// of members declared before a process.
    private func decodePrecedingFormalMembers(
        _ expression: ExprSyntax,
        scope: TypedFacadeScope = .empty
    ) -> StateExpr? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "members",
              let base = call.calledExpression.as(MemberAccessExprSyntax.self)?.base,
              let domain = finiteAlgorithmDomain(base),
              let currentSyntax = call.arguments.first(where: { $0.label?.text == "before" })?.expression,
              let current = decodeTypedFacadeValue(currentSyntax, scope: scope)
        else { return nil }

        var result = StateExpr.setLiteral([])
        for (index, candidate) in domain.values.enumerated().reversed() {
            result = .ifThenElse(
                .equal(current, .value(candidate)),
                .setLiteral(domain.values.prefix(index).map(StateExpr.value)),
                result
            )
        }
        return result
    }

    /// Parses `At(Label.name, process)`, keeping the lowered `pc` variable
    /// private to the builder and macro implementation.
    private func decodeControlLocation(
        _ expression: ExprSyntax,
        scope: TypedFacadeScope = .empty
    ) -> StateExpr? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "At",
              call.arguments.count == 2,
              let label = registeredStringEnumCase(call.arguments.first?.expression),
              let processSyntax = call.arguments.dropFirst().first?.expression,
              let process = decodeTypedFacadeValue(processSyntax, scope: scope)
        else { return nil }
        return .equal(
            .functionApply(.programCounter, process),
            .controlLocation(.init(label))
        )
    }

    /// Lowers sequential and process-family completion predicates to the
    /// compiler-owned program counter.
    private func decodeFinishedControlLocation(
        _ expression: ExprSyntax,
        scope: TypedFacadeScope = .empty
    ) -> StateExpr? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Finished"
        else { return nil }

        if call.arguments.isEmpty {
            return .equal(.programCounter, .controlLocation(.done))
        }
        guard call.arguments.count == 1,
              let processSyntax = call.arguments.first?.expression,
              let process = decodeTypedFacadeValue(processSyntax, scope: scope)
        else { return nil }
        return .equal(
            .functionApply(.programCounter, process),
            .controlLocation(.done)
        )
    }

    func registeredStringEnumCase(_ expression: ExprSyntax?) -> String? {
        guard let access = expression?.as(MemberAccessExprSyntax.self),
              let type = access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
              case .string(let label) = enumDefinition(named: type)?.value(named: access.declName.baseName.text)
        else { return nil }
        return label
    }

    /// Expands the bounded `Sequences(of:lengths:)` spelling into the finite
    /// model-checking form of TLA+ `Seq(S)`.
    private func decodeBoundedSequenceDomain(_ expression: ExprSyntax) -> StateExpr? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              name == "Sequences" || name == "SortedSequences" || name == "ZeroBasedSequences",
              let memberSyntax = call.arguments.first(where: { $0.label?.text == "of" })?.expression,
              let lengthSyntax = call.arguments.first(where: { $0.label?.text == "lengths" })?.expression,
              let memberSet = decodeStateExpr(memberSyntax),
              case .setLiteral(let members) = memberSet,
              let lengths = parseIntegerClosedRange(lengthSyntax)
        else { return nil }
        let sequences = formalSequenceExpressions(members: members, lengths: lengths)
        switch name {
        case "SortedSequences":
            return .setLiteral(sequences.filter(formalIntegerSequenceIsSorted))
        case "ZeroBasedSequences":
            return .setLiteral(formalZeroBasedSequenceExpressions(members: members, lengths: lengths))
        default:
            return .setLiteral(sequences)
        }
    }

    /// Parses `ZeroBasedSequence<Element>.filled(length:with:)` into the
    /// TLA+ function literal used by the runtime builder.
    private func decodeZeroBasedSequenceFill(
        _ expression: ExprSyntax,
        scope: TypedFacadeScope = .empty
    ) -> StateExpr? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let access = call.calledExpression.as(MemberAccessExprSyntax.self),
              access.declName.baseName.text == "filled",
              let base = access.base,
              typedFacadeType(base)?.name == "ZeroBasedSequence",
              let lengthSyntax = call.arguments.first(where: { $0.label?.text == "length" })?.expression,
              let valueSyntax = call.arguments.first(where: { $0.label?.text == "with" })?.expression,
              let length = decodeTypedFacadeValue(lengthSyntax, scope: scope),
              let value = decodeTypedFacadeValue(valueSyntax, scope: scope)
        else { return nil }
        return .functionLiteral(
            .integerRange(.int(0), .subtract(length, .int(1))),
            "__zeroBasedSequenceIndex",
            value
        )
    }

    private func decodeBoundedSubsetDomain(
        _ expression: ExprSyntax,
        scope: TypedFacadeScope = .empty
    ) -> StateExpr? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              name == "Subsets" || name == "NonEmptySubsets"
        else { return nil }
        guard let valuesSyntax = call.arguments.first(where: { $0.label?.text == "of" })?.expression,
              let values = decodeTypedFacadeValue(valuesSyntax, scope: scope)
        else {
            algorithmParseFailure = "Subsets could not decode its finite formal set."
            return nil
        }
        let subsets = StateExpr.powerSet(values)
        guard name == "NonEmptySubsets" else { return subsets }
        return .setDifference(subsets, .setLiteral([.setLiteral([])]))
    }

    private func decodeBoundedFunctionDomain(
        _ expression: ExprSyntax,
        scope: TypedFacadeScope = .empty
    ) -> StateExpr? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Functions"
        else { return nil }
        guard let domainSyntax = call.arguments.first(where: { $0.label?.text == "from" })?.expression,
              let domain = finiteAlgorithmDomain(domainSyntax)
        else {
            algorithmParseFailure = "Functions requires a finite enum domain, for example Functions(from: Node.all, ...)."
            return nil
        }
        guard let rangeSyntax = call.arguments.first(where: { $0.label?.text == "to" })?.expression,
              let range = decodeTypedFacadeValue(rangeSyntax, scope: scope)
        else {
            algorithmParseFailure = "Functions could not decode its formal result domain."
            return nil
        }
        return .functionSet(.setLiteral(domain.values.map(StateExpr.value)), range)
    }

    private func decodeStaticFormalChoice(_ expression: ExprSyntax) -> StateExpr? {
        let canonicalBinding = "__tla_static_choice"
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Select",
              let candidatesSyntax = call.arguments.first(where: { $0.label?.text == "from" })?.expression,
              let candidates = decodeStateExpr(candidatesSyntax),
              let closure = call.trailingClosure
                ?? call.arguments.first(where: { $0.label?.text == "matching" })?.expression.as(ClosureExprSyntax.self),
              closureParameterNames(in: closure).count == 1,
              let parameter = closureParameterNames(in: closure).first,
              closure.statements.count == 1,
              case .expr(let predicateSyntax) = closure.statements.first?.item,
              let predicate = decodeTypedFacadeValue(
                predicateSyntax,
                scope: typedFacadeScope(.empty, binding: parameter, to: .variable(canonicalBinding))
              )
        else { return nil }
        return .choose(
            candidates,
            canonicalBinding,
            predicate
        )
    }

    private func decodeBoundedFilteredDomain(_ expression: ExprSyntax) -> StateExpr? {
        let canonicalBinding = "__pcal_filtered_value"
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Where"
        else { return nil }
        guard let candidatesSyntax = call.arguments.first?.expression,
              let candidates = decodeStateExpr(candidatesSyntax)
        else {
            algorithmParseFailure = algorithmParseFailure ?? "Where could not decode its candidate domain."
            return nil
        }
        guard let closure = call.trailingClosure,
              closureParameterNames(in: closure).count == 1,
              let parameter = closureParameterNames(in: closure).first,
              closure.statements.count == 1,
              case .expr(let predicateSyntax) = closure.statements.first?.item,
              let predicate = decodeTypedFacadeValue(
                predicateSyntax,
                scope: typedFacadeScope(.empty, binding: parameter, to: .variable(canonicalBinding))
              )
        else {
            algorithmParseFailure = "Where requires one parameter and one decodable predicate expression."
            return nil
        }
        return .setFilter(
            candidates,
            canonicalBinding,
            predicate
        )
    }

    func decodeAlgorithmDomainQuantifier(
        _ expression: ExprSyntax,
        scope: TypedFacadeScope = .empty
    ) -> StateExpr? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              name == "All",
              let domainSyntax = call.arguments.first?.expression,
              let domain = finiteAlgorithmDomain(domainSyntax),
              let closure = call.trailingClosure,
              closure.statements.count == 1,
              case .expr(let bodySyntax) = closure.statements.first?.item
        else { return nil }

        let parameters = closureParameterNames(in: closure)
        guard parameters.count <= 1 else { return nil }
        let sourceParameter = parameters.first ?? "$0"
        let parameter = parameters.first ?? generatedBinderName(
            line: UInt(closure.positionAfterSkippingLeadingTrivia.utf8Offset),
            column: 0
        )

        let binding = StateExpr.variable(parameter)
        let predicate: StateExpr?
        if let finished = bodySyntax.as(FunctionCallExprSyntax.self),
           finished.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Finished",
           let argument = finished.arguments.first?.expression,
           decodeTypedFacadeValue(
            argument,
            scope: typedFacadeScope(scope, binding: sourceParameter, to: binding)
           ) != nil {
            predicate = .equal(
                .functionApply(.programCounter, binding),
                .controlLocation(.done)
            )
        } else {
            predicate = decodeTypedFacadeValue(
                bodySyntax,
                scope: typedFacadeScope(scope, binding: sourceParameter, to: binding)
            )
        }
        guard let predicate else { return nil }
        let values = StateExpr.setLiteral(domain.values.map(StateExpr.value))
        return .forAll(values, parameter, predicate)
    }

    func decodeTypedFacadeExpr(
        _ expression: ExprSyntax,
        scope: TypedFacadeScope,
        expectedEnumType: String? = nil
    ) -> StateExpr? {
        if let call = expression.as(FunctionCallExprSyntax.self),
           let family = decodeProcessLocalFamily(call) {
            return family
        }
        if let quantifier = decodeAlgorithmDomainQuantifier(expression, scope: scope) {
            return quantifier
        }
        if let controlLocation = decodeControlLocation(expression, scope: scope) {
            return controlLocation
        }
        if let finished = decodeFinishedControlLocation(expression, scope: scope) {
            return finished
        }
        if let precedingMembers = decodePrecedingFormalMembers(expression, scope: scope) {
            return precedingMembers
        }
        if let subsets = decodeBoundedSubsetDomain(expression, scope: scope) {
            return subsets
        }
        if let functions = decodeBoundedFunctionDomain(expression, scope: scope) {
            return functions
        }
        // SwiftSyntax represents a parenthesized expression as a one-element
        // tuple. Keep decoding through the typed path so scoped facade values
        // such as `current.expr` retain their lexical scope.
        if let tuple = expression.as(TupleExprSyntax.self),
           tuple.elements.count == 1,
           let value = tuple.elements.first?.expression {
            return decodeTypedFacadeValue(value, scope: scope, expectedEnumType: expectedEnumType)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let reference = call.calledExpression.as(DeclReferenceExprSyntax.self),
           let operation = scope.recursiveOperator(for: reference) {
            let arguments = call.arguments.compactMap {
                decodeTypedFacadeValue($0.expression, scope: scope)
            }
            guard arguments.count == call.arguments.count else { return nil }
            return .recursiveCall(operation, arguments)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let reference = call.calledExpression.as(DeclReferenceExprSyntax.self),
           let function = scope.value(for: reference),
           call.arguments.count == 1,
           let argument = call.arguments.first.flatMap({
               decodeTypedFacadeValue($0.expression, scope: scope)
           }) {
            return .functionApply(function, argument)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.arguments.isEmpty,
           let access = call.calledExpression.as(MemberAccessExprSyntax.self),
           let baseSyntax = access.base,
           let base = decodeTypedFacadeValue(baseSyntax, scope: scope) {
            switch access.declName.baseName.text {
            case "first": return .tupleAccess(base, 1)
            case "second": return .tupleAccess(base, 2)
            default: break
            }
        }
        if let reference = expression.as(DeclReferenceExprSyntax.self),
           let value = scope.value(for: reference) {
            return value
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr",
           member.declName.baseName.text == "operatorApplication",
           call.arguments.count == 2,
           let operation = decodeFormalOperator(call.arguments[call.arguments.startIndex].expression),
           let argumentArray = call.arguments[call.arguments.index(after: call.arguments.startIndex)]
            .expression.as(ArrayExprSyntax.self) {
            let arguments = argumentArray.elements.compactMap {
                decodeFormalCallArgument(
                    $0.expression,
                    valueDecoder: { self.decodeTypedFacadeValue($0, scope: scope) }
                )
            }
            guard arguments.count == argumentArray.elements.count else { return nil }
            return .operatorApplication(operation, arguments)
        }
        // `Expr<T>` is a phantom type wrapper. Its one value argument is
        // already a formal expression, including the canonical formal
        // operator application spelling, so preserve that parser path rather
        // than attempting to infer it as a typed collection operation.
        if let call = expression.as(FunctionCallExprSyntax.self),
           let type = typedFacadeType(call.calledExpression),
           type.name == "Expr",
           call.arguments.count == 1,
           let value = call.arguments.first?.expression {
            return decodeTypedFacadeValue(value, scope: scope)
                ?? type.terminalArgumentName(at: 0).flatMap { typeName in
                    guard let member = value.as(MemberAccessExprSyntax.self),
                          member.base == nil,
                          let formalValue = enumDefinition(named: typeName)?
                            .value(named: member.declName.baseName.text)
                    else { return nil }
                    return .value(formalValue)
                }
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.base == nil,
           member.declName.baseName.text == "variable",
           let name = extractStringArg(call, index: 0) {
            return .variable(name)
        }
        if let localRecursion = decodeLocalRecursion(expression, scope: scope) {
            return localRecursion
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            return decodeInfixExpr(
                Array(sequence.elements),
                expectedEnumType: expectedEnumType,
                enumType: { self.typedFacadeValueShape($0, scope: scope)?.enumerationType }
            ) { expression, expectedEnumType in
                decodeTypedFacadeValue(
                    expression,
                    scope: scope,
                    expectedEnumType: expectedEnumType
                )
            }
        }
        // `IntRange` occurs inside scoped typed expressions as well as at the
        // top level.  Decode both bounds here so closure bindings such as a
        // local-recursion argument remain available to the upper bound.
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "IntRange",
           let lowerSyntax = call.arguments.first?.expression,
           let upperSyntax = call.arguments.first(where: { $0.label?.text == "through" })?.expression,
           let lower = decodeTypedFacadeValue(lowerSyntax, scope: scope),
           let upper = decodeTypedFacadeValue(upperSyntax, scope: scope) {
            return .integerRange(lower, upper)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
           name == "Exists" || name == "ForAll" || name == "All",
           let domainSyntax = call.arguments.first(where: { $0.label?.text == "in" })?.expression,
           let domain = decodeTypedFacadeValue(domainSyntax, scope: scope),
           let closure = call.trailingClosure,
           closure.statements.count == 1,
           case .expr(let predicateSyntax) = closure.statements.first?.item,
           let parameter = closureParameterNames(in: closure).first,
           closureParameterNames(in: closure).count == 1,
           let predicate = decodeTypedFacadeValue(
            predicateSyntax,
            scope: typedFacadeScope(
                scope,
                binding: parameter,
                to: .variable(parameter),
                shape: typedFacadeValueShape(domainSyntax, scope: scope)?.selectedElement
            )
           ) {
            return name == "Exists" ? .exists(domain, parameter, predicate) : .forAll(domain, parameter, predicate)
        }
        // `OneOf` is a type-level union: its alternatives retain their
        // underlying TLA+ value and therefore need no runtime wrapper.
        if let call = expression.as(FunctionCallExprSyntax.self),
           let access = call.calledExpression.as(MemberAccessExprSyntax.self),
           access.base?.as(DeclReferenceExprSyntax.self) != nil,
           ["first", "second"].contains(access.declName.baseName.text),
           call.arguments.count == 1,
           let value = call.arguments.first?.expression {
            return decodeTypedFacadeValue(value, scope: scope)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           (typedFacadeType(call.calledExpression)?.name == "FormalCall"
             || call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "FormalCall") {
            let argumentsSyntax = Array(call.arguments).filter { $0.label?.text != "as" }
            guard let name = argumentsSyntax.first?.expression.as(StringLiteralExprSyntax.self)?
                .representedLiteralValue
            else { return nil }
            let arguments = argumentsSyntax.dropFirst().compactMap {
                decodeTypedFacadeValue($0.expression, scope: scope)
            }
            guard arguments.count == argumentsSyntax.count - 1 else { return nil }
            return .operatorApplication(
                .reference(name, arity: arguments.count), arguments.map(FormalCallArgument.value)
            )
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Range",
           call.arguments.count == 1,
           let value = decodeTypedFacadeValue(call.arguments[call.arguments.startIndex].expression, scope: scope) {
            return .operatorApplication(.reference("Range", arity: 1), [.value(value)])
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "InjectiveSequence",
           let valuesSyntax = call.arguments.first(where: { $0.label?.text == "from" })?.expression,
           let values = decodeTypedFacadeValue(valuesSyntax, scope: scope) {
            return .choose(
                .functionSet(.integerRange(.int(1), .cardinality(values)), values),
                "f",
                .operatorApplication(.reference("IsInjective", arity: 1), [.value(.variable("f"))])
            )
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           (typedFacadeType(call.calledExpression)?.name == "ModuleCall"
             || call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "ModuleCall"),
           call.arguments.count >= 2 {
            let argumentsSyntax = Array(call.arguments).filter { $0.label?.text != "as" }
            guard argumentsSyntax.count >= 2 else { return nil }
            guard let instance = argumentsSyntax[0].expression.as(StringLiteralExprSyntax.self)?
                .representedLiteralValue,
                  let operation = argumentsSyntax[1].expression.as(StringLiteralExprSyntax.self)?
                    .representedLiteralValue
            else { return nil }
            let arguments = argumentsSyntax.dropFirst(2).compactMap {
                decodeTypedFacadeValue($0.expression, scope: scope)
            }
            guard arguments.count == argumentsSyntax.count - 2 else { return nil }
            return .operatorApplication(
                .reference("\(instance)!\(operation)", arity: arguments.count),
                arguments.map(FormalCallArgument.value)
            )
        }
        // `Pair(first:second:)` and `Pair.literal(_, _)` are normally
        // inferred from an enclosing `SetExpr<Pair<...>>`, so SwiftSyntax
        // sees neither spelling with its generic arguments.
        if let call = expression.as(FunctionCallExprSyntax.self),
           let pairCall = pairCallKind(call),
           call.arguments.count == 2,
           let firstSyntax = pairCall == .initializer
                ? call.arguments.first(where: { $0.label?.text == "first" })?.expression
                : call.arguments.first?.expression,
           let secondSyntax = pairCall == .initializer
                ? call.arguments.first(where: { $0.label?.text == "second" })?.expression
                : call.arguments.dropFirst().first?.expression,
           let first = decodeTypedFacadeValue(firstSyntax, scope: scope),
           let second = decodeTypedFacadeValue(secondSyntax, scope: scope) {
            if case .value(let firstValue) = first,
               case .value(let secondValue) = second {
                return .value(.tuple([firstValue, secondValue]))
            }
            return .tupleLiteral([first, second])
        }
        // `If` is a freestanding Swift-shaped formal value constructor. Parse
        // it here, before falling back to the untyped decoder, so a value
        // bound by `Function.mapping` or `With` remains in scope.
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "If",
           let conditionSyntax = call.arguments.first?.expression,
           let thenSyntax = call.arguments.first(where: { $0.label?.text == "then" })?.expression,
           let elseSyntax = call.arguments.first(where: { $0.label?.text == "else" })?.expression,
           let condition = decodeTypedFacadeValue(conditionSyntax, scope: scope),
           let thenValue = decodeTypedFacadeValue(
                thenSyntax,
                scope: scope,
                expectedEnumType: expectedEnumType
           ),
           let elseValue = decodeTypedFacadeValue(
                elseSyntax,
                scope: scope,
                expectedEnumType: expectedEnumType
           ) {
            return .ifThenElse(condition, thenValue, elseValue)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Fold",
           let sequenceSyntax = call.arguments.first?.expression,
           let initialSyntax = call.arguments.first(where: { $0.label?.text == "startingWith" })?.expression,
           let sequence = decodeTypedFacadeValue(sequenceSyntax, scope: scope),
           let initial = decodeTypedFacadeValue(initialSyntax, scope: scope),
           let closure = call.trailingClosure,
           closure.statements.count == 1,
           case .expr(let bodySyntax) = closure.statements.first?.item,
           closureParameterNames(in: closure).count == 2 {
            let parameters = closureParameterNames(in: closure)
            let bindings = [
                parameters[0]: StateExpr.variable(parameters[0]),
                parameters[1]: StateExpr.variable(parameters[1])
            ]
            guard let body = decodeTypedFacadeValue(
                bodySyntax,
                scope: typedFacadeScope(
                    scope,
                    bindings: bindings.map { (sourceName: $0.key, value: $0.value) }
                )
            ) else { return nil }
            return .foldFunction(
                FormalLambda(parameters: parameters, body: body),
                initial: initial,
                sequence: sequence
            )
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let operation = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text,
           let lhs = decodeTypedFacadeValue(
                infix.leftOperand,
                scope: scope,
                expectedEnumType: typedFacadeValueShape(infix.rightOperand, scope: scope)?.enumerationType
           ),
           let rhs = decodeTypedFacadeValue(
                infix.rightOperand,
                scope: scope,
                expectedEnumType: typedFacadeValueShape(infix.leftOperand, scope: scope)?.enumerationType
           ) {
            return applyInfixOp(operation, lhs, rhs)
        }
        if let prefix = expression.as(PrefixOperatorExprSyntax.self),
           let operand = decodeTypedFacadeValue(prefix.expression, scope: scope) {
            switch prefix.operator.text {
            case "!": return .not(operand)
            case "-":
                // The runtime typed facade receives `-1` as an Int literal.
                // Canonicalize the macro-side spelling the same way before a
                // bounded collection expands it into many formal values.
                if case .value(.int(let value)) = operand {
                    return .value(.int(-value))
                }
                return .negate(operand)
            default: return nil
            }
        }
        if let subscriptCall = expression.as(SubscriptCallExprSyntax.self),
           subscriptCall.arguments.count == 1,
           let base = decodeTypedFacadeValue(subscriptCall.calledExpression, scope: scope),
           let selector = subscriptCall.arguments.first?.expression {
            if let fieldName = typedFieldName(selector) {
                return .recordAccess(base, fieldName)
            }
            guard let index = decodeTypedFacadeValue(selector, scope: scope) else { return nil }
            if let reference = subscriptCall.calledExpression.as(DeclReferenceExprSyntax.self),
               algorithmTupleVariables.contains(reference.baseName.text) {
                return .tupleDynamicAccess(base, index)
            }
            return .functionApply(base, index)
        }
        if let member = expression.as(MemberAccessExprSyntax.self),
           let baseSyntax = member.base,
           let base = decodeTypedFacadeValue(baseSyntax, scope: scope) {
            switch member.declName.baseName.text {
            case "raw", "stateExpr", "expr": return base
            case "count":
                switch typedFacadeValueShape(baseSyntax, scope: scope) {
                case .tuple: return .tupleLength(base)
                case .zeroBasedSequence: return .cardinality(.domain(base))
                default: return nil
                }
            case "cardinality": return .cardinality(base)
            case "range":
                return .operatorApplication(.reference("Range", arity: 1), [.value(base)])
            case "isEmpty": return .equal(.cardinality(base), .value(.int(0)))
            case "subsets": return .powerSet(base)
            default: break
            }
        }
        // A `SetExpr` initializer is a closed typed value, unlike
        // `SetExpr.literal`, which is an expression form.  Constants need the
        // former so the builder and macro both retain a concrete TLA+ set.
        if let call = expression.as(FunctionCallExprSyntax.self),
           let type = typedFacadeType(call.calledExpression),
           type.name == "SetExpr" {
            return decodeTypedSetValue(
                call,
                elementType: type.terminalArgumentName(at: 0),
                scope: scope
            )
        }

        guard let call = expression.as(FunctionCallExprSyntax.self),
              let access = call.calledExpression.as(MemberAccessExprSyntax.self)
        else { return nil }

        // `OneOf` preserves an ordinary TLA+ union and lifts each alternative
        // as its underlying formal value.
        if ["first", "second"].contains(access.declName.baseName.text),
           let unionType = typedFacadeType(access.base),
           unionType.name == "OneOf",
           let valueSyntax = call.arguments.first?.expression,
           let value = decodeTypedFacadeValue(valueSyntax, scope: scope) {
            return value
        }

        // A typed union view is justified by the surrounding PlusCal label.
        // Its formal representation remains the original value.
        if ["assumingFirst", "assumingSecond"].contains(access.declName.baseName.text),
           let baseSyntax = access.base,
           let base = decodeTypedFacadeValue(baseSyntax, scope: scope) {
            return base
        }

        if access.declName.baseName.text == "literal",
           let literalType = typedFacadeType(access.base) {
            switch literalType.name {
            case "Record":
                return decodeTypedRecordLiteral(call, scope: scope)
            case "SetExpr":
                return decodeTypedSetLiteral(
                    call,
                    elementType: literalType.terminalArgumentName(at: 0),
                    scope: scope
                )
            case "TupleExpr":
                let elements = call.arguments.compactMap {
                    decodeTypedFacadeValue($0.expression, scope: scope)
                }
                guard elements.count == call.arguments.count else { return nil }
                return .tupleLiteral(elements)
            case "Pair":
                guard call.arguments.count == 2,
                      let first = decodeTypedFacadeValue(
                        call.arguments[call.arguments.startIndex].expression,
                        scope: scope
                      ),
                      let second = decodeTypedFacadeValue(
                        call.arguments[call.arguments.index(after: call.arguments.startIndex)].expression,
                        scope: scope
                      )
                else { return nil }
                return .tupleLiteral([first, second])
            case "Function":
                return decodeTypedFunctionLiteral(
                    call,
                    domainType: literalType.terminalArgumentName(at: 0),
                    scope: scope
                )
            default:
                return nil
            }
        }

        if access.declName.baseName.text == "mapping",
           let literalType = typedFacadeType(access.base),
           literalType.name == "Function",
           let domainType = literalType.terminalArgumentName(at: 0),
           let domain = enumDefinition(named: domainType)?.finiteValues,
           let closure = call.trailingClosure,
           let parameter = closureParameterNames(in: closure).first,
           closure.statements.count == 1,
           case .expr(let bodySyntax) = closure.statements.first?.item {
            let functionScope = typedFacadeScope(
                scope,
                binding: parameter,
                to: .variable("__pcal_function_key"),
                shape: .enumeration(domainType)
            )
            let body = decodeTypedFacadeValue(
                bodySyntax,
                scope: functionScope,
                expectedEnumType: literalType.terminalArgumentName(at: 1)
            )
                ?? decodeTypedDefaultValue(bodySyntax, expectedType: literalType.argument(at: 1))
            guard let body else { return nil }
            return .functionLiteral(
                .setLiteral(domain.map(StateExpr.value)),
                "__pcal_function_key",
                body
            )
        }

        if access.declName.baseName.text == "ifThenElse",
           let base = access.base,
           typedFacadeType(base)?.name == "Expr",
           let conditionSyntax = call.arguments.first?.expression,
           let thenSyntax = call.arguments.first(where: { $0.label?.text == "then" })?.expression,
           let elseSyntax = call.arguments.first(where: { $0.label?.text == "else" })?.expression,
           let condition = decodeTypedFacadeValue(conditionSyntax, scope: scope),
           let thenValue = decodeTypedFacadeValue(
                thenSyntax,
                scope: scope,
                expectedEnumType: expectedEnumType
           ),
           let elseValue = decodeTypedFacadeValue(
                elseSyntax,
                scope: scope,
                expectedEnumType: expectedEnumType
           ) {
            return .ifThenElse(condition, thenValue, elseValue)
        }

        // Swift infers `Record<Schema>` from a surrounding `SetExpr` or
        // `Function` literal, so the source spelling may be `Record.literal`.
        // Its field entries retain enough syntax to decode independently.
        if access.declName.baseName.text == "literal",
           access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "Record" {
            return decodeTypedRecordLiteral(call, scope: scope)
        }

        guard let baseSyntax = access.base,
              let base = decodeTypedFacadeValue(baseSyntax, scope: scope)
        else { return nil }

        switch access.declName.baseName.text {
        case "contains":
            guard let memberSyntax = call.arguments.first?.expression,
                  let member = decodeTypedFacadeValue(memberSyntax, scope: scope)
            else { return nil }
            return .in(member, base)
        case "union":
            guard let otherSyntax = call.arguments.first?.expression,
                  let other = decodeTypedFacadeValue(otherSyntax, scope: scope)
            else { return nil }
            return .union(base, other)
        case "intersection":
            guard let otherSyntax = call.arguments.first?.expression,
                  let other = decodeTypedFacadeValue(otherSyntax, scope: scope)
            else { return nil }
            return .intersection(base, other)
        case "isSubset":
            guard let otherSyntax = call.arguments.first(where: { $0.label?.text == "of" })?.expression,
                  let other = decodeTypedFacadeValue(otherSyntax, scope: scope)
            else { return nil }
            return .subset(base, other)
        case "appending":
            guard let elementSyntax = call.arguments.first?.expression,
                  let element = decodeTypedFacadeValue(elementSyntax, scope: scope)
            else { return nil }
            return .tupleAppend(base, element)
        case "concatenating":
            guard let otherSyntax = call.arguments.first?.expression,
                  let other = decodeTypedFacadeValue(otherSyntax, scope: scope)
            else { return nil }
            return .tupleConcatenate(base, other)
        case "inserting", "removing":
            guard let elementSyntax = call.arguments.first?.expression,
                  let element = decodeTypedFacadeValue(elementSyntax, scope: scope)
            else { return nil }
            let singleton = StateExpr.setLiteral([element])
            return access.declName.baseName.text == "inserting"
                ? .union(base, singleton)
                : .setDifference(base, singleton)
        case "updating":
            break
        case "filtering":
            guard let closure = call.trailingClosure,
                  closure.statements.count == 1,
                  case .expr(let body) = closure.statements.first?.item,
                  let parameter = closureParameterNames(in: closure).first,
                  closureParameterNames(in: closure).count == 1,
                  let predicate = decodeTypedFacadeValue(
                    body,
                    scope: typedFacadeScope(scope, binding: parameter, to: .variable(parameter))
                  )
            else { return nil }
            return .setFilter(base, parameter, predicate)
        case "mapping":
            guard let closure = call.trailingClosure,
                  closure.statements.count == 1,
                  case .expr(let body) = closure.statements.first?.item,
                  let parameter = closureParameterNames(in: closure).first,
                  closureParameterNames(in: closure).count == 1,
                  let mapping = decodeTypedFacadeValue(
                    body,
                    scope: typedFacadeScope(scope, binding: parameter, to: .variable(parameter))
                  )
            else { return nil }
            return .setMap(mapping, parameter, base)
        case "at":
            guard let indexSyntax = call.arguments.first?.expression,
                  let index = decodeTypedFacadeValue(indexSyntax, scope: scope)
            else { return nil }
            if case .value(.int(let position)) = index {
                return .tupleAccess(base, position)
            }
            return .tupleDynamicAccess(base, index)
        default:
            return nil
        }

        guard let selectorSyntax = call.arguments.first?.expression,
              let selector = typedUpdateSelector(selectorSyntax, scope: scope)
        else { return nil }

        if let closure = call.trailingClosure {
            guard closure.statements.count == 1,
                  case .expr(let body) = closure.statements.first?.item,
                  let parameter = closureParameterNames(in: closure).first,
                  closureParameterNames(in: closure).count == 1
            else { return nil }
            let selected = typedSelectedValue(base, selector: selectorSyntax, scope: scope)
            guard let selected,
                  let value = decodeTypedFacadeValue(
                    body,
                    scope: typedFacadeScope(scope, binding: parameter, to: selected)
                  )
            else { return nil }
            return .except(base, selector, value)
        }

        guard let valueSyntax = call.arguments.first(where: { $0.label?.text == "to" })?.expression,
              let value = decodeTypedFacadeValue(valueSyntax, scope: scope)
        else { return nil }
        return .except(base, selector, value)
    }

    func decodeTypedFacadeValue(
        _ expression: ExprSyntax,
        scope: TypedFacadeScope,
        expectedEnumType: String? = nil
    ) -> StateExpr? {
        if let call = expression.as(FunctionCallExprSyntax.self),
           let constructor = compilerGrammarName(in: call.calledExpression),
           constructor == "FormalModuleParameter" || constructor == "Parameter",
           let name = call.arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
            return .variable(name)
        }
        if let filledSequence = decodeZeroBasedSequenceFill(expression, scope: scope) {
            return filledSequence
        }
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            if let value = scope.value(for: reference) { return value }
            if let constant = constants.value(named: name) { return .value(constant) }
            if let state = sourceScope.value(for: reference) { return state }
        }
        if let literal = expression.as(IntegerLiteralExprSyntax.self),
           let value = Self.integerLiteralValue(literal) {
            return .value(.int(value))
        }
        if let literal = expression.as(BooleanLiteralExprSyntax.self) {
            return .value(.bool(literal.literal.text == "true"))
        }
        if let literal = expression.as(StringLiteralExprSyntax.self),
           let value = literal.representedLiteralValue {
            return .value(.string(value))
        }
        if let enumCase = decodeEnumCase(expression, expectedType: expectedEnumType) {
            return enumCase
        }
        if let member = expression.as(MemberAccessExprSyntax.self),
           let type = terminalTypeName(in: member.base),
           enumDefinition(named: type) != nil {
            return nil
        }
        if let decoded = decodeTypedFacadeExpr(
            expression,
            scope: scope,
            expectedEnumType: expectedEnumType
        ) {
            return decoded
        }
        guard scope.isEmpty else { return nil }
        return decodeStateExpr(expression)
    }

    private func decodeEnumCase(
        _ expression: ExprSyntax,
        expectedType: String? = nil
    ) -> StateExpr? {
        guard let member = expression.as(MemberAccessExprSyntax.self) else { return nil }
        if member.base != nil {
            guard let type = terminalTypeName(in: member.base),
                  let value = enumDefinition(named: type)?.value(named: member.declName.baseName.text)
            else { return nil }
            return .value(value)
        }
        if let expectedType,
           let value = enumDefinition(named: expectedType)?.value(named: member.declName.baseName.text) {
            return .value(value)
        }
        let matches = enumDefinitions.compactMap {
            $0.value(named: member.declName.baseName.text)
        }
        if matches.count == 1, let value = matches.first {
            return .value(value)
        }
        if matches.count > 1 {
            algorithmParseFailure = "Enum case '.\(member.declName.baseName.text)' is ambiguous in this scope."
        }
        return nil
    }

    func typedUpdateSelector(
        _ expression: ExprSyntax,
        scope: TypedFacadeScope
    ) -> StateExpr? {
        if let fieldName = typedFieldName(expression) {
            return .value(.string(fieldName))
        }
        return decodeTypedFacadeValue(expression, scope: scope)
    }

    func typedSelectedValue(
        _ base: StateExpr,
        selector: ExprSyntax,
        scope: TypedFacadeScope
    ) -> StateExpr? {
        if let fieldName = typedFieldName(selector) {
            return .recordAccess(base, fieldName)
        }
        guard let index = decodeTypedFacadeValue(selector, scope: scope) else { return nil }
        return .functionApply(base, index)
    }

    func typedFieldName(_ expression: ExprSyntax) -> String? {
        guard let member = expression.as(MemberAccessExprSyntax.self),
              member.base != nil,
              member.declName.baseName.text != "finiteValues"
        else { return nil }
        if let typeName = terminalTypeName(in: member.base), enumDefinition(named: typeName) != nil {
            return nil
        }
        return member.declName.baseName.text
    }

    /// A record field may be qualified by its enclosing model type, while an
    /// enum case must remain a formal enum value. Reduce either spelling to
    /// its terminal type name before consulting the enum namespace.
    func terminalTypeName(in expression: ExprSyntax?) -> String? {
        if let generic = expression?.as(GenericSpecializationExprSyntax.self) {
            return terminalTypeName(in: generic.expression)
        }
        if let reference = expression?.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if let member = expression?.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }

    func compilerGrammarName(in expression: ExprSyntax?) -> String? {
        let base = expression?.as(GenericSpecializationExprSyntax.self)?.expression ?? expression
        guard let base,
              let path = Self.sourceTypePath(base),
              let name = path.last
        else { return nil }
        let qualification = Array(path.dropLast())
        return qualification.isEmpty || qualification == ["SwiftTLA"] ? name : nil
    }

    struct TypedFacadeType {
        let qualification: [String]
        let name: String
        let arguments: [TypeSyntax]

        func argument(at index: Int) -> TypeSyntax? {
            arguments.indices.contains(index) ? arguments[index] : nil
        }

        func terminalArgumentName(at index: Int) -> String? {
            argument(at: index).flatMap(ParserSession.terminalTypeName)
        }

        var renderedSourceName: String? {
            let renderedArguments = arguments.compactMap(ParserSession.sourceTypeSpelling)
            guard renderedArguments.count == arguments.count else { return nil }
            let sourceName = (qualification + [name]).joined(separator: ".")
            return "\(sourceName)<\(renderedArguments.joined(separator: ", "))>"
        }
    }

    func typedFacadeValueShape(
        _ expression: ExprSyntax,
        scope: TypedFacadeScope
    ) -> TypedFacadeValueShape? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return scope.shape(for: reference)
        }
        if let member = expression.as(MemberAccessExprSyntax.self),
           ["expr", "raw", "stateExpr"].contains(member.declName.baseName.text),
           let base = member.base {
            return typedFacadeValueShape(base, scope: scope)
        }
        if let member = expression.as(MemberAccessExprSyntax.self),
           let type = terminalTypeName(in: member.base),
           enumDefinition(named: type) != nil {
            return member.declName.baseName.text == "all"
                ? .set(.enumeration(type))
                : .enumeration(type)
        }
        if let subscriptCall = expression.as(SubscriptCallExprSyntax.self),
           case .function(let value) = typedFacadeValueShape(
                subscriptCall.calledExpression,
                scope: scope
           ) {
            return value
        }
        guard let call = expression.as(FunctionCallExprSyntax.self) else { return nil }
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            switch reference.baseName.text {
            case "Sequences", "SortedSequences": return .set(.tuple)
            case "ZeroBasedSequences": return .set(.zeroBasedSequence)
            default: break
            }
        }
        if let type = typedFacadeType(call.calledExpression) {
            return typedFacadeValueShape(type)
        }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           ["appending", "concatenating"].contains(member.declName.baseName.text),
           let base = member.base {
            return typedFacadeValueShape(base, scope: scope)
        }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           let type = typedFacadeType(member.base) {
            return typedFacadeValueShape(type)
        }
        return nil
    }

    private func typedFacadeValueShape(_ type: TypedFacadeType) -> TypedFacadeValueShape? {
        switch type.name {
        case "Function":
            guard let valueType = type.argument(at: 1),
                  let value = typedFacadeValueShape(valueType)
            else { return nil }
            return .function(value)
        case "TupleExpr": return .tuple
        case "ZeroBasedSequence": return .zeroBasedSequence
        case "SetExpr":
            guard let argument = type.argument(at: 0),
                  let element = typedFacadeValueShape(argument)
            else { return nil }
            return .set(element)
        default:
            return enumDefinition(named: type.name) == nil ? nil : .enumeration(type.name)
        }
    }

    private func typedFacadeValueShape(_ type: TypeSyntax) -> TypedFacadeValueShape? {
        let facade: TypedFacadeType
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            facade = .init(
                qualification: [],
                name: identifier.name.text,
                arguments: identifier.genericArgumentClause?.arguments.map(\.argument) ?? []
            )
        } else if let member = type.as(MemberTypeSyntax.self) {
            guard member.baseType.as(IdentifierTypeSyntax.self)?.name.text == "SwiftTLA"
            else { return nil }
            facade = .init(
                qualification: ["SwiftTLA"],
                name: member.name.text,
                arguments: member.genericArgumentClause?.arguments.map(\.argument) ?? []
            )
        } else {
            return nil
        }
        return typedFacadeValueShape(facade)
    }

    /// Preserves a supported type's Swift spelling for generated Swift output.
    /// Semantic recognition uses the syntax nodes above; this conversion runs
    /// only after the parser has identified the type form.
    static func sourceTypeSpelling(_ type: TypeSyntax) -> String? {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            let arguments = identifier.genericArgumentClause?.arguments.map(\.argument) ?? []
            let renderedArguments = arguments.compactMap(Self.sourceTypeSpelling)
            guard renderedArguments.count == arguments.count else { return nil }
            return renderedArguments.isEmpty
                ? identifier.name.text
                : "\(identifier.name.text)<\(renderedArguments.joined(separator: ", "))>"
        }
        if let member = type.as(MemberTypeSyntax.self),
           let base = Self.sourceTypeSpelling(member.baseType) {
            let arguments = member.genericArgumentClause?.arguments.map(\.argument) ?? []
            let renderedArguments = arguments.compactMap(Self.sourceTypeSpelling)
            guard renderedArguments.count == arguments.count else { return nil }
            let name = "\(base).\(member.name.text)"
            return renderedArguments.isEmpty
                ? name
                : "\(name)<\(renderedArguments.joined(separator: ", "))>"
        }
        return nil
    }

    func typedFacadeType(_ expression: ExprSyntax?) -> TypedFacadeType? {
        guard let generic = expression?.as(GenericSpecializationExprSyntax.self),
              let name = compilerGrammarName(in: generic.expression),
              let path = Self.sourceTypePath(generic.expression)
        else { return nil }
        let qualification = Array(path.dropLast())
        return .init(
            qualification: qualification,
            name: name,
            arguments: generic.genericArgumentClause.arguments.map(\.argument)
        )
    }

    private static func sourceTypePath(_ expression: ExprSyntax) -> [String]? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return [reference.baseName.text]
        }
        guard let member = expression.as(MemberAccessExprSyntax.self),
              let base = member.base,
              let qualification = sourceTypePath(base)
        else { return nil }
        return qualification + [member.declName.baseName.text]
    }

    static func terminalTypeName(_ type: TypeSyntax) -> String? {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text
        }
        return nil
    }

    private enum PairCallKind: Equatable {
        case initializer
        case literal
    }

    private func pairCallKind(_ call: FunctionCallExprSyntax) -> PairCallKind? {
        if call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Pair" {
            return .initializer
        }
        guard let access = call.calledExpression.as(MemberAccessExprSyntax.self),
              access.declName.baseName.text == "literal",
              access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "Pair"
        else { return nil }
        return .literal
    }

    /// Decodes a typed value whose Swift spelling omits its generic arguments
    /// because the surrounding expression already supplies them.
    func decodeTypedDefaultValue(_ expression: ExprSyntax, expectedType: TypeSyntax?) -> StateExpr? {
        guard let expectedType,
              facadeTypeName(expectedType) == "SetExpr",
              let call = expression.as(FunctionCallExprSyntax.self),
              call.arguments.isEmpty,
              call.trailingClosure == nil,
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "SetExpr"
        else { return nil }
        return .setLiteral([])
    }

    func facadeTypeName(_ type: TypeSyntax) -> String? {
        if let identifier = type.as(IdentifierTypeSyntax.self),
           identifier.genericArgumentClause != nil {
            return identifier.name.text
        }
        if let member = type.as(MemberTypeSyntax.self),
           member.genericArgumentClause != nil {
            return member.name.text
        }
        return nil
    }

    func decodeTypedRecordLiteral(
        _ call: FunctionCallExprSyntax,
        scope: TypedFacadeScope
    ) -> StateExpr? {
        var fields: [String: StateExpr] = [:]
        for argument in call.arguments {
            guard let entry = argument.expression.as(FunctionCallExprSyntax.self),
                  let entryName = entry.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text,
                  entryName == "init",
                  entry.arguments.count == 2,
                  let field = entry.arguments.first.flatMap({ typedFieldName($0.expression) }),
                  fields[field] == nil,
                  let value = entry.arguments.dropFirst().first.flatMap({
                      decodeTypedFacadeValue($0.expression, scope: scope)
                  })
            else { return nil }
            fields[field] = value
        }
        return StateExpr.record(fields)
    }

    func decodeTypedSetLiteral(
        _ call: FunctionCallExprSyntax,
        elementType: String?,
        scope: TypedFacadeScope
    ) -> StateExpr? {
        let elements = call.arguments.compactMap { element in
            if let member = element.expression.as(MemberAccessExprSyntax.self),
               member.base == nil,
               let elementType,
               let value = enumDefinition(named: elementType)?.value(named: member.declName.baseName.text) {
                return StateExpr.value(value)
            }
            return decodeTypedFacadeValue(element.expression, scope: scope)
        }
        guard elements.count == call.arguments.count else { return nil }
        return .setLiteral(elements)
    }

    func decodeTypedSetValue(
        _ call: FunctionCallExprSyntax,
        elementType: String?,
        scope: TypedFacadeScope
    ) -> StateExpr? {
        guard case .setLiteral(let elements) = decodeTypedSetLiteral(
            call,
            elementType: elementType,
            scope: scope
        ) else { return nil }
        let values = elements.compactMap { element -> TLAValue? in
            guard case .value(let value) = element else { return nil }
            return value
        }
        guard values.count == elements.count else { return nil }
        return .value(.set(Set(values)))
    }

    func decodeTypedFunctionLiteral(
        _ call: FunctionCallExprSyntax,
        domainType: String?,
        scope: TypedFacadeScope
    ) -> StateExpr? {
        guard let domainType,
              let domain = enumDefinition(named: domainType)?.finiteValues,
              !domain.isEmpty
        else { return nil }
        var pairs: [StateExpr] = []
        for argument in call.arguments {
            guard let entry = argument.expression.as(TupleExprSyntax.self),
                  entry.elements.count == 2,
                  let key = entry.elements.first.flatMap({
                      decodeTypedFacadeValue(
                          $0.expression,
                          scope: scope,
                          expectedEnumType: domainType
                      )
                  }),
                  let value = entry.elements.dropFirst().first.flatMap({ decodeTypedFacadeValue($0.expression, scope: scope) })
            else { return nil }
            pairs += [.equal(.variable("_typedFunctionEntry"), key), value]
        }
        return .functionLiteral(
            .setLiteral(domain.map(StateExpr.value)),
            "_typedFunctionEntry",
            .caseExpr(pairs, nil)
        )
    }

    private func decodeProcessLocalFamily(_ call: FunctionCallExprSyntax) -> StateExpr? {
        guard let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "family",
              call.arguments.count == 1,
              call.arguments.first?.label?.text == "for",
              let local = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text
        else {
            return nil
        }
        return .processLocalFamily(local)
    }

    func decodeMethodCall(_ memberAccess: MemberAccessExprSyntax, _ call: FunctionCallExprSyntax) -> StateExpr? {
        if let family = decodeProcessLocalFamily(call) {
            return family
        }
        let methodName = memberAccess.declName.baseName.text
        let args = Array(call.arguments)
        let base = memberAccess.base
        if let sourceType = base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
           FormalModuleProvider(sourceType: sourceType) == .zeroBasedSequences {
            switch methodName {
            case "indices":
                guard let sequence = args.first(where: { $0.label?.text == "of" }).flatMap({ decodeStateExpr($0.expression) }) else { return nil }
                return .recursiveCall("ZIndices", [sequence])
            case "length":
                guard let sequence = args.first(where: { $0.label?.text == "of" }).flatMap({ decodeStateExpr($0.expression) }) else { return nil }
                return .recursiveCall("ZLen", [sequence])
            case "rotation":
                guard let sequence = args.first(where: { $0.label?.text == "of" }).flatMap({ decodeStateExpr($0.expression) }),
                      let shift = args.first(where: { $0.label?.text == "leftBy" }).flatMap({ decodeStateExpr($0.expression) })
                else { return nil }
                return .recursiveCall("Rotation", [sequence, shift])
            case "lexicographicallyPrecedesOrEquals":
                guard args.count == 2,
                      let left = decodeStateExpr(args[0].expression),
                      let right = decodeStateExpr(args[1].expression)
                else { return nil }
                return .recursiveCall("LexicographicallyPrecedesOrEquals", [left, right])
            default:
                return nil
            }
        }
        let selfExpr = base.flatMap { decodeStateExpr($0) }
        switch methodName {
        case "isIn", "contains", "union", "intersection", "subtracting", "isSubset", "applying",
             "filtering", "mapping", "appending", "concatenating", "integerDivided":
            guard let selfExpr, let arg = args.first?.expression, let argExpr = decodeStateExpr(arg) else { return nil }
            switch methodName {
            case "isIn": return .in(selfExpr, argExpr)
            case "contains": return .in(argExpr, selfExpr)
            case "union": return .union(selfExpr, argExpr)
            case "intersection": return .intersection(selfExpr, argExpr)
            case "subtracting": return .setDifference(selfExpr, argExpr)
            case "isSubset": return .subset(selfExpr, argExpr)
            case "applying": return .functionApply(selfExpr, argExpr)
            case "filtering": return .setFilter(selfExpr, generatedBinderName(), argExpr)
            case "mapping": return .setMap(argExpr, generatedBinderName(), selfExpr)
            case "appending": return .tupleAppend(selfExpr, argExpr)
            case "concatenating": return .tupleConcatenate(selfExpr, argExpr)
            default: return .integerDivide(selfExpr, argExpr)
            }
        case "updated":
            guard let selfExpr, args.count >= 2,
                  let key = decodeStateExpr(args[0].expression),
                  let val = decodeStateExpr(args[1].expression) else { return nil }
            return .except(selfExpr, key, val)
        case "at":
            guard let selfExpr,
                  let idx = args.first?.expression.as(IntegerLiteralExprSyntax.self).flatMap(Self.integerLiteralValue)
            else { return nil }
            return .tupleAccess(selfExpr, idx)
        case "set", "tuple", "singleton":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr" else { return nil }
            if let array = args.first?.expression.as(ArrayExprSyntax.self) {
                let exprs = array.elements.compactMap { decodeStateExpr($0.expression) }
                return (methodName == "tuple") ? .tupleLiteral(exprs) : .setLiteral(exprs)
            }
            if methodName == "singleton", let single = args.first.flatMap({ decodeStateExpr($0.expression) }) {
                return .setLiteral([single])
            }
            return nil
        case "record":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr" else { return nil }
            var fields: [String: StateExpr] = [:]
            for arg in args {
                guard let label = arg.label?.text, let val = decodeStateExpr(arg.expression) else { return nil }
                fields[label] = val
            }
            return StateExpr.record(fields)
        case "variable":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr",
                  let name = args.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
            else { return nil }
            return .variable(name)
        case "if":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr",
                  args.count >= 3,
                  let cond = decodeStateExpr(args[0].expression),
                  let thenVal = decodeStateExpr(args[1].expression),
                  let elseVal = decodeStateExpr(args[2].expression) else { return nil }
            return .ifThenElse(cond, thenVal, elseVal)
        case "negate":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr",
                  let value = args.first.flatMap({ decodeStateExpr($0.expression) })
            else { return nil }
            return .negate(value)
        case "integerRange":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr",
                  args.count == 2,
                  let lower = decodeStateExpr(args[0].expression),
                  let upper = decodeStateExpr(args[1].expression)
            else { return nil }
            return .integerRange(lower, upper)
        case "enabled":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr",
                  let action = actionReference(args.first?.expression)
            else { return nil }
            return .enabledAction(action.name)
        case "letValue":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr",
                  args.count == 3,
                  let name = args[0].expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue,
                  let value = decodeStateExpr(args[1].expression),
                  let body = decodeStateExpr(args[2].expression)
            else { return nil }
            return .letValue(name, value, body)
        case "letIn":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr",
                  args.count == 2,
                  let definitionArray = args[0].expression.as(ArrayExprSyntax.self),
                  let body = decodeStateExpr(args[1].expression)
            else { return nil }
            let definitions = definitionArray.elements.compactMap {
                decodeLocalOperator($0.expression)
            }
            guard definitions.count == definitionArray.elements.count else { return nil }
            return .letIn(definitions, body)
        case "operatorApplication":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr",
                  args.count == 2,
                  let operation = decodeFormalOperator(args[0].expression),
                  let argumentArray = args[1].expression.as(ArrayExprSyntax.self)
            else { return nil }
            let arguments = argumentArray.elements.compactMap {
                decodeFormalCallArgument($0.expression, valueDecoder: decodeStateExpr)
            }
            guard arguments.count == argumentArray.elements.count else { return nil }
            return .operatorApplication(operation, arguments)
        case "setFilter", "setMap", "forAll":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr",
                  args.count == 3,
                  let binder = args[1].expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
            else { return nil }
            switch methodName {
            case "setFilter":
                guard let set = decodeStateExpr(args[0].expression),
                      let predicate = decodeStateExpr(args[2].expression) else { return nil }
                return .setFilter(set, binder, predicate)
            case "setMap":
                guard let value = decodeStateExpr(args[0].expression),
                      let set = decodeStateExpr(args[2].expression) else { return nil }
                return .setMap(value, binder, set)
            case "forAll":
                guard let set = decodeStateExpr(args[0].expression),
                      let predicate = decodeStateExpr(args[2].expression) else { return nil }
                return .forAll(set, binder, predicate)
            default:
                return nil
            }
        case "exists", "choose", "any", "functionLiteral":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr" else { return nil }
            if args.count == 3,
               let binder = args[1].expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
                guard let domain = decodeStateExpr(args[0].expression),
                      let body = decodeStateExpr(args[2].expression) else { return nil }
                switch methodName {
                case "exists": return .exists(domain, binder, body)
                case "choose": return .choose(domain, binder, body)
                case "functionLiteral": return .functionLiteral(domain, binder, body)
                default: return nil
                }
            }
            let exprs = args.compactMap { decodeStateExpr($0.expression) }
            switch methodName {
            case "any": return exprs.count >= 1 ? .choose(exprs[0], generatedBinderName(), .value(.bool(true))) : nil
            default: return nil
            }
        case "firstMatch":
            guard memberAccess.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "StateExpr" else { return nil }
            var pairs: [StateExpr] = []
            var fallback: StateExpr?
            for arg in args {
                if arg.label?.text == "fallback" {
                    fallback = decodeStateExpr(arg.expression)
                } else if let tuple = arg.expression.as(TupleExprSyntax.self) {
                    for elem in tuple.elements { if let p = decodeStateExpr(elem.expression) { pairs.append(p) } }
                }
            }
            return .caseExpr(pairs, fallback)
        default:
            return nil
        }
    }

    private func decodeLocalOperator(_ expression: ExprSyntax) -> LocalOperator? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "LocalOperator",
              let nameSyntax = call.arguments.first?.expression.as(StringLiteralExprSyntax.self)
        else { return nil }

        guard let name = nameSyntax.representedLiteralValue else { return nil }
        let parameters: [String]
        if let parameterArray = call.arguments.first(where: { $0.label?.text == "parameters" })?
            .expression.as(ArrayExprSyntax.self) {
            parameters = parameterArray.elements.compactMap { element in
                element.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
            }
            guard parameters.count == parameterArray.elements.count else { return nil }
        } else {
            parameters = []
        }
        let domain = call.arguments.first(where: { $0.label?.text == "domain" })
            .flatMap { decodeStateExpr($0.expression) }
        guard let bodySyntax = call.arguments.first(where: { $0.label?.text == "body" })?.expression,
              let body = decodeStateExpr(bodySyntax)
        else { return nil }
        return LocalOperator(name, parameters: parameters, domain: domain, body: body)
    }

    /// Decodes formal operators as syntax, rather than Swift closures. This is
    /// the source-side half of higher-order operator fidelity.
    private func decodeFormalOperator(_ expression: ExprSyntax) -> FormalOperator? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self)
        else { return nil }

        switch member.declName.baseName.text {
        case "reference":
            guard let name = call.arguments.first?.expression.as(StringLiteralExprSyntax.self)?
                    .representedLiteralValue,
                  let aritySyntax = call.arguments.first(where: { $0.label?.text == "arity" })?
                    .expression.as(IntegerLiteralExprSyntax.self),
                  let arity = Self.integerLiteralValue(aritySyntax), arity >= 0
            else { return nil }
            return .reference(name, arity: arity)
        case "lambda":
            guard let lambdaSyntax = call.arguments.first?.expression,
                  let lambda = decodeFormalLambda(lambdaSyntax)
            else { return nil }
            return .lambda(lambda)
        default:
            return nil
        }
    }

    private func decodeFormalLambda(_ expression: ExprSyntax) -> FormalLambda? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "FormalLambda",
              let parameterArray = call.arguments.first(where: { $0.label?.text == "parameters" })?
                .expression.as(ArrayExprSyntax.self),
              let bodySyntax = call.arguments.first(where: { $0.label?.text == "body" })?.expression
        else { return nil }

        let parameters = parameterArray.elements.compactMap { element in
            element.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        }
        guard parameters.count == parameterArray.elements.count,
              !parameters.isEmpty,
              Set(parameters).count == parameters.count,
              let body = decodeStateExpr(bodySyntax)
        else { return nil }
        return FormalLambda(parameters: parameters, body: body)
    }

    private func decodeFormalCallArgument(
        _ expression: ExprSyntax,
        valueDecoder: (ExprSyntax) -> StateExpr?
    ) -> FormalCallArgument? {
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              let argument = call.arguments.first?.expression
        else { return nil }

        switch member.declName.baseName.text {
        case "value":
            return valueDecoder(argument).map(FormalCallArgument.value)
        case "operator":
            return decodeFormalOperator(argument).map(FormalCallArgument.operator)
        default:
            return nil
        }
    }

    func decodeInfixExpr(_ elements: [ExprSyntax]) -> StateExpr? {
        decodeInfixExpr(
            elements,
            enumType: { _ in nil },
            decoding: { expression, _ in decodeStateExpr(expression) }
        )
    }

    func decodeInfixExpr(
        _ elements: [ExprSyntax],
        expectedEnumType: String? = nil,
        enumType: (ExprSyntax) -> String?,
        decoding decodeOperand: (ExprSyntax, String?) -> StateExpr?
    ) -> StateExpr? {
        guard !elements.isEmpty else { return nil }
        if elements.count == 1 {
            return decodeOperand(elements[0], expectedEnumType)
        }
        guard elements.count % 2 == 1 else { return nil }

        // SequenceExprSyntax retains a flat token sequence. Reconstruct
        // Swift precedence before lowering into the formal AST: a left fold
        // would turn `index <= count + 1` into `(index <= count) + 1`.
        func precedence(_ operation: String) -> Int? {
            switch operation {
            case "||": return 1
            case "&&": return 2
            case "==", "!=", "<", "<=", ">", ">=": return 3
            case "...": return 4
            case "+", "-": return 5
            case "*", "/", "%": return 6
            default: return nil
            }
        }

        let operators = stride(from: 1, to: elements.count, by: 2).compactMap { index -> (Int, String, Int)? in
            guard let operation = elements[index].as(BinaryOperatorExprSyntax.self)?.operator.text,
                  let level = precedence(operation)
            else { return nil }
            return (index, operation, level)
        }
        guard operators.count == (elements.count - 1) / 2,
              let split = operators.min(by: { lhs, rhs in
                  // Equal-precedence Swift operators associate from the left.
                  lhs.2 == rhs.2 ? lhs.0 > rhs.0 : lhs.2 < rhs.2
              })
        else { return nil }

        let lhsElements = Array(elements[..<split.0])
        let rhsElements = Array(elements[(split.0 + 1)...])
        let carriesEnumType = split.1 == "==" || split.1 == "!="
        let lhsEnumType = carriesEnumType && rhsElements.count == 1
            ? enumType(rhsElements[0]) ?? expectedEnumType
            : expectedEnumType
        let rhsEnumType = carriesEnumType && lhsElements.count == 1
            ? enumType(lhsElements[0]) ?? expectedEnumType
            : expectedEnumType
        guard let lhs = decodeInfixExpr(
                  lhsElements,
                  expectedEnumType: lhsEnumType,
                  enumType: enumType,
                  decoding: decodeOperand
              ),
              let rhs = decodeInfixExpr(
                  rhsElements,
                  expectedEnumType: rhsEnumType,
                  enumType: enumType,
                  decoding: decodeOperand
              )
        else { return nil }
        return applyInfixOp(split.1, lhs, rhs)
    }

    func applyInfixOp(_ op: String, _ lhs: StateExpr, _ rhs: StateExpr) -> StateExpr? {
        switch op {
        case "+": return .add(lhs, rhs)
        case "-": return .subtract(lhs, rhs)
        case "*": return .multiply(lhs, rhs)
        case "/": return .divide(lhs, rhs)
        case "%": return .modulo(lhs, rhs)
        case "<": return .lessThan(lhs, rhs)
        case "<=": return .lessOrEqual(lhs, rhs)
        case ">": return .greaterThan(lhs, rhs)
        case ">=": return .greaterOrEqual(lhs, rhs)
        case "==": return .equal(lhs, rhs)
        case "!=": return .notEqual(lhs, rhs)
        case "&&": return .and(lhs, rhs)
        case "||": return .or(lhs, rhs)
        case "...":
            guard case .value(.int(let f)) = lhs, case .value(.int(let l)) = rhs else { return nil }
            return .setLiteral((f...l).map { .value(.int($0)) })
        default: return nil
        }
    }

}

/// Package parser entry points create a fresh session for each source tree.
package enum SpecParser {
    package static func parseSpecClosure(
        _ closure: ClosureExprSyntax,
        enumDefinitions: [ParserEnumDefinition] = []
    ) -> ParsedSpecComponents {
        ParserSession(enumDefinitions: enumDefinitions).parseSpecClosure(closure)
    }

    static func decodeStateExpr(_ expression: ExprSyntax) -> StateExpr? {
        ParserSession().decodeStateExpr(expression)
    }

    static func decodeTypedFacadeValue(
        _ expression: ExprSyntax
    ) -> StateExpr? {
        ParserSession().decodeTypedFacadeValue(expression, scope: .empty)
    }

    static func decodeActionExpr(_ expression: ExprSyntax) -> ActionExpr? {
        ParserSession().decodeActionExpr(expression)
    }

    static func decodeActionFromClosure(_ closure: ClosureExprSyntax) -> ActionExpr? {
        ParserSession().decodeActionFromClosure(closure)
    }

    static func decodeTemporal(_ call: FunctionCallExprSyntax) -> TemporalExpr? {
        ParserSession().decodeTemporal(call)
    }

}

extension ParserSession {
    private func decodeActionState(
        _ expression: ExprSyntax,
        scope: TypedFacadeScope
    ) -> StateExpr? {
        decodeTypedFacadeValue(expression, scope: scope) ?? decodeStateExpr(expression)
    }

    func decodeActionExpr(
        _ expression: ExprSyntax,
        scope: TypedFacadeScope = .empty
    ) -> ActionExpr? {
        if let call = expression.as(FunctionCallExprSyntax.self),
           let access = call.calledExpression.as(MemberAccessExprSyntax.self),
           access.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "ActionExpr",
           access.declName.baseName.text == "exists",
           let binder = call.arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue,
           let domainSyntax = call.arguments.first(where: { $0.label?.text == "from" })?.expression,
           let domain = decodeTypedFacadeValue(domainSyntax, scope: scope),
           let closure = call.trailingClosure,
           let parameter = closureParameterNames(in: closure).first,
           closureParameterNames(in: closure).count == 1,
           closure.statements.count == 1,
           case .expr(let bodySyntax) = closure.statements.first?.item,
           let body = decodeActionExpr(
                bodySyntax,
                scope: typedFacadeScope(scope, binding: parameter, to: .variable(binder))
           ) {
            return .existsAction(binder, domain, body)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let access = call.calledExpression.as(MemberAccessExprSyntax.self),
           access.declName.baseName.text == "becomes",
           let baseRef = access.base?.as(DeclReferenceExprSyntax.self) {
            let varName = baseRef.baseName.text
            if let arg = call.arguments.first?.expression,
               let state = decodeActionState(arg, scope: scope) {
                if case .choose(let chosenSet, _, _) = state {
                    return .chooseAction(.named(varName), chosenSet)
                }
                return .assign(.named(varName), state)
            }
            return nil
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let access = call.calledExpression.as(MemberAccessExprSyntax.self),
           let baseRef = access.base?.as(DeclReferenceExprSyntax.self),
           let elementSyntax = call.arguments.first?.expression,
           let element = decodeActionState(elementSyntax, scope: scope) {
            switch access.declName.baseName.text {
            case "inserting":
                return .assign(
                    .named(baseRef.baseName.text),
                    .union(.variable(baseRef.baseName.text), .setLiteral([element]))
                )
            case "removing":
                return .assign(
                    .named(baseRef.baseName.text),
                    .setDifference(.variable(baseRef.baseName.text), .setLiteral([element]))
                )
            default:
                break
            }
        }
        if let access = expression.as(MemberAccessExprSyntax.self),
           access.declName.baseName.text == "stays",
           let baseRef = access.base?.as(DeclReferenceExprSyntax.self) {
            return .unchanged(.named(baseRef.baseName.text))
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let access = call.calledExpression.as(MemberAccessExprSyntax.self),
           access.declName.baseName.text == "when" {
            let outerCondition = call.arguments.first.flatMap { decodeActionState($0.expression, scope: scope) }
            guard let inner = access.base.flatMap({ decodeActionExpr($0, scope: scope) }) else { return nil }
            guard let outer = outerCondition else { return inner }
            // Merge: inner is always .and(.guard_(innerConditions), innerAction) or just .guard_ + .assign
            // We want: .and(.guard_(outer && innerConditions), innerAction)
            if case .and(.guard_(let innerCond), let innerAction) = inner {
                return .and(.guard_(.and(outer, innerCond)), innerAction)
            }
            return .and(.guard_(outer), inner)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
           let ref = call.calledExpression.as(DeclReferenceExprSyntax.self),
           ref.baseName.text == "choose",
           let varArg = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self),
           let fromArg = call.arguments.dropFirst().first?.expression,
           let setExpr = decodeActionState(fromArg, scope: scope) {
            return .chooseAction(.named(varArg.baseName.text), setExpr)
        }
        if let seq = expression.as(SequenceExprSyntax.self) {
            return decodeActionSequence(Array(seq.elements), scope: scope)
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self),
           let opText = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text {
            let leftAction = decodeActionExpr(infix.leftOperand, scope: scope)
            let rightAction = decodeActionExpr(infix.rightOperand, scope: scope)
            let leftState = decodeActionState(infix.leftOperand, scope: scope)
            let rightState = decodeActionState(infix.rightOperand, scope: scope)
            if opText == "||" {
                let l = leftAction ?? leftState.map(ActionExpr.guard_)
                let r = rightAction ?? rightState.map(ActionExpr.guard_)
                if let l, let r { return .or(l, r) }
            }
            if opText == "&&" {
                let l = leftAction ?? leftState.map(ActionExpr.guard_)
                let r = rightAction ?? rightState.map(ActionExpr.guard_)
                if let l, let r { return .and(l, r) }
            }
        }
        if let tuple = expression.as(TupleExprSyntax.self),
           let single = tuple.elements.first?.expression {
            return decodeActionExpr(single, scope: scope)
        }
        if let state = decodeActionState(expression, scope: scope) {
            return .guard_(state)
        }
        return nil
    }

    func decodeActionSequence(
        _ elements: [ExprSyntax],
        scope: TypedFacadeScope = .empty
    ) -> ActionExpr? {
        guard elements.count >= 1 else { return nil }
        if elements.count == 1 { return decodeActionExpr(elements[0], scope: scope) }
        if let orIdx = stride(from: 1, to: elements.count, by: 2).first(where: {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "||"
        }) {
            guard let left = decodeActionSequence(Array(elements[0..<orIdx]), scope: scope),
                  let right = decodeActionSequence(Array(elements[(orIdx + 1)..<elements.count]), scope: scope)
            else { return nil }
            return .or(left, right)
        }
        if let andIdx = stride(from: 1, to: elements.count, by: 2).first(where: {
            elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "&&"
        }) {
            guard let left = decodeActionSequence(Array(elements[0..<andIdx]), scope: scope),
                  let right = decodeActionSequence(Array(elements[(andIdx + 1)..<elements.count]), scope: scope)
            else { return nil }
            return .and(left, right)
        }
        if elements.count >= 3 {
            guard let opText = elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text else { return nil }
            if opText == "||" || opText == "&&" {
                guard let left = decodeActionExpr(elements[0], scope: scope),
                      let right = decodeActionExpr(elements[2], scope: scope) else { return nil }
                return opText == "||" ? .or(left, right) : .and(left, right)
            }
            if let state = decodeInfixExpr(elements) { return .guard_(state) }
        }
        return nil
    }

    func unwrapSingleElementTuple(_ expression: ExprSyntax) -> ExprSyntax {
        if let tuple = expression.as(TupleExprSyntax.self),
           tuple.elements.count == 1,
           let nested = tuple.elements.first?.expression {
            return nested
        }
        return expression
    }

    func decodeActionFromClosure(
        _ closure: ClosureExprSyntax,
        scope initialScope: TypedFacadeScope = .empty
    ) -> ActionExpr? {
        var actions: [ActionExpr] = []
        var scope = initialScope
        for statement in closure.statements {
            switch statement.item {
            case .decl(let declaration):
                guard let binding = actionLocalBinding(declaration, scope: scope) else { return nil }
                scope = typedFacadeScope(scope, binding: binding.name, to: binding.value)
            case .expr(let expression):
                guard let action = decodeActionExpr(expression, scope: scope) else { return nil }
                actions.append(action)
            default:
                return nil
            }
        }
        guard let first = actions.first else { return .guard_(.value(.bool(true))) }
        return actions.dropFirst().reduce(first) { .and($0, $1) }
    }

    private func actionLocalBinding(
        _ declaration: DeclSyntax,
        scope: TypedFacadeScope
    ) -> (name: String, value: StateExpr)? {
        guard let variable = declaration.as(VariableDeclSyntax.self),
              variable.bindingSpecifier.tokenKind == .keyword(.let),
              variable.bindings.count == 1,
              let binding = variable.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let initializer = binding.initializer?.value,
              let value = decodeTypedFacadeValue(initializer, scope: scope)
                ?? decodeStateExpr(initializer)
        else { return nil }
        return (name, value)
    }

    func decodeCollectionPredicate(_ call: FunctionCallExprSyntax) -> StateExpr? {
        decodeCollectionPredicate(call) { expression, scope in
            decodeTypedFacadeValue(expression, scope: scope)
        }
    }

    /// Decodes a collection predicate by binding its closure parameter to the
    /// selected collection value before the predicate body is decoded.
    func decodeCollectionPredicate(
        _ call: FunctionCallExprSyntax,
        requiringCollectionIn collectionNames: Set<String>? = nil,
        decodeBody: (ExprSyntax, TypedFacadeScope) -> StateExpr?
    ) -> StateExpr? {
        guard let access = call.calledExpression.as(MemberAccessExprSyntax.self),
              let collectionReference = access.base?.as(DeclReferenceExprSyntax.self),
              let kind = CollectionPredicateKind(rawValue: access.declName.baseName.text),
              let closure = call.trailingClosure
                ?? call.arguments.first?.expression.as(ClosureExprSyntax.self),
              let sourceParameter = Self.collectionPredicateParameter(in: closure),
              closure.statements.count == 1,
              case .expr(let bodySyntax) = closure.statements.first?.item
        else { return nil }

        let sourceName = collectionReference.baseName.text
        let collection = sourceScope.value(for: collectionReference) ?? .variable(sourceName)
        if let collectionNames {
            guard case .variable(let formalName) = collection,
                  collectionNames.contains(formalName)
            else { return nil }
        }
        let parameter = "member"
        let selectedValue = StateExpr.functionApply(collection, .variable(parameter))
        guard let body = decodeBody(
            bodySyntax,
            typedFacadeScope(.empty, binding: sourceParameter, to: selectedValue)
        ) else { return nil }

        let domain = StateExpr.domain(collection)
        switch kind {
        case .allSatisfy: return .forAll(domain, parameter, body)
        case .contains: return .exists(domain, parameter, body)
        }
    }

    enum CollectionPredicateKind: String {
        case allSatisfy
        case contains
    }

    func decodeTemporal(
        _ call: FunctionCallExprSyntax,
        scope: TypedFacadeScope = .empty
    ) -> TemporalExpr? {
        let operation: String
        let syntax: [ExprSyntax]
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           let base = member.base {
            operation = member.declName.baseName.text
            syntax = [base] + call.arguments.map(\.expression)
        } else if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            operation = reference.baseName.text
            syntax = call.arguments.dropFirst().map(\.expression)
        } else {
            return nil
        }
        let values = syntax.compactMap { decodeTypedFacadeValue($0, scope: scope) }
        guard values.count == syntax.count else { return nil }
        switch operation {
        case "leadsTo", "LeadsTo":
            guard values.count == 2 else { return nil }
            return .leadsTo(values[0], values[1])
        case "always", "Always":
            guard values.count == 1 else { return nil }
            return .always(values[0])
        case "eventually", "Eventually":
            guard values.count == 1 else { return nil }
            return .eventually(values[0])
        case "alwaysEventually", "AlwaysEventually":
            guard values.count == 1 else { return nil }
            return .alwaysEventually(values[0])
        case "eventuallyAlways", "EventuallyAlways":
            guard values.count == 1 else { return nil }
            return .eventuallyAlways(values[0])
        default:
            return nil
        }
    }

    func decodeFairness(_ call: FunctionCallExprSyntax) -> FairnessCondition? {
        guard let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text else {
            return nil
        }
        switch name {
        case "WeakFairness":
            guard let action = actionReference(call.arguments.first?.expression) else { return nil }
            return .weakFairness(action.name)
        case "StrongFairness":
            guard let action = actionReference(call.arguments.first?.expression) else { return nil }
            return .strongFairness(action.name)
        case "WeakFairnessNext": return .weakFairnessNext
        case "StrongFairnessNext": return .strongFairnessNext
        default: return nil
        }
    }

    func actionReference(_ expression: ExprSyntax?) -> NamedAction? {
        guard let reference = expression?.as(DeclReferenceExprSyntax.self) else { return nil }
        return sourceActionBindings[reference.baseName.text]
    }

}
