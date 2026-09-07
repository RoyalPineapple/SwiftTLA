import AVPipeline
import Bluetooth
import CoreBluetooth
import Foundation
import XCTest

final class GeneratedAppleModelTests: XCTestCase {
    private struct RecordingFailure: Error {}

    func testBluetoothGeneratedLifecycleExposesScanActions() async throws {
        var machine = try BluetoothModel.makeMachine()
        _ = try machine.send(.poweredOn)
        XCTAssertTrue(try machine.isEnabled(.startScan))
        XCTAssertFalse(try machine.isEnabled(.stopScan))

        _ = try machine.send(.startScan)
        let scanning = machine.state
        XCTAssertEqual(scanning.phase, .scanning)
        XCTAssertFalse(try machine.isEnabled(.startScan))
        XCTAssertTrue(try machine.isEnabled(.stopScan))

        _ = try machine.send(.stopScan)
        let poweredOn = machine.state
        XCTAssertEqual(poweredOn.phase, .poweredOn)
    }

    func testBluetoothManagerStatesMapToTypedActions() {
        XCTAssertEqual(BluetoothModel.Action(managerState: .poweredOn), .poweredOn)
        XCTAssertEqual(BluetoothModel.Action(managerState: .poweredOff), .poweredOff)
        XCTAssertNil(BluetoothModel.Action(managerState: .unknown))
    }

    func testPeripheralGeneratedLifecycle() async throws {
        var machine = try PeripheralModel.makeMachine()
        _ = try machine.send(.connected)
        _ = try machine.send(.beginDiscovery)
        _ = try machine.send(.finishDiscovery)
        let ready = machine.state
        XCTAssertEqual(ready.phase, .ready)
        _ = try machine.send(.disconnect)
        let disconnected = machine.state
        XCTAssertEqual(disconnected.phase, .disconnected)

        var failedDiscovery = try PeripheralModel.makeMachine()
        _ = try failedDiscovery.send(.connected)
        _ = try failedDiscovery.send(.beginDiscovery)
        _ = try failedDiscovery.send(.discoveryFailed)
        XCTAssertEqual(failedDiscovery.state.phase, .connected)
    }

    func testRecordingAttemptClassifiesCompletionFailureAndCancellation() {
        let id = UUID(uuidString: "4A9661D8-49EF-4ACF-A33D-506E42512407")!

        var completed = RecordingAttempt(id: id)
        XCTAssertEqual(completed.consumeCallback(error: nil, wasCancelled: false), .recordingSucceeded)

        var failed = RecordingAttempt(id: id)
        XCTAssertEqual(failed.consumeCallback(error: RecordingFailure(), wasCancelled: false), .recordingFailed)

        var cancelled = RecordingAttempt(id: id)
        cancelled.requestCancellation()
        XCTAssertEqual(cancelled.consumeCallback(error: nil, wasCancelled: false), .recordingCancelled)
    }

    func testRecordingAttemptIgnoresDuplicateAndLateCallbacks() {
        var attempt = RecordingAttempt(id: UUID(uuidString: "4A9661D8-49EF-4ACF-A33D-506E42512407")!)

        XCTAssertEqual(attempt.consumeCallback(error: nil, wasCancelled: false), .recordingSucceeded)
        XCTAssertNil(attempt.consumeCallback(error: RecordingFailure(), wasCancelled: false))
    }

    func testLateAndDuplicateCallbacksPreserveTheCurrentGeneratedState() throws {
        let firstID = UUID(uuidString: "4A9661D8-49EF-4ACF-A33D-506E42512407")!
        let secondID = UUID(uuidString: "D4E4A2B5-C85B-49BD-B8D7-6B28E959CD42")!
        var correlation = RecordingCallbackCorrelation()
        var machine = try CameraWorkflow.makeMachine()

        _ = try machine.send(.ready)

        correlation.begin(RecordingAttempt(id: firstID))
        _ = try machine.send(.record)
        _ = try machine.send(.stopRecording)
        let firstOutcome = correlation.consumeCallback(for: firstID, error: nil, wasCancelled: false)
        guard case .submitted(let completedID, let completedAction) = firstOutcome else {
            return XCTFail("Expected A's completed callback to submit an outcome.")
        }
        XCTAssertEqual(completedID, firstID)
        _ = try machine.send(completedAction)
        XCTAssertEqual(machine.state.phase, .live)

        correlation.begin(RecordingAttempt(id: secondID))
        _ = try machine.send(.record)
        let stateBeforeLateCallback = machine.state
        XCTAssertEqual(correlation.pendingAttemptID, secondID)
        let lateFirstOutcome = correlation.consumeCallback(for: firstID, error: nil, wasCancelled: false)
        guard case .ignored(let callbackID, let activeID) = lateFirstOutcome else {
            return XCTFail("Expected A's late callback to be ignored while B is pending.")
        }
        XCTAssertEqual(callbackID, firstID)
        XCTAssertEqual(activeID, secondID)
        XCTAssertEqual(correlation.pendingAttemptID, secondID)
        XCTAssertEqual(machine.state, stateBeforeLateCallback)

        let secondOutcome = correlation.consumeCallback(for: secondID, error: RecordingFailure(), wasCancelled: false)
        guard case .submitted(let submittedID, let submittedAction) = secondOutcome else {
            return XCTFail("Expected B's callback to submit its own outcome.")
        }
        XCTAssertEqual(submittedID, secondID)
        let secondTransition = try machine.send(submittedAction)
        XCTAssertEqual(secondTransition.before.phase, .recording)
        XCTAssertEqual(secondTransition.after.phase, .live)

        let stateBeforeDuplicateCallback = machine.state
        let duplicateSecondOutcome = correlation.consumeCallback(for: secondID, error: nil, wasCancelled: false)
        guard case .ignored(let duplicateCallbackID, let duplicateActiveID) = duplicateSecondOutcome else {
            return XCTFail("Expected B's duplicate callback to be ignored after its outcome.")
        }
        XCTAssertEqual(duplicateCallbackID, secondID)
        XCTAssertNil(duplicateActiveID)
        XCTAssertEqual(machine.state, stateBeforeDuplicateCallback)
    }

}
