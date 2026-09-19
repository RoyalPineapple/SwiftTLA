import Testing
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct PositiveReachabilityTests {
    @Test("positive predicates and parameter bindings survive typed lowering")
    func retainsPositivePredicate() throws {
        let compilation = try ReachabilityCounter.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let goal = try #require(program.behavior.reachabilityProperties.first)
        #expect(goal.name == "Target")
        #expect(goal.predicate.expression.operation == .equal)
        #expect(goal.predicate.expression.resultType == .bool)
        #expect(goal.predicate.expression.children.map(\.resultType) == [.int, .int])
        let target = try #require(program.layout.parameters.first { $0.reference.name == "target" })
        #expect(goal.predicate.expression.children.last?.operation == .boundValue(target.binder))
        #expect(compilation.description.reachabilityProperties == ["Target"])
        #expect(program.layout.stateProperties.map(\.declaration.kind) == [.invariant, .reachability])
    }

    @Test("native reachability retains full witnesses and does not truncate graph capture")
    func retainsNativeWitnesses() throws {
        for target in [0, 1, 2] {
            let graph = try ReachabilityGraph(initialMachines: ReachabilityCounter.initialMachines(
                configuration: .init(target: target, exploredThrough: 2)), maximumStates: 10)
            guard case .reached(let state) = graph.reachabilityResults[.Target] else {
                Issue.record("Expected a positive reachability witness for \(target)")
                continue
            }
            #expect(state.state.count == target)
            #expect(try graph.trace(to: state).map { $0.state.state.count } == Array(0...target))
            #expect(graph.transitions.count == 3)
            #expect(graph.transitions.values.flatMap { $0 }.count == 2)
            #expect(graph.deadlockedStates.map { $0.state.count } == [2])
        }
    }

    @Test("only complete exploration establishes an unreachable goal")
    func unreachableAndIncompleteRemainDistinct() throws {
        let graph = try ReachabilityGraph(initialMachines: ReachabilityCounter.initialMachines(
            configuration: .init(target: 3, exploredThrough: 2)), maximumStates: 10)
        #expect(graph.reachabilityResults[.Target] == .unreachable)
        #expect(graph.transitions.count == 3)
        #expect(throws: ExplorationError.stateLimitExceeded(1)) {
            try ReachabilityGraph(initialMachines: ReachabilityCounter.initialMachines(
                configuration: .init(target: 0, exploredThrough: 2)), maximumStates: 1)
        }
    }

    @Test("constraint-boundary matches retain executable witness states outside the graph")
    func retainsBoundaryWitness() throws {
        let graph = try ReachabilityGraph(initialMachines: ReachabilityCounter.initialMachines(
            configuration: .init(target: 2, exploredThrough: 1)), maximumStates: 10)
        guard case .reached(let state) = graph.reachabilityResults[.Target] else {
            Issue.record("Expected a witness for the excluded candidate")
            return
        }
        #expect(graph.transitions[state] == nil)
        #expect(graph.transitions.count == 2)
        #expect(graph.deadlockedStates.isEmpty)
        #expect(try graph.trace(to: state).map { $0.state.state.count } == [0, 1, 2])
    }

    @Test("TLC export alone negates the predicate and retains positive check metadata")
    func negatesOnlyAtExport() throws {
        let first = try ConfiguredCounter.render(configuration: .init(limit: 2, stopAtLimit: true))
        let second = try ConfiguredCounter.render(configuration: .init(limit: 4, stopAtLimit: false))
        #expect(first.tlaBundle.tla == second.tlaBundle.tla)
        #expect(first.tlaBundle.tla.contains("AtLimit == ~("))
        #expect(first.tlaBundle.cfg.contains("INVARIANT AtLimit"))
        #expect(first.reachabilityNames == ["AtLimit"])
        #expect(!first.invariantNames.contains("AtLimit"))
        let selected = try first.tlaBundle(checking: ["AtLimit"], checkDeadlock: false)
        #expect(selected.cfg.contains("INVARIANT AtLimit"))
        #expect(!selected.cfg.contains("INVARIANT Bounded"))
    }

    @Test("reachability declarations affect identity and reject conflicting property names")
    func declarationIdentityAndNames() throws {
        let original = ReachabilityCounter.spec
        var changed = original
        changed.reachabilityProperties = [.init(name: "Target", body: .value(.bool(false)))]
        #expect(try original.compile().identity != changed.compile().identity)
        changed.reachabilityProperties = [.init(name: "Bounded", body: .value(.bool(true)))]
        #expect(throws: CompilationDiagnostic.self) { try changed.compile() }
    }

    @Test("formal parity exploration rejects unsupported positive outcomes explicitly")
    func rejectsUnreportedFormalOutcome() throws {
        let compilation = try ReachabilityCounter.spec.compile()
        #expect(throws: CompilationDiagnostic.self) {
            try ModelChecker(compilation: compilation,
                configuration: .init(maximumStateLimit: 10, symmetryReduction: .disabled)).explore()
        }
    }
}
