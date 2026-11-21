import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA
import SwiftTLACompilerSupport

private struct ActionField {
    let name: String
    let slot: String
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

private struct ActionInstructions {
    var captures: [String] = []
    var guards: [String] = []
    var writes: [String] = []

    var tla: String {
        "[captures |-> <<\(captures.joined(separator: ", "))>>, "
            + "guards |-> <<\(guards.joined(separator: ", "))>>, "
            + "writes |-> <<\(writes.joined(separator: ", "))>>]"
    }
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

// Interpret only the total scalar continuation grammar. Its reads come from the retained Swift.
package func nativeScalarActionEvidence(_ source: String, program: CompiledProgram) throws -> Data {
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
        case (.source, .int):
            return .init(name: variable.formalName, slot: slot,
                member: try nativeSourceIdentifier(variable.declaration.name), type: intType)
        case (.programCounter, .controlLocation):
            return .init(name: variable.formalName, slot: slot, member: nil, type: controlType)
        default: throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
    }
    let control = try checked(fields.filter { $0.member == nil && $0.name == "pc" })
    let visible = fields.filter { $0.member != nil }
    let locations = program.layout.controlLocations.map {
        (caseName: "location\($0.id.ordinal)", ordinal: $0.id.ordinal, label: $0.formalName)
    }
    guard !visible.isEmpty, !locations.isEmpty else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }

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
    let inputs = visible.enumerated().map { (index: $0.offset + 1, field: $0.element) }
    let stateStorage = visible.map { "public let \($0.member!): \($0.type)" }.joined(separator: "\n")
    let parameters = inputs.map { "\($0.field.member!) _value\($0.index): \($0.field.type)" }.joined(separator: ", ")
    let assignments = inputs.map { "self.\($0.field.member!) = _value\($0.index)" }.joined(separator: "\n")
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
    try require(checked(structs.filter { $0.name.text == "Snapshot" }), """
    public struct Snapshot: Hashable, Sendable {
        public let state: State
        let \(control.slot): \(controlType)
    }
    """)
    let controlCases = locations.map { "case \($0.caseName) = \($0.ordinal)" }.joined(separator: "\n")
    try require(checked(enums.filter { $0.name.text == controlType }), """
    @_documentation(visibility: internal)
    public enum \(controlType): \(intType), Hashable, Sendable { \(controlCases) }
    """)
    let storage = fields.map { "var \($0.slot): \($0.type)? = nil" }.joined(separator: "\n")
    let merging = fields.map {
        "guard SwiftTLA._NativeMachineOperations.mergeUpdate(&result.\($0.slot), other.\($0.slot)) else { return nil }"
    }.joined(separator: "\n")
    let materialized = visible.map { "\($0.member!): \($0.slot) ?? \($0.before)" }.joined(separator: ", ")
    try require(checked(structs.filter { $0.name.text == "_Updates" }), """
    private struct _Updates: Sendable {
        \(storage)
        func merging(_ other: Self) -> Self? {
            var result = self
            \(merging)
            return result
        }
        func applying(to state: Snapshot) -> Snapshot {
            Snapshot(state: State(\(materialized)), \(control.slot): \(control.slot) ?? \(control.before))
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
    guard !labels.isEmpty, Set(labels).count == labels.count else {
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }
    let actionCases = try labels.map { "case \(try nativeSourceIdentifier($0))" }.joined(separator: "\n")
    try require(action, "public enum Action: Hashable, Sendable { \(actionCases) }")
    let qualifiedLabels = try labels.map(nativeSourceIdentifier)
    let formalCalls = zip(labels, qualifiedLabels).map {
        "case .\($1): return FormalActionCall(name: \(String(reflecting: $0)), arguments: [])"
    }.joined(separator: "\n")
    try checkFunction("""
    public func formalCall(for action: Action) throws -> FormalActionCall { switch action { \(formalCalls) } }
    """, named: "formalCall", arity: 1)
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

    let rows = try labels.enumerated().map { index, label in
        let visitor = try checked(functions.filter { $0.name.text == "_visitUpdates\(index)" })
        let plan = try decodeScalarActionVisitor(visitor, index: index, fields: fields, control: control,
            locations: locations.map { ($0.caseName, $0.label) }, checking: checking)
        let successor = try checked(functions.filter { $0.name.text == "_visitSuccessors\(index)" })
        try verifyGeneratedSuccessorOutput(DeclSyntax(successor), actionID: index, parameters: "", arguments: "",
            configurationParameters: "", configurationArguments: "")
        return "<<\(TLAValue.string(label)), \(plan.tla)>>"
    }
    try checkNativeValidationActionRoute(functions)
    return Data("""
    ---- MODULE SwiftTLANativeActions ----
    NativeActionRows == <<\(rows.joined(separator: ", "))>>
    ====

    """.utf8)
}

private func decodeScalarActionVisitor(_ visitor: FunctionDeclSyntax, index: Int,
    fields: [ActionField], control: ActionField, locations: [(caseName: String, label: String)],
    checking: String) throws -> ActionInstructions {
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
    var instructions = ActionInstructions()
    var visited: Set<String> = []
    let stateReads: [(String, ActionReference)] = fields.map {
        ($0.before, .init(kind: "state", operand: TLAValue.string($0.name).description, type: $0.type))
    }
    let controlValues: [(String, ActionReference)] = locations.map {
        ("\(control.type).\($0.caseName)", .init(kind: "control", operand: TLAValue.string($0.label).description, type: control.type))
    }

    typealias Binding = (local: String, value: ActionReference)
    var pending: [(String, [Binding])] = [("_actionPart0", [])]
    walk: while let (name, scope) = pending.popLast() {
        guard let part = byName[name], let body = part.body, visited.insert(name).inserted else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let argument = scope.map { "\($0.local), " }.joined()
        let formal = scope.map { "_ \($0.local): \($0.value.type), " }.joined()
        let tokens = syntaxWords(body)
        let prefix = words("{ do {")
        let suffix = words("} catch let failure as NativeMachineEvaluationError where failure.isModelEvaluationFailure { failures.append(failure) } }")
        guard tokens.count > prefix.count + suffix.count else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let core = Array(tokens.dropFirst(prefix.count).dropLast(suffix.count))
        let signature = "func \(name)(\(formal)_ updates: _Updates, _ emit: (_Updates) throws -> Void) throws"
        guard sameWords(syntaxWords(part), """
            \(signature) {
                do { \(core.joined(separator: " ")) }
                catch let failure as NativeMachineEvaluationError where failure.isModelEvaluationFailure {
                    failures.append(failure)
                }
            }
            """) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }

        if sameWords(core, "try emit(updates)") { continue walk }
        for location in locations where sameWords(core, """
            guard (\(control.before) == \(control.type).\(location.caseName)) else { return }
            try emit(updates)
            """) {
            instructions.guards.append(TLAValue.string(location.label).description)
            continue walk
        }
        let boundReads = scope.map { ($0.local, $0.value) }
        if core.count > 2, core[0] == "let",
           let call = core.firstIndex(of: "try"), call + 1 < core.count, byName[core[call + 1]] != nil {
            let local = try nativeSourceIdentifier(core[1])
            let child = core[call + 1]
            guard !scope.contains(where: { $0.local == local }) else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            guard core[2] == "=", call > 3 else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
            let rhs = Array(core[3..<call])
            var reads = stateReads + boundReads
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
            for (spelling, value) in reads where value.type == nativeIntTypeTokens.joined() &&
                sameWords(core, "let \(local) = \(spelling)\ntry \(child)(\(argument)\(local), updates, emit)") {
                instructions.captures.append(value.tla)
                let reference = ActionReference(kind: "capture", operand: String(instructions.captures.count), type: value.type)
                pending.append((child, scope + [(local, reference)]))
                continue walk
            }
        }
        if core.count > 2, core[0] == "try", byName[core[1]] != nil,
           let nextCall = core.lastIndex(of: "try"), nextCall > 0, nextCall + 1 < core.count,
           byName[core[nextCall + 1]] != nil {
            let first = core[1]
            let next = core[nextCall + 1]
            if sameWords(core, "try \(first)(\(argument)updates, { candidate in try \(next)(\(argument)candidate, emit) })") {
                pending.append((next, scope))
                pending.append((first, scope))
                continue walk
            }
        }
        let operands = stateReads + controlValues + boundReads
        for field in fields {
            for (spelling, value) in operands where value.type == field.type &&
                sameWords(core, "if let merged = updates.merging(_Updates(\(field.slot): \(spelling))) { try emit(merged) }") {
                instructions.writes.append("<<\(TLAValue.string(field.name)), \(value.tla)>>")
                continue walk
            }
        }
        throw InitialFailureEvidenceError.unsupportedGeneratedOutput
    }

    guard visited.count == parts.count else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
    return instructions
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
