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

    @Test("Expression failures report the operation without dumping nested payloads")
    func expressionFailureIdentifiesOperation() throws {
        let specification = TLASpec(name: "InvalidOperand", variables: [
            .init(name: "count", initialization: .value(.int(0)), origin: .compiler)
        ], actions: [], invariants: [])
        let inference = try NativeTypeInference(plan: .init(compilation: specification.compile()))
        let payload = String(repeating: "private-expression-payload", count: 1_000)
        let expression = CompiledStateExpr.add(.value(.string(payload)), .value(.integer(1)))
        do {
            _ = try inference.resolutionScope(expression, expected: .int)
            Issue.record("String operands must not be accepted as integers")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasSuffix(" <- value <- add"))
            #expect(!diagnostic.description.contains(payload))
            #expect(!diagnostic.description.contains("CompiledStateExpr"))
        }
    }

}
