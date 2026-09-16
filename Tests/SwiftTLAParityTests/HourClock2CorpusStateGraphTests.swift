import Foundation
import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct HourClock2CorpusStateGraphTests {
    @Test("HourClock2 modulo steps retain every initial state and replay through application dispatch")
    func replaysCompleteGraph() throws {
        let scenario = try #require(try HourClock2Model.validationScenarios().first)
        let initial = try scenario.initialMachines()
        let graph = try scenario.explore(maximumStates: 12)
        #expect(Set(initial.map { $0.state.hr }) == Set(1...12))
        #expect(graph.initialStates.count == 12)
        #expect(graph.transitions.count == 12)
        #expect(graph.transitions.values.flatMap { $0 }.count == 12)
        #expect(graph.deadlockedStates.isEmpty)
        for machine in initial {
            let edges = try #require(graph.transitions[machine.snapshot])
            let edge = try #require(edges.first)
            #expect(edge.action == .HCnxt2)
            #expect(edge.target.state.hr == machine.state.hr % 12 + 1)
            var dispatched = machine
            _ = try dispatched.send(edge.action)
            #expect(dispatched.snapshot == edge.target)
        }
        #expect(throws: ExplorationError.stateLimitExceeded(11)) {
            try scenario.explore(maximumStates: 11)
        }
        let run = try NativeScenarioRun(scenario, maximumStates: 12)
        try run.validateExpectations()
        let rendered = try scenario.render()
        #expect(rendered.tlaBundle.tla.contains("VARIABLES hr\n"))
        #expect(rendered.invariantNames == ["HCini"])
        #expect(rendered.checksDeadlock)
        #expect(try rendered.plusCalBundle().root.cfg == rendered.tlaBundle.root.cfg)
    }

    @Test("HourClock2 admission retains the pinned INSTANCE and EXTENDS module chain")
    func retainsReferenceClosure() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: root.appendingPathComponent("Verification/FiniteGraph/cases.json")))
        let declaration = try #require(manifest.cases.first { $0.id == "ap-hour-clock-2" })
        #expect(declaration.sourceModel == .hourClock2)
        #expect(try declaration.resolveScenario()?.name == "AP Upstream")
        #expect(declaration.imports == ["hour-clock/HourClock2.tla", "hour-clock/HourClock.tla"])
        #expect(declaration.dependencies.map(\.importingModule) == ["APHourClock2", "HourClock2"])
        #expect(declaration.dependencies.map(\.importedModule) == ["HourClock2", "HourClock"])
        let pin = try #require(declaration.sourceInput)
        #expect(pin.path == "tlaplus/Examples@ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SpecifyingSystems/HourClock/APHourClock2.tla")
        #expect(pin.sha256 == declaration.moduleSHA256)
        for (path, digest) in [(declaration.module, declaration.moduleSHA256),
                               (declaration.configuration, declaration.cfgSHA256),
                               ("hour-clock/HourClock2.tla", "dfbb3e62e0ad33edec7d7dd5db8eba8a57f18778bf7c3adf1e5e4fe8dd6b69ca")] {
            let input = try Data(contentsOf: root.appendingPathComponent("Verification/FiniteGraph/fixtures/\(path)"))
            #expect(SHA256.hex(input) == digest)
        }
    }
}
