import SwiftTLA
import SwiftTLAMacros

public enum ContractActionError: Error, Equatable {
    case actionNotEnabled(String)
}

/// The formal coordination policy for a Bluetooth central and its peripherals.
///
/// `Contract` owns the shared decisions: whether the radio can scan and which
/// lifecycle transition a selected peripheral may take. `Device` actors own
/// the framework callbacks for individual `CBPeripheral` objects. The formal
/// state contains no CoreBluetooth objects; runtime UUIDs select a live entry,
/// while verification uses four exchangeable opaque members.
@TLAActor
public actor Contract {
    public static let devicePhaseVerificationScope = 4

    public static var spec: TLASpec {
        TLASpec("Contract") {
            /// Central-manager phase. The integer names mirror CBManagerState:
            /// 4 is powered off, 5 is powered on, and 6 is scanning.
            let cPhase = Var("cPhase", 0)
            Variable(cPhase)

            /// One lifecycle value per peripheral. Scope four is a finite TLC
            /// reference model, not a cap on runtime UUID-routed devices.
            let devicePhases = DictionaryVar<Device, Int>("devicePhases", scope: 4)
            devicePhases

            /// Central transitions are global: power loss/resetting and scan
            /// changes are legal only when no peripheral is mid-handoff.
            Action("cToPoweredOn") { (cPhase == 0 || cPhase == 1 || cPhase == 4) && cPhase.becomes(5) }
            Action("cToPoweredOff") {
                (cPhase == 0 || cPhase == 1 || cPhase == 5)
                    && devicePhases.allSatisfy { $0 == 0 || $0 == 7 }
                    && cPhase.becomes(4)
            }
            Action("cToUnsupported") { cPhase == 0 && cPhase.becomes(2) }
            Action("cToUnauthorized") { cPhase == 0 && cPhase.becomes(3) }
            Action("cToResetting") {
                (cPhase == 4 || cPhase == 5)
                    && devicePhases.allSatisfy { $0 == 0 || $0 == 7 }
                    && cPhase.becomes(1)
            }
            Action("cStartScan") {
                cPhase == 5
                    && devicePhases.allSatisfy { $0 == 0 || $0 == 7 }
                    && cPhase.becomes(6)
            }
            Action("cStopScan") { cPhase == 6 && cPhase.becomes(5) }

            /// Each action selects exactly one peripheral. TLC chooses an
            /// opaque member; generated runtime methods route the same action
            /// to the entry selected by `Device.ID`.
            ///
            /// 0 disconnected → 1 connecting → 2 connected → 3 discovering
            /// services → 4 services known → 5 discovering characteristics →
            /// 6 ready → 7 disconnecting → 0 disconnected.
            CollectionAction("beginConnect", on: devicePhases) { member in
                cPhase == 5 && devicePhases[member] == 0 && devicePhases.update(member, to: 1)
            }
            CollectionAction("finishConnect", on: devicePhases) { member in
                cPhase == 5 && devicePhases[member] == 1 && devicePhases.update(member, to: 2)
            }
            CollectionAction("failConnect", on: devicePhases) { member in
                cPhase == 5 && devicePhases[member] == 1 && devicePhases.update(member, to: 0)
            }
            CollectionAction("disconnectConnected", on: devicePhases) { member in
                cPhase == 5 && devicePhases[member] == 2 && devicePhases.update(member, to: 7)
            }
            CollectionAction("disconnectServices", on: devicePhases) { member in
                cPhase == 5 && devicePhases[member] == 4 && devicePhases.update(member, to: 7)
            }
            CollectionAction("disconnectCharacteristics", on: devicePhases) { member in
                cPhase == 5 && devicePhases[member] == 6 && devicePhases.update(member, to: 7)
            }
            CollectionAction("finishDisconnect", on: devicePhases) { member in
                devicePhases[member] == 7 && devicePhases.update(member, to: 0)
            }
            CollectionAction("beginDiscover", on: devicePhases) { member in
                cPhase == 5 && devicePhases[member] == 2 && devicePhases.update(member, to: 3)
            }
            CollectionAction("finishDiscover", on: devicePhases) { member in
                cPhase == 5 && devicePhases[member] == 3 && devicePhases.update(member, to: 4)
            }
            CollectionAction("beginDiscoverChars", on: devicePhases) { member in
                cPhase == 5 && devicePhases[member] == 4 && devicePhases.update(member, to: 5)
            }
            CollectionAction("finishDiscoverChars", on: devicePhases) { member in
                cPhase == 5 && devicePhases[member] == 5 && devicePhases.update(member, to: 6)
            }

            /// Every peripheral that is not disconnected or disconnecting
            /// requires a powered-on central. Scanning cannot race connection.
            Invariant("noPeripheralWithoutPower") {
                devicePhases.allSatisfy { (cPhase == 5) || ($0 == 0) || ($0 == 7) }
            }
            Invariant("noScanWhileConnecting") {
                devicePhases.allSatisfy { (cPhase != 6) || ($0 != 1) }
            }
        }
    }

    public func register(_ device: Device, phase: Int = 0) {
        devicePhases.insert(device, value: phase)
    }

    @discardableResult
    public func unregister(id: Device.ID) -> IdentifiedModelCollection<Device, Int>.Entry? {
        devicePhases.remove(id: id)
    }

    public func devicePhase(id: Device.ID) -> Int? {
        devicePhases[id]
    }

    public func powerOn() {
        cToPoweredOn()
    }

    public func connect(id: Device.ID) throws {
        try transition(id: id, action: "beginConnect", from: [0], to: 1)
    }

    public func completeConnection(id: Device.ID) throws {
        try transition(id: id, action: "finishConnect", from: [1], to: 2)
    }

    public func failConnection(id: Device.ID) throws {
        try transition(id: id, action: "failConnect", from: [1], to: 0)
    }

    public func disconnect(id: Device.ID) throws {
        try transition(id: id, action: "disconnect", from: [2, 4, 6], to: 7)
    }

    public func completeDisconnection(id: Device.ID) throws {
        try transition(id: id, action: "finishDisconnect", from: [7], to: 0, requiresPoweredOn: false)
    }

    public func beginServiceDiscovery(id: Device.ID) throws {
        try transition(id: id, action: "beginDiscover", from: [2], to: 3)
    }

    public func completeServiceDiscovery(id: Device.ID) throws {
        try transition(id: id, action: "finishDiscover", from: [3], to: 4)
    }

    public func beginCharacteristicDiscovery(id: Device.ID) throws {
        try transition(id: id, action: "beginDiscoverChars", from: [4], to: 5)
    }

    public func completeCharacteristicDiscovery(id: Device.ID) throws {
        try transition(id: id, action: "finishDiscoverChars", from: [5], to: 6)
    }

    private func transition(
        id: Device.ID,
        action: String,
        from phases: Set<Int>,
        to phase: Int,
        requiresPoweredOn: Bool = true
    ) throws {
        let entry = try devicePhases.entry(for: id, action: action)
        guard !requiresPoweredOn || cPhase == 5, phases.contains(entry.value) else {
            throw ContractActionError.actionNotEnabled(action)
        }
        try devicePhases.update(id: id, to: phase, action: action)
    }
}
