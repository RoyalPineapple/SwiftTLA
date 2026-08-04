import XCTest
import SwiftTLA

final class CompositionTests: XCTestCase {
    func testExtendsMergesSpecs() throws {
        let x = Var<Int>("x")
        let y = Var<Int>("y")

        let specA = TLASpec("A") {
            Variable(x, 0)
            Act("IncX") { x.next == x + 1 }
            Invariant("XNonNeg") { x >= 0 }
        }

        let specB = TLASpec("B") {
            Variable(y, 0)
            Act("IncY") { y.next == y + 1 }
            Invariant("YNonNeg") { y >= 0 }
        }

        let composed = specA.extending(specB)
        let graph = try ModelChecker(spec: composed, maxStates: 100).exploreGraph()

        XCTAssertFalse(graph.states.isEmpty)
        XCTAssertEqual(composed.variables.count, 2)
        XCTAssertEqual(composed.actions.count, 2)
        XCTAssertEqual(composed.invariants.count, 2)
    }

    func testInstanceSubstitutesConstants() throws {
        let spec = TLASpec("Param") {
            Variable(Var<Int>("x"), TLAValue.constant("N"))
            Constant("N", 5)
            Act("Inc") { next(Var<Int>("x")) == Var<Int>("x") + 1 }
            Invariant("Positive") { Var<Int>("x") >= 0 }
        }

        let instantiated = spec.instantiating(["N": TLAValue.int(3)])
        let graph = try ModelChecker(spec: instantiated, maxStates: 10).exploreGraph()
        XCTAssertFalse(graph.states.isEmpty)
    }

    func testComposedWithConstraints() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Bounded") {
            Variable(x, 0)
            Act("Inc") { x.next == x + 1 }
        }

        let bounded = spec.extending(TLASpec("Bounds") {
            Variable(Var<Int>("dummy"), 0)
            Invariant("Below10") { x < 10 }
        })

        let result = try ModelChecker(spec: bounded, maxStates: 20).check()
        if case .invariantViolated(let inv, _, _) = result {
            XCTAssertEqual(inv, "Below10")
        } else { XCTFail("Should violate x < 10") }
    }
}
