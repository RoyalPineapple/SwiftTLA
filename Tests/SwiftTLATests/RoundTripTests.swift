import Foundation
import Testing
import SwiftTLA

struct CheckerTests {
    @Test("Lock: 2 states, 2 actions, invariant holds")
    func lockSpec() throws {
        let v = Var<Int>("isLocked")
        let spec = TLASpec("Lock") {
            Variable(v, 0)
            Action("lock") { v.becomes(1).when(v == 0) }
            Action("unlock") { v.becomes(0).when(v == 1) }
            Invariant("binary") { v >= 0 && v <= 1 }
        }
        let result = try ModelChecker(spec: spec, maxStates: 100).check()
        guard case .ok(let count) = result else { #expect(Bool(false), "Expected ok"); return }
        #expect(count == 2)
    }

    @Test("Toggle: 2 states")
    func toggleSpec() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Toggle") {
            Variable(x, 0)
            Action("flip") { x.becomes((x + 1) % 2) }
        }
        let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
        #expect(graph.states.count == 2)
    }

    @Test("Counter: invariant violation")
    func counterViolation() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Counter") {
            Variable(x, 0)
            Action("inc") { x.becomes(x + 1) }
            Action("dec") { x.becomes(x - 1) }
            Invariant("nonNeg") { x >= 0 }
        }
        let result = try ModelChecker(spec: spec, maxStates: 100).check()
        guard case .invariantViolated(let name, _, _) = result else { #expect(Bool(false), "Expected violation"); return }
        #expect(name == "nonNeg")
    }

    @Test("Transition struct Codable roundtrip")
    func transitionCodable() throws {
        let transition = StateGraph.Transition(action: "test", target: StateGraph.StateID(1))
        let data = try JSONEncoder().encode(transition)
        let decoded = try JSONDecoder().decode(StateGraph.Transition.self, from: data)
        #expect(decoded.action == "test")
        #expect(decoded.target.id == 1)
    }
}
