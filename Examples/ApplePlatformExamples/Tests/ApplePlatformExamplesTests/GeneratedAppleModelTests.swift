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
}
