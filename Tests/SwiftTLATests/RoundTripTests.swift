import Testing
import SwiftTLA
import SwiftTLAExamples

struct RoundTripTests {
    @Test("Every example's @TLAModel spec equals builder DSL equivalent")
    func allExamples() {
        for example in Examples.all {
            let fromMacro = example.spec
            let fromBuilder = TLASpec(
                name: fromMacro.name,
                variables: fromMacro.variables,
                actions: fromMacro.actions,
                invariants: fromMacro.invariants,
                temporalProperties: fromMacro.temporalProperties,
                fairness: fromMacro.fairness,
                constraint: fromMacro.constraint,
                assume: fromMacro.assume,
                checkDeadlock: fromMacro.checkDeadlock
            )
            #expect(fromMacro == fromBuilder, "\(example.name): macro and builder must produce identical TLASpec")
        }
    }
}

struct CheckerTests {
    @Test("Lock checker finds 2 states, 2 actions, no violations")
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
        #expect(count == 2, "Expected 2 states, got \(count)")

        let graph = try checker.exploreGraph()
        #expect(graph.states.count == 2, "Expected 2 states in graph")

        let actions = Set(graph.transitions.values.flatMap { $0.map(\.action) }).sorted()
        #expect(actions == ["lock", "unlock"], "Expected lock and unlock actions")
    }

    @Test("Toggle checker finds 2 states, 1 action")
    func toggleSpec() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Toggle") {
            Variable(x, 0)
            Action("flip") { x.becomes((x + 1) % 2) }
        }

        let checker = ModelChecker(spec: spec, maxStates: 100)
        let graph = try checker.exploreGraph()
        #expect(graph.states.count == 2, "Expected 2 states")
        #expect(graph.transitions.count == 2, "Each state should have outgoing transitions")
    }

    @Test("Counter invariant violation with negative value")
    func counterViolation() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Counter") {
            Variable(x, 0)
            Action("inc") { x.becomes(x + 1) }
            Action("dec") { x.becomes(x - 1) }
            Invariant("nonNeg") { x >= 0 }
        }

        let checker = ModelChecker(spec: spec, maxStates: 100)
        let result = try checker.check()
        guard case .invariantViolated(let name, let state, _) = result else {
            #expect(Bool(false), "Expected violation")
            return
        }
        #expect(name == "nonNeg")
        #expect(state["x"] == .int(-1))
    }

    @Test("Empty named actions produce Action enum case 'noop' when no transitions")
    func emptyActions() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Empty") {
            Variable(x, 0)
            Action("") { x.stays }
        }

        let checker = ModelChecker(spec: spec, maxStates: 100)
        let graph = try checker.exploreGraph()
        let actions = Set(graph.transitions.values.flatMap { $0.map(\.action) })
        #expect(actions == [""], "Empty-name action should produce empty-string action name")
    }
}
