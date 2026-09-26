import Foundation
import SwiftTLA

package struct NativeCounterexampleRun: Sendable {
    package let rendered: RenderedSpecification
    package let checks: ModelCheckResults
    private let compareTrace: @Sendable (Data, TLCExecutionOutcome, String) throws -> PropertyComparison

    package init<Machine: StateMachine>(_ result: SafetyCounterexample<Machine>,
        initialMachines: [Machine], rendered: RenderedSpecification, maximumStates: Int) throws {
        guard let machine = initialMachines.first, !result.trace.isEmpty, !result.violations.isEmpty else {
            throw EvidenceFormatError.invalidField(record: "counterexample", field: "missing native witness")
        }
        let names = Machine.formalPropertyNames
        guard Set(result.checking.properties.compactMap { names[$0] }) == rendered.checkNames,
              result.checking.checkDeadlock == rendered.checksDeadlock else {
            throw EvidenceFormatError.invalidField(record: "counterexample", field: "check selection")
        }
        let actions = Dictionary(uniqueKeysWithValues: rendered.actions.map {
            ($0.sourceInvocationName, $0.renderedName)
        })
        @Sendable func canonicalTrace(_ steps: [(action: Machine.Action?, state: Machine.Snapshot)]) throws -> GraphTrace {
            try GraphTrace(id: "native-witness", steps: steps.map { step in
                let action = try step.action.map { action in
                    let invocation = try machine.formalCall(for: action).description
                    return actions[invocation] ?? invocation
                }
                return GraphTraceStep(state: try CanonicalState(machine.formalProjection(of: step.state)).key, action: action)
            })
        }
        let trace = try canonicalTrace(result.trace)
        var properties = Dictionary(uniqueKeysWithValues: rendered.checkNames.map { ($0, PropertyResult.unavailable) })
        var deadlock: PropertyResult? = rendered.checksDeadlock ? .unavailable : nil
        for violation in result.violations {
            switch violation {
            case .invariant(let property):
                guard let name = names[property], rendered.invariantNames.contains(name) else {
                    throw EvidenceFormatError.invalidField(record: "counterexample", field: "undeclared invariant")
                }
                properties[name] = .violated(trace)
            case .deadlock:
                guard rendered.checksDeadlock else {
                    throw EvidenceFormatError.invalidField(record: "counterexample", field: "unselected deadlock")
                }
                deadlock = .violated(trace)
            }
        }
        let checks = ModelCheckResults(properties: properties, deadlock: deadlock)
        self.rendered = rendered
        self.checks = checks
        compareTrace = { data, outcome, stdout in
            if outcome == .deadlock {
                guard rendered.checksDeadlock, case .violated = checks.deadlock else {
                    throw EvidenceFormatError.invalidField(record: "counterexample", field: "different decisive check")
                }
            }
            let replay = try TLCTraceParser().replayCounterexample(data,
                initialMachines: initialMachines, renderedActions: rendered.actions,
                maximumStates: maximumStates, checkingDeadlock: outcome == .deadlock)
            let check: ModelCheck
            let nativeResult: PropertyResult?
            switch outcome {
            case .deadlock where rendered.checksDeadlock:
                guard replay.finalIsDeadlocked == true else {
                    throw EvidenceFormatError.invalidField(record: "counterexample", field: "false deadlock")
                }
                check = .deadlock
                nativeResult = checks.deadlock
            case .safetyViolation:
                let reported = rendered.invariantNames.union(rendered.reachabilityNames).filter { name in
                    stdout.split(whereSeparator: \.isNewline).contains {
                        $0 == "Error: Invariant \(name) is violated."
                            || (replay.trace.steps.count == 1
                                && $0 == "Error: Invariant \(name) is violated by the initial state:")
                    }
                }
                guard reported.count == 1, let name = reported.first else {
                    throw EvidenceFormatError.invalidField(record: "counterexample", field: "unconfirmed invariant")
                }
                if rendered.reachabilityNames.contains(name) {
                    guard let property = names.first(where: { $0.value == name })?.key,
                          try replay.final.matchedReachabilityProperties(checking: [property]).contains(property),
                          let steps = try ReachabilityGraph<Machine>.reachabilityWitness(
                            initialMachines: initialMachines, property: property, maximumStates: maximumStates),
                          steps.count == replay.trace.steps.count else {
                        throw EvidenceFormatError.invalidField(record: name, field: "unconfirmed reachability witness")
                    }
                    return PropertyComparison(caseID: rendered.tlaBundle.root.name, check: .property(name), status: .exact,
                        swiftResult: .reached(try canonicalTrace(steps)), tlcResult: .reached(replay.trace))
                }
                guard try replay.final.violatedInvariants(checking: result.checking.properties)
                        .contains(where: { names[$0] == name }) else {
                    throw EvidenceFormatError.invalidField(record: "counterexample", field: "unconfirmed invariant")
                }
                check = .property(name)
                nativeResult = checks.properties[name]
            default:
                throw EvidenceFormatError.invalidField(record: "counterexample", field: "no matching decisive TLC outcome")
            }
            guard case .violated(let nativeTrace) = nativeResult else {
                throw EvidenceFormatError.invalidField(record: "counterexample", field: "different decisive check")
            }
            guard nativeTrace.steps.count == replay.trace.steps.count else {
                throw EvidenceFormatError.invalidField(record: "counterexample", field: "shortest BFS witness length")
            }
            return PropertyComparison(caseID: rendered.tlaBundle.root.name, check: check, status: .exact,
                swiftResult: .violated(nativeTrace), tlcResult: .violated(replay.trace))
        }
    }

    package func compare(data: Data, outcome: TLCExecutionOutcome, stdout: String) throws -> PropertyComparison {
        try compareTrace(data, outcome, stdout)
    }
}
