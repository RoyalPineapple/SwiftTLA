import Testing

@Suite(.serialized)
struct ConfiguredPopulationConsumerTests {
    @Test("configured process population executes and exports from an external consumer")
    func generatedMachineAndScenario() throws {
        let run = try runExternalConsumer("ConfiguredPopulationConsumer")
        #expect(run.status == 0, "configured population consumer failed:\n\(run.output)")
    }
}
