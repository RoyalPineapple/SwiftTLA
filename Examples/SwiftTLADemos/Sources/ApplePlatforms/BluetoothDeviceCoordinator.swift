import Foundation
import SwiftTLA
import SwiftTLAMacros

/// The formal central/peripheral contract.
///
/// TLC checks a symmetric, finite device scope. The generated `devicePhases`
/// registry accepts any number of concrete UUID-backed devices at runtime.
@TLAModel
public struct BluetoothDeviceCoordinator {
    public struct Device: Identifiable, Hashable, Sendable {
        public let id: UUID

        public init(id: UUID = UUID()) {
            self.id = id
        }
    }

    public enum CentralPhase: String, CaseIterable, FiniteDomainKey {
        case poweredOff, poweredOn, scanning, resetting, unsupported, unauthorized

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.bluetooth-device-coordinator.central-phase")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum DevicePhase: String, CaseIterable, FiniteDomainKey {
        case disconnected, connecting, connected, discovering, ready, disconnecting

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.bluetooth-device-coordinator.device-phase")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public static var spec: TLASpec {
        #spec("BluetoothDeviceCoordinator") {
            let central = Var<CentralPhase>("central", .poweredOn)
            Variable(central)

            let devicePhases = SharedCollection(
                Device.self,
                verificationScope: 4,
                initial: DevicePhase.disconnected
            )

            Action("powerOff") {
                central == CentralPhase.poweredOn &&
                    devicePhases.allSatisfy { $0 == .disconnected || $0 == .disconnecting } &&
                    central.becomes(CentralPhase.poweredOff)
            }
            Action("powerOn") {
                (central == CentralPhase.poweredOff || central == CentralPhase.resetting) && central.becomes(CentralPhase.poweredOn)
            }
            Action("reset") {
                (central == CentralPhase.poweredOff || central == CentralPhase.poweredOn) &&
                    devicePhases.allSatisfy { $0 == .disconnected || $0 == .disconnecting } &&
                    central.becomes(CentralPhase.resetting)
            }
            Action("startScan") {
                central == CentralPhase.poweredOn &&
                    devicePhases.allSatisfy { $0 != .connecting } &&
                    central.becomes(.scanning)
            }
            Action("stopScan") { central == CentralPhase.scanning && central.becomes(CentralPhase.poweredOn) }

            CollectionAction("beginConnect", on: devicePhases) { member in
                central == CentralPhase.poweredOn &&
                    devicePhases[member] == .disconnected &&
                    devicePhases.update(member, to: .connecting)
            }
            CollectionAction("finishConnect", on: devicePhases) { member in
                central == CentralPhase.poweredOn &&
                    devicePhases[member] == .connecting &&
                    devicePhases.update(member, to: .connected)
            }
            CollectionAction("beginServiceDiscovery", on: devicePhases) { member in
                central == CentralPhase.poweredOn &&
                    devicePhases[member] == .connected &&
                    devicePhases.update(member, to: .discovering)
            }
            CollectionAction("finishServiceDiscovery", on: devicePhases) { member in
                central == CentralPhase.poweredOn &&
                    devicePhases[member] == .discovering &&
                    devicePhases.update(member, to: .ready)
            }
            CollectionAction("beginDisconnect", on: devicePhases) { member in
                central == CentralPhase.poweredOn &&
                    devicePhases[member] != .disconnected &&
                    devicePhases[member] != .disconnecting &&
                    devicePhases.update(member, to: .disconnecting)
            }
            CollectionAction("finishDisconnect", on: devicePhases) { member in
                devicePhases[member] == .disconnecting &&
                    devicePhases.update(member, to: .disconnected)
            }

            Invariant("PeripheralRequiresPower") {
                devicePhases.allSatisfy {
                    central == CentralPhase.poweredOn || central == CentralPhase.scanning ||
                        $0 == .disconnected || $0 == .disconnecting
                }
            }
            Invariant("NoScanWhileConnecting") {
                devicePhases.allSatisfy { central != CentralPhase.scanning || $0 != .connecting }
            }
        }
    }
}
