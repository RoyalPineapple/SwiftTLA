import SwiftTLA
import Testing
import UpstreamParity

struct MajorityCorpusStateGraphTests {
    @Test("Majority preserves all bounded initial choices, transitions, and invariants")
    func completeBoundedGraph() throws {
        let initial = try MajorityModel.initialMachines()
        #expect(initial.count == 1092)
        let native = try ReachabilityGraph(initialMachines: initial, maximumStates: 10_000)
        #expect(native.transitions.count == 2733)
        #expect(native.safetyViolations.isEmpty)
        let compilation = try MajorityModel.spec.compile()
        let formal = try ModelChecker(compilation: compilation,
            configuration: .init(maximumStateLimit: 10_000, symmetryReduction: .disabled))
            .explore(checkingSafety: false)
        let run = try NativeModelRun(native, description: compilation.description, rendered: compilation.render())
        let reference = try FormalGraphExporter().export(formal)
        #expect(try CanonicalGraph(native) == reference.graph)
        #expect(run.checks.properties == ["TypeOK": .satisfied, "Correct": .satisfied, "Inv": .satisfied])
        #expect(run.checks.deadlock == nil)
    }
}
