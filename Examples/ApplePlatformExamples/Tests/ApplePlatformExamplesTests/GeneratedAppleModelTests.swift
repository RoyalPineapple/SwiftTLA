import AVPipeline
import Bluetooth
import CoreBluetooth
import Foundation
import XCTest

final class GeneratedAppleModelTests: XCTestCase {
    private struct RecordingFailure: Error {}

    func testBoundInvariantsRemainSelectedForExport() throws {
        XCTAssertEqual(try BluetoothModel.render().checkNames, Set(["knownCentralPhase"]))
        XCTAssertEqual(try PeripheralModel.render().checkNames, Set(["knownPeripheralPhase"]))
        XCTAssertEqual(try CameraWorkflow.render().checkNames, Set(["validPhase"]))
    }

    func testBluetoothGeneratedLifecycleExposesScanActions() async throws {
        var machine = try BluetoothModel.makeMachine()
        try machine.send(.poweredOn)
        XCTAssertTrue(try machine.isEnabled(.startScan))
        XCTAssertFalse(try machine.isEnabled(.stopScan))

        try machine.send(.startScan)
        let scanning = machine.state
        XCTAssertEqual(scanning.phase, .scanning)
        XCTAssertFalse(try machine.isEnabled(.startScan))
        XCTAssertTrue(try machine.isEnabled(.stopScan))

        try machine.send(.stopScan)
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
        try machine.send(.connected)
        try machine.send(.beginDiscovery)
        try machine.send(.finishDiscovery)
        let ready = machine.state
        XCTAssertEqual(ready.phase, .ready)
        try machine.send(.disconnect)
        let disconnected = machine.state
        XCTAssertEqual(disconnected.phase, .disconnected)

        var failedDiscovery = try PeripheralModel.makeMachine()
        try failedDiscovery.send(.connected)
        try failedDiscovery.send(.beginDiscovery)
        try failedDiscovery.send(.discoveryFailed)
        XCTAssertEqual(failedDiscovery.state.phase, .connected)
    }

    func testRecordingCallbacksClassifyCompletionFailureAndCancellation() throws {
        let id = try XCTUnwrap(UUID(uuidString: "4A9661D8-49EF-4ACF-A33D-506E42512407"))

        var completed = RecordingCallbackCorrelation()
        XCTAssertEqual(completed.begin(id: id), id)
        XCTAssertEqual(completed.consumeCallback(for: id, error: nil), .recordingSucceeded)

        var failed = RecordingCallbackCorrelation()
        XCTAssertEqual(failed.begin(id: id), id)
        XCTAssertEqual(failed.consumeCallback(for: id, error: RecordingFailure()), .recordingFailed)

        var cancelled = RecordingCallbackCorrelation()
        XCTAssertEqual(cancelled.begin(id: id), id)
        XCTAssertTrue(cancelled.requestCancellation(for: id))
        XCTAssertEqual(cancelled.consumeCallback(for: id, error: nil), .recordingCancelled)
    }

    func testRecordingCallbacksIgnoreDuplicateCallbacks() throws {
        let id = try XCTUnwrap(UUID(uuidString: "4A9661D8-49EF-4ACF-A33D-506E42512407"))
        var callbacks = RecordingCallbackCorrelation()

        XCTAssertEqual(callbacks.begin(id: id), id)
        XCTAssertEqual(callbacks.consumeCallback(for: id, error: nil), .recordingSucceeded)
        XCTAssertNil(callbacks.consumeCallback(for: id, error: RecordingFailure()))
    }

    func testLateAndDuplicateCallbacksPreserveTheCurrentGeneratedState() throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "4A9661D8-49EF-4ACF-A33D-506E42512407"))
        let secondID = try XCTUnwrap(UUID(uuidString: "D4E4A2B5-C85B-49BD-B8D7-6B28E959CD42"))
        var correlation = RecordingCallbackCorrelation()
        var machine = try CameraWorkflow.makeMachine()

        try machine.send(.ready)

        XCTAssertEqual(correlation.begin(id: firstID), firstID)
        try machine.send(.record)
        try machine.send(.stopRecording)
        let completedAction = try XCTUnwrap(correlation.consumeCallback(for: firstID, error: nil))
        try machine.send(completedAction)
        XCTAssertEqual(machine.state.phase, .live)

        XCTAssertEqual(correlation.begin(id: secondID), secondID)
        try machine.send(.record)
        let stateBeforeLateCallback = machine.state
        XCTAssertEqual(correlation.pendingAttemptID, secondID)
        XCTAssertNil(correlation.consumeCallback(for: firstID, error: nil))
        XCTAssertEqual(correlation.pendingAttemptID, secondID)
        XCTAssertEqual(machine.state, stateBeforeLateCallback)

        let submittedAction = try XCTUnwrap(correlation.consumeCallback(for: secondID, error: RecordingFailure()))
        let secondTransitionBefore = machine.state
        try machine.send(submittedAction)
        XCTAssertEqual(secondTransitionBefore.phase, .recording)
        XCTAssertEqual(machine.state.phase, .live)

        let stateBeforeDuplicateCallback = machine.state
        XCTAssertNil(correlation.consumeCallback(for: secondID, error: nil))
        XCTAssertEqual(machine.state, stateBeforeDuplicateCallback)
    }

}
