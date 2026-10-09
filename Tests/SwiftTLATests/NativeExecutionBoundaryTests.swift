import Testing
@testable import SwiftTLA
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
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try ReachabilityGraph(initialMachines: [machine], maximumStates: 2)
        }
        for _ in 0..<2 {
            #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
                try machine.send(.advance)
            }
            #expect(machine.snapshot == before)
        }
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
