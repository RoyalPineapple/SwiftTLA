import XCTest
import SwiftTLA

final class HourClockTests: XCTestCase {
    func testExactly12States() throws {
        let hr = Var<Int>("hr")
        let spec = TLASpec("HourClock") {
            Variable(hr, 1)
            Act("Tick") {
                let inc: ActionExpr = (hr >= 1) && (hr <= 11) && (next(hr) == hr + 1)
                let wrap: ActionExpr = (hr == 12) && (next(hr) == 1)
                inc || wrap
            }
            Inv("ValidHour") { (hr >= 1) && (hr <= 12) }
        }
        let graph = try ModelChecker(spec: spec, maxStates: 20).exploreGraph()
        XCTAssertEqual(graph.states.count, 12, "HourClock must have exactly 12 reachable states")
    }

    func testInvariantHolds() throws {
        let hr = Var<Int>("hr")
        let spec = TLASpec("HourClock") {
            Variable(hr, 1)
            Act("Tick") {
                let inc: ActionExpr = (hr >= 1) && (hr <= 11) && (next(hr) == hr + 1)
                let wrap: ActionExpr = (hr == 12) && (next(hr) == 1)
                inc || wrap
            }
            Inv("Never13") { hr != 13 }
        }
        let result = try ModelChecker(spec: spec, maxStates: 20).check()
        if case .ok(let count) = result { XCTAssertEqual(count, 12) }
        else { XCTFail("Expected OK") }
    }
}
