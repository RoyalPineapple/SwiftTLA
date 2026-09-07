import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct CartesianInitialSelection {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("CartesianInitialSelection") {
            Algorithm("CartesianInitialSelection", scoped: { scope in
                let left = scope.sharedVar("left", in: 1...2)
                let right = scope.sharedVar("right", in: 3...4)
                Do(Step.advance) { Assign(left, to: left + right) }
            })
        }
    }
}

@TLAModel
private struct EmptyInitialSelection {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("EmptyInitialSelection") {
            Algorithm("EmptyInitialSelection", scoped: { scope in
                let count = scope.sharedVar("count", in: Where(SetExpr<Int>.literal(1)) { value in value < 0 })
                Do(Step.advance) { Assign(count, to: count + 1) }
            })
        }
    }
}

@TLAModel
private struct DuplicateExecutionPaths {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("DuplicateExecutionPaths") {
            Algorithm("DuplicateExecutionPaths", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(Step.advance) {
                    Either { Assign(count, to: 1) } or: { Assign(count, to: 1) }
                }
            })
        }
    }
}

@TLAModel
private struct HiddenControlAlternatives {
    enum Step: String, CaseIterable { case select, left, right }
    static var spec: TLASpec {
        #spec("HiddenControlAlternatives") {
            Algorithm("HiddenControlAlternatives", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(Step.select) {
                    Either { Goto(Step.left) } or: { Goto(Step.right) }
                }
                Do(Step.left) { Assign(count, to: 1) }
                Do(Step.right) { Assign(count, to: 2) }
            })
        }
    }
}

@TLAModel
private struct CheckedExecutionOverflow {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("CheckedExecutionOverflow") {
            Algorithm("CheckedExecutionOverflow", scoped: { scope in
                let count = scope.sharedVar("count", initial: 9_223_372_036_854_775_807)
                Do(Step.advance) { Assign(count, to: count + 1) }
            })
        }
    }
}

@TLAModel
private struct ReachableInvariantFailure {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("ReachableInvariantFailure") {
            Algorithm("ReachableInvariantFailure", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(Step.advance) { Assign(count, to: 1) }
                Invariant("Zero") { count == 0 }
            })
        }
    }
}

@Suite struct NativeExecutionBoundaryTests {
    @Test("typed initial selection matches the complete formal Cartesian domain")
    func initialSelection() throws {
        let compilation = try CartesianInitialSelection.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let left = try #require(compilation.layout.testVariableID(named: "left"))
        let right = try #require(compilation.layout.testVariableID(named: "right"))
        let formal = try runtime.initialStates()
        let pairs = try Set(formal.map { state in
            [try state.value(for: left), try state.value(for: right)]
        })
        #expect(pairs.count == 4)
        for lhs in 1...2 {
            for rhs in 3...4 {
                let machine = try CartesianInitialSelection.makeMachine(initial: .init(left: lhs, right: rhs))
                #expect(pairs.contains([.integer(machine.state.left), .integer(machine.state.right)]))
            }
        }
        do {
            _ = try CartesianInitialSelection.makeMachine()
            Issue.record("Multiple initial states require explicit selection")
        } catch GeneratedMachineError.ambiguousInitialState {}
        do {
            _ = try CartesianInitialSelection.makeMachine(initial: .init(left: 9, right: 3))
            Issue.record("A selection outside the formal initial domain must fail")
        } catch GeneratedMachineError.invalidInitialState {}
    }

    @Test("empty formal initial domains reject both implicit and explicit construction")
    func emptyInitialDomain() throws {
        let runtime = CompiledRuntime(compilation: try EmptyInitialSelection.spec.compile())
        #expect(try runtime.initialStates().isEmpty)
        do {
            _ = try EmptyInitialSelection.makeMachine()
            Issue.record("Empty initial domains cannot construct a machine")
        } catch GeneratedMachineError.noInitialState {}
        do {
            _ = try EmptyInitialSelection.makeMachine(initial: .init(count: 1))
            Issue.record("Explicit selection cannot create a missing initial state")
        } catch GeneratedMachineError.invalidInitialState {}
    }

    @Test("duplicate paths coalesce while distinct hidden control states remain ambiguous")
    func successorIdentity() throws {
        let duplicateCompilation = try DuplicateExecutionPaths.spec.compile()
        let duplicateRuntime = CompiledRuntime(compilation: duplicateCompilation)
        let duplicateInitial = try #require(try duplicateRuntime.initialStates().first)
        let advance = try #require(duplicateCompilation.layout.testActionID(named: "advance"))
        #expect(Set(try duplicateRuntime.successors(for: advance, from: duplicateInitial).map(\.state)).count == 1)
        var duplicate = try DuplicateExecutionPaths.makeMachine()
        #expect(try duplicate.enabledActions() == [.advance])
        #expect(try duplicate.send(.advance).after.count == 1)

        let compilation = try HiddenControlAlternatives.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let select = try #require(compilation.layout.testActionID(named: "select"))
        let count = try #require(compilation.layout.testVariableID(named: "count"))
        let successors = try runtime.successors(for: select, from: initial)
        #expect(Set(successors.map(\.state)).count == 2)
        #expect(try Set(successors.map { try $0.state.value(for: count) }) == [.integer(0)])
        var machine = try HiddenControlAlternatives.makeMachine()
        let before = machine.state
        #expect(try machine.enabledActions() == [.select])
        do {
            _ = try machine.send(.select)
            Issue.record("Public equality must not merge distinct hidden control states")
        } catch GeneratedMachineError.ambiguousAction {}
        #expect(machine.state == before)
        #expect(try machine.enabledActions() == [.select])
    }

    @Test("checked arithmetic failure leaves native state and control unchanged")
    func arithmeticFailureIsTransactional() throws {
        let compilation = try CheckedExecutionOverflow.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let advance = try #require(compilation.layout.testActionID(named: "advance"))
        #expect(throws: EvalError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try runtime.successors(for: advance, from: initial)
        }
        var machine = try CheckedExecutionOverflow.makeMachine()
        let before = machine.state
        for _ in 0..<2 {
            #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
                try machine.send(.advance)
            }
            #expect(machine.state == before)
        }
    }

    @Test("invariant violations remain reachable and are reported by both engines")
    func invariantsAreObservations() throws {
        let compilation = try ReachableInvariantFailure.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let advance = try #require(compilation.layout.testActionID(named: "advance"))
        let invariant = try #require(compilation.semantics.invariants.first)
        #expect(try runtime.invariantHolds(invariant, in: initial))
        let successor = try #require(try runtime.successors(for: advance, from: initial).first)
        #expect(try !runtime.invariantHolds(invariant, in: successor.state))
        var machine = try ReachableInvariantFailure.makeMachine()
        #expect(try machine.violatedInvariants().isEmpty)
        #expect(try machine.send(.advance).after.count == 1)
        #expect(try machine.violatedInvariants() == [invariant.name])
    }
}
