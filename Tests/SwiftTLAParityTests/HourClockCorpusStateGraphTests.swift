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
        let declarations = manifest.cases.filter { $0.sourceModel == .hourClock }
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

    @Test("HourClock native execution matches the complete formal graph and initial domain")
    func nativeGraphMatchesFormalGraph() throws {
        let compilation = try HourClockModel.spec.compile()
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)
        ).explore()
        #expect(exploration.isComplete)
        let initial = try HourClockModel.initialMachines()
        let native = try ReachabilityGraph(initialMachines: initial, maximumStates: 100)
        #expect(native.safetyViolations.isEmpty)
        let exported = try CanonicalGraph(native)
        let formal = try FormalGraphExporter().export(exploration)
        #expect(exported == formal.graph)
        #expect(exported.initialStateKeys.count == 12)
        #expect(exported.states.count == 12)
        #expect(exported.edges.count == 12)
        #expect(throws: GeneratedMachineError.ambiguousInitialState) { try HourClockModel.makeMachine() }
        for invalid in [0, 13] {
            #expect(throws: GeneratedMachineError.invalidInitialState) {
                try HourClockModel.makeMachine(.init(hr: invalid))
            }
        }
    }
}
