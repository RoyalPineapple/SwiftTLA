import XCTest
import SwiftTLA

final class CoffeeCanTests: XCTestCase {
    func testWhiteParityPreserved() throws {
        let black = Var<Int>("black")
        let white = Var<Int>("white")
        let maxBeans = 5
        let spec = TLASpec("CoffeeCan") {
            Variable(black, maxBeans)
            Variable(white, maxBeans)
            Act("RemoveTwoBlack") { (black >= 2) && (next(black) == black - 1) && (next(white) == white) }
            Act("RemoveTwoWhite") { (white >= 2) && (next(white) == white - 2) && (next(black) == black + 1) }
            Act("RemoveOneEach") { (black >= 1) && (white >= 1) && (next(white) == white - 1) && (next(black) == black) }
            Inv("Parity") { (white % 2) == (maxBeans % 2) }
        }
        let result = try ModelChecker(spec: spec, maxStates: 10_000).check()
        if case .ok(let count) = result { XCTAssertGreaterThan(count, 0) }
        else if case .invariantViolated = result { XCTFail("Parity should be preserved") }
    }
}
