import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity

struct GeneratedTLCOracleTests {
    @Test("expecting an invariant failure does not change TLC inputs or cache identity")
    func expectationsDoNotSelectOracleChecks() throws {
        let original = try #require(ConstantStateClaims.validationScenarios().first)
        var expectations = original.expectations
        expectations[.falseInvariant] = .satisfied
        let changed = ConstantStateClaims.ValidationScenario(
            name: original.name, displayName: original.displayName, configuration: original.configuration,
            checking: original.checking, checkingMode: original.checkingMode, behavior: original.behavior,
            selectedSymmetry: original.selectedSymmetry,
            selectedFairnessProfile: original.selectedFairnessProfile,
            selectedFairnessProfileName: original.selectedFairnessProfileName,
            selectedView: original.selectedView,
            expectations: expectations, deadlockExpectation: original.deadlockExpectation)
        let pin = try testReferencePin()
        let originalKey = try GeneratedTLCOracle.cacheKey(
            scenario: original, id: "constant-state-claims-0", maximumStates: 10, pin: pin)
        let changedKey = try GeneratedTLCOracle.cacheKey(
            scenario: changed, id: "constant-state-claims-0", maximumStates: 10, pin: pin)
        #expect(originalKey == changedKey)
    }

    @Test("decisive stopping changes oracle cache identity without changing model semantics")
    func decisiveModeChangesCacheIdentity() throws {
        let decisive = try #require(DieHardestModel.validationScenarios().first)
        let exhaustive = DieHardestModel.ValidationScenario(
            name: decisive.name, displayName: decisive.displayName, configuration: decisive.configuration,
            checking: decisive.checking, checkingMode: .exhaustive, behavior: decisive.behavior,
            selectedSymmetry: decisive.selectedSymmetry,
            selectedFairnessProfile: decisive.selectedFairnessProfile,
            selectedFairnessProfileName: decisive.selectedFairnessProfileName,
            selectedView: decisive.selectedView,
            expectations: decisive.expectations, deadlockExpectation: decisive.deadlockExpectation)
        let pin = try testReferencePin()
        let decisiveBundle = try decisive.render().tlaBundle
        let exhaustiveBundle = try exhaustive.render().tlaBundle
        #expect(decisiveBundle.tla == exhaustiveBundle.tla)
        #expect(decisiveBundle.cfg == exhaustiveBundle.cfg)
        #expect(try GeneratedTLCOracle.cacheKey(
            scenario: decisive, id: "die-hardest-0", maximumStates: 100_000, pin: pin) !=
            GeneratedTLCOracle.cacheKey(
                scenario: exhaustive, id: "die-hardest-0", maximumStates: 100_000, pin: pin))
    }

    @Test("sampled TLC evidence keys include trace count and maximum depth")
    func simulationLimitsChangeCacheIdentity() throws {
        let configured = try #require(EWD840AnimationModel.validationScenarios().first)
        let pin = try testReferencePin()
        let base = try GeneratedTLCOracle.cacheKey(
            scenario: configured, id: "ewd840-anim-0", maximumStates: 1_000_000, pin: pin)
        let moreTraces = EWD840AnimationModel.ValidationScenario(
            name: configured.name, displayName: configured.displayName,
            configuration: configured.configuration, checking: configured.checking,
            checkingMode: .simulation(traces: 101, maximumDepth: 100),
            behavior: configured.behavior, selectedSymmetry: configured.selectedSymmetry,
            selectedFairnessProfile: configured.selectedFairnessProfile,
            selectedFairnessProfileName: configured.selectedFairnessProfileName,
            selectedView: configured.selectedView,
            expectations: configured.expectations, deadlockExpectation: configured.deadlockExpectation)
        let deeper = EWD840AnimationModel.ValidationScenario(
            name: configured.name, displayName: configured.displayName,
            configuration: configured.configuration, checking: configured.checking,
            checkingMode: .simulation(traces: 100, maximumDepth: 101),
            behavior: configured.behavior, selectedSymmetry: configured.selectedSymmetry,
            selectedFairnessProfile: configured.selectedFairnessProfile,
            selectedFairnessProfileName: configured.selectedFairnessProfileName,
            selectedView: configured.selectedView,
            expectations: configured.expectations, deadlockExpectation: configured.deadlockExpectation)
        #expect(base != (try GeneratedTLCOracle.cacheKey(
            scenario: moreTraces, id: "ewd840-anim-0", maximumStates: 1_000_000, pin: pin)))
        #expect(base != (try GeneratedTLCOracle.cacheKey(
            scenario: deeper, id: "ewd840-anim-0", maximumStates: 1_000_000, pin: pin)))
    }

    @Test("cached TLC evidence is bound to its scenario, exploration limit, and bridge producer")
    func cacheKeyRejectsDifferentScenarioLimitOrProducer() throws {
        let selected = try #require(modelValidationScenarios().first)
        let pin = try testReferencePin()
        let changedPin = try TLCReferencePin(
            tag: pin.tag, commit: pin.commit, jarSHA256: pin.jarSHA256,
            javaDistribution: pin.javaDistribution, javaVersion: pin.javaVersion,
            javaArchiveSHA256: pin.javaArchiveSHA256, bridgeClass: pin.bridgeClass,
            bridgeSourceHashes: pin.bridgeSourceHashes.merging([
                "Tools/TLCGraphBridge/src/org/swifttla/conformance/NewProducer.java":
                    SHA256.hex(Data("new producer".utf8))
            ]) { _, replacement in replacement }, bridgeBinarySHA256: pin.bridgeBinarySHA256)
        let baseline = try GeneratedTLCOracle.cacheKey(
            scenario: selected.scenario, id: selected.id, maximumStates: 100, pin: pin)
        #expect(baseline == (try GeneratedTLCOracle.cacheKey(
            scenario: selected.scenario, id: selected.id, maximumStates: 100, pin: pin)))
        #expect(baseline != (try GeneratedTLCOracle.cacheKey(
            scenario: selected.scenario, id: selected.id, maximumStates: 101, pin: pin)))
        #expect(baseline != (try GeneratedTLCOracle.cacheKey(
            scenario: selected.scenario, id: "another-case", maximumStates: 100, pin: pin)))
        #expect(baseline != (try GeneratedTLCOracle.cacheKey(
            scenario: selected.scenario, id: selected.id, maximumStates: 100, pin: changedPin)))
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
