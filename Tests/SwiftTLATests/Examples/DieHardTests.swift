import XCTest
import SwiftTLA
import SwiftTLAExamples

final class DieHardTests: XCTestCase {
    func test16States() throws {
        let g = try ModelChecker(spec: DieHardSpec.spec).exploreGraph()
        XCTAssertEqual(g.states.count, 16)
    }
}
