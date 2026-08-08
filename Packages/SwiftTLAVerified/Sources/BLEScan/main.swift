import SwiftTLAVerified
import Foundation

@main
struct BLEScanner {
    static func main() async throws {
        let ble = Bluetooth()
        print("Bluetooth (@TLAActor, proven at compile time)")

        Task { RunLoop.current.run() }

        try await ble.ready()
        print("Ready! Scanning for 10 seconds...\n")

        var seen = Set<UUID>()
        var count = 0
        let stream = await ble.scan()
        let task = Task {
            for await device in stream {
                let id = await device.peripheral.identifier
                if seen.insert(id).inserted {
                    count += 1
                    print("[\(count)] \(await device.name ?? "Unknown")")
                }
            }
        }

        try await Task.sleep(for: .seconds(10))
        await ble.stopScanning()
        task.cancel()
        print("\nDone. \(count) unique device(s).")
        exit(0)
    }
}
