import Testing
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ProjectedFairnessTests {
    @Test("generated checking requires progress in the declared record field")
    func projectedProgress() throws {
        let machine = try ProjectedProgress.makeMachine()
        let graph = try MachineValidationGraph(initialMachines: [machine], maximumStates: 10)
        #expect(graph.transitions.count == 4)
        #expect(try graph.temporalResults(checking: [.Complete])[.Complete]?.status == .satisfied)
        let tla = try ProjectedProgress.render().tlaBundle.tla
        #expect(tla.contains("WF_((position).progress)(Next)"))
        #expect(tla.contains("SF_((position).progress)(Next)"))
        let obligations = try machine.fairnessConditions()
        for successor in try machine.successors() {
            for obligation in obligations {
                let changes = try #require(obligation.changes)
                #expect(try changes(machine.snapshot, successor.machine.snapshot) == (successor.action == .advance))
            }
        }
    }

    @Test("fairness on an unchanged variable permits a typed stuttering counterexample")
    func projectedStuttering() throws {
        let machine = try ProjectedStuttering.makeMachine()
        let graph = try MachineValidationGraph(initialMachines: [machine], maximumStates: 10)
        #expect(graph.transitions.count == 2)
        let result = try #require(graph.temporalResults(checking: [.Changed])[.Changed])
        #expect(result.status == .violated)
        let witness = try #require(result.witness)
        #expect(witness.cycle == [machine.snapshot, machine.snapshot])
        #expect(witness.cycleActions == [nil])
        let tla = try ProjectedStuttering.render().tlaBundle.tla
        #expect(tla.contains("WF_(progress)(toggle)"))
        #expect(tla.contains("SF_(progress)(toggle)"))
    }

    @Test("fairness arguments must name a resolved current-state projection")
    func parserArguments() throws {
        let parser = ParserSession()
        let scope = ParserSession.TypedFacadeScope.empty.extending(binding: "progress", to: .variable("progress"), shape: .int)
        let valid: ExprSyntax = "WeakFairnessNext(on: progress)"
        #expect(parser.decodeFairness(try #require(valid.as(FunctionCallExprSyntax.self)), scope: scope)
            == .projected(.weakFairnessNext, .variable("progress")))
        for source: ExprSyntax in ["WeakFairnessNext(progress)", "WeakFairnessNext(on: progress, on: progress)"] {
            #expect(parser.decodeFairness(try #require(source.as(FunctionCallExprSyntax.self)), scope: scope) == nil)
        }
        for projection: StateExpr in [.variable("missing"), .nextState(.variable("progress"))] {
            var spec = ProjectedStuttering.spec
            spec.fairness = [.projected(.weakFairnessNext, projection)]
            #expect(throws: CompilationDiagnostic.self) { _ = try spec.compile() }
        }
    }

    @Test("refinement fairness uses abstract projections and all abstract successors")
    func projectedRefinement() throws {
        let stalled = try MachineValidationGraph(initialMachines: [ProjectedStuttering.makeMachine()], maximumStates: 10)
        let failure = try stalled.refinementFailure(initialMachines: [ProjectedProgress.makeMachine()]) { snapshot in
            var abstract = try ProjectedProgress.makeMachine()
            if snapshot.state.noise == 1 { _ = try abstract.send(.toggle) }
            return abstract
        }
        guard case .fairness(_, let witness) = try #require(failure) else {
            Issue.record("Expected an abstract projected-fairness violation")
            return
        }
        #expect(witness.cycle.allSatisfy { $0.state.progress == 0 })
        let progressing = try MachineValidationGraph(initialMachines: [ProjectedProgress.makeMachine()], maximumStates: 10)
        let accepted = try progressing.refinementFailure(initialMachines: [ProjectedStuttering.makeMachine()]) { snapshot in
            var abstract = try ProjectedStuttering.makeMachine()
            if snapshot.state.position.noise == 1 { _ = try abstract.send(.toggle) }
            return abstract
        }
        #expect(accepted == nil)
    }
}
