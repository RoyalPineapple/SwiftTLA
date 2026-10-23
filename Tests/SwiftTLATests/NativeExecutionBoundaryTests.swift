import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin
import SwiftTLAMacros

@TLAModel
private struct CartesianInitialSelection {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("CartesianInitialSelection") {
            let cartesianInitialSelection = Algorithm(label: "CartesianInitialSelection", scoped: { scope in
                let left = scope.sharedVar(_name: "left", in: Where(Set<Int>([0, 1, 2])) { value in value > 0 })
                let right = scope.sharedVar(_name: "right", in: 3...4)
                Do(Step.advance) { Assign(left, to: left + right) }
            })
            cartesianInitialSelection
        }
    }
}

@TLAModel
private struct EmptyInitialSelection {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("EmptyInitialSelection") {
            let emptyInitialSelection = Algorithm(label: "EmptyInitialSelection", scoped: { scope in
                let count = scope.sharedVar(_name: "count", in: Where(Set<Int>([1])) { value in value < 0 })
                Do(Step.advance) { Assign(count, to: count + 1) }
            })
            emptyInitialSelection
        }
    }
}

@TLAModel
private struct DuplicateExecutionPaths {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("DuplicateExecutionPaths") {
            let duplicateExecutionPaths = Algorithm(label: "DuplicateExecutionPaths", scoped: { scope in
                let count = scope.sharedVar(_name: "count", initial: 0)
                Do(Step.advance) {
                    Either { Assign(count, to: 1) } or: { Assign(count, to: 1) }
                }
            })
            duplicateExecutionPaths
        }
    }
}

@TLAModel
private struct NestedChoiceExecution {
    enum Step: String, CaseIterable { case choose }
    static var spec: TLASpec {
        #spec("NestedChoiceExecution") {
            let nestedChoiceExecution = Algorithm(label: "NestedChoiceExecution", scoped: { scope in
                let x = scope.sharedVar(initial: 0)
                let y = scope.sharedVar(initial: 0)
                Do(Step.choose, when: x == 0) {
                    Assign(x, to: 1)
                    Either {
                        Either { Assign(y, to: 2) } or: { Assign(y, to: 3) }
                    } or: {
                        Assign(y, to: 4)
                    }
                }
            })
            nestedChoiceExecution
        }
    }
}

@TLAModel
private struct HiddenControlAlternatives {
    enum Step: String, CaseIterable { case select, left, right }
    static var spec: TLASpec {
        #spec("HiddenControlAlternatives") {
            let hiddenControlAlternatives = Algorithm(label: "HiddenControlAlternatives", scoped: { scope in
                let count = scope.sharedVar(_name: "count", initial: 0)
                Do(Step.select) {
                    Either { Goto(Step.left) } or: { Goto(Step.right) }
                }
                Do(Step.left) { Assign(count, to: 1) }
                Do(Step.right) { Assign(count, to: 2) }
            })
            hiddenControlAlternatives
        }
    }
}

@TLAModel
private struct CheckedExecutionOverflow {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("CheckedExecutionOverflow") {
            let checkedExecutionOverflow = Algorithm(label: "CheckedExecutionOverflow", scoped: { scope in
                let count = scope.sharedVar(_name: "count", initial: 9_223_372_036_854_775_807)
                Do(Step.advance) { Assign(count, to: count + 1) }
            })
            checkedExecutionOverflow
        }
    }
}

@TLAModel
private struct CheckedSubtractionOverflow {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("CheckedSubtractionOverflow") {
            let algorithm = Algorithm(label: "CheckedSubtractionOverflow", scoped: { scope in
                let count = scope.sharedVar(_name: "count", in: Set<Int>([3, 9_223_372_036_854_775_807]))
                Do(Step.advance) { Assign(count, to: count - (-1)) }
            })
            algorithm
        }
    }
}

@TLAModel
private struct CheckedSubtractionUnderflow {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("CheckedSubtractionUnderflow") {
            let algorithm = Algorithm(label: "CheckedSubtractionUnderflow", scoped: { scope in
                let count = scope.sharedVar(_name: "count", initial: -9_223_372_036_854_775_807)
                Do(Step.advance) { Assign(count, to: count - 2) }
            })
            algorithm
        }
    }
}

@TLAModel
private struct CheckedNestedNegation {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("CheckedNestedNegation") {
            let algorithm = Algorithm(label: "CheckedNestedNegation", scoped: { scope in
                let count = scope.sharedVar(_name: "count", in: Set<Int>([3, -9_223_372_036_854_775_807]))
                Do(Step.advance) { Assign(count, to: -(count - 1)) }
            })
            algorithm
        }
    }
}

@TLAModel
private struct CheckedExecutionBeyondTLCIntegerRange {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("CheckedExecutionBeyondTLCIntegerRange") {
            let algorithm = Algorithm(label: "CheckedExecutionBeyondTLCIntegerRange", scoped: { scope in
                let count = scope.sharedVar(_name: "count", initial: 2_147_483_647)
                Do(Step.advance) { Assign(count, to: count + 1) }
            })
            algorithm
        }
    }
}

