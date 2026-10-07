import Testing

@Suite("Generated refinement contracts")
struct GeneratedRefinementContractTests {
    @Test("Every abstract generated state member requires a mapping")
    func missingAbstractStateMappingFailsCompilation() throws {
        let build = try buildExternalConsumer("InvalidGeneratedRefinementMapping")
        #expect(build.status != 0)
        #expect(build.output.contains("missing argument for parameter 'value'"))
    }
}
