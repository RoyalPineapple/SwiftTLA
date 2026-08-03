import XCTest
import SwiftTLA
import SwiftTLAExamples

final class HourClockTests: XCTestCase {
    func testExactly12States() throws {
        let graph = try ModelChecker(spec: HourClockSpec.spec, maxStates: 20).exploreGraph()
        XCTAssertEqual(graph.states.count, HourClockSpec.expectedStates)
    }
    func testTLAOutputValid() {
        XCTAssertTrue(HourClockSpec.spec.description.contains("VARIABLES hr"))
    }
}
