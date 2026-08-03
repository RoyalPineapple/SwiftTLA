import XCTest
import SwiftTLA
import SwiftTLAExamples

final class DieHardTests: XCTestCase {
    func testExactly16States() throws {
        let graph = try ModelChecker(spec: DieHardSpec.spec).exploreGraph()
        XCTAssertEqual(graph.states.count, DieHardSpec.expectedStates)
    }
}
