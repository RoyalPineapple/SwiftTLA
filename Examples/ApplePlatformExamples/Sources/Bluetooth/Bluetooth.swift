import CoreBluetooth
import SwiftTLA
import SwiftTLAMacros

/// The formal central-manager lifecycle. CoreBluetooth objects do not enter
/// this model; the `Bluetooth` actor below is the framework-facing shim.
@TLAModel
public struct BluetoothModel {
    public enum Phase: String, CaseIterable, FiniteTLAValueDomain {
        case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn, scanning

        public static var defaultValue: Self { .unknown }
        public static let finiteValues = allCases
        public var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum PoweredOnProcess: String, FiniteTLAValueDomain { case poweredOnEvent
        static var defaultValue: Self { .poweredOnEvent }
        static let finiteValues: [Self] = [.poweredOnEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum PoweredOffProcess: String, FiniteTLAValueDomain { case poweredOffEvent
        static var defaultValue: Self { .poweredOffEvent }
        static let finiteValues: [Self] = [.poweredOffEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum StartScanProcess: String, FiniteTLAValueDomain { case startScanEvent
        static var defaultValue: Self { .startScanEvent }
        static let finiteValues: [Self] = [.startScanEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum StopScanProcess: String, FiniteTLAValueDomain { case stopScanEvent
        static var defaultValue: Self { .stopScanEvent }
        static let finiteValues: [Self] = [.stopScanEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum ResettingProcess: String, FiniteTLAValueDomain { case resettingEvent
        static var defaultValue: Self { .resettingEvent }
        static let finiteValues: [Self] = [.resettingEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum UnsupportedProcess: String, FiniteTLAValueDomain { case unsupportedEvent
        static var defaultValue: Self { .unsupportedEvent }
        static let finiteValues: [Self] = [.unsupportedEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum UnauthorizedProcess: String, FiniteTLAValueDomain { case unauthorizedEvent
        static var defaultValue: Self { .unauthorizedEvent }
        static let finiteValues: [Self] = [.unauthorizedEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum Step: String, CaseIterable { case poweredOn, poweredOff, resetting, unsupported, unauthorized, startScan, stopScan }

    public static var spec: TLASpec {
        #spec("BluetoothModel") {
            Algorithm("BluetoothModel", scoped: { scope in
                let phase = scope.sharedVar("phase", initial: Phase.unknown)
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
            })
        }
    }

}

public extension BluetoothModel.Action {
    init?(managerState: CBManagerState) {
        switch managerState {
        case .poweredOn: self = .poweredOn
        case .poweredOff: self = .poweredOff
        case .resetting: self = .resetting
        case .unsupported: self = .unsupported
        case .unauthorized: self = .unauthorized
        default: return nil
        }
    }
}

private final class BleDelegate: NSObject, CBCentralManagerDelegate {
    weak var owner: Bluetooth?
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { await owner?.updateState(central.state) }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        Task {
            do {
                await owner?.didDiscover(try Device(peripheral: peripheral))
            } catch {
                await owner?.record(error)
            }
        }
    }
}

/// A thin CoreBluetooth shim. All lifecycle decisions are made by the
/// generated `BluetoothModel`; this actor only owns framework objects,
/// continuations, and UUID-to-peripheral identity.
public actor Bluetooth {
    private var machine: BluetoothModel
    private let delegate: BleDelegate
    private let central: CBCentralManager
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var scanContinuation: AsyncStream<Device>.Continuation?
    public private(set) var diagnostic: String?

    public init() throws {
        machine = try BluetoothModel.makeMachine()
        let delegate = BleDelegate()
        self.delegate = delegate
        central = CBCentralManager(delegate: delegate, queue: nil)
        delegate.owner = self
    }

    public var state: BluetoothModel.State { machine.state }

    public func ready() async throws {
        if let diagnostic { throw BleError.transitionFailed(diagnostic) }
        if machine.state.phase == .poweredOn { return }
        try await withCheckedThrowingContinuation { readyContinuation = $0 }
    }

    public func scan() async throws -> AsyncStream<Device> {
        if let diagnostic { throw BleError.transitionFailed(diagnostic) }
        guard try machine.isEnabled(.startScan) else { throw BleError.notReady }
        _ = try machine.send(.startScan)
        let stream = AsyncStream<Device>.makeStream()
        scanContinuation = stream.continuation
        central.scanForPeripherals(withServices: nil)
        return stream.stream
    }

    public func stopScanning() async throws {
        if try machine.isEnabled(.stopScan) {
            _ = try machine.send(.stopScan)
        }
        central.stopScan()
        scanContinuation?.finish()
        scanContinuation = nil
    }

    func updateState(_ state: CBManagerState) async {
        if let action = BluetoothModel.Action(managerState: state) {
            do {
                _ = try machine.send(action)
                diagnostic = nil
            } catch {
                record(error)
                return
            }
        }
        if state == .poweredOn, let readyContinuation { readyContinuation.resume(); self.readyContinuation = nil }
        if state != .poweredOn { scanContinuation?.finish(); scanContinuation = nil }
    }

    func didDiscover(_ device: Device) { scanContinuation?.yield(device) }

    func record(_ error: Error) {
        diagnostic = String(describing: error)
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
        scanContinuation?.finish()
        scanContinuation = nil
    }
}

public enum BleError: Error { case notReady, transitionFailed(String) }
