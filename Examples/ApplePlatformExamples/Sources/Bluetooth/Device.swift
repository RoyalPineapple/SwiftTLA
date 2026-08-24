import CoreBluetooth
import Foundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct PeripheralModel {
    public enum Phase: String, CaseIterable {
        case disconnected, connected, discovering, ready
    }

    public func discoverServices(_ uuids: [CBUUID]? = nil) async throws -> [CBService] {
        guard let peripheral, await machine.state.phase == .connected else { throw BleError.notReady }
        _ = try await machine.send(.beginDiscovery)
        return try await withCheckedThrowingContinuation { servicesContinuation = $0; peripheral.discoverServices(uuids) }
    }

    func finishedDiscoveringServices(_ error: (any Error)?) async {
        _ = try? await machine.send(.finishDiscovery)
        if let error { servicesContinuation?.resume(throwing: error) }
        else { servicesContinuation?.resume(returning: peripheral?.services ?? []) }
        servicesContinuation = nil
    }
}
