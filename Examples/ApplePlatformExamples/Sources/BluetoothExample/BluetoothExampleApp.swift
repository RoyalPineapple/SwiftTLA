import SwiftUI
import Bluetooth
import CoreBluetooth
import Observation

@main
struct BLEScannerApp: App {
    @State private var effects = BluetoothEffects()
    @State private var machine: BluetoothModel?

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                List(effects.devices) { device in
                    HStack {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                        Text(device.name)
                            .font(.body)
                        Spacer()
                        Text(device.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospaced()
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                }

                if let diagnostic = effects.diagnostic {
                    Text(diagnostic)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                HStack {
                    Button(scanAction == .stopScan ? "Stop" : "Scan") {
                        toggleScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(scanAction == .stopScan ? .red : .accentColor)
                    .disabled(scanAction == nil)

                    Spacer()

                    Text("\(effects.devices.count) device(s)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding()
            }
            .frame(minWidth: 400, minHeight: 300)
            .task {
                guard machine == nil else { return }
                do {
                    machine = try BluetoothModel.makeMachine()
                    effects.eventReceived = { action in _ = send(action) }
                } catch {
                    effects.diagnostic = "Bluetooth workflow failed to initialize: \(error)"
                }
            }
        }
    }

    private var scanAction: BluetoothModel.Action? {
        guard let machine, let actions = try? machine.enabledActions() else { return nil }
        if actions.contains(.stopScan) { return .stopScan }
        if actions.contains(.startScan) { return .startScan }
        return nil
    }

    private func send(_ action: BluetoothModel.Action) -> Bool {
        guard var machine else {
            effects.diagnostic = "Bluetooth workflow did not initialize."
            return false
        }
        do {
            _ = try machine.send(action)
            self.machine = machine
            effects.diagnostic = nil
            return true
        } catch {
            effects.diagnostic = String(describing: error)
            return false
        }
    }

    private func toggleScan() {
        guard let scanAction, send(scanAction) else { return }
        switch scanAction {
        case .stopScan:
            effects.stopScanning()
        case .startScan:
            effects.startScanning()
        default:
            return
        }
    }
}

struct DiscoveredDevice: Identifiable {
    let id: String
    let name: String
    let identifier: UUID
}

@MainActor
@Observable
final class BluetoothEffects {
    var devices: [DiscoveredDevice] = []
    var diagnostic: String?
    var eventReceived: ((BluetoothModel.Action) -> Void)? {
        didSet { report(central.state) }
    }

    private let delegate: BLEDelegate
    private let central: CBCentralManager
    private var seen = Set<UUID>()

    init() {
        let delegate = BLEDelegate()
        self.delegate = delegate
        central = CBCentralManager(delegate: delegate, queue: nil)
        delegate.owner = self
    }

    func startScanning() {
        central.scanForPeripherals(withServices: nil)
        diagnostic = nil
    }

    func stopScanning() {
        central.stopScan()
        diagnostic = nil
    }

    fileprivate func report(_ state: CBManagerState) {
        if let action = BluetoothModel.Action(managerState: state) { eventReceived?(action) }
    }

    fileprivate func discovered(_ peripheral: CBPeripheral) {
        guard seen.insert(peripheral.identifier).inserted else { return }
        devices.append(.init(
            id: peripheral.identifier.uuidString,
            name: peripheral.name ?? "Unknown",
            identifier: peripheral.identifier
        ))
    }
}

private final class BLEDelegate: NSObject, CBCentralManagerDelegate {
    weak var owner: BluetoothEffects?

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in owner?.report(central.state) }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        Task { @MainActor in owner?.discovered(peripheral) }
    }
}