@TLAModel
private struct ReachableInvariantFailure {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("ReachableInvariantFailure") {
            let reachableInvariantFailure = Algorithm(label: "ReachableInvariantFailure", scoped: { scope in
                let count = scope.sharedVar(_name: "count", initial: 0)
                Do(Step.advance) { Assign(count, to: 1) }
                Invariant("Zero") { count == 0 }
            })
            reachableInvariantFailure
        }
    }
}

@Suite struct NativeExecutionBoundaryTests {
    @Test("typed initial selection exhausts the Cartesian domain")
    func initialSelection() throws {
        let initial = try CartesianInitialSelection.initialMachines()
        #expect(Set(initial.map { [$0.state.left, $0.state.right] }) == [[1, 3], [1, 4], [2, 3], [2, 4]])
        for lhs in 1...2 {
            for rhs in 3...4 {
                let machine = try CartesianInitialSelection.makeMachine(.init(left: lhs, right: rhs))
                #expect(machine.state.left == lhs)
                #expect(machine.state.right == rhs)
            }
        }
        do {
            _ = try CartesianInitialSelection.makeMachine()
            Issue.record("Multiple initial states require explicit selection")
        } catch GeneratedMachineError.ambiguousInitialState {}
        do {
            _ = try CartesianInitialSelection.makeMachine(.init(left: 9, right: 3))
            Issue.record("A selection outside the formal initial domain must fail")
        } catch GeneratedMachineError.invalidInitialState {}
    }

    @Test("empty initial domains reject both implicit and explicit construction")
    func emptyInitialDomain() throws {
        #expect(try EmptyInitialSelection.initialMachines().isEmpty)
        do {
            _ = try EmptyInitialSelection.makeMachine()
            Issue.record("Empty initial domains cannot construct a machine")
        } catch GeneratedMachineError.noInitialState {}
        do {
            _ = try EmptyInitialSelection.makeMachine(.init(count: 1))
            Issue.record("Explicit selection cannot create a missing initial state")
        } catch GeneratedMachineError.invalidInitialState {}
    }

    @Test("duplicate paths coalesce while distinct hidden control states remain ambiguous")
    func successorIdentity() throws {
        var duplicate = try DuplicateExecutionPaths.makeMachine()
        #expect(try duplicate.enabledActions() == [.advance])
        #expect(try duplicate.successors(for: .advance).count == 1)
        #expect(try duplicate.send(.advance).after.count == 1)

        var machine = try HiddenControlAlternatives.makeMachine()
        let before = machine.state
        let successors = try machine.successors()
        #expect(successors.count == 2)
        #expect(successors.allSatisfy { $0.action == .select })
        #expect(Set(successors.map { $0.machine.snapshot }).count == 2)
        #expect(Set(successors.map { $0.machine.state.count }) == [0])
        #expect(try machine.enabledActions() == [.select])
        do {
            _ = try machine.send(.select)
            Issue.record("Public equality must not merge distinct hidden control states")
        } catch GeneratedMachineError.ambiguousAction {}
        #expect(machine.state == before)
        #expect(try machine.enabledActions() == [.select])
    }

    @Test("nested choices after an ordered write retain every generated successor")
    func nestedChoiceSuccessors() throws {
        let initial = try NestedChoiceExecution.makeMachine()
        let successors = try initial.successors(for: .choose)
        #expect(successors.count == 3)
        #expect(successors.allSatisfy { $0.state.x == 1 })
        #expect(Set(successors.map(\.state.y)) == [2, 3, 4])
        let graph = try ReachabilityGraph(initialMachines: [initial], maximumStates: 4)
        #expect(graph.transitions.count == 4)
        #expect(graph.transitions[initial.snapshot]?.count == 3)
        #expect(Set(graph.transitions[initial.snapshot, default: []].map { $0.target.state.y }) == [2, 3, 4])
    }

