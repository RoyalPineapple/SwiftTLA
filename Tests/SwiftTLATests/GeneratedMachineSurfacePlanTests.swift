import Testing
@testable import SwiftTLA

@Suite("Generated machine surface planning")
struct GeneratedMachineSurfacePlanTests {
    @Test("raw formal values cannot enter a generated state")
    func rejectsRawFormalState() throws {
        let value = Var<TLAValue>("value")
        let specification = TLASpec("RawGeneratedState") { Variable(value, TLAValue.int(0)) }
        let compilation = try specification.compile()
        #expect(throws: CompilationDiagnostic.self) { try NativeResolvedProgram(compilation: compilation) }
    }

    @Test("raw structured formal values cannot enter a generated state")
    func rejectsUntypedStructuredState() throws {
        let value = Var<TLAValue>("value")
        let specification = TLASpec("StructuredGeneratedState") { Variable(value, TLAValue.tuple([.int(0)])) }
        let compilation = try specification.compile()
        #expect(throws: CompilationDiagnostic.self) { try NativeResolvedProgram(compilation: compilation) }
    }

    @Test("raw formal values are rejected through qualification, aliases, and containers")
    func rawStateCannotHideInsideDeclaredTypes() throws {
        let declarations: [(String, TLAValue)] = [
            ("SwiftTLA.TLAValue", .int(0)),
            ("Raw", .int(0)),
            ("Set<Raw>", .set([.int(0)])),
            ("[String: TLAValue]", .function([.string("key"): .int(0)]))
        ]
        for (type, initial) in declarations {
            let compilation = try TLASpec(name: "RawState", variables: [
                .init(name: "value", initialization: .value(initial), generatedSwiftType: type, origin: .compiler)
            ], actions: [], invariants: []).compile()
            do {
                _ = try NativeResolvedProgram(compilation: compilation, sourceTypes: .init(aliases: ["Raw": "TLAValue"]))
                Issue.record("Generated state admitted raw formal type: \(type)")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.actual.contains("raw TLAValue"))
            }
        }
    }

    @Test("duplicate typed action parameters produce a compilation diagnostic")
    func rejectsDuplicateTypedActionParameters() {
        let worker = ActionParameter("worker", values: [1, 2])
        let specification = TLASpec("DuplicateTypedActionParameter") {
            Action("advance", parameters: [worker, worker]) {
                StateExpr.bool(true)
            }
        }

        #expect(throws: CompilationDiagnostic.self) {
            try specification.compile()
        }
    }
}
