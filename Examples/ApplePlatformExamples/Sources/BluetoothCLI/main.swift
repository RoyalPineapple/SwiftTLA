import Bluetooth
import Foundation

@main
struct BluetoothCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--verify") {
            do {
                try BluetoothModel.verifySpec()
                try PeripheralModel.verifySpec()
                let central = BluetoothModel.Machine()
                _ = try await central.apply(.poweredOn)
                _ = try await central.apply(.startScan)
                _ = try await central.apply(.stopScan)
                let peripheral = PeripheralModel.Machine()
                _ = try await peripheral.apply(.connected)
                _ = try await peripheral.apply(.beginDiscovery)
                _ = try await peripheral.apply(.finishDiscovery)
                print("Bluetooth formal checks passed.")
                print("central: \(await central.state.phase.rawValue)")
                print("peripheral: \(await peripheral.state.phase.rawValue)")
            } catch {
                writeError("Bluetooth validation failed: \(error)")
            }
            return
        }

        let duration = scanDuration(arguments: arguments)
        let central = Bluetooth()

        do {
            try await central.ready()
        } catch {
            writeError("Bluetooth did not become ready: \(error)")
            return
        }

        print("Scanning for \(duration) seconds. Press Control-C to stop.")
        let devices: AsyncStream<Device>
        do {
            devices = try await central.scan()
        } catch {
            writeError("Bluetooth scan could not start: \(error)")
            return
        }
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
