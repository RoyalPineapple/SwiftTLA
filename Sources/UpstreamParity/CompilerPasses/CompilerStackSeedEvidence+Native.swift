import SwiftParser
import SwiftSyntax
import SwiftTLA
import SwiftTLACompilerSupport

private let nativeBoolType = "SwiftTLA.TLAValue.BooleanLiteralType"

struct NativeTraversalSeedExpansion: Sendable {
    struct Push: Sendable {
        let source: String
        let position: Int
        let expanded: Bool
    }

    let countFloor: Int
    let lastIndex: String
    let prefixDrop: Int
    let localExpandedPosition: Int
    let pushes: [Push]
    let returnedSlots: [Int]
}

private func words(_ syntax: some SyntaxProtocol) -> [String] {
    syntax.tokens(viewMode: .sourceAccurate).filter { $0.tokenKind != .endOfFile }.map(\.text)
}
private func matches(_ actual: [String], _ expected: String) -> Bool {
    actual == words(Parser.parse(source: expected))
}

func decodeTraversalSeedPrefixFloor(_ operations: String) throws -> Int {
    let failure = CompilationDiagnostic(
        code: .unsupportedGeneratedValueShape, stage: .validation,
        path: "native.traversal.operations.sequenceAppend",
        expected: "the reviewed Array copy, append, and return",
        actual: "a different or missing stack append implementation",
        nextSafeAction: "Review the sequenceAppend proof interpretation against the runtime implementation."
    )
    let runtime = Parser.parse(source: operations)
    let operationOwners = runtime.statements.compactMap { $0.item.as(EnumDeclSyntax.self) }
        .filter { $0.name.text == "_NativeMachineOperations" }
    guard !runtime.hasError, !operations.utf8.contains(0), operationOwners.count == 1,
          let owner = operationOwners.first else { throw failure }
    let appendHelpers = owner.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }
        .filter { $0.name.text == "sequenceAppend" }
    // Reviewed Array.append interpretation: retain each old cell and write the new cell at the old count.
    guard appendHelpers.count == 1, let helper = appendHelpers.first,
          matches(words(helper), """
              public static func sequenceAppend<Element: Sendable>(_ sequence: [Element], _ element: Element) -> [Element] {
                  var result = sequence
                  result.append(element)
                  return result
              }
              """) else { throw failure }

    let prefixHelpers = owner.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }
        .filter { $0.name.text == "sequencePrefix" }
    guard prefixHelpers.count == 1, let prefix = prefixHelpers.first,
          let returned = prefix.body?.statements.last?.item.as(ReturnStmtSyntax.self),
          let array = returned.expression?.as(FunctionCallExprSyntax.self),
          let slice = array.arguments.first?.expression.as(FunctionCallExprSyntax.self),
          let maximum = slice.arguments.first?.expression.as(FunctionCallExprSyntax.self),
          let floor = maximum.arguments.first?.expression.as(IntegerLiteralExprSyntax.self),
          let lowerBound = Int(floor.literal.text), lowerBound == 0,
          matches(words(prefix), """
              public static func sequencePrefix<Element: Sendable>(_ sequence: [Element], length: Int) throws -> [Element] {
                  guard length <= sequence.count else {
                      throw NativeMachineEvaluationError.indexOutOfBounds(index: length, count: sequence.count)
                  }
                  return Array(sequence.prefix(Swift.max(\(lowerBound), length)))
              }
              """) else {
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.traversal.operations.sequencePrefix",
            expected: "the reviewed length guard and zero-clamped leading Array prefix",
            actual: "a different or missing stack prefix implementation",
            nextSafeAction: "Review the sequencePrefix proof interpretation against the runtime implementation."
        )
    }
    return lowerBound
}

