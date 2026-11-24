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
    let operand: String
    let type: String

    var tla: String { "<<\(TLAValue.string(kind)), \(operand)>>" }
}

private func actionTuple(_ values: [String]) -> String {
    "<<\(values.joined(separator: ", "))>>"
}

private struct ArithmeticCapturePlan {
    var kinds: [String] = []
    var literals: [String] = []
    var reads: [String] = []
    var left: [String] = []
    var right: [String] = []

    var tla: String {
        "[count |-> \(kinds.count), kinds |-> \(actionTuple(kinds)), "
            + "literals |-> \(actionTuple(literals)), reads |-> \(actionTuple(reads)), "
            + "left |-> \(actionTuple(left)), right |-> \(actionTuple(right))]"
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
            return ArithmeticCapturePlan(kinds: [literal ? "\"literal\"" : "\"read\""],
                literals: [literal ? reference.operand : "0"],
                reads: [literal ? "<<>>" : reference.tla], left: ["0"], right: ["0"])
        case .expression(let plan):
            return plan
        }
    }
}

private struct ActionInstructions {
    var captures: [ActionCapture] = []
    var guards: [String] = []
    var writes: [String] = []
    var failureAppendSites: [Int] = []

    var tla: String {
        "[captures |-> \(actionTuple(captures.map(\.tla))), "
            + "guards |-> \(actionTuple(guards)), writes |-> \(actionTuple(writes))]"
    }

