import SwiftUI
import ApplePlatformBluetooth
import CoreBluetooth

@main
struct BLEScannerApp: App {
    @StateObject private var model = BLEModel()

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                List(model.devices) { device in
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

                HStack {
                    Button(model.isScanning ? "Stop" : "Scan") {
                        Task { await model.toggleScan() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.isScanning ? .red : .accentColor)

                    Spacer()

                    Text("\(model.devices.count) device(s)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding()
            }
            .frame(minWidth: 400, minHeight: 300)
            .task { await model.ready() }
        }
    }
}

struct DiscoveredDevice: Identifiable {
    let id: String
    let name: String
    let identifier: UUID
}

@MainActor
final class BLEModel: ObservableObject {
    @Published var devices: [DiscoveredDevice] = []
    @Published var isScanning = false
    private let ble = Bluetooth()
    private var scanTask: Task<Void, Never>?
    private var seen = Set<UUID>()

    func ready() async {
        do {
            try await ble.ready()
            print("BLE ready")
        } catch {
            print("BLE ready error: \(error)")
        }
    }

    func toggleScan() async {
        if isScanning {
            await stopScanning()
        } else {
            await startScanning()
        }
    }

    private func startScanning() async {
        isScanning = true
        let stream = await ble.scan()
        scanTask = Task { [weak self] in
            for await device in stream {
                guard let self else { return }
                let peripheral = await device.peripheral
                let id = peripheral.identifier
                guard seen.insert(id).inserted else { continue }
                let name = peripheral.name ?? "Unknown"
                let item = DiscoveredDevice(id: id.uuidString, name: name, identifier: id)
                devices.append(item)
            }
        }
    }

    private func stopScanning() async {
        await ble.stopScanning()
        scanTask?.cancel()
        isScanning = false
    }
}
