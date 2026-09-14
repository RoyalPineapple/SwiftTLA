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
        let terminalStates = Set(native.transitions.keys.filter { $0.state.i > $0.state.seq.count })
        #expect(!terminalStates.isEmpty)
        #expect(Set(native.safetyViolations.keys) == terminalStates)
        #expect(native.safetyViolations.values.allSatisfy { $0 == [.deadlock] })
        #expect(terminalStates.allSatisfy { native.transitions[$0]?.isEmpty == true })
        let compilation = try MajorityModel.spec.compile()
        let formal = try ModelChecker(compilation: compilation,
            configuration: .init(maximumStateLimit: 10_000, symmetryReduction: .disabled))
            .explore(checkingSafety: false)
        #expect(formal.isComplete)
        let run = try NativeModelRun(native, description: compilation.description, rendered: compilation.render())
        let reference = try FormalGraphExporter().export(formal)
        #expect(try CanonicalGraph(native) == reference.graph)
        #expect(run.checks.properties == ["TypeOK": .satisfied, "Correct": .satisfied, "Inv": .satisfied])
        guard case .violated(let trace) = run.checks.deadlock else {
            Issue.record("Expected a deadlock witness for a completed Majority input.")
            return
        }
        let terminal = try #require(trace.steps.last?.state)
        #expect(!run.graph.graph.edges.contains { $0.source == terminal })
    }
}
