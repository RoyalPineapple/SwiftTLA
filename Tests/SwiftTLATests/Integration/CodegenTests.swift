import XCTest
@_spi(Internal) import SwiftTLA
@_spi(Internal) import SwiftTLAGenerator

final class CodegenTests: XCTestCase {
    func testStateMachineGeneration() throws {
        let x = Var<Int>("x")
        let spec = TLASpec("Toggle") {
            Variable(x, 0)
            Action("Flip") { x.prime == (x + 1) % 2 }
        }
        let graph = try ModelChecker(spec: spec, maxStates: 10).exploreGraph()
        let code = try StateMachineGenerator(graph: graph).generate()
        XCTAssertTrue(code.contains("struct Toggle"))
        XCTAssertTrue(code.contains("enum Action"))
        XCTAssertTrue(code.contains("transitions"))
    }

    func testCodableRoundtrip() throws {
        let spec = TLASpec("Test") {
            Variable(Var<Int>("x"), 0)
            Action("Inc") { prime(Var<Int>("x")) == Var<Int>("x") + 1 }
            Invariant("GE0") { Var<Int>("x") >= 0 }
        }
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(TLASpec.self, from: data)
        XCTAssertEqual(decoded.name, "Test")
    }
}
