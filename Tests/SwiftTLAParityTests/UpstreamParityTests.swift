import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct UpstreamParityTests {
    @Test("LearnProofs AddTwo preserves its PlusCal AST through both construction paths")
    func addTwoParserBuilderFidelity() throws {
        AddTwoModel._checkParserTree()
        #expect(try AddTwoModel.verifySpec() == 5)
    }

    @Test("ModelChecker count vs TLC-verified expected — they must match")
    func modelCheckerMatchesTLC() throws {
        for entry in Example.all {

            let mc = try ModelChecker(spec: entry.spec, maxStates: entry.verificationStateLimit)
            let count = try mc.exploreGraph().states.count
            let result = try mc.check()

            let match = count == entry.expectedDistinct && { if case .ok = result { true } else { false } }()
            if !match {
                print("✘ \(entry.id): ModelChecker=\(count), TLC=\(entry.expectedDistinct), result=\(result)")
                Issue.record("\(entry.id): mismatch — ModelChecker \(count) states, TLC \(entry.expectedDistinct)")
                continue
            }
            print("✔ \(entry.id): \(count) states ✓")
        }
    }

    @Test("Game of Life function update matches TLC")
    func gameOfLifeMatchesTLC() throws {
        let checker = try ModelChecker(spec: Example.gameOfLife.spec, maxStates: 10)
        #expect(try checker.exploreGraph().states.count == 2)
        guard case .ok(let count) = try checker.check() else {
            Issue.record("Game of Life did not verify")
            return
        }
        #expect(count == 2)
    }

    @Test("N-Queens FourQueens PlusCal port matches the published TLC graph")
    func nQueensMatchesTLC() throws {
        try NQueensModel.verifySpec()
        let checker = try ModelChecker(spec: Example.nQueensFour.spec, maxStates: 5_000)
        #expect(try checker.exploreGraph().states.count == Example.nQueensFour.expectedDistinct)
        guard case .ok = try checker.check() else {
            Issue.record("N-Queens did not verify")
            return
        }
    }

    @Test("two-process Lock PlusCal port matches TLC")
    func lockMatchesTLC() throws {
        try LockModel.verifySpec()
        let checker = try ModelChecker(spec: Example.lockTwoProcess.spec, maxStates: 100)
        #expect(try checker.exploreGraph().states.count == Example.lockTwoProcess.expectedDistinct)
        guard case .ok = try checker.check() else {
            Issue.record("Lock did not verify")
            return
        }
    }

    @Test("two-process Peterson PlusCal port matches TLC")
    func petersonMatchesTLC() throws {
        try PetersonModel.verifySpec()
        let checker = try ModelChecker(spec: Example.petersonTwoProcess.spec, maxStates: 1_000)
        #expect(try checker.exploreGraph().states.count == Example.petersonTwoProcess.expectedDistinct)
        guard case .ok = try checker.check() else {
            Issue.record("Peterson did not verify")
            return
        }
    }

    @Test("N=6 two-chamber Barriers PlusCal port matches TLC")
    func barriersMatchTLC() throws {
        #expect(try BarriersN6Model.verifySpec() == Example.barriersN6.expectedDistinct)
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
        try ChannelModel.verifySpec()
        let checker = try ModelChecker(spec: ChannelModel.spec, maxStates: 50_000)
        #expect(try checker.exploreGraph().states.count == Example.channel.expectedDistinct)
        guard case .ok = try checker.check() else {
            Issue.record("Typed Channel model did not verify")
            return
        }
    }

    @Test("AsynchInterface typed record model matches its validated state count")
    func asynchInterfaceTypedRecordParity() throws {
        try AsynchInterfaceModel.verifySpec()
        let checker = try ModelChecker(spec: AsynchInterfaceModel.spec, maxStates: 50_000)
        #expect(try checker.exploreGraph().states.count == Example.asynchInterface.expectedDistinct)
        guard case .ok = try checker.check() else {
            Issue.record("Typed AsynchInterface model did not verify")
            return
        }
    }

    @Test("TeachingConcurrency Simple models use typed phase state")
    func teachingSimpleTypedPhaseParity() throws {
        try TeachingSimpleN2Model.verifySpec()
        try TeachingSimpleN3Model.verifySpec()

        let n2 = try ModelChecker(spec: TeachingSimpleN2Model.spec, maxStates: 50_000)
        let n3 = try ModelChecker(spec: TeachingSimpleN3Model.spec, maxStates: 50_000)
        #expect(try n2.exploreGraph().states.count == Example.teachingSimpleN2.expectedDistinct)
        #expect(try n3.exploreGraph().states.count == Example.teachingSimpleN3.expectedDistinct)
    }

    @Test("TeachingConcurrency SimpleRegular uses bounded regular-register state")
    func teachingSimpleRegularParity() throws {
        #expect(try TeachingSimpleRegularN8Model.verifySpec() == Example.teachingSimpleRegularN8.expectedDistinct)
    }

    @Test("FindHighest PlusCal port matches its bounded TLC configuration")
    func findHighestParity() throws {
        let count = try FindHighestModel.verifySpec()
        #expect(count == Example.findHighest.expectedDistinct)
    }

    @Test("Dijkstra mutex preserves its bounded PlusCal model")
    func dijkstraMutexParity() throws {
        DijkstraMutexModel._checkParserTree()
        let checker = try ModelChecker(
            spec: DijkstraMutexModel.spec,
            maxStates: Example.dijkstraMutex.verificationStateLimit
        )
        let exploration = try checker.explore()
        print("Dijkstra mutex: \(exploration.graph.states.count) states, \(exploration.result)")
        #expect(exploration.graph.states.count == Example.dijkstraMutex.expectedDistinct)
    }

    @Test("BinarySearch PlusCal port matches its bounded TLC configuration")
    func binarySearchParity() throws {
        let count = try BinarySearchModel.verifySpec()
        #expect(count == Example.binarySearch.expectedDistinct)
        #expect(try BinarySearchModel.spec.compile().renderedTLAModuleBundle().tla.contains("WF_"))
        #expect(try BinarySearchModel.spec.compile().renderedTLAModuleBundle().tla.contains("(Next)"))
    }

    @Test("Consensus PlusCal port matches its bounded TLC configuration")
    func consensusParity() throws {
        let count = try ConsensusModel.verifySpec()
        #expect(count == Example.consensus.expectedDistinct)
    }

    @Test("SumSequence bounded source port verifies")
    func sumSequenceBoundedPort() throws {
        SumSequenceModel._checkParserTree()
        let count = try SumSequenceModel.verifySpec()
        #expect(count == Example.sumSequence.expectedDistinct)
    }

    @Test("Reachable bounded source port compiles its formal graph choice")
    func reachableBoundedPort() throws {
        ReachableModel._checkParserTree()
        let count = try ReachableModel.verifySpec()
        #expect(count == Example.reachable.expectedDistinct)
    }

    @Test("Parallel Reachable bounded source port verifies")
    func parallelReachableBoundedPort() throws {
        ParallelReachableModel._checkParserTree()
        let count = try ParallelReachableModel.verifySpec()
        #expect(count == Example.parallelReachable.expectedDistinct)
    }

    @Test("Echo PlusCal port matches its three-node TLC configuration")
    func echoParity() throws {
        EchoModel._checkParserTree()
        let count = try EchoModel.verifySpec()
        #expect(count == Example.echo.expectedDistinct)
    }

    @Test("EWD840 uses typed finite function state")
    func ewd840TypedFunctionParity() throws {
        try EWD840Model.verifySpec()
        let checker = try ModelChecker(spec: EWD840Model.spec, maxStates: 50_000)
        #expect(try checker.exploreGraph().states.count == Example.ewd840.expectedDistinct)
        guard case .ok = try checker.check() else {
            Issue.record("Typed EWD840 model did not verify")
            return
        }
    }

    @Test("EWD998 uses typed finite functions and parameterized actions")
    func ewd998TypedFunctionParity() throws {
        try EWD998TerminationModel.verifySpec()
        let checker = try ModelChecker(spec: EWD998TerminationModel.spec, maxStates: 50_000)
        #expect(try checker.exploreGraph().states.count == Example.ewd998.expectedDistinct)
        guard case .ok = try checker.check() else {
            Issue.record("Typed EWD998 model did not verify")
            return
        }
    }

    @Test("Moving Cat models use typed direction state")
    func movingCatTypedDirectionParity() throws {
        try CatEvenBoxesModel.verifySpec()
        try CatOddBoxesModel.verifySpec()

        let even = try ModelChecker(spec: CatEvenBoxesModel.spec, maxStates: 50_000)
        let odd = try ModelChecker(spec: CatOddBoxesModel.spec, maxStates: 50_000)
        #expect(try even.exploreGraph().states.count == Example.catEvenBoxes.expectedDistinct)
        #expect(try odd.exploreGraph().states.count == Example.catOddBoxes.expectedDistinct)
    }

    @Test("Sync termination detector uses typed finite function state")
    func syncTerminationTypedFunctionParity() throws {
        try SyncTerminationDetectionModel.verifySpec()
        let checker = try ModelChecker(spec: SyncTerminationDetectionModel.spec, maxStates: 50_000)
        #expect(try checker.exploreGraph().states.count == Example.syncTD.expectedDistinct)
    }
}