    @Test("checked arithmetic failure is transactional across dispatch and exploration")
    func arithmeticFailureIsTransactional() throws {
        var machine = try CheckedExecutionOverflow.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try machine.successors(for: .advance)
        }
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try machine.isEnabled(.advance)
        }
        #expect(throws: MachineActionEvaluationFailure<CheckedExecutionOverflow.Action>(
            action: .advance, reason: .integerOverflow(.addition, operands: [Int.max, 1]))) {
            try ReachabilityGraph(initialMachines: [machine], maximumStates: 2)
        }
        var observedFailure = false
        let outcome = try MachineValidator.run(initialMachines: [machine], maximumStates: 2,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
            if case .evaluationFailure(let source, let action, let reason) = event {
                observedFailure = true
                #expect(source == 0)
                #expect(action == .advance)
                #expect(reason == .integerOverflow(.addition, operands: [Int.max, 1]))
            }
        }
        #expect(observedFailure)
        if case .evaluationFailure(let reason) = outcome.completion {
            #expect(reason == .integerOverflow(.addition, operands: [Int.max, 1]))
        } else {
            Issue.record("Expected a typed model evaluation failure")
        }
        #expect(outcome.initialStates == 1 && outcome.states == 1 && outcome.edges == 0)
        for _ in 0..<2 {
            #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
                try machine.send(.advance)
            }
            #expect(machine.snapshot == before)
        }
    }

    @Test("Generated addition uses checked Swift execution and a matching TLA failure rule")
    func renderedOverflowMatchesGeneratedFailure() throws {
        let compiled = try CheckedExecutionOverflow.spec.compile()
        let count = try #require(compiled.layout.variables.first { $0.declaration.name == "count" })
        let pc = try #require(compiled.layout.variables.first { $0.declaration.name == "pc" })
        let advance = try #require(compiled.layout.controlLocations.first { $0.renderedName == "advance" })
        let done = try #require(compiled.layout.controlLocations.first { $0.renderedName == "Done" })
        let actionLayout = try #require(compiled.layout.actions.first { $0.renderedName == "advance" })
        let termination = try #require(compiled.layout.actions.first { $0.isTermination })
        let compiledAction = try #require(compiled.semantics.behavior.actions.first)
        #expect(compiled.layout.variables.count == 2)
        #expect(compiled.layout.controlLocations.count == 2)
        #expect(compiled.layout.actions.count == 2)
        #expect(compiled.semantics.behavior.actions.count == 2)
        #expect(!actionLayout.isTermination)
        #expect(compiledAction.id == actionLayout.id)
        #expect(compiledAction.bindings.isEmpty)
        #expect(compiled.semantics.behavior.actions[1].id == termination.id)
        guard case .and(.guard_(let controlGuard), let body) = compiledAction.body,
              case .equal = controlGuard.operation, controlGuard.children.count == 2,
              case .stateVariable(let controlRead) = controlGuard.children[0].operation,
              case .controlLocation(let start) = controlGuard.children[1].operation else {
            Issue.record("The authored step no longer lowers to the proved control guard")
            return
        }
        guard case .define(let result, let addition, let writes) = body,
              case .add = addition.operation,
              addition.children.count == 2,
              case .stateVariable(let source) = addition.children[0].operation,
              case .value(.integer(1)) = addition.children[1].operation else {
            Issue.record("The authored step no longer lowers to the proved checked-addition binding")
            return
        }
        guard case .and(let stepBody, let controlWrite) = writes,
              case .and(.guard_(let stepGuard), let countWrite) = stepBody,
              case .value(.boolean(true)) = stepGuard.operation,
              case .assign(let countTarget, let countValue) = countWrite,
              case .boundValue(let usedResult) = countValue.operation,
              case .assign(let controlTarget, let controlValue) = controlWrite,
              case .controlLocation(let next) = controlValue.operation else {
            Issue.record("The authored step no longer lowers to the proved complete-state updates")
            return
        }
        #expect(controlRead == pc.id && start == advance.id)
        #expect(source == count.id)
        #expect(countTarget == count.id && usedResult == result)
        #expect(controlTarget == pc.id && next == done.id)
        #expect([controlGuard.children[0], controlGuard.children[1], addition.children[0],
                 addition.children[1], stepGuard, countValue, controlValue]
            .allSatisfy { $0.children.isEmpty })

        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let generatedAction = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "CheckedExecutionOverflow", program: program))
        let members = try emitter.machineMembers()
        let failureVisitor = try #require(members.first { declaration in
            guard let function = declaration.as(FunctionDeclSyntax.self) else { return false }
            return function.name.text == "_visitSuccessors"
                && function.signature.parameterClause.parameters.last?.firstName.text == "onEvaluationFailure"
        })
        let lostFailure = failureVisitor.description.replacingOccurrences(
            of: "onEvaluationFailure(action, reason)",
            with: "onEvaluationFailure(action, .noSatisfyingChoice)")
        #expect(lostFailure != failureVisitor.description)
        let wrongFailureVisitor = try #require(Parser.parse(source: lostFailure)
            .statements.first?.item.as(DeclSyntax.self))
        let wrongMembers = members.map { $0.id == failureVisitor.id ? wrongFailureVisitor : $0 }
        let actions = emitter.model.api.actions
        #expect(actions.allSatisfy { $0.bindings.isEmpty })
        let routes = actions.map { api in
            (name: api.swiftIdentifier, id: api.compiledAction.ordinal,
             formalName: program.layout.actions[api.compiledAction.ordinal].renderedName)
        }
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedActionRoutingOutput(wrongMembers, routes: routes,
                allActions: routes.map { ($0.name, $0.id, $0.formalName, 0) },
                candidates: routes.map { ($0.name, []) }, configurationArguments: "")
        }
        let successor = try #require(members.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitSuccessors\(generatedAction.id.ordinal)"
        })
        try verifyGeneratedSuccessorOutput(successor, actionID: generatedAction.id.ordinal,
            parameters: "", arguments: "", configurationParameters: "", configurationArguments: "")
        let droppedUpdate = successor.description.replacingOccurrences(
            of: "let candidate = updates.applying(to: state)", with: "let candidate = state")
        #expect(droppedUpdate != successor.description)
        let wrongSuccessor = try #require(Parser.parse(source: droppedUpdate)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedSuccessorOutput(wrongSuccessor, actionID: generatedAction.id.ordinal,
                parameters: "", arguments: "", configurationParameters: "", configurationArguments: "")
        }
        let validationEntry = try #require(members.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "visitValidationOutcomes"
        })
        try verifyGeneratedValidationDelegationOutput(validationEntry)
        let droppedFailureHandler = validationEntry.description.replacingOccurrences(
            of: ", onEvaluationFailure: onEvaluationFailure", with: "")
        #expect(droppedFailureHandler != validationEntry.description)
        let wrongEntry = try #require(Parser.parse(source: droppedFailureHandler)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedValidationDelegationOutput(wrongEntry)
        }
        let swiftAction = try #require(members.first {
            $0.description.contains("private static func _visitUpdates0(")
        }?.description)
        let swiftWitness = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/CheckedExecutionOverflowSwiftWitness.txt")
            .standardizedFileURL
        let expectedSwift = try String(contentsOf: swiftWitness, encoding: .utf8)
        let emittedTokens = Array(Parser.parse(source: swiftAction).tokens(viewMode: .sourceAccurate)).map(\.text)
        let witnessTokens = Array(Parser.parse(source: expectedSwift).tokens(viewMode: .sourceAccurate)).map(\.text)
        #expect(emittedTokens == witnessTokens)
        let emittedUpdate = try #require(members.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let emittedWrites = try emitter.actionFunctions(generatedAction.body).writes
        try verifyGeneratedActionWriteOutput(emittedUpdate, action: generatedAction.body,
            program: program, stateFields: emitter.stateMemberNames, parts: emittedWrites)
        let wrongOperation = swiftAction.replacingOccurrences(
            of: "_NativeMachineOperations.add(_arithmetic0, _arithmetic1)",
            with: "_NativeMachineOperations.subtract(_arithmetic0, _arithmetic1)")
        #expect(wrongOperation != swiftAction)
        let wrongUpdate = try #require(Parser.parse(source: wrongOperation)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongUpdate, action: generatedAction.body,
                program: program, stateFields: emitter.stateMemberNames, parts: emittedWrites)
            Issue.record("A generated addition called subtraction")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.binding.1")
        }
        let reversedOperands = swiftAction.replacingOccurrences(
            of: "_NativeMachineOperations.add(_arithmetic0, _arithmetic1)",
            with: "_NativeMachineOperations.add(_arithmetic1, _arithmetic0)")
        #expect(reversedOperands != swiftAction)
        let reversedUpdate = try #require(Parser.parse(source: reversedOperands)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(reversedUpdate, action: generatedAction.body,
                program: program, stateFields: emitter.stateMemberNames, parts: emittedWrites)
            Issue.record("A generated addition reversed the compiled operands")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.binding.1")
        }

        let rendered = try CheckedExecutionOverflow.render()
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/CheckedExecutionOverflow.tla")
            .standardizedFileURL
        #expect(rendered.tlaBundle.root.tla == (try String(contentsOf: proofInput, encoding: .utf8)))
        let symbolicProofInput = proofInput.deletingLastPathComponent()
            .appendingPathComponent("CheckedExecutionOverflowSymbolic.tla")
        #expect(Int.min == -Int.max - 1)
        #expect(Int.min <= -2_000_000_000 && 2_000_000_000 <= Int.max)
        let symbolicOutput = rendered.tlaBundle.root.tla
            .replacingOccurrences(of: "MODULE CheckedExecutionOverflow ----",
                with: "MODULE CheckedExecutionOverflowSymbolic ----")
            .replacingOccurrences(of: "EXTENDS Integers, FiniteSets, Sequences\n\nVARIABLES",
                with: "EXTENDS Integers, FiniteSets, Sequences\n\nCONSTANTS SwiftIntMin, SwiftIntMax\n\nVARIABLES")
            .replacingOccurrences(of: TLAValue.int(.min).description, with: "SwiftIntMin")
            .replacingOccurrences(of: TLAValue.int(.max).description, with: "SwiftIntMax")
        #expect(symbolicOutput == (try String(contentsOf: symbolicProofInput, encoding: .utf8)))
        let direct = rendered.tlaBundle.root.tla.split(separator: "\n")
        let action = try #require(direct.first { $0.hasPrefix("advance ==") })
        let machine = try CheckedExecutionOverflow.makeMachine()
        #expect(try machine.formalCall(for: .advance) == FormalActionCall(name: "advance", arguments: []))
        let initial = try machine.formalProjection(of: machine.snapshot)
        #expect(try renderedInitialStates(in: compiled) == [initial])
        let control = try #require(TLAStateProjection.Token(validating: "pc"))
        let countToken = try #require(TLAStateProjection.Token(validating: "count"))
        #expect(initial.entries.count == 2)
        #expect(initial.value(for: control) == .string("advance"))
        #expect(initial.value(for: countToken) == .int(Int.max))
        let failure = try #require(direct.first { $0.hasPrefix("__SwiftTLAOverflowFailure0 ==") })
        let operands = try #require(direct.first { $0.hasPrefix("__SwiftTLAOverflowOperands0 ==") })
        let operation = try #require(direct.first { $0.hasPrefix("__SwiftTLAOverflowOperation0 ==") })
        let evaluation = try #require(direct.first { $0.hasPrefix("__SwiftTLAEvaluationOK ==") })
        #expect(operands == "__SwiftTLAOverflowOperands0 == <<count, 1>>")
        #expect(operation == "__SwiftTLAOverflowOperation0 == \"addition\"")
        #expect(direct.contains { $0.hasPrefix("__SwiftTLAAnyEvaluationFailure0 ==") })
        #expect(evaluation == "__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)")
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        for checkDeadlock in [false, true] {
            let selected = try rendered.tlaBundle(checking: [], checkDeadlock: checkDeadlock)
            let cfg = try #require(selected.root.cfg)
            #expect(cfg.contains("INVARIANT __SwiftTLAEvaluationOK\n"))
            #expect(cfg.contains("CHECK_DEADLOCK \(checkDeadlock ? "TRUE" : "FALSE")\n"))
        }

        let plusCal = try rendered.plusCalBundle().root.tla.split(separator: "\n")
        let binding = try #require(plusCal.firstIndex { $0.contains("with (__atomic_0 =") })
        #expect(binding > 0)
        if binding > 0 {
            let line = plusCal[binding - 1].trimmingCharacters(in: .whitespaces)
            let prefix = "when "
            let defined = try #require(line.hasPrefix(prefix) && line.hasSuffix(";")
                ? String(line.dropFirst(prefix.count).dropLast()) : nil)
            #expect(action.contains("IF \(defined) THEN"))
            #expect(action.contains("ELSE FALSE"))
            #expect(failure == "__SwiftTLAOverflowFailure0 == (((pc = \"advance\")) = TRUE /\\ ~(\(defined)))")
        }
        #expect(plusCal.contains(failure))
        #expect(plusCal.contains(operands))
        #expect(plusCal.contains(operation))
        #expect(plusCal.contains(evaluation))
    }

    @Test("Nested arithmetic output retains its compiled operations and operand order")
    func nestedArithmeticOutputRetainsCompiledOperations() throws {
        let compiled = try GeneratedArithmeticFailureOrderModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "GeneratedArithmeticFailureOrderModel", program: program))
        let members = try emitter.machineMembers()
        let visitor = try #require(members.first {
            $0.description.contains("private static func _visitUpdates0(")
        }?.description)
        let writes = try emitter.actionFunctions(action.body).writes
        func check(_ source: String) throws {
            let declaration = try #require(Parser.parse(source: source)
                .statements.first?.item.as(DeclSyntax.self))
            try verifyGeneratedActionWriteOutput(declaration, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
        }
        try check(visitor)
        let wrongOperation = visitor.replacingOccurrences(
            of: "_NativeMachineOperations.divide(_arithmetic", with: "_NativeMachineOperations.add(_arithmetic")
        #expect(wrongOperation != visitor)
        #expect(throws: CompilationDiagnostic.self) { try check(wrongOperation) }
        let reversedOperands = visitor.replacingOccurrences(
            of: "_NativeMachineOperations.add(_arithmetic3, _arithmetic4)",
            with: "_NativeMachineOperations.add(_arithmetic4, _arithmetic3)")
        #expect(reversedOperands != visitor)
        #expect(throws: CompilationDiagnostic.self) { try check(reversedOperands) }
    }

    @Test("generated subtraction preserves complete transitions and overflow failures")
    func subtractionPreservesGeneratedOutcomes() throws {
        let compiled = try CheckedSubtractionOverflow.spec.compile()
        let step = try #require(compiled.semantics.behavior.actions.first)
        guard case .and(.guard_(let control), let body) = step.body,
              case .equal = control.operation,
              case .define(_, let value, _) = body,
              case .subtract = value.operation,
              value.children.count == 2,
              case .stateVariable = value.children[0].operation,
              case .value(.integer(-1)) = value.children[1].operation else {
            Issue.record("The authored step no longer lowers to the checked subtraction rule")
            return
        }
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "CheckedSubtractionOverflow", program: program))
        let swiftAction = try #require(try emitter.machineMembers().first {
            $0.description.contains("private static func _visitUpdates0(")
        }?.description)
        let additionWitness = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/CheckedExecutionOverflowSwiftWitness.txt")
            .standardizedFileURL
        let expectedSwift = try String(contentsOf: additionWitness, encoding: .utf8)
            .replacingOccurrences(of: "let _arithmetic1: Int = 1", with: "let _arithmetic1: Int = -1")
            .replacingOccurrences(of: "_NativeMachineOperations.add", with: "_NativeMachineOperations.subtract")
        let actualTokens = Array(Parser.parse(source: swiftAction).tokens(viewMode: .sourceAccurate)).map(\.text)
        let expectedTokens = Array(Parser.parse(source: expectedSwift).tokens(viewMode: .sourceAccurate)).map(\.text)
        #expect(actualTokens == expectedTokens)

        let initial = try CheckedSubtractionOverflow.initialMachines()
        #expect(Set(initial.map(\.state.count)) == [3, Int.max])
        var successful = try CheckedSubtractionOverflow.makeMachine(.init(count: 3))
        let transition = try successful.send(.advance)
        #expect(transition.before.count == 3 && transition.after.count == 4)
        let controlToken = try #require(TLAStateProjection.Token(validating: "pc"))
        #expect(try successful.formalProjection(of: successful.snapshot).value(for: controlToken) == .string("Done"))

        let machine = try CheckedSubtractionOverflow.makeMachine(.init(count: Int.max))
        #expect(throws: NativeMachineEvaluationError.integerOverflow(
            .subtraction, operands: [Int.max, -1])) {
            try machine.successors(for: .advance)
        }

        let rendered = try CheckedSubtractionOverflow.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let output = rendered.tlaBundle.root.tla
        #expect(output.contains("__SwiftTLAOverflowOperation0 == \"subtraction\""))
        #expect(output.contains("__SwiftTLAOverflowOperands0 == <<count, -1>>"))
        let plusCal = try rendered.plusCalBundle().root.tla.split(separator: "\n")
        let binding = try #require(plusCal.firstIndex { $0.contains("with (__atomic_0 =") })
        let guardLine = plusCal[binding - 1].trimmingCharacters(in: .whitespaces)
        let guard_ = try #require(guardLine.hasPrefix("when ") && guardLine.hasSuffix(";")
            ? String(guardLine.dropFirst(5).dropLast()) : nil)
        let small = "(count >= -1000000000 /\\ count <= 1000000000 /\\ -1 >= -1000000000 /\\ -1 <= 1000000000)"
        let exact = "(IF -1 > 0 THEN count >= \(TLAValue.int(.min).description) + (-1) ELSE IF -1 < 0 THEN count <= \(TLAValue.int(.max).description) + (-1) ELSE TRUE)"
        #expect(guard_ == "(IF \(small) THEN TRUE ELSE \(exact))")
        #expect(output.contains("IF \(guard_) THEN"))
        #expect(output.contains("__SwiftTLAOverflowFailure0 == (((pc = \"advance\")) = TRUE /\\ ~(\(guard_)))"))
        #expect(plusCal.contains("__SwiftTLAOverflowOperation0 == \"subtraction\""))
        #expect(plusCal.contains("__SwiftTLAOverflowOperands0 == <<count, -1>>"))

        let underflow = try CheckedSubtractionUnderflow.makeMachine()
        #expect(throws: NativeMachineEvaluationError.integerOverflow(
            .subtraction, operands: [Int.min + 1, 2])) {
            try underflow.successors(for: .advance)
        }
        let underflowTLA = try CheckedSubtractionUnderflow.render().tlaBundle.root.tla
        #expect(underflowTLA.contains("IF 2 > 0 THEN count >= \(TLAValue.int(.min).description) + (2)"))
        #expect(underflowTLA.contains("__SwiftTLAOverflowOperation0 == \"subtraction\""))
        #expect(underflowTLA.contains("__SwiftTLAOverflowOperands0 == <<count, 2>>"))
    }

    @Test("generated multiplication preserves complete transitions and overflow failures")
    func multiplicationPreservesGeneratedOutcomes() throws {
        let compiled = try CheckedMultiplicationOverflow.spec.compile()
        let step = try #require(compiled.semantics.behavior.actions.first)
        guard case .and(.guard_(let control), let body) = step.body,
              case .equal = control.operation,
              case .define(_, let value, _) = body,
              case .multiply = value.operation,
              value.children.count == 2,
              case .stateVariable = value.children[0].operation,
              case .value(.integer(2)) = value.children[1].operation else {
            Issue.record("The authored step no longer lowers to checked multiplication")
            return
        }

        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "CheckedMultiplicationOverflow", program: program))
        let swiftAction = try #require(try emitter.machineMembers().first {
            $0.description.contains("private static func _visitUpdates0(")
        }?.description)
        let witness = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/CheckedExecutionOverflowSwiftWitness.txt")
            .standardizedFileURL
        let expectedSwift = try String(contentsOf: witness, encoding: .utf8)
            .replacingOccurrences(of: "let _arithmetic1: Int = 1", with: "let _arithmetic1: Int = 2")
            .replacingOccurrences(of: "_NativeMachineOperations.add", with: "_NativeMachineOperations.multiply")
        #expect(Array(Parser.parse(source: swiftAction).tokens(viewMode: .sourceAccurate)).map(\.text)
            == Array(Parser.parse(source: expectedSwift).tokens(viewMode: .sourceAccurate)).map(\.text))

        var successful = try CheckedMultiplicationOverflow.makeMachine(.init(count: 3))
        let transition = try successful.send(.advance)
        #expect(transition.before.count == 3 && transition.after.count == 6)
        let controlToken = try #require(TLAStateProjection.Token(validating: "pc"))
        #expect(try successful.formalProjection(of: successful.snapshot).value(for: controlToken) == .string("Done"))

        for count in [Int.max, -Int.max] {
            let failing = try CheckedMultiplicationOverflow.makeMachine(.init(count: count))
            let before = failing.snapshot
            #expect(throws: NativeMachineEvaluationError.integerOverflow(
                .multiplication, operands: [count, 2])) {
                try failing.successors(for: .advance)
            }
            #expect(failing.snapshot == before)
        }

        let rendered = try CheckedMultiplicationOverflow.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let output = rendered.tlaBundle.root.tla
        let small = "(count >= -40000 /\\ count <= 40000 /\\ 2 >= -40000 /\\ 2 <= 40000)"
        let exact = "(count * 2 >= \(TLAValue.int(.min).description) /\\ count * 2 <= \(TLAValue.int(.max).description))"
        let guard_ = "(IF \(small) THEN TRUE ELSE \(exact))"
        #expect(output.contains("IF \(guard_) THEN"))
        #expect(output.contains("__SwiftTLAOverflowFailure0 == (((pc = \"advance\")) = TRUE /\\ ~(\(guard_)))"))
        #expect(output.contains("__SwiftTLAOverflowOperation0 == \"multiplication\""))
        #expect(output.contains("__SwiftTLAOverflowOperands0 == <<count, 2>>"))

        let plusCal = try rendered.plusCalBundle().root.tla.split(separator: "\n")
        let binding = try #require(plusCal.firstIndex { $0.contains("with (__atomic_0 =") })
        #expect(plusCal[binding - 1].trimmingCharacters(in: .whitespaces) == "when \(guard_);")
        #expect(plusCal.contains("__SwiftTLAOverflowOperation0 == \"multiplication\""))
        #expect(plusCal.contains("__SwiftTLAOverflowOperands0 == <<count, 2>>"))
    }

    @Test("nested negation preserves ordered failure and complete state")
    func negationPreservesGeneratedOutcomes() throws {
        #expect(Int.min == -Int.max - 1)
        var successful = try CheckedNestedNegation.makeMachine(.init(count: 3))
        let transition = try successful.send(.advance)
        #expect(transition.before.count == 3 && transition.after.count == -2)
        let controlToken = try #require(TLAStateProjection.Token(validating: "pc"))
        #expect(try successful.formalProjection(of: successful.snapshot).value(for: controlToken) == .string("Done"))

        let failing = try CheckedNestedNegation.makeMachine(.init(count: -Int.max))
        let before = failing.snapshot
        #expect(throws: NativeMachineEvaluationError.integerOverflow(
            .negation, operands: [Int.min])) {
            try failing.successors(for: .advance)
        }
        #expect(failing.snapshot == before)

        let rendered = try CheckedNestedNegation.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let output = rendered.tlaBundle.root.tla
        #expect(output.contains("__SwiftTLAOverflowOperation0 == \"subtraction\""))
        #expect(output.contains("__SwiftTLAOverflowOperation0_1 == \"negation\""))
        #expect(output.contains("__SwiftTLAOverflowOperands0_1 == <<(count - 1)>>"))
        #expect(output.contains("IF ((count - 1) >= -1000000000 /\\ (count - 1) <= 1000000000) THEN TRUE ELSE (count - 1) # \(TLAValue.int(.min).description)"))
        #expect(output.contains("__SwiftTLAAnyEvaluationFailure0 =="))
        #expect(output.contains("__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)"))
    }

    @Test("generated TLA export rejects a different target Int width")
    func rejectsCrossWidthExport() throws {
        let source = "---- MODULE WidthMismatch ----\n====\n"
        do {
            _ = try RenderedSpecification(_generatedModule: "WidthMismatch", source: source,
                compilationIdentity: "width-mismatch", declarations: [], checkDeadlock: false,
                _generatedIntegerBitWidth: Int.bitWidth - 1, _generatedIntrinsicInvariants: [],
                invariants: [], reachabilityProperties: [], properties: [], refinements: [],
                symmetry: [], actions: [])
            Issue.record("Expected a target-width diagnostic")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .compilationIdentityMismatch)
            #expect(diagnostic.path == "generatedIntegerBitWidth")
        }
    }

    @Test("generated Swift retains valid Int results beyond TLC's integer range")
    func arithmeticAboveTLCIntegerRange() throws {
        var machine = try CheckedExecutionBeyondTLCIntegerRange.makeMachine()
        let transition = try machine.send(.advance)
        #expect(transition.after.count == 2_147_483_648)
    }

    @Test("evidence callback errors do not become model evaluation failures")
    func callbackErrorIsNotModelFailure() throws {
        let machine = try DuplicateExecutionPaths.makeMachine()
        let callbackError = NativeMachineEvaluationError.integerOverflow(.addition, operands: [1, 2])
        var modelFailureEvents = 0
        #expect(throws: callbackError) {
            _ = try MachineValidator.run(initialMachines: [machine], maximumStates: 3,
                checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
                if case .evaluationFailure = event { modelFailureEvents += 1 }
                if case .edge = event { throw callbackError }
            }
        }
        #expect(modelFailureEvents == 0)
    }

    @Test("invariant violations remain executable and observable")
    func invariantsAreObservations() throws {
        var machine = try ReachableInvariantFailure.makeMachine()
        #expect(try machine.violatedInvariants(atLevel: 1).isEmpty)
        #expect(try machine.send(.advance).after.count == 1)
        #expect(try machine.violatedInvariants(atLevel: 2) == [.Zero])
    }
}


