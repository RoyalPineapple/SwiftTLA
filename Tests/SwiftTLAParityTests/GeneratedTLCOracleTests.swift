import Foundation
import Testing
import SwiftTLA
import UpstreamParity

struct GeneratedTLCOracleTests {
    @Test("cached TLC evidence is bound to its scenario and exploration limit")
    func cacheKeyRejectsDifferentScenarioOrLimit() throws {
        let selected = try #require(modelValidationScenarios().first)
        let pin = try testReferencePin()
        let baseline = try GeneratedTLCOracle.cacheKey(
            scenario: selected.scenario, id: selected.id, maximumStates: 100, pin: pin)
        #expect(baseline == (try GeneratedTLCOracle.cacheKey(
            scenario: selected.scenario, id: selected.id, maximumStates: 100, pin: pin)))
        #expect(baseline != (try GeneratedTLCOracle.cacheKey(
            scenario: selected.scenario, id: selected.id, maximumStates: 101, pin: pin)))
        #expect(baseline != (try GeneratedTLCOracle.cacheKey(
            scenario: selected.scenario, id: "another-case", maximumStates: 100, pin: pin)))
    }

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
