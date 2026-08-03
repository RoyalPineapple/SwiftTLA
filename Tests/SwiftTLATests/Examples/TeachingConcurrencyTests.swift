import XCTest
import SwiftTLA
import SwiftTLAExamples

final class TeachingConcurrencyTests: XCTestCase {
    func testTwoProcessSafety() throws {
        let graph = try ModelChecker(spec: TeachingConcurrencySpec.spec, maxStates: 200).exploreGraph()
        XCTAssertFalse(graph.states.isEmpty, "Should have reachable states")
    }
}
