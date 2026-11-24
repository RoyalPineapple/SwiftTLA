import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA
import SwiftTLACompilerSupport

private let boolType = "SwiftTLA.TLAValue.BooleanLiteralType"

private struct ActionField {
    let name: String
    let slot: String
    let ordinal: Int
    let member: String?
    let type: String

    var before: String { member.map { "state.state.\($0)" } ?? "state.\(slot)" }
}

private struct ActionReference {
    let kind: String
    let value: TLAValue
    let type: String

    var operand: String {
        if kind == "literal", case .int(let integer) = value { return InitialFailureEvidence.binaryLiteral(integer) }
        return value.description
    }
    var tla: String { "<<\(TLAValue.string(kind)), \(operand)>>" }
    var wire: TLAValue { .tuple([.string(kind), value]) }
}

private struct ActionWrite {
    let target: String
    let value: ActionReference

    var tla: String { "<<\(TLAValue.string(target)), \(value.tla)>>" }
}

private func actionTuple(_ values: [String]) -> String {
    "<<\(values.joined(separator: ", "))>>"
}

private typealias ArithmeticCapturePlan = OrderedRHSPhysicalAction.Plan

private extension ArithmeticCapturePlan {
    var binaryLiterals: [String] {
        literals.map { value in
            if case .int(let integer) = value { return InitialFailureEvidence.binaryLiteral(integer) }
            return value.description
        }
    }

    var tla: String {
        "[count |-> \(kinds.count), kinds |-> \(TLAValue.tuple(kinds)), "
            + "literals |-> \(actionTuple(binaryLiterals)), reads |-> \(TLAValue.tuple(reads)), "
            + "left |-> \(TLAValue.tuple(left)), right |-> \(TLAValue.tuple(right))]"
    }
}

private enum ActionCapture {
    case reference(ActionReference)
    case expression(ArithmeticCapturePlan)

    var tag: String {
        switch self {
        case .reference(let reference): reference.kind
        case .expression: "expression"
        }
    }

    var tla: String {
        switch self {
        case .reference(let reference): reference.tla
        case .expression(let plan): "<<\"expression\", \(plan.tla)>>"
        }
    }

    var columns: ArithmeticCapturePlan {
        switch self {
        case .reference(let reference):
            let literal = reference.kind == "literal"
            return ArithmeticCapturePlan(kinds: [.string(literal ? "literal" : "read")],
                literals: [literal ? reference.value : .int(0)],
                reads: [literal ? .tuple([]) : reference.wire], left: [.int(0)], right: [.int(0)])
        case .expression(let plan):
            return plan
        }
    }
}

private struct ActionInstructions {
    var captures: [ActionCapture] = []
    var guards: [String] = []
    var writes: [ActionWrite] = []
    var failureAppendSites: [Int] = []
    var conditionalFailureCalls: [NativeConditionalFailureCall] = []

    var tla: String {
        "[captures |-> \(actionTuple(captures.map(\.tla))), "
            + "guards |-> \(actionTuple(guards)), writes |-> \(actionTuple(writes.map(\.tla)))]"
    }

