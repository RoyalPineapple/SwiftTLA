import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct UpstreamParityTests {
    @Test("Model checker count matches every TLC-verified example")
    func modelCheckerMatchesTLC() throws {
        for entry in Example.all {
            let result = try explore(entry.spec, maximumStateLimit: entry.maximumStateLimit)
            let count = result.graph.states.count
            let matches = count == entry.expectedDistinct && isSuccessful(result)
            if !matches {
                Issue.record("\(entry.id): ModelChecker \(count) states, TLC \(entry.expectedDistinct)")
            }
        }
    }

    @Test("Game of Life function update matches TLC")
    func gameOfLifeMatchesTLC() throws {
        let result = try explore(Example.gameOfLife.spec, maximumStateLimit: 10)
        #expect(result.graph.states.count == 2)
        #expect(isSuccessful(result))
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
        #expect(tla.contains("WF_"))
        #expect(tla.contains("(a__0)"))
    }

    @Test("Consensus PlusCal port matches its bounded TLC configuration")
    func consensusParity() throws {
        let result = try explore(ConsensusModel.spec, maximumStateLimit: 100_000)
        #expect(result.graph.states.count == Example.consensus.expectedDistinct)
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

private func explore(_ spec: TLASpec, maximumStateLimit: Int) throws -> ModelExplorationResult {
    let compilation = try spec.compile()
    return try ModelChecker(
        compilation: compilation,
        configuration: try FiniteExplorationConfiguration(maximumStateLimit: maximumStateLimit)
    ).explore()
}

private func isSuccessful(_ exploration: ModelExplorationResult) -> Bool {
    if case .ok = exploration.result.underlyingOutcome { return true }
    return false
}
