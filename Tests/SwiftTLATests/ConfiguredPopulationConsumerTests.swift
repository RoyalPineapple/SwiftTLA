import Testing

@Suite(.serialized)
struct ConfiguredPopulationConsumerTests {
    @Test("typed member-ID population executes and exports from an external consumer")
    func generatedMachineAndScenario() throws {
        let run = try runExternalConsumer("ConfiguredPopulationConsumer")
        #expect(run.status == 0, "configured population consumer failed:\n\(run.output)")
    }

    @Test("mutable state cannot determine a generated process population")
    func rejectsMutableProcessPopulation() throws {
        let build = try buildExternalConsumer("InvalidMutableProcessPopulation")
        #expect(build.status != 0)
        #expect(build.output.contains("at lowering authoredPlusCal.processes[0].domain"))
        #expect(build.output.contains("an immutable process population"))
    }
}
