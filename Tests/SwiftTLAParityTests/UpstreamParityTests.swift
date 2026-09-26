import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct UpstreamParityTests {
    @Test("Game of Life preserves the blinker transition")
    func gameOfLifeBlinkerTransition() throws {
        func grid(alive: Set<TLAValue>) -> TLAValue {
            .function(Dictionary(uniqueKeysWithValues: (1...4).flatMap { column in
                (1...4).map { row in
                    let position = TLAValue.tuple([.int(column), .int(row)])
                    return (position, .bool(alive.contains(position)))
                }
            }))
        }

        let vertical: Set<TLAValue> = [
            .tuple([.int(2), .int(2)]),
            .tuple([.int(2), .int(3)]),
            .tuple([.int(2), .int(4)]),
        ]
        let horizontal: Set<TLAValue> = [
            .tuple([.int(1), .int(3)]),
            .tuple([.int(2), .int(3)]),
            .tuple([.int(3), .int(3)]),
        ]
        let compilation = try GameOfLifeModel.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let token = try #require(TLAStateProjection.Token(validating: "grid"))
        #expect(try initial.projection(using: compilation.layout).value(for: token) == grid(alive: vertical))

        let first = try #require(try runtime.successors(from: initial).first)
        #expect(try runtime.successors(from: initial).count == 1)
        #expect(try first.state.projection(using: compilation.layout).value(for: token) == grid(alive: horizontal))

        let second = try #require(try runtime.successors(from: first.state).first)
        #expect(try second.state.projection(using: compilation.layout).value(for: token) == grid(alive: vertical))
    }

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

    @Test("two-process Lock PlusCal port matches TLC")
    func lockMatchesTLC() throws {
        let exploration = try explore(Example.lockTwoProcess.spec, maximumStateLimit: 100)
        #expect(exploration.graph.states.count == Example.lockTwoProcess.expectedDistinct)
        #expect(isSuccessful(exploration))
    }

    @Test("two-process Peterson PlusCal port matches TLC")
    func petersonMatchesTLC() throws {
        let exploration = try explore(Example.petersonTwoProcess.spec, maximumStateLimit: 1_000)
        #expect(exploration.graph.states.count == Example.petersonTwoProcess.expectedDistinct)
        #expect(isSuccessful(exploration))
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

    @Test("TeachingConcurrency Simple models use typed phase state")
    func teachingSimpleTypedPhaseParity() throws {
        let n2 = try explore(TeachingSimpleN2Model.spec, maximumStateLimit: 50_000)
        let n3 = try explore(TeachingSimpleN3Model.spec, maximumStateLimit: 50_000)
        #expect(n2.graph.states.count == Example.teachingSimpleN2.expectedDistinct)
        #expect(n3.graph.states.count == Example.teachingSimpleN3.expectedDistinct)
    }

    @Test("TeachingConcurrency SimpleRegular uses bounded regular-register state")
    func teachingSimpleRegularParity() throws {
        let exploration = try explore(TeachingSimpleRegularN8Model.spec, maximumStateLimit: Example.teachingSimpleRegularN8.maximumStateLimit)
        #expect(exploration.graph.states.count == Example.teachingSimpleRegularN8.expectedDistinct)
    }

    @Test("Dijkstra mutex preserves its bounded PlusCal model")
    func dijkstraMutexParity() throws {
        let exploration = try explore(DijkstraMutexModel.spec, maximumStateLimit: Example.dijkstraMutex.maximumStateLimit)
        #expect(exploration.graph.states.count == Example.dijkstraMutex.expectedDistinct)
    }

    @Test("Consensus PlusCal port matches its bounded TLC configuration")
    func consensusParity() throws {
        let exploration = try explore(ConsensusModel.spec, maximumStateLimit: 100_000)
        #expect(exploration.graph.states.count == Example.consensus.expectedDistinct)
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

    @Test("Reachable bounded source port compiles its formal graph choice")
    func reachableBoundedPort() throws {
        let exploration = try explore(ReachableModel.spec, maximumStateLimit: 100_000)
        #expect(exploration.graph.states.count == Example.reachable.expectedDistinct)
    }

    @Test("Parallel Reachable bounded source port verifies")
    func parallelReachableBoundedPort() throws {
        let exploration = try explore(ParallelReachableModel.spec, maximumStateLimit: 100_000)
        #expect(exploration.graph.states.count == Example.parallelReachable.expectedDistinct)
    }

    @Test("EWD998 uses typed finite functions and parameterized actions")
    func ewd998TypedFunctionParity() throws {
        let exploration = try explore(EWD998TerminationModel.spec, maximumStateLimit: 50_000)
        #expect(exploration.graph.states.count == Example.ewd998.expectedDistinct)
        #expect(isSuccessful(exploration))
    }

    @Test("Moving Cat models use typed direction state")
    func movingCatTypedDirectionParity() throws {
        let even = try explore(CatEvenBoxesModel.spec, maximumStateLimit: 50_000)
        let odd = try explore(CatOddBoxesModel.spec, maximumStateLimit: 50_000)
        #expect(even.graph.states.count == Example.catEvenBoxes.expectedDistinct)
        #expect(odd.graph.states.count == Example.catOddBoxes.expectedDistinct)
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
