import Foundation
import SwiftTLA

package struct ScenarioCheckCoverage: Codable, Equatable, Sendable {
    package let selectedProperties: [String]
    package let omittedProperties: [String]
    package let checksDeadlock: Bool
    package let behavior: ModelBehavior
    package let coversCompleteScenario: Bool
    package let propertyDisplayNames: [String: String]
    package let postconditionName: String?

    package init<Scenario: ModelValidationScenario>(_ scenario: Scenario) throws {
        let names = scenario.formalPropertyNames
        let displayNames = Scenario.Machine.propertyDisplayNames
        guard names == Scenario.Machine.formalPropertyNames,
              Set(names.keys) == Set(Scenario.Property.allCases),
              Set(names.values).count == names.count,
              Set(displayNames.keys) == Set(names.keys),
              scenario.checking.properties.isSubset(of: Set(names.keys)),
              scenario.checking.properties == Set(scenario.expectations.keys) else {
            throw EvidenceFormatError.invalidField(record: scenario.name, field: "scenario check coverage")
        }
        let omitted = Set(names.keys).subtracting(scenario.checking.properties)
        selectedProperties = scenario.checking.properties.map { names[$0]! }.sorted()
        omittedProperties = omitted.map { names[$0]! }.sorted()
        checksDeadlock = scenario.checking.checkDeadlock
        behavior = scenario.behavior
        coversCompleteScenario = omitted.isEmpty
            && (checksDeadlock || !Scenario.Machine.checksDeadlock)
            && behavior == .specification
        propertyDisplayNames = Dictionary(uniqueKeysWithValues: names.map {
            ($0.value, displayNames[$0.key]!)
        })
        postconditionName = scenario.postconditionName
    }

    package static func annotateUpstream<Scenario: ModelValidationScenario>(
        _ scenario: Scenario, caseID: String, reportURL: URL
    ) throws {
        let report = try JSONDecoder().decode(UpstreamTLCParityReport.self,
            from: Data(contentsOf: reportURL))
        let coverage = try Self(scenario)
        let reported = Set(report.generatedProperties.keys)
        let unreported = Set(coverage.selectedProperties).subtracting(reported)
        guard report.schema == "swifttla.upstream-tlc-parity", report.caseID == caseID,
              report.deadlockSelected == coverage.checksDeadlock,
              report.postconditionSelected == (coverage.postconditionName != nil),
              reported == Set(report.referenceProperties.keys),
              reported.isSubset(of: Set(coverage.selectedProperties)),
              // PlusCal assertions are checked by TLC's transition execution, not named CFG properties.
              !report.graphCompared || unreported.allSatisfy({ $0.hasPrefix("__pcal_assert_") }) else {
            throw EvidenceFormatError.invalidField(record: caseID, field: "upstream check coverage")
        }
        if let expected = scenario.postconditionExpectation,
           (report.generatedPostcondition?.satisfies(expected) != true
            || report.referencePostcondition?.satisfies(expected) != true) {
            throw EvidenceFormatError.invalidField(record: caseID, field: "upstream postcondition outcome")
        }
        try coverage.attach(to: reportURL)
    }

    package func attach(to reportURL: URL) throws {
        guard var report = try JSONSerialization.jsonObject(with: Data(contentsOf: reportURL)) as? [String: Any] else {
            throw EvidenceFormatError.invalidField(record: reportURL.lastPathComponent, field: "comparison report")
        }
        report["coverage"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self))
        try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
            .write(to: reportURL, options: .atomic)
    }
}