/// Bind the compiler seed's checked stack operations and ordered tuple operands to the actual native visitor.
func decodeGeneratedTraversalSeedOutput(_ declarations: [DeclSyntax]) throws -> NativeTraversalSeedExpansion {
    func fail(_ path: String) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.traversal." + path,
            expected: "the generated typed stack operation and its lexical operands",
            actual: "a different or incomplete compiler stack action",
            nextSafeAction: "Regenerate the compiler stack seed output."
        )
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
    let collected = try function(named: "_successors", arity: 2, firstLabel: "for")
    let context = try function(named: "_successors", arity: 1, firstLabel: "for")
    let successors = try function(named: "successors", arity: 1, firstLabel: "for")
    guard matches(words(dispatch), """
        private func _visitSuccessors(for action: Action, checking context: inout CheckingContext<CheckingRegisters>?,
            _ visit: (Snapshot) throws -> Void) throws -> [NativeMachineEvaluationError] {
            switch action { case .expand: return try Self._visitSuccessors0(from: _execution, checking: &context, visit) }
        }
        """), matches(words(collected), """
        private func _successors(for action: Action, checking context: inout CheckingContext<CheckingRegisters>?) throws -> [Snapshot] {
            var result: [Snapshot] = []
            let failures = try _visitSuccessors(for: action, checking: &context) { SwiftTLA._appendNativeOutcome(&result, $0) }
            if let failure = SwiftTLA._firstNativeEvaluationFailure(failures) { throw failure }
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
    let fields = ["pending", "leftChild", "rightChild"]
    let returnedSlots = try nativeUpdateSnapshotSlots(declarations.compactMap { $0.as(StructDeclSyntax.self) },
        fields: fields.enumerated().map { ordinal, name in
            (name, "_value_\(name)_\(ordinal)", ordinal == 0 ? stackType : intType)
        })
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
    func previous(dropping drop: Int) -> String {
        """
            (try { () throws -> \(stackType) in
                let _sequenceValue = \(stack)
                let _prefixLength = (try { () throws -> \(intType) in
                    let _arithmetic0: \(intType) = \(size)
                    let _arithmetic1: \(intType) = \(drop)
                    let _arithmetic2: \(intType) = try \(prefix)subtract(_arithmetic0, _arithmetic1)
                    return _arithmetic2
                }())
                return try \(prefix)sequencePrefix(_sequenceValue, length: _prefixLength)
            }())
            """
    }
    func append(_ sequence: String, first: String, second: Bool) -> String {
        """
        (try { () throws -> \(stackType) in
            let _sequenceValue: \(stackType) = \(sequence)
            let _appendedValue: \(frameType) = \(frameType)(first: \(first), second: \(second))
            return \(prefix)sequenceAppend(_sequenceValue, _appendedValue)
        }())
        """
    }
    func pushRows(in expression: ExprSyntax, frame: String) -> [NativeTraversalSeedExpansion.Push]? {
        var pending = [Syntax(expression)]
        var rows: [NativeTraversalSeedExpansion.Push] = []
        while let syntax = pending.popLast() {
            if let declaration = syntax.as(VariableDeclSyntax.self), declaration.bindings.count == 1,
               let binding = declaration.bindings.first,
               binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "_appendedValue" {
                guard let pair = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                      matches(words(pair.calledExpression), frameType), pair.arguments.count == 2,
                      let first = pair.arguments.first, first.label?.text == "first",
                      let flag = pair.arguments.last, flag.label?.text == "second",
                      let expanded = flag.expression.as(BooleanLiteralExprSyntax.self) else { return nil }
                let operand = words(first.expression)
                if matches(operand, "\(frame).first") {
                    rows.append(.init(source: "local", position: 1, expanded: expanded.literal.text == "true"))
                } else if operand.count == 5, operand.starts(with: ["state", ".", "state", "."]),
                          let field = operand.last, ["leftChild", "rightChild"].contains(field) {
                    rows.append(.init(source: field, position: 0, expanded: expanded.literal.text == "true"))
                } else {
                    return nil
                }
            } else {
                pending.append(contentsOf: syntax.children(viewMode: .sourceAccurate).reversed())
            }
        }
        return rows.count == 3 ? rows : nil
    }
    func integer(after anchor: [String], in tokens: [String]) -> Int? {
        let matches = tokens.indices.filter { index in
            let end = index + anchor.count
            return end < tokens.count && tokens[index..<end].elementsEqual(anchor)
        }
        guard matches.count == 1, let index = matches.first else { return nil }
        let token = tokens[index + anchor.count]
        guard let value = Int(token), value >= 0, String(value) == token else { return nil }
        return value
    }

    func unexpanded(_ frame: String, _ tokens: [String]) -> Bool {
        let names = tokens.indices.dropLast().compactMap { index -> String? in
            guard tokens[index] == "func" else { return nil }
            let name = tokens[index + 1]
            guard name.hasPrefix("_predicate"),
                  Int(name.dropFirst("_predicate".count)).map({ $0 >= 0 }) == true else { return nil }
            return name
        }
        guard names.count == 2, names[0] != names[1] else { return false }
        let predicate = names[0], operand = names[1]
        return matches(tokens, """
            guard (try { () throws -> \(nativeBoolType) in
                func \(predicate)() throws -> \(nativeBoolType) {
                    return try \(prefix)booleanNot { try \(operand)() }
                }
                func \(operand)() throws -> \(nativeBoolType) { return \(frame).second }
                return try \(predicate)()
            }()) else { return }
            try emit(updates)
            """)
    }
    var events: [String] = []
    var countFloor: Int?
    var lastIndex: String?
    var localExpandedPosition: Int?
    var replacement: (drop: Int, pushes: [NativeTraversalSeedExpansion.Push])?
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
        if scope.isEmpty, countFloor == nil, let floor = integer(after: words(Parser.parse(source: "\(size) >")), in: core),
           matches(core, "guard (\(size) > \(floor)) else { return }\ntry emit(updates)") {
            countFloor = floor
            events.append("nonempty")
            continue
        }
        if scope.count == 1, let frame = scope.first?.name,
           unexpanded(frame, core) {
            localExpandedPosition = 2
            events.append("unexpanded")
            continue
        }
        if body.count == 2, let capture = body.first?.item.as(VariableDeclSyntax.self),
           capture.bindings.count == 1,
           let local = capture.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
           let capturedValue = capture.bindings.first?.initializer?.value,
           !scope.contains(where: { $0.name == local }),
           let lastTry = core.lastIndex(of: "try"), lastTry + 1 < core.count, parts[core[lastTry + 1]] != nil {
            let child = core[lastTry + 1]
            let value: String
            let type: String
            if scope.isEmpty {
                value = last
                type = frameType
            } else if scope.count == 1, let frame = scope.first?.name, replacement == nil,
                      let drop = integer(after: words(Parser.parse(source: "_arithmetic1: \(intType) =")), in: core),
                      let pushes = pushRows(in: capturedValue, frame: frame) {
                value = pushes.reduce(previous(dropping: drop)) { sequence, row in
                    let operand = row.position == 1 ? "\(frame).first" : "state.state.\(row.source)"
                    return append(sequence, first: operand, second: row.expanded)
                }
                replacement = (drop, pushes)
                type = stackType
            } else {
                throw fail("capture")
            }
            guard matches(core, "let \(local) = \(value)\ntry \(child)(\(arguments)\(local), updates, emit)") else {
                throw fail(scope.isEmpty ? "last" : "append")
            }
            if scope.isEmpty { lastIndex = "count" }
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
          events == ["nonempty", "last", "unexpanded", "replacement", "write"],
          let countFloor, let lastIndex, let localExpandedPosition, let replacement else {
        throw fail("order")
    }
    return .init(countFloor: countFloor, lastIndex: lastIndex, prefixDrop: replacement.drop,
                 localExpandedPosition: localExpandedPosition, pushes: replacement.pushes, returnedSlots: returnedSlots)
}

struct NativeTraversalSeedInitialization: Sendable, Equatable {
    let leftChild: Int
    let rightChild: Int
}

/// Read the typed literal slots and check how the unselected initial branch returns them.
func decodeGeneratedTraversalSeedInitialization(_ declarations: [DeclSyntax]) throws -> NativeTraversalSeedInitialization {
    func invalid(_ field: String) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.traversal.initial." + field,
            expected: "the checked typed stack initializer and its exact returned slots",
            actual: "a different or incomplete compiler seed initializer",
            nextSafeAction: "Regenerate the compiler stack seed output."
        )
    }
    func words(_ syntax: some SyntaxProtocol) -> [String] {
        syntax.tokens(viewMode: .sourceAccurate).filter { $0.tokenKind != .endOfFile }.map(\.text)
    }
    func matches(_ syntax: some SyntaxProtocol, _ expected: String) -> Bool {
        words(syntax) == words(Parser.parse(source: expected))
    }

    let indices = declarations.indices.filter {
        declarations[$0].as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
    }
    guard indices.count == 1, let initialIndex = indices.first,
          let initial = declarations[initialIndex].as(FunctionDeclSyntax.self), !initial.hasError,
          let branchItem = initial.body?.statements.dropFirst(4).first?.item,
          let attempt = branchItem.as(TryExprSyntax.self)
              ?? branchItem.as(ExpressionStmtSyntax.self)?.expression.as(TryExprSyntax.self),
          let branch = attempt.expression.as(FunctionCallExprSyntax.self),
          let original = branch.arguments.first?.expression.as(ClosureExprSyntax.self) else {
        throw invalid("entry")
    }
    try verifyGeneratedInitialConstruction(Array(declarations[initialIndex...]), configured: false)

    let intType = nativeIntTypeTokens.joined()
    let stackType = "[Pair<\(intType), \(nativeBoolType)>]"
    let fields = ["pending", "leftChild", "rightChild"]
    let slots = fields.enumerated().map { "_value_\($0.element)_\($0.offset)" }
    let types = [stackType, intType, intType]
    var current = original.statements
    var literals = [String]()
    for (index, slot) in slots.enumerated() {
        guard current.count == 5,
              let local = current.dropFirst(2).first?.item.as(VariableDeclSyntax.self),
              local.bindings.count == 1, let binding = local.bindings.first,
              binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == slot,
              let value = binding.initializer?.value, let selectionItem = current.last?.item,
              let selection = selectionItem.as(IfExprSyntax.self)
                  ?? selectionItem.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self) else {
            throw invalid(fields[index])
        }
        let literal = words(value).joined()
        if index == 0 {
            guard let array = value.as(ArrayExprSyntax.self), array.elements.isEmpty else {
                throw invalid(fields[index])
            }
        } else {
            guard let integer = Int(literal), String(integer) == literal else {
                throw invalid(fields[index])
            }
        }
        literals.append(literal)
        current = selection.body.statements
    }

    let arguments = zip(fields, slots).map { field, slot in "\(field): \(slot)" }.joined(separator: ", ")
    var body = "SwiftTLA._appendNativeOutcome(&result, Snapshot(state: State(\(arguments))))"
    for index in fields.indices.reversed() {
        let captures = slots.prefix(index).joined(separator: ", ")
        let entries = slots.indices.prefix(index).map { ordinal in
            let slot = slots[ordinal]
            let value = ordinal == 0
                ? "SwiftTLA.TLAValue.tuple(try \(slot).map { (element) throws -> SwiftTLA.TLAValue in SwiftTLA.TLAValue.tuple([SwiftTLA._nativeFormalInt(element.first), SwiftTLA.TLAValue.bool(element.second)]) })"
                : "SwiftTLA._nativeFormalInt(\(slot))"
            return "SwiftTLA._nativeFormalProjectionEntry(Self.__swifttlaFormalProjectionTokens, at: \(ordinal), value: \(value))"
        }.joined(separator: ", ")
        let capture = captures.isEmpty ? "" : "[\(captures)] in "
        let field = fields[index]
        let slot = slots[index]
        let selection = index == 0 ? "_selectedInitial == nil || _selectedInitial!.\(field) == \(slot)"
            : "SwiftTLA._nativeIntInitialMatches(_selectedInitial?.\(field), \(slot))"
        body = """
            evaluatingInitialBindings = { \(capture)try SwiftTLA._nativeFormalProjection([\(entries)]) }
            evaluatingInitializerOrdinal = \(index)
            let \(slot): \(types[index]) = \(literals[index])
            evaluatingInitializerOrdinal = nil
            if \(selection) { \(body) }
            """
    }
    guard matches(initial, """
        private static func _initialStates(_selectedInitial: State? = nil) throws -> SwiftTLA.InitialEvaluationOutcomes<Snapshot> {
            var result: [Snapshot] = []
            var failures: [SwiftTLA.InitialEvaluationFailure] = []
            var evaluatingInitializerOrdinal: \(intType)?
            var evaluatingInitialBindings: @Sendable () throws -> SwiftTLA.TLAStateProjection = {
                try SwiftTLA._nativeFormalProjection([])
            }
            try SwiftTLA._visitNativeInitialBranch({ \(body) }, onEvaluationFailure: { failure in
                SwiftTLA._appendNativeOutcome(&failures, SwiftTLA._nativeInitialFailure(
                    evaluatingInitializerOrdinal, failure: failure, projectingBefore: evaluatingInitialBindings))
            })
            return SwiftTLA._nativeInitialOutcomes(states: result, failures: failures)
        }
        """) else { throw invalid("assembly") }

    let structs = declarations.compactMap { $0.as(StructDeclSyntax.self) }
    let snapshots = structs.filter { $0.name.text == "Snapshot" }
    let states = structs.filter { $0.name.text == "State" }
    guard snapshots.count == 1, let snapshot = snapshots.first, states.count == 1, let state = states.first,
          matches(snapshot, "public struct Snapshot: Hashable, Sendable { public let state: State }") else {
        throw invalid("snapshot")
    }
    let fieldsAndConstructors = state.memberBlock.members.map(\.decl).filter { declaration in
        declaration.as(VariableDeclSyntax.self)?.modifiers.contains { $0.name.text == "static" } != true
    }
    let storage = fields.indices.map { "public let \(fields[$0]): \(types[$0])" }.joined(separator: "\n")
    let inputs = fields.indices.map { "\(fields[$0]) _value\($0): \(types[$0])" }.joined(separator: ", ")
    let assigns = fields.indices.map { "self.\(fields[$0]) = _value\($0)" }.joined(separator: "\n")
    let syntax = Parser.parse(source: """
        struct Checked {
            \(storage)
            public init(\(inputs)) { \(assigns) }
        }
        """).statements.first?.item.as(StructDeclSyntax.self)?.memberBlock.members
    guard let syntax, fieldsAndConstructors.map({ words($0) }) == syntax.map({ words($0.decl) })
    else { throw invalid("state") }

    let constructors = declarations.compactMap { $0.as(InitializerDeclSyntax.self) }.filter {
        $0.signature.parameterClause.parameters.first?.firstName.text == "execution"
    }
    let properties = declarations.compactMap { $0.as(VariableDeclSyntax.self) }
    func property(named name: String, matching expected: String) -> Bool {
        let found = properties.filter {
            $0.bindings.contains { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name }
        }
        return found.count == 1 && found.first.map { matches($0, expected) } == true
    }
    guard constructors.count == 1, let constructor = constructors.first,
          matches(constructor, "private init(execution: Snapshot) { _execution = execution }"),
          property(named: "_execution", matching: "private var _execution: Snapshot"),
          property(named: "state", matching: "public var state: State { _execution.state }"),
          let left = Int(literals[1]), let right = Int(literals[2]) else { throw invalid("returnedState") }
    return .init(leftChild: left, rightChild: right)
}
