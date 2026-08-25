import SwiftUI
import Bluetooth
import CoreBluetooth
import Observation

@main
struct BLEScannerApp: App {
    @State private var controller = BLEController()
    @State private var machine: BluetoothModel?

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                List(controller.devices) { device in
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

                if let diagnostic = controller.diagnostic {
                    Text(diagnostic)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                HStack {
                    Button(phase == .scanning ? "Stop" : "Scan") {
                        toggleScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(phase == .scanning ? .red : .accentColor)
                    .disabled(phase != .poweredOn && phase != .scanning)

                    Spacer()

                    Text("\(controller.devices.count) device(s)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding()
            }
            .frame(minWidth: 400, minHeight: 300)
            .task {
                do {
                    machine = try BluetoothModel.makeMachine()
                    controller.eventReceived = { action in _ = send(action) }
                } catch {
                    controller.diagnostic = "Bluetooth workflow failed to initialize: \(error)"
                }
            }
        }
    }

    private var phase: BluetoothModel.Phase { machine?.state.phase ?? .unknown }

    private func send(_ action: BluetoothModel.Action) -> Bool {
        guard var machine else {
            controller.diagnostic = "Bluetooth workflow did not initialize."
            return false
        }
        do {
            _ = try machine.send(action)
            self.machine = machine
            controller.diagnostic = nil
            return true
        } catch {
            controller.diagnostic = String(describing: error)
            return false
        }
    }

    private func toggleScan() {
        if phase == .scanning {
            guard send(.stopScan) else { return }
            controller.stopScanning()
        } else if phase == .poweredOn {
            guard send(.startScan) else { return }
            controller.startScanning()
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
final class BLEController {
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
    weak var owner: BLEController?

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
