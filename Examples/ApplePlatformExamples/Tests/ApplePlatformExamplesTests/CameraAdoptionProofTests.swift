import AVPipeline
import SwiftTLA
import XCTest

final class CameraAdoptionProofTests: XCTestCase {
    func testGeneratedMachineInitializesWithCompleteTypedState() throws {
        let machine = try CameraWorkflow.makeMachine()
        let state: CameraWorkflow.State = machine.state

        XCTAssertEqual(state.phase, .starting)
    }

    func testTypedActionReplacesGeneratedState() throws {
        var machine = try CameraWorkflow.makeMachine()
        let transitionBefore = machine.state
        try machine.send(.ready)

        XCTAssertEqual(transitionBefore.phase, .starting)
        XCTAssertEqual(machine.state.phase, .live)
    }

    func testRejectedTypedActionPreservesGeneratedState() throws {
        var machine = try CameraWorkflow.makeMachine()
        let before = machine.state

        XCTAssertThrowsError(try machine.send(.record)) { error in
            guard let generatedError = error as? GeneratedMachineError else {
                return XCTFail("Expected a generated-machine rejection, got \(error).")
            }
            guard case .noMatchingSuccessor = generatedError else {
                return XCTFail("Expected no matching successor, got \(generatedError).")
            }
        }
        XCTAssertEqual(machine.state, before)
    }

    func testGeneratedActorSerializesConcurrentDuplicateRecords() async throws {
        let actor = try CameraWorkflow.Actor()
        try await actor.send(.ready)

        async let first = submitRecord(to: actor)
        async let second = submitRecord(to: actor)
        let submissions = await [first, second]
        let accepted = submissions.filter(\.isAccepted)
        let rejections = submissions.filter(\.isNoMatchingSuccessor)

        XCTAssertEqual(accepted.count, 1)
        XCTAssertEqual(rejections.count, 1)
        let finalState = await actor.state
        XCTAssertEqual(finalState.phase, .recording)
    }

    func testTypedRecordingOutcomesReturnToLiveState() throws {
        for outcome in [
            CameraWorkflow.Action.recordingSucceeded,
            .recordingFailed,
            .recordingCancelled
        ] {
            var machine = try CameraWorkflow.makeMachine()
            try machine.send(.ready)
            try machine.send(.record)
            if outcome == .recordingSucceeded {
                try machine.send(.stopRecording)
            }

            try machine.send(outcome)

            XCTAssertEqual(machine.state.phase, .live)
        }
    }

    func testGeneratedApplicationValuesAreSendable() throws {
        requireSendable(CameraWorkflow.State.self)
        requireSendable(CameraWorkflow.Action.self)
        requireSendable(CameraWorkflow.Actor.self)
    }

    private func submitRecord(to actor: CameraWorkflow.Actor) async -> ActorSubmission {
        do {
            try await actor.send(.record)
            return .accepted
        } catch let error as GeneratedMachineError {
            return .rejected(error)
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}

    private enum ActorSubmission: Sendable {
        case accepted
        case rejected(GeneratedMachineError)
        case failed(String)

        var isAccepted: Bool {
            if case .accepted = self { return true }
            return false
        }

        var isNoMatchingSuccessor: Bool {
            if case .rejected(.noMatchingSuccessor) = self { return true }
            return false
        }
    }
}
