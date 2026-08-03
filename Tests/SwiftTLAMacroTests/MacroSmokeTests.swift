import SwiftTLAMacrosInterface
import SwiftTLA
import XCTest

final class MacroSmokeTests: XCTestCase {

    func testHourClockExpandsTo12StateMachine() throws {
        let hr = Var<Int>("hr")
        #VerifiedStateMachine {
            TypeName("HourClock")
            Variable(hr, 1)
            Act("Tick") {
                let inc: ActionExpr = (hr >= 1) && (hr <= 11) && (next(hr) == hr + 1)
                let wrap: ActionExpr = (hr == 12) && (next(hr) == 1)
                inc || wrap
            }
        }

        // After macro expansion, HourClock is available as a type
        var clock = HourClock.initial
        XCTAssertEqual(clock.hr, 1)

        for _ in 1...12 {
            clock.apply(.tick)
        }
        XCTAssertEqual(clock.hr, 1, "Clock wraps around after 12 ticks")
    }

    func testDieHardExpandsToRunnablePuzzle() throws {
        let jug3 = Var<Int>("jug3")
        let jug5 = Var<Int>("jug5")
        #VerifiedStateMachine {
            TypeName("DieHard")
            Variable(jug3, 0)
            Variable(jug5, 0)
            Act("Fill3") { next(jug3) == 3 }
            Act("Fill5") { next(jug5) == 5 }
            Act("Empty3") { next(jug3) == 0 }
            Act("Empty5") { next(jug5) == 0 }
        }

        var puzzle = DieHard.initial
        puzzle.apply(.fill5)
        puzzle.apply(.fill3)
        XCTAssertEqual(puzzle.jug3, 3)
        XCTAssertEqual(puzzle.jug5, 5)
    }
}
