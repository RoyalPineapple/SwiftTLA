import Testing
import SwiftTLA

@Suite("Generated refinement behavior")
struct GeneratedRefinementBehaviorTests {
    @Test("generated refinement maps non-initial states and respects selected abstract fairness")
    func explicitSafetyOnlyRefinement() throws {
        let initial = try StutteringRefinementSource.initialMachines()
        var graph = try ReachabilityGraph(initialMachines: initial, maximumStates: 10)
        let machine = try #require(initial.first)
        let failures = try machine.refinementFailures(in: &graph)
        #expect(failures[.Safety] == nil)
        guard case .fairness? = failures[.Full] else {
            Issue.record("Full abstract behavior should reject perpetual stuttering")
            return
        }

        let rendered = try StutteringRefinementSource.render()
        #expect(rendered.tlaBundle.root.tla.contains("Full == abstract!Spec"))
        #expect(rendered.tlaBundle.root.tla.contains(
            "Safety == abstract!Init /\\ [][abstract!Next]_abstract!vars"))
    }
}
