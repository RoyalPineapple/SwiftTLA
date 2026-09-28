import Testing
@testable import SwiftTLA

@Suite("Typed sequence mapping")
struct SequenceMappingTests {
    @Test("one-based mapping preserves order in compiled, generated, and rendered semantics")
    func oneBasedMapping() throws {
        let values: Expr<[Int]> = SequenceMapping(length: 3) { index in index.expr * 2 }
        #expect(try evaluateClosed(values.stateExpr) == .tuple([.int(2), .int(4), .int(6)]))

        let scenario = try #require(SequenceMappingFixture.validationScenarios().first)
        #expect(try scenario.evaluateAssumptions().satisfied)
        let rendered = try scenario.render().tlaBundle.tla
        #expect(rendered.contains("1..3"))
        #expect(rendered.contains("|->"))
    }
}
