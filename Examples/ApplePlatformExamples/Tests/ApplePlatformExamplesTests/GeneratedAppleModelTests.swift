import AVPipeline
import Bluetooth
import XCTest

final class GeneratedAppleModelTests: XCTestCase {
    func testCaptureGeneratedLifecycle() async throws {
        var machine = try CaptureModel.makeMachine()
        _ = try machine.send(.configure)
        let configured = machine.state
        XCTAssertEqual(configured.phase, .configured)
        _ = try machine.send(.start)
        let running = machine.state
        XCTAssertEqual(running.phase, .running)
        _ = try machine.send(.stop)
        let idle = machine.state
        XCTAssertEqual(idle.phase, .idle)
    }

    func testBluetoothGeneratedLifecycle() async throws {
        var machine = try BluetoothModel.makeMachine()
        _ = try machine.send(.poweredOn)
        _ = try machine.send(.startScan)
        let scanning = machine.state
        XCTAssertEqual(scanning.phase, .scanning)
        _ = try machine.send(.stopScan)
        let poweredOn = machine.state
        XCTAssertEqual(poweredOn.phase, .poweredOn)
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
    }

    func testAVGeneratedLifecycles() async throws {
        var writer = try WriterModel.makeMachine()
        _ = try writer.send(.start)
        _ = try writer.send(.write)
        _ = try writer.send(.pause)
        _ = try writer.send(.resume)
        _ = try writer.send(.finish)
        let finishedWriter = writer.state
        XCTAssertEqual(finishedWriter.phase, .finished)

        var player = try PlayerModel.makeMachine()
        _ = try player.send(.beginLoad)
        _ = try player.send(.ready)
        _ = try player.send(.play)
        _ = try player.send(.pause)
        _ = try player.send(.seek)
        _ = try player.send(.play)
        _ = try player.send(.finish)
        let finishedPlayer = player.state
        XCTAssertEqual(finishedPlayer.phase, .finished)

        var pipeline = try MediaPipelineModel.makeMachine()
        _ = try pipeline.send(.beginCapture)
        _ = try pipeline.send(.beginWriting)
        _ = try pipeline.send(.finishWriting)
        _ = try pipeline.send(.play)
        _ = try pipeline.send(.stop)
        let idlePipeline = pipeline.state
        XCTAssertEqual(idlePipeline.stage, .idle)

        var diskStore = try DiskStoreModel.makeMachine()
        _ = try diskStore.send(.write)
        _ = try diskStore.send(.delete)
        _ = try diskStore.send(.clear)
        let readyDiskStore = diskStore.state
        XCTAssertEqual(readyDiskStore.phase, .ready)
    }
}
