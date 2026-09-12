import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct ChangRobertsCorpusContractTests {
    private typealias Node = ChangRobertsModel.Node

    @Test("Chang–Roberts native execution preserves the complete N=3 graph and its properties")
    func nativeGraphMatchesFormalGraph() throws {
        let compilation = try ChangRobertsModel.spec.compile()
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: FiniteExplorationConfiguration(maximumStateLimit: 500, symmetryReduction: .disabled)
        ).explore()
        try #require(exploration.isComplete)
        #expect(compilation.description.invariants == ["Correctness"])
        #expect(compilation.description.temporalProperties == ["Liveness"])
        #expect(try exploration.analyzeTemporalProperties(in: compilation).map(\.status) == [.satisfied])
        let initial = try ChangRobertsModel.initialMachines()
        #expect(initial.count == 8)
        #expect(throws: GeneratedMachineError.ambiguousInitialState) { try ChangRobertsModel.makeMachine() }
        let machine = try #require(initial.first)
        let native = try ReachabilityGraph(initialMachines: initial, maximumStates: 500)
        #expect(native.safetyViolations.isEmpty)
        #expect(try native.analyzeTemporalProperties(using: machine)["Liveness"]?.status == .satisfied)
        let exported = try CanonicalGraph(native, using: machine)
        let formal = try SwiftGraphExporter().export(exploration)
        #expect(exported == formal.graph)
        #expect(exported.states.count == Example.changRobertsN3.expectedDistinct)
    }

    @Test("Chang–Roberts requires the smallest initiator to win and every peer to lose")
    func rejectsInvalidWinners() throws {
        let compilation = try ChangRobertsModel.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let initiator = try #require(compilation.layout.testVariableID(named: "initiator"))
        let processState = try #require(compilation.layout.testVariableID(named: "processState"))
        let correctness = try #require(compilation.semantics.behavior.invariants.first { $0.name == "Correctness" })
        let source = try initial.updating(initiator, to: .function([
            .integer(1): .boolean(true), .integer(2): .boolean(true), .integer(3): .boolean(false)
        ]))
        let scenarios: [([Node: ChangRobertsModel.ProcessState], Bool)] = [
            ([.one: .won, .two: .lost, .three: .lost], true),
            ([.one: .lost, .two: .won, .three: .lost], false),
            ([.one: .won, .two: .candidate, .three: .lost], false)
        ]
        for (statuses, expected) in scenarios {
            let values = Dictionary(uniqueKeysWithValues: statuses.map { node, status in
                (CompiledValue.integer(node.rawValue), CompiledValue.string(status.rawValue))
            })
            let state = try source.updating(processState, to: .function(values))
            #expect(try runtime.invariantHolds(correctness, in: state) == expected)
        }
    }

}
