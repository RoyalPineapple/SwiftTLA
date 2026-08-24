import SwiftUI
import Bluetooth
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

                if let diagnostic = model.diagnostic {
                    Text(diagnostic)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
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
    @Published var diagnostic: String?
    private var ble: Bluetooth?
    private var scanTask: Task<Void, Never>?
    private var seen = Set<UUID>()

    func ready() async {
        do {
            try await bluetooth().ready()
            diagnostic = nil
        } catch {
            diagnostic = "Bluetooth setup failed: \(error)"
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
        let stream: AsyncStream<Device>
        do {
            stream = try await bluetooth().scan()
            isScanning = true
            diagnostic = nil
        } catch {
            diagnostic = "Bluetooth scan failed: \(error)"
            return
        }
        scanTask = Task { [weak self] in
            for await device in stream {
                guard let self else { return }
                let id = device.id
                guard seen.insert(id).inserted else { continue }
                let name = await device.name ?? "Unknown"
                let item = DiscoveredDevice(id: id.uuidString, name: name, identifier: id)
                devices.append(item)
            }
        }
    }

    private func stopScanning() async {
        do {
            if let ble {
                try await ble.stopScanning()
            }
            diagnostic = nil
        } catch {
            diagnostic = "Bluetooth scan could not stop: \(error)"
            return
        }
        scanTask?.cancel()
        isScanning = false
    }

    private func bluetooth() throws -> Bluetooth {
        if let ble { return ble }
        let ble = try Bluetooth()
        self.ble = ble
        return ble
    }
}
