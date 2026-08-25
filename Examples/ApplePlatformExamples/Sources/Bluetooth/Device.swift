import CoreBluetooth
import Foundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct PeripheralModel {
    public enum Phase: String, CaseIterable, FiniteTLAValueDomain {
        case disconnected, connected, discovering, ready
        public static var defaultValue: Self { .disconnected }
        public static let finiteValues = allCases
        public var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum ConnectProcess: String, FiniteTLAValueDomain { case connectEvent
        static var defaultValue: Self { .connectEvent }
        static let finiteValues: [Self] = [.connectEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum BeginDiscoveryProcess: String, FiniteTLAValueDomain { case beginDiscoveryEvent
        static var defaultValue: Self { .beginDiscoveryEvent }
        static let finiteValues: [Self] = [.beginDiscoveryEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum FinishDiscoveryProcess: String, FiniteTLAValueDomain { case finishDiscoveryEvent
        static var defaultValue: Self { .finishDiscoveryEvent }
        static let finiteValues: [Self] = [.finishDiscoveryEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum DiscoveryFailedProcess: String, FiniteTLAValueDomain { case discoveryFailedEvent
        static var defaultValue: Self { .discoveryFailedEvent }
        static let finiteValues: [Self] = [.discoveryFailedEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum DisconnectProcess: String, FiniteTLAValueDomain { case disconnectEvent
        static var defaultValue: Self { .disconnectEvent }
        static let finiteValues: [Self] = [.disconnectEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum Step: String, CaseIterable { case connected, beginDiscovery, finishDiscovery, discoveryFailed, disconnect }

    public static var spec: TLASpec {
        #spec("PeripheralModel") {
            Algorithm("PeripheralModel", scoped: { scope in
                let phase = scope.sharedVar("phase", initial: Phase.disconnected)
                Each(ConnectProcess.all) { _ in
                    Do(Step.connected) {
                        When(phase == .disconnected)
                        Assign(phase, to: Phase.connected)
                        Goto(Step.connected)
                    }
                }
                Each(BeginDiscoveryProcess.all) { _ in Do(Step.beginDiscovery) { When(phase == .connected); Assign(phase, to: Phase.discovering); Goto(Step.beginDiscovery) } }
                Each(FinishDiscoveryProcess.all) { _ in Do(Step.finishDiscovery) { When(phase == .discovering); Assign(phase, to: Phase.ready); Goto(Step.finishDiscovery) } }
                Each(DiscoveryFailedProcess.all) { _ in Do(Step.discoveryFailed) { When(phase == .discovering); Assign(phase, to: Phase.connected); Goto(Step.discoveryFailed) } }
                Each(DisconnectProcess.all) { _ in Do(Step.disconnect) { When(phase == .ready); Assign(phase, to: Phase.disconnected); Goto(Step.disconnect) } }
                Invariant("knownPeripheralPhase") { phase == .disconnected || phase == .connected || phase == .discovering || phase == .ready }
            })
        }
    }

}

private final class DeviceDelegate: NSObject, CBPeripheralDelegate {
    weak var owner: Device?
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        Task { await owner?.finishedDiscoveringServices(error) }
    }
}

/// UUID identity and CoreBluetooth callbacks live here. The formal lifecycle
/// lives exclusively in the generated `PeripheralModel` value.
public actor Device: Identifiable {
    public nonisolated let id: UUID
    private let peripheral: CBPeripheral?
    private let delegate = DeviceDelegate()
    private var machine: PeripheralModel
    private var servicesContinuation: CheckedContinuation<[CBService], Error>?

    init(peripheral: CBPeripheral) throws {
        id = peripheral.identifier
        self.peripheral = peripheral
        machine = try PeripheralModel.makeMachine()
        peripheral.delegate = delegate
        delegate.owner = self
    }

    public var name: String? { peripheral?.name }
    public var state: PeripheralModel.State { machine.state }

    func connected() async throws {
        _ = try machine.send(.connected)
    }

    public func discoverServices(_ uuids: [CBUUID]? = nil) async throws -> [CBService] {
        guard let peripheral, machine.state.phase == .connected else { throw BleError.notReady }
        _ = try machine.send(.beginDiscovery)
        return try await withCheckedThrowingContinuation { servicesContinuation = $0; peripheral.discoverServices(uuids) }
    }

    func finishedDiscoveringServices(_ error: (any Error)?) async {
        do {
            if let error {
                _ = try machine.send(.discoveryFailed)
                servicesContinuation?.resume(throwing: error)
            } else {
                _ = try machine.send(.finishDiscovery)
                servicesContinuation?.resume(returning: peripheral?.services ?? [])
            }
        } catch {
            servicesContinuation?.resume(throwing: error)
        }
        servicesContinuation = nil
    }
}
