import SwiftUI
import Bluetooth
import Observation

@main
struct BLEScannerApp: App {
    @State private var model = BluetoothScreenModel()

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
                    Button(model.scanAction == .stopScan ? "Stop" : "Scan") {
                        model.toggleScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.scanAction == .stopScan ? .red : .accentColor)
                    .disabled(model.scanAction == nil)

                    Spacer()

                    Text("\(model.devices.count) device(s)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding()
            }
            .frame(minWidth: 400, minHeight: 300)
            .task {
                await model.start()
            }
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
final class BluetoothScreenModel {
    var devices: [DiscoveredDevice] = []
    var diagnostic: String?
    private(set) var state: BluetoothModel.State?
    private(set) var scanAction: BluetoothModel.Action?

    private var bluetooth: Bluetooth?
    private var stateTask: Task<Void, Never>?
    private var devicesTask: Task<Void, Never>?

    func start() async {
        guard bluetooth == nil else { return }
        do {
            let bluetooth = try Bluetooth()
            self.bluetooth = bluetooth
            observeState(from: bluetooth)
        } catch {
            diagnostic = "Bluetooth workflow failed to initialize: \(error)"
        }
    }

    func toggleScan() {
        guard let bluetooth, let scanAction else { return }
        Task { [weak self, bluetooth] in
            do {
                if scanAction == .startScan {
                    let stream = try await bluetooth.scan()
                    self?.observeDevices(from: stream)
                } else {
                    try await bluetooth.stopScanning()
                    self?.devicesTask?.cancel()
                    self?.devicesTask = nil
                }
                self?.diagnostic = nil
            } catch {
                self?.diagnostic = String(describing: error)
            }
        }
    }

    private func observeState(from bluetooth: Bluetooth) {
        stateTask = Task { [weak self, bluetooth] in
            for await nextState in await bluetooth.stateUpdates() {
                guard let self else { return }
                state = nextState
                do {
                    scanAction = try await bluetooth.scanAction()
                } catch {
                    diagnostic = String(describing: error)
                    scanAction = nil
                }
            }
        }
    }

    private func observeDevices(from stream: AsyncStream<Device>) {
        devicesTask?.cancel()
        devicesTask = Task { [weak self] in
            for await device in stream {
                guard let self else { return }
                let id = device.id
                guard !devices.contains(where: { $0.identifier == id }) else { continue }
                let name = await device.name ?? "Unknown"
                devices.append(.init(id: id.uuidString, name: name, identifier: id))
            }
        }
    }
}
