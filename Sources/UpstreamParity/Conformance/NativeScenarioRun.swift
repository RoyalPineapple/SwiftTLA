import SwiftTLA

package enum ScenarioExpectationError: Error, Equatable, Sendable {
    case unexpectedOutcome(check: ModelCheck, expected: ValidationExpectation, actual: PropertyResult)
    case graphDifference(GraphComparison)
    case checkDifference(PropertyComparison)
}

package enum NativeScenarioResult: Sendable {
    case exhausted(NativeModelRun)
    case counterexample(NativeCounterexampleRun)

    package var rendered: RenderedSpecification {
        switch self {
        case .exhausted(let run): run.rendered
        case .counterexample(let run): run.rendered
        }
    }

    package var checks: ModelCheckResults {
        switch self {
        case .exhausted(let run): run.checks
        case .counterexample(let run): run.checks
        }
    }

    package var graph: GraphRun? {
        if case .exhausted(let run) = self { return run.graph }
        return nil
    }
}

package struct NativeScenarioRun: Sendable {
    package struct CheckCoverage: Encodable, Sendable {
        package let selectedProperties: [String]
        package let omittedProperties: [String]
        package let checksDeadlock: Bool
        package let behavior: ModelBehavior
        package let coversCompleteScenario: Bool
        package let propertyDisplayNames: [String: String]
    }
    package let name: String
    package let native: NativeScenarioResult
    package let expectations: [String: ValidationExpectation]
    package let deadlockExpectation: ValidationExpectation?
    package let coverage: CheckCoverage

    package init<Scenario: ModelValidationScenario>(_ scenario: Scenario, maximumStates: Int) throws {
        let rendered = try scenario.render()
        let names = scenario.formalPropertyNames
        guard names == Scenario.Machine.formalPropertyNames,
              Set(Scenario.Machine.propertyDisplayNames.keys) == Set(names.keys),
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
        let initial = try scenario.initialMachines()
        switch try ReachabilityGraph.check(initialMachines: initial, maximumStates: maximumStates,
            checking: scenario.checking, behavior: scenario.behavior) {
        case .exhausted(let graph): native = .exhausted(try NativeModelRun(graph, rendered: rendered))
        case .counterexample(let result):
            native = .counterexample(try NativeCounterexampleRun(result, initialMachines: initial,
                rendered: rendered, maximumStates: maximumStates))
        }
        let omitted = Set(names.keys).subtracting(scenario.checking.properties)
        coverage = .init(selectedProperties: rendered.checkNames.sorted(),
            omittedProperties: omitted.map { names[$0]! }.sorted(), checksDeadlock: rendered.checksDeadlock,
            behavior: rendered.behavior,
            coversCompleteScenario: omitted.isEmpty && (rendered.checksDeadlock || !Scenario.Machine.checksDeadlock)
                && rendered.behavior == .specification,
            propertyDisplayNames: Dictionary(uniqueKeysWithValues: names.map {
                ($0.value, Scenario.Machine.propertyDisplayNames[$0.key]!)
            }))
    }

    package func validateExpectations() throws {
        for (name, expected) in expectations.sorted(by: { $0.key < $1.key }) {
            guard let actual = native.checks.properties[name] else {
                throw EvidenceFormatError.invalidField(record: self.name, field: "missing scenario result: \(name)")
            }
            if case .counterexample = native, actual == .unavailable { continue }
            guard expected.accepts(actual) else {
                throw ScenarioExpectationError.unexpectedOutcome(check: .property(name), expected: expected, actual: actual)
            }
        }
        if let expected = deadlockExpectation {
            guard let actual = native.checks.deadlock else {
                throw EvidenceFormatError.invalidField(record: name, field: "missing scenario deadlock result")
            }
            if case .counterexample = native, actual == .unavailable { return }
            guard expected.accepts(actual) else {
                throw ScenarioExpectationError.unexpectedOutcome(check: .deadlock, expected: expected, actual: actual)
            }
        }
    }

    package func validateComparison(_ graph: GraphComparison, checks: [PropertyComparison]) throws {
        guard case .exhausted = native else {
            throw EvidenceFormatError.invalidField(record: name, field: "counterexample is not a complete graph")
        }
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

    package func validateCounterexample(_ comparison: PropertyComparison) throws {
        guard case .counterexample = native else {
            throw EvidenceFormatError.invalidField(record: name, field: "expected a decisive result")
        }
        try validateExpectations()
        let expected: ValidationExpectation?
        let actual: PropertyResult?
        switch comparison.check {
        case .property(let name):
            expected = expectations[name]
            actual = native.checks.properties[name]
        case .deadlock:
            expected = deadlockExpectation
            actual = native.checks.deadlock
        }
        guard comparison.status == .exact, comparison.swiftResult == actual,
              case .violated = comparison.tlcResult, expected == .violated else {
            throw ScenarioExpectationError.checkDifference(comparison)
        }
    }

    package func validateReachability(_ comparison: PropertyComparison) throws {
        guard case .counterexample = native,
              case .property(let name) = comparison.check,
              native.rendered.reachabilityNames.contains(name),
              comparison.status == .exact,
              case .reached = comparison.swiftResult,
              case .reached = comparison.tlcResult,
              expectations[name]?.accepts(comparison.swiftResult) == true else {
            throw ScenarioExpectationError.checkDifference(comparison)
        }
    }
}
