import CoreBluetooth
import Foundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct PeripheralModel {
    public enum Phase: String, CaseIterable, FiniteDomainKey {
        case disconnected, connected, discovering, ready
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.bluetooth.peripheral-phase")
        public var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum ConnectProcess: String, FiniteDomainKey { case connectEvent
        static let formalDomain: [Self] = [.connectEvent]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.bluetooth.peripheral-connect")
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum BeginDiscoveryProcess: String, FiniteDomainKey { case beginDiscoveryEvent
        static let formalDomain: [Self] = [.beginDiscoveryEvent]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.bluetooth.peripheral-begin-discovery")
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum FinishDiscoveryProcess: String, FiniteDomainKey { case finishDiscoveryEvent
        static let formalDomain: [Self] = [.finishDiscoveryEvent]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.bluetooth.peripheral-finish-discovery")
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum DisconnectProcess: String, FiniteDomainKey { case disconnectEvent
        static let formalDomain: [Self] = [.disconnectEvent]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.bluetooth.peripheral-disconnect")
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum Step: String, PlusCalLabel { case connected, beginDiscovery, finishDiscovery, disconnect }

    public static var spec: TLASpec {
        #spec("PeripheralModel") {
            Algorithm("PeripheralModel") {
                let phase = SharedVar(initial: Phase.disconnected)
                Each(ConnectProcess.all) { _ in
                    Do(Step.connected) {
                        When(phase == .disconnected)
                        Assign(phase, to: Phase.connected)
                        Goto(Step.connected)
                    }
                }
                Each(BeginDiscoveryProcess.all) { _ in Do(Step.beginDiscovery) { When(phase == .connected); Assign(phase, to: Phase.discovering); Goto(Step.beginDiscovery) } }
                Each(FinishDiscoveryProcess.all) { _ in Do(Step.finishDiscovery) { When(phase == .discovering); Assign(phase, to: Phase.ready); Goto(Step.finishDiscovery) } }
                Each(DisconnectProcess.all) { _ in Do(Step.disconnect) { When(phase == .ready); Assign(phase, to: Phase.disconnected); Goto(Step.disconnect) } }
                Invariant("knownPeripheralPhase") { phase == .disconnected || phase == .connected || phase == .discovering || phase == .ready }
            }
        }
    }

    @TLAActor public actor Machine {}
}

private final class DeviceDelegate: NSObject, CBPeripheralDelegate {
    weak var owner: Device?
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        Task { await owner?.finishedDiscoveringServices(error) }
    }
}

/// UUID identity and CoreBluetooth callbacks live here. The formal lifecycle
/// lives exclusively in the generated `PeripheralModel.Machine`.
public actor Device: Identifiable {
    public nonisolated let id: UUID
    private let peripheral: CBPeripheral?
    private let delegate = DeviceDelegate()
    private let machine = PeripheralModel.Machine()
    private var servicesContinuation: CheckedContinuation<[CBService], Error>?

    init(peripheral: CBPeripheral) {
        id = peripheral.identifier
        self.peripheral = peripheral
        peripheral.delegate = delegate
        delegate.owner = self
    }

    public var name: String? { peripheral?.name }

    func connected() async {
        _ = try? await machine.execute(PeripheralModel.Machine.ActionLabel.connected.toInvocation())
    }

    public func discoverServices(_ uuids: [CBUUID]? = nil) async throws -> [CBService] {
        guard let peripheral, await machine.state.phase == .connected else { throw BleError.notReady }
        _ = try await machine.execute(PeripheralModel.Machine.ActionLabel.beginDiscovery.toInvocation())
        return try await withCheckedThrowingContinuation { servicesContinuation = $0; peripheral.discoverServices(uuids) }
    }

    func finishedDiscoveringServices(_ error: (any Error)?) async {
        _ = try? await machine.execute(PeripheralModel.Machine.ActionLabel.finishDiscovery.toInvocation())
        if let error { servicesContinuation?.resume(throwing: error) }
        else { servicesContinuation?.resume(returning: peripheral?.services ?? []) }
        servicesContinuation = nil
    }
}
