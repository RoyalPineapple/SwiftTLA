import Foundation
import SwiftTLA
@testable import SwiftTLAVerified
import XCTest

private struct LiveDevice: Identifiable {
    let id: UUID
}

final class ContractSymmetricCollectionTests: XCTestCase {
    func testReferenceScopeDoesNotCapLiveDevicePopulation() throws {
        var devicePhases = IdentifiedModelCollection<LiveDevice, Int>(
            name: "devicePhases",
            verificationScope: Contract.devicePhaseVerificationScope,
            initial: 0
        )

        for _ in 0...Contract.devicePhaseVerificationScope {
            devicePhases.insert(LiveDevice(id: UUID()))
        }

        XCTAssertEqual(devicePhases.count, Contract.devicePhaseVerificationScope + 1)
        XCTAssertEqual(Contract.spec.symmetricCollections.map(\.name), ["devicePhases"])
        XCTAssertFalse(Contract.spec.tlaBundle.tla.contains("UUID"))
    }

    func testConnectionActionRoutesThroughDeviceID() async {
        do {
            try await Contract().connect(id: UUID())
            XCTFail("Unknown IDs must not be accepted by the contract action")
        } catch let error as SymmetricCollectionRuntimeError {
            XCTAssertEqual(
                error,
                .unknownMember(collection: "devicePhases", action: "beginConnect")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLiveRoutingUsesSelectedDeviceBeyondVerificationScope() async throws {
        let contract = Contract()
        let devices = (0...Contract.devicePhaseVerificationScope).map { _ in Device(id: UUID()) }

        for device in devices {
            await contract.register(device, phase: 0)
        }
        await contract.powerOn()

        let selected = devices[Contract.devicePhaseVerificationScope]
        try await contract.connect(id: selected.id)

        let selectedPhase = await contract.devicePhase(id: selected.id)
        XCTAssertEqual(selectedPhase, 1)
        for peer in devices.dropLast() {
            let peerPhase = await contract.devicePhase(id: peer.id)
            XCTAssertEqual(peerPhase, 0)
        }
    }

    func testDeviceTransitionsCheckSelectedEntryAndExposeFullFamily() async throws {
        let contract = Contract()
        let device = Device(id: UUID())
        let wrongPhaseDevice = Device(id: UUID())
        await contract.register(device)
        await contract.register(wrongPhaseDevice, phase: 1)
        await contract.powerOn()

        do {
            try await contract.connect(id: wrongPhaseDevice.id)
            XCTFail("The routed entry's phase must enable the action")
        } catch let error as ContractActionError {
            XCTAssertEqual(error, .actionNotEnabled("beginConnect"))
        }

        try await contract.connect(id: device.id)
        try await contract.failConnection(id: device.id)
        try await contract.connect(id: device.id)
        try await contract.completeConnection(id: device.id)
        try await contract.beginServiceDiscovery(id: device.id)
        try await contract.completeServiceDiscovery(id: device.id)
        try await contract.beginCharacteristicDiscovery(id: device.id)
        try await contract.completeCharacteristicDiscovery(id: device.id)
        try await contract.disconnect(id: device.id)
        try await contract.completeDisconnection(id: device.id)

        let devicePhase = await contract.devicePhase(id: device.id)
        let wrongPhase = await contract.devicePhase(id: wrongPhaseDevice.id)
        XCTAssertEqual(devicePhase, 0)
        XCTAssertEqual(wrongPhase, 1)
    }

    func testBoundedResultReportsExactlyReferenceScope() throws {
        let result = try ModelChecker(spec: Contract.spec).check()

        XCTAssertEqual(result.boundedScopes.map(\.verificationScope), [Contract.devicePhaseVerificationScope])
        XCTAssertTrue(result.description.contains("devicePhases: 4 exchangeable members"))
        XCTAssertTrue(result.description.contains("does not prove larger populations"))
    }
}
