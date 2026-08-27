import Testing

@Suite(.serialized)
struct ReadmeSymmetricCollectionTests {
  @Test("symmetric collection fixture runs its generated machine")
  func symmetricCollectionFixtureRunsGeneratedMachine() throws {
    let result = try runExternalConsumer("ReadmeSymmetricCollectionMacro")
    #expect(result.status == 0, "symmetric collection fixture failed:\n\(result.output)")
  }
}
