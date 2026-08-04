import XCTest
@_spi(Internal) import SwiftTLA
@_spi(Internal) import SwiftTLAExamples

final class AttachedMacroTests: XCTestCase {
    
    func testHourClockViaSpec() throws {
        let graph = try ModelChecker(spec: HourClockSpec.spec, maxStates: 20).exploreGraph()
        XCTAssertEqual(graph.states.count, 12)
    }
    
    func testDieHardViaSpec() throws {
        let graph = try ModelChecker(spec: DieHardSpec.spec).exploreGraph()
        XCTAssertEqual(graph.states.count, 16)
    }
    
    func testCoffeeCanViaSpec() throws {
        let result = try ModelChecker(spec: CoffeeCanSpec.spec, maxStates: 10_000).check()
        if case .invariantViolated = result { XCTFail("Parity invariant should hold") }
    }
    
    func testAllExamplesInRegistry() {
        XCTAssertGreaterThanOrEqual(Examples.all.count, 16)
        for ex in Examples.all {
            XCTAssertFalse(ex.spec.description.isEmpty, ex.name)
        }
    }
    
    func testVariableExtraction() {
        let hr = Var<Int>("hr")
        let spec = TLASpec("Test") { Variable(hr, 5) }
        XCTAssertEqual(spec.variables.first?.initial, .int(5))
    }
    
    func testActionWithGuard() {
        let x = Var<Int>("x")
        let spec = TLASpec("Test") {
            Variable(x, 0)
            Action("Inc") { (x < 3) && (x.next == x + 1) }
        }
        let graph = try! ModelChecker(spec: spec, maxStates: 10).exploreGraph()
        XCTAssertEqual(graph.states.count, 4)
    }
    
    func testInvariantViolationCaught() {
        let x = Var<Int>("x")
        let spec = TLASpec("Test") {
            Variable(x, 0)
            Action("Dec") { x.next == x - 1 }
            Invariant("NonNeg") { x >= 0 }
        }
        let result = try! ModelChecker(spec: spec, maxStates: 10).check()
        if case .invariantViolated = result { } else { XCTFail("Should catch violation") }
    }
    
    func testTLAOutputValidSyntax() {
        for ex in Examples.all {
            let tla = ex.spec.description
            XCTAssertTrue(tla.contains("VARIABLES") || tla.contains("Spec"), ex.name)
        }
    }
}
