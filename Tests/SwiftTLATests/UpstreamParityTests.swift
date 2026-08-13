import Testing
import SwiftTLA
import UpstreamParity

struct UpstreamParityTests {
    @Test("ModelChecker count vs TLC-verified expected — they must match")
    func modelCheckerMatchesTLC() throws {
        for entry in Example.all {

            let mc = ModelChecker(spec: entry.spec, maxStates: 50_000)
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
        let checker = ModelChecker(spec: Example.gameOfLife.spec, maxStates: 10)
        #expect(try checker.exploreGraph().states.count == 2)
        guard case .ok(let count) = try checker.check() else {
            Issue.record("Game of Life did not verify")
            return
        }
        #expect(count == 2)
    }

    @Test("HourClock .tlaModule is TLC-shaped")
    func hourClockTLA() {
        let tla = Example.hourClock.spec.tlaModule
        #expect(tla.contains("MODULE HourClock"))
        #expect(tla.contains("hr \\in"))
        #expect(tla.contains("HCnxt"))
        #expect(tla.contains("Spec =="))
    }

    @Test("DieHard actions match upstream names")
    func dieHardNames() {
        let tla = Example.dieHardTypeOK.spec.tlaModule
        for name in ["FillSmallJug", "FillBigJug", "EmptySmallJug", "EmptyBigJug", "SmallToBig", "BigToSmall", "TypeOK"] {
            #expect(tla.contains(name), "missing \(name)")
        }
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

    // Barrier
    @Test("Barrier_N6 native verifySpec")
    func barrierNativeVerifySpec() throws { try BarrierModel.verifySpec() }
    @Test("Barrier_N6 native verifyTransitions")
    func barrierNativeVerifyTransitions() throws { try BarrierModel.verifyTransitions() }

    // Self-consistency
    @Test("Native codegen self-consistency")
    func nativeSelfConsistency() throws {
        func check(_ matrix: [(from: [String: TLAValue], action: String, to: [String: TLAValue])], runtime: SpecRuntime) throws {
            for entry in matrix {
                let next = try runtime.apply(.init(name: entry.action), to: entry.from)
                #expect(next == entry.to)
            }
        }
        try check(HourClockModel.transitionMatrix(), runtime: HourClockModel.runtime)
        try check(HourClock2Model.transitionMatrix(), runtime: HourClock2Model.runtime)
        try check(DieHardModel.transitionMatrix(), runtime: DieHardModel.runtime)
        try check(BarrierModel.transitionMatrix(), runtime: BarrierModel.runtime)
    }
}
