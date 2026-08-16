@testable import AlgorithmConformance
import Testing

struct K4StructuredTLCWitnessTests {
    @Test("K4 structured witness generates a typed two-car door runtime")
    func generatedRuntimeUsesTypedNestedDoorUpdate() throws {
        K4StructuredTLCWitness._checkParserTree()

        var model = K4StructuredTLCWitness()
        let result = try model.apply(.openDoor(process: .left))

        #expect(result.before.doors[.left][K4StructuredTLCWitness.Door.open] == false)
        #expect(result.after.doors[.left][K4StructuredTLCWitness.Door.open] == true)
        #expect(result.after.doors[.right][K4StructuredTLCWitness.Door.open] == false)
        #expect(K4StructuredTLCWitness.spec.tlaModule.contains("EXCEPT ![__pcal_self]"))
    }

    @Test("K4 fixture exposes one independently renderable PlusCal source")
    func exposesSinglePlusCalOracleSource() throws {
        let fixture = try #require(AlgorithmConformanceRegistry.fixture(id: "k4-structured-doors"))
        let source = try fixture.plusCalModule()

        #expect(source.contains("(*--algorithm K4StructuredTLCWitness"))
        #expect(fixture.configuration.contains("SPECIFICATION Spec"))
    }
}
