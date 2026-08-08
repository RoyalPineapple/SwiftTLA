import SwiftTLAVerified
import Foundation

@main
struct BLEScanner {
    static func main() async throws {
        let ble = Bluetooth()
        print("Bluetooth (@TLAActor, proven at compile time)")

        Task { RunLoop.current.run() }

        print("Waiting for powered on...")
        try await ble.ready()
        print("Ready! Scanning for 5 seconds...\n")

        // Collect devices for 5 seconds
        var devices: [Device] = []
        let stream = await ble.scan()
        let scanTask = Task {
            for await device in stream { devices.append(device) }
        }
        try await Task.sleep(for: .seconds(5))
        await ble.stopScanning()
        scanTask.cancel()

        // Pick the first named device
        guard let target = devices.first(where: { $0.name != nil }) else {
            print("No named devices found among \(devices.count) total.")
            exit(0)
        }

        print("\nConnecting to: \(target.name ?? "?")")
        try await ble.connect(target)
        print("Connected!")

        print("Discovering services...")
        let services = try await target.discoverServices()
        for svc in services {
            print("  Service: \(svc.uuid)")
        }
        print("Done. \(services.count) service(s).")
        exit(0)
    }
}
