import Foundation
import Testing
import SwiftTLA

struct CollectionCheckingTests {
    @Test("independent set steps preserve the complete generated graph")
    func checksSetSteps() throws {
        let graph = try ReachabilityGraph(initialMachines: SetStepMachine.initialMachines(), maximumStates: 10)
        #expect(graph.initialStates.count == 1)
        #expect(Set(graph.transitions.keys.map(\.state.seen)) == [Set<Int>(), Set<Int>([1])])
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 3)
        #expect(graph.safetyViolations.isEmpty)
        let empty = try #require(graph.transitions.first { $0.key.state.seen.isEmpty }?.value)
        #expect(empty.count == 1)
        #expect(empty.contains { $0.action == .add && $0.target.state.seen == Set([1]) })
        let occupied = try #require(graph.transitions.first { $0.key.state.seen == Set([1]) }?.value)
        #expect(occupied.count == 2)
        #expect(occupied.contains { $0.action == .add && $0.target.state.seen == Set([1]) })
        #expect(occupied.contains { $0.action == .remove && $0.target.state.seen.isEmpty })
        let tla = try SetStepMachine.render().tlaBundle.tla
        #expect(tla.contains("(seen \\cup {1})"))
        #expect(!tla.contains("VARIABLES pc"))
    }

    @Test("bounded array append has exactly one unfinished deadlock")
    func checksArraySteps() throws {
        let graph = try ReachabilityGraph(initialMachines: ArrayStepMachine.initialMachines(), maximumStates: 10)
        #expect(graph.initialStates.count == 1)
        #expect(Set(graph.transitions.keys.map(\.state.values)) == [[], [1], [1, 1]])
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 2)
        #expect(Set(graph.deadlockedStates.map(\.state.values)) == [[1, 1]])
        #expect(graph.safetyViolations.count == 1)
        #expect(graph.safetyViolations.first?.key.state.values == [1, 1])
        #expect(graph.safetyViolations.first?.value == [.deadlock])
        for (source, target) in [([Int](), [1]), ([1], [1, 1])] {
            let outgoing = try #require(graph.transitions.first { $0.key.state.values == source }?.value)
            #expect(outgoing.count == 1)
            #expect(outgoing.contains { $0.action == .append && $0.target.state.values == target })
        }
        let tla = try ArrayStepMachine.render().tlaBundle.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/ArrayStepMachine.tla")
            .standardizedFileURL
        #expect(tla == (try String(contentsOf: proofInput, encoding: .utf8)))
    }

    @Test("sequence concatenation preserves order, repeated values, and complete states")
    func checksSequenceConcatenation() throws {
        let graph = try ReachabilityGraph(
            initialMachines: SequenceConcatenationMachine.initialMachines(), maximumStates: 10)
        #expect(graph.initialStates.count == 1)
        #expect(Set(graph.transitions.keys.map(\.state.front)) == [[1], [1, 2, 2]])
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 1)
        #expect(Set(graph.deadlockedStates.map(\.state.front)) == [[1, 2, 2]])
        #expect(graph.safetyViolations.count == 1)
        #expect(graph.safetyViolations.first?.value == [.deadlock])
        for state in graph.transitions.keys { #expect(state.state.back == [2, 2]) }
        let outgoing = try #require(graph.transitions.first { $0.key.state.front == [1] }?.value)
        #expect(outgoing.count == 1)
        #expect(outgoing.contains {
            $0.action == .combine && $0.target.state.front == [1, 2, 2]
                && $0.target.state.back == [2, 2]
        })
        let tla = try SequenceConcatenationMachine.render().tlaBundle.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/SequenceConcatenationMachine.tla")
            .standardizedFileURL
        #expect(tla == (try String(contentsOf: proofInput, encoding: .utf8)))
    }

    @Test("sequence concatenation retains successes and first operand failures")
    func checksFallibleSequenceConcatenation() throws {
        let machines = try FallibleSequenceConcatenationMachine.initialMachines()
        #expect(machines.count == 4)
        for machine in machines {
            switch (machine.state.frontLength, machine.state.backLength) {
            case (1, 2):
                let successor = try #require(machine.successors(for: .combine).first)
                #expect(successor.state.front == [1, 2, 2])
                #expect(successor.state.back == [2, 2])
                #expect(successor.state.frontLength == 1 && successor.state.backLength == 2)
            case (1, 3):
                #expect(throws: NativeMachineEvaluationError.indexOutOfBounds(index: 3, count: 2)) {
                    try machine.successors(for: .combine)
                }
            case (2, 2), (2, 3):
                #expect(throws: NativeMachineEvaluationError.indexOutOfBounds(index: 2, count: 1)) {
                    try machine.successors(for: .combine)
                }
            default:
                Issue.record("Unexpected initial sequence-length pair")
            }
        }
        let tla = try FallibleSequenceConcatenationMachine.render().tlaBundle.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/FallibleSequenceConcatenationMachine.tla")
            .standardizedFileURL
        let expected = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(tla == expected, "Generated TLA:\n\(tla)")
    }

    @Test("sequence append preserves the failure of its prefix operand")
    func checksFallibleSequenceAppend() throws {
        let machines = try FallibleSequenceAppendMachine.initialMachines()
        #expect(machines.count == 2)
        for machine in machines {
            #expect(machine.state.values == [1])
            switch machine.state.length {
            case 1:
                let successors = try machine.successors(for: .append)
                #expect(successors.count == 1)
                let successor = try #require(successors.first)
                #expect(successor.state.values == [1, 3])
                #expect(successor.state.length == 1)
            case 2:
                #expect(throws: NativeMachineEvaluationError.indexOutOfBounds(index: 2, count: 1)) {
                    try machine.successors(for: .append)
                }
            default:
                Issue.record("Unexpected initial prefix length")
            }
        }
        let tla = try FallibleSequenceAppendMachine.render().tlaBundle.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/FallibleSequenceAppendMachine.tla")
            .standardizedFileURL
        let expected = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(tla == expected, "Generated TLA:\n\(tla)")
    }

    @Test("finite initial domain retains both states and an unfinished deadlock")
    func checksFiniteInitialStates() throws {
        let graph = try ReachabilityGraph(initialMachines: FiniteInitialStepMachine.initialMachines(), maximumStates: 10)
        #expect(Set(graph.initialStates.map(\.state.phase)) == [1, 2])
        #expect(Set(graph.transitions.keys.map(\.state.phase)) == [1, 2])
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 1)
        #expect(Set(graph.deadlockedStates.map(\.state.phase)) == [2])
        #expect(graph.safetyViolations.count == 1)
        #expect(graph.safetyViolations.first?.key.state.phase == 2)
        #expect(graph.safetyViolations.first?.value == [.deadlock])
        let outgoing = try #require(graph.transitions.first { $0.key.state.phase == 1 }?.value)
        #expect(outgoing.count == 1)
        #expect(outgoing.contains { $0.action == .prepare && $0.target.state.phase == 2 })
    }
}
