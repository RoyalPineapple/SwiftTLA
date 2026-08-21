import Testing
@testable import SwiftTLA

@Suite("Generated machine surface planning")
struct GeneratedMachineSurfacePlanTests {
    @Test("raw formal values cannot enter a generated state")
    func rejectsRawFormalState() throws {
        let value = Var<TLAValue>("value")
        let compilation = try TLASpec("RawGeneratedState") {
            Variable(value, .int(0))
        }.compile()

        #expect(throws: GeneratedMachineSurfaceDiagnostic.self) {
            try MachineSurfacePlan(
                compilation: compilation,
                swiftFacts: .init(variableTypes: ["value": "TLAValue"])
            )
        }
    }

    @Test("structured formal values require a declared generated type")
    func rejectsUntypedStructuredState() throws {
        let value = Var<TLAValue>("value")
        let compilation = try TLASpec("StructuredGeneratedState") {
            Variable(value, .tuple([.int(0)]))
        }.compile()

        #expect(throws: GeneratedMachineSurfaceDiagnostic.self) {
            try MachineSurfacePlan(compilation: compilation)
        }
    }
}
