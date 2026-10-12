import Foundation
import SwiftTLA
import Testing

@Suite("Choice evaluation failures")
struct ChoiceEvaluationFailureTests {
    @Test("A failing sole candidate is reported by both generated checking paths")
    func soleCandidateFailure() throws {
        let machine = try SingleCandidateDivisionFailureModel.makeMachine()
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.successors(for: .pick)
        }

        let rendered = try SingleCandidateDivisionFailureModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==") })
    }

    @Test("A failing candidate does not hide another candidate's successor")
    func mixedCandidateOutcome() throws {
        let machine = try MixedCandidateDivisionFailureModel.makeMachine()
        var states: [Int: Int] = [:]
        var edges: [(Int, Int)] = []
        var observedFailure = false
        let outcome = try MachineValidator.run(initialMachines: [machine], maximumStates: 2,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
            switch event {
            case .state(let id, let snapshot, _, _, _): states[id] = snapshot.state.result
            case .edge(let source, let action, let target):
                #expect(action == .pick)
                edges.append((source, target))
            case .evaluationFailure(let source, let action, let reason):
                observedFailure = true
                #expect(source == 0 && action == .pick && reason == .divisionByZero)
            default: break
            }
        }
        #expect(observedFailure)
        #expect(outcome.completion == .evaluationFailure(.divisionByZero))
        #expect(outcome.states == 2 && outcome.edges == 1)
        #expect(states == [0: 0, 1: 1])
        #expect(edges.count == 1 && edges[0].0 == 0 && edges[0].1 == 1)

        let rendered = try MixedCandidateDivisionFailureModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        let failure = try #require(definitions.first {
            $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==")
        })
        #expect(failure.contains("__atomic_0 \\in 0..1"))
        let divisors = try #require(definitions.first {
            $0.hasPrefix("__SwiftTLADivisionByZeroDivisor0 ==")
        })
        #expect(divisors.contains("__atomic_0 \\in {__atomic_0 \\in 0..1:"))
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/MixedCandidateDivisionFailureModel.tla")
            .standardizedFileURL
        #expect(rendered.tlaBundle.root.tla == (try String(contentsOf: proofInput, encoding: .utf8)))
    }
}
