import XCTest
import SwiftTLA
import SwiftTLAExamples

final class MovingCatTests: XCTestCase {
    func testExactly24States() throws {
        let graph = try ModelChecker(spec: MovingCatSpec.spec, maxStates: 100).exploreGraph()
        XCTAssertEqual(graph.states.count, MovingCatSpec.expectedStates)
    }
}
