import SwiftTLAVerified
import Foundation

@main
struct CameraScanner {
    static func main() async throws {
        let camera = Camera()
        print("Camera (@TLAActor, proven at compile time)")

        Task { RunLoop.current.run() }

        let devices = await camera.devices
        guard let device = devices.first else {
            print("No camera found.")
            exit(1)
        }

        print("Using: \(device.localizedName)")
        print("Configuring...")
        try await camera.configure(device: device)

        print("Starting...")
        try await camera.start()
        print("Running. Taking photo...")

        let data = try await camera.capturePhoto()
        print("Photo captured: \(data.count) bytes")

        await camera.stop()
        print("Stopped.")
        exit(0)
    }
}
