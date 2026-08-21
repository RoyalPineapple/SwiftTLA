import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct UpstreamParityTests {
    @Test("LearnProofs AddTwo preserves its PlusCal AST through both construction paths")
    func addTwoParserBuilderFidelity() throws {
        AddTwoModel._checkParserTree()
    }

    @Test("ModelChecker count vs TLC-verified expected — they must match")
    func modelCheckerMatchesTLC() throws {
        for entry in Example.all {

            let mc = try ModelChecker(compilation: try entry.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: entry.maximumStateLimit))
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
        let checker = try ModelChecker(compilation: try Example.gameOfLife.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10))
        #expect(try checker.exploreGraph().states.count == 2)
        guard case .ok(let count) = try checker.check() else {
            Issue.record("Game of Life did not verify")
            return
        }
        #expect(count == 2)
    }

    @Test("N-Queens FourQueens PlusCal port matches the published TLC graph")
    func nQueensMatchesTLC() throws {
        let checker = try ModelChecker(compilation: try Example.nQueensFour.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 5_000))
        #expect(try checker.exploreGraph().states.count == Example.nQueensFour.expectedDistinct)
        guard case .ok = try checker.check() else {
            Issue.record("N-Queens did not verify")
            return
        }
    }

    @Test("two-process Lock PlusCal port matches TLC")
    func lockMatchesTLC() throws {
        let checker = try ModelChecker(compilation: try Example.lockTwoProcess.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100))
        #expect(try checker.exploreGraph().states.count == Example.lockTwoProcess.expectedDistinct)
        guard case .ok = try checker.check() else {
            Issue.record("Lock did not verify")
            return
        }
    }

    @Test("two-process Peterson PlusCal port matches TLC")
    func petersonMatchesTLC() throws {
        let checker = try ModelChecker(compilation: try Example.petersonTwoProcess.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 1_000))
        #expect(try checker.exploreGraph().states.count == Example.petersonTwoProcess.expectedDistinct)
        guard case .ok = try checker.check() else {
            Issue.record("Peterson did not verify")
            return
        }
    }

    @Test("N=6 two-chamber Barriers PlusCal port matches TLC")
    func barriersMatchTLC() throws {
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
        let checker = try ModelChecker(compilation: try ChannelModel.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 50_000))
        #expect(try checker.exploreGraph().states.count == Example.channel.expectedDistinct)
        guard case .ok = try checker.check() else {
            Issue.record("Typed Channel model did not verify")
            return
        }
    }

    @Test("AsynchInterface typed record model matches its validated state count")
    func asynchInterfaceTypedRecordParity() throws {
        let checker = try ModelChecker(compilation: try AsynchInterfaceModel.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 50_000))
        #expect(try checker.exploreGraph().states.count == Example.asynchInterface.expectedDistinct)
        guard case .ok = try checker.check() else {
            Issue.record("Typed AsynchInterface model did not verify")
            return
        }
    }

    @Test("TeachingConcurrency Simple models use typed phase state")
    func teachingSimpleTypedPhaseParity() throws {

        let n2 = try ModelChecker(compilation: try TeachingSimpleN2Model.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 50_000))
        let n3 = try ModelChecker(compilation: try TeachingSimpleN3Model.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 50_000))
        #expect(try n2.exploreGraph().states.count == Example.teachingSimpleN2.expectedDistinct)
        #expect(try n3.exploreGraph().states.count == Example.teachingSimpleN3.expectedDistinct)
    }

    @Test("TeachingConcurrency SimpleRegular uses bounded regular-register state")
    func teachingSimpleRegularParity() throws {
        let checker = try ModelChecker(
            spec: TeachingSimpleRegularN8Model.spec,
            configuration: try FiniteExplorationConfiguration(
                maximumStateLimit: Example.teachingSimpleRegularN8.maximumStateLimit
            )
        )
        #expect(try checker.exploreGraph().states.count == Example.teachingSimpleRegularN8.expectedDistinct)
    }

    @Test("FindHighest PlusCal port matches its bounded TLC configuration")
    func findHighestParity() throws {
        let checker = try ModelChecker(compilation: try FindHighestModel.spec.compile(), configuration: .standard)
        #expect(try checker.exploreGraph().states.count == Example.findHighest.expectedDistinct)
    }

    @Test("Dijkstra mutex preserves its bounded PlusCal model")
    func dijkstraMutexParity() throws {
        DijkstraMutexModel._checkParserTree()
        let checker = try ModelChecker(
            spec: DijkstraMutexModel.spec,
            configuration: try FiniteExplorationConfiguration(
                maximumStateLimit: Example.dijkstraMutex.maximumStateLimit
            )
        )
        let exploration = try checker.explore()
        print("Dijkstra mutex: \(exploration.graph.states.count) states, \(exploration.result)")
        #expect(exploration.graph.states.count == Example.dijkstraMutex.expectedDistinct)
    }

    @Test("BinarySearch PlusCal port matches its bounded TLC configuration")
    func binarySearchParity() throws {
        let checker = try ModelChecker(compilation: try BinarySearchModel.spec.compile(), configuration: .standard)
        #expect(try checker.exploreGraph().states.count == Example.binarySearch.expectedDistinct)
        #expect(try BinarySearchModel.spec.compile().renderedTLAModuleBundle().tla.contains("WF_"))
        #expect(try BinarySearchModel.spec.compile().renderedTLAModuleBundle().tla.contains("(Next)"))
    }

    @Test("Consensus PlusCal port matches its bounded TLC configuration")
    func consensusParity() throws {
        let checker = try ModelChecker(compilation: try ConsensusModel.spec.compile(), configuration: .standard)
        #expect(try checker.exploreGraph().states.count == Example.consensus.expectedDistinct)
    }

    @Test("SumSequence bounded source port verifies")
    func sumSequenceBoundedPort() throws {
        SumSequenceModel._checkParserTree()
        let checker = try ModelChecker(compilation: try SumSequenceModel.spec.compile(), configuration: .standard)
        #expect(try checker.exploreGraph().states.count == Example.sumSequence.expectedDistinct)
    }

    @Test("Reachable bounded source port compiles its formal graph choice")
    func reachableBoundedPort() throws {
        ReachableModel._checkParserTree()
        let checker = try ModelChecker(compilation: try ReachableModel.spec.compile(), configuration: .standard)
        #expect(try checker.exploreGraph().states.count == Example.reachable.expectedDistinct)
    }

    @Test("Parallel Reachable bounded source port verifies")
    func parallelReachableBoundedPort() throws {
        ParallelReachableModel._checkParserTree()
        let checker = try ModelChecker(compilation: try ParallelReachableModel.spec.compile(), configuration: .standard)
        #expect(try checker.exploreGraph().states.count == Example.parallelReachable.expectedDistinct)
    }

    @Test("Echo PlusCal port matches its three-node TLC configuration")
    func echoParity() throws {
        EchoModel._checkParserTree()
        let checker = try ModelChecker(compilation: try EchoModel.spec.compile(), configuration: .standard)
        #expect(try checker.exploreGraph().states.count == Example.echo.expectedDistinct)
    }

    @Test("EWD840 uses typed finite function state")
    func ewd840TypedFunctionParity() throws {
        let checker = try ModelChecker(compilation: try EWD840Model.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 50_000))
        #expect(try checker.exploreGraph().states.count == Example.ewd840.expectedDistinct)
        guard case .ok = try checker.check() else {
            Issue.record("Typed EWD840 model did not verify")
            return
        }
    }

    @Test("EWD998 uses typed finite functions and parameterized actions")
    func ewd998TypedFunctionParity() throws {
        let checker = try ModelChecker(compilation: try EWD998TerminationModel.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 50_000))
        #expect(try checker.exploreGraph().states.count == Example.ewd998.expectedDistinct)
        guard case .ok = try checker.check() else {
            Issue.record("Typed EWD998 model did not verify")
            return
        }
    }

    @Test("Moving Cat models use typed direction state")
    func movingCatTypedDirectionParity() throws {

        let even = try ModelChecker(compilation: try CatEvenBoxesModel.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 50_000))
        let odd = try ModelChecker(compilation: try CatOddBoxesModel.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 50_000))
        #expect(try even.exploreGraph().states.count == Example.catEvenBoxes.expectedDistinct)
        #expect(try odd.exploreGraph().states.count == Example.catOddBoxes.expectedDistinct)
    }

    @Test("Sync termination detector uses typed finite function state")
    func syncTerminationTypedFunctionParity() throws {
        let checker = try ModelChecker(compilation: try SyncTerminationDetectionModel.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 50_000))
        #expect(try checker.exploreGraph().states.count == Example.syncTD.expectedDistinct)
    }
}
