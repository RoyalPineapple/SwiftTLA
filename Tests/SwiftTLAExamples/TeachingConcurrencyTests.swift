import XCTest
import SwiftTLA

final class TeachingConcurrencyTests: XCTestCase {
    func testSimpleN5_723States() throws {
        let x0 = Var<Int>("x0"); let y0 = Var<Int>("y0"); let pc0 = Var<Int>("pc0")
        let x1 = Var<Int>("x1"); let y1 = Var<Int>("y1"); let pc1 = Var<Int>("pc1")
        let x2 = Var<Int>("x2"); let y2 = Var<Int>("y2"); let pc2 = Var<Int>("pc2")
        let x3 = Var<Int>("x3"); let y3 = Var<Int>("y3"); let pc3 = Var<Int>("pc3")
        let x4 = Var<Int>("x4"); let y4 = Var<Int>("y4"); let pc4 = Var<Int>("pc4")

        let spec = TLASpec("TeachingConcurrency") {
            Variable(x0, 0); Variable(y0, 0); Variable(pc0, 0)
            Variable(x1, 0); Variable(y1, 0); Variable(pc1, 0)
            Variable(x2, 0); Variable(y2, 0); Variable(pc2, 0)
            Variable(x3, 0); Variable(y3, 0); Variable(pc3, 0)
            Variable(x4, 0); Variable(y4, 0); Variable(pc4, 0)

            Act("Process") {
                let a0: ActionExpr = (pc0 == 0) && (next(x0) == 1) && (next(pc0) == 1)
                let a1: ActionExpr = (pc1 == 0) && (next(x1) == 1) && (next(pc1) == 1)
                let a2: ActionExpr = (pc2 == 0) && (next(x2) == 1) && (next(pc2) == 1)
                let a3: ActionExpr = (pc3 == 0) && (next(x3) == 1) && (next(pc3) == 1)
                let a4: ActionExpr = (pc4 == 0) && (next(x4) == 1) && (next(pc4) == 1)

                let b0: ActionExpr = (pc0 == 1) && (next(y0) == x4) && (next(pc0) == 2)
                let b1: ActionExpr = (pc1 == 1) && (next(y1) == x0) && (next(pc1) == 2)
                let b2: ActionExpr = (pc2 == 1) && (next(y2) == x1) && (next(pc2) == 2)
                let b3: ActionExpr = (pc3 == 1) && (next(y3) == x2) && (next(pc3) == 2)
                let b4: ActionExpr = (pc4 == 1) && (next(y4) == x3) && (next(pc4) == 2)

                a0 || a1 || a2 || a3 || a4 || b0 || b1 || b2 || b3 || b4
            }
        }

        let graph = try ModelChecker(spec: spec, maxStates: 2000).exploreGraph()
        XCTAssertEqual(graph.states.count, 723, "TeachingConcurrency Simple N=5 must have 723 states")
    }
}
