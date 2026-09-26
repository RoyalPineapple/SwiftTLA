import Foundation
import Testing
import SwiftTLA
import UpstreamParity

struct GeneratedTLCOracleTests {
    @Test("oracle input identity covers configuration, imports, and check mode")
    func inputIdentityCoversCompleteBundle() throws {
        func bundle(configuration: String, imported: String) -> TLAModuleBundle {
            .external(
                root: .init(name: "Root", tla: "---- MODULE Root ----\nEXTENDS Helper\n====", cfg: configuration),
                imports: [.init(name: "Helper", tla: imported)])
        }
        let pin = try testReferencePin()
        let base = try GeneratedTLCOracle.inputIdentity(
            bundle: bundle(configuration: "CHECK_DEADLOCK TRUE", imported: "---- MODULE Helper ----\nX == 1\n===="),
            pin: pin, arguments: ["-workers", "1"])
        let changedConfiguration = try GeneratedTLCOracle.inputIdentity(
            bundle: bundle(configuration: "CHECK_DEADLOCK FALSE", imported: "---- MODULE Helper ----\nX == 1\n===="),
            pin: pin, arguments: ["-workers", "1"])
        let changedImport = try GeneratedTLCOracle.inputIdentity(
            bundle: bundle(configuration: "CHECK_DEADLOCK TRUE", imported: "---- MODULE Helper ----\nX == 2\n===="),
            pin: pin, arguments: ["-workers", "1"])
        let propertyOnly = try GeneratedTLCOracle.inputIdentity(
            bundle: bundle(configuration: "CHECK_DEADLOCK TRUE", imported: "---- MODULE Helper ----\nX == 1\n===="),
            pin: pin, arguments: ["-workers", "1"], invocation: .propertyCheck)
        #expect(base != changedConfiguration)
        #expect(base != changedImport)
        #expect(base != propertyOnly)
    }
}
