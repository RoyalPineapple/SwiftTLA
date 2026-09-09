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


@TLAModel
private struct EnabledActionChain {
    static var spec: TLASpec {
        TLASpec("EnabledActionChain") {
            let count = Var<Int>("count")
            Variable(count, 0)
            let base = SwiftTLA.Action("base") { count < 1 && count.becomes(count) }
            base
            let middle = SwiftTLA.Action("middle") { StateExpr.enabled(base) && count.becomes(count) }
            middle
            SwiftTLA.Action("outer") { StateExpr.enabled(middle) && count.becomes(count) }
            Invariant("MiddleEnabled") { StateExpr.enabled(middle) }
        }
    }
}

@Suite struct NativeEnabledSemanticsTests {
    @Test("Nested ENABLED references preserve transitive action dependencies")
    func enabledActionChain() throws {
        let compilation = try EnabledActionChain.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let native = try EnabledActionChain.makeMachine()
        for action in compilation.semantics.actions {
            #expect(try !runtime.successors(for: action.id, from: initial).isEmpty)
        }
        #expect(try native.isEnabled(.base))
        #expect(try native.isEnabled(.middle))
        #expect(try native.isEnabled(.outer))
        #expect(try native.violatedInvariants().isEmpty)
        for invariant in compilation.semantics.invariants {
            #expect(try runtime.invariantHolds(invariant, in: initial))
        }
    }

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

extension NativeEnabledSemanticsTests {
    @Test("ENABLED dependency ordering does not depend on action declaration order")
    func reverseActionDeclarations() throws {
        let compilation = try TLASpec(
            name: "ReverseEnabledDependencies",
            variables: [.init(name: "count", initialization: .value(.int(0)), origin: .compiler)],
            actions: [
                .init(name: "outer", body: .and(.guard_(.enabledAction("middle")), .unchanged(.named("count")))),
                .init(name: "middle", body: .and(.guard_(.operatorApplication(.reference("BaseEnabled", arity: 0), [])), .unchanged(.named("count")))),
                .init(name: "base", body: .unchanged(.named("count")))
            ],
            invariants: [],
            formalOperatorDefinitions: [.init(name: "BaseEnabled", parameters: [], body: .enabledAction("base"))]
        ).compile()
        #expect(compilation.semantics.enabledActionIndices == [2, 1, 0])
        let runtime = CompiledRuntime(compilation: compilation)
        let state = try #require(try runtime.initialStates().first)
        for action in compilation.semantics.actions {
            #expect(try !runtime.successors(for: action.id, from: state).isEmpty)
        }
    }

    @Test("Cyclic ENABLED references produce a build-time diagnostic naming the actions")
    func cyclicEnabledDependencies() throws {
        let specification = TLASpec(name: "CyclicEnabledDependencies", variables: [], actions: [
            .init(name: "first", body: .guard_(.enabledAction("second"))),
            .init(name: "second", body: .guard_(.enabledAction("first")))
        ], invariants: [])
        do {
            _ = try specification.compile()
            Issue.record("A cyclic ENABLED dependency must be diagnosed")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .cyclicActionEnabledness)
            #expect(diagnostic.actual.contains("first"))
            #expect(diagnostic.actual.contains("second"))
        }
    }
}
