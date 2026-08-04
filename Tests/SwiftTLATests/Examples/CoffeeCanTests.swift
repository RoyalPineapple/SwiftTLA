import XCTest
import SwiftTLA
import SwiftTLAExamples

final class CoffeeCanTests: XCTestCase {
    func testParityPreserved() throws {
        let result = try ModelChecker(spec: CoffeeCanSpec.spec, maxStates: 10_000).check()
        if case .invariantViolated = result { XCTFail("Parity should hold") }
    }
}
