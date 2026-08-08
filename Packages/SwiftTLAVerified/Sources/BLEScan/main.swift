import SwiftTLAVerified
import Foundation

@main
struct BLEScanner {
    static func main() async throws {
        let ble = Bluetooth()
        print("Bluetooth (@TLAActor, proven at compile time)")

        Task {
            // Keep run loop alive so CoreBluetooth callbacks fire
            RunLoop.current.run()
        }

        print("Waiting for powered on...")
        try await ble.ready()
        print("Ready! Scanning for 10 seconds...\n")

        var count = 0
        let stream = await ble.scan()
        let task = Task {
            for await device in stream {
                count += 1
                print("[\(count)] \(await device.name ?? "Unknown")")
            }
        }

        try await Task.sleep(for: .seconds(10))
        await ble.stopScanning()
        task.cancel()
        print("\nDone. Found \(count) device(s).")
        exit(0)
    }
}
