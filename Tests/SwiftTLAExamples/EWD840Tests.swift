import XCTest
import SwiftTLA

final class EWD840Tests: XCTestCase {
    func testN3_302States() throws {
        let active0 = Var<Int>("active0"); let active1 = Var<Int>("active1"); let active2 = Var<Int>("active2")
        let color0 = Var<Int>("color0"); let color1 = Var<Int>("color1"); let color2 = Var<Int>("color2")
        let tpos = Var<Int>("tpos")
        let tcolor = Var<Int>("tcolor")

        // Unique value ranges per variable to prevent symmetry reduction cross-interference
        let spec = TLASpec("EWD840") {
            Variable(active0, set([0, 1]))
            Variable(active1, set([2, 3]))
            Variable(active2, set([4, 5]))
            Variable(color0, set([6, 7]))
            Variable(color1, set([8, 9]))
            Variable(color2, set([10, 11]))
            Variable(tpos, set([12, 13, 14]))
            Variable(tcolor, 16)

            Act("Next") {
                let probe: ActionExpr = (tpos == 12) && (tcolor == 16 || color0 == 7)
                    && (next(tpos) == 14) && (next(tcolor) == 15) && (next(color0) == 6)

                let pass1Black: ActionExpr = (tpos == 13) && (active1 == 2 || color1 == 9 || tcolor == 16) && (color1 == 9)
                    && (next(tpos) == 12) && (next(tcolor) == 16) && (next(color1) == 8)
                let pass1White: ActionExpr = (tpos == 13) && (active1 == 2 || color1 == 9 || tcolor == 16) && (color1 == 8)
                    && (next(tpos) == 12) && (next(color1) == 8)

                let pass2Black: ActionExpr = (tpos == 14) && (active2 == 4 || color2 == 11 || tcolor == 16) && (color2 == 11)
                    && (next(tpos) == 13) && (next(tcolor) == 16) && (next(color2) == 10)
                let pass2White: ActionExpr = (tpos == 14) && (active2 == 4 || color2 == 11 || tcolor == 16) && (color2 == 10)
                    && (next(tpos) == 13) && (next(color2) == 10)

                let send0_1: ActionExpr = (active0 == 1) && (next(active1) == 3) && (next(color0) == 7)
                let send0_2: ActionExpr = (active0 == 1) && (next(active2) == 5) && (next(color0) == 7)

                let send1_0: ActionExpr = (active1 == 3) && (next(active0) == 1)
                let send1_2: ActionExpr = (active1 == 3) && (next(active2) == 5) && (next(color1) == 9)

                let send2_0: ActionExpr = (active2 == 5) && (next(active0) == 1)
                let send2_1: ActionExpr = (active2 == 5) && (next(active1) == 3)

                let deact0: ActionExpr = (active0 == 1) && (next(active0) == 0)
                let deact1: ActionExpr = (active1 == 3) && (next(active1) == 2)
                let deact2: ActionExpr = (active2 == 5) && (next(active2) == 4)

                probe || pass1Black || pass1White || pass2Black || pass2White
                    || send0_1 || send0_2 || send1_0 || send1_2 || send2_0 || send2_1
                    || deact0 || deact1 || deact2
            }
        }

        let graph = try ModelChecker(spec: spec, maxStates: 500).exploreGraph()
        XCTAssertEqual(graph.states.count, 302, "EWD840 N=3 must have 302 states")
    }
}
