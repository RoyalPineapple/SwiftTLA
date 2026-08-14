import CoreBluetooth
import SwiftTLA
import SwiftTLAMacros

/// The formal central-manager lifecycle. CoreBluetooth objects do not enter
/// this model; the `Bluetooth` actor below is the framework-facing shim.
@TLAModel
public struct BluetoothModel {
    public enum Phase: String, CaseIterable, FiniteDomainKey {
        case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn, scanning

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.bluetooth.central-phase")
        public var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum PoweredOnProcess: String, FiniteDomainKey { case poweredOnEvent
        static let formalDomain: [Self] = [.poweredOnEvent]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.bluetooth.powered-on")
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum PoweredOffProcess: String, FiniteDomainKey { case poweredOffEvent
        static let formalDomain: [Self] = [.poweredOffEvent]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.bluetooth.powered-off")
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum StartScanProcess: String, FiniteDomainKey { case startScanEvent
        static let formalDomain: [Self] = [.startScanEvent]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.bluetooth.start-scan")
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum StopScanProcess: String, FiniteDomainKey { case stopScanEvent
        static let formalDomain: [Self] = [.stopScanEvent]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.bluetooth.stop-scan")
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum ResettingProcess: String, FiniteDomainKey { case resettingEvent
        static let formalDomain: [Self] = [.resettingEvent]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.bluetooth.resetting")
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum UnsupportedProcess: String, FiniteDomainKey { case unsupportedEvent
        static let formalDomain: [Self] = [.unsupportedEvent]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.bluetooth.unsupported")
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum UnauthorizedProcess: String, FiniteDomainKey { case unauthorizedEvent
        static let formalDomain: [Self] = [.unauthorizedEvent]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.bluetooth.unauthorized")
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum Step: String, PlusCalLabel { case poweredOn, poweredOff, resetting, unsupported, unauthorized, startScan, stopScan }

    public static var spec: TLASpec {
        #spec("BluetoothModel") {
            Algorithm("BluetoothModel") {
                let phase = SharedVar(initial: Phase.unknown)
                Each(PoweredOnProcess.all) { _ in
                    Do(Step.poweredOn) {
                        When(phase == .unknown || phase == .resetting || phase == .poweredOff)
                        Assign(phase, to: Phase.poweredOn)
                        Goto(Step.poweredOn)
                    }
                }
                Each(PoweredOffProcess.all) { _ in
                    Do(Step.poweredOff) {
                        When(phase == .unknown || phase == .resetting || phase == .poweredOn || phase == .scanning)
                        Assign(phase, to: Phase.poweredOff)
                        Goto(Step.poweredOff)
                    }
                }
                Each(ResettingProcess.all) { _ in
                    Do(Step.resetting) {
                        When(phase != .resetting)
                        Assign(phase, to: Phase.resetting)
                        Goto(Step.resetting)
                    }
                }
                Each(UnsupportedProcess.all) { _ in
                    Do(Step.unsupported) {
                        When(phase != .unsupported)
                        Assign(phase, to: Phase.unsupported)
                        Goto(Step.unsupported)
                    }
                }
                Each(UnauthorizedProcess.all) { _ in
                    Do(Step.unauthorized) {
                        When(phase != .unauthorized)
                        Assign(phase, to: Phase.unauthorized)
                        Goto(Step.unauthorized)
                    }
                }
                Each(StartScanProcess.all) { _ in
                    Do(Step.startScan) { When(phase == .poweredOn); Assign(phase, to: Phase.scanning); Goto(Step.startScan) }
                }
                Each(StopScanProcess.all) { _ in
                    Do(Step.stopScan) { When(phase == .scanning); Assign(phase, to: Phase.poweredOn); Goto(Step.stopScan) }
                }
                Invariant("knownCentralPhase") { phase == .unknown || phase == .resetting || phase == .unsupported || phase == .unauthorized || phase == .poweredOff || phase == .poweredOn || phase == .scanning }
            }
        }
    }

    @TLAActor public actor Machine {}
}

private final class BleDelegate: NSObject, CBCentralManagerDelegate {
    weak var owner: Bluetooth?
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { await owner?.updateState(central.state) }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        Task { await owner?.didDiscover(Device(peripheral: peripheral)) }
    }
}

/// A thin CoreBluetooth shim. All lifecycle decisions are made by the
/// generated `BluetoothModel.Machine`; this actor only owns framework objects,
/// continuations, and UUID-to-peripheral identity.
public actor Bluetooth {
    private let machine = BluetoothModel.Machine()
    private let delegate = BleDelegate()
    private var central: CBCentralManager!
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var scanContinuation: AsyncStream<Device>.Continuation?

    public init() {
        central = CBCentralManager()
        central.delegate = delegate
        delegate.owner = self
    }

    public func ready() async throws {
        if await machine.state.phase == .poweredOn { return }
        try await withCheckedThrowingContinuation { readyContinuation = $0 }
    }

    public func scan() async throws -> AsyncStream<Device> {
        guard await machine.state.phase == .poweredOn else { throw BleError.notReady }
        _ = try await machine.execute(BluetoothModel.Machine.ActionLabel.startScan.toInvocation())
        let stream = AsyncStream<Device>.makeStream()
        scanContinuation = stream.continuation
        central.scanForPeripherals(withServices: nil)
        return stream.stream
    }

    public func stopScanning() async {
        if await machine.state.phase == .scanning {
            _ = try? await machine.execute(BluetoothModel.Machine.ActionLabel.stopScan.toInvocation())
        }
        central.stopScan()
        scanContinuation?.finish()
        scanContinuation = nil
    }

    func updateState(_ state: CBManagerState) async {
        let action: BluetoothModel.Machine.ActionLabel?
        switch state {
        case .poweredOn: action = .poweredOn
        case .poweredOff: action = .poweredOff
        case .resetting: action = .resetting
        case .unsupported: action = .unsupported
        case .unauthorized: action = .unauthorized
        default: action = nil
        }
        if let action { _ = try? await machine.execute(action.toInvocation()) }
        if state == .poweredOn, let readyContinuation { readyContinuation.resume(); self.readyContinuation = nil }
        if state != .poweredOn { scanContinuation?.finish(); scanContinuation = nil }
    }

    func didDiscover(_ device: Device) { scanContinuation?.yield(device) }
}

public enum BleError: Error { case notReady }
