import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct ChangRobertsCorpusContractTests {
    private typealias Node = ChangRobertsModel.Node

    private struct Position: Hashable {
        let state: ChangRobertsModel.State
        let unstarted: Set<Node>
    }

    private struct Edge: Hashable {
        let source: Position
        let action: ChangRobertsModel.Action
        let target: Position
    }

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
        let formalPositions = try exploration.graph.states.mapValues { projection in
            let locations: [Node: String] = try table("pc", in: projection)
            try #require(locations.values.allSatisfy { $0 == "n0" || $0 == "n1" })
            let messages: [Node: SetExpr<Node>] = try table("messages", in: projection)
            return try Position(
                state: .init(
                    initiator: table("initiator", in: projection),
                    processState: table("processState", in: projection),
                    successor: table("successor", in: projection),
                    messages: messages.mapValues { Set($0.elements) }
                ),
                unstarted: Set(locations.filter { $0.value == "n0" }.keys)
            )
        }
        var formalEdges: Set<Edge> = []
        for (source, transitions) in exploration.graph.transitions {
            for transition in transitions {
                let arguments = try transition.label.formalArguments(using: compilation.layout)
                try #require(arguments.count == 1)
                let node = try #require(Node(formalValue: arguments[0]))
                let action: ChangRobertsModel.Action
                switch transition.label.action {
                case "n0": action = .n0(process: node)
                case "n1": action = .n1(process: node)
                default:
                    Issue.record("Unexpected Chang–Roberts action: \(transition.label.action)")
                    continue
                }
                formalEdges.insert(try Edge(
                    source: #require(formalPositions[source]), action: action,
                    target: #require(formalPositions[transition.target])
                ))
            }
        }
        var pending = try ChangRobertsModel.initialMachines()
        #expect(pending.count == 8)
        #expect(throws: GeneratedMachineError.ambiguousInitialState) { try ChangRobertsModel.makeMachine() }
        let initial = try Set(pending.map(position))
        #expect(initial == Set(try exploration.initialStateIDs.map { try #require(formalPositions[$0]) }))
        let actions: [ChangRobertsModel.Action] = Node.allCases.flatMap { [.n0(process: $0), .n1(process: $0)] }
        var nativePositions: Set<Position> = []
        var nativeEdges: Set<Edge> = []
        while let machine = pending.popLast() {
            let source = try position(machine)
            guard nativePositions.insert(source).inserted else { continue }
            try #require(nativePositions.count <= 500)
            #expect(try machine.violatedInvariants().isEmpty)
            let enabled = try machine.enabledActions()
            #expect(Set(enabled) == Set(formalEdges.filter { $0.source == source }.map(\.action)))
            for action in actions {
                let successors = try machine.successors(for: action)
                #expect(try machine.isEnabled(action) == !successors.isEmpty)
                #expect(enabled.contains(action) == !successors.isEmpty)
                var next = machine
                if successors.isEmpty {
                    #expect(throws: GeneratedMachineError.noMatchingSuccessor) { try next.send(action) }
                    #expect(try position(next) == source)
                } else if successors.count == 1 {
                    let transition = try next.send(action)
                    #expect(transition.before == machine.state)
                    #expect(transition.after == successors[0].state)
                    #expect(try position(next) == position(successors[0]))
                } else {
                    #expect(throws: GeneratedMachineError.ambiguousAction) { try next.send(action) }
                    #expect(try position(next) == source)
                }
                for successor in successors {
                    nativeEdges.insert(try Edge(source: source, action: action, target: position(successor)))
                    pending.append(successor)
                }
            }
        }
        #expect(nativePositions.count == Example.changRobertsN3.expectedDistinct)
        #expect(nativePositions == Set(formalPositions.values))
        #expect(nativeEdges == formalEdges)
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

    private func position(_ machine: ChangRobertsModel) throws -> Position {
        // n0 is enabled exactly until that node has sent its initial message.
        // This distinguishes control states even when sending changes no public value.
        let unstarted = try Node.allCases.filter { try machine.isEnabled(.n0(process: $0)) }
        return Position(state: machine.state, unstarted: Set(unstarted))
    }

    private func table<Value: TLAValueType>(_ name: String, in projection: TLAStateProjection) throws -> [Node: Value] {
        let token = try #require(TLAStateProjection.Token(validating: name))
        let value = try #require(projection.value(for: token).flatMap(Function<Node, Value>.init(formalValue:)))
        return try Dictionary(uniqueKeysWithValues: Node.allCases.map { node in (node, try #require(value[node])) })
    }
}
