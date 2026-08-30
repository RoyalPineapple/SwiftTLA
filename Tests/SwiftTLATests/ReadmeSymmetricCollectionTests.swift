import Testing

@Suite(.serialized)
struct ReadmeSymmetricCollectionTests {
  @Test("symmetric collection fixture runs its generated machine")
  func symmetricCollectionFixtureRunsGeneratedMachine() throws {
    let run = try runExternalConsumer("ReadmeSymmetricCollectionMacro")
    #expect(run.status == 0, "symmetric collection fixture failed:\n\(run.output)")
  }
}
