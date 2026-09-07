import AVPipeline
import SwiftTLA
import XCTest

final class CameraAdoptionProofTests: XCTestCase {
    func testGeneratedMachineInitializesWithCompleteTypedState() throws {
        let machine = try CameraWorkflow.makeMachine()
        let state: CameraWorkflow.State = machine.state

        XCTAssertEqual(state.phase, .starting)
    }

    func testTypedActionReturnsTransitionAndReplacesGeneratedState() throws {
        var machine = try CameraWorkflow.makeMachine()
        let transition: CameraWorkflow.Transition = try machine.send(.ready)

        XCTAssertEqual(transition.action, .ready)
        XCTAssertEqual(transition.before.phase, .starting)
        XCTAssertEqual(transition.after.phase, .live)
        XCTAssertEqual(machine.state, transition.after)
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
        _ = try await actor.send(.ready)

        async let first = submitRecord(to: actor)
        async let second = submitRecord(to: actor)
        let submissions = await [first, second]
        let transitions = submissions.compactMap(\.transition)
        let rejections = submissions.filter(\.isNoMatchingSuccessor)

        XCTAssertEqual(transitions.count, 1)
        XCTAssertEqual(transitions.first?.action, .record)
        XCTAssertEqual(transitions.first?.before.phase, .live)
        XCTAssertEqual(transitions.first?.after.phase, .recording)
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
            _ = try machine.send(.ready)
            _ = try machine.send(.record)
            if outcome == .recordingSucceeded {
                _ = try machine.send(.stopRecording)
            }

            let transition = try machine.send(outcome)

            XCTAssertEqual(transition.action, outcome)
            XCTAssertEqual(transition.after.phase, .live)
            XCTAssertEqual(machine.state, transition.after)
        }
    }

    func testGeneratedApplicationValuesAreSendable() throws {
        requireSendable(CameraWorkflow.State.self)
        requireSendable(CameraWorkflow.Action.self)
        requireSendable(CameraWorkflow.Transition.self)
        requireSendable(CameraWorkflow.Actor.self)
    }

    private func submitRecord(to actor: CameraWorkflow.Actor) async -> ActorSubmission {
        do {
            return .accepted(try await actor.send(.record))
        } catch let error as GeneratedMachineError {
            return .rejected(error)
        } catch {
            return .failed(String(describing: error))
        }
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}

    private enum ActorSubmission: Sendable {
        case accepted(CameraWorkflow.Transition)
        case rejected(GeneratedMachineError)
        case failed(String)

        var transition: CameraWorkflow.Transition? {
            guard case .accepted(let transition) = self else { return nil }
            return transition
        }

        var isNoMatchingSuccessor: Bool {
            if case .rejected(.noMatchingSuccessor) = self { return true }
            return false
        }
    }
}
