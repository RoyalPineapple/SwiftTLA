import Testing
@testable import SwiftTLA

@Suite("Generated machine surface planning")
struct GeneratedMachineSurfacePlanTests {
    @Test("raw formal values cannot enter a generated state")
    func rejectsRawFormalState() throws {
        let value = Var<TLAValue>("value")
        #expect(throws: CompilationDiagnostic.self) {
            try TLASpec("RawGeneratedState") {
                Variable(value, TLAValue.int(0))
            }.compile()
        }
    }

    @Test("structured formal values require a declared generated type")
    func rejectsUntypedStructuredState() throws {
        let value = Var<TLAValue>("value")
        #expect(throws: CompilationDiagnostic.self) {
            try TLASpec("StructuredGeneratedState") {
                Variable(value, TLAValue.tuple([.int(0)]))
            }.compile()
        }
    }
}
