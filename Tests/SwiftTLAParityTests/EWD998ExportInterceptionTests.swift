import Foundation
import Testing
@testable import UpstreamParity

struct EWD998ExportInterceptionTests {
    @Test("the pinned export POST is captured locally and no other request is accepted")
    func interceptsExternalPost() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: output) }
        let interceptor = try EWD998ChanIDExportReference.stageCurlInterceptor(in: output)
        let environment = [
            "PATH": interceptor.executable.deletingLastPathComponent().path,
            "SWIFTTLA_BLOCKED_POST_PAYLOAD": interceptor.payload.path
        ]
        func invoke(_ url: String) throws -> TLCProcessResult {
            try executeProcess(executable: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["curl", "-H", "Content-Type:application/json", "-X", "POST",
                    "-d", "{\"trace\":1}", url],
                directory: output, timeout: 5, environment: environment)
        }
        #expect(try invoke("https://example.invalid/post").status == 64)
        #expect(!FileManager.default.fileExists(atPath: interceptor.payload.path))
        let result = try invoke("https://postman-echo.com/post")
        #expect(result.status == 0)
        #expect(result.stdout == "{\"networkBlocked\":true}")
        #expect(try Data(contentsOf: interceptor.payload) == Data("{\"trace\":1}".utf8))
        #expect(try invoke("https://postman-echo.com/post").status == 64)
    }
}
