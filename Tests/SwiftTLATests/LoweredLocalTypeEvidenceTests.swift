import Testing
@testable import SwiftTLA

@Suite("Lowered local state retains declared Swift types")
struct LoweredLocalTypeEvidenceTests {
    private enum Process: Int, FiniteTLAValueDomain {
        case one = 1, two = 2
        static var defaultValue: Self { .one }
        static let finiteValues: [Self] = [.one, .two]
    }
    private enum Step: String, CaseIterable { case start, enter, done }
    private enum Routine: String, CaseIterable { case work }

    @Test("Process local and procedure slots retain domain and value types")
    func processSlotsRetainDeclaredTypes() throws {
        let algorithm = Algorithm("ProcessLocalTypes", scoped: { scope in
            let output = scope.sharedVar("output", initial: 0)
            Procedure(Routine.work, parameters: Int.self, scoped: { value, scope in
                let offset = scope.localVar("offset", initial: 1)
                Do(Step.enter) {
                    Assign(output, to: value.expr + offset.expr)
                    Return()
                }
            })
            Each(Process.all, scoped: { _, scope in
                let selected = scope.localVar("selected", initial: Process.one)
                Do(Step.start) {
                    Assign(selected, to: Process.two)
                    Call(Routine.work, with: 7)
                }
                Do(Step.done) { Stop() }
            })
        })
        let compilation = try TLASpec("ProcessLocalTypes") { algorithm }.compile()
        #expect(try type(of: "selected", in: compilation) == "[Process: Process]")
        #expect(try type(of: "parameter0", in: compilation) == "[Process: Int]")
        #expect(try type(of: "offset", in: compilation) == "[Process: Int]")
    }

    @Test("Sequential procedure slots retain scalar value types")
    func sequentialSlotsRetainDeclaredTypes() throws {
        let algorithm = Algorithm("SequentialLocalTypes", scoped: { scope in
            let output = scope.sharedVar("output", initial: 0)
            Procedure(Routine.work, parameters: Int.self, scoped: { value, scope in
                let offset = scope.localVar("offset", initial: 1)
                Do(Step.enter) {
                    Assign(output, to: value.expr + offset.expr)
                    Return()
                }
            })
            Do(Step.start) { Call(Routine.work, with: 7) }
            Do(Step.done) { Stop() }
        })
        let compilation = try TLASpec("SequentialLocalTypes") { algorithm }.compile()
        #expect(try type(of: "parameter0", in: compilation) == "Int")
        #expect(try type(of: "offset", in: compilation) == "Int")
    }

    private func type(of name: String, in compilation: CompiledSpecification) throws -> String {
        let variable = try #require(compilation.layout.variables.first { $0.declaration.name == name })
        return try #require(variable.generatedSwiftType)
    }
}
