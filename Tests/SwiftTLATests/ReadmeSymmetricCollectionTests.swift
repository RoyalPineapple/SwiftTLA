import Foundation
import Testing

@Suite(.serialized)
struct ReadmeSymmetricCollectionTests {
  @Test("symmetric collection fixture runs its generated machine")
  func symmetricCollectionFixtureRunsGeneratedMachine() throws {
    let root = packageRoot()
    let fixture = root.appendingPathComponent("Tests/Fixtures/ReadmeSymmetricCollectionMacro")

    let result = try runSwiftPackage(["run", "--package-path", fixture.path])
    #expect(result.status == 0, "symmetric collection fixture failed:\n\(result.output)")
  }
}
