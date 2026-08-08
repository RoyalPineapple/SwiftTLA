import Testing
import SwiftTLA
import UpstreamParity

struct UpstreamParityTests {
    @Test("Every Example: ModelChecker explores without error")
    func modelCheckerRuns() throws {
        for entry in Example.all {
            let count = try ModelChecker(spec: entry.spec, maxStates: 50_000).exploreGraph().states.count
            let result = try ModelChecker(spec: entry.spec, maxStates: 50_000).check()
            if case .invariantViolated(let inv, _, _) = result {
                Issue.record("\(entry.id): \(count) states, INVARIANT VIOLATED '\(inv)'")
            } else if case .ok = result {
                // TLC parity validated by scripts/validate_upstream_parity.sh
            } else {
                Issue.record("\(entry.id): unexpected result \(result)")
            }
        }
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
