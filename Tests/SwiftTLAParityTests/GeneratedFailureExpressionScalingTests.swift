import Testing
@testable import UpstreamParity

@Suite("Generated failure expressions")
struct GeneratedFailureExpressionScalingTests {
    @Test("Nested candidate failures stay bounded in the TLA+ sent to TLC")
    func nestedCandidateFailures() throws {
        let boulanger = try #require(BoulangerModel.validationScenarios().first)
        let parallel = try #require(DieHardestParallelModel.validationScenarios().first)
        for module in [try boulanger.render().tlaBundle.root.tla,
                       try parallel.render().tlaBundle.root.tla] {
            let longestLine = module.split(separator: "\n").map(\.utf8.count).max() ?? 0
            #expect(module.utf8.count < 1_000_000)
            #expect(longestLine < 65_536)
        }
    }
}
