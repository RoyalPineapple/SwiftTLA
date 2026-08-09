import SwiftTLA
import SwiftTLAMacros

public enum ContractActionError: Error, Equatable {
    case actionNotEnabled(String)
}

/// Cross-actor Bluetooth contract with an arbitrary live `Device.ID` population.
///
/// The macro verifies exactly four exchangeable, opaque device-phase model
/// members. Runtime UUIDs route live storage only and never enter the model or
/// TLC artifacts. This bounded check does not prove arbitrary `N`; a
/// locality-checked parametric proof would be separate future work.
@TLAActor
public actor Contract {
    public static let devicePhaseVerificationScope = 4

    public static var spec: TLASpec {
        TLASpec("Contract") {
            let cPhase = Var<Int>("cPhase")
            let devicePhases = SymmetricCollectionVar<Device, Int>("devicePhases")

            Variable(cPhase, 0)
            /// Scope four is the explicit verification reference model, not a
            /// cap on the runtime's identified device population.
            SymmetricCollection(devicePhases, verificationScope: 4, initial: 0)

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

            /// Verification existentially selects an opaque member; generated
            /// runtime methods select one live entry by `Device.ID`, evaluate
            /// the same guard, and update only that entry.
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

            /// These value-only predicates quantify over every scoped opaque
            /// member, expressing collection-wide safety at scope four.
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
