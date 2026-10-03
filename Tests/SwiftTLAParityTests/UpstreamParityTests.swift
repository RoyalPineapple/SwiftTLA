import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct UpstreamParityTests {
    @Test("NanoBlockchain preserves its six genesis transitions")
    func nanoBlockchainGenesisTransitions() throws {
        let noBlock = TLAValue.record([
            "block": .record(["type": .string("NoBlock")]),
            "signature": .record([
                "data": .string("NoHash"),
                "signedWith": .string("NoPriv"),
            ]),
        ])
        let emptyLedger = TLAValue.function([
            .string("h1"): noBlock,
            .string("h2"): noBlock,
            .string("h3"): noBlock,
        ])
        let initialLedger = TLAValue.function([
            .string("n1"): emptyLedger,
            .string("n2"): emptyLedger,
        ])
        let emptyReceived = TLAValue.function([
            .string("n1"): .set([]),
            .string("n2"): .set([]),
        ])
        let compilation = try NanoBlockchainModel.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let lastHash = try #require(TLAStateProjection.Token(validating: "lastHash"))
        let distributedLedger = try #require(TLAStateProjection.Token(validating: "distributedLedger"))
        let received = try #require(TLAStateProjection.Token(validating: "received"))
        let initialProjection = try initial.projection(using: compilation.layout)
        #expect(initialProjection.value(for: lastHash) == .string("NoHash"))
        #expect(initialProjection.value(for: distributedLedger) == initialLedger)
        #expect(initialProjection.value(for: received) == emptyReceived)

        let successors = try runtime.successors(from: initial)
        #expect(successors.count == 6)
        let names = try successors.map { successor in
            try #require(
                compilation.layout.actions.first { $0.id == successor.action }?.declaration.name
            )
        }
        #expect(Dictionary(grouping: names, by: { $0 }).mapValues(\.count) == [
            "CreateGenesis_prv1": 3,
            "CreateGenesis_prv2": 3,
        ])

        for (successor, actionName) in zip(successors, names) {
            let projection = try successor.state.projection(using: compilation.layout)
            let hash = try #require(projection.value(for: lastHash))
            let privateKey = actionName == "CreateGenesis_prv1" ? "prv1" : "prv2"
            let signedBlock = TLAValue.record([
                "block": .record([
                    "type": .string("genesis"),
                    "account": .string(privateKey),
                    "balance": .int(3),
                ]),
                "signature": .record([
                    "data": hash,
                    "signedWith": .string(privateKey),
                ]),
            ])
            let ledger = TLAValue.function([
                .string("h1"): hash == .string("h1") ? signedBlock : noBlock,
                .string("h2"): hash == .string("h2") ? signedBlock : noBlock,
                .string("h3"): hash == .string("h3") ? signedBlock : noBlock,
            ])
            #expect(projection.value(for: distributedLedger) == .function([
                .string("n1"): ledger,
                .string("n2"): ledger,
            ]))
            #expect(projection.value(for: received) == emptyReceived)
        }
    }

    @Test("SimpleAllocator binds each finite request through the three authored actions")
    func simpleAllocatorUsesParameterizedActions() throws {
        let specification = SimpleAllocatorModel.spec
        #expect(specification.actions.map(\.name) == ["Request", "Allocate", "Return"])
        #expect(specification.actions.allSatisfy { $0.bindings.map { $0.literalMembers?.count } == [3, 3] })
        _ = try specification.compile()
    }

    @Test("two-process Lock generated machine explores its complete bounded graph")
    func lockGeneratedGraph() throws {
        let graph = try ReachabilityGraph(initialMachines: LockModel.initialMachines(), maximumStates: 100)
        #expect(graph.transitions.count == Example.lockTwoProcess.expectedDistinct)
        #expect(graph.safetyViolations.isEmpty)
    }

    @Test("HourClock TLA+ module is TLC-shaped")
    func hourClockTLA() throws {
        let tla = try Example.hourClock.spec.compile().render().tlaBundle.tla
        #expect(tla.contains("MODULE HourClock"))
        #expect(tla.contains("hr \\in"))
        #expect(tla.contains("HCnxt"))
        #expect(tla.contains("Spec =="))
    }

    @Test("DieHard actions match upstream names")
    func dieHardNames() throws {
        let tla = try DieHardModel.render().tlaBundle.tla
        for name in ["FillSmallJug", "FillBigJug", "EmptySmallJug", "EmptyBigJug", "SmallToBig", "BigToSmall", "TypeOK", "NotSolved"] {
            #expect(tla.contains(name), "missing \(name)")
        }
    }

    @Test("Channel application transitions and complete checking agree for every upstream configuration")
    func channelGraphParity() throws {
        struct Edge: Hashable {
            let source: ChannelModel.Snapshot
            let action: ChannelModel.Action
            let target: ChannelModel.Snapshot
        }
        for scenario in try ChannelModel.validationScenarios() {
            let configuration = scenario.configuration
            let exploration = try scenario.explore(maximumStates: 100)
            let count = configuration.Data.count
            #expect(exploration.initialStates.count == 2 * count)
            #expect(exploration.initialStates.allSatisfy { $0.state.chan.ack == $0.state.chan.rdy })
            let checkedEdges = Set(exploration.transitions.flatMap { source, transitions in
                transitions.map { Edge(source: source, action: $0.action, target: $0.target) }
            })
            var pending = try scenario.initialMachines()
            #expect(Set(pending.map(\.snapshot)) == exploration.initialStates)
            #expect(throws: GeneratedMachineError.ambiguousInitialState) {
                try ChannelModel.makeMachine(configuration: configuration)
            }
            let datum = try #require(configuration.Data.first)
            #expect(throws: GeneratedMachineError.invalidInitialState) {
                try ChannelModel.makeMachine(.init(chan: .init(ack: 1, rdy: 0, val: datum)),
                    configuration: configuration)
            }
            let actions = configuration.Data.map { ChannelModel.Action.Send(d: $0) } + [.Rcv]
            var states: Set<ChannelModel.Snapshot> = []
            var edges: Set<Edge> = []
            while let machine = pending.popLast() {
                guard states.insert(machine.snapshot).inserted else { continue }
                try #require(states.count <= 4 * count)
                #expect(try machine.violatedInvariants().isEmpty)
                let enabled = try Set(machine.enabledActions())
                for action in actions {
                    let successors = try machine.successors(for: action)
                    #expect(try machine.isEnabled(action) == !successors.isEmpty)
                    #expect(enabled.contains(action) == !successors.isEmpty)
                    var next = machine
                    guard let successor = successors.first else {
                        #expect(throws: GeneratedMachineError.noMatchingSuccessor) { try next.send(action) }
                        #expect(next.state == machine.state)
                        continue
                    }
                    try #require(successors.count == 1)
                    let transition = try next.send(action)
                    #expect(transition.before == machine.state)
                    #expect(transition.after == successor.state)
                    #expect(next.state == successor.state)
                    edges.insert(Edge(source: machine.snapshot, action: action, target: next.snapshot))
                    pending.append(next)
                }
            }
            #expect(states == Set(exploration.transitions.keys))
            #expect(edges == checkedEdges)
            #expect(states.count == 4 * count)
            #expect(edges.count == 2 * count * (count + 1))
        }
    }

    @Test("AsynchInterface application transitions and complete checking agree for every upstream configuration")
    func asynchInterfaceGraphParity() throws {
        struct Edge: Hashable {
            let source: AsynchInterfaceModel.Snapshot
            let action: AsynchInterfaceModel.Action
            let target: AsynchInterfaceModel.Snapshot
        }
        for scenario in try AsynchInterfaceModel.validationScenarios() {
            let configuration = scenario.configuration
            let exploration = try scenario.explore(maximumStates: 100)
            let count = configuration.Data.count
            #expect(exploration.initialStates.count == 2 * count)
            #expect(exploration.initialStates.allSatisfy { $0.state.ack == $0.state.rdy })
            let checkedEdges = Set(exploration.transitions.flatMap { source, transitions in
                transitions.map { Edge(source: source, action: $0.action, target: $0.target) }
            })
            var pending = try scenario.initialMachines()
            #expect(Set(pending.map(\.snapshot)) == exploration.initialStates)
            #expect(throws: GeneratedMachineError.ambiguousInitialState) {
                try AsynchInterfaceModel.makeMachine(configuration: configuration)
            }
            let datum = try #require(configuration.Data.first)
            #expect(throws: GeneratedMachineError.invalidInitialState) {
                try AsynchInterfaceModel.makeMachine(.init(val: datum, rdy: 0, ack: 1),
                    configuration: configuration)
            }
            var states: Set<AsynchInterfaceModel.Snapshot> = []
            var edges: Set<Edge> = []
            let actions: [AsynchInterfaceModel.Action] = [.Send, .Rcv]
            while let machine = pending.popLast() {
                guard states.insert(machine.snapshot).inserted else { continue }
                try #require(states.count <= 4 * count)
                #expect(try machine.violatedInvariants().isEmpty)
                let enabled = try Set(machine.enabledActions())
                for action in actions {
                    let candidates = try machine.successors(for: action)
                    #expect(try machine.isEnabled(action) == !candidates.isEmpty)
                    #expect(enabled.contains(action) == !candidates.isEmpty)
                    var sent = machine
                    switch candidates.count {
                    case 0:
                        #expect(throws: GeneratedMachineError.noMatchingSuccessor) { try sent.send(action) }
                        #expect(sent.snapshot == machine.snapshot)
                    case 1:
                        let transition = try sent.send(action)
                        #expect(transition.before == machine.state)
                        #expect(transition.after == candidates[0].state)
                        #expect(sent.snapshot == candidates[0].snapshot)
                    default:
                        #expect(throws: GeneratedMachineError.ambiguousAction) { try sent.send(action) }
                        #expect(sent.snapshot == machine.snapshot)
                    }
                    for candidate in candidates {
                        edges.insert(Edge(source: machine.snapshot, action: action, target: candidate.snapshot))
                    }
                    pending.append(contentsOf: candidates)
                }
            }
            #expect(states == Set(exploration.transitions.keys))
            #expect(edges == checkedEdges)
            #expect(states.count == 4 * count)
            #expect(edges.count == 2 * count * (count + 1))
        }
    }

    @Test("partial three-process Dijkstra port has a complete generated graph without safety violations")
    func dijkstraPartialNativeGraph() throws {
        let graph = try ReachabilityGraph(
            initialMachines: DijkstraMutexModel.initialMachines(),
            maximumStates: Example.dijkstraMutex.maximumStateLimit
        )
        #expect(graph.transitions.count == Example.dijkstraMutex.expectedDistinct)
        #expect(graph.safetyViolations.isEmpty)
    }

    @Test("bounded Consensus fixture retains terminal deadlocks and temporal progress")
    func consensusGeneratedChecking() throws {
        let graph = try ReachabilityGraph(initialMachines: ConsensusModel.initialMachines(), maximumStates: 100)
        #expect(graph.transitions.count == Example.consensus.expectedDistinct)
        #expect(graph.safetyViolations.count == 3)
        #expect(graph.safetyViolations.values.allSatisfy { $0 == [.deadlock] })
        #expect(graph.temporalResults[.Success]?.status == .satisfied)
    }

    @Test("Paxos typed state preserves its bounded TLC graph")
    func paxosTypedStateParity() throws {
        let exploration = try explore(
            PaxosModel.spec,
            maximumStateLimit: Example.paxosSmall.maximumStateLimit
        )

        #expect(exploration.graph.states.count == Example.paxosSmall.expectedDistinct)
        #expect(isSuccessful(exploration))
    }

    @Test("Reachable bounded source port checks its generated machine")
    func reachableBoundedPort() throws {
        let graph = try ReachabilityGraph(
            initialMachines: ReachableModel.initialMachines(),
            maximumStates: Example.reachable.maximumStateLimit
        )
        #expect(graph.transitions.count == Example.reachable.expectedDistinct)
        #expect(graph.safetyViolations.isEmpty)
    }

    @Test("Parallel Reachable bounded source port checks its generated machine")
    func parallelReachableBoundedPort() throws {
        let graph = try ReachabilityGraph(
            initialMachines: ParallelReachableModel.initialMachines(),
            maximumStates: Example.parallelReachable.maximumStateLimit
        )
        #expect(graph.transitions.count == Example.parallelReachable.expectedDistinct)
        #expect(graph.safetyViolations.isEmpty)
    }

    @Test("EWD998 uses typed finite functions and parameterized actions")
    func ewd998TypedFunctionParity() throws {
        let exploration = try explore(EWD998TerminationModel.spec, maximumStateLimit: 50_000)
        #expect(exploration.graph.states.count == Example.ewd998.expectedDistinct)
        #expect(isSuccessful(exploration))
    }

    @Test("Sync termination detector uses typed finite function state")
    func syncTerminationTypedFunctionParity() throws {
        let exploration = try explore(SyncTerminationDetectionModel.spec, maximumStateLimit: 50_000)
        #expect(exploration.graph.states.count == Example.syncTD.expectedDistinct)
    }
}

private func explore(_ spec: TLASpec, maximumStateLimit: Int) throws -> FiniteExploration {
    let compilation = try spec.compile()
    return try ModelChecker(
        compilation: compilation,
        configuration: try FiniteExplorationConfiguration(maximumStateLimit: maximumStateLimit, symmetryReduction: .disabled)
    ).explore()
}

private func isSuccessful(_ exploration: FiniteExploration) -> Bool {
    if case .ok = exploration.outcome { return true }
    return false
}