// MARK: - Native codegen verification for @TLAModel parity specs

struct UpstreamParityNativeTests {
    // HourClock
    @Test("HourClock native verifySpec")
    func hourClockNativeVerifySpec() throws { try HourClockModel.verifySpec() }
    @Test("HourClock native verifyTransitions")
    func hourClockNativeVerifyTransitions() throws { try HourClockModel.verifyTransitions() }
    @Test("HourClock native verifyInvariants")
    func hourClockNativeVerifyInvariants() throws { try HourClockModel.verifyInvariants() }
    @Test("HourClock native transitionMatrix count")
    func hourClockNativeTransitionMatrix() throws { #expect(try HourClockModel.transitionMatrix().count == 12) }

    // HourClock2
    @Test("HourClock2 native verifySpec")
    func hourClock2NativeVerifySpec() throws { try HourClock2Model.verifySpec() }
    @Test("HourClock2 native verifyTransitions")
    func hourClock2NativeVerifyTransitions() throws { try HourClock2Model.verifyTransitions() }
    @Test("HourClock2 native verifyInvariants")
    func hourClock2NativeVerifyInvariants() throws { try HourClock2Model.verifyInvariants() }
    @Test("HourClock2 native transitionMatrix count")
    func hourClock2NativeTransitionMatrix() throws { #expect(try HourClock2Model.transitionMatrix().count == 12) }

    // DieHard
    @Test("DieHard native verifySpec")
    func dieHardNativeVerifySpec() throws { try DieHardModel.verifySpec() }
    @Test("DieHard native verifyTransitions")
    func dieHardNativeVerifyTransitions() throws { try DieHardModel.verifyTransitions() }
    @Test("DieHard native verifyInvariants")
    func dieHardNativeVerifyInvariants() throws { try DieHardModel.verifyInvariants() }

    // TwoPhase
    @Test("TwoPhase native verifySpec")
    func twoPhaseNativeVerifySpec() throws { try TwoPhaseModel.verifySpec() }

    @Test("TwoPhase with backup manager preserves the published PlusCal model")
    func twoPhaseWithBackupManagerParity() throws {
        TwoPhaseWithBackupManagerModel._checkParserTree()
        #expect(
            try TwoPhaseWithBackupManagerModel.verifySpec()
                == Example.twoPhaseWithBackupManager.expectedDistinct
        )
    }

    @Test("Consensus preserves the published parameterless macro model")
    func consensusNativeParity() throws {
        ConsensusModel._checkParserTree()
        #expect(try ConsensusModel.verifySpec() == Example.consensus.expectedDistinct)
    }

    // Barrier
    @Test("Barrier_N6 native verifySpec")
    func barrierNativeVerifySpec() throws { try BarrierModel.verifySpec() }
    @Test("Barrier_N6 native verifyTransitions")
    func barrierNativeVerifyTransitions() throws { try BarrierModel.verifyTransitions() }

}
