import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct MultiCarElevatorCorpusStateGraphTests {
    @Test("MultiCarElevator native execution preserves the complete bounded formal graph")
    func nativeGraphMatchesFormalGraph() throws {
        let compilation = try MultiCarElevator.spec.compile()
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: .init(maximumStateLimit: 4_000, symmetryReduction: .disabled)
        ).explore()
        try #require(exploration.isComplete)
        let initial = try MultiCarElevator.initialMachines()
        #expect(initial.count == 1)
        let machine = try #require(initial.first)
        let native = try ReachabilityGraph(initialMachines: initial, maximumStates: 4_000)
        #expect(native.safetyViolations.isEmpty)
        let exported = try CanonicalGraph(native, using: machine)
        let formal = try SwiftGraphExporter().export(exploration)
        #expect(exported == formal.graph)
        #expect(formal.outcome == .exhaustiveSuccess)
    }
}
