import AVPipeline
import Bluetooth
import XCTest

final class GeneratedAppleModelTests: XCTestCase {
    func testBluetoothModelsVerify() throws {
        try BluetoothModel.verifySpec()
        try PeripheralModel.verifySpec()
    }

    func testAVPipelineModelsVerify() throws {
        try CaptureModel.verifySpec()
        try WriterModel.verifySpec()
        try PlayerModel.verifySpec()
        try DiskStoreModel.verifySpec()
        try MediaPipelineModel.verifySpec()
    }

    func testCaptureGeneratedLifecycle() async throws {
        let machine = CaptureModel.Machine()
        _ = try await machine.execute(CaptureModel.Machine.ActionLabel.configure.toInvocation())
        let configured = await machine.state
        XCTAssertEqual(configured.phase, .configured)
        _ = try await machine.execute(CaptureModel.Machine.ActionLabel.start.toInvocation())
        let running = await machine.state
        XCTAssertEqual(running.phase, .running)
        _ = try await machine.execute(CaptureModel.Machine.ActionLabel.stop.toInvocation())
        let idle = await machine.state
        XCTAssertEqual(idle.phase, .idle)
    }

    func testBluetoothGeneratedLifecycle() async throws {
        let machine = BluetoothModel.Machine()
        _ = try await machine.execute(BluetoothModel.Machine.ActionLabel.poweredOn.toInvocation())
        _ = try await machine.execute(BluetoothModel.Machine.ActionLabel.startScan.toInvocation())
        let scanning = await machine.state
        XCTAssertEqual(scanning.phase, .scanning)
        _ = try await machine.execute(BluetoothModel.Machine.ActionLabel.stopScan.toInvocation())
        let poweredOn = await machine.state
        XCTAssertEqual(poweredOn.phase, .poweredOn)
    }

    func testPeripheralGeneratedLifecycle() async throws {
        let machine = PeripheralModel.Machine()
        _ = try await machine.execute(PeripheralModel.Machine.ActionLabel.connected.toInvocation())
        _ = try await machine.execute(PeripheralModel.Machine.ActionLabel.beginDiscovery.toInvocation())
        _ = try await machine.execute(PeripheralModel.Machine.ActionLabel.finishDiscovery.toInvocation())
        let ready = await machine.state
        XCTAssertEqual(ready.phase, .ready)
        _ = try await machine.execute(PeripheralModel.Machine.ActionLabel.disconnect.toInvocation())
        let disconnected = await machine.state
        XCTAssertEqual(disconnected.phase, .disconnected)
    }

    func testAVGeneratedLifecycles() async throws {
        let writer = WriterModel.Machine()
        _ = try await writer.execute(WriterModel.Machine.ActionLabel.start.toInvocation())
        _ = try await writer.execute(WriterModel.Machine.ActionLabel.write.toInvocation())
        _ = try await writer.execute(WriterModel.Machine.ActionLabel.pause.toInvocation())
        _ = try await writer.execute(WriterModel.Machine.ActionLabel.resume.toInvocation())
        _ = try await writer.execute(WriterModel.Machine.ActionLabel.finish.toInvocation())
        let finishedWriter = await writer.state
        XCTAssertEqual(finishedWriter.phase, .finished)

        let player = PlayerModel.Machine()
        _ = try await player.execute(PlayerModel.Machine.ActionLabel.beginLoad.toInvocation())
        _ = try await player.execute(PlayerModel.Machine.ActionLabel.ready.toInvocation())
        _ = try await player.execute(PlayerModel.Machine.ActionLabel.play.toInvocation())
        _ = try await player.execute(PlayerModel.Machine.ActionLabel.pause.toInvocation())
        _ = try await player.execute(PlayerModel.Machine.ActionLabel.seek.toInvocation())
        _ = try await player.execute(PlayerModel.Machine.ActionLabel.play.toInvocation())
        _ = try await player.execute(PlayerModel.Machine.ActionLabel.finish.toInvocation())
        let finishedPlayer = await player.state
        XCTAssertEqual(finishedPlayer.phase, .finished)

        let pipeline = MediaPipelineModel.Machine()
        _ = try await pipeline.execute(MediaPipelineModel.Machine.ActionLabel.beginCapture.toInvocation())
        _ = try await pipeline.execute(MediaPipelineModel.Machine.ActionLabel.beginWriting.toInvocation())
        _ = try await pipeline.execute(MediaPipelineModel.Machine.ActionLabel.finishWriting.toInvocation())
        _ = try await pipeline.execute(MediaPipelineModel.Machine.ActionLabel.play.toInvocation())
        _ = try await pipeline.execute(MediaPipelineModel.Machine.ActionLabel.stop.toInvocation())
        let idlePipeline = await pipeline.state
        XCTAssertEqual(idlePipeline.stage, .idle)

        let diskStore = DiskStoreModel.Machine()
        _ = try await diskStore.execute(DiskStoreModel.Machine.ActionLabel.write.toInvocation())
        _ = try await diskStore.execute(DiskStoreModel.Machine.ActionLabel.delete.toInvocation())
        _ = try await diskStore.execute(DiskStoreModel.Machine.ActionLabel.clear.toInvocation())
        let readyDiskStore = await diskStore.state
        XCTAssertEqual(readyDiskStore.phase, .ready)
    }
}
