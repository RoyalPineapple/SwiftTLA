import Bluetooth
import Foundation

@main
struct BluetoothCLI {
    static func main() async {
        let duration = scanDuration(arguments: Array(CommandLine.arguments.dropFirst()))
        let central = Bluetooth()

        do {
            try await central.ready()
        } catch {
            writeError("Bluetooth did not become ready: \(error)")
            return
        }

        print("Scanning for \(duration) seconds. Press Control-C to stop.")
        let devices = await central.scan()
        let printer = Task {
            for await device in devices {
                let name = await device.name ?? "Unnamed peripheral"
                print("\(device.id.uuidString)  \(name)")
            }
        }

        do {
            try await Task.sleep(for: .seconds(duration))
        } catch {
            // Task cancellation is equivalent to stopping the scan.
        }

        await central.stopScanning()
        printer.cancel()
    }

    private static func scanDuration(arguments: [String]) -> Double {
        guard let secondsIndex = arguments.firstIndex(of: "--seconds"),
              arguments.indices.contains(secondsIndex + 1),
              let seconds = Double(arguments[secondsIndex + 1]),
              seconds > 0
        else {
            return 10
        }
        return seconds
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
