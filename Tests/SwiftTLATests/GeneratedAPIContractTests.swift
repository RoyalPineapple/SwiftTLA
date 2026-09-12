import SwiftSyntaxBuilder
import Testing
@testable import SwiftTLAPlugin
@testable import SwiftTLA

@Suite("Generated Swift API contracts")
struct GeneratedAPIContractTests {
    @Test("Generated cases preserve readable names and disambiguate Swift identifiers")
    func generatedCaseNames() {
        let names = ["nodeA", "nodeB", "node-a", "node_a", "class", "init", "1"]
        #expect(GeneratedMachineAPI.generatedIdentifiers(names, fallback: "modelValue") == [
            "nodeA", "nodeB", "node_a", "node_a_2", "`class`", "modelValue_init", "modelValue_1"
        ])
    }

    @Test("formal collections compile without Swift API metadata")
    func formalCompilationDoesNotRequireSwiftAPITypes() throws {
        let specification = TLASpec("FormalCollection") {
            ModelCollectionDecl(name: "members", verificationScope: 2, initial: .int(0),
                generatedElementType: nil, generatedValueType: nil)
        }
        let compilation = try specification.compile()
        let initial = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
        let variable = try #require(compilation.layout.variables.first)
        let members = try #require(variable.collection?.members)
        #expect(try initial.value(for: variable.id) == .function(Dictionary(
            uniqueKeysWithValues: members.map { ($0, .integer(0)) })))
        #expect(throws: CompilationDiagnostic.self) {
            try GeneratedMachineAPI(layout: compilation.layout, actions: compilation.semantics.behavior.actions)
        }
    }

    @Test("raw formal values cannot enter a generated state")
    func rejectsRawFormalState() throws {
        let value = Var<TLAValue>("value")
        let specification = TLASpec("RawGeneratedState") { Variable(value, TLAValue.int(0)) }
        let compilation = try specification.compile()
        #expect(throws: CompilationDiagnostic.self) { try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation)) }
    }

    @Test("raw structured formal values cannot enter a generated state")
    func rejectsUntypedStructuredState() throws {
        let value = Var<TLAValue>("value")
        let specification = TLASpec("StructuredGeneratedState") { Variable(value, TLAValue.tuple([.int(0)])) }
        let compilation = try specification.compile()
        #expect(throws: CompilationDiagnostic.self) { try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation)) }
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
                _ = try CompiledProgram(inputs: SourceTypeResolver(metadata: .init(aliases: ["Raw": "TLAValue"])).resolve(in: compilation))
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
