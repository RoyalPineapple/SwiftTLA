import Testing
import SwiftTLA
import UpstreamParity

struct UpstreamParityTests {
    @Test("Every ParityCatalog entry: ModelChecker count matches expectedDistinct")
    func modelCheckerMatchesCatalog() throws {
        for entry in ParityCatalog.all {
            let count = try ModelChecker(spec: entry.spec, maxStates: 50_000).exploreGraph().states.count
            #expect(count == entry.expectedDistinct, "\(entry.id): got \(count), expected \(entry.expectedDistinct)")
            let result = try ModelChecker(spec: entry.spec, maxStates: 50_000).check()
            #expect({ if case .ok = result { true } else { false } }(), "\(entry.id): \(result)")
        }
    }

    @Test("HourClock .tlaModule is TLC-shaped")
    func hourClockTLA() {
        let tla = ParityCatalog.hourClock.spec.tlaModule
        #expect(tla.contains("MODULE HourClock"))
        #expect(tla.contains("hr \\in"))
        #expect(tla.contains("HCnxt"))
        #expect(tla.contains("Spec =="))
    }

    @Test("DieHard actions match upstream names")
    func dieHardNames() {
        let tla = ParityCatalog.dieHardTypeOK.spec.tlaModule
        for name in ["FillSmallJug", "FillBigJug", "EmptySmallJug", "EmptyBigJug", "SmallToBig", "BigToSmall", "TypeOK"] {
            #expect(tla.contains(name), "missing \(name)")
        }
    }
}
