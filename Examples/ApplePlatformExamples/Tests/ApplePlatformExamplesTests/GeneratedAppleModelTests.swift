import AVPipeline
import Bluetooth
import XCTest

final class GeneratedAppleModelTests: XCTestCase {
    func testBluetoothModelsVerify() throws {
        try BluetoothModel.verifySpec(configuration: .standard)
        try PeripheralModel.verifySpec(configuration: .standard)
    }

    func testAVPipelineModelsVerify() throws {
        try CaptureModel.verifySpec(configuration: .standard)
        try WriterModel.verifySpec(configuration: .standard)
        try PlayerModel.verifySpec(configuration: .standard)
        try DiskStoreModel.verifySpec(configuration: .standard)
        try MediaPipelineModel.verifySpec(configuration: .standard)
    }

    func testCaptureGeneratedLifecycle() async throws {
        let machine = CaptureModel.Machine()
        _ = try await machine.apply(.configure)
        let configured = await machine.state
        XCTAssertEqual(configured.phase, .configured)
        _ = try await machine.apply(.start)
        let running = await machine.state
        XCTAssertEqual(running.phase, .running)
        _ = try await machine.apply(.stop)
        let idle = await machine.state
        XCTAssertEqual(idle.phase, .idle)
    }

    func testBluetoothGeneratedLifecycle() async throws {
        let machine = BluetoothModel.Machine()
        _ = try await machine.apply(.poweredOn)
        _ = try await machine.apply(.startScan)
        let scanning = await machine.state
        XCTAssertEqual(scanning.phase, .scanning)
        _ = try await machine.apply(.stopScan)
        let poweredOn = await machine.state
        XCTAssertEqual(poweredOn.phase, .poweredOn)
    }

    func testPeripheralGeneratedLifecycle() async throws {
        let machine = PeripheralModel.Machine()
        _ = try await machine.apply(.connected)
        _ = try await machine.apply(.beginDiscovery)
        _ = try await machine.apply(.finishDiscovery)
        let ready = await machine.state
        XCTAssertEqual(ready.phase, .ready)
        _ = try await machine.apply(.disconnect)
        let disconnected = await machine.state
        XCTAssertEqual(disconnected.phase, .disconnected)
    }

    func testAVGeneratedLifecycles() async throws {
        let writer = WriterModel.Machine()
        _ = try await writer.apply(.start)
        _ = try await writer.apply(.write)
        _ = try await writer.apply(.pause)
        _ = try await writer.apply(.resume)
        _ = try await writer.apply(.finish)
        let finishedWriter = await writer.state
        XCTAssertEqual(finishedWriter.phase, .finished)

        let player = PlayerModel.Machine()
        _ = try await player.apply(.beginLoad)
        _ = try await player.apply(.ready)
        _ = try await player.apply(.play)
        _ = try await player.apply(.pause)
        _ = try await player.apply(.seek)
        _ = try await player.apply(.play)
        _ = try await player.apply(.finish)
        let finishedPlayer = await player.state
        XCTAssertEqual(finishedPlayer.phase, .finished)

        let pipeline = MediaPipelineModel.Machine()
        _ = try await pipeline.apply(.beginCapture)
        _ = try await pipeline.apply(.beginWriting)
        _ = try await pipeline.apply(.finishWriting)
        _ = try await pipeline.apply(.play)
        _ = try await pipeline.apply(.stop)
        let idlePipeline = await pipeline.state
        XCTAssertEqual(idlePipeline.stage, .idle)

        let diskStore = DiskStoreModel.Machine()
        _ = try await diskStore.apply(.write)
        _ = try await diskStore.apply(.delete)
        _ = try await diskStore.apply(.clear)
        let readyDiskStore = await diskStore.state
        XCTAssertEqual(readyDiskStore.phase, .ready)
    }
}
