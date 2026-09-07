@testable import SwiftTLA
import Testing

struct SymmetryRecordFieldTests {
    @Test("Symmetry preserves record field names while permuting their values")
    func recordLabelsRemainFixedAcrossMemberPermutations() throws {
        let compilation = try TLASpec(
            name: "RecordFieldPermutation",
            variables: [.init(name: "value", initialization: .value(.record(["a": .string("b")])), origin: .compiler)],
            actions: [], invariants: [],
            symmetrySets: [.init(variableName: "Members", values: [.string("a"), .string("b")])]
        ).compile()
        let plan = try SymmetryPlan(compilation: compilation, reduction: .enabled(maximumPermutationCount: 2))
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let canonical = try plan.canonicalState(initial)
        let field = try canonical.value(for: compilation.layout.variables[0].id).rendered(using: compilation.layout)
        guard case .record(let record) = field else {
            Issue.record("Expected the record to remain a record")
            return
        }
        #expect(record.fields.map(\.name) == ["a"])
        #expect(record.fields.map(\.value) == [.string("a")])
        let renamed = try CompiledState(values: [.init(formal: .record(["a": .string("a")]))], compilation: compilation)
        #expect(try plan.canonicalState(renamed) == canonical)
    }
}
