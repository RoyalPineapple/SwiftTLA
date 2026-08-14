import Foundation
import Testing
import SwiftTLA
@testable import SwiftTLADemos

struct BluetoothDeviceCoordinatorDemoTests {
    @Test("generated registry accepts more live devices than its TLC scope")
    func coordinatesArbitraryLivePopulation() throws {
        var model = BluetoothDeviceCoordinator()

        try BluetoothDeviceCoordinator.verifySpec()
        try BluetoothDeviceCoordinator.verifyTransitions()
        try BluetoothDeviceCoordinator.verifyInvariants()

        let devices = (0..<7).map { _ in BluetoothDeviceCoordinator.Device() }
        for device in devices {
            model.devicePhases.insert(device)
        }

        let target = try #require(devices.first)
        _ = try model.beginConnect(id: target.id)
        _ = try model.finishConnect(id: target.id)
        _ = try model.beginServiceDiscovery(id: target.id)
        _ = try model.finishServiceDiscovery(id: target.id)

        #expect(model.devicePhases.count == 7)
        #expect(model.devicePhases[target.id] == .ready)
        #expect(BluetoothDeviceCoordinator.symmetricCollectionScopes == [
            SymmetricCollectionScope(collectionName: "devicePhases", verificationScope: 4)
        ])
    }
}
