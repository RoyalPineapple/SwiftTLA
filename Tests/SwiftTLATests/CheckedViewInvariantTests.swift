import Foundation
@testable import SwiftTLA
import Testing

@Suite("Checked record views in invariant predicates")
struct CheckedViewInvariantTests {
    @Test("Selected predicates retain skipped reads and the first reached error")
    func firstFailure() throws {
        var machine = try CheckedViewInvariantMachine.makeMachine()
        #expect(try machine.violatedInvariants(atLevel: 0).isEmpty)
        try machine.send(.zero)
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.violatedInvariants(checking: [.EarlierFailure], atLevel: 1)
        }
        try machine.send(.replace)
        #expect(try machine.violatedInvariants(checking: [.ShortCircuit], atLevel: 2).isEmpty)
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            try machine.violatedInvariants(checking: [.WithinLimit], atLevel: 2)
        }
    }

    @Test("A view in a skipped branch cannot justify a later read")
    func skippedViewCannotBeReused() throws {
        let compiled = try CheckedViewInvariantMachine.spec.compile()
        let property = try #require(compiled.semantics.behavior.invariants.first { $0.name == "WithinLimit" })
        let predicate = property.predicate.expression
        let renderer = CompiledTLARenderer(moduleName: "CheckedViewInvariantMachine", reservedNames: [],
            layout: compiled.layout, bindings: compiled.bindings, operators: compiled.semantics.operators,
            actions: [], functions: [])
        // On the replaced state the left arm succeeds without checking the record.
        let skipped = CompiledExpression(operation: .or, resultType: .bool,
            children: [.value(.boolean(true)), predicate.children[0]])
        let required = CompiledExpression(operation: .and, resultType: .bool,
            children: [skipped, predicate.children[1]])
        #expect(try renderer.invariantPredicate(required) == renderer.state(required))
    }

    @Test("The invariant proof uses the model the compiler exports")
    func proofInput() throws {
        let model = try CheckedViewInvariantMachine.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/CheckedViewInvariantMachine.tla")
        #expect(model == (try String(contentsOf: proofInput, encoding: .utf8)))
    }
}
