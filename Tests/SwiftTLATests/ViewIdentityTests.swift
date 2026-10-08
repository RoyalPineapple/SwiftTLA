import Testing
import SwiftTLA

struct ViewIdentityTests {
    @Test("a configured view uses one typed identity for native exploration and TLC export")
    func configuredQuotient() throws {
        let scenario = try #require(ViewIdentityCounter.validationScenarios().first)
        #expect(scenario.usesView)
        let rendered = try scenario.render().tlaBundle
        #expect(try #require(rendered.root.cfg).contains("VIEW __SwiftTLAView0"))
        #expect(rendered.root.tla.contains("__SwiftTLAView0 == phase"))

        var representatives: [Int] = []
        var edges: [(Int, Int)] = []
        let result = try scenario.runValidation(maximumStates: 3, checking: scenario.checking,
            stopOnViolation: false, stopOnReachability: false) { event in
            switch event {
            case .state(_, let snapshot, _, _, _): representatives.append(snapshot.state.history)
            case .edge(let source, _, let target): edges.append((source, target))
            default: break
            }
        }
        #expect(result.states == 2)
        #expect(result.edges == 2)
        #expect(representatives == [0, 1])
        #expect(edges.map { "\($0.0)->\($0.1)" } == ["0->1", "1->0"])
        let token = try #require(TLAStateProjection.Token(validating: "View"))
        let initial = try #require(scenario.initialMachines().first)
        let projection = try scenario.formalIdentityProjection(of: initial.snapshot, using: initial,
            atLevel: 1)
        #expect(projection.value(for: token) == .int(0))
        #expect(throws: ExplorationError.viewRequiresStreamingValidation) {
            try scenario.explore(maximumStates: 3)
        }
    }

    @Test("a view containing the checking level retains revisits at later depths")
    func levelSensitiveView() throws {
        let scenario = try #require(ViewIdentityCounter.validationScenarios().first {
            $0.name == "levelSensitive"
        })
        let rendered = try scenario.render().tlaBundle
        #expect(rendered.root.tla.contains("TLCGet(\"level\")"))

        var states: [(Int, Int)] = []
        let result = try scenario.runValidation(maximumStates: 4, checking: scenario.checking,
            stopOnViolation: false, stopOnReachability: false) { event in
            if case .state(_, let snapshot, _, _, _) = event {
                states.append((snapshot.state.phase, snapshot.state.history))
            }
        }
        #expect(states.map { "\($0.0):\($0.1)" } == ["0:0", "1:1", "0:2"])
        #expect(result.states == 3)
        #expect(result.edges == 2)
        guard case .exhausted = result.completion else {
            Issue.record("The level-sensitive view stopped before completing exploration")
            return
        }
        let initial = try #require(scenario.initialMachines().first)
        let first = try scenario.formalIdentityProjection(of: initial.snapshot, using: initial, atLevel: 1)
        let revisited = try scenario.formalIdentityProjection(of: initial.snapshot, using: initial, atLevel: 3)
        #expect(first != revisited)
    }
}