    func selectedActionDefinitions(prefix: String = "NativeSelected") -> String {
        let plans = captures.map(\.columns)
        func column(_ path: KeyPath<ArithmeticCapturePlan, [String]>) -> String {
            actionTuple(plans.map { actionTuple($0[keyPath: path]) })
        }
        return #"""
        \#(prefix)CaptureTags == \#(actionTuple(captures.map { TLAValue.string($0.tag).description }))
        \#(prefix)NodeCounts == \#(actionTuple(plans.map { String($0.kinds.count) }))
        \#(prefix)NodeKinds == \#(column(\.kinds))
        \#(prefix)NodeLiterals == \#(column(\.literals))
        \#(prefix)NodeReads == \#(column(\.reads))
        \#(prefix)NodeLeft == \#(column(\.left))
        \#(prefix)NodeRight == \#(column(\.right))
        \#(prefix)Guards == \#(actionTuple(guards))
        \#(prefix)Writes == \#(actionTuple(writes))
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

private func nativeArithmeticCapture(_ steps: [NativeIntInitialStep]) -> ArithmeticCapturePlan {
    var plan = ArithmeticCapturePlan()
    for step in steps {
        switch step {
        case .integer(let value):
            plan.kinds.append("\"literal\"")
            plan.literals.append(InitialFailureEvidence.binaryLiteral(value))
            plan.reads.append("<<>>")
            plan.left.append("0")
            plan.right.append("0")
        case .slot(let reference):
            plan.kinds.append("\"read\"")
            plan.literals.append("0")
            plan.reads.append(reference)
            plan.left.append("0")
            plan.right.append("0")
        case .add(let first, let second):
            plan.kinds.append("\"add\"")
            plan.literals.append("0")
            plan.reads.append("<<>>")
            plan.left.append(String(first + 1))
            plan.right.append(String(second + 1))
        }
    }
    return plan
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

package func verifyNativeMemberTokens(compiled: String, attached: String) throws {
    let actual = Parser.parse(source: compiled)
    let candidate = Parser.parse(source: attached)
    guard !compiled.utf8.contains(0), !attached.utf8.contains(0),
          !actual.hasError, !candidate.hasError,
          !actual.statements.isEmpty,
          syntaxWords(actual).elementsEqual(syntaxWords(candidate), by: { $0.utf8.elementsEqual($1.utf8) })
    else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
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
    let dispatch = try instructions(method(visitor, arity: 3))
    guard let choice = dispatch.first.flatMap(value)?.as(SwitchExprSyntax.self) else { throw invalid }
    let receivers = try choice.cases.map { item -> (String, String) in
        guard let branch = item.as(SwitchCaseSyntax.self), let label = branch.label.as(SwitchCaseLabelSyntax.self),
              let pattern = label.caseItems.first?.pattern, let handle = syntaxWords(pattern).last,
              let returned = branch.statements.first?.item.as(ReturnStmtSyntax.self),
              let routed = returned.expression?.as(TryExprSyntax.self)?.expression.as(FunctionCallExprSyntax.self),
              let from = routed.arguments.first, from.label?.text == "from",
              let receiver = reference(from.expression) else { throw invalid }
        return (handle, receiver)
    }

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
    let targets = receivers.map { "[handle |-> \(string($0.0)), slot |-> \(string($0.1))]" }

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
        ("receivers", actionTuple(targets)), ("selectorGuards", tests),
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
    let handles = receivers.map { string($0.0) }.joined(separator: ", ")
    let operandFields = bindingFields.filter { $0.0 != "checking" && $0.0 != "selectorGuards" }
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
        BY ONLY <1>receivers, SMT
    <1>route.
        /\\ \\E row \\in DOMAIN \(binding).receivers : \(binding).receivers[row].handle = action
        /\\ \\A row \\in DOMAIN \(binding).receivers :
               \(binding).receivers[row].handle = action => \(binding).receivers[row].slot = \(binding).writeTarget
        BY ONLY (action \\in {\(handles)}), <1>receiverIndices, <1>receivers, <1>writeTarget, SMT
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

func nativeConditionalActionPlans(_ source: String, program: CompiledProgram, predicate: [String]) throws
    -> (children: String, plans: String, fields: String) {
    let row = try checked(decodeScalarActions(source, program: program, predicate: predicate))
    guard row.label == "choose", let visit = row.visit else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    let first = visit.ifTrue.id, second = visit.ifFalse.id
    return ("<<\(first), \(second)>>",
        "[child \\in {\(first), \(second)} |-> IF child = \(first) THEN \(row.plans[0].tla) ELSE \(row.plans[1].tla)]",
        TLAValue.set(Set(row.fields.map(TLAValue.string))).description)
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
    let storage = fields.map { "var \($0.slot): \($0.type)? = nil" }.joined(separator: "\n")
    let merging = fields.map {
        "guard SwiftTLA._NativeMachineOperations.mergeUpdate(&result.\($0.slot), other.\($0.slot)) else { return nil }"
    }.joined(separator: "\n")
    let materialized = visible.map { "\($0.member!): \($0.slot) ?? \($0.before)" }.joined(separator: ", ")
    let hiddenArguments = hidden.map { ", \($0.slot): \($0.slot) ?? \($0.before)" }.joined()
    try require(checked(structs.filter { $0.name.text == "_Updates" }), """
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
    """)

    let execution = try checked(declarations.compactMap { $0.as(VariableDeclSyntax.self) }.filter {
        $0.bindings.contains { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "_execution" }
    })
    try require(execution, "private var _execution: Snapshot")
    try require(checked(declarations.compactMap { $0.as(InitializerDeclSyntax.self) }.filter {
        $0.signature.parameterClause.parameters.first?.firstName.text == "execution"
    }), "private init(execution: Snapshot) { _execution = execution }")

    let action = try checked(enums.filter { $0.name.text == "Action" })
    let labels = action.memberBlock.members.compactMap { item -> String? in
        guard let declaration = item.decl.as(EnumCaseDeclSyntax.self), declaration.elements.count == 1 else { return nil }
        return declaration.elements.first?.name.text
    }
    let compiledActions = program.layout.actions
    guard !labels.isEmpty, Set(labels).count == labels.count,
          labels.count == compiledActions.count,
          compiledActions.enumerated().allSatisfy({ $0.offset == $0.element.id.ordinal }) else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    let actionCases = try labels.map { "case \(try nativeSourceIdentifier($0))" }.joined(separator: "\n")
    try require(action, "public enum Action: Hashable, Sendable { \(actionCases) }")
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
    let routes = qualifiedLabels.enumerated().map {
        "case .\($0.element): return try Self._visitSuccessors\($0.offset)(from: _execution, checking: &context, visit)"
    }.joined(separator: "\n")
    let dispatch = try checkFunction("""
    private func _visitSuccessors(for action: Action, \(checking),
        _ visit: (Snapshot) throws -> Void) throws -> [NativeMachineEvaluationError] {
        switch action { \(routes) }
    }
    """, named: "_visitSuccessors", arity: 3, firstLabel: "for")
    guard let dispatchItem = dispatch.body?.statements.first?.item,
          let dispatchSwitch = (dispatchItem.as(ExprSyntax.self) ?? dispatchItem.as(ExpressionStmtSyntax.self)?.expression)?
              .as(SwitchExprSyntax.self), dispatchSwitch.cases.count == compiledActions.count else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    // CheckFunction established the switch and forwarded arguments. Read the
    // actual callee suffix for each candidate rather than exporting its position.
    let physicalTargets = try dispatchSwitch.cases.map { item -> Int in
        guard let branch = item.as(SwitchCaseSyntax.self),
              let returned = branch.statements.first?.item.as(ReturnStmtSyntax.self),
              let call = returned.expression?.as(TryExprSyntax.self)?.expression.as(FunctionCallExprSyntax.self),
              let name = call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text,
              let ordinal = Int(name.dropFirst("_visitSuccessors".count)),
              name == "_visitSuccessors\(ordinal)", compiledActions.indices.contains(ordinal) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        return ordinal + 1
    }

    let rows = try compiledActions.enumerated().map { index, action in
        let visitor = try checked(functions.filter { $0.name.text == "_visitUpdates\(index)" })
        let decoded = try decodeScalarActionVisitor(visitor, index: index, fields: fields, control: control,
            locations: locations.map { ($0.caseName, $0.label) }, checking: checking, predicate: predicate)
        let successor = try checked(functions.filter { $0.name.text == "_visitSuccessors\(index)" })
        try verifyGeneratedSuccessorOutput(DeclSyntax(successor), actionID: index, parameters: "", arguments: "",
            configurationParameters: "", configurationArguments: "")
        return (label: action.declaration.name, formalLabel: formalLabels[index], handle: labels[index],
            visitor: physicalTargets[index], fields: fields.map(\.name), visit: decoded.visit, plans: decoded.plans)
    }
    try checkNativeValidationActionRoute(functions)
    return rows
}

private func decodeScalarActionVisitor(_ visitor: FunctionDeclSyntax, index: Int,
    fields: [ActionField], control: ActionField?, locations: [(caseName: String, label: String)],
    checking: String, predicate: [String]?) throws -> (visit: NativeConditionalVisit?, plans: [ActionInstructions]) {
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
    var visited: Set<String> = []
    let stateReads: [(String, ActionReference)] = fields.map {
        ($0.before, .init(kind: "state", operand: TLAValue.string($0.name).description, type: $0.type))
    }
    let controlValues = control.map { field in
        locations.map {
            ("\(field.type).\($0.caseName)", ActionReference(kind: "control",
                operand: TLAValue.string($0.label).description, type: field.type))
        }
    } ?? []
    let booleanValues = [("true", "TRUE"), ("false", "FALSE")].map {
        ($0.0, ActionReference(kind: "literal", operand: $0.1, type: boolType))
    }

    typealias Binding = (local: String, value: ActionReference)
    func partCore(_ name: String, scope: [Binding]) throws -> (tokens: [String], recordsFailure: Bool) {
        guard let part = byName[name], let body = part.body, visited.insert(name).inserted else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let formal = scope.map { "_ \($0.local): \($0.value.type), " }.joined()
        let tokens = syntaxWords(body)
        let prefix = words("{ do {")
        let handler = "} catch let failure as NativeMachineEvaluationError where failure.isModelEvaluationFailure {"
        let append = "failures.append(failure) } }"
        let observer = nativeOrderedIntAssignmentFailureSource(actionOrdinal: index, preceding: scope.map(\.local))
        let observed = words("\(handler)\n\(observer)\n\(append)")
        let recordsFailure = tokens.suffix(observed.count).elementsEqual(observed)
        let suffix = recordsFailure ? observed : words("\(handler)\n\(append)")
        guard tokens.count > prefix.count + suffix.count else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let core = Array(tokens.dropFirst(prefix.count).dropLast(suffix.count))
        let recording = recordsFailure ? "\(observer)\n" : ""
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

        return (core, recordsFailure)
    }

    func walk(_ entry: String) throws -> ActionInstructions {
        var instructions = ActionInstructions()
        var capturesFollowGuard = true
        var pending: [(String, [Binding])] = [(entry, [])]
        parts: while let (name, scope) = pending.popLast() {
            let (core, recordsFailure) = try partCore(name, scope: scope)
            guard !recordsFailure || (predicate == nil && core.first == "let"
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
                    && instructions.guards.count == 1 && instructions.writes.isEmpty
                    && scope.count == instructions.captures.count
                    && scope.enumerated().allSatisfy { offset, binding in
                        binding.value.kind == "capture" && binding.value.operand == String(offset + 1)
                    }
                if recordsFailure {
                    let intType = nativeIntTypeTokens.joined()
                    let references = Dictionary(uniqueKeysWithValues: (stateReads + boundReads)
                        .filter { $0.1.type == intType }.map { (words($0.0), $0.1.tla) })
                    guard let decoded = decodeNativeOrderedIntExpression(rhs[...], reads: references),
                          decoded.consumed == rhs.count, decoded.steps.count > 1,
                          sameWords(core, """
                          let \(local) = \(rhs.joined(separator: " "))
                          try \(child)(\(argument)\(local), updates, emit)
                          """) else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
                    instructions.captures.append(.expression(nativeArithmeticCapture(decoded.steps)))
                    // partCore verified that this lexical catch appends its bound reason to the returned buffer.
                    instructions.failureAppendSites.append(instructions.captures.count)
                    let reference = ActionReference(kind: "capture", operand: String(instructions.captures.count), type: intType)
                    pending.append((child, scope + [(local, reference)]))
                    continue parts
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
                    reads.append((rhs.joined(), .init(kind: "literal", operand: InitialFailureEvidence.binaryLiteral(integer),
                                                       type: nativeIntTypeTokens.joined())))
                }
                for (spelling, value) in reads where
                    sameWords(core, "let \(local) = \(spelling)\ntry \(child)(\(argument)\(local), updates, emit)") {
                    instructions.captures.append(.reference(value))
                    let reference = ActionReference(kind: "capture", operand: String(instructions.captures.count), type: value.type)
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
                    instructions.writes.append("<<\(TLAValue.string(field.name)), \(value.tla)>>")
                    continue parts
                }
            }
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        // The split receipt retains a single entry decision, then captures, then writes.
        guard instructions.failureAppendSites.isEmpty || (capturesFollowGuard && instructions.guards.count == 1) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        return instructions
    }

    let visit: NativeConditionalVisit?
    let plans: [ActionInstructions]
    if let predicate {
        let (root, recordsFailure) = try partCore("_actionPart0", scope: [])
        let body = byName["_actionPart0"]?.body?.statements.first?.item.as(DoStmtSyntax.self)?.body.statements
        guard !recordsFailure, body?.count == 1, let item = body?.first?.item,
              let expression = item.as(TryExprSyntax.self) ?? item.as(ExpressionStmtSyntax.self)?.expression.as(TryExprSyntax.self),
              syntaxWords(expression) == root, let conditional = nativeConditionalVisit(Syntax(expression)),
              conditional.predicate == predicate, conditional.ifTrue.arguments == ["updates", "emit"],
              conditional.ifFalse.arguments == ["updates", "emit"] else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        visit = conditional
        plans = try [walk("_actionPart\(conditional.ifTrue.id)"), walk("_actionPart\(conditional.ifFalse.id)")]
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
