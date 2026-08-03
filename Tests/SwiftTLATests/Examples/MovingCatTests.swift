import XCTest
import SwiftTLA

final class MovingCatTests: XCTestCase {
    func testEvenBoxes24StatesFromSingleInit() throws {
        let cat_box = Var<Int>("cat_box")
        let observed_box = Var<Int>("observed_box")
        let direction = Var<Int>("direction")
        let n = 6

        let spec = TLASpec("Cat") {
            Variable(cat_box, 3)
            Variable(observed_box, 3)
            Variable(direction, 1)

            Act("Next") {
                let cL: ActionExpr = (cat_box > 1) && (next(cat_box) == cat_box - 1)
                let cR: ActionExpr = (cat_box < n) && (next(cat_box) == cat_box + 1)

                let oMR: ActionExpr = (direction == 1) && (observed_box < n - 1) && (next(observed_box) == observed_box + 1) && (next(direction) == direction)
                let oML: ActionExpr = (direction == 0) && (observed_box > 2) && (next(observed_box) == observed_box - 1) && (next(direction) == direction)
                let oRR: ActionExpr = (direction == 1) && (observed_box == n - 1) && (next(direction) == 0) && (next(observed_box) == observed_box)
                let oRL: ActionExpr = (direction == 0) && (observed_box == 2) && (next(direction) == 1) && (next(observed_box) == observed_box)

                (cL && oMR) || (cL && oML) || (cL && oRR) || (cL && oRL) ||
                (cR && oMR) || (cR && oML) || (cR && oRR) || (cR && oRL)
            }

            Inv("TypeOK") {
                let catRange: StateExpr = (cat_box >= 1) && (cat_box <= n)
                let obsRange: StateExpr = (observed_box >= 2) && (observed_box <= n - 1)
                let dirRange: StateExpr = (direction >= 0) && (direction <= 1)
                catRange && obsRange && dirRange
            }
        }

        let graph = try ModelChecker(spec: spec).exploreGraph()
        XCTAssertEqual(graph.states.count, 24, "Cat with N=6, single init (3,3,1) should have 24 reachable states (parity invariant restricts half)")
    }

    func testOddBoxes15StatesFromSingleInit() throws {
        let cat_box = Var<Int>("cat_box")
        let observed_box = Var<Int>("observed_box")
        let direction = Var<Int>("direction")
        let n = 5

        let spec = TLASpec("Cat") {
            Variable(cat_box, 3)
            Variable(observed_box, 3)
            Variable(direction, 1)

            Act("Next") {
                let cL: ActionExpr = (cat_box > 1) && (next(cat_box) == cat_box - 1)
                let cR: ActionExpr = (cat_box < n) && (next(cat_box) == cat_box + 1)

                let oMR: ActionExpr = (direction == 1) && (observed_box < n - 1) && (next(observed_box) == observed_box + 1) && (next(direction) == direction)
                let oML: ActionExpr = (direction == 0) && (observed_box > 2) && (next(observed_box) == observed_box - 1) && (next(direction) == direction)
                let oRR: ActionExpr = (direction == 1) && (observed_box == n - 1) && (next(direction) == 0) && (next(observed_box) == observed_box)
                let oRL: ActionExpr = (direction == 0) && (observed_box == 2) && (next(direction) == 1) && (next(observed_box) == observed_box)

                (cL && oMR) || (cL && oML) || (cL && oRR) || (cL && oRL) ||
                (cR && oMR) || (cR && oML) || (cR && oRR) || (cR && oRL)
            }

            Inv("TypeOK") {
                let catRange: StateExpr = (cat_box >= 1) && (cat_box <= n)
                let obsRange: StateExpr = (observed_box >= 2) && (observed_box <= n - 1)
                let dirRange: StateExpr = (direction >= 0) && (direction <= 1)
                catRange && obsRange && dirRange
            }
        }

        let graph = try ModelChecker(spec: spec).exploreGraph()
        XCTAssertEqual(graph.states.count, 15, "Cat with N=5, single init (3,3,1) should have 15 reachable states")
    }

    func testTypeOKInvariantHolds() throws {
        let cat_box = Var<Int>("cat_box")
        let observed_box = Var<Int>("observed_box")
        let direction = Var<Int>("direction")
        let n = 6

        let spec = TLASpec("Cat") {
            Variable(cat_box, 3)
            Variable(observed_box, 3)
            Variable(direction, 1)

            Act("Next") {
                let cL: ActionExpr = (cat_box > 1) && (next(cat_box) == cat_box - 1)
                let cR: ActionExpr = (cat_box < n) && (next(cat_box) == cat_box + 1)

                let oMR: ActionExpr = (direction == 1) && (observed_box < n - 1) && (next(observed_box) == observed_box + 1) && (next(direction) == direction)
                let oML: ActionExpr = (direction == 0) && (observed_box > 2) && (next(observed_box) == observed_box - 1) && (next(direction) == direction)
                let oRR: ActionExpr = (direction == 1) && (observed_box == n - 1) && (next(direction) == 0) && (next(observed_box) == observed_box)
                let oRL: ActionExpr = (direction == 0) && (observed_box == 2) && (next(direction) == 1) && (next(observed_box) == observed_box)

                (cL && oMR) || (cL && oML) || (cL && oRR) || (cL && oRL) ||
                (cR && oMR) || (cR && oML) || (cR && oRR) || (cR && oRL)
            }

            Inv("TypeOK") {
                let catRange: StateExpr = (cat_box >= 1) && (cat_box <= n)
                let obsRange: StateExpr = (observed_box >= 2) && (observed_box <= n - 1)
                let dirRange: StateExpr = (direction >= 0) && (direction <= 1)
                catRange && obsRange && dirRange
            }
        }

        let result = try ModelChecker(spec: spec).check()
        if case .ok = result { } else { XCTFail("TypeOK should hold") }
    }
}
