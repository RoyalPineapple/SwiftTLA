import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct HourClockCorpusStateGraphTests {
    @Test("HourClock native execution matches the complete formal graph and initial domain")
    func nativeGraphMatchesFormalGraph() throws {
        let compilation = try HourClockModel.spec.compile()
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)
        ).explore()
        #expect(exploration.isComplete)
        let initial = try HourClockModel.initialMachines()
        let machine = try #require(initial.first)
        let native = try ReachabilityGraph(initialMachines: initial, maximumStates: 100)
        #expect(native.safetyViolations.isEmpty)
        let exported = try CanonicalGraph(native, using: machine)
        let formal = try SwiftGraphExporter().export(exploration)
        #expect(exported == formal.graph)
        #expect(exported.initialStateKeys.count == 12)
        #expect(exported.states.count == 12)
        #expect(exported.edgeOccurrences.count == 12)
        #expect(throws: GeneratedMachineError.ambiguousInitialState) { try HourClockModel.makeMachine() }
        for invalid in [0, 13] {
            #expect(throws: GeneratedMachineError.invalidInitialState) {
                try HourClockModel.makeMachine(.init(hr: invalid))
            }
        }
    }
}
