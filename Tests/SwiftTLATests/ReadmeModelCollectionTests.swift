import Testing

@Suite(.serialized)
struct ReadmeModelCollectionTests {
  @Test("symmetric collection fixture runs its generated machine")
  func collectionFixtureRunsGeneratedMachine() throws {
    let run = try runExternalConsumer("ReadmeModelCollectionMacro")
    #expect(run.status == 0, "symmetric collection fixture failed:\n\(run.output)")
  }
}
