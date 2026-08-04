import XCTest
import SwiftTLA
import SwiftTLAExamples

final class HourClockTests: XCTestCase {
    func test12States() throws {
        let g = try ModelChecker(spec: HourClockSpec.spec, maxStates: 20).exploreGraph()
        XCTAssertEqual(g.states.count, 12)
    }
    func testTLAOutput() {
        let tla = HourClockSpec.spec.description
        XCTAssertTrue(tla.contains("VARIABLES hr"))
        XCTAssertTrue(tla.contains("hr' = (hr + 1)"))
    }
}
