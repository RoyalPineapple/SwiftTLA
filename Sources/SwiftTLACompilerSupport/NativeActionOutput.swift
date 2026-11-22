import SwiftParser
import SwiftSyntax
import SwiftTLA

private let nativeBoolType = "SwiftTLA.TLAValue.BooleanLiteralType"

package func verifyGeneratedValidationDelegationOutput(_ declaration: DeclSyntax?) throws {
    let expected = Parser.parse(source: """
    public func visitValidationOutcomes(checking context: inout CheckingContext<CheckingRegisters>,
                                        _ visit: (Action, Self) throws -> \(nativeBoolType),
                                        onEvaluationFailure: (Action, NativeMachineEvaluationError) throws -> \(nativeBoolType)) throws -> \(nativeBoolType) {
        var run: CheckingContext<CheckingRegisters>? = context
        defer { context = run! }
        return try _visitSuccessors(checking: &run, visit, onEvaluationFailure: onEvaluationFailure)
    }
    """).statements.first?.item.as(FunctionDeclSyntax.self)
    guard let actual = declaration?.as(FunctionDeclSyntax.self), let expected,
          Array(actual.tokens(viewMode: .sourceAccurate)).map(\.text)
            == Array(expected.tokens(viewMode: .sourceAccurate)).map(\.text) else {
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.validation.delegation",
            expected: "forward every successor and exact action failure through the generated checking entry point",
            actual: "the emitted validation entry point differs from the checked rule",
            nextSafeAction: "Report this native validation generation failure."
        )
    }
}

package func verifyGeneratedSuccessorOutput(
    _ declaration: DeclSyntax?, actionID: Int, parameters: String, arguments: String,
    configurationParameters: String, configurationArguments: String
) throws {
    let expected = Parser.parse(source: """
    private static func _visitSuccessors\(actionID)(from state: Snapshot\(parameters.isEmpty ? "" : ", " + parameters)\(configurationParameters), checking context: inout CheckingContext<CheckingRegisters>?,
                                                  _ visit: (Snapshot) throws -> Void) throws -> [NativeMachineEvaluationError] {
        var emitted: [Snapshot] = []
        return try _visitUpdates\(actionID)(from: state\(arguments.isEmpty ? "" : ", " + arguments)\(configurationArguments), checking: &context) { updates in
            let candidate = updates.applying(to: state)
            if !emitted.contains(candidate) {
                emitted.append(candidate)
                try visit(candidate)
            }
        }
    }
    """).statements.first?.item.as(FunctionDeclSyntax.self)
    guard let actual = declaration?.as(FunctionDeclSyntax.self), let expected,
          Array(actual.tokens(viewMode: .sourceAccurate)).map(\.text)
            == Array(expected.tokens(viewMode: .sourceAccurate)).map(\.text) else {
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.action.successor.\(actionID)",
            expected: "apply every complete compiled update and visit each resulting snapshot once",
            actual: "the emitted successor wrapper differs from the checked rule",
            nextSafeAction: "Report this native successor generation failure."
        )
    }
}

package func nativeOrderedIntAssignmentFailureSource(actionOrdinal: Int, preceding: [String]) -> String {
    "SwiftTLA._recordNativeOrderedIntAssignmentFailure(&context, actionOrdinal: \(actionOrdinal), "
        + "assignmentOrdinal: \(preceding.count + 1), preceding: [\(preceding.joined(separator: ", "))], reason: failure)"
}

