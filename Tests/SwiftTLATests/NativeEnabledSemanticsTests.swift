import Testing
@testable import SwiftTLA
import SwiftTLAMacros

// Formal boundary fixtures exercise action references as values in predicates.
@TLAModel
private struct EnabledActionObservations {
    static var spec: TLASpec {
        TLASpec("EnabledActionObservations") {
            let count = Var<Int>("count")
            Variable(count, 0)
            let advance = SwiftTLA.Action("advance") { count < 1 && count.becomes(count + 1) }
            advance
            SwiftTLA.Action("probe") { StateExpr.enabled(advance) && count.becomes(count) }
            Invariant("AdvanceEnabled") { StateExpr.enabled(advance) }
        }
    }
}

@TLAModel
private struct EnabledTargetConstraint {
    static var spec: TLASpec {
        TLASpec("EnabledTargetConstraint") {
            let count = Var<Int>("count")
            Variable(count, 0)
            let advance = SwiftTLA.Action("advance") { count < 2 && count.becomes(count + 1) }
            advance
            Constraint(StateExpr.enabled(advance))
        }
    }
}

@Suite struct NativeEnabledSemanticsTests {
    @Test("ENABLED guards and invariants follow the current formal action set")
    func enabledGuardAndInvariant() throws {
        let compilation = try EnabledActionObservations.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        var formal = try #require(try runtime.initialStates().first)
        let advance = try #require(compilation.layout.testActionID(named: "advance"))
        let probe = try #require(compilation.layout.testActionID(named: "probe"))
        let invariant = try #require(compilation.semantics.invariants.first)
        var native = try EnabledActionObservations.makeMachine()
        for iteration in 0..<2 {
            #expect(try native.isEnabled(.probe) == !runtime.successors(for: probe, from: formal).isEmpty)
            #expect(try native.violatedInvariants().isEmpty == runtime.invariantHolds(invariant, in: formal))
            #expect(try native.isEnabled(.probe) == (iteration == 0))
            if iteration == 0 {
                formal = try #require(try runtime.successors(for: advance, from: formal).first).state
                _ = try native.send(.advance)
            }
        }
        #expect(try native.violatedInvariants() == [invariant.name])
    }

    @Test("ENABLED constraints are evaluated in each candidate target state")
    func enabledTargetStateConstraint() throws {
        let compilation = try EnabledTargetConstraint.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        var formal = try #require(try runtime.initialStates().first)
        let advance = try #require(compilation.layout.testActionID(named: "advance"))
        var native = try EnabledTargetConstraint.makeMachine()
        formal = try #require(try runtime.successors(for: advance, from: formal).first).state
        #expect(try native.send(.advance).after.count == 1)
        #expect(try runtime.successors(for: advance, from: formal).isEmpty)
        #expect(try !native.isEnabled(.advance))
        let before = native.state
        do {
            _ = try native.send(.advance)
            Issue.record("The target loses enabledness and must be excluded")
        } catch GeneratedMachineError.noMatchingSuccessor {}
        #expect(native.state == before)
    }
}
