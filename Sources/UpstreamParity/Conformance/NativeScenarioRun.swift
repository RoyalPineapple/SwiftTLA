import SwiftTLA

package enum ScenarioExpectationError: Error, Equatable, Sendable {
    case unexpectedOutcome(check: ModelCheck, expected: ValidationExpectation, actual: PropertyResult)
}

package struct NativeScenarioRun: Sendable {
    package let name: String
    package let native: NativeModelRun
    package let expectations: [String: ValidationExpectation]
    package let deadlockExpectation: ValidationExpectation?

    package init(_ scenario: some ModelValidationScenario, maximumStates: Int) throws {
        let rendered = try scenario.render()
        let names = scenario.formalPropertyNames
        guard Set(names.keys) == Set(scenario.expectations.keys) else {
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
}