/// Bind the compiler seed's checked stack operations to the actual native visitor.
package func verifyGeneratedTraversalSeedOutput(_ declarations: [DeclSyntax]) throws {
    func fail(_ path: String) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.traversal." + path,
            expected: "the generated typed stack operation and its lexical operands",
            actual: "a different or incomplete compiler stack action",
            nextSafeAction: "Regenerate the compiler stack seed output."
        )
    }

    func words(_ syntax: some SyntaxProtocol) -> [String] {
        syntax.tokens(viewMode: .sourceAccurate).filter { $0.tokenKind != .endOfFile }.map(\.text)
    }
    func matches(_ actual: [String], _ expected: String) -> Bool {
        actual == words(Parser.parse(source: expected))
    }
    func function(named name: String, arity: Int? = nil, firstLabel: String? = nil) throws -> FunctionDeclSyntax {
        let functions = declarations.compactMap { $0.as(FunctionDeclSyntax.self) }.filter {
            let parameters = $0.signature.parameterClause.parameters
            return $0.name.text == name
                && (arity == nil || parameters.count == arity)
                && (firstLabel == nil || parameters.first?.firstName.text == firstLabel)
        }
        guard functions.count == 1, let declaration = functions.first, !declaration.hasError else {
            throw fail(name)
        }
        return declaration
    }

    let visitor = try function(named: "_visitUpdates0")
    try verifyGeneratedSuccessorOutput(DeclSyntax(try function(named: "_visitSuccessors0")),
        actionID: 0, parameters: "", arguments: "", configurationParameters: "", configurationArguments: "")
    let dispatch = try function(named: "_visitSuccessors", arity: 3, firstLabel: "for")
    let collected = try function(named: "_successors", arity: 2)
    let context = try function(named: "_successors", arity: 1)
    let successors = try function(named: "successors", arity: 1)
    guard matches(words(dispatch), """
        private func _visitSuccessors(for action: Action, checking context: inout CheckingContext<CheckingRegisters>?,
            _ visit: (Snapshot) throws -> Void) throws -> [NativeMachineEvaluationError] {
            switch action { case .expand: return try Self._visitSuccessors0(from: _execution, checking: &context, visit) }
        }
        """), matches(words(collected), """
        private func _successors(for action: Action, checking context: inout CheckingContext<CheckingRegisters>?) throws -> [Snapshot] {
            var result: [Snapshot] = []
            let failures = try _visitSuccessors(for: action, checking: &context) { SwiftTLA._appendNativeOutcome(&result, $0) }
            if let failure = failures.first { throw failure }
            return result
        }
        """), matches(words(context), """
        private func _successors(for action: Action) throws -> [Snapshot] {
            var context: CheckingContext<CheckingRegisters>?
            return try _successors(for: action, checking: &context)
        }
        """), matches(words(successors), """
        public func successors(for action: Action) throws -> [Self] {
            try _successors(for: action).map { execution in return Self(execution: execution) }
        }
        """) else { throw fail("dispatch") }
    let helpers = visitor.body?.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }
        .filter { $0.name.text.hasPrefix("_actionPart") } ?? []
    let names = helpers.map { $0.name.text }
    guard Set(names).count == names.count, !helpers.isEmpty,
          names.allSatisfy({ Int($0.dropFirst("_actionPart".count)).map { $0 >= 0 } == true }),
          matches(words(visitor), """
            private static func _visitUpdates0(from state: Snapshot, checking context: inout CheckingContext<CheckingRegisters>?,
                _ _emit: (_Updates) throws -> Void) throws -> [NativeMachineEvaluationError] {
                var failures: [NativeMachineEvaluationError] = []
                func emit(_ update: _Updates) throws {
                    do { try _emit(update) }
                    catch { throw _StopSuccessorTraversal(cause: error) }
                }
                \(helpers.map(\.description).joined(separator: "\n"))
                do { try _actionPart0(_Updates(), emit) }
                catch let stop as _StopSuccessorTraversal {
                    if let cause = stop.cause { throw cause }
                    throw stop
                }
                return failures
            }
            """) else { throw fail("entry") }
    let parts = Dictionary(uniqueKeysWithValues: zip(names, helpers))
    let intType = nativeIntTypeTokens.joined()
    let frameType = "Pair<\(intType), \(nativeBoolType)>"
    let stackType = "[\(frameType)]"
    let prefix = "SwiftTLA._NativeMachineOperations."
    let stack = "state.state.pending"
    let size = "(\(stack).count)"
    let last = """
        (try { () throws -> \(frameType) in
            let _sequenceValue = \(stack)
            let _sequenceIndex = \(size)
            return try \(prefix)sequenceElement(_sequenceValue, at: _sequenceIndex)
        }())
        """
    let previous = """
        (try { () throws -> \(stackType) in
            let _sequenceValue = \(stack)
            let _prefixLength = (try { () throws -> \(intType) in
                let _arithmetic0: \(intType) = \(size)
                let _arithmetic1: \(intType) = 1
                let _arithmetic2: \(intType) = try \(prefix)subtract(_arithmetic0, _arithmetic1)
                return _arithmetic2
            }())
            return try \(prefix)sequencePrefix(_sequenceValue, length: _prefixLength)
        }())
        """
    func append(_ sequence: String, first: String, second: Bool) -> String {
        """
        (try { () throws -> \(stackType) in
            let _sequenceValue: \(stackType) = \(sequence)
            let _appendedValue: \(frameType) = \(frameType)(first: \(first), second: \(second))
            return \(prefix)sequenceAppend(_sequenceValue, _appendedValue)
        }())
        """
    }
    func unexpanded(_ frame: String) -> String {
        """
        (try { () throws -> \(nativeBoolType) in
            func _predicate0() throws -> \(nativeBoolType) {
                return try \(prefix)booleanNot { try _predicate1() }
            }
            func _predicate1() throws -> \(nativeBoolType) { return \(frame).second }
            return try _predicate0()
        }())
        """
    }
    var events: [String] = []
    var visited: Set<String> = []
    let frameSlots = ["_value_leftChild_1": "state.state.leftChild", "_value_rightChild_2": "state.state.rightChild"]
    var visitedFrameSlots: Set<String> = []
    typealias Binding = (name: String, type: String)
    var pending: [(String, [Binding])] = [("_actionPart0", [])]
    partLoop: while let (name, scope) = pending.popLast() {
        guard visited.insert(name).inserted, let part = parts[name],
              let statement = part.body?.statements.first?.item.as(DoStmtSyntax.self) else {
            throw fail("continuation")
        }
        let parameters = scope.map { "_ \($0.name): \($0.type), " }.joined()
        let arguments = scope.map { "\($0.name), " }.joined()
        let body = statement.body.statements
        guard matches(words(part), """
            func \(name)(\(parameters)_ updates: _Updates, _ emit: (_Updates) throws -> Void) throws {
                do { \(body.description) }
                catch let failure as NativeMachineEvaluationError where failure.isModelEvaluationFailure {
                    failures.append(failure)
                }
            }
            """) else { throw fail("scope") }
        let core = words(body)
        if matches(core, "try emit(updates)") { continue }
        if core.first == "try", core.count > 2, parts[core[1]] != nil,
           let lastTry = core.lastIndex(of: "try"), lastTry > 0, lastTry + 1 < core.count,
           parts[core[lastTry + 1]] != nil {
            let first = core[1], second = core[lastTry + 1]
            if matches(core, "try \(first)(\(arguments)updates, { candidate in try \(second)(\(arguments)candidate, emit) })") {
                pending.append((second, scope))
                pending.append((first, scope))
                continue
            }
        }
        if scope.isEmpty, matches(core, "guard (\(size) > 0) else { return }\ntry emit(updates)") {
            events.append("nonempty")
            continue
        }
        if scope.count == 1, let frame = scope.first?.name,
           matches(core, "guard \(unexpanded(frame)) else { return }\ntry emit(updates)") {
            events.append("unexpanded")
            continue
        }
        if body.count == 2, let capture = body.first?.item.as(VariableDeclSyntax.self),
           capture.bindings.count == 1,
           let local = capture.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
           !scope.contains(where: { $0.name == local }),
           let lastTry = core.lastIndex(of: "try"), lastTry + 1 < core.count, parts[core[lastTry + 1]] != nil {
            let child = core[lastTry + 1]
            let value: String
            let type: String
            if scope.isEmpty {
                value = last
                type = frameType
            } else if scope.count == 1, let frame = scope.first?.name {
                value = append(append(append(previous, first: "\(frame).first", second: true),
                    first: "state.state.rightChild", second: false), first: "state.state.leftChild", second: false)
                type = stackType
            } else {
                throw fail("capture")
            }
            guard matches(core, "let \(local) = \(value)\ntry \(child)(\(arguments)\(local), updates, emit)") else {
                throw fail(scope.isEmpty ? "last" : "append")
            }
            events.append(scope.isEmpty ? "last" : "replacement")
            pending.append((child, scope + [(local, type)]))
            continue
        }
        if scope.count == 2, let replacement = scope.last?.name,
           matches(core, "if let merged = updates.merging(_Updates(_value_pending_0: \(replacement))) { try emit(merged) }") {
            events.append("write")
            continue
        }
        for (field, read) in frameSlots where
            matches(core, "if let merged = updates.merging(_Updates(\(field): \(read))) { try emit(merged) }") {
            guard visitedFrameSlots.insert(field).inserted else { throw fail("frame") }
            continue partLoop
        }
        throw fail("operand")
    }
    guard visited.count == parts.count, visitedFrameSlots == Set(frameSlots.keys),
          events == ["nonempty", "last", "unexpanded", "replacement", "write"] else {
        throw fail("order")
    }
}
