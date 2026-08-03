import XCTest
import SwiftTLA

final class TeachingConcurrencyTests: XCTestCase {
    func testTwoProcessSafety() throws {
        let N = 2
        let x = Var<TLASet>("x")
        let y = Var<TLASet>("y")
        
        let spec = TLASpec("Simple") {
            Variable(x, .functionLiteral(.setLiteral((0..<N).map { .int($0) }), .int(0)))
            Variable(y, .functionLiteral(.setLiteral((0..<N).map { .int($0) }), .int(0)))
            
            for i in 0..<N {
                Act("a\(i)") {
                    let step: ActionExpr = functionApply(x, .int(i)) == 0
                        && (next(x) == except(x, at: .int(i), value: .int(1)))
                        && (next(y) == y)
                    step
                }
                Act("b\(i)") {
                    let prev = (i - 1 + N) % N
                    let step: ActionExpr = functionApply(x, .int(i)) == 1
                        && (next(y) == except(y, at: .int(i), value: functionApply(x, .int(prev))))
                        && (next(x) == x)
                    step
                }
            }
            
            Inv("AtLeastOneYisOne") {
                forAll(x, .lessThan(.variable("_q"), .int(1)))
                || exists(y, .equal(.variable("_q"), .int(1)))
            }
        }
        
        let graph = try ModelChecker(spec: spec, maxStates: 100).exploreGraph()
        XCTAssertFalse(graph.states.isEmpty, "Teaching concurrency should have reachable states")
    }
}
