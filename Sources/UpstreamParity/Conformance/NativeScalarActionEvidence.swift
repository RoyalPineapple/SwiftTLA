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

    var selectedActionDefinitions: String {
        let plans = captures.map(\.columns)
        func column(_ path: KeyPath<ArithmeticCapturePlan, [String]>) -> String {
            actionTuple(plans.map { actionTuple($0[keyPath: path]) })
        }
        return #"""
        NativeSelectedCaptureTags == \#(actionTuple(captures.map { TLAValue.string($0.tag).description }))
        NativeSelectedNodeCounts == \#(actionTuple(plans.map { String($0.kinds.count) }))
        NativeSelectedNodeKinds == \#(column(\.kinds))
        NativeSelectedNodeLiterals == \#(column(\.literals))
        NativeSelectedNodeReads == \#(column(\.reads))
        NativeSelectedNodeLeft == \#(column(\.left))
        NativeSelectedNodeRight == \#(column(\.right))
        NativeSelectedGuards == \#(actionTuple(guards))
        NativeSelectedWrites == \#(actionTuple(writes))
        NativeSelectedFailureAppendSites == \#(actionTuple(failureAppendSites.map(String.init)))
        NativeSelectedPlans == [index \in DOMAIN NativeSelectedCaptureTags |->
            [count |-> NativeSelectedNodeCounts[index], kinds |-> NativeSelectedNodeKinds[index],
             literals |-> NativeSelectedNodeLiterals[index], reads |-> NativeSelectedNodeReads[index],
             left |-> NativeSelectedNodeLeft[index], right |-> NativeSelectedNodeRight[index]]]
        NativeSelectedCaptures == [index \in DOMAIN NativeSelectedCaptureTags |->
            IF NativeSelectedCaptureTags[index] = "expression" THEN <<"expression", NativeSelectedPlans[index]>>
            ELSE IF NativeSelectedCaptureTags[index] = "literal" THEN <<"literal", NativeSelectedNodeLiterals[index][1]>>
            ELSE NativeSelectedNodeReads[index][1]]
        NativeSelectedAction == [captures |-> NativeSelectedCaptures, guards |-> NativeSelectedGuards, writes |-> NativeSelectedWrites]
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

// Interpret the scalar continuation grammar. Its reads come from the retained Swift.
package func nativeScalarActionEvidence(_ source: String, program: CompiledProgram) throws -> Data {
    let definitions = try nativeScalarActionDefinitions(source, program: program)
    return Data("""
    ---- MODULE SwiftTLANativeActions ----
    \(definitions)
    ====

    """.utf8)
}

func nativeScalarActionDefinitions(_ source: String, program: CompiledProgram, selectedActionOrdinal: Int? = nil) throws -> String {
    let actions = try decodeScalarActions(source, program: program, predicate: nil)
    var selectedDefinitions = ""
    if let selectedActionOrdinal {
        guard actions.indices.contains(selectedActionOrdinal) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        selectedDefinitions = actions[selectedActionOrdinal].plans[0].selectedActionDefinitions + "\n"
    }
    let rows = actions.enumerated().map { index, action in
        let plan = selectedActionOrdinal == index ? "NativeSelectedAction" : action.plans[0].tla
        return "<<\(TLAValue.string(action.label)), \(plan)>>"
    }
    let dispatch = TLAValue.tuple(actions.map { .string($0.formalLabel) })
    return """
    \(selectedDefinitions)NativeActionRows == \(actionTuple(rows))
    NativeActionDispatchLabels == \(dispatch)
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
    -> [(label: String, formalLabel: String, fields: [String], visit: NativeConditionalVisit?, plans: [ActionInstructions])] {

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
    func checkFunction(_ spelling: String, named name: String, arity: Int, firstLabel: String? = nil) throws {
        try require(checked(functions.filter {
            $0.name.text == name && $0.signature.parameterClause.parameters.count == arity
                && (firstLabel == nil || $0.signature.parameterClause.parameters.first?.firstName.text == firstLabel)
        }), spelling)
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
    try checkFunction("""
    private func _visitSuccessors(for action: Action, \(checking),
        _ visit: (Snapshot) throws -> Void) throws -> [NativeMachineEvaluationError] {
        switch action { \(routes) }
    }
    """, named: "_visitSuccessors", arity: 3, firstLabel: "for")

    let rows = try compiledActions.enumerated().map { index, action in
        let visitor = try checked(functions.filter { $0.name.text == "_visitUpdates\(index)" })
        let decoded = try decodeScalarActionVisitor(visitor, index: index, fields: fields, control: control,
            locations: locations.map { ($0.caseName, $0.label) }, checking: checking, predicate: predicate)
        let successor = try checked(functions.filter { $0.name.text == "_visitSuccessors\(index)" })
        try verifyGeneratedSuccessorOutput(DeclSyntax(successor), actionID: index, parameters: "", arguments: "",
            configurationParameters: "", configurationArguments: "")
        return (label: action.declaration.name, formalLabel: formalLabels[index], fields: fields.map(\.name),
            visit: decoded.visit, plans: decoded.plans)
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
