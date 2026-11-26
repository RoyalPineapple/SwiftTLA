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
    case reference(ActionReference, local: String)
    case expression(ArithmeticCapturePlan, local: String)

    var declaredLocal: String {
        switch self {
        case .reference(_, let local), .expression(_, let local): local
        }
    }

    var tag: String {
        switch self {
        case .reference(let reference, _): reference.kind
        case .expression: "expression"
        }
    }

    var tla: String {
        switch self {
        case .reference(let reference, _): reference.tla
        case .expression(let plan, _): "<<\"expression\", \(plan.tla)>>"
        }
    }

    var columns: ArithmeticCapturePlan {
        switch self {
        case .reference(let reference, _):
            let literal = reference.kind == "literal"
            return ArithmeticCapturePlan(kinds: [.string(literal ? "literal" : "read")],
                literals: [literal ? reference.value : .int(0)],
                reads: [literal ? .tuple([]) : reference.wire], left: [.int(0)], right: [.int(0)])
        case .expression(let plan, _):
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
    var disabled = false

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

struct SequentialNativeProof {
    let definitions: String
    let theorem: String
    let hasFullFailures: Bool
}

func sequentialNativeProof(_ source: String, program: CompiledProgram) throws -> SequentialNativeProof {
    let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
    let rows = try decodeScalarActions(source, program: program, predicate: nil, controlledFork: true)
    guard !rows.isEmpty, Set(rows.map(\.visitor)) == Set(1...rows.count),
          Set(rows.map(\.label)).count == rows.count,
          let counter = program.layout.variables.first(where: { $0.declaration.origin == .programCounter }),
          program.layout.variables.filter({ $0.declaration.origin == .source })
            .allSatisfy({ program.variableTypes[$0.id] == .int }) else { throw invalid }
    let fields = program.layout.variables.map(\.formalName)
    let keys = TLAValue.set(Set(fields.map(TLAValue.string)))
    let integerFields = TLAValue.set(Set(fields.filter { $0 != counter.formalName }.map(TLAValue.string)))
    let readPrefixes = try program.layout.variables.filter { $0.declaration.origin == .source }.map {
        (words("state.state.\(try nativeSourceIdentifier($0.declaration.name))"), $0.formalName)
    }
    func comparison(_ predicate: [String]) throws -> String {
        guard predicate.first == "(", predicate.last == ")" else { throw invalid }
        let terms = predicate.dropFirst().dropLast()
        let operators = ["<": "<", "<=": "<=", ">": ">", ">=": ">=", "==": "=", "!=": "#"]
        guard let pivot = terms.firstIndex(where: { operators[$0] != nil }),
              let relation = operators[terms[pivot]] else { throw invalid }
        func operand(_ tokens: ArraySlice<String>) throws -> String {
            if let state = readPrefixes.first(where: { tokens.elementsEqual($0.0) }) { return state.1 }
            if let number = Int(tokens.joined()), sameWords(Array(tokens), String(number)) {
                return TLAValue.int(number).description
            }
            throw invalid
        }
        return try "(\(operand(terms[..<pivot])) \(relation) \(operand(terms[(pivot + 1)...])))"
    }
    func snapshot(_ suffix: String) -> String {
        let cases = fields.map { "key = \(TLAValue.string($0)) -> \($0)\(suffix)" }
        return "[key \\in \(keys) |-> CASE \(cases.joined(separator: " [] "))]"
    }
    let formalLabels = TLAValue.tuple(rows.map { .string($0.formalLabel) })
    let authoredLabels = TLAValue.tuple(rows.map { .string($0.label) })
    let routes = actionTuple(rows.map {
        "[handle |-> \(TLAValue.string($0.handle)), formal |-> \(TLAValue.string($0.formalLabel)), visitor |-> \($0.visitor)]"
    })
    var actionDefinitions: [String] = []
    var actionSteps: [String] = []
    var actionFacts: [String] = []
    var failureSteps: [String] = []
    var failureFacts: [String] = []
    var fullFailureConclusions: [String] = []
    var fullFailureSteps: [String] = []
    var fullFailureFacts: [String] = []
    var nativeActions: [String] = []
    var failureActions: [String] = []
    var rhsProofs: [String] = []
    var rhsFacts: [String] = []
    for (index, row) in rows.enumerated() {
        let name = "NativeSequentialVisitor\(index + 1)"
        var plans: [String] = []
        var steps: [String] = []
        var failures: [String] = []
        var rhsDefinitions: [String] = []
        var rhsDefinitionNames: [String] = []
        var materializationFacts: [String] = []
        for (arm, plan) in row.plans.enumerated() {
            let prefix = name + "Arm\(arm + 1)"
            guard plan.guards.count == 1,
                  plan.writes.allSatisfy({ fields.contains($0.target) }),
                  plan.failureAppendSites.allSatisfy({ $0 > 0 && $0 <= plan.captures.count })
            else { throw invalid }
            plans.append(prefix + "Plan == \(plan.tla)")
            let captured = prefix + "Capture"
            plans.append("\(captured)0 == NativeSequentialRule!NativeAssignmentStart")
            for slot in plan.captures.indices {
                let previous = "\(captured)\(slot)"
                let next = "\(captured)\(slot + 1)"
                let rhs = "\(next)Rhs"
                let checkedRHS = nativeSequentialRhsProof(
                    rhs, capture: plan.captures[slot], armPlan: prefix + "Plan",
                    slot: slot + 1, previous: previous, ordinal: rhsFacts.count + 1
                )
                rhsDefinitions += checkedRHS.definitions
                rhsDefinitionNames += checkedRHS.names
                rhsProofs.append(checkedRHS.proof)
                rhsFacts.append(checkedRHS.conclusion)
                plans.append("""
                \(next) ==
                    NativeSequentialRule!NativeAssignmentStep(NativeSequentialBefore,
                        NativeSequentialRule!NativeAssignmentRhsPlan(\(prefix)Plan.captures[\(slot + 1)]), \(slot + 1), \(previous))
                """)
            }
            let final = "\(captured)\(plan.captures.count)"
            guard plan.failureAppendSites.count == plan.conditionalFailureCalls.count else { throw invalid }
            let calls = try zip(plan.failureAppendSites, plan.conditionalFailureCalls).map { slot, call -> String in
                guard call.location == .arm(arm), call.action == index,
                      call.before.count == slot - 1 else { throw invalid }
                let before = actionTuple(call.before.enumerated().map { prior, binding in
                    "[slot |-> \(prior + 1), binding |-> \(binding.binding), target |-> \(binding.target)]"
                })
                return "slot = \(slot) -> [action |-> \(call.action), branch |-> \(arm), "
                    + "site |-> \(call.site), target |-> \(call.target), before |-> \(before)]"
            }
            let sites = TLAValue.set(Set(plan.failureAppendSites.map(TLAValue.int)))
            let dispatch = calls.isEmpty ? "slot" : "CASE " + calls.joined(separator: " [] ")
            let appendCalls = "[slot \\in \(sites) |-> \(dispatch)]"
            let emits = plan.disabled ? "FALSE" : #"""
            IF \#(prefix)Reached THEN
                IF \#(final).failure = <<>> THEN
                    NativeSequentialRule!NativePendingMergesEmit(NativeSequentialFields, NativeSequentialBefore, NativeSequentialAfter,
                        Len(\#(prefix)Plan.writes), \#(prefix)Writes)
                ELSE FALSE
            ELSE FALSE
            """#
            plans.append(#"""
            \#(prefix)Reached == \#(counter.formalName) = \#(prefix)Plan.guards[1]
            \#(prefix)Writes == NativeSequentialRule!NativeCopyWrites(\#(prefix)Plan, NativeSequentialBefore, \#(final).completed)
            \#(prefix)Emits ==
            \#(emits.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n"))
            \#(prefix)AppendCalls == \#(appendCalls)
            \#(prefix)RecordedFailure(recording) ==
                LET reached == \#(final)
                    calls == \#(prefix)AppendCalls
                IN IF recording /\ \#(prefix)Reached THEN
                       IF reached.failure # <<>> THEN
                           IF reached.failure.site \in DOMAIN calls THEN
                               LET call == calls[reached.failure.site]
                               IN <<[action |-> call.action, branch |-> call.branch,
                                     site |-> call.site, target |-> call.target, payload |-> reached.failure.payload,
                                     before |-> [i \in DOMAIN call.before |->
                                         [binding |-> call.before[i].binding, target |-> call.before[i].target,
                                          value |-> reached.completed[call.before[i].slot]]]]>>
                           ELSE <<>>
                       ELSE <<>>
                   ELSE <<>>
            \#(prefix)Failure ==
                LET recorded == \#(prefix)RecordedFailure(TRUE)
                IN IF recorded = <<>> THEN <<>>
                   ELSE <<[label |-> \#(TLAValue.string(row.label)), pc |-> \#(counter.formalName),
                           site |-> \#(final).failure.site, payload |-> recorded[1].payload,
                           completed |-> [i \in DOMAIN recorded[1].before |-> recorded[1].before[i].value]]>>
            """#)
            let fact = "<2>frame\(arm + 1)"
            actionSteps.append(#"""
                \#(fact). NativeSequentialRule!NativePendingMergesEmit(NativeSequentialFields, NativeSequentialBefore,
                    NativeSequentialAfter, Len(\#(prefix)Plan.writes), \#(prefix)Writes)
                    <=> NativeSequentialRule!NativePendingWriteConstraints(NativeSequentialFields, NativeSequentialBefore,
                        NativeSequentialAfter, Len(\#(prefix)Plan.writes), \#(prefix)Writes)
                <3>count. Len(\#(prefix)Plan.writes) \in Nat
                    BY ONLY SMT DEF \#(prefix)Plan
                <3>targets. \A slot \in 1..Len(\#(prefix)Plan.writes) :
                    \#(prefix)Writes[slot][1] \in NativeSequentialFields
                    BY ONLY SMT DEF NativeSequentialFields, \#(prefix)Plan, \#(prefix)Writes,
                        NativeSequentialRule!NativeCopyWrites
                <3>. QED BY ONLY <3>count, <3>targets,
                    NativeSequentialRule!PendingMergeFoldMaterializesExactlyTheCompatibleWrites, SMT
            """#)
            materializationFacts.append(fact)
            steps.append(prefix + "Emits")
            failures.append(prefix + "Failure")
        }
        let selector = try row.visit.map { try comparison($0.predicate) }
        let event: String
        let errors: String
        if let guardText = selector {
            guard steps.count == 2, failures.count == 2 else { throw invalid }
            event = "IF \(name)Arm1Reached THEN (IF \(guardText) THEN \(steps[0]) ELSE \(steps[1])) ELSE FALSE"
            errors = "IF \(name)Arm1Reached THEN (IF \(guardText) THEN \(failures[0]) ELSE \(failures[1])) ELSE <<>>"
        } else {
            event = try checked(steps)
            errors = try checked(failures)
        }
        actionDefinitions += plans + rhsDefinitions
        actionDefinitions.append("\(name) == \(event)")
        actionDefinitions.append("\(name)Failures == \(errors)")
        nativeActions.append(name)
        failureActions.append(name + "Failures")
        let fact = "<1>action\(index + 1)"
        actionFacts.append(fact)
        let planDefinitions = plans.flatMap { block in
            block.split(separator: "\n").compactMap { line -> Substring? in
                guard line.hasPrefix(name), line.contains(" ==") else { return nil }
                return line.prefix { $0 != "(" && $0 != " " }
            }
        }.joined(separator: ", ")
        actionSteps.insert(#"""
            \#(fact). \#(name) <=> \#(row.formalLabel)
            """#, at: actionSteps.count - materializationFacts.count)
        let rhsExpansion = (rhsDefinitionNames + [
            "NativeSequentialRule!GeneratedNode", "NativeSequentialRule!GeneratedCombine",
            "NativeSequentialRule!GeneratedAdd", "NativeSequentialRule!GeneratedAddDefined",
            "NativeSequentialRule!Success", "NativeSequentialRule!GeneratedOverflow",
            "NativeSequentialRule!PhysicalRhsReadIndices", "NativeSequentialRule!PhysicalRhsBindings",
            "NativeSequentialRule!CopyReferenceValue", "NativeSequentialRule!NativeAssignmentRhsPlan"
        ]).joined(separator: ", ")
        let failureFact = "<1>failure\(index + 1)"
        failureFacts.append(failureFact)
        let authoredFailure = "AuthoredSequentialActionFailure\(index + 1)"
        let authoredBranches = row.plans.indices.map { "\(authoredFailure)Branch\($0 + 1)" }.joined(separator: ", ")
        failureSteps.append(#"""
            \#(failureFact). \#(name)Failures = AuthoredSequentialVisitorFailure(\#(index + 1))
                BY ONLY AuthoredSequentialTypedEntry, NativeSequentialDecodedRhsOutcomes, NativeSequentialRule!CheckedAdditionRule, SMT
                    DEF AuthoredSequentialTypedEntry, AuthoredSequentialMachineInts, AuthoredSequentialVisitorFailure,
                        \#(authoredFailure), \#(authoredBranches), \#(name)Failures, \#(planDefinitions), NativeSequentialBefore,
                        NativeSequentialRule!NativeAssignmentStart, NativeSequentialRule!NativeAssignmentStep,
                        \#(rhsExpansion)
            """#)
        let action = program.layout.actions[index].id
        let regions = program[action].body.orderedAlternativeFailureRegions(afterControlGuardOf: counter.id)
        if regions.filter({ !$0.bindings.isEmpty }).count == 1 {
            guard regions.count == row.plans.count else { throw invalid }
            for (arm, region) in regions.enumerated() where !region.bindings.isEmpty {
                let prefix = name + "Arm\(arm + 1)"
                let source = "TLASequentialAuthoredHistory\(index + 1)Arm\(arm + 1)"
                let sourceFailure = "AuthoredSequentialActionFailure\(index + 1)Branch\(arm + 1)"
                guard row.plans.enumerated().allSatisfy({ $0.offset == arm || $0.element.failureAppendSites.isEmpty })
                else { throw invalid }
                let active = selector.map { arm == 0 ? $0 : "~" + $0 }
                let recorded = "\(prefix)RecordedFailure(TRUE)"
                let observed = active.map { "IF \(name)Arm1Reached /\\ \($0) THEN \(recorded) ELSE <<>>" } ?? recorded
                let conclusion = #"""
                LET observed == \#(observed)
                    authored == \#(source)
                IN /\ DOMAIN observed = DOMAIN authored
                   /\ \A i \in DOMAIN authored :
                       observed[i] = [action |-> authored[i].action, branch |-> authored[i].branch,
                           site |-> authored[i].site, target |-> authored[i].target,
                           payload |-> authored[i].payload, before |-> authored[i].before]
                """#
                let otherSourceBranches = row.plans.indices.filter { $0 != arm }.map { "\(authoredFailure)Branch\($0 + 1)" }
                let sourceDispatchDefinitions = ([authoredFailure] + otherSourceBranches).joined(separator: ", ")
                let capture = "\(prefix)Capture\(row.plans[arm].captures.count)"
                let recorder = "\(prefix)RecordedFailure"
                let callback = "\(prefix)AppendCalls"
                let otherRecorders = row.plans.indices.filter { $0 != arm }.flatMap { other in
                    ["Reached", "Failure", "RecordedFailure", "AppendCalls"].map { "\(name)Arm\(other + 1)\($0)" }
                }
                let dispatchDefs = (["\(name)Failures", "\(prefix)Failure"] + otherRecorders).joined(separator: ", ")
                let callbackSites = row.plans[arm].failureAppendSites
                let siteFacts = callbackSites.map { "<3>site\($0)" }
                let facts = (siteFacts.isEmpty ? "" : siteFacts.joined(separator: ", ") + ", ")
                let slotProofs = callbackSites.map { slot in
                    """
                            <3>site\(slot). active /\\ \(capture).failure.site = \(slot) => observed[1] = expected
                                BY ONLY <2>selected, SMT
                                    DEF active, expected, observed, authored, \(source), \(recorder), \(callback), \(prefix)Failure
                    """
                }.joined(separator: "\n")
                let fact = "<1>full\(index + 1)arm\(arm + 1)"
                let predicateLines = conclusion.split(separator: "\n").map { "    " + $0 }
                fullFailureConclusions.append("    /\\ (\n" + predicateLines.joined(separator: "\n") + "\n    )")
                fullFailureFacts.append(fact)
                fullFailureSteps.append(#"""
                \#(fact).
                \#(predicateLines.joined(separator: "\n"))
                    <2>payload. \#(name)Failures = \#(sourceFailure)
                        BY ONLY AuthoredSequentialTypedEntry, NativeSequentialDispatchUsesAuthoredFailures, SMT
                            DEF NativeSequentialLabeledFailures, NativeSequentialRoutes, NativeSequentialAuthoredLabels,
                                NativeSequentialFailures, AuthoredSequentialLabels, AuthoredSequentialFirstFailure,
                                AuthoredSequentialVisitorFailure, \#(sourceDispatchDefinitions)
                    <2>. DEFINE observed == \#(observed)
                                 authored == \#(source)
                                 active == \#(sourceFailure) # <<>>
                                 expected == [action |-> authored[1].action, branch |-> authored[1].branch,
                                     site |-> authored[1].site, target |-> authored[1].target,
                                     payload |-> authored[1].payload, before |-> authored[1].before]
                    <2>projection. active => /\ observed = \#(recorder)(TRUE)
                                             /\ observed # <<>>
                                             /\ \#(sourceFailure) = \#(prefix)Failure
                        BY ONLY <2>payload, SMT DEF active, observed, \#(dispatchDefs)
                    <2>empty. ~active => observed = <<>> /\ authored = <<>>
                        BY ONLY <2>payload, SMT DEF active, observed, authored, \#(source), \#(dispatchDefs)
                    <2>selected. active => /\ \#(capture).failure.site \in \#(TLAValue.set(Set(callbackSites.map(TLAValue.int))))
                                           /\ observed = \#(recorder)(TRUE)
                                           /\ \#(sourceFailure) = \#(prefix)Failure
                        BY ONLY <2>projection, SMT DEF \#(recorder), \#(callback)
                    <2>domains. active => DOMAIN observed = {1} /\ DOMAIN authored = {1}
                        BY ONLY <2>projection, SMT DEF active, authored, \#(source), \#(recorder)
                    <2>record. active => observed[1] = expected
                    \#(slotProofs)
                        <3>. QED BY ONLY <2>selected, \#(facts)SMT
                    <2>. QED BY ONLY <2>empty, <2>domains, <2>record, SMT DEF observed, authored, expected
                """#)
            }
        }
        actionSteps.append(#"""
                <2>. QED BY ONLY AuthoredSequentialTypedEntry, NativeSequentialDecodedRhsOutcomes, \#(materializationFacts.joined(separator: ", ")), SMT
                    DEF \#(name), \#(row.formalLabel), \#(planDefinitions), AuthoredSequentialTypedEntry, AuthoredSequentialMachineInts,
                        NativeSequentialBefore, NativeSequentialAfter, NativeSequentialFields,
                        NativeSequentialRule!NativeAssignmentStart, NativeSequentialRule!NativeAssignmentStep,
                        \#(rhsExpansion),
                        NativeSequentialRule!NativePendingWriteConstraints, NativeSequentialRule!PendingWriteKeys,
                        NativeSequentialRule!NativeCopyWrites, NativeSequentialRule!NativeCopyValue, NativeSequentialRule!CopyReferenceValue
            """#)
    }
    let actual = actionTuple(rows.map(\.formalLabel))
    let rhsTheorem: String
    if rhsFacts.isEmpty {
        rhsTheorem = "LOCAL THEOREM NativeSequentialDecodedRhsOutcomes == TRUE\nPROOF OBVIOUS"
    } else {
        rhsTheorem = #"""
        LOCAL THEOREM NativeSequentialDecodedRhsOutcomes ==
        \#(rhsFacts.map { "    /\\ " + $0 }.joined(separator: "\n"))
        PROOF
        \#(rhsProofs.joined(separator: "\n"))
        <1>. QED BY ONLY \#(rhsFacts.indices.map { "<1>rhs\($0 + 1)" }.joined(separator: ", ")), PTL

        """#
    }
    let fullFailureTheorem = fullFailureFacts.isEmpty ? "" : #"""
    NativeSequentialFullFailureHistoriesMatch ==
    \#(fullFailureConclusions.joined(separator: "\n"))

    THEOREM NativeSequentialRecorderUsesAuthoredHistories ==
        AuthoredSequentialTypedEntry => NativeSequentialFullFailureHistoriesMatch
    PROOF
    <1>. SUFFICES ASSUME AuthoredSequentialTypedEntry
                  PROVE NativeSequentialFullFailureHistoriesMatch BY PTL
    \#(fullFailureSteps.joined(separator: "\n"))
    <1>. QED BY ONLY \#(fullFailureFacts.joined(separator: ", ")), PTL DEF NativeSequentialFullFailureHistoriesMatch

    """#
    let theorem = #"""
    \#(rhsTheorem)
    THEOREM NativeSequentialDispatchUsesEmittedLabeledSteps ==
        AuthoredSequentialTypedEntry =>
            (\A label : NativeSequentialLabeledStep(label) <=> TLASequentialLabeledStep(label))
    PROOF
    <1>. SUFFICES ASSUME AuthoredSequentialTypedEntry
                  PROVE \A label : NativeSequentialLabeledStep(label) <=> TLASequentialLabeledStep(label) BY PTL
    \#(actionSteps.joined(separator: "\n"))
    <1>routes. NativeSequentialDispatch!NativeDispatchBindsTheActionCatalog(NativeSequentialRoutes, NativeSequentialFormalLabels)
        BY ONLY SMT DEF NativeSequentialRoutes, NativeSequentialFormalLabels,
            NativeSequentialDispatch!NativeDispatchBindsTheActionCatalog
    <1>domains. /\ DOMAIN NativeSequentialAuthoredLabels = DOMAIN NativeSequentialFormalLabels
                /\ DOMAIN NativeSequentialActions = DOMAIN TLASequentialActions
        BY ONLY IsaM("simp") DEF NativeSequentialAuthoredLabels, NativeSequentialFormalLabels, NativeSequentialActions, TLASequentialActions
    <1>slots. \A slot \in DOMAIN NativeSequentialFormalLabels :
                  NativeSequentialActions[slot] <=> TLASequentialActions[slot]
        BY ONLY \#(actionFacts.joined(separator: ", ")), IsaM("simp"), SMT
            DEF NativeSequentialFormalLabels, NativeSequentialActions, TLASequentialActions
    <1>. QED BY ONLY <1>routes, <1>domains, <1>slots,
        NativeSequentialDispatch!CertifiedNativeDispatchUsesTheLabeledCatalog, SMT
        DEF NativeSequentialLabeledStep, TLASequentialLabeledStep

    THEOREM NativeSequentialDispatchUsesAuthoredFailures ==
        AuthoredSequentialTypedEntry =>
            (\A label : NativeSequentialLabeledFailures(label) = AuthoredSequentialFirstFailure(label))
    PROOF
    <1>. SUFFICES ASSUME AuthoredSequentialTypedEntry
                  PROVE \A label : NativeSequentialLabeledFailures(label) = AuthoredSequentialFirstFailure(label) BY PTL
    \#(failureSteps.joined(separator: "\n"))
    <1>. QED BY ONLY \#(failureFacts.joined(separator: ", ")), IsaM("simp"), SMT
        DEF NativeSequentialLabeledFailures, NativeSequentialRoutes, NativeSequentialAuthoredLabels,
            NativeSequentialFailures, AuthoredSequentialLabels, AuthoredSequentialFirstFailure, AuthoredSequentialVisitorFailure

    \#(fullFailureTheorem)
    """#
    let failureCases = rows.indices.map { index in
        let visitor = "NativeSequentialRoutes[\(index + 1)].visitor"
        return "label = NativeSequentialAuthoredLabels[\(visitor)] -> NativeSequentialFailures[\(visitor)]"
    }.joined(separator: " [] ")
    let definitions = #"""
    LOCAL NativeSequentialFields == \#(keys)
    LOCAL NativeSequentialBefore == \#(snapshot(""))
    LOCAL NativeSequentialAfter == \#(snapshot("'"))
    LOCAL NativeSequentialRule == INSTANCE OrderedAssignmentOutputRules WITH Keys <- \#(integerFields),
        SwiftIntMin <- \#(TLAValue.int(Int.min)), SwiftIntMax <- \#(TLAValue.int(Int.max)),
        Vars <- {}, Values <- {}, ActionLabels <- {}, FailureValues <- {}, NoFailure <- <<>>
    LOCAL NativeSequentialDispatch == INSTANCE ActionOutcomeInterface
        WITH UpdateValues <- {}, FailureValues <- {}, NoFailure <- <<>>
    \#(actionDefinitions.joined(separator: "\n"))
    LOCAL NativeSequentialRoutes == \#(routes)
    LOCAL NativeSequentialFormalLabels == \#(formalLabels)
    LOCAL NativeSequentialAuthoredLabels == \#(authoredLabels)
    LOCAL NativeSequentialActions == \#(actionTuple(nativeActions))
    LOCAL TLASequentialActions == \#(actual)
    LOCAL NativeSequentialFailures == \#(actionTuple(failureActions))
    NativeSequentialLabeledStep(label) ==
        NativeSequentialDispatch!NativeDispatchLabeled(NativeSequentialRoutes, NativeSequentialActions,
            NativeSequentialFormalLabels, NativeSequentialAuthoredLabels, label)
    TLASequentialLabeledStep(label) ==
        NativeSequentialDispatch!CatalogLabeledBranches(TLASequentialActions, NativeSequentialAuthoredLabels, label)
    NativeSequentialLabeledFailures(label) ==
        CASE \#(failureCases) [] OTHER -> <<>>
    """#
    return .init(definitions: definitions, theorem: theorem, hasFullFailures: !fullFailureFacts.isEmpty)
}

/// Instantiate the existing physical history recurrence on the decoded capture's finite node range.
private func nativeSequentialRhsProof(
    _ name: String, capture: ActionCapture, armPlan: String, slot: Int, previous: String, ordinal: Int
) -> (definitions: [String], names: [String], proof: String, conclusion: String) {
    let rule = "NativeSequentialRule!"
    let before = "NativeSequentialBefore"
    let completed = "\(previous).completed"
    let count = capture.columns.kinds.count
    let plan = "\(name)Plan"
    let witness = "\(name)Witness"
    let history = "\(rule)PhysicalAssignmentRhsHistory"
    let nodes = (0...count).map { "\(name)Node\($0)" }
    func finiteHistory(through end: Int) -> String {
        if end == 0 { return "[i \\in 0..0 |-> \(nodes[0])]" }
        let cases = (0..<end).map { "i = \($0) -> \(nodes[$0])" }
        return "[i \\in 0..\(end) |-> CASE \((cases + ["OTHER -> \(nodes[end])"]).joined(separator: " [] "))]"
    }
    var definitions = [
        "\(plan) == \(rule)NativeAssignmentRhsPlan(\(armPlan).captures[\(slot)])",
        "\(nodes[0]) == \(rule)Success(0)",
    ]
    for index in 1...count {
        definitions.append("""
        \(nodes[index]) == \(rule)GeneratedNode(\(index), \(plan).kinds, \(plan).literals,
            \(rule)PhysicalRhsReadIndices(\(plan)), \(plan).left, \(plan).right,
            \(rule)PhysicalRhsBindings(\(plan), \(before), \(completed)), \(finiteHistory(through: index - 1)))
        """)
    }
    definitions.append("\(witness) == \(finiteHistory(through: count))")
    let recurrenceFacts = (1...count).map { "<3>node\($0)" }
    let recurrence = (1...count).map { index in
        let tag = capture.columns.kinds[index - 1]
        let prefix = finiteHistory(through: index - 1)
        let isAddition = tag == .string("add")
        let children = isAddition ? #"""

                    <4>children. /\ (\#(prefix))[\#(plan).left[\#(index)]] = \#(witness)[\#(plan).left[\#(index)]]
                                 /\ (\#(prefix))[\#(plan).right[\#(index)]] = \#(witness)[\#(plan).right[\#(index)]]
                        BY ONLY <2>columns, SMT DEF left, right, \#(witness)
        """# : ""
        let childFact = isAddition ? ", <4>children" : ""
        return #"""
                <3>node\#(index). \#(witness)[\#(index)] = \#(rule)GeneratedNode(\#(index), \#(plan).kinds, \#(plan).literals,
                    \#(rule)PhysicalRhsReadIndices(\#(plan)), \#(plan).left, \#(plan).right,
                    \#(rule)PhysicalRhsBindings(\#(plan), \#(before), \#(completed)), \#(witness))
                    <4>slot. \#(witness)[\#(index)] = \#(nodes[index])
                        BY ONLY SMT DEF \#(witness)
                    <4>tag. \#(plan).kinds[\#(index)] = \#(tag)
                        BY ONLY <2>columns, SMT DEF kinds\#(children)
                    <4>. QED BY ONLY <4>slot, <4>tag\#(childFact), SMT DEF \#(nodes[index]), \#(rule)GeneratedNode
        """#
    }.joined(separator: "\n")
    let conclusion = "\(rule)PhysicalAssignmentRhs(\(plan), \(before), \(completed)) = \(nodes[count])"
    let proof = #"""
    <1>rhs\#(ordinal). \#(conclusion)
        <2>. DEFINE decodedCapture == \#(capture.tla)
                    kinds == \#(TLAValue.tuple(capture.columns.kinds))
                    left == \#(TLAValue.tuple(capture.columns.left))
                    right == \#(TLAValue.tuple(capture.columns.right))
        <2>capture. \#(armPlan).captures[\#(slot)] = decodedCapture
            BY ONLY IsaM("simp") DEF \#(armPlan), decodedCapture
        <2>decoded. \#(plan) = \#(rule)NativeAssignmentRhsPlan(decodedCapture)
            BY ONLY <2>capture, SMT DEF \#(plan)
        <2>columns. /\ \#(plan).count = \#(count)
                     /\ \#(plan).kinds = kinds
                     /\ \#(plan).left = left /\ \#(plan).right = right
            BY ONLY <2>decoded, IsaM("simp") DEF decodedCapture, \#(rule)NativeAssignmentRhsPlan, kinds, left, right
        <2>shape. /\ \#(plan).count \in Nat \ {0}
                  /\ 1..\#(plan).count = \#(TLAValue.set(Set((1...count).map(TLAValue.int))))
                  /\ \A index \in 1..\#(plan).count : \#(plan).kinds[index] \in {"literal", "read", "add"}
                  /\ \A index \in 1..\#(plan).count : \#(plan).kinds[index] = "add" =>
                       /\ \#(plan).left[index] \in 1..(index - 1)
                       /\ \#(plan).right[index] \in 1..(index - 1)
            <3>tags. \A index \in 1..\#(count) : kinds[index] \in {"literal", "read", "add"}
                BY ONLY SMT DEF kinds
            <3>children. \A index \in 1..\#(count) : kinds[index] = "add" =>
                /\ left[index] \in 1..(index - 1)
                /\ right[index] \in 1..(index - 1)
                BY ONLY SMT DEF kinds, left, right
            <3>. QED BY ONLY <2>columns, <3>tags, <3>children, SMT
        <2>witness. \#(history)(\#(plan), \#(before), \#(completed), \#(witness))
            <3>zero. \#(witness)[0] = \#(rule)Success(0)
                BY ONLY SMT DEF \#(witness), \#(nodes[0])
    \#(recurrence)
            <3>. QED BY ONLY <2>shape, <3>zero, \#(recurrenceFacts.joined(separator: ", ")), SMT
                DEF \#(rule)PhysicalAssignmentRhsHistory, \#(rule)GeneratedExpressionHistory
        <2>result. \#(rule)PhysicalAssignmentRhs(\#(plan), \#(before), \#(completed)) = \#(witness)[\#(plan).count]
            BY ONLY <2>shape, <2>witness, \#(rule)PhysicalAssignmentRhsAgreesWithWitness, SMT
        <2>count. \#(plan).count = \#(count)
            BY ONLY <2>columns, PTL
        <2>root. \#(witness)[\#(count)] = \#(nodes[count])
            BY ONLY SMT DEF \#(witness)
        <2>. QED BY ONLY <2>result, <2>count, <2>root, SMT
    """#
    return (definitions, [plan] + nodes, proof, conclusion)
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

extension OrderedRHSPhysicalAction.Plan {
    var integerRecord: TLAValue {
        .record(["count": .int(kinds.count), "kinds": .tuple(kinds), "literals": .tuple(literals),
                 "reads": .tuple(reads), "left": .tuple(left), "right": .tuple(right)])
    }
}

struct NativeConditionalArmOutput {
    let captures: [(binder: BinderID?, plan: OrderedRHSPhysicalAction.Plan)]
    var capturePlans: [OrderedRHSPhysicalAction.Plan] { captures.map { $0.plan } }
    let writeOrder: [String]
    let writes: [String: TLAValue]
    let failureAppendSites: [Int]
    let failureCalls: [NativeConditionalFailureCall]

    func operands() throws -> TLAValue {
        try conditionalArmOperands(capturePlans, writeOrder: writeOrder, writes: writes, failureAppendSites: failureAppendSites)
    }

    func integerTrace(count: Int) throws -> TLAValue {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        let output = try materialization(after: count)
        let declarations = try self.captures.prefix(count).map { capture in
            guard let binder = capture.binder else { throw invalid }
            return TLAValue.int(binder.ordinal)
        }
        let captures = capturePlans.prefix(count)
        let sites = captures.enumerated().compactMap { index, plan in
            plan.kinds.contains(.string("add")) ? index + 1 : nil
        }
        guard sites == failureAppendSites, sites.count == failureCalls.count else { throw invalid }
        let callbacks = try zip(sites, failureCalls).map { site, call -> (TLAValue, TLAValue) in
            guard call.before.count == site - 1 else { throw invalid }
            // The visitor decoder already matched every callback local to its lexical capture.
            let before = call.before.enumerated().map { index, binding in
                TLAValue.record(["binding": .int(binding.binding), "target": .int(binding.target), "slot": .int(index + 1)])
            }
            let branch: TLAValue = switch call.location {
            case .arm(let ordinal): .int(ordinal)
            case .sharedPrefix: .tuple([])
            }
            return (.int(site), .record(["action": .int(call.action), "branch": branch,
                "site": .int(call.site), "target": .int(call.target), "before": .tuple(before)]))
        }
        return .record(["declarations": .tuple(declarations), "captures": .tuple(captures.map { $0.integerRecord }),
            "callbacks": .function(Dictionary(uniqueKeysWithValues: callbacks)),
            "suffix": output.suffix, "writes": output.writes])
    }

    func materialization(after slot: Int) throws -> (suffix: TLAValue, writes: TLAValue) {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        guard slot >= 0, slot <= capturePlans.count else { throw invalid }
        let suffix = try capturePlans.dropFirst(slot).map { plan -> TLAValue in
            guard plan.kinds == [.string("literal")], let value = plan.literals.first,
                  case .bool = value else { throw invalid }
            return value
        }
        let pending = try writeOrder.map { target -> TLAValue in
            guard let reference = writes[target] else { throw invalid }
            return .tuple([.string(target), reference])
        }
        return (.tuple(suffix), .tuple(pending))
    }
}

struct NativeConditionalActionOutput {
    let children: String
    let plans: String
    let fields: String
    let predicate: [String]
    let selectorCaptures: [String]
    let handle: String
    let formalLabel: String
    let visitor: Int
    let sharedPrefix: NativeConditionalArmOutput
    let ifTrue: NativeConditionalArmOutput
    let ifFalse: NativeConditionalArmOutput
}

/// Keep the reviewed arithmetic, branch selection and history recorder tied to the library source.
func verifyConditionalHistoryHelpers(operations: String, checking: String, requiresSharedPrefix: Bool = false) throws {
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
    let errors = try checked(library.compactMap { $0.as(EnumDeclSyntax.self) }.filter {
        $0.name.text == "NativeMachineEvaluationError"
    })
    let classification = try checked(errors.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }.filter {
        $0.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "isModelEvaluationFailure"
    })
    guard sameWords(syntaxWords(classification), """
        @_documentation(visibility: internal)
        public var isModelEvaluationFailure: Bool {
            switch self {
            case .nonEnumerableIntegerDomain, .nonEnumerableSequenceDomain,
                 .collectionCardinalityOverflow, .powerSetTooLarge,
                 .recursionDepthExceeded, .checkingContextRequired:
                false
            case .noMatchingCase, .noSatisfyingChoice, .integerOverflow,
                 .divisionByZero, .negativeModuloDivisor, .indexOutOfBounds,
                 .invalidSequenceDomain, .emptySequence, .functionArgumentOutsideDomain,
                 .tupleIndexOutsideDomain, .recordFieldUnavailable,
                 .invalidRandomSubsetCount, .emptyRandomElementDomain:
                true
            }
        }
        """) else { throw invalid }
    try require("_nativeIntMinimum", """
        @_documentation(visibility: internal)
        public func _nativeIntMinimum() -> Int { Int.min }
        """, in: library)
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
    try require("mergeUpdate", """
        @inlinable
        public static func mergeUpdate<Value: Equatable & Sendable>(
            _ current: inout Value?, _ incoming: Value?,
            equivalent: @Sendable (Value, Value) -> Bool = { $0 == $1 }
        ) -> Bool {
            guard let incoming else { return true }
            if let current, !equivalent(current, incoming) { return false }
            current = incoming
            return true
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
            context?.record(.alternative(.init(action: action, location: .arm(branch), site: site, target: target,
                                               before: bindings, reason: reason)))
        }
        """, in: collector)
    try require("startRecordingActionFailureHistory", """
        package mutating func startRecordingActionFailureHistory() {
            recordsAlternativeFailures = true
            assignmentFailures = []
        }
        """, in: context.memberBlock.members.map(\.decl))
    try require("finishRecordingActionFailureHistory", """
        package mutating func finishRecordingActionFailureHistory() -> [NativeAlternativeFailure] {
            guard recordsAlternativeFailures else { return [] }
            defer {
                assignmentFailures = nil
                recordsAlternativeFailures = false
            }
            return assignmentFailures?.compactMap {
                guard case .alternative(let failure) = $0 else { return nil }
                return failure
            } ?? []
        }
        """, in: context.memberBlock.members.map(\.decl))
    let typedRecorder = collector.contains {
        $0.as(FunctionDeclSyntax.self)?.name.text == "_recordNativeSharedPrefixFailure"
    }
    guard requiresSharedPrefix || typedRecorder else { return }
    try require("_recordNativeSharedPrefixFailure", """
        @_documentation(visibility: internal)
        public func _recordNativeSharedPrefixFailure<Registers>(
            _ context: inout CheckingContext<Registers>?, action: Int, site: Int, target: Int,
            before: @autoclosure () -> [(binding: Int, target: Int, value: Int)], reason: NativeMachineEvaluationError
        ) {
            guard context?.recordsAlternativeFailures == true else { return }
            let bindings = before().map { NativeAlternativeFailure.Binding(binding: $0.binding, target: $0.target, value: $0.value) }
            context?.record(.alternative(.init(action: action, location: .sharedPrefix, site: site, target: target,
                                               before: bindings, reason: reason)))
        }
        """, in: collector)
}

func nativeConditionalActionPlans(_ source: String, program: CompiledProgram, predicate: [String]) throws
    -> NativeConditionalActionOutput {
    let row = try checked(decodeScalarActions(source, program: program, predicate: predicate))
    guard let visit = row.visit, let shared = row.shared else {
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
    let binderByLocal = Dictionary(uniqueKeysWithValues: program.binderNames.map { binder, name in
        ("_\(name)_\(binder.ordinal)", binder)
    })
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
        let captures = try plan.captures.map { capture in
            let columns = capture.columns
            let decoded = OrderedRHSPhysicalAction.Plan(kinds: columns.kinds, literals: columns.literals,
                reads: try columns.reads.map(renamedRead), left: columns.left, right: columns.right)
            return (binderByLocal[capture.declaredLocal], decoded)
        }
        return .init(captures: captures, writeOrder: order, writes: writes,
                     failureAppendSites: plan.failureAppendSites, failureCalls: plan.conditionalFailureCalls)
    }
    let first = visit.ifTrue.id, second = visit.ifFalse.id
    return .init(children: "<<\(first), \(second)>>",
        plans: "[child \\in {\(first), \(second)} |-> IF child = \(first) THEN \(row.plans[0].tla) ELSE \(row.plans[1].tla)]",
        fields: TLAValue.set(Set(row.fields.map(TLAValue.string))).description,
        predicate: visit.predicate, selectorCaptures: Array(visit.ifTrue.arguments.dropLast(2)), handle: row.handle, formalLabel: row.formalLabel, visitor: row.visitor,
        sharedPrefix: try arm(shared), ifTrue: try arm(row.plans[0]), ifFalse: try arm(row.plans[1]))
}

private func decodeScalarActions(_ source: String, program: CompiledProgram, predicate: [String]?,
                                 controlledFork: Bool = false) throws
    -> [(label: String, formalLabel: String, handle: String, visitor: Int, fields: [String],
         visit: NativeConditionalVisit?, shared: ActionInstructions?, plans: [ActionInstructions])] {

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
            locations: locations.map { ($0.caseName, $0.label) }, checking: checking, predicate: predicate,
            program: program, controlledFork: controlledFork)
        let successor = try checked(functions.filter { $0.name.text == "_visitSuccessors\(index)" })
        try verifyGeneratedSuccessorOutput(DeclSyntax(successor), actionID: index, parameters: "", arguments: "",
            configurationParameters: "", configurationArguments: "")
        return (label: action.declaration.name, formalLabel: formalLabels[index], handle: labels[index],
            visitor: physicalRoutes[index].visitor, fields: fields.map(\.name), visit: decoded.visit, shared: decoded.shared,
            plans: decoded.plans)
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
    let location: NativeAlternativeFailure.Location
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
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else { return nil }
        let arguments = Array(call.arguments)
        let labels = arguments.map { $0.label?.text }
        let location: NativeAlternativeFailure.Location
        let siteIndex: Int
        switch syntaxWords(call.calledExpression) {
        case ["SwiftTLA", ".", "_recordNativeAlternativeFailure"]:
            guard labels == [nil, "action", "branch", "site", "target", "before", "reason"],
                  let branch = ordinal(arguments[2].expression) else { return nil }
            location = .arm(branch)
            siteIndex = 3
        case ["SwiftTLA", ".", "_recordNativeSharedPrefixFailure"]:
            guard labels == [nil, "action", "site", "target", "before", "reason"] else { return nil }
            location = .sharedPrefix
            siteIndex = 2
        default: return nil
        }
        guard let context = arguments[0].expression.as(InOutExprSyntax.self), reference(context.expression) == "context",
              let action = ordinal(arguments[1].expression),
              let site = ordinal(arguments[siteIndex].expression), let target = ordinal(arguments[siteIndex + 1].expression),
              let bindings = arguments[siteIndex + 2].expression.as(ArrayExprSyntax.self),
              reference(arguments[siteIndex + 3].expression) == "failure" else { return nil }
        var before: [Preceding] = []
        for binding in bindings.elements {
            guard let tuple = binding.expression.as(TupleExprSyntax.self) else { return nil }
            let fields = Array(tuple.elements)
            guard fields.map({ $0.label?.text }) == ["binding", "target", "value"],
                  let binder = ordinal(fields[0].expression), let key = ordinal(fields[1].expression),
                  let local = reference(fields[2].expression) else { return nil }
            before.append(.init(binding: binder, target: key, local: local))
        }
        return .init(action: action, location: location, site: site, target: target, before: before)
    }
}

private func decodeScalarActionVisitor(_ visitor: FunctionDeclSyntax, index: Int,
    fields: [ActionField], control: ActionField?, locations: [(caseName: String, label: String)],
    checking: String, predicate: [String]?, program: CompiledProgram, controlledFork: Bool) throws
    -> (visit: NativeConditionalVisit?, shared: ActionInstructions?, plans: [ActionInstructions]) {
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
    let counter = program.layout.variables.first { $0.declaration.origin == .programCounter }?.id
    let regions = controlledFork ? program[action].body.orderedAlternativeFailureRegions(afterControlGuardOf: counter)
        : (predicate == nil ? [] : program[action].body.orderedAlternativeFailureRegions)
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
    func partCore(_ name: String, scope: [Binding], beforeSelector: Bool, region: AlternativeFailureRegion?) throws
        -> (tokens: [String], recordsFailure: Bool, conditionalFailure: NativeConditionalFailureCall?) {
        guard let part = byName[name], let body = part.body, visited.insert(name).inserted else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let formal = scope.map { "_ \($0.local): \($0.value.type), " }.joined()
        let signature = "func \(name)(\(formal)_ updates: _Updates, _ emit: (_Updates) throws -> Void) throws"
        if controlledFork, sameWords(syntaxWords(part), "\(signature) { return }") {
            return (["return"], false, nil)
        }
        let tokens = syntaxWords(body)
        let prefix = words("{ do {")
        let handler = "} catch let failure as NativeMachineEvaluationError where failure.isModelEvaluationFailure {"
        let append = "failures.append(failure) } }"
        let lexical = scope.map(\.local)
        let recording: String
        let conditionalFailure: NativeConditionalFailureCall?
        if predicate != nil || controlledFork,
           let actionPart = body.statements.first?.item.as(DoStmtSyntax.self),
           let catchBody = actionPart.catchClauses.first?.body.statements, catchBody.count == 2,
           let observer = catchBody.first {
            guard let decoded = NativeConditionalFailureCall.decode(observer), let region,
                  decoded.action == action.ordinal,
                  decoded.location == (beforeSelector ? .sharedPrefix : .arm(region.armOrdinal)),
                  decoded.before.count == lexical.count, lexical.count < region.bindings.count else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            let expectedSite = region.bindings[lexical.count]
            let position = beforeSelector ? region.sharedIndex(of: expectedSite.binder) : region.index(of: expectedSite.binder)
            guard position == lexical.count,
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
        } else if predicate == nil && !controlledFork {
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

    var fork: (visit: NativeConditionalVisit, scope: [Binding])?
    func walk(_ entry: String, scope: [Binding] = [], startingWith prefix: ActionInstructions = .init(),
              untilSelector: Bool = false, region: AlternativeFailureRegion? = nil) throws -> ActionInstructions {
        var instructions = prefix
        var capturesFollowGuard = true
        let entryGuards = predicate == nil ? 1 : 0
        var pending: [(String, [Binding])] = [(entry, scope)]
        parts: while let (name, scope) = pending.popLast() {
            let (core, recordsFailure, conditionalFailure) = try partCore(name, scope: scope,
                beforeSelector: untilSelector, region: region)
            guard !recordsFailure || (core.first == "let"
                && scope.allSatisfy({ $0.value.type == nativeIntTypeTokens.joined() })) else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            if untilSelector,
               let body = byName[name]?.body?.statements.first?.item.as(DoStmtSyntax.self)?.body.statements,
               body.count == 1, let item = body.first?.item,
               let call = item.as(TryExprSyntax.self) ?? item.as(ExpressionStmtSyntax.self)?.expression.as(TryExprSyntax.self),
               let selection = nativeConditionalVisit(Syntax(call)) {
                let names = scope.map(\.local)
                let arguments = names + ["updates", "emit"]
                guard !recordsFailure, pending.isEmpty, instructions.writes.isEmpty,
                      instructions.guards.count == entryGuards,
                      region.map({ $0.sharedBindingCount == names.count }) ?? true,
                      capturesFollowGuard, names.count == instructions.captures.count, syntaxWords(call) == core,
                      predicate.map({ selection.predicate == $0 }) ?? controlledFork,
                      !controlledFork || names.isEmpty,
                      selection.ifTrue.arguments == arguments, selection.ifFalse.arguments == arguments else {
                    throw InitialFailureEvidenceError.unsupportedGeneratedOutput
                }
                fork = (selection, scope)
                break parts
            }
            let argument = scope.map { "\($0.local), " }.joined()
            if controlledFork, core == ["return"] {
                guard pending.isEmpty, instructions.writes.isEmpty, instructions.guards.count == entryGuards
                else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
                instructions.disabled = true
                break parts
            }
            if sameWords(core, "try emit(updates)") { continue }
            if let control {
                for location in locations where sameWords(core, """
                    guard (\(control.before) == \(control.type).\(location.caseName)) else { return }
                    try emit(updates)
                    """) {
                    if controlledFork {
                        guard instructions.guards.isEmpty, instructions.captures.isEmpty, instructions.writes.isEmpty
                        else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
                    }
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
                if let region {
                    let position = scope.count
                    guard position < region.bindings.count,
                          untilSelector == (position < region.sharedBindingCount) else {
                        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
                    }
                    let binding = region.bindings[position].binder
                    guard let name = program.binderNames[binding], local == "_\(name)_\(binding.ordinal)" else {
                        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
                    }
                }
                let rhs = Array(core[3..<call])
                capturesFollowGuard = capturesFollowGuard
                    && instructions.guards.count == entryGuards && instructions.writes.isEmpty
                    && scope.count == instructions.captures.count
                    && scope.enumerated().allSatisfy { offset, binding in
                        binding.value.kind == "capture" && binding.value.operand == String(offset + 1)
                    }
                if recordsFailure || predicate != nil || controlledFork {
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
                        instructions.captures.append(.expression(try nativeArithmeticCapture(decoded.steps, reads: reads.map { $0.1 }), local: local))
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
                    instructions.captures.append(.reference(value, local: local))
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
        let checkedOrder = capturesFollowGuard && instructions.guards.count == entryGuards
        guard checkedOrder || (!controlledFork && predicate == nil && instructions.failureAppendSites.isEmpty) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        return instructions
    }

    let visit: NativeConditionalVisit?
    let sharedPrefix: ActionInstructions?
    let plans: [ActionInstructions]
    let initial = try walk("_actionPart0", untilSelector: predicate != nil || controlledFork, region: regions.first)
    if let fork {
        visit = fork.visit
        sharedPrefix = initial
        plans = try [walk("_actionPart\(fork.visit.ifTrue.id)", scope: fork.scope, startingWith: initial,
                          region: regions.first { $0.armOrdinal == 0 }),
                     walk("_actionPart\(fork.visit.ifFalse.id)", scope: fork.scope, startingWith: initial,
                          region: regions.first { $0.armOrdinal == 1 })]
    } else {
        guard predicate == nil else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        visit = nil
        sharedPrefix = nil
        plans = [initial]
    }
    guard visited.count == parts.count else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
    return (visit, sharedPrefix, plans)
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

/// The checked visitor has one continuation per arm. It reaches the successor
/// wrapper only after all captures and ordered _Updates merges have succeeded.
func conditionalNativeOutputProof(writeOrders: [[String]], nativeRows: TLAValue, tables: [String], planNames: [[String]],
                                  sharedPrefix: Bool = false)
    throws -> (rowDefinitions: String, captureNames: [[String]], definitions: String, steps: String,
               inventorySteps: String, selectedSteps: String) {
    guard case .tuple(let traces) = nativeRows, traces.count == tables.count,
          tables.count == planNames.count, writeOrders.count == tables.count else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    let arms = writeOrders.indices.map { $0 + 1 }
    let planRows = try traces.enumerated().map { index, trace -> (names: [String], definitions: [String], row: String, steps: String) in
        guard case .record(let row) = trace, case .tuple(let captures)? = row.value(named: "captures"),
              captures.count == planNames[index].count else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let arm = index + 1
        let physicalPlans = planNames[index]
        let nativePlans = captures.indices.map { "ConditionalNativeArm\(arm)Plan\($0 + 1)" }
        let planDefinitions = zip(nativePlans, captures).map { "LOCAL \($0) == \($1)" }
        let nativeTuple = actionTuple(nativePlans)
        let namedCaptures = TLAValue.tuple(nativePlans.map(TLAValue.constant))
        let nativeRow = TLAValue.record(row.replacing(namedCaptures, for: "captures")).description
        let physicalTuple = actionTuple(physicalPlans)
        let rowSteps = zip(nativePlans, physicalPlans).enumerated().map { slot, pair in
            #"""
                    <3>row\#(slot + 1). \#(pair.0) = \#(pair.1)
                        BY ONLY SMT DEF \#(pair.0), \#(pair.1)
            """#
        }.joined(separator: "\n")
        let rowFacts = captures.indices.map { "<3>row\($0 + 1), " }.joined()
        let steps = #"""
            <2>arm\#(arm). CASE arm = \#(arm)
                <3>native. ConditionalNativeRows[arm].captures = \#(nativeTuple)
                    BY ONLY <2>arm\#(arm), SMT DEF ConditionalNativeRows
                <3>physical. ConditionalIntegerTable(arm).plans = \#(physicalTuple)
                    BY ONLY <2>arm\#(arm), SMT DEF ConditionalIntegerTable, \#(tables[index])
        \#(rowSteps)
                <3>. QED BY ONLY <3>native, <3>physical, \#(rowFacts)SMT
        """#
        return (nativePlans, planDefinitions, nativeRow, steps)
    }
    let rowDefinitions = (planRows.flatMap(\.definitions)
        + ["ConditionalNativeRows == \(actionTuple(planRows.map(\.row)))"]).joined(separator: "\n")
    let captureNames = planRows.map(\.names)
    let callbackPlanDefinitions = captureNames.flatMap { $0 }.map { ", " + $0 }.joined()
    let nativePlanCases = planRows.map(\.steps).joined(separator: "\n")
    let suffixSteps = arms.map { arm in
        #"""
            <2>suffix\#(arm). ConditionalNativeRows[\#(arm)].suffix = ConditionalSourceRows[\#(arm)].suffix
                BY ONLY IsaM("simp") DEF ConditionalNativeRows, ConditionalSourceRows
        """#
    }.joined(separator: "\n")
    let suffixFacts = arms.map { "<2>suffix\($0)" }.joined(separator: ", ")
    let writeRoleSteps = zip(arms, writeOrders).map { arm, order in
        let renderedKeys = TLAValue.tuple(order.map(TLAValue.string))
        let keySet = "{\(order.map { String(describing: TLAValue.string($0)) }.joined(separator: ", "))}"
        let matchSteps = order.indices.map { index in
            let position = index + 1
            return #"""
                        <4>write\#(position). raw[\#(position)][2] = routes[keys[\#(position)]]
                            BY ONLY <2>arm\#(arm), IsaM("simp"), SMT DEF raw, keys, routes,
                                ConditionalNativeRows, ConditionalSourceRows
            """#
        }.joined(separator: "\n")
        let matchFacts = order.indices.map { "<4>write\($0 + 1), " }.joined()
        return #"""
            <2>arm\#(arm). CASE arm = \#(arm)
                <3>. DEFINE keys == \#(renderedKeys)
                            targets == \#(keySet)
                <3>domain. Len(raw) = \#(order.count) /\ DOMAIN raw = 1..\#(order.count)
                            /\ (\A i \in 1..\#(order.count) : raw[i][1] = keys[i])
                    BY ONLY <2>arm\#(arm), IsaM("auto"), SMT DEF raw, keys, ConditionalNativeRows
                <3>keySet. targets = {keys[i] : i \in 1..\#(order.count)} /\ targets \subseteq ConditionalStateKeys
                    BY ONLY SMT DEF keys, targets, ConditionalStateKeys
                <3>matches. \A i \in 1..\#(order.count) : raw[i][2] = routes[keys[i]]
                    <4>. TAKE i \in 1..\#(order.count)
        \#(matchSteps)
                    <4>. QED BY ONLY (i \in 1..\#(order.count)), \#(matchFacts)SMT
                <3>untouched. \A key \in ConditionalStateKeys \ targets : routes[key] = <<"state", key>>
                    BY ONLY <2>arm\#(arm), IsaM("auto"), SMT DEF routes, targets, ConditionalSourceRows, ConditionalStateKeys
                <3>. QED BY ONLY <3>domain, <3>keySet, <3>matches, <3>untouched, SMT
        """#
    }.joined(separator: "\n")
    let writeRoleCases = arms.map { "<2>arm\($0)" }.joined(separator: ", ")

    func afterPrefix(_ selected: String, failure: String, indentation: String = "    ",
                     condition: String = "~ConditionalNativeAfterSharedPrefix") -> String {
        guard sharedPrefix else { return selected }
        let continuation = selected.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }.joined(separator: "\n")
        return "\(indentation)IF \(condition) THEN \(failure)\n\(indentation)ELSE\n\(continuation)"
    }
    let armSelection = sharedPrefix ? #"""
    ConditionalNativeSelectedArm ==
        IF ~ConditionalNativeAfterSharedPrefix THEN <<>>
        ELSE IF ConditionalNativeDecision = <<>> THEN <<>> ELSE ConditionalNativeDecision[1]
    """# : "ConditionalNativeSelectedArm == ConditionalArmFor(ConditionalNativeComparison)"
    let certifiedFailure = "[callbacks |-> <<>>, reasons |-> <<ConditionalSharedTerminal.failure.payload>>]"
    let history = #"""
        LET arm == ConditionalNativeSelectedArm
            result == ConditionalNativeIntegerResult(arm)
            calls == ConditionalNativeRows[arm].callbacks
        IN IF ~recording \/ result.failure = <<>> THEN <<>>
           ELSE IF result.failure.site \notin DOMAIN calls THEN <<>>
           ELSE LET call == calls[result.failure.site]
                    before == [i \in DOMAIN call.before |->
                        LET capture == call.before[i]
                        IN [binding |-> capture.binding, target |-> capture.target, value |-> result.completed[capture.slot]]]
                IN <<[source |-> ConditionalEntry, action |-> call.action, branch |-> call.branch, site |-> call.site,
                      target |-> call.target, payload |-> result.failure.payload, before |-> before]>>
    """#
    let step = #"""
        LET arm == ConditionalNativeSelectedArm
        IN ConditionalNativeIntegerResult(arm).failure = <<>> /\ ConditionalNativeMaterializes(arm, ConditionalStateAfter)
    """#
    let visitor = #"""
            LET arm == ConditionalNativeSelectedArm
                result == ConditionalNativeIntegerResult(arm)
                handlers == ConditionalNativeRows[arm].callbacks
            IN IF result.failure = <<>>
               THEN [callbacks |-> IF \E after : ConditionalNativeMaterializes(arm, after)
                                   THEN <<ConditionalSnapshot(CHOOSE after : ConditionalNativeMaterializes(arm, after))>>
                                   ELSE <<>>,
                     reasons |-> <<>>]
               ELSE [callbacks |-> <<>>,
                     reasons |-> IF result.failure.site \in DOMAIN handlers THEN <<result.failure.payload>> ELSE <<>>]
    """#
    let certifiedVisitor = #"""
        LET arm == ConditionalSelectedArm
            terminal == ConditionalIntegerTerminal(arm)
        IN IF terminal.failure = <<>>
           THEN [callbacks |-> <<ConditionalSnapshot(ConditionalSourceSuccessor(arm, terminal))>>, reasons |-> <<>>]
           ELSE [callbacks |-> <<>>, reasons |-> <<terminal.failure.payload>>]
    """#
    let definitions = #"""
    ConditionalIntegerRun(arm) ==
        LET rows == ConditionalIntegerRows(arm)
        IN CHOOSE history : Arithmetic!AssignmentListHistory(FALSE, ConditionalBefore, rows, history)
    LOCAL ConditionalGeneratedIntegerRun(arm) ==
        LET rows == ConditionalIntegerRows(arm)
        IN CHOOSE history : Arithmetic!AssignmentListHistory(TRUE, ConditionalBefore, rows, history)
    ConditionalIntegerTerminal(arm) == ConditionalIntegerRun(arm)[Len(ConditionalIntegerRows(arm))]
    \#(armSelection)
    ConditionalNativeIntegerResult(arm) ==
        LET visitor == ConditionalNativeRows[arm]
        IN Arithmetic!NativeAssignmentCaptureResult(ConditionalBefore, visitor, Len(visitor.captures))
    ConditionalNativeHistory(recording) ==
    \#(afterPrefix(history, failure: "ConditionalNativeSharedHistory(recording)"))

    ConditionalMerge == INSTANCE NativePendingWriteFold WITH Vars <- ConditionalStateKeys, Values <- ConditionalIntValues \cup BOOLEAN, ActionLabels <- {ConditionalActionOrdinal}, FailureValues <- {}, NoFailure <- <<>>
    ConditionalNativeCompleted(arm) ==
        ConditionalNativeIntegerResult(arm).completed \o ConditionalNativeRows[arm].suffix
    ConditionalNativeWrites(arm) ==
        LET raw == ConditionalNativeRows[arm].writes
            completed == ConditionalNativeCompleted(arm)
        IN [i \in DOMAIN raw |-> <<raw[i][1],
            Arithmetic!CopyReferenceValue(ConditionalStateBefore, completed, raw[i][2])>>]
    \* Snapshot has no fields outside State. The send rule uses the pair <<nonState, state>>.
    ConditionalSnapshot(state) == <<<<>>, state>>
    ConditionalSourceSuccessor(arm, terminal) ==
        LET row == ConditionalSourceRows[arm]
        IN Arithmetic!CopyMaterializedState(ConditionalStateKeys, ConditionalStateBefore,
                terminal.completed \o row.suffix, row.finalRoutes)
    LOCAL ConditionalNativeMaterializes(arm, after) ==
        /\ after = [key \in ConditionalStateKeys |-> after[key]]
        /\ ConditionalMerge!NativePendingMergesEmit(ConditionalStateKeys, ConditionalStateBefore, after,
                Len(ConditionalNativeRows[arm].writes), ConditionalNativeWrites(arm))
    ConditionalNativeStep ==
    \#(afterPrefix(step, failure: "FALSE"))
    \* The decoded catch sites append to the returned error array even when checking is nil.
    ConditionalNativeVisitorOutput ==
        [visitor \in {ConditionalSendVisitor} |->
    \#(afterPrefix(visitor, failure: "ConditionalNativeSharedVisitorOutput", indentation: "        "))]
    ConditionalCertifiedVisitorOutput ==
    \#(afterPrefix(certifiedVisitor, failure: certifiedFailure, condition: "ConditionalSharedTerminal.failure # <<>>"))
    """#
    let nativeGateFact = sharedPrefix ? "<1>nativePrefixPass, " : ""
    let queueGateFacts = sharedPrefix ? nativeGateFact + "<1>prefixPass, " : ""
    let callbackBranch = sharedPrefix ? "(IF site <= ConditionalSharedCount THEN <<>> ELSE arm - 1)" : "arm - 1"
    let callbackCountDefinition = sharedPrefix ? ", ConditionalSharedCount" : ""
    let afterSharedFailure = sharedPrefix
        ? "\n           /\\ (ConditionalSharedTerminal.failure = <<>> => ConditionalSharedCount < terminal.failure.site)" : ""
    let afterSharedFailureGoal = sharedPrefix
        ? "\n                           /\\ (ConditionalSharedTerminal.failure = <<>> => ConditionalSharedCount < terminal.failure.site)" : ""
    let afterSharedFailureProof = sharedPrefix ? #"""
        <2>afterShared. ConditionalSharedTerminal.failure = <<>> => ConditionalSharedCount < slot
            BY ONLY (arm \in ConditionalArms), <2>site, <2>node, <1>sharedRows, <1>sharedPasses, <1>sharedGuardColumns,
                SMT DEF raw, Arithmetic!RenderedAssignmentFailsAt, Arithmetic!FirstRejectedRenderedGuard,
                    Arithmetic!RenderedAssignmentsPass, Arithmetic!EveryRenderedGuardPasses

    """# : ""
    let afterSharedFailureFact = sharedPrefix ? "<2>afterShared, " : ""
    let callbackSiteFact = sharedPrefix ? "<1>prefixPass, " : ""
    let arithmeticInventory = #"""
    <1>integerRuns. \A arm \in ConditionalArms :
        LET rows == ConditionalIntegerRows(arm)
            history == ConditionalIntegerRun(arm)
        IN /\ Arithmetic!AssignmentListHistory(FALSE, ConditionalBefore, rows, history)
           /\ Arithmetic!AssignmentListHistory(TRUE, ConditionalBefore, rows, history)
        <2>. TAKE arm \in ConditionalArms
        <2>. DEFINE rows == ConditionalIntegerRows(arm)
                    source == ConditionalIntegerRun(arm)
                    generated == ConditionalGeneratedIntegerRun(arm)
        <2>supported. Arithmetic!SupportedAssignmentList(rows)
            BY ONLY (arm \in ConditionalArms), <1>integerRows DEF rows
        <2>exists. \E history :
                       /\ Arithmetic!AssignmentListHistory(FALSE, ConditionalBefore, rows, history)
                       /\ Arithmetic!AssignmentListHistory(TRUE, ConditionalBefore, rows, history)
            BY ONLY <2>supported, <1>integerEntry, Arithmetic!CertifiedAssignmentListsConstructTheirHistories
        <2>source. Arithmetic!AssignmentListHistory(FALSE, ConditionalBefore, rows, source)
            BY ONLY <2>exists, SMT DEF rows, source, ConditionalIntegerRun
        <2>generated. Arithmetic!AssignmentListHistory(TRUE, ConditionalBefore, rows, generated)
            BY ONLY <2>exists, SMT DEF rows, generated, ConditionalGeneratedIntegerRun
        <2>same. \A index \in 0..Len(rows) : source[index] = generated[index]
            BY ONLY <2>supported, <1>integerEntry, <2>source, <2>generated, Arithmetic!CertifiedAssignmentListHistoriesAgree
        <2>equal. source = generated
            BY ONLY <2>same, <2>source, <2>generated, SMT DEF Arithmetic!AssignmentListHistory
        <2>. QED BY ONLY <2>equal, <2>source, <2>generated DEF rows, source, generated
    <1>integerOutcomes. \A arm \in ConditionalArms :
        LET rows == ConditionalIntegerRows(arm)
            raw == ConditionalIntegerTable(arm)
            last == Len(rows)
            history == ConditionalIntegerRun(arm)
        IN Arithmetic!RenderedAssignmentHistoryAt(rows, ConditionalBefore, raw, history, last)
        BY ONLY <1>integerRows, <1>integerEntry, <1>integerInventory, <1>integerRuns,
            Arithmetic!PhysicalGuardedAssignmentTablesDetermineTheCompleteOutcome, SMT
            DEF Arithmetic!SupportedAssignmentList
    <1>nativePlans. \A arm \in ConditionalArms :
        ConditionalNativeRows[arm].captures = ConditionalIntegerTable(arm).plans
        <2>. TAKE arm \in ConditionalArms
    \#(nativePlanCases)
        <2>. QED BY ONLY (arm \in ConditionalArms), <1>shape, \#(writeRoleCases), SMT
    <1>nativeReplay. \A arm \in ConditionalArms :
        ConditionalNativeIntegerResult(arm) = Arithmetic!NativeAssignmentPrefix(ConditionalIntegerTerminal(arm))
        <2>. TAKE arm \in ConditionalArms
        <2>. DEFINE rows == ConditionalIntegerRows(arm)
                    raw == ConditionalIntegerTable(arm)
                    plan == ConditionalNativeRows[arm]
                    history == ConditionalIntegerRun(arm)
        <2>known. /\ Arithmetic!SupportedAssignmentList(rows)
                  /\ DOMAIN rows = 1..Len(rows)
                  /\ Arithmetic!AssignmentListHistory(FALSE, ConditionalBefore, rows, history)
                  /\ Arithmetic!RenderedAssignmentInventory(rows, ConditionalBefore, raw)
            BY ONLY (arm \in ConditionalArms), <1>integerRows, <1>integerRuns, <1>integerInventory, SMT
                DEF rows, raw, history, Arithmetic!SupportedAssignmentList
        <2>routes. \A index \in 1..Len(rows) :
            Arithmetic!PhysicalAssignmentReadsMatchRoutes(rows, index, plan.captures[index])
            BY ONLY (arm \in ConditionalArms), <2>known, <1>nativePlans, SMT
                DEF plan, raw, Arithmetic!RenderedAssignmentInventory
        <2>result. Arithmetic!NativeAssignmentCaptureResult(ConditionalBefore, plan, Len(rows)) =
            Arithmetic!NativeAssignmentPrefix(history[Len(rows)])
            BY ONLY <2>known, <2>routes, <1>integerEntry, Arithmetic!PhysicalNativeCaptureResultUsesTheCertifiedTerminal
        <2>count. Len(plan.captures) = Len(rows)
            <3>physical. Len(raw.plans) = IF arm = 1 THEN \#(planNames[0].count) ELSE \#(planNames[1].count)
                BY ONLY (arm \in ConditionalArms), <1>shape, IsaM("simp"), SMT
                    DEF raw, ConditionalIntegerTable, \#(tables.joined(separator: ", "))
            <3>. QED BY ONLY (arm \in ConditionalArms), <1>nativePlans, <1>integerRows, <3>physical, SMT
                DEF plan, raw, rows
        <2>. QED BY ONLY <2>result, <2>count DEF ConditionalNativeIntegerResult, ConditionalIntegerTerminal, plan, rows, history
    <1>nativeCallbacks. \A arm \in ConditionalArms :
        LET calls == ConditionalNativeRows[arm].callbacks
            plans == ConditionalNativeRows[arm].captures
            targets == ConditionalAssignmentOrigins(arm)
        IN /\ DOMAIN calls = {site \in DOMAIN plans : \E n \in 1..plans[site].count : plans[site].kinds[n] = "add"}
           /\ \A site \in DOMAIN calls :
                  LET call == calls[site]
                  IN /\ call.action = ConditionalActionOrdinal /\ call.branch = \#(callbackBranch)
                     /\ call.site = targets[site].binding /\ call.target = targets[site].field
                     /\ DOMAIN call.before = 1..(site - 1)
                     /\ \A i \in DOMAIN call.before :
                            /\ call.before[i].binding = targets[i].binding
                            /\ call.before[i].target = targets[i].field
                            /\ call.before[i].slot = i
        BY ONLY <1>shape, IsaM("simp"), SMT
            DEF ConditionalNativeRows, ConditionalAssignmentOrigins, ConditionalSourceRows, ConditionalActionOrdinal\#(callbackCountDefinition)\#(callbackPlanDefinitions)
    <1>integerFailureSites. \A arm \in ConditionalArms :
        LET terminal == ConditionalIntegerTerminal(arm)
        IN terminal.failure # <<>> =>
            /\ terminal.failure.site \in DOMAIN ConditionalNativeRows[arm].callbacks
            /\ DOMAIN terminal.completed = 1..(terminal.failure.site - 1)\#(afterSharedFailure)
        <2>. TAKE arm \in ConditionalArms
        <2>. DEFINE rows == ConditionalIntegerRows(arm)
                    raw == ConditionalIntegerTable(arm)
                    count == Len(rows)
                    terminal == ConditionalIntegerTerminal(arm)
        <2>. SUFFICES ASSUME terminal.failure # <<>>
                     PROVE /\ terminal.failure.site \in DOMAIN ConditionalNativeRows[arm].callbacks
                           /\ DOMAIN terminal.completed = 1..(terminal.failure.site - 1)\#(afterSharedFailureGoal)
            OBVIOUS
        <2>input. /\ Arithmetic!SupportedAssignmentList(rows)
                  /\ DOMAIN rows = DOMAIN raw.plans
                  /\ DOMAIN rows = 1..count
                  /\ Arithmetic!RenderedAssignmentInventory(rows, ConditionalBefore, raw)
            BY ONLY (arm \in ConditionalArms), <1>integerRows, <1>integerInventory, SMT
                DEF rows, raw, count, Arithmetic!SupportedAssignmentList
        <2>outcome. Arithmetic!RenderedAssignmentHistoryAt(rows, ConditionalBefore, raw, ConditionalIntegerRun(arm), count)
            BY ONLY (arm \in ConditionalArms), <1>integerOutcomes DEF rows, raw, count
        <2>failed. ~Arithmetic!RenderedAssignmentsPass(raw, count)
            BY ONLY <2>outcome, (terminal.failure # <<>>), SMT
                DEF terminal, ConditionalIntegerTerminal, rows, count, Arithmetic!RenderedAssignmentHistoryAt
        <2>site. PICK slot \in 1..count : \E node \in 1..raw.plans[slot].count :
                Arithmetic!RenderedAssignmentFailsAt(raw, count, slot, node)
            BY ONLY <2>input, <2>failed, Arithmetic!WholeGuardTableHasAnExactFirstFailureSite, SMT
        <2>node. PICK node \in 1..raw.plans[slot].count : Arithmetic!RenderedAssignmentFailsAt(raw, count, slot, node)
            BY ONLY <2>site
        <2>reached. /\ terminal.failure.site = slot
                    /\ raw.plans[slot].kinds[node] = "add"
                    /\ terminal.completed = Arithmetic!HistoryPrefix(raw.roots, slot - 1)
            BY ONLY <2>outcome, <2>site, <2>node, SMT
                DEF terminal, ConditionalIntegerTerminal, rows, count, Arithmetic!RenderedAssignmentHistoryAt,
                    Arithmetic!RenderedAssignmentFailure
    \#(afterSharedFailureProof)    <2>. QED BY ONLY (arm \in ConditionalArms), <2>input, <2>site, <2>node, <2>reached, <1>nativePlans, <1>nativeCallbacks,
            \#(afterSharedFailureFact)SMT DEF raw, Arithmetic!HistoryPrefix
    """#
    let historyProof = #"""
    <1>nativeHistory. ConditionalNativeHistory(TRUE) = ConditionalOrderedFailure(
        ConditionalSelectedArm, ConditionalIntegerTerminal(ConditionalSelectedArm))
        <2>. DEFINE arm == ConditionalSelectedArm
                    terminal == ConditionalIntegerTerminal(arm)
                    result == ConditionalNativeIntegerResult(arm)
                    calls == ConditionalNativeRows[arm].callbacks
                    origins == ConditionalAssignmentOrigins(arm)
        <2>replay. result = Arithmetic!NativeAssignmentPrefix(terminal)
            BY ONLY <1>selector, <1>nativeReplay DEF arm, result, terminal
        <2>success. CASE terminal.failure = <<>>
            BY ONLY <2>success, <2>replay, <1>selected, \#(nativeGateFact)SMT
                DEF arm, terminal, result, ConditionalNativeHistory, ConditionalOrderedFailure, Arithmetic!NativeAssignmentPrefix
        <2>failure. CASE terminal.failure # <<>>
            <3>. DEFINE slot == terminal.failure.site
                        call == calls[slot]
            <3>site. /\ slot \in DOMAIN calls
                      /\ DOMAIN terminal.completed = 1..(slot - 1)
                      /\ result.failure # <<>>
                      /\ result.failure.site = slot
                      /\ result.failure.payload = terminal.failure.payload
                      /\ result.completed = terminal.completed\#(sharedPrefix ? "\n                      /\\ ConditionalSharedCount < slot" : "")
                BY ONLY <2>failure, <2>replay, <1>selector, <1>integerFailureSites, \#(callbackSiteFact)SMT
                    DEF arm, terminal, result, calls, slot, Arithmetic!NativeAssignmentPrefix
            <3>metadata. /\ call.action = ConditionalActionOrdinal /\ call.branch = arm - 1
                          /\ call.site = origins[slot].binding /\ call.target = origins[slot].field
                          /\ DOMAIN call.before = DOMAIN terminal.completed
                          /\ \A i \in DOMAIN terminal.completed :
                                 /\ call.before[i].binding = origins[i].binding
                                 /\ call.before[i].target = origins[i].field
                                 /\ call.before[i].slot = i
                BY ONLY <1>selector, <3>site, <1>nativeCallbacks, SMT DEF arm, calls, call, origins
            <3>. QED BY ONLY <3>site, <3>metadata, <1>selected, \#(nativeGateFact)SMT
                DEF arm, terminal, result, call, calls, origins, slot, ConditionalNativeHistory,
                    ConditionalOrderedFailure, ConditionalLabeledFailure, ConditionalFailurePrefix
        <2>. QED BY ONLY <2>success, <2>failure, SMT
    """#
    let materializationInventory = #"""
    <1>nativeSuffix. \A arm \in ConditionalArms :
        ConditionalNativeRows[arm].suffix = ConditionalSourceRows[arm].suffix
    \#(suffixSteps)
        <2>. QED BY ONLY <1>shape, \#(suffixFacts), SMT
    <1>nativeCompleted. \A arm \in ConditionalArms :
        ConditionalNativeCompleted(arm) = ConditionalIntegerTerminal(arm).completed \o ConditionalSourceRows[arm].suffix
        BY ONLY <1>nativeReplay, <1>nativeSuffix, SMT DEF ConditionalNativeCompleted, Arithmetic!NativeAssignmentPrefix
    <1>nativeWriteRoles. \A arm \in ConditionalArms :
        LET raw == ConditionalNativeRows[arm].writes
            routes == ConditionalSourceRows[arm].finalRoutes
        IN /\ Len(raw) \in Nat /\ DOMAIN raw = 1..Len(raw)
           /\ \A i \in DOMAIN raw :
                  /\ raw[i][1] \in ConditionalStateKeys
                  /\ raw[i][2] = routes[raw[i][1]]
           /\ \A key \in ConditionalStateKeys :
                  (\A i \in DOMAIN raw : raw[i][1] # key) => routes[key] = <<"state", key>>
        <2>. TAKE arm \in ConditionalArms
        <2>. DEFINE raw == ConditionalNativeRows[arm].writes
                    routes == ConditionalSourceRows[arm].finalRoutes
    \#(writeRoleSteps)
        <2>. QED BY ONLY (arm \in ConditionalArms), <1>shape, \#(writeRoleCases), SMT DEF raw, routes
    <1>nativeMaterialized. \A arm \in ConditionalArms : \A after :
        ConditionalNativeMaterializes(arm, after) <=> after = ConditionalSourceSuccessor(arm, ConditionalIntegerTerminal(arm))
        <2>. TAKE arm \in ConditionalArms
        <2>. TAKE after
        <2>. DEFINE raw == ConditionalNativeRows[arm].writes
                    writes == ConditionalNativeWrites(arm)
                    count == Len(raw)
                    targets == ConditionalMerge!PendingWriteKeys(writes, count)
                    expected == ConditionalSourceSuccessor(arm, ConditionalIntegerTerminal(arm))
                    routes == ConditionalSourceRows[arm].finalRoutes
                    constraints == ConditionalMerge!NativePendingWriteConstraints(
                        ConditionalStateKeys, ConditionalStateBefore, after, count, writes)
        <2>columns. /\ count \in Nat
                    /\ \A i \in 1..count : writes[i][1] = raw[i][1] /\ raw[i][1] \in ConditionalStateKeys
            BY ONLY (arm \in ConditionalArms), <1>nativeWriteRoles, SMT DEF writes, raw, count, ConditionalNativeWrites
        <2>fold. ConditionalMerge!NativePendingMergesEmit(
            ConditionalStateKeys, ConditionalStateBefore, after, count, writes) <=> constraints
            BY ONLY <2>columns, ConditionalMerge!PendingMergeFoldMaterializesExactlyTheCompatibleWrites, SMT DEF constraints
        <2>written. \A i \in 1..count : expected[writes[i][1]] = writes[i][2]
            BY ONLY (arm \in ConditionalArms), <1>nativeWriteRoles, <1>nativeCompleted, <2>columns, SMT
                DEF expected, count, raw, writes, routes, ConditionalNativeWrites, ConditionalSourceSuccessor,
                    Arithmetic!CopyMaterializedState
        <2>preserved. \A key \in ConditionalStateKeys \ targets : expected[key] = ConditionalStateBefore[key]
            BY ONLY (arm \in ConditionalArms), <1>nativeWriteRoles, <2>columns, SMT
                DEF expected, count, raw, routes, targets, ConditionalSourceSuccessor,
                    ConditionalMerge!PendingWriteKeys, Arithmetic!CopyMaterializedState, Arithmetic!CopyReferenceValue
        <2>frame. expected = [key \in ConditionalStateKeys |-> expected[key]]
            BY ONLY SMT DEF expected, ConditionalSourceSuccessor, Arithmetic!CopyMaterializedState
        <2>forward. ASSUME constraints, after = [key \in ConditionalStateKeys |-> after[key]]
                    PROVE after = expected
            <3>frame. \A key \in ConditionalStateKeys : after[key] = expected[key]
                <4>. TAKE key \in ConditionalStateKeys
                <4>touched. CASE key \in targets
                    <5>witness. PICK i \in 1..count : key = writes[i][1]
                        BY ONLY <4>touched, SMT DEF targets, ConditionalMerge!PendingWriteKeys
                    <5>. QED BY ONLY <5>witness, constraints, <2>written, SMT
                        DEF constraints, ConditionalMerge!NativePendingWriteConstraints
                <4>untouched. CASE key \notin targets
                    BY ONLY (key \in ConditionalStateKeys), <4>untouched, constraints, <2>preserved, SMT
                        DEF constraints, targets, ConditionalMerge!NativePendingWriteConstraints
                <4>. QED BY ONLY <4>touched, <4>untouched, SMT
            <3>. QED BY ONLY <3>frame, <2>frame, (after = [key \in ConditionalStateKeys |-> after[key]]), SMT
        <2>reverse. after = expected => constraints
            BY ONLY <2>written, <2>preserved, SMT DEF constraints, targets, ConditionalMerge!NativePendingWriteConstraints
        <2>. QED BY ONLY <2>fold, <2>forward, <2>reverse, <2>frame, SMT
            DEF ConditionalNativeMaterializes, raw, count, writes, expected
    """#
    let successorProof = #"""
    <1>nativeSuccess. ConditionalNativeStep <=>
        ConditionalOrderedStep(ConditionalSelectedArm, ConditionalIntegerTerminal(ConditionalSelectedArm))
        BY ONLY <1>nativeMaterialized, <1>selected, <1>selector, <1>nativeReplay, \#(nativeGateFact)SMT
            DEF ConditionalNativeStep, ConditionalOrderedStep, Arithmetic!NativeAssignmentPrefix
    <1>nativeQueue. ConditionalNativeVisitorOutput[ConditionalSendVisitor] = ConditionalCertifiedVisitorOutput
        <2>. DEFINE arm == ConditionalSelectedArm
                    terminal == ConditionalIntegerTerminal(arm)
                    expected == ConditionalSourceSuccessor(arm, terminal)
                    result == ConditionalNativeIntegerResult(arm)
        <2>replay. result = Arithmetic!NativeAssignmentPrefix(terminal)
            BY ONLY <1>selector, <1>nativeReplay DEF arm, terminal, result
        <2>success. CASE terminal.failure = <<>>
            <3>target. ConditionalNativeMaterializes(arm, expected) /\
                (CHOOSE after : ConditionalNativeMaterializes(arm, after)) = expected
                BY ONLY <1>selector, <1>nativeMaterialized, SMT DEF arm, terminal, expected
            <3>. QED BY ONLY <2>success, <2>replay, <3>target, <1>selected, \#(queueGateFacts)SMT DEF arm, terminal, result, expected,
                ConditionalNativeVisitorOutput, ConditionalCertifiedVisitorOutput, Arithmetic!NativeAssignmentPrefix
        <2>failure. CASE terminal.failure # <<>>
            <3>caught. terminal.failure.site \in DOMAIN ConditionalNativeRows[arm].callbacks
                BY ONLY <2>failure, <1>selector, <1>integerFailureSites, SMT DEF arm, terminal
            <3>. QED BY ONLY <2>failure, <2>replay, <3>caught, <1>selected, \#(queueGateFacts)SMT DEF arm, terminal, result,
                ConditionalNativeVisitorOutput, ConditionalCertifiedVisitorOutput, Arithmetic!NativeAssignmentPrefix
        <2>. QED BY ONLY <2>success, <2>failure, SMT
    """#
    let inventory = arithmeticInventory + "\n" + materializationInventory
    let selected = historyProof + "\n" + successorProof
    if sharedPrefix {
        let nativePrefixPass = #"""
        <1>nativePrefixPass. ConditionalNativeAfterSharedPrefix
            BY ONLY <1>nativePrefixReach, <1>prefixPass
        """#
        return (rowDefinitions, captureNames, definitions, "", inventory, nativePrefixPass + "\n" + selected)
    }
    // Keep the original declaration order for an empty prefix.
    let steps = arithmeticInventory + "\n" + historyProof + "\n\n"
        + materializationInventory + "\n" + successorProof
    return (rowDefinitions, captureNames, definitions, steps, inventory, selected)
}

/// Bind the preselection observation to the independently decoded TLA probes
/// and the single native visitor path ending at the selector.
func conditionalSharedFailureProof(
    native: NativeConditionalActionOutput, sharedCount: Int, guardNames: [String],
    overflow: (aggregate: String, evaluationCheck: String)?, actionName: String, tableDefinitions: [String]
) throws -> (planDefinitions: String, collectorDefinitions: String, observationDefinition: String,
             inventorySteps: String, failureSteps: String) {
    guard sharedCount > 0, native.sharedPrefix.capturePlans.count == sharedCount,
          (overflow == nil) == guardNames.isEmpty,
          overflow != nil || native.sharedPrefix.failureAppendSites.isEmpty else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    let trace = try native.sharedPrefix.integerTrace(count: sharedCount)
    let tables = (["ConditionalSharedTable"] + tableDefinitions).joined(separator: ", ")
    let planDefinitions = #"""
    ConditionalNativeSharedPlan == \#(trace)
    ConditionalNativeSharedResult ==
        Arithmetic!NativeAssignmentCaptureResult(ConditionalBefore, ConditionalNativeSharedPlan, ConditionalSharedCount)
    ConditionalNativeAfterSharedPrefix == ConditionalNativeSharedResult.failure = <<>>
    """#
    let collectorDefinitions = #"""
    ConditionalSharedEvent(terminal) ==
        IF terminal.failure = <<>> THEN <<>>
        ELSE LET origin == ConditionalSharedOrigins[terminal.failure.site]
                 completed == terminal.completed
                 before == [i \in DOMAIN completed |-> [
                     binding |-> ConditionalSharedOrigins[i].binding,
                     target |-> ConditionalSharedOrigins[i].field,
                     value |-> completed[i]]]
             IN <<[source |-> ConditionalEntry, action |-> ConditionalActionOrdinal, branch |-> <<>>,
                   site |-> origin.binding, target |-> origin.field, payload |-> terminal.failure.payload, before |-> before]>>
    ConditionalNativeSharedHistory(recording) ==
        LET result == ConditionalNativeSharedResult
            calls == ConditionalNativeSharedPlan.callbacks
        IN IF ~recording \/ result.failure = <<>> THEN <<>>
           ELSE IF result.failure.site \notin DOMAIN calls THEN <<>>
           ELSE LET call == calls[result.failure.site]
                    before == [i \in DOMAIN call.before |-> [
                        binding |-> call.before[i].binding, target |-> call.before[i].target,
                        value |-> result.completed[call.before[i].slot]]]
                IN <<[source |-> ConditionalEntry, action |-> call.action, branch |-> call.branch,
                      site |-> call.site, target |-> call.target, payload |-> result.failure.payload, before |-> before]>>
    ConditionalNativeSharedVisitorOutput ==
        LET result == ConditionalNativeSharedResult
        IN [callbacks |-> <<>>,
            reasons |-> IF result.failure # <<>> /\ result.failure.site \in DOMAIN ConditionalNativeSharedPlan.callbacks
                        THEN <<result.failure.payload>> ELSE <<>>]
    """#
    let inventorySteps = #"""
    <1>sharedNativeReplay. ConditionalNativeSharedResult = Arithmetic!NativeAssignmentPrefix(ConditionalSharedTerminal)
        BY ONLY <1>sharedRows, <1>sharedRun, <1>integerEntry, <1>sharedNativeInventory,
            Arithmetic!PhysicalNativeCaptureResultUsesTheCertifiedTerminal, SMT DEF
            ConditionalSharedTerminal, ConditionalNativeSharedResult
    <1>nativePrefixReach. ConditionalSharedTerminal.failure = <<>> => ConditionalNativeAfterSharedPrefix
        BY ONLY <1>sharedNativeReplay, SMT DEF ConditionalNativeAfterSharedPrefix, Arithmetic!NativeAssignmentPrefix
    <1>sharedNativeCallbacks.
        LET calls == ConditionalNativeSharedPlan.callbacks
            plans == ConditionalNativeSharedPlan.captures
        IN /\ DOMAIN calls = {slot \in DOMAIN plans : \E node \in 1..plans[slot].count : plans[slot].kinds[node] = "add"}
           /\ \A slot \in DOMAIN calls :
                 LET call == calls[slot]
                 IN /\ call.action = ConditionalActionOrdinal /\ call.branch = <<>>
                    /\ call.site = ConditionalSharedOrigins[slot].binding
                    /\ call.target = ConditionalSharedOrigins[slot].field
                    /\ DOMAIN call.before = 1..(slot - 1)
                    /\ \A i \in DOMAIN call.before :
                           /\ call.before[i].binding = ConditionalSharedOrigins[i].binding
                           /\ call.before[i].target = ConditionalSharedOrigins[i].field
                           /\ call.before[i].slot = i
        BY ONLY IsaM("simp"), SMT DEF ConditionalNativeSharedPlan, ConditionalSharedOrigins, ConditionalActionOrdinal
    """#
    guard let overflow else {
        let failureSteps = #"""
        <1>sharedTotal. Arithmetic!RenderedAssignmentsPass(ConditionalSharedTable, ConditionalSharedCount)
            BY ONLY SMT DEF ConditionalSharedCount, \#(tables), Arithmetic!RenderedAssignmentsPass,
                Arithmetic!EveryRenderedGuardPasses
        <1>sharedFailure. ConditionalSharedTerminal.failure # <<>> => ConditionalSharedFailureObservations
            BY ONLY <1>sharedPasses, <1>sharedTotal, SMT DEF ConditionalSharedFailureObservations
        """#
        return (planDefinitions, collectorDefinitions, "ConditionalSharedFailureObservations == FALSE", inventorySteps, failureSteps)
    }
    let guardDefinitions = (["ConditionalProbeGuards", overflow.evaluationCheck, overflow.aggregate] + guardNames)
        .joined(separator: ", ")
    let observationDefinition = #"""
    ConditionalSharedFailureObservations ==
        /\ ConditionalSharedTerminal.failure # <<>>
        /\ ConditionalNativeSharedResult.failure # <<>>
        /\ ActualConditionalHistory = ConditionalSharedEvent(ConditionalSharedTerminal)
        /\ ConditionalNativeHistory(TRUE) = ConditionalSharedEvent(ConditionalSharedTerminal)
        /\ ConditionalNativeHistory(FALSE) = <<>>
        /\ ~Arithmetic!RenderedAssignmentsPass(ConditionalSharedTable, ConditionalSharedCount)
        /\ ~ConditionalSelectedEvaluationCheck
        /\ ~ConditionalPhysicalStep
        /\ ~ENABLED Next
        /\ ~ConditionalNativeStep
        /\ ConditionalNativeVisitorOutput[ConditionalSendVisitor] =
               [callbacks |-> <<>>, reasons |-> <<ConditionalSharedTerminal.failure.payload>>]
        /\ ConditionalNativeVisitorOutput[ConditionalSendVisitor] = ConditionalCertifiedVisitorOutput
    """#
    let failureSteps = #"""
    <1>sharedFailure. ConditionalSharedTerminal.failure # <<>> => ConditionalSharedFailureObservations
        <2>. DEFINE terminal == ConditionalSharedTerminal
                    rows == ConditionalSharedRows
                    raw == ConditionalSharedTable
                    count == ConditionalSharedCount
                    result == ConditionalNativeSharedResult
                    calls == ConditionalNativeSharedPlan.callbacks
        <2>. SUFFICES ASSUME terminal.failure # <<>>
                      PROVE ConditionalSharedFailureObservations
            BY DEF terminal
        <2>failed. ~Arithmetic!RenderedAssignmentsPass(raw, count)
            BY ONLY <1>sharedReached, (terminal.failure # <<>>), SMT DEF terminal, ConditionalSharedTerminal,
                raw, count, Arithmetic!RenderedAssignmentHistoryAt
        <2>first. PICK slot \in 1..count : \E node \in 1..raw.plans[slot].count :
                  Arithmetic!RenderedAssignmentFailsAt(raw, count, slot, node)
            BY ONLY <1>sharedRows, <1>sharedInventory, <2>failed, Arithmetic!WholeGuardTableHasAnExactFirstFailureSite,
                SMT DEF rows, raw, count
        <2>node. PICK node \in 1..raw.plans[slot].count : Arithmetic!RenderedAssignmentFailsAt(raw, count, slot, node)
            BY ONLY <2>first
        <2>reached. /\ terminal.failure.site = slot
                    /\ raw.plans[slot].kinds[node] = "add"
                    /\ terminal.failure = Arithmetic!RenderedAssignmentFailure(rows, ConditionalBefore, raw, slot, node)
                    /\ terminal.completed = Arithmetic!HistoryPrefix(raw.roots, slot - 1)
            BY ONLY <1>sharedReached, <2>first, <2>node, SMT DEF terminal, ConditionalSharedTerminal,
                raw, count, Arithmetic!RenderedAssignmentHistoryAt, Arithmetic!RenderedAssignmentFailure
        <2>chosen. PICK p \in DOMAIN ConditionalProbePositions : ConditionalProbePositions[p] = <<<<>>, slot, node>>
            BY ONLY <2>first, <2>node, <2>reached, <1>probeInventory, SMT DEF raw, count
        <2>fires. ConditionalProbeGuards[p]
            BY ONLY <2>chosen, <2>node, <1>probeReach, SMT DEF raw, count
        <2>eventData. /\ ConditionalProbePayloads[p] = terminal.failure.payload
                      /\ ConditionalProbeBefore[p] = ConditionalProbeFailurePrefix(<<>>, terminal.completed)
            BY ONLY <2>chosen, <2>fires, <2>reached, <1>probeValues, SMT DEF rows, raw
        <2>history. ActualConditionalHistory = ConditionalSharedEvent(terminal)
            BY ONLY <2>chosen, <2>fires, <2>eventData, <2>reached, <1>probeOne, (terminal.failure # <<>>), SMT
                DEF ConditionalExportedProbe, ConditionalSharedEvent, ConditionalProbeFailurePrefix
        <2>checking. ~ConditionalSelectedEvaluationCheck
            BY ONLY <2>chosen, <2>fires, SMT DEF ConditionalSelectedEvaluationCheck, \#(guardDefinitions)
        <2>physicalDisabled. ~ConditionalPhysicalStep
            BY ONLY <2>failed, SMT DEF ConditionalPhysicalStep, \#(actionName), raw, count,
                ConditionalSharedCount, \#(tables), Arithmetic!RenderedAssignmentsPass, Arithmetic!EveryRenderedGuardPasses
        <2>disabled. ~ENABLED Next
            BY ONLY <2>checking, ConditionalFailedCheckDisablesEmittedNext, PTL
        <2>nativePlans. ConditionalNativeSharedPlan.captures = raw.plans
            BY ONLY IsaM("simp"), SMT DEF ConditionalNativeSharedPlan, raw, \#(tables)
        <2>caught. /\ slot \in DOMAIN calls /\ DOMAIN terminal.completed = 1..(slot - 1)
                   /\ result.failure # <<>> /\ result.failure.site = slot
                   /\ result.failure.payload = terminal.failure.payload /\ result.completed = terminal.completed
            BY ONLY <1>sharedNativeReplay, <1>sharedNativeCallbacks, <2>first, <2>node, <2>reached, <2>nativePlans,
                (terminal.failure # <<>>), SMT DEF terminal, calls, result, Arithmetic!NativeAssignmentPrefix, Arithmetic!HistoryPrefix
        <2>native. /\ ConditionalNativeSharedHistory(TRUE) = ConditionalSharedEvent(terminal)
                   /\ ConditionalNativeSharedHistory(FALSE) = <<>>
                   /\ ConditionalNativeSharedVisitorOutput =
                          [callbacks |-> <<>>, reasons |-> <<terminal.failure.payload>>]
            BY ONLY <2>caught, <2>reached, <1>sharedNativeCallbacks, (terminal.failure # <<>>), SMT DEF
                calls, result, ConditionalSharedEvent, ConditionalNativeSharedHistory, ConditionalNativeSharedVisitorOutput
        <2>. QED BY ONLY <2>caught, <2>history, <2>failed, <2>checking, <2>physicalDisabled, <2>disabled, <2>native,
            (terminal.failure # <<>>), SMT DEF terminal, result, raw, count, ConditionalSharedFailureObservations,
            ConditionalNativeAfterSharedPrefix, ConditionalNativeStep, ConditionalNativeHistory, ConditionalNativeVisitorOutput,
            ConditionalCertifiedVisitorOutput
    """#
    return (planDefinitions, collectorDefinitions, observationDefinition, inventorySteps, failureSteps)
}
