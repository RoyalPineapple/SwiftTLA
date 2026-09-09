import Testing
@testable import SwiftTLA

@Suite struct NativeTypeDiagnosticTests {
    @Test("Incomplete inference identifies the missing field type without an internal expression dump")
    func missingCollectionElement() throws {
        let specification = TLASpec(name: "MissingElementType", variables: [
            .init(name: "accumulator", initialization: .expression(
                .recordLiteral(.init(["execution": .tupleLiteral([])]))), origin: .compiler)
        ], actions: [], invariants: [])
        do {
            _ = try NativeResolvedProgram(plan: .init(compilation: specification.compile()))
            Issue.record("An unresolved element type must not reach Swift emission")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unresolvedGeneratedValueShape)
            #expect(diagnostic.path == "nativeMachine.variables.accumulator")
            #expect(diagnostic.actual == "type inference could not determine value.execution.element")
            #expect(!diagnostic.description.contains("BinderID"))
        }
    }
}