@TLAModel
private struct CheckedRecordConversion {
    enum Step: String, CaseIterable { case valid, change, invalid }
    enum Level: Int, CaseIterable, FiniteTLAValueDomain {
        case zero = 0
        static var defaultValue: Self { .zero }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .int(rawValue) }
    }
    struct IntegerRecord: Hashable, Sendable { let count: Int }
    struct FiniteRecord: Hashable, Sendable { let count: Level }
    static var spec: TLASpec {
        #spec("CheckedRecordConversion") {
            let checkedRecordConversion = Algorithm(label: "CheckedRecordConversion", scoped: { scope in
                let record = scope.sharedVar(_name: "record", initial: IntegerRecord(count: 0))
                Do(
                    Step.valid,
                    when: record.expr.assuming(FiniteRecord.self).count == Level.zero
                ) {}
                Do(Step.change) {
                    Assign(record.count, to: 1)
                }
                Do(
                    Step.invalid,
                    when: record.expr.assuming(FiniteRecord.self).count == Level.zero
                ) {}
            })
            checkedRecordConversion
        }
    }
}

extension NativeExecutionBoundaryTests {
    @Test("record narrowing preserves valid fields and rejects out-of-domain values")
    func checkedRecordConversion() throws {
        var machine = try CheckedRecordConversion.makeMachine()
        _ = try machine.send(.valid)
        _ = try machine.send(.change)
        let before = machine.state
        #expect(before.record.count == 1)
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            try machine.send(.invalid)
        }
        #expect(machine.state == before)

