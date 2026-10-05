import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct DescribedIntegerState {
    enum Rank: Swift.Int, SwiftTLA.FiniteTLAValueDomain, Swift.CustomStringConvertible {
        case low = 1, high = 2
        static var defaultValue: Self { .low }
        static let finiteValues: [Self] = [.low, .high]
        var description: String { self == .low ? "Low priority" : "High priority" }
    }
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec {
            let describedIntegerState = Algorithm(label: "DescribedIntegerState", scoped: { scope in
                let rank = scope.sharedVar(initial: Rank.low)
                Do(Step.advance) {
                    Assign(rank, to: Rank.high)
                }
            })
            describedIntegerState
        }
    }
}

@TLAModel
private struct BoundedExecutionCounter {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec {
            let boundedExecutionCounter = Algorithm(label: "BoundedExecutionCounter", scoped: { scope in
                let count = scope.sharedVar(initial: 0)
                While(Step.advance, true) {
                    When(count < 3)
                    Assign(count, to: count + 1)
                }
            })
            boundedExecutionCounter
        }
    }
}

@TLAModel
private struct SavedValueExecutionSwap {
    enum Step: String, CaseIterable { case swap }
    static var spec: TLASpec {
        #spec {
            let savedValueExecutionSwap = Algorithm(label: "SavedValueExecutionSwap", scoped: { scope in
                let left = scope.sharedVar(initial: 1)
                let right = scope.sharedVar(initial: 2)
                While(Step.swap, true) {
                    let originalLeft = left
                    Assign(left, to: right)
                    Assign(right, to: originalLeft)
                }
            })
            savedValueExecutionSwap
        }
    }
}

@TLAModel
private struct ConstrainedExecutionChoice {
    enum Step: String, CaseIterable { case select }
    static var spec: TLASpec {
        #spec {
            let constrainedExecutionChoice = Algorithm(label: "ConstrainedExecutionChoice", scoped: { scope in
                let selected = scope.sharedVar(initial: 0)
                While(Step.select, true) {
                    Choose(1...3) { choice in
                        Assign(selected, to: choice.expr)
                    }
                }
                StateConstraint(selected <= 1)
            })
            constrainedExecutionChoice
        }
    }
}

@TLAModel
private struct AmbiguousExecutionChoice {
    enum Step: String, CaseIterable { case select }
    static var spec: TLASpec {
        #spec {
            let BelowTwo = Invariant()
            let ambiguousExecutionChoice = Algorithm(label: "AmbiguousExecutionChoice", scoped: { scope in
                let selected = scope.sharedVar(in: 0...1)
                While(Step.select, true) {
                    When(selected < 2)
                    Choose(1...3) { choice in
                        Assign(selected, to: choice.expr)
                    }
                }
                StateConstraint(selected <= 2)
                BelowTwo { selected < 2 }
            })
            ambiguousExecutionChoice
        }
    }
}

@Suite("Generated transition contracts")
struct NativeMachineExecutionTests {
    @Test("Display descriptions do not change integer enum encoding or machine behavior")
    func describedEnumsPreserveFormalEncoding() throws {
        typealias Rank = DescribedIntegerState.Rank
        #expect(Rank.low.description == "Low priority")
        #expect(Rank.low.tlaValue == .int(1))
        #expect(Rank(formalValue: Rank.low.tlaValue) == .low)
        let rank = try #require(TLAStateProjection.Token(validating: "rank"))
        var machine = try DescribedIntegerState.makeMachine()
        #expect(try machine.formalProjection(of: machine.snapshot).value(for: rank) == .int(1))
        _ = try machine.send(.advance)
        #expect(machine.state.rank == .high)
        #expect(try machine.formalProjection(of: machine.snapshot).value(for: rank) == .int(2))
    }

    @Test("Bounded counter preserves exact steps and complete checking")
    func counterStepsAndChecking() throws {
        var machine = try BoundedExecutionCounter.makeMachine()
        var observed = Set<Int>()

        for expected in 0...3 {
            observed.insert(machine.state.count)
            #expect(machine.state.count == expected)
            #expect(try machine.isEnabled(.advance) == (expected < 3))
            #expect(try machine.enabledActions() == (expected < 3 ? [.advance] : []))
            if expected < 3 {
                let before = machine.state
                let transition = try machine.send(.advance)
                #expect(transition.before == before)
                #expect(transition.after == machine.state)
            }
        }
        let before = machine.state
        do {
            _ = try machine.send(.advance)
            Issue.record("A disabled action must fail")
        } catch GeneratedMachineError.noMatchingSuccessor {}
        #expect(machine.state == before)
        var checked: Set<Int> = []
        let result = try MachineValidator.run(
            initialMachines: BoundedExecutionCounter.initialMachines(), maximumStates: 16,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false
        ) { event in
            if case .state(_, let snapshot, _, _, _) = event {
                checked.insert(snapshot.state.count)
            }
        }
        if case .exhausted = result.completion {} else { Issue.record("Native checking stopped early") }
        #expect(result.initialStates == 1)
        #expect(result.states == 4)
        #expect(result.edges == 3)
        #expect(checked == observed)
    }

