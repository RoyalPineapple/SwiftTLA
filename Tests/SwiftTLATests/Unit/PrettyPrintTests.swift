import XCTest
@_spi(Internal) import SwiftTLA
@_spi(Internal) import SwiftTLAGenerator

final class PrettyPrintTests: XCTestCase {

    func testSimpleAssign() {
        let x = Var<Int>("x")
        let spec = TLASpec("Simple") {
            Variable(x, 0)
            Action("Inc") { x.next == x + 1 }
        }
        let actual = spec.annotatedDescription
        XCTAssertTrue(actual.contains("var x = Var(\"x\", 0)"))
        XCTAssertTrue(actual.contains("func inc()"))
        XCTAssertTrue(actual.contains("x.next == x + 1"))
    }

    func testStays() {
        let x = Var<Int>("x")
        let spec = TLASpec("Stays") {
            Variable(x, 0)
            Action("Nop") { x.stays }
        }
        let actual = spec.annotatedDescription
        XCTAssertTrue(actual.contains("x.stays"))
    }

    func testCompoundActionWithOr() {
        let jug3 = Var<Int>("jug3")
        let jug5 = Var<Int>("jug5")
        let spec = TLASpec("Pour") {
            Variable(jug3, 0); Variable(jug5, 0)
            Action("Pour3to5") {
                (jug3 + jug5 <= 5) && (jug5.next == jug3 + jug5) && (jug3.next == 0)
                || (!(jug3 + jug5 <= 5)) && (jug5.next == 5) && (jug3.next == jug3 - (5 - jug5))
            }
        }
        let actual = spec.annotatedDescription
        XCTAssertTrue(actual.contains("jug3 + jug5 <= 5"))
        XCTAssertTrue(actual.contains("||"))
        XCTAssertTrue(actual.contains("jug5.next == 5"))
    }

    func testInvariant() {
        let x = Var<Int>("x")
        let spec = TLASpec("Inv") {
            Variable(x, 0)
            Action("Inc") { x.next == x + 1 }
            Invariant("NonNeg") { x >= 0 }
        }
        let actual = spec.annotatedDescription
        XCTAssertTrue(actual.contains("var nonneg: StateExpr"))
        XCTAssertTrue(actual.contains("x >= 0"))
    }

    func testTLADescription() {
        let x = Var<Int>("x")
        let spec = TLASpec("TLATest") {
            Variable(x, 0)
            Action("Inc") { x.next == x + 1 }
        }
        let actual = spec.tlaDescription
        XCTAssertTrue(actual.contains("---- MODULE TLATest ----"))
        XCTAssertTrue(actual.contains("VARIABLES x"))
        XCTAssertTrue(actual.contains("Init =="))
        XCTAssertTrue(actual.contains("Inc =="))
        XCTAssertTrue(actual.contains("Next =="))
        XCTAssertTrue(actual.contains("===="))
    }

    func testMultipleVariables() {
        let x = Var<Int>("x")
        let y = Var<Int>("y")
        let spec = TLASpec("Multi") {
            Variable(x, 5); Variable(y, 10)
            Action("Swap") {
                x.next == y && y.next == x
            }
        }
        let actual = spec.annotatedDescription
        XCTAssertTrue(actual.contains("var x = Var(\"x\", 5)"))
        XCTAssertTrue(actual.contains("var y = Var(\"y\", 10)"))
        XCTAssertTrue(actual.contains("x.next == y"))
        XCTAssertTrue(actual.contains("y.next == x"))
    }

    func testEmptyNameActionsExcludedFromTLA() {
        let x = Var<Int>("x")
        let spec = TLASpec("Hidden") {
            Variable(x, 0)
            Action("") { x.stays }
        }
        let actual = spec.tlaDescription
        XCTAssertFalse(actual.contains("=="))
    }

    func testStructNameSpaceStripping() {
        let x = Var<Int>("x")
        let spec = TLASpec("My Spec", variables: [NamedVar(name: "x", initial: .int(0))], actions: [], invariants: [])
        let actual = spec.annotatedDescription
        XCTAssertTrue(actual.contains("struct MySpec"))
    }
}