        let rendered = try CheckedRecordConversion.render()
        #expect(rendered.intrinsicInvariantNames == ["__SwiftTLAEvaluationOK"])
        let proofInput = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/CheckedRecordConversion.tla")
            .standardizedFileURL
        let emitted = rendered.tlaBundle.root.tla
        let checked = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(emitted == checked)
        let cfg = try #require(rendered.tlaBundle(checking: [], checkDeadlock: false).root.cfg)
        #expect(cfg.contains("INVARIANT __SwiftTLAEvaluationOK\n"))

        let syntax = Parser.parse(source: try String(contentsOfFile: #filePath, encoding: .utf8))
        let declaration = try #require(syntax.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "CheckedRecordConversion" })
        var emitter = NativeSwiftEmitter(model: try TLASpecVerifier.parseAndVerify(declaration))
        let visitor = try #require(emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates2"
        })
        let swiftInput = proofInput.deletingLastPathComponent()
            .appendingPathComponent("CheckedRecordConversionSwiftVisitor.txt")
        let expectedSwift = try String(contentsOf: swiftInput, encoding: .utf8)
        func tokens(_ source: String) -> [String] {
            Parser.parse(source: source).tokens(viewMode: .sourceAccurate).map(\.text)
        }
        #expect(tokens(visitor.description) == tokens(expectedSwift))
        let wrongCase = visitor.description.replacingOccurrences(
            of: "case 0: return Level.`zero`", with: "case 1: return Level.`zero`")
        #expect(wrongCase != visitor.description)
        #expect(tokens(wrongCase) != tokens(expectedSwift))
    }
}
