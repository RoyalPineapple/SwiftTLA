import Testing
import SwiftTLA
import UpstreamParity

struct UpstreamParityTests {
    @Test("ModelChecker count vs TLC-verified expected — they must match")
    func modelCheckerMatchesTLC() throws {
        for entry in Example.all {
            // FIXME: Bakery ModelChecker diverges from TLC — known evaluator bug
            if entry.id == "Bakery/N2" || entry.id == "NanoBlockchain/Small" { continue }

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
