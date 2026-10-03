import Foundation
import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct HourClockCorpusStateGraphTests {
    @Test("original and INSTANCE-wrapped HourClock references retain pinned inputs and model-owned checks")
    func retainsIndependentConfigurations() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: root.appendingPathComponent("Verification/FiniteGraph/cases.json")))
        let declarations = manifest.cases.filter { $0.sourceModel.rawValue == "hour-clock" }
        #expect(Set(declarations.map(\.id)) == ["hour-clock", "ap-hour-clock"])
        for declaration in declarations {
            let pin = try #require(declaration.sourceInput)
            #expect(pin.path.hasPrefix("tlaplus/Examples@ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SpecifyingSystems/HourClock/"))
            #expect(pin.sha256 == declaration.moduleSHA256)
            for (path, digest) in [(declaration.module, declaration.moduleSHA256),
                                   (declaration.configuration, declaration.cfgSHA256)] {
                let input = try Data(contentsOf: root.appendingPathComponent("Verification/FiniteGraph/fixtures/\(path)"))
                #expect(SHA256.hex(input) == digest)
            }
            let scenario = try #require(try declaration.resolveScenario())
            let run = try NativeScenarioRun(scenario, maximumStates: 12)
            try run.validateExpectations()
            let graph = try #require(run.native.graph).graph
            #expect(graph.initialStateKeys.count == 12)
            #expect(graph.states.count == 12)
            #expect(graph.edges.count == 12)
            let rendered = try scenario.render()
            #expect(rendered.invariantNames == ["HCini"])
            #expect(rendered.checksDeadlock)
        }
        let wrapper = try #require(declarations.first { $0.id == "ap-hour-clock" })
        #expect(wrapper.imports == ["hour-clock/HourClock.tla"])
        #expect(wrapper.dependencies.map(\.importingModule) == ["APHourClock"])
        #expect(wrapper.dependencies.map(\.importedModule) == ["HourClock"])
    }

    @Test("HourClock generated initial-state selection rejects ambiguity and out-of-domain hours")
    func rejectsInvalidInitialSelection() throws {
        #expect(throws: GeneratedMachineError.ambiguousInitialState) { try HourClockModel.makeMachine() }
        for invalid in [0, 13] {
            #expect(throws: GeneratedMachineError.invalidInitialState) {
                try HourClockModel.makeMachine(.init(hr: invalid))
            }
        }
    }
}
