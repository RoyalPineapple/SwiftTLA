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

        var failedDiscovery = try PeripheralModel.makeMachine()
        _ = try failedDiscovery.send(.connected)
        _ = try failedDiscovery.send(.beginDiscovery)
        _ = try failedDiscovery.send(.discoveryFailed)
        XCTAssertEqual(failedDiscovery.state.phase, .connected)
    }

    func testDiskStoreGeneratedLifecycle() async throws {
        var diskStore = try DiskStoreModel.makeMachine()
        _ = try diskStore.send(.write)
        _ = try diskStore.send(.delete)
        _ = try diskStore.send(.clear)
        let readyDiskStore = diskStore.state
        XCTAssertEqual(readyDiskStore.phase, .ready)
    }
}
