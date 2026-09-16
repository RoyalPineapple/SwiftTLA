import SwiftTLA

package enum ScenarioExpectationError: Error, Equatable, Sendable {
    case unexpectedOutcome(check: ModelCheck, expected: ValidationExpectation, actual: PropertyResult)
    case graphDifference(GraphComparison)
    case checkDifference(PropertyComparison)
}

package struct NativeScenarioRun: Sendable {
    package struct CheckCoverage: Encodable, Sendable {
        package let selectedProperties: [String]
        package let omittedProperties: [String]
        package let checksDeadlock: Bool
        package let coversCompleteScenario: Bool
    }
    package let name: String
    package let native: NativeModelRun
    package let expectations: [String: ValidationExpectation]
    package let deadlockExpectation: ValidationExpectation?
    package let coverage: CheckCoverage

    package init<Scenario: ModelValidationScenario>(_ scenario: Scenario, maximumStates: Int) throws {
        let rendered = try scenario.render()
        let names = scenario.formalPropertyNames
        guard names == Scenario.Machine.formalPropertyNames,
              scenario.checking.properties.isSubset(of: Set(names.keys)),
              scenario.checking.properties == Set(scenario.expectations.keys) else {
            throw EvidenceFormatError.invalidField(record: scenario.name, field: "scenario check coverage")
        }
        let bindings = scenario.expectations.map { (names[$0.key]!, $0.value) }
        guard !scenario.name.isEmpty, Set(bindings.map(\.0)).count == bindings.count,
              Set(bindings.map(\.0)) == rendered.checkNames,
              (scenario.deadlockExpectation != nil) == rendered.checksDeadlock else {
            throw EvidenceFormatError.invalidField(record: scenario.name, field: "scenario check coverage")
        }
        name = scenario.name
        expectations = Dictionary(uniqueKeysWithValues: bindings)
        deadlockExpectation = scenario.deadlockExpectation
        native = try NativeModelRun(scenario.explore(maximumStates: maximumStates), rendered: rendered)
        let omitted = Set(names.keys).subtracting(scenario.checking.properties)
        coverage = .init(selectedProperties: rendered.checkNames.sorted(),
            omittedProperties: omitted.map { names[$0]! }.sorted(), checksDeadlock: rendered.checksDeadlock,
            coversCompleteScenario: omitted.isEmpty && (rendered.checksDeadlock || !Scenario.Machine.checksDeadlock))
    }

    package func validateExpectations() throws {
        for (name, expected) in expectations.sorted(by: { $0.key < $1.key }) {
            guard let actual = native.checks.properties[name] else {
                throw EvidenceFormatError.invalidField(record: self.name, field: "missing scenario result: \(name)")
            }
            guard expected.accepts(actual) else {
                throw ScenarioExpectationError.unexpectedOutcome(check: .property(name), expected: expected, actual: actual)
            }
        }
        if let expected = deadlockExpectation {
            guard let actual = native.checks.deadlock else {
                throw EvidenceFormatError.invalidField(record: name, field: "missing scenario deadlock result")
            }
            guard expected.accepts(actual) else {
                throw ScenarioExpectationError.unexpectedOutcome(check: .deadlock, expected: expected, actual: actual)
            }
        }
    }

    package func validateComparison(_ graph: GraphComparison, checks: [PropertyComparison]) throws {
        let expectedPaths = Set(expectations.keys.map { ModelCheck.property($0).artifactPath })
            .union(deadlockExpectation == nil ? [] : [ModelCheck.deadlock.artifactPath])
        guard checks.count == expectedPaths.count, Set(checks.map { $0.check.artifactPath }) == expectedPaths else {
            throw EvidenceFormatError.invalidField(record: name, field: "scenario comparison coverage")
        }
        guard graph.matches else { throw ScenarioExpectationError.graphDifference(graph) }
        try validateExpectations()
        for comparison in checks {
            let expected: ValidationExpectation?
            let actual: PropertyResult?
            switch comparison.check {
            case .property(let property):
                expected = expectations[property]
                actual = native.checks.properties[property]
            case .deadlock:
                expected = deadlockExpectation
                actual = native.checks.deadlock
            }
            guard comparison.status == .exact, comparison.swiftResult == actual,
                  expected?.accepts(comparison.tlcResult) == true else {
                throw ScenarioExpectationError.checkDifference(comparison)
            }
        }
    }
}
