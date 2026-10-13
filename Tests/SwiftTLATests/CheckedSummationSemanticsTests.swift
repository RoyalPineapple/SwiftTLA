import SwiftTLA
import Testing

@Suite("Checked summation semantics")
struct CheckedSummationSemanticsTests {
    @Test("Generated Swift and TLA both report an overflowing sum")
    func overflowingSumHasMatchedFailure() throws {
        let machine = try CheckedSummationOverflowModel.makeMachine()
        #expect(throws: NativeMachineEvaluationError.integerOverflow(
            .summation, operands: [1, 1, 9223372036854775807]
        )) {
            try machine.successors(for: .sum)
        }

        let rendered = try CheckedSummationOverflowModel.render()
        #expect(rendered.intrinsicInvariantNames.contains("__SwiftTLAEvaluationOK"))
        let declarations = rendered.tlaBundle.root.tla.split(separator: "\n")
        let failure = try #require(declarations.first { $0.hasPrefix("__SwiftTLAOverflowFailure0 ==") })
        let operands = try #require(declarations.first { $0.hasPrefix("__SwiftTLAOverflowOperands0 ==") })
        #expect(failure.contains("SumFunctionOnSet(values"))
        #expect(failure.contains(TLAValue.int(Int.max).description))
        #expect(operands.contains("CHOOSE __SwiftTLASum_candidate"))
        #expect(operands.contains("Cardinality("))
        #expect(declarations.contains("__SwiftTLAOverflowOperation0 == \"summation\""))
    }
}
