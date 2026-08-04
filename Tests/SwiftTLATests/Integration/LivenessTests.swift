import XCTest
@_spi(Internal) import SwiftTLA

final class LivenessTests: XCTestCase {
    func testAlwaysEventually() throws {
        let hr = Var<Int>("hr")
        let spec = TLASpec("Clock") {
            Variable(hr, 0)
            Action("Tick") {
                let inc: ActionExpr = (hr < 5) && (hr.next == hr + 1)
                let wrap: ActionExpr = (hr == 5) && (hr.next == 0)
                inc || wrap
            }
            Temporal("AlwaysEventually3", .alwaysEventually(hr == 3))
        }
        let graph = try ModelChecker(spec: spec, maxStates: 10).exploreGraph()
        let violations = try LivenessChecker(graph: graph, spec: spec).check()
        XCTAssertTrue(violations.isEmpty)
    }

    func testLivenessViolated() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Stuck") {
            Variable(x, 0)
            Action("Inc") { (x < 3) && (x.next == x + 1) }
            Temporal("AlwaysEventually4", .alwaysEventually(x == 4))
        }
        let graph = try ModelChecker(spec: spec, maxStates: 10).exploreGraph()
        let violations = try LivenessChecker(graph: graph, spec: spec).check()
        XCTAssertFalse(violations.isEmpty)
    }

    func testLeadsTo() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("LeadsTo") {
            Variable(x, 0)
            Action("Inc") { (x < 5) && (x.next == x + 1) }
            Temporal("FiveLeadsToTwo", .leadsTo(x == 5, x == 2))
        }
        let graph = try ModelChecker(spec: spec, maxStates: 10).exploreGraph()
        let violations = try LivenessChecker(graph: graph, spec: spec).check()
        XCTAssertFalse(violations.isEmpty)
    }

    func testFairnessFiltersViolation() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("FairClock") {
            Variable(x, 0)
            Action("Tick") { (x < 3) && (x.next == x + 1) }
            Action("Stutter") { x.next == x }
            Temporal("AlwaysEventually3", .alwaysEventually(x == 3))
            WeakFairness("Tick")
        }
        let graph = try ModelChecker(spec: spec, maxStates: 10).exploreGraph()
        let violations = try LivenessChecker(graph: graph, spec: spec).check()
        XCTAssertTrue(violations.isEmpty)
    }
}