    @Test("Saved values preserve a swap across a complete cycle")
    func swapsSavedValues() throws {
        var machine = try SavedValueExecutionSwap.makeMachine()
        for _ in 0..<2 {
            let before = machine.state
            _ = try machine.send(.swap)
            #expect(machine.state.left == before.right)
            #expect(machine.state.right == before.left)
        }
        #expect(machine.state.left == 1)
        #expect(machine.state.right == 2)
    }

    @Test("State constraints do not resolve executable choice ambiguity")
    func constrainedChoiceRemainsAmbiguous() throws {
        var machine = try ConstrainedExecutionChoice.makeMachine()
        #expect(try machine.enabledActions() == [.select])
        #expect(try Set(machine.successors(for: .select).map { $0.state.selected }) == [1, 2, 3])
        do {
            _ = try machine.send(.select)
            Issue.record("All three executable choices must remain ambiguous")
        } catch GeneratedMachineError.ambiguousAction {}
        #expect(machine.state.selected == 0)
        let graph = try ReachabilityGraph(initialMachines: ConstrainedExecutionChoice.initialMachines(), maximumStates: 4)
        #expect(Set(graph.transitions.keys.map { $0.state.selected }) == [0, 1])
        #expect(graph.transitions.values.flatMap { $0 }.allSatisfy { $0.target.state.selected == 1 })
        #expect(graph.transitions.values.flatMap { $0 }.count == 2)
        #expect(graph.safetyViolations.isEmpty)
    }

    @Test("Every initial state and executable branch retains disabled actions and invariant failures")
    func completeChoiceGraph() throws {
        let nativeInitial = try AmbiguousExecutionChoice.initialMachines()
        #expect(nativeInitial.count == 2)
        #expect(Set(nativeInitial.map { $0.state.selected }) == [0, 1])
        var pending = nativeInitial
        var visited: Set<AmbiguousExecutionChoice.Snapshot> = []
        var edges: Set<[Int]> = []
        var violations: Set<Int> = []
        var disabled: Set<Int> = []
        while let machine = pending.popLast() {
            guard visited.insert(machine.snapshot).inserted else { continue }
            let source = machine.state.selected
            let nativeNext = try machine.successors()
            #expect(nativeNext.allSatisfy { $0.action == .select })
            #expect(nativeNext.count == (source < 2 ? 3 : 0))
            #expect(Set(nativeNext.map { $0.machine.state.selected }) == Set(source < 2 ? [1, 2, 3] : []))
            #expect(try machine.enabledActions() == (source < 2 ? [.select] : []))
            #expect(try machine.isEnabled(.select) == (source < 2))
            let failed = try machine.violatedInvariants(atLevel: 1)
            #expect(failed == (source < 2 ? [] : [.BelowTwo]))
            if !failed.isEmpty { violations.insert(source) }
            var sending = machine
            if nativeNext.isEmpty {
                disabled.insert(source)
                do {
                    _ = try sending.send(.select)
                    Issue.record("A disabled action must fail")
                } catch GeneratedMachineError.noMatchingSuccessor {}
                #expect(sending.state == machine.state)
            } else {
                do {
                    _ = try sending.send(.select)
                    Issue.record("An ambiguous action must fail")
                } catch GeneratedMachineError.ambiguousAction {}
                #expect(sending.state == machine.state)
            }
            for successor in nativeNext {
                let target = successor.machine.state.selected
                edges.insert([source, target])
                pending.append(successor.machine)
            }
        }
        #expect(Set(visited.map { $0.state.selected }) == [0, 1, 2, 3])
        #expect(edges == [[0, 1], [0, 2], [0, 3], [1, 1], [1, 2], [1, 3]])
        #expect(disabled == [2, 3])
        #expect(violations == [2, 3])
        let graph = try ReachabilityGraph(initialMachines: nativeInitial, maximumStates: 4)
        #expect(Set(graph.transitions.keys.map { $0.state.selected }) == [0, 1, 2])
        #expect(graph.transitions.values.flatMap { $0 }.count == 4)
        #expect(Set(graph.deadlockedStates.map { $0.state.selected }) == [2])
        #expect(Set(graph.safetyViolations.keys.map { $0.state.selected }) == [2, 3])
        let excluded = try #require(graph.safetyViolations.keys.first { $0.state.selected == 3 })
        #expect(graph.transitions[excluded] == nil)
        #expect(graph.safetyViolations[excluded] == [.invariant(.BelowTwo)])
        #expect(try graph.trace(to: excluded).count == 2)
    }

}
