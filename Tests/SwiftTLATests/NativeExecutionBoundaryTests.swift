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
        let compiledAction = try #require(compiled.semantics.behavior.actions.first)
        guard case .and(.guard_, let body) = compiledAction.body,
              case .define(_, let addition, _) = body,
              case .add = addition.operation,
              addition.children.count == 2,
              case .stateVariable(let source) = addition.children[0].operation,
              case .value(.integer(1)) = addition.children[1].operation else {
            Issue.record("The authored addition no longer lowers to the checked root-addition rule")
            return
        }
        #expect(source == count.id)

        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "CheckedExecutionOverflow", program: program))
        let members = try emitter.machineMembers()
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

        let rendered = try CheckedExecutionOverflow.render()
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/CheckedExecutionOverflow.tla")
            .standardizedFileURL
        #expect(rendered.tlaBundle.root.tla == (try String(contentsOf: proofInput, encoding: .utf8)))
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
        #expect(evaluation == "__SwiftTLAEvaluationOK == ~(__SwiftTLAOverflowFailure0)")
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
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            try machine.send(.invalid)
        }
        #expect(machine.state == before)
    }
}
