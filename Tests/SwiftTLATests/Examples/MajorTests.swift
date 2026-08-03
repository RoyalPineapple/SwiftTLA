import XCTest
import SwiftTLA
import SwiftTLAExamples

final class MajorTests: XCTestCase {
    func testReachesTerminalState() throws {
        let graph = try ModelChecker(spec: MajorSpec.spec, maxStates: 100).exploreGraph()
        XCTAssertFalse(graph.states.isEmpty)
    }
}