    func selectedActionDefinitions(prefix: String = "NativeSelected") -> String {
        let plans = captures.map(\.columns)
        func column(_ path: KeyPath<ArithmeticCapturePlan, [TLAValue]>) -> String {
            actionTuple(plans.map { TLAValue.tuple($0[keyPath: path]).description })
        }
        return #"""
        \#(prefix)CaptureTags == \#(actionTuple(captures.map { TLAValue.string($0.tag).description }))
        \#(prefix)NodeCounts == \#(actionTuple(plans.map { String($0.kinds.count) }))
        \#(prefix)NodeKinds == \#(column(\.kinds))
        \#(prefix)NodeLiterals == \#(actionTuple(plans.map { actionTuple($0.binaryLiterals) }))
        \#(prefix)NodeReads == \#(column(\.reads))
        \#(prefix)NodeLeft == \#(column(\.left))
        \#(prefix)NodeRight == \#(column(\.right))
        \#(prefix)Guards == \#(actionTuple(guards))
        \#(prefix)Writes == \#(actionTuple(writes.map(\.tla)))
        \#(prefix)FailureAppendSites == \#(actionTuple(failureAppendSites.map(String.init)))
        \#(prefix)Plans == [index \in DOMAIN \#(prefix)CaptureTags |->
            [count |-> \#(prefix)NodeCounts[index], kinds |-> \#(prefix)NodeKinds[index],
             literals |-> \#(prefix)NodeLiterals[index], reads |-> \#(prefix)NodeReads[index],
             left |-> \#(prefix)NodeLeft[index], right |-> \#(prefix)NodeRight[index]]]
        \#(prefix)Captures == [index \in DOMAIN \#(prefix)CaptureTags |->
            IF \#(prefix)CaptureTags[index] = "expression" THEN <<"expression", \#(prefix)Plans[index]>>
            ELSE IF \#(prefix)CaptureTags[index] = "literal" THEN <<"literal", \#(prefix)NodeLiterals[index][1]>>
            ELSE \#(prefix)NodeReads[index][1]]
        \#(prefix)Action == [captures |-> \#(prefix)Captures, guards |-> \#(prefix)Guards, writes |-> \#(prefix)Writes]
        """#
    }
}

private func nativeArithmeticCapture(_ steps: [NativeIntInitialStep], reads: [ActionReference]) throws -> ArithmeticCapturePlan {
    var kinds: [TLAValue] = [], literals: [TLAValue] = [], references: [TLAValue] = []
    var left: [TLAValue] = [], right: [TLAValue] = []
    for step in steps {
        switch step {
        case .integer(let value):
            kinds.append(.string("literal"))
            literals.append(.int(value))
            references.append(.tuple([]))
            left.append(.int(0))
            right.append(.int(0))
        case .slot(let reference):
            guard let index = Int(reference), reads.indices.contains(index) else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            kinds.append(.string("read"))
            literals.append(.int(0))
            references.append(reads[index].wire)
            left.append(.int(0))
            right.append(.int(0))
        case .add(let first, let second):
            kinds.append(.string("add"))
            literals.append(.int(0))
            references.append(.tuple([]))
            left.append(.int(first + 1))
            right.append(.int(second + 1))
        }
    }
    return .init(kinds: kinds, literals: literals, reads: references, left: left, right: right)
}

private func syntaxWords(_ syntax: some SyntaxProtocol) -> [String] {
    syntax.tokens(viewMode: .sourceAccurate).filter { $0.tokenKind != .endOfFile }.map(\.text)
}

private func words(_ source: String) -> [String] {
    syntaxWords(Parser.parse(source: source))
}

private func sameWords(_ actual: [String], _ spelling: String) -> Bool {
    actual.elementsEqual(words(spelling)) { $0.utf8.elementsEqual($1.utf8) }
}

private func checked<T>(_ matches: [T]) throws -> T {
    guard matches.count == 1, let match = matches.first else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    return match
}

/// Bind returned State arguments to physical update slots, in the checked layout's public-field order.
func nativeUpdateSnapshotSlots(_ structs: [StructDeclSyntax], fields: [(member: String?, slot: String, type: String)]) throws -> [Int] {
    let updates = try checked(structs.filter { $0.name.text == "_Updates" })
    let apply = try checked(updates.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }
        .filter { $0.name.text == "applying" })
    guard let snapshot = apply.body?.statements.first?.item.as(FunctionCallExprSyntax.self),
          let state = snapshot.arguments.first?.expression.as(FunctionCallExprSyntax.self) else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    var ordinals: [String: Int] = [:]
    for (index, field) in fields.enumerated() {
        guard ordinals.updateValue(index + 1, forKey: field.slot) == nil else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
    }
    let visible = fields.compactMap { field in field.member.map { (name: $0, slot: field.slot) } }
    guard state.arguments.count == visible.count else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
    let slots = try zip(state.arguments, visible).map { argument, target in
        guard let candidate = argument.expression.firstToken(viewMode: .sourceAccurate)?.text,
              candidate.utf8.elementsEqual(target.slot.utf8), let ordinal = ordinals[candidate] else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        return ordinal
    }
    let storage = fields.map { "var \($0.slot): \($0.type)? = nil" }.joined(separator: "\n")
    let merging = fields.map {
        "guard SwiftTLA._NativeMachineOperations.mergeUpdate(&result.\($0.slot), other.\($0.slot)) else { return nil }"
    }.joined(separator: "\n")
    let materialized = zip(visible, slots).map { field, index in
        "\(field.name): \(fields[index - 1].slot) ?? state.state.\(field.name)"
    }.joined(separator: ", ")
    let hiddenArguments = fields.filter { $0.member == nil }.map { ", \($0.slot): \($0.slot) ?? state.\($0.slot)" }.joined()
    guard sameWords(syntaxWords(updates), """
    private struct _Updates: Sendable {
        \(storage)
        func merging(_ other: Self) -> Self? {
            var result = self
            \(merging)
            return result
        }
        func applying(to state: Snapshot) -> Snapshot {
            Snapshot(state: State(\(materialized))\(hiddenArguments))
        }
    }
    """) else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }

    return slots
}

package func verifyNativeMemberTokens(compiled: String, attached: String) throws {
    let actual = Parser.parse(source: compiled)
    let candidate = Parser.parse(source: attached)
    guard !compiled.utf8.contains(0), !attached.utf8.contains(0),
          !actual.hasError, !candidate.hasError,
          !actual.statements.isEmpty,
          syntaxWords(actual).elementsEqual(syntaxWords(candidate), by: { $0.utf8.elementsEqual($1.utf8) })
    else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
}

private func scalarActionHandles(_ declarations: [DeclSyntax]) throws -> [String] {
    let action = try checked(declarations.compactMap { $0.as(EnumDeclSyntax.self) }.filter { $0.name.text == "Action" })
    let labels = action.memberBlock.members.compactMap { item -> String? in
        guard let declaration = item.decl.as(EnumCaseDeclSyntax.self), declaration.elements.count == 1 else { return nil }
        return declaration.elements.first?.name.text
    }
    let cases = try labels.map { "case \(try nativeSourceIdentifier($0))" }.joined(separator: "\n")
    guard !labels.isEmpty, Set(labels).count == labels.count,
          sameWords(syntaxWords(action), "public enum Action: Hashable, Sendable { \(cases) }")
    else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
    return labels
}

private func scalarDispatchRoutes(_ dispatch: FunctionDeclSyntax, handles: [String]) throws
    -> [(handle: String, receiver: String, visitor: Int)] {
    let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
    guard let item = dispatch.body?.statements.first?.item,
          let choice = (item.as(ExprSyntax.self) ?? item.as(ExpressionStmtSyntax.self)?.expression)?
              .as(SwitchExprSyntax.self), choice.cases.count == handles.count else { throw invalid }

    let routes = try choice.cases.enumerated().map { index, item -> (handle: String, receiver: String, visitor: Int) in
        guard let branch = item.as(SwitchCaseSyntax.self),
              let returned = branch.statements.first?.item.as(ReturnStmtSyntax.self),
              let call = returned.expression?.as(TryExprSyntax.self)?.expression.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text,
              let ordinal = Int(callee.dropFirst("_visitSuccessors".count)),
              ordinal == index, callee == "_visitSuccessors\(ordinal)",
              let receiver = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { throw invalid }
        return (handles[index], receiver, ordinal + 1)
    }
    // Check that the decoded callee really receives that snapshot, context and callback,
    // and that every case is dispatched on the actual input action.
    let cases = try routes.map { route in
        "case .\(try nativeSourceIdentifier(route.handle)): return try Self._visitSuccessors\(route.visitor - 1)"
            + "(from: \(try nativeSourceIdentifier(route.receiver)), checking: &context, visit)"
    }.joined(separator: "\n")
    guard sameWords(syntaxWords(dispatch), """
        private func _visitSuccessors(for action: Action, checking context: inout CheckingContext<CheckingRegisters>?,
            _ visit: (Snapshot) throws -> Void) throws -> [NativeMachineEvaluationError] {
            switch action { \(cases) }
        }
        """) else { throw invalid }
    return routes
}

package func nativePublicSendBinding(_ source: String, operations: String, checking: String,
                                    module: String, binding: String) throws -> Data {
    guard module.range(of: "^[A-Za-z_][A-Za-z_0-9]*$", options: .regularExpression) != nil,
          binding.range(of: "^[A-Za-z_][A-Za-z_0-9]*$", options: .regularExpression) != nil else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    func parse(_ source: String) throws -> [DeclSyntax] {
        let parsed = Parser.parse(source: source)
        guard !parsed.hasError, !source.utf8.contains(0) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        return parsed.statements.compactMap { $0.item.as(DeclSyntax.self) }
    }
    @discardableResult
    func require(_ name: String, _ spelling: String, in declarations: [DeclSyntax]) throws -> FunctionDeclSyntax {
        let function = try checked(declarations.compactMap { $0.as(FunctionDeclSyntax.self) }.filter {
            $0.name.text == name
        })
        guard sameWords(syntaxWords(function), spelling) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        return function
    }

    let declarations = try parse(source)
    try verifyGeneratedPublicSendOutput(declarations)
    let state = try checked(declarations.compactMap { $0.as(VariableDeclSyntax.self) }.filter {
        $0.bindings.contains { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "state" }
    })
    let transition = try checked(declarations.compactMap { $0.as(StructDeclSyntax.self) }.filter {
        $0.name.text == "Transition"
    })
    guard sameWords(syntaxWords(state), "public var state: State { _execution.state }"),
          sameWords(syntaxWords(transition), """
              public struct Transition: Equatable, Sendable {
                  public let action: Action
                  public let before: State
                  public let after: State
              }
              """) else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }

    let helpers = try parse(operations)
    try require("_appendNativeOutcome", """
        @_documentation(visibility: internal)
        public func _appendNativeOutcome<Outcome: Sendable>(_ outcomes: inout [Outcome], _ outcome: Outcome) {
            outcomes.append(outcome)
        }
        """, in: helpers)
    try require("_firstNativeEvaluationFailure", """
        @_documentation(visibility: internal)
        public func _firstNativeEvaluationFailure(
            _ failures: [NativeMachineEvaluationError]
        ) -> NativeMachineEvaluationError? {
            failures.first
        }
        """, in: helpers)
    let singleton = try require("_singleNativeOutcome", """
        @_documentation(visibility: internal)
        public func _singleNativeOutcome<Outcome: Sendable>(
            _ outcomes: [Outcome], missing: GeneratedMachineError, ambiguous: GeneratedMachineError
        ) throws -> Outcome {
            guard let first = outcomes.first else { throw missing }
            guard outcomes.count == 1 else { throw ambiguous }
            return first
        }
        """, in: helpers)
    try require("_recordNativeOrderedIntAssignmentFailure", """
        @_documentation(visibility: internal)
        public func _recordNativeOrderedIntAssignmentFailure<Registers>(
            _ context: inout CheckingContext<Registers>?, actionOrdinal: Int, assignmentOrdinal: Int,
            preceding: @autoclosure () -> [Int], reason: NativeMachineEvaluationError
        ) {
            guard context?.recordsOrderedIntAssignmentFailures == true,
                  case .integerOverflow(.addition, _) = reason else { return }
            context?.record(.addition(.init(actionOrdinal: actionOrdinal, assignmentOrdinal: assignmentOrdinal,
                                            preceding: preceding(), reason: reason)))
        }
        """, in: parse(checking))

    return try nativePublicSendFlow(declarations, state: state, singleton: singleton, module: module, binding: binding)
}

private func nativePublicSendFlow(_ declarations: [DeclSyntax], state: VariableDeclSyntax,
                                 singleton: FunctionDeclSyntax, module: String, binding: String) throws -> Data {
    let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
    let methods = declarations.compactMap { $0.as(FunctionDeclSyntax.self) }

    func reference(_ expression: ExprSyntax?) -> String? {
        expression?.as(DeclReferenceExprSyntax.self)?.baseName.text
    }
    func member(_ expression: ExprSyntax?) -> String? {
        expression?.as(MemberAccessExprSyntax.self)?.declName.baseName.text
    }
    func value(_ item: CodeBlockItemSyntax) -> ExprSyntax? {
        item.item.as(ExprSyntax.self) ?? item.item.as(ExpressionStmtSyntax.self)?.expression
    }
    func local(_ item: CodeBlockItemSyntax) -> PatternBindingSyntax? {
        item.item.as(VariableDeclSyntax.self)?.bindings.first
    }
    func name(_ binding: PatternBindingSyntax?) -> String? {
        binding?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
    }
    func method(_ name: String, arity: Int) throws -> FunctionDeclSyntax {
        try checked(methods.filter {
            $0.name.text == name && $0.signature.parameterClause.parameters.count == arity
                && (name == "send" || $0.signature.parameterClause.parameters.first?.firstName.text == "for")
        })
    }
    func instructions(_ method: FunctionDeclSyntax) throws -> [CodeBlockItemSyntax] {
        guard let statements = method.body?.statements else { throw invalid }
        return Array(statements)
    }
    func string(_ name: String) -> String { TLAValue.string(name).description }
    func tuple(_ names: [String]) -> String { actionTuple(names.map(string)) }

    let send = try method("send", arity: 1)
    let sendSteps = try instructions(send)
    guard sendSteps.count == 4, let selected = local(sendSteps[0]), let capture = local(sendSteps[1]),
          let write = value(sendSteps[2])?.as(SequenceExprSyntax.self),
          let returned = sendSteps[3].item.as(ReturnStmtSyntax.self) else { throw invalid }
    let operands = Array(write.elements)
    let select = selected.initializer?.value.as(TryExprSyntax.self)?.expression.as(FunctionCallExprSyntax.self)
    let selectedCall = select?.arguments.first?.expression.as(FunctionCallExprSyntax.self)
    let transition = returned.expression?.as(FunctionCallExprSyntax.self)
    guard let select, let selector = member(select.calledExpression), let selectedCall,
          let selectedName = name(selected), let prior = name(capture), let captureSource = reference(capture.initializer?.value),
          let inputAction = send.signature.parameterClause.parameters.first?.secondName?.text,
          let suppliedAction = reference(selectedCall.arguments.first?.expression),
          let selectedCallee = reference(selectedCall.calledExpression),
          operands.count == 3, operands[1].is(AssignmentExprSyntax.self),
          let destination = reference(operands[0]), let writeSource = reference(operands[2]),
          let transition, let constructor = reference(transition.calledExpression),
          let getter = state.bindings.first?.accessorBlock, case .getter(let projectionBody) = getter.accessors,
          let head = projectionBody.first, let projection = value(head)?.as(MemberAccessExprSyntax.self),
          let snapshot = reference(projection.base), let snapshotState = member(ExprSyntax(projection)),
          let getterName = name(state.bindings.first) else { throw invalid }

    let sendOrder = try sendSteps.map { step -> String in
        if let slot = name(local(step)) { return slot }
        if step.item.is(ReturnStmtSyntax.self) { return constructor }
        if let sequence = value(step)?.as(SequenceExprSyntax.self),
           let slot = reference(sequence.elements.first) { return slot }
        throw invalid
    }
    let transitionFields = try transition.arguments.map { argument -> String in
        guard let label = argument.label?.text, let origin = reference(argument.expression) else { throw invalid }
        return "\(label) |-> \(string(origin))"
    }
    let errors = try select.arguments.dropFirst().map { argument -> String in
        guard let error = member(argument.expression), let kind = argument.label?.text else { throw invalid }
        return "\(kind) |-> \(string(error))"
    }

    let start = try instructions(method(selectedCallee, arity: 1))
    guard start.count == 2, let checking = local(start[0]),
          let delegate = start[1].item.as(ReturnStmtSyntax.self),
          checking.typeAnnotation?.type.is(OptionalTypeSyntax.self) == true, checking.initializer == nil,
          let delegatedCall = delegate.expression?.as(TryExprSyntax.self)?.expression.as(FunctionCallExprSyntax.self),
          let delegatedName = reference(delegatedCall.calledExpression) else { throw invalid }
    let collection = try instructions(method(delegatedName, arity: 2))
    guard collection.count == 4, let collectorBinding = local(collection[0]),
          let visitorBinding = local(collection[1]), let failed = value(collection[2])?.as(IfExprSyntax.self),
          let collectorReturn = collection[3].item.as(ReturnStmtSyntax.self) else { throw invalid }
    let visitorCall = visitorBinding.initializer?.value.as(TryExprSyntax.self)?.expression.as(FunctionCallExprSyntax.self)
    let failureTest = failed.conditions.first?.condition.as(OptionalBindingConditionSyntax.self)
    let reason = failureTest?.initializer?.value.as(FunctionCallExprSyntax.self)
    guard let visitorCall, let visitor = reference(visitorCall.calledExpression),
          let visitorAction = reference(visitorCall.arguments.first?.expression),
          let visitorResult = name(visitorBinding), let reason,
          let firstFailure = member(reason.calledExpression),
          let failureInput = reference(reason.arguments.first?.expression), failureInput == visitorResult,
          let collector = name(collectorBinding),
          let callback = visitorCall.trailingClosure?.statements.first,
          let append = value(callback)?.as(FunctionCallExprSyntax.self),
          let appendOperation = member(append.calledExpression),
          let target = append.arguments.first?.expression.as(InOutExprSyntax.self),
          let appendTarget = reference(target.expression),
          let appendix = append.arguments.dropFirst().first?.expression,
          let appended = reference(appendix),
          let snapshots = reference(collectorReturn.expression) else { throw invalid }
    let collectionOrder = try collection.map { step -> String in
        if let slot = name(local(step)) { return slot }
        if value(step)?.is(IfExprSyntax.self) == true { return firstFailure }
        if step.item.is(ReturnStmtSyntax.self) { return "return" }
        throw invalid
    }
    let receivers = try scalarDispatchRoutes(method(visitor, arity: 3), handles: scalarActionHandles(declarations))

    let selectorSteps = try instructions(singleton)
    let guards = selectorSteps.compactMap { $0.item.as(GuardStmtSyntax.self) }
    let checks = try guards.map { clause -> (String, String) in
        guard let condition = clause.conditions.first?.condition,
              let thrown = clause.body.statements.first?.item.as(ThrowStmtSyntax.self),
              let result = reference(thrown.expression) else { throw invalid }
        switch condition {
        case .optionalBinding(let binding):
            guard let property = member(binding.initializer?.value) else { throw invalid }
            return (property, result)
        case .expression(let expression):
            guard let comparison = expression.as(SequenceExprSyntax.self) else { throw invalid }
            let operands = Array(comparison.elements)
            guard operands.count == 3, let property = member(operands[0]),
                  operands[1].as(BinaryOperatorExprSyntax.self)?.operator.text == "==",
                  operands[2].as(IntegerLiteralExprSyntax.self)?.literal.text == "1" else { throw invalid }
            return (property, result)
        default:
            throw invalid
        }
    }
    guard let firstBinding = guards.first?.conditions.first?.condition.as(OptionalBindingConditionSyntax.self),
          let picked = firstBinding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
          let selectedReturn = selectorSteps.last?.item.as(ReturnStmtSyntax.self),
          let selectorResult = reference(selectedReturn.expression) else { throw invalid }
    let tests = actionTuple(checks.map { "[test |-> \(string($0.0)), error |-> \(string($0.1))]" })
    let targets = actionTuple(receivers.map {
        "[handle |-> \(string($0.handle)), slot |-> \(string($0.receiver)), visitor |-> \($0.visitor)]"
    })

    let bindingFields = [
        ("checking", string("none")),
        ("send", tuple(sendOrder)), ("selected", string(selectedName)), ("selector", string(selector)),
        ("inputAction", string(inputAction)), ("suppliedAction", string(suppliedAction)),
        ("captured", string(prior)), ("captureSource", string(captureSource)),
        ("writeTarget", string(destination)), ("writeValue", string(writeSource)),
        ("result", string(constructor)), ("fields", "[\(transitionFields.joined(separator: ", "))]"),
        ("getter", string(getterName)), ("projection", tuple([snapshot, snapshotState])),
        ("visitorAction", string(visitorAction)), ("visitor", string(visitor)),
        ("callbackOrder", tuple(collectionOrder)), ("visitorResult", string(visitorResult)),
        ("failureGate", string(firstFailure)), ("snapshots", string(snapshots)),
        ("collector", string(collector)), ("appendOperation", string(appendOperation)),
        ("appendTarget", string(appendTarget)), ("appended", string(appended)),
        ("receivers", targets), ("selectorGuards", tests),
        ("lookupBinding", string(picked)), ("lookupResult", string(selectorResult))
    ]
    let selectorErrors = "[\(errors.joined(separator: ", "))]"
    let planFields = bindingFields + [("errors", selectorErrors)]
    let groupWidth = 8
    let groups = stride(from: 0, to: planFields.count, by: groupWidth).map {
        planFields[$0..<min($0 + groupWidth, planFields.count)]
    }
    func groupName(_ index: Int) -> String { "\(binding)FieldGroup\(index + 1)" }
    func fieldNames(_ fields: ArraySlice<(String, String)>) -> String {
        fields.map { string($0.0) }.joined(separator: ", ")
    }
    func fieldGroup(_ field: String) throws -> Int {
        guard let index = groups.firstIndex(where: { $0.contains { $0.0 == field } }) else { throw invalid }
        return index
    }
    func fieldProjection(_ field: String) throws -> String {
        "\(binding), \(groupName(try fieldGroup(field)))"
    }
    let planNames = fieldNames(planFields[...])
    let groupDefinitions = groups.enumerated().map { index, fields in
        let lastValue = fields[fields.index(before: fields.endIndex)].1
        let alternatives = fields.dropLast().reversed().reduce(lastValue) { rest, field in
            "IF name = \(string(field.0)) THEN \(field.1)\n    ELSE \(rest)"
        }
        return "LOCAL \(groupName(index))(name) ==\n    \(alternatives)"
    }.joined(separator: "\n\n")
    let lookup = groups.dropLast().enumerated().reversed().reduce("\(groupName(groups.count - 1))(name)") {
        rest, group in
        "IF name \\in {\(fieldNames(group.element))} THEN \(groupName(group.offset))(name)\n        ELSE \(rest)"
    }
    let handles = receivers.map { string($0.handle) }.joined(separator: ", ")
    let operandFields = bindingFields.filter { !["checking", "selectorGuards", "receivers"].contains($0.0) }
    let projections = try operandFields.map { field, value in
        let claim = "<1>\(field). \(binding).\(field) = \(value)"
        let index = try fieldGroup(field)
        let group = groupName(index)
        guard field == "appendOperation" || field == "lookupBinding" else {
            return """
                \(claim)
                    BY ONLY IsaM("(subst fapply, simp, simp)") DEF \(binding), \(group)
                """
        }
        let key = string(field)
        let conditions = groups.dropLast().enumerated().prefix(index + 1).map { part in
            let membership = part.offset == index ? "\\in" : "\\notin"
            return "/\\ \(key) \(membership) {\(fieldNames(part.element))}"
        }.joined(separator: "\n            ")
        return """
            \(claim)
                <2>column. \(binding).\(field) = \(group)(\(key))
                    <3>domain. \(key) \\in {\(planNames)}
                        BY ONLY SMT
                    <3>groups.
                        \(conditions)
                        BY ONLY SMT
                    <3>. QED BY ONLY <3>domain, <3>groups, SMT DEF \(binding)
                <2>. QED BY ONLY <2>column, IsaM("simp") DEF \(group)
            """
    }.joined(separator: "\n")
    let receiverIndices = receivers.indices.map { String($0 + 1) }.joined(separator: ", ")

    return Data("""
    ---- MODULE \(module) ----
    EXTENDS NativePublicSendFlowRule

    \(groupDefinitions)

    \(binding) ==
        [name \\in {\(planNames)} |->
            \(lookup)]

    THEOREM \(binding)UsesNoChecking == \(binding).checking = "none"
        BY ONLY IsaM("(subst fapply, simp, simp)") DEF \(try fieldProjection("checking"))

    THEOREM \(binding)SelectorGuards == \(binding).selectorGuards = \(tests)
        BY ONLY IsaM("(subst fapply, simp, simp)") DEF \(try fieldProjection("selectorGuards"))

    THEOREM \(binding)Receivers == \(binding).receivers = \(targets)
        BY ONLY IsaM("(subst fapply, simp, simp)") DEF \(try fieldProjection("receivers"))

    THEOREM \(binding)ReportsMissingSuccessor ==
        \(binding).errors[\(binding).selectorGuards[1].error] = "noMatchingSuccessor"
    PROOF
    <1>errors. \(binding).errors = \(selectorErrors)
        BY ONLY IsaM("(subst fapply, simp, simp)") DEF \(try fieldProjection("errors"))
    <1>. QED BY ONLY \(binding)SelectorGuards, <1>errors, IsaM("simp")

    THEOREM \(binding)DecodesReceiverOperands ==
        \\A action \\in {\(handles)} : DecodedSendOperands(\(binding), action)
    PROOF
    \(projections)
    <1>. TAKE action \\in {\(handles)}
    <1>receiverIndices. DOMAIN \(binding).receivers = {\(receiverIndices)}
        BY ONLY \(binding)Receivers, SMT
    <1>route.
        /\\ \\E row \\in DOMAIN \(binding).receivers : \(binding).receivers[row].handle = action
        /\\ \\A row \\in DOMAIN \(binding).receivers :
               \(binding).receivers[row].handle = action => \(binding).receivers[row].slot = \(binding).writeTarget
        BY ONLY (action \\in {\(handles)}), <1>receiverIndices, \(binding)Receivers, <1>writeTarget, SMT
    <1>sendOrder.
        /\\ \(binding).send = <<\(binding).selected, \(binding).captured, \(binding).writeTarget, \(binding).result>>
        /\\ \\A i, j \\in DOMAIN \(binding).send : \(binding).send[i] = \(binding).send[j] => i = j
        BY ONLY <1>send, <1>selected, <1>captured, <1>writeTarget, <1>result, SMT
    <1>callbackSteps.
        /\\ \(binding).callbackOrder = <<\(binding).collector, \(binding).visitorResult, \(binding).failureGate, "return">>
        /\\ \\A i, j \\in DOMAIN \(binding).callbackOrder : \(binding).callbackOrder[i] = \(binding).callbackOrder[j] => i = j
        BY ONLY <1>callbackOrder, <1>collector, <1>visitorResult, <1>failureGate, SMT
    <1>localNames.
        \\A i, j \\in DOMAIN <<\(binding).inputAction, \(binding).captured, \(binding).getter>> :
            <<\(binding).inputAction, \(binding).captured, \(binding).getter>>[i]
                = <<\(binding).inputAction, \(binding).captured, \(binding).getter>>[j] => i = j
        BY ONLY <1>inputAction, <1>captured, <1>getter, SMT
    <1>wiring.
        /\\ \(binding).checking = "none" /\\ \(binding).visitor = "_visitSuccessors"
        /\\ \(binding).failureGate = "_firstNativeEvaluationFailure"
        /\\ \(binding).appendOperation = "_appendNativeOutcome" /\\ \(binding).appended = "$0"
        /\\ \(binding).suppliedAction = \(binding).inputAction /\\ \(binding).visitorAction = \(binding).inputAction
        /\\ \(binding).collector = \(binding).appendTarget /\\ \(binding).collector = \(binding).snapshots
        /\\ \(binding).selector = "_singleNativeOutcome"
        /\\ DOMAIN \(binding).selectorGuards = {1, 2}
        /\\ \(binding).selectorGuards[1].test = "first" /\\ \(binding).selectorGuards[2].test = "count"
        /\\ \(binding).lookupResult = \(binding).lookupBinding
        /\\ \(binding).projection = <<\(binding).writeTarget, "state">>
        /\\ \(binding).captureSource = \(binding).getter
        /\\ \(binding).writeValue = \(binding).selected
        /\\ \(binding).fields = [action |-> \(binding).inputAction, before |-> \(binding).captured, after |-> \(binding).getter]
        BY ONLY \(binding)UsesNoChecking, \(binding)SelectorGuards, <1>visitor, <1>failureGate,
            <1>appendOperation, <1>appended, <1>suppliedAction, <1>inputAction, <1>visitorAction,
            <1>collector, <1>appendTarget, <1>snapshots, <1>selector, <1>lookupResult,
            <1>lookupBinding, <1>projection, <1>writeTarget, <1>captureSource, <1>getter,
            <1>writeValue, <1>selected, <1>fields, <1>captured, IsaM("simp")
    <1>. QED BY ONLY <1>route, <1>sendOrder, <1>callbackSteps, <1>localNames, <1>wiring,
        PTL DEF DecodedSendOperands
    ====

    """.utf8)
}

// Interpret the scalar continuation grammar. Its reads come from the retained Swift.
package func nativeScalarActionEvidence(_ source: String, program: CompiledProgram) throws -> Data {
    let definitions = try nativeScalarActionDefinitions(source, program: program)
    return Data("""
    ---- MODULE SwiftTLANativeActions ----
    \(definitions)
    ====

    """.utf8)
}

func nativeScalarActionDefinitions(_ source: String, program: CompiledProgram,
                                   selectedActionOrdinal: Int? = nil, retainingFailureSites: Bool = false) throws -> String {
    let actions = try decodeScalarActions(source, program: program, predicate: nil)
    if let selectedActionOrdinal, !actions.indices.contains(selectedActionOrdinal) {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    var definitions = ""
    var rows: [String] = []
    var failureSiteColumns: [String] = []
    for (index, action) in actions.enumerated() {
        let plan = action.plans[0]
        let actionValue: String
        if selectedActionOrdinal == index || retainingFailureSites {
            let prefix = retainingFailureSites ? "NativeVisitor\(index + 1)" : "NativeSelected"
            definitions += plan.selectedActionDefinitions(prefix: prefix) + "\n"
            actionValue = prefix + "Action"
            if retainingFailureSites {
                failureSiteColumns.append(prefix + "FailureAppendSites")
            }
        } else {
            actionValue = plan.tla
        }
        rows.append("<<\(TLAValue.string(action.label)), \(actionValue)>>")
    }
    let dispatch = TLAValue.tuple(actions.map { .string($0.formalLabel) })
    let physicalRoutes = actions.map { route in
        "[handle |-> \(TLAValue.string(route.handle)), visitor |-> \(route.visitor), formal |-> \(TLAValue.string(route.formalLabel))]"
    }
    if retainingFailureSites {
        definitions += "NativeActionFailureAppendSites == \(actionTuple(failureSiteColumns))\n"
    }
    return """
    \(definitions)NativeActionRows == \(actionTuple(rows))
    NativeActionDispatchLabels == \(dispatch)
    NativeActionRoutes == \(actionTuple(physicalRoutes))
    """
}

func conditionalArmOperands(_ captures: [OrderedRHSPhysicalAction.Plan], writeOrder: [String],
                            writes: [String: TLAValue], failureAppendSites: [Int]) throws -> TLAValue {
    let plans = captures.map { plan in
        TLAValue.record(["kinds": .tuple(plan.kinds), "literals": .tuple(plan.literals), "reads": .tuple(plan.reads),
                         "left": .tuple(plan.left), "right": .tuple(plan.right)])
    }
    let orderedWrites = try writeOrder.map { target -> TLAValue in
        guard let value = writes[target] else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        return .tuple([.string(target), value])
    }
    return .record(["captures": .tuple(plans), "writes": .tuple(orderedWrites),
                    "failureAppendSites": .tuple(failureAppendSites.map(TLAValue.int))])
}

struct NativeConditionalArmOutput {
    let capturePlans: [OrderedRHSPhysicalAction.Plan]
    let writeOrder: [String]
    let writes: [String: TLAValue]
    let failureAppendSites: [Int]
    let failureCalls: [NativeConditionalFailureCall]

    func operands() throws -> TLAValue {
        try conditionalArmOperands(capturePlans, writeOrder: writeOrder, writes: writes, failureAppendSites: failureAppendSites)
    }
}

struct NativeConditionalActionOutput {
    let children: String
    let plans: String
    let fields: String
    let predicate: [String]
    let ifTrue: NativeConditionalArmOutput
    let ifFalse: NativeConditionalArmOutput
}

/// Keep the reviewed arithmetic, branch selection and history recorder tied to the library source.
func verifyConditionalHistoryHelpers(operations: String, checking: String) throws {
    let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
    func declarations(_ source: String) throws -> [DeclSyntax] {
        let parsed = Parser.parse(source: source)
        guard !parsed.hasError, !source.utf8.contains(0) else { throw invalid }
        return parsed.statements.compactMap { $0.item.as(DeclSyntax.self) }
    }
    func require(_ name: String, _ spelling: String, in declarations: [DeclSyntax]) throws {
        let function = try checked(declarations.compactMap { $0.as(FunctionDeclSyntax.self) }.filter {
            $0.name.text == name
        })
        guard sameWords(syntaxWords(function), spelling) else { throw invalid }
    }

    let library = try declarations(operations)
    let owner = try checked(library.compactMap { $0.as(EnumDeclSyntax.self) }.filter {
        $0.name.text == "_NativeMachineOperations"
    })
    let members = owner.memberBlock.members.map(\.decl)
    try require("_nativeIntAdd", """
        @_documentation(visibility: internal)
        public func _nativeIntAdd(_ lhs: Int, _ rhs: Int) throws -> Int {
            try _NativeMachineOperations.add(lhs, rhs)
        }
        """, in: library)
    try require("add", """
        public static func add(_ lhs: Int, _ rhs: Int) throws -> Int {
            try checked(lhs.addingReportingOverflow(rhs), operation: .addition, operands: [lhs, rhs])
        }
        """, in: members)
    try require("checked", """
        private static func checked(
            _ result: (partialValue: Int, overflow: Bool),
            operation: NativeMachineEvaluationError.IntegerOperation,
            operands: @autoclosure () -> [Int]
        ) throws -> Int {
            guard !result.overflow else { throw NativeMachineEvaluationError.integerOverflow(operation, operands: operands()) }
            return result.partialValue
        }
        """, in: members)
    try require("visitConditional", """
        public static func visitConditional(
            _ condition: () throws -> Bool,
            ifTrue: () throws -> Void,
            ifFalse: () throws -> Void
        ) throws {
            let selected = try condition()
            if selected { try ifTrue() } else { try ifFalse() }
        }
        """, in: members)

    let collector = try declarations(checking)
    let context = try checked(collector.compactMap { $0.as(StructDeclSyntax.self) }.filter {
        $0.name.text == "CheckingContext"
    })
    try require("record", """
        fileprivate mutating func record(_ observation: AssignmentFailureObservation) {
            assignmentFailures?.append(observation)
        }
        """, in: context.memberBlock.members.map(\.decl))
    try require("_recordNativeAlternativeFailure", """
        @_documentation(visibility: internal)
        public func _recordNativeAlternativeFailure<Registers>(
            _ context: inout CheckingContext<Registers>?, action: Int, branch: Int, site: Int, target: Int,
            before: @autoclosure () -> [(binding: Int, target: Int, value: Int)], reason: NativeMachineEvaluationError
        ) {
            guard context?.recordsAlternativeFailures == true else { return }
            let bindings = before().map { NativeAlternativeFailure.Binding(binding: $0.binding, target: $0.target, value: $0.value) }
            context?.record(.alternative(.init(action: action, branch: branch, site: site, target: target,
                                               before: bindings, reason: reason)))
        }
        """, in: collector)
}

func nativeConditionalActionPlans(_ source: String, program: CompiledProgram, predicate: [String]) throws
    -> NativeConditionalActionOutput {
    let row = try checked(decodeScalarActions(source, program: program, predicate: predicate))
    guard let visit = row.visit else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    let names = Dictionary(uniqueKeysWithValues: program.layout.variables.map { ($0.formalName, $0.declaration.name) })
    func sourceName(_ formal: String) throws -> String {
        guard let name = names[formal] else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        return name
    }
    func renamedRead(_ raw: TLAValue) throws -> TLAValue {
        guard case .tuple(let pair) = raw, pair.count == 2,
              pair[0] == .string("state"), case .string(let name) = pair[1] else { return raw }
        return .tuple([.string("state"), .string(try sourceName(name))])
    }
    func arm(_ plan: ActionInstructions) throws -> NativeConditionalArmOutput {
        var writes: [String: TLAValue] = [:]
        var order: [String] = []
        for write in plan.writes {
            let target = try sourceName(write.target)
            guard writes.updateValue(try renamedRead(write.value.wire), forKey: target) == nil else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            order.append(target)
        }
        let captures = try plan.captures.map { capture -> OrderedRHSPhysicalAction.Plan in
            let columns = capture.columns
            return .init(kinds: columns.kinds, literals: columns.literals, reads: try columns.reads.map(renamedRead),
                left: columns.left, right: columns.right)
        }
        return .init(capturePlans: captures, writeOrder: order, writes: writes,
                     failureAppendSites: plan.failureAppendSites, failureCalls: plan.conditionalFailureCalls)
    }
    let first = visit.ifTrue.id, second = visit.ifFalse.id
    return .init(children: "<<\(first), \(second)>>",
        plans: "[child \\in {\(first), \(second)} |-> IF child = \(first) THEN \(row.plans[0].tla) ELSE \(row.plans[1].tla)]",
        fields: TLAValue.set(Set(row.fields.map(TLAValue.string))).description,
        predicate: visit.predicate, ifTrue: try arm(row.plans[0]), ifFalse: try arm(row.plans[1]))
}

private func decodeScalarActions(_ source: String, program: CompiledProgram, predicate: [String]?) throws
    -> [(label: String, formalLabel: String, handle: String, visitor: Int, fields: [String],
         visit: NativeConditionalVisit?, plans: [ActionInstructions])] {

    let parsed = Parser.parse(source: source)
    guard !parsed.hasError, !source.utf8.contains(0), program.layout.parameters.isEmpty else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    let declarations = parsed.statements.compactMap { $0.item.as(DeclSyntax.self) }
    let functions = declarations.compactMap { $0.as(FunctionDeclSyntax.self) }
    let structs = declarations.compactMap { $0.as(StructDeclSyntax.self) }
    let enums = declarations.compactMap { $0.as(EnumDeclSyntax.self) }
    let intType = nativeIntTypeTokens.joined()
    let controlType = "_ControlLocation"
    let slots = nativeVariableSlots(program.layout)
    let fields = try program.layout.variables.map { variable -> ActionField in
        guard let slot = slots[variable.id] else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        switch (variable.declaration.origin, program.variableTypes[variable.id]) {
        case (.source, .int), (.source, .bool):
            let type = program.variableTypes[variable.id] == .int ? intType : boolType
            return .init(name: variable.formalName, slot: slot, ordinal: variable.id.ordinal,
                member: try nativeSourceIdentifier(variable.declaration.name), type: type)
        case (.programCounter, .controlLocation):
            return .init(name: variable.formalName, slot: slot, ordinal: variable.id.ordinal, member: nil, type: controlType)
        default: throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
    }
    let hidden = fields.filter { $0.member == nil }
    let control = predicate == nil ? try checked(hidden) : nil
    let visible = fields.filter { $0.member != nil }
    let locations = program.layout.controlLocations.map {
        (caseName: "location\($0.id.ordinal)", ordinal: $0.id.ordinal, label: $0.formalName)
    }
    guard !visible.isEmpty, hidden.count == (control == nil ? 0 : 1),
          control == nil || !locations.isEmpty else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }

    func require(_ declaration: some SyntaxProtocol, _ spelling: String) throws {
        guard sameWords(syntaxWords(declaration), spelling) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
    }
    @discardableResult
    func checkFunction(_ spelling: String, named name: String, arity: Int,
                       firstLabel: String? = nil) throws -> FunctionDeclSyntax {
        let declaration = try checked(functions.filter {
            $0.name.text == name && $0.signature.parameterClause.parameters.count == arity
                && (firstLabel == nil || $0.signature.parameterClause.parameters.first?.firstName.text == firstLabel)
        })
        try require(declaration, spelling)
        return declaration
    }

    // Validate the exact fields and constructors through which the update is materialized.
    let state = try checked(structs.filter { $0.name.text == "State" })
    let stateMembers = state.memberBlock.members.map(\.decl)
    let stateStorage = visible.map { "public let \($0.member!): \($0.type)" }.joined(separator: "\n")
    let parameters = visible.map { "\($0.member!) _value\($0.ordinal): \($0.type)" }.joined(separator: ", ")
    let assignments = visible.map { "self.\($0.member!) = _value\($0.ordinal)" }.joined(separator: "\n")
    let metadata = try ["displayNames", "fieldIdentities"].map { name in
        try checked(stateMembers.compactMap { $0.as(VariableDeclSyntax.self) }.filter {
            $0.bindings.count == 1 && $0.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name
        })
    }
    try require(state, """
    public struct State: Hashable, GeneratedModelFields {
        \(stateStorage)
        \(metadata[0].description)
        \(metadata[1].description)
        public init(\(parameters)) {
            \(assignments)
        }
    }
    """)
    let controlStorage = control.map { "let \($0.slot): \(controlType)" } ?? ""
    try require(checked(structs.filter { $0.name.text == "Snapshot" }), """
    public struct Snapshot: Hashable, Sendable {
        public let state: State
        \(controlStorage)
    }
    """)
    if control != nil {
        let controlCases = locations.map { "case \($0.caseName) = \($0.ordinal)" }.joined(separator: "\n")
        try require(checked(enums.filter { $0.name.text == controlType }), """
        @_documentation(visibility: internal)
        public enum \(controlType): \(intType), Hashable, Sendable { \(controlCases) }
        """)
    }
    do {
        let table = try checked(declarations.filter {
            $0.as(VariableDeclSyntax.self)?.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?
                .identifier.text == "__swifttlaFormalProjectionTokens"
        })
        let projection = try checked(functions.filter { $0.name.text == "formalProjection" })
        try verifyGeneratedFormalProjectionOutput([table, DeclSyntax(projection)], fields: fields.map { field in
            if let member = field.member {
                let route = "snapshot.state.\(member)"
                let isInt = field.type == intType
                let callee = isInt ? "SwiftTLA._nativeFormalInt" : "SwiftTLA.TLAValue.bool"
                return (formalName: field.name, route: route, type: isInt ? .int : .bool, value: "\(callee)(\(route))")
            }
            let route = "snapshot.\(field.slot)"
            let cases = locations.map {
                "case .\($0.caseName): return SwiftTLA._nativeFormalString(\(String(reflecting: $0.label)))"
            }.joined(separator: "\n")
            let value = "try { () throws -> SwiftTLA.TLAValue in switch \(route) {\n\(cases)\n} }()"
            return (formalName: field.name, route: route, type: .controlLocation, value: value)
        })
    }
    _ = try nativeUpdateSnapshotSlots(structs, fields: fields.map { ($0.member, $0.slot, $0.type) })

    let execution = try checked(declarations.compactMap { $0.as(VariableDeclSyntax.self) }.filter {
        $0.bindings.contains { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "_execution" }
    })
    try require(execution, "private var _execution: Snapshot")
    try require(checked(declarations.compactMap { $0.as(InitializerDeclSyntax.self) }.filter {
        $0.signature.parameterClause.parameters.first?.firstName.text == "execution"
    }), "private init(execution: Snapshot) { _execution = execution }")

    let labels = try scalarActionHandles(declarations)
    let compiledActions = program.layout.actions
    guard labels.count == compiledActions.count,
          compiledActions.enumerated().allSatisfy({ $0.offset == $0.element.id.ordinal }) else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    let qualifiedLabels = try labels.map(nativeSourceIdentifier)
    let formalCall = try checked(functions.filter {
        $0.name.text == "formalCall" && $0.signature.parameterClause.parameters.count == 1
    })
    guard let statement = formalCall.body?.statements.first,
          let choice = (statement.item.as(ExprSyntax.self) ?? statement.item.as(ExpressionStmtSyntax.self)?.expression)?
              .as(SwitchExprSyntax.self) else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    let formalLabels = try choice.cases.map { item in
        guard let branch = item.as(SwitchCaseSyntax.self),
              let returned = branch.statements.first?.item.as(ReturnStmtSyntax.self),
              let call = returned.expression?.as(FunctionCallExprSyntax.self),
              let label = call.arguments.first?.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        return label
    }
    guard formalLabels.elementsEqual(compiledActions.map(\.renderedName), by: {
        $0.utf8.elementsEqual($1.utf8)
    }) else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
    let formalCalls = zip(formalLabels, qualifiedLabels).map {
        "case .\($1): return FormalActionCall(name: \(String(reflecting: $0)), arguments: [])"
    }.joined(separator: "\n")
    try require(formalCall, """
    public func formalCall(for action: Action) throws -> FormalActionCall { switch action { \(formalCalls) } }
    """)
    let checking = "checking context: inout CheckingContext<CheckingRegisters>?"
    let candidateCalls = qualifiedLabels.map { "do { try visit(.\($0)) }" }.joined(separator: "\n")
    try checkFunction("""
    private func _visitActionCandidates(_ visit: (Action) throws -> Void) throws { \(candidateCalls) }
    """, named: "_visitActionCandidates", arity: 1)
    let dispatch = try checked(functions.filter {
        $0.name.text == "_visitSuccessors" && $0.signature.parameterClause.parameters.first?.firstName.text == "for"
    })
    let physicalRoutes = try scalarDispatchRoutes(dispatch, handles: labels)
    guard physicalRoutes.allSatisfy({ $0.receiver == "_execution" }) else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }

    let rows = try compiledActions.enumerated().map { index, action in
        let visitor = try checked(functions.filter { $0.name.text == "_visitUpdates\(index)" })
        let decoded = try decodeScalarActionVisitor(visitor, index: index, fields: fields, control: control,
            locations: locations.map { ($0.caseName, $0.label) }, checking: checking, predicate: predicate, program: program)
        let successor = try checked(functions.filter { $0.name.text == "_visitSuccessors\(index)" })
        try verifyGeneratedSuccessorOutput(DeclSyntax(successor), actionID: index, parameters: "", arguments: "",
            configurationParameters: "", configurationArguments: "")
        return (label: action.declaration.name, formalLabel: formalLabels[index], handle: labels[index],
            visitor: physicalRoutes[index].visitor, fields: fields.map(\.name), visit: decoded.visit, plans: decoded.plans)
    }
    try checkNativeValidationActionRoute(functions)
    return rows
}

struct NativeConditionalFailureCall {
    struct Preceding {
        let binding: Int
        let target: Int
        let local: String
    }

    let action: Int
    let branch: Int
    let site: Int
    let target: Int
    let before: [Preceding]

    fileprivate static func decode(_ item: CodeBlockItemSyntax) -> Self? {
        func reference(_ expression: ExprSyntax?) -> String? {
            guard let reference = expression?.as(DeclReferenceExprSyntax.self), reference.argumentNames == nil else { return nil }
            return reference.baseName.text
        }
        func ordinal(_ expression: ExprSyntax) -> Int? {
            guard let spelling = expression.as(IntegerLiteralExprSyntax.self)?.literal.text,
                  let value = Int(spelling), value >= 0, spelling == String(value) else { return nil }
            return value
        }
        let expression = item.item.as(ExprSyntax.self) ?? item.item.as(ExpressionStmtSyntax.self)?.expression
        guard let call = expression?.as(FunctionCallExprSyntax.self), !call.hasError,
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              syntaxWords(call.calledExpression) == ["SwiftTLA", ".", "_recordNativeAlternativeFailure"] else { return nil }
        let arguments = Array(call.arguments)
        guard arguments.map({ $0.label?.text }) == [nil, "action", "branch", "site", "target", "before", "reason"],
              let context = arguments[0].expression.as(InOutExprSyntax.self), reference(context.expression) == "context",
              let action = ordinal(arguments[1].expression), let branch = ordinal(arguments[2].expression),
              let site = ordinal(arguments[3].expression), let target = ordinal(arguments[4].expression),
              let bindings = arguments[5].expression.as(ArrayExprSyntax.self),
              reference(arguments[6].expression) == "failure" else { return nil }
        var before: [Preceding] = []
        for binding in bindings.elements {
            guard let tuple = binding.expression.as(TupleExprSyntax.self) else { return nil }
            let fields = Array(tuple.elements)
            guard fields.map({ $0.label?.text }) == ["binding", "target", "value"],
                  let binder = ordinal(fields[0].expression), let key = ordinal(fields[1].expression),
                  let local = reference(fields[2].expression) else { return nil }
            before.append(.init(binding: binder, target: key, local: local))
        }
        return .init(action: action, branch: branch, site: site, target: target, before: before)
    }
}

private func decodeScalarActionVisitor(_ visitor: FunctionDeclSyntax, index: Int,
    fields: [ActionField], control: ActionField?, locations: [(caseName: String, label: String)],
    checking: String, predicate: [String]?, program: CompiledProgram) throws
    -> (visit: NativeConditionalVisit?, plans: [ActionInstructions]) {
    let parts = visitor.body?.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }.filter {
        $0.name.text.hasPrefix("_actionPart")
    } ?? []
    let names = parts.map { $0.name.text }
    guard !parts.isEmpty, Set(names).count == names.count,
          names.allSatisfy({ Int($0.dropFirst("_actionPart".count)) != nil }) else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    let expected = """
    private static func _visitUpdates\(index)(from state: Snapshot, \(checking),
        _ _emit: (_Updates) throws -> Void) throws -> [NativeMachineEvaluationError] {
        var failures: [NativeMachineEvaluationError] = []
        func emit(_ update: _Updates) throws {
            do { try _emit(update) }
            catch { throw _StopSuccessorTraversal(cause: error) }
        }
        \(parts.map(\.description).joined(separator: "\n"))
        do { try _actionPart0(_Updates(), emit) }
        catch let stop as _StopSuccessorTraversal {
            if let cause = stop.cause { throw cause }
            throw stop
        }
        return failures
    }
    """
    guard sameWords(syntaxWords(visitor), expected) else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    let byName = Dictionary(uniqueKeysWithValues: zip(names, parts))
    let action = program.layout.actions[index].id
    let regions = predicate == nil ? [] : program[action].body.orderedAlternativeFailureRegions
    var visited: Set<String> = []
    let stateReads: [(String, ActionReference)] = fields.map {
        ($0.before, .init(kind: "state", value: .string($0.name), type: $0.type))
    }
    let controlValues = control.map { field in
        locations.map {
            ("\(field.type).\($0.caseName)", ActionReference(kind: "control", value: .string($0.label), type: field.type))
        }
    } ?? []
    let booleanValues = [("true", true), ("false", false)].map {
        ($0.0, ActionReference(kind: "literal", value: .bool($0.1), type: boolType))
    }

    typealias Binding = (local: String, value: ActionReference)
    func partCore(_ name: String, scope: [Binding], region: AlternativeFailureRegion? = nil) throws
        -> (tokens: [String], recordsFailure: Bool, conditionalFailure: NativeConditionalFailureCall?) {
        guard let part = byName[name], let body = part.body, visited.insert(name).inserted else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let formal = scope.map { "_ \($0.local): \($0.value.type), " }.joined()
        let tokens = syntaxWords(body)
        let prefix = words("{ do {")
        let handler = "} catch let failure as NativeMachineEvaluationError where failure.isModelEvaluationFailure {"
        let append = "failures.append(failure) } }"
        let lexical = scope.map(\.local)
        let recording: String
        let conditionalFailure: NativeConditionalFailureCall?
        if predicate != nil,
           let actionPart = body.statements.first?.item.as(DoStmtSyntax.self),
           let catchBody = actionPart.catchClauses.first?.body.statements, catchBody.count == 2,
           let observer = catchBody.first {
            guard let decoded = NativeConditionalFailureCall.decode(observer), let region,
                  decoded.action == action.ordinal, decoded.branch == region.armOrdinal,
                  decoded.before.count == lexical.count, lexical.count < region.bindings.count else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            let expectedSite = region.bindings[lexical.count]
            guard region.index(of: expectedSite.binder) == lexical.count,
                  decoded.site == expectedSite.binder.ordinal, decoded.target == expectedSite.target.ordinal,
                  let name = program.binderNames[expectedSite.binder], tokens.count > prefix.count + 1,
                  tokens[prefix.count] == "let", tokens[prefix.count + 1] == "_\(name)_\(expectedSite.binder.ordinal)"
            else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
            for (offset, observed) in decoded.before.enumerated() {
                let scheduled = region.bindings[offset]
                guard let name = program.binderNames[scheduled.binder], observed.local == lexical[offset],
                      observed.local == "_\(name)_\(scheduled.binder.ordinal)",
                      observed.binding == scheduled.binder.ordinal, observed.target == scheduled.target.ordinal
                else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
            }
            conditionalFailure = decoded
            recording = observer.description + "\n"
        } else if predicate == nil {
            conditionalFailure = nil
            let linear = nativeOrderedIntAssignmentFailureSource(actionOrdinal: index, preceding: lexical)
            let observed = words("\(handler)\n\(linear)\n\(append)")
            recording = tokens.suffix(observed.count).elementsEqual(observed) ? linear + "\n" : ""
        } else {
            conditionalFailure = nil
            recording = ""
        }
        let suffix = words("\(handler)\n\(recording)\(append)")
        guard tokens.count > prefix.count + suffix.count else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let core = Array(tokens.dropFirst(prefix.count).dropLast(suffix.count))
        let signature = "func \(name)(\(formal)_ updates: _Updates, _ emit: (_Updates) throws -> Void) throws"
        guard sameWords(syntaxWords(part), """
            \(signature) {
                do { \(core.joined(separator: " ")) }
                catch let failure as NativeMachineEvaluationError where failure.isModelEvaluationFailure {
                    \(recording)failures.append(failure)
                }
            }
            """) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }

        return (core, !recording.isEmpty, conditionalFailure)
    }

    func walk(_ entry: String, region: AlternativeFailureRegion? = nil) throws -> ActionInstructions {
        var instructions = ActionInstructions()
        var capturesFollowGuard = true
        let entryGuards = predicate == nil ? 1 : 0
        var pending: [(String, [Binding])] = [(entry, [])]
        parts: while let (name, scope) = pending.popLast() {
            let (core, recordsFailure, conditionalFailure) = try partCore(name, scope: scope, region: region)
            guard !recordsFailure || (core.first == "let"
                && scope.allSatisfy({ $0.value.type == nativeIntTypeTokens.joined() })) else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            let argument = scope.map { "\($0.local), " }.joined()
            if sameWords(core, "try emit(updates)") { continue }
            if let control {
                for location in locations where sameWords(core, """
                    guard (\(control.before) == \(control.type).\(location.caseName)) else { return }
                    try emit(updates)
                    """) {
                    instructions.guards.append(TLAValue.string(location.label).description)
                    continue parts
                }
            }
            let boundReads = scope.map { ($0.local, $0.value) }
            if core.count > 2, core[0] == "let",
               let call = core.lastIndex(of: "try"), call + 1 < core.count, byName[core[call + 1]] != nil {
                let local = try nativeSourceIdentifier(core[1])
                let child = core[call + 1]
                guard !scope.contains(where: { $0.local == local }) else {
                    throw InitialFailureEvidenceError.unsupportedGeneratedOutput
                }
                guard core[2] == "=", call > 3 else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
                let rhs = Array(core[3..<call])
                capturesFollowGuard = capturesFollowGuard
                    && instructions.guards.count == entryGuards && instructions.writes.isEmpty
                    && scope.count == instructions.captures.count
                    && scope.enumerated().allSatisfy { offset, binding in
                        binding.value.kind == "capture" && binding.value.operand == String(offset + 1)
                    }
                if recordsFailure || predicate != nil {
                    let intType = nativeIntTypeTokens.joined()
                    let reads = (stateReads + boundReads).filter { $0.1.type == intType }
                    let references = Dictionary(uniqueKeysWithValues: reads.enumerated().map { (words($0.element.0), String($0.offset)) })
                    if let decoded = decodeNativeOrderedIntExpression(rhs[...], reads: references),
                       decoded.consumed == rhs.count, decoded.steps.count > 1,
                       sameWords(core, """
                       let \(local) = \(rhs.joined(separator: " "))
                       try \(child)(\(argument)\(local), updates, emit)
                       """) {
                        guard recordsFailure else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
                        instructions.captures.append(.expression(try nativeArithmeticCapture(decoded.steps, reads: reads.map { $0.1 })))
                        // The verified catch appends the reached error; the continuation requires a completed capture.
                        let index = instructions.captures.count
                        instructions.failureAppendSites.append(index)
                        if let conditionalFailure {
                            instructions.conditionalFailureCalls.append(conditionalFailure)
                        }
                        let reference = ActionReference(kind: "capture", value: .int(index), type: intType)
                        pending.append((child, scope + [(local, reference)]))
                        continue parts
                    }
                    guard !recordsFailure else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
                }
                var reads = stateReads + boundReads + booleanValues
                let integer: Int?
                if sameWords(rhs, "SwiftTLA._nativeIntMinimum()") {
                    integer = Int.min
                } else if let value = Int(rhs.joined()), sameWords(rhs, String(value)) {
                    integer = value
                } else {
                    integer = nil
                }
                if let integer {
                    reads.append((rhs.joined(), .init(kind: "literal", value: .int(integer),
                                                       type: nativeIntTypeTokens.joined())))
                }
                for (spelling, value) in reads where
                    sameWords(core, "let \(local) = \(spelling)\ntry \(child)(\(argument)\(local), updates, emit)") {
                    instructions.captures.append(.reference(value))
                    let reference = ActionReference(kind: "capture", value: .int(instructions.captures.count), type: value.type)
                    pending.append((child, scope + [(local, reference)]))
                    continue parts
                }
            }
            guard !recordsFailure else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
            if core.count > 2, core[0] == "try", byName[core[1]] != nil,
               let nextCall = core.lastIndex(of: "try"), nextCall > 0, nextCall + 1 < core.count,
               byName[core[nextCall + 1]] != nil {
                let first = core[1]
                let next = core[nextCall + 1]
                if sameWords(core, "try \(first)(\(argument)updates, { candidate in try \(next)(\(argument)candidate, emit) })") {
                    pending.append((next, scope))
                    pending.append((first, scope))
                    continue parts
                }
            }
            let operands = stateReads + controlValues + boundReads + booleanValues
            for field in fields {
                for (spelling, value) in operands where value.type == field.type &&
                    sameWords(core, "if let merged = updates.merging(_Updates(\(field.slot): \(spelling))) { try emit(merged) }") {
                    instructions.writes.append(.init(target: field.name, value: value))
                    continue parts
                }
            }
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        // A selected conditional arm has already passed the checked branch decision.
        guard instructions.failureAppendSites.isEmpty || (capturesFollowGuard && instructions.guards.count == entryGuards) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        return instructions
    }

    let visit: NativeConditionalVisit?
    let plans: [ActionInstructions]
    if let predicate {
        let (root, recordsFailure, _) = try partCore("_actionPart0", scope: [])
        let body = byName["_actionPart0"]?.body?.statements.first?.item.as(DoStmtSyntax.self)?.body.statements
        guard !recordsFailure, body?.count == 1, let item = body?.first?.item,
              let expression = item.as(TryExprSyntax.self) ?? item.as(ExpressionStmtSyntax.self)?.expression.as(TryExprSyntax.self),
              syntaxWords(expression) == root, let conditional = nativeConditionalVisit(Syntax(expression)),
              conditional.predicate == predicate, conditional.ifTrue.arguments == ["updates", "emit"],
              conditional.ifFalse.arguments == ["updates", "emit"] else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        visit = conditional
        plans = try [walk("_actionPart\(conditional.ifTrue.id)", region: regions.first { $0.armOrdinal == 0 }),
                     walk("_actionPart\(conditional.ifFalse.id)", region: regions.first { $0.armOrdinal == 1 })]
    } else {
        visit = nil
        plans = try [walk("_actionPart0")]
    }
    guard visited.count == parts.count else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
    return (visit, plans)
}

private func checkNativeValidationActionRoute(_ functions: [FunctionDeclSyntax]) throws {
    let publicRoute = try checked(functions.filter { $0.name.text == "visitValidationOutcomes" })
    let nativeRoute = try checked(functions.filter {
        $0.name.text == "_visitSuccessors"
            && $0.signature.parameterClause.parameters.first?.firstName.text == "checking"
            && $0.signature.parameterClause.parameters.count == 3
    })
    let callback = "(Action, Self) throws -> SwiftTLA.TLAValue.BooleanLiteralType"
    let failureCallback = "(Action, NativeMachineEvaluationError) throws -> SwiftTLA.TLAValue.BooleanLiteralType"
    try verifyGeneratedValidationDelegationOutput(DeclSyntax(publicRoute))
    guard sameWords(syntaxWords(nativeRoute), """
        private func _visitSuccessors(checking context: inout CheckingContext<CheckingRegisters>?,
            _ visit: \(callback), onEvaluationFailure: \(failureCallback)) throws -> SwiftTLA.TLAValue.BooleanLiteralType {
            var found = false
            do {
                func _visitAction(_ action: Action) throws {
                    var callbackFailed = false
                    var failures: [NativeMachineEvaluationError] = []
                    do {
                        failures = try _visitSuccessors(for: action, checking: &context) { execution in
                            found = true
                            do {
                                if try !visit(action, Self(execution: execution)) {
                                    throw _StopSuccessorTraversal()
                                }
                            } catch {
                                callbackFailed = true
                                throw error
                            }
                        }
                    } catch let reason as NativeMachineEvaluationError where !callbackFailed && reason.isModelEvaluationFailure {
                        failures.append(reason)
                    } catch {
                        throw error
                    }
                    for reason in failures {
                        if try !onEvaluationFailure(action, reason) {
                            throw _StopSuccessorTraversal()
                        }
                    }
                }
                try _visitActionCandidates(_visitAction)
            } catch is _StopSuccessorTraversal {}
            return found
        }
        """) else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
}
