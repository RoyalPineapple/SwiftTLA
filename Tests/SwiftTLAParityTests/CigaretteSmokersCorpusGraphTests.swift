import Foundation
import Testing
@testable import UpstreamParity

struct CigaretteSmokersCorpusGraphTests {
    @Test("both ingredient representations exhaust the same six-state smoking cycle")
    func checksBothConfigurations() throws {
        let scenarios = try CigaretteSmokersModel.validationScenarios()
        #expect(Set(scenarios.map(\.name)) == ["CigaretteSmokers", "APCigaretteSmokers"])
        for scenario in scenarios {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let report = try NativeValidationRunner.run(
                scenario: scenario, caseID: scenario.name, maximumStates: 100, to: directory)
            #expect(report.graphComplete)
            #expect(report.initialStates == 3)
            #expect(report.states == 6)
            #expect(report.edges == 12)
            #expect(report.properties["TypeOK"] == .satisfied)
            #expect(report.properties["AtMostOne"] == .satisfied)
            #expect(report.deadlock == .satisfied)
        }
    }
}
