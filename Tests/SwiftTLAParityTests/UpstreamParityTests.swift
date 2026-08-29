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
        #expect(specification.actions.allSatisfy { $0.bindings.map(\.values.count) == [3, 3] })
        _ = try specification.compile()
    }

    @Test("N-Queens FourQueens PlusCal port matches the published TLC graph")
    func nQueensMatchesTLC() throws {
        let result = try explore(Example.nQueensFour.spec, maximumStateLimit: 5_000)
        #expect(result.graph.states.count == Example.nQueensFour.expectedDistinct)
        #expect(isSuccessful(result))
    }

    @Test("two-process Lock PlusCal port matches TLC")
    func lockMatchesTLC() throws {
        let result = try explore(Example.lockTwoProcess.spec, maximumStateLimit: 100)
        #expect(result.graph.states.count == Example.lockTwoProcess.expectedDistinct)
        #expect(isSuccessful(result))
    }

    @Test("two-process Peterson PlusCal port matches TLC")
    func petersonMatchesTLC() throws {
        let result = try explore(Example.petersonTwoProcess.spec, maximumStateLimit: 1_000)
        #expect(result.graph.states.count == Example.petersonTwoProcess.expectedDistinct)
        #expect(isSuccessful(result))
    }

    @Test("HourClock TLA+ module is TLC-shaped")
    func hourClockTLA() throws {
        let tla = try Example.hourClock.spec.compile().renderedTLAModuleBundle().tla
        #expect(tla.contains("MODULE HourClock"))
        #expect(tla.contains("hr \\in"))
        #expect(tla.contains("HCnxt"))
        #expect(tla.contains("Spec =="))
    }

    @Test("DieHard actions match upstream names")
    func dieHardNames() throws {
        let tla = try Example.dieHardTypeOK.spec.compile().renderedTLAModuleBundle().tla
        for name in ["FillSmallJug", "FillBigJug", "EmptySmallJug", "EmptyBigJug", "SmallToBig", "BigToSmall", "TypeOK"] {
            #expect(tla.contains(name), "missing \(name)")
        }
    }

    @Test("Channel typed record model matches its validated state count")
    func channelTypedRecordParity() throws {
        let result = try explore(ChannelModel.spec, maximumStateLimit: 50_000)
        #expect(result.graph.states.count == Example.channel.expectedDistinct)
        #expect(isSuccessful(result))
    }

    @Test("AsynchInterface typed record model matches its validated state count")
    func asynchInterfaceTypedRecordParity() throws {
        let result = try explore(AsynchInterfaceModel.spec, maximumStateLimit: 50_000)
        #expect(result.graph.states.count == Example.asynchInterface.expectedDistinct)
        #expect(isSuccessful(result))
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
        let result = try explore(TeachingSimpleRegularN8Model.spec, maximumStateLimit: Example.teachingSimpleRegularN8.maximumStateLimit)
        #expect(result.graph.states.count == Example.teachingSimpleRegularN8.expectedDistinct)
    }

    @Test("FindHighest PlusCal port matches its bounded TLC configuration")
    func findHighestParity() throws {
        let result = try explore(FindHighestModel.spec, maximumStateLimit: 100_000)
        #expect(result.graph.states.count == Example.findHighest.expectedDistinct)
    }

    @Test("Dijkstra mutex preserves its bounded PlusCal model")
    func dijkstraMutexParity() throws {
        let result = try explore(DijkstraMutexModel.spec, maximumStateLimit: Example.dijkstraMutex.maximumStateLimit)
        #expect(result.graph.states.count == Example.dijkstraMutex.expectedDistinct)
    }

    @Test("BinarySearch PlusCal port matches its bounded TLC configuration")
    func binarySearchParity() throws {
        let result = try explore(BinarySearchModel.spec, maximumStateLimit: 100_000)
        #expect(result.graph.states.count == Example.binarySearch.expectedDistinct)
        let tla = try BinarySearchModel.spec.compile().renderedTLAModuleBundle().tla
        #expect(tla.contains("WF_<<pc, seq, val, low, high, result>>(Next)"))
    }

    @Test("Consensus PlusCal port matches its bounded TLC configuration")
    func consensusParity() throws {
        let result = try explore(ConsensusModel.spec, maximumStateLimit: 100_000)
        #expect(result.graph.states.count == Example.consensus.expectedDistinct)
    }

    @Test("Paxos typed state preserves its bounded TLC graph")
    func paxosTypedStateParity() throws {
        let result = try explore(
            PaxosModel.spec,
            maximumStateLimit: Example.paxosSmall.maximumStateLimit
        )

        #expect(result.graph.states.count == Example.paxosSmall.expectedDistinct)
        #expect(isSuccessful(result))
    }

    @Test("SumSequence bounded source port verifies")
    func sumSequenceBoundedPort() throws {
        let result = try explore(SumSequenceModel.spec, maximumStateLimit: 100_000)
        #expect(result.graph.states.count == Example.sumSequence.expectedDistinct)
    }

    @Test("Reachable bounded source port compiles its formal graph choice")
    func reachableBoundedPort() throws {
        let result = try explore(ReachableModel.spec, maximumStateLimit: 100_000)
        #expect(result.graph.states.count == Example.reachable.expectedDistinct)
    }

    @Test("Parallel Reachable bounded source port verifies")
    func parallelReachableBoundedPort() throws {
        let result = try explore(ParallelReachableModel.spec, maximumStateLimit: 100_000)
        #expect(result.graph.states.count == Example.parallelReachable.expectedDistinct)
    }

    @Test("Echo PlusCal port matches its three-node TLC configuration")
    func echoParity() throws {
        let result = try explore(EchoModel.spec, maximumStateLimit: 100_000)
        #expect(result.graph.states.count == Example.echo.expectedDistinct)
    }

    @Test("EWD840 uses typed finite function state")
    func ewd840TypedFunctionParity() throws {
        let result = try explore(EWD840Model.spec, maximumStateLimit: 50_000)
        #expect(result.graph.states.count == Example.ewd840.expectedDistinct)
        #expect(isSuccessful(result))
    }

    @Test("EWD998 uses typed finite functions and parameterized actions")
    func ewd998TypedFunctionParity() throws {
        let result = try explore(EWD998TerminationModel.spec, maximumStateLimit: 50_000)
        #expect(result.graph.states.count == Example.ewd998.expectedDistinct)
        #expect(isSuccessful(result))
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
        let result = try explore(SyncTerminationDetectionModel.spec, maximumStateLimit: 50_000)
        #expect(result.graph.states.count == Example.syncTD.expectedDistinct)
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
    if case .ok = exploration.result { return true }
    return false
}
