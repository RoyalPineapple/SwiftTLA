@testable import SwiftTLAPlugin
import Testing
@testable import SwiftTLA

struct GeneratedRestrictedProcessDomainTests {
    @Test("a process declaration keeps its explicit member subset")
    func compiledProcessUsesOnlyDeclaredMembers() throws {
        let compilation = try GeneratedRestrictedProcessDomain.spec.compile()
        let binding = try #require(compilation.semantics.behavior.actions.first?.bindings.first)
        #expect(binding.sourceName == "process")
        #expect(binding.literalMembers == [.integer(1)])
        let metadata = SourceTypeMetadata(enums: [.init(typeName: "Member",
            cases: GeneratedRestrictedProcessDomain.Member.allCases.map {
                (name: String(describing: $0), value: $0.tlaValue)
            })])
        let program = try CompiledProgram(inputs: SourceTypeResolver(metadata: metadata).resolve(in: compilation))
        let resolved = try #require(program.behavior.actions.first?.bindings.first)
        let type = try #require(program.bindingTypes[resolved.binder])
        #expect(resolved.domain.resultType == .set(type))
        #expect(resolved.domain.children.map(\.resultType) == [type])
        #expect(resolved.literalMembers == [.integer(1)])
    }
}
