import Testing
@testable import SwiftTLA

struct ProcessLocalDomainTests {
    @Test("each process chooses its initial local value independently")
    func independentInitialChoices() throws {
        let compilation = try IndependentLocalChoices.spec.compile()
        let native = try IndependentLocalChoices.initialMachines()
        let nativeStates = try Set(native.map { try $0.formalProjection(of: $0.snapshot) })
        let compiledStates = try Set(CompiledRuntime(compilation: compilation).initialStates().map {
            try $0.projection(using: compilation.layout)
        })
        #expect(nativeStates.count == 16)
        #expect(nativeStates == compiledStates)
        #expect(try IndependentLocalChoices.render().tlaBundle.tla.contains("choice \\in ["))
    }
}
