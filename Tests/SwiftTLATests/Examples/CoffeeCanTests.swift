import XCTest
import SwiftTLA
import SwiftTLAExamples

final class CoffeeCanTests: XCTestCase {
    func testStateSpace() throws {
        let result = try ModelChecker(spec: CoffeeCanSpec.spec, maxStates: 10_000).check()
        if case .ok(let count) = result { XCTAssertGreaterThan(count, 0) }
        else { XCTFail("Should not violate invariants") }
    }
}
