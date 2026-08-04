import XCTest
import SwiftTLA
import SwiftTLAExamples

final class ExampleTests: XCTestCase {
    func testStateCounts() throws {
        for ex in Examples.all {
            let graph = try ModelChecker(spec: ex.spec, maxStates: 10_000).exploreGraph()
            if ex.expectedStates > 0 {
                XCTAssertEqual(graph.states.count, ex.expectedStates, ex.name)
            } else {
                XCTAssertFalse(graph.states.isEmpty, ex.name)
            }
        }
    }

    func testTLAOutput() {
        for ex in Examples.all {
            XCTAssertTrue(ex.spec.description.contains("VARIABLES"), ex.name)
        }
    }
}
