import Testing
import SwiftTLA

struct CheckerTests {
    @Test("Lock checker finds 2 states, 2 actions")
    func lockSpec() throws {
        let isLocked = Var<Int>("isLocked")
        let spec = TLASpec("Lock") {
            Variable(isLocked, 0)
            Action("lock") { isLocked.becomes(1).when(isLocked == 0) }
            Action("unlock") { isLocked.becomes(0).when(isLocked == 1) }
            Invariant("binary") { isLocked >= 0 && isLocked <= 1 }
        }

        let checker = ModelChecker(spec: spec, maxStates: 100)
        let result = try checker.check()

        guard case .ok(let count) = result else {
            #expect(Bool(false), "Expected ok, got \(result)")
            return
        }
        #expect(count == 2)

        let graph = try checker.exploreGraph()
        #expect(graph.states.count == 2)

        let actionNames = Set(graph.transitions.values.flatMap { $0.map(\.action) }).sorted()
        #expect(actionNames == ["lock", "unlock"])
    }

    @Test("Toggle checker finds 2 states")
    func toggleSpec() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Toggle") {
            Variable(x, 0)
            Action("flip") { x.becomes((x + 1) % 2) }
        }

        let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
        #expect(graph.states.count == 2)
    }

    @Test("Counter invariant violation")
    func counterViolation() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Counter") {
            Variable(x, 0)
            Action("inc") { x.becomes(x + 1) }
            Action("dec") { x.becomes(x - 1) }
            Invariant("nonNeg") { x >= 0 }
        }

        let result = try ModelChecker(spec: spec, maxStates: 100).check()
        guard case .invariantViolated(let name, _, _) = result else {
            #expect(Bool(false), "Expected violation")
            return
        }
        #expect(name == "nonNeg")
    }

    @Test("Transition struct roundtrips through Codable")
    func transitionCodable() throws {
        let transition = StateGraph.Transition(action: "test", target: StateGraph.StateID(1))
        let encoder = JSONEncoder()
        let data = try encoder.encode(transition)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(StateGraph.Transition.self, from: data)
        #expect(decoded.action == "test")
        #expect(decoded.target.id == 1)
    }
}
