import CryptoKit
import Foundation
import SwiftTLA

package enum MachineValidationEvidenceError: Error, Equatable {
    case invalidPropertyName
}

/// Append-only evidence from the generated Swift machine. TLC is never read by this checker.
package enum MachineValidationEvidence {
    package static func write<Scenario: ModelValidationScenario>(
        scenario: Scenario, maximumStates: Int, stopOnViolation: Bool,
        stopOnReachability: Bool = false,
        checking: ModelChecks<Scenario.Property>? = nil, to output: URL
    ) throws -> MachineValidationSummary<Scenario.Property> {
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let propertyNames = scenario.formalPropertyNames
        guard Set(propertyNames.keys) == Set(Scenario.Property.allCases),
              Set(propertyNames.values).count == propertyNames.count,
              propertyNames == Scenario.Machine.formalPropertyNames else {
            throw MachineValidationEvidenceError.invalidPropertyName
        }
        let checking = checking ?? scenario.checking
        guard checking.properties.isSubset(of: scenario.checking.properties),
              !checking.checkDeadlock || scenario.checking.checkDeadlock else {
            throw MachineValidationEvidenceError.invalidPropertyName
        }
        let selectedNames = try Set(checking.properties.map { property -> String in
            guard let name = propertyNames[property] else { throw MachineValidationEvidenceError.invalidPropertyName }
            return name
        })
        let initial = try scenario.initialMachines()
        guard let machine = initial.first else { throw ExplorationError.noInitialStates }
        try Data().write(to: output, options: .withoutOverwriting)
        let file = try FileHandle(forWritingTo: output)
        var buffer = Data()
        buffer.reserveCapacity(1_048_576)
        var digest = CryptoKit.SHA256()
        let encoder = JSONEncoder()
        var actionCache: [Scenario.Machine.Action: String] = [:]

        func quoted(_ value: String) throws -> String {
            String(decoding: try encoder.encode(value), as: UTF8.self)
        }
        func quoted(_ values: [String]) throws -> String {
            String(decoding: try encoder.encode(values), as: UTF8.self)
        }
        func flush() throws {
            guard !buffer.isEmpty else { return }
            digest.update(data: buffer)
            try file.write(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)
        }
        defer {
            try? flush()
            try? file.close()
        }
        func emit(_ line: String) throws {
            let length = line.utf8.count + 1
            if buffer.count + length > 1_048_576 { try flush() }
            if length > 1_048_576 {
                let bytes = Data((line + "\n").utf8)
                digest.update(data: bytes)
                try file.write(contentsOf: bytes)
            } else {
                buffer.append(contentsOf: line.utf8)
                buffer.append(10)
            }
        }
        func actionName(_ action: Scenario.Machine.Action) throws -> String {
            if let cached = actionCache[action] { return cached }
            let encoded = try quoted(machine.formalCall(for: action).description)
            actionCache[action] = encoded
            return encoded
        }
        func stateKey(_ snapshot: Scenario.Machine.Snapshot) throws -> String {
            try CanonicalState(machine.formalProjection(of: snapshot)).key.canonicalEncoding
        }
        try emit("{\"type\":\"header\",\"schema\":\"swifttla.native-validation\",\"version\":1,\"scenario\":\(try quoted(scenario.name)),\"selectedChecks\":\(try quoted(selectedNames.sorted())),\"checkDeadlock\":\(checking.checkDeadlock),\"behavior\":\(try quoted(scenario.behavior.rawValue))}")
        let started = ContinuousClock.now
        let result = try MachineValidator.run(
            initialMachines: initial, maximumStates: maximumStates,
            checking: checking, stopOnViolation: stopOnViolation,
            stopOnReachability: stopOnReachability
        ) { event in
            switch event {
            case .state(let id, let snapshot, let isInitial, let predecessor, let action):
                let parent = predecessor.map { String($0) } ?? "null"
                let incoming = try action.map(actionName) ?? "null"
                try emit("{\"type\":\"state\",\"id\":\(id),\"key\":\(try quoted(stateKey(snapshot))),\"initial\":\(isInitial),\"predecessor\":\(parent),\"action\":\(incoming)}")
            case .edge(let source, let action, let target):
                try emit("{\"type\":\"edge\",\"source\":\(source),\"action\":\(try actionName(action)),\"target\":\(target)}")
            case .invariantFailure(let property, let snapshot, let predecessor, let action):
                guard let name = propertyNames[property] else { throw MachineValidationEvidenceError.invalidPropertyName }
                let parent = predecessor.map { String($0) } ?? "null"
                let incoming = try action.map(actionName) ?? "null"
                try emit("{\"type\":\"invariant-failure\",\"property\":\(try quoted(name)),\"key\":\(try quoted(stateKey(snapshot))),\"predecessor\":\(parent),\"action\":\(incoming)}")
            case .deadlock(let state):
                try emit("{\"type\":\"deadlock\",\"state\":\(state)}")
            case .reachability(let property, let snapshot, let predecessor, let action):
                guard let name = propertyNames[property] else { throw MachineValidationEvidenceError.invalidPropertyName }
                let parent = predecessor.map { String($0) } ?? "null"
                let incoming = try action.map(actionName) ?? "null"
                try emit("{\"type\":\"reachability\",\"property\":\(try quoted(name)),\"key\":\(try quoted(stateKey(snapshot))),\"predecessor\":\(parent),\"action\":\(incoming)}")
            }
        }
        try flush()
        let bodyHash = digest.finalize().map { String(format: "%02x", $0) }.joined()
        let elapsed = started.duration(to: .now)
        let completion = switch result.completion {
        case .exhausted: "exhausted"
        case .decisiveViolation: "decisive-violation"
        case .decisiveReachability: "decisive-reachability"
        }
        let failedNames = try result.violatedInvariants.map { property -> String in
            guard let name = propertyNames[property] else { throw MachineValidationEvidenceError.invalidPropertyName }
            return name
        }.sorted()
        let reachedNames = try result.reachedProperties.map { property -> String in
            guard let name = propertyNames[property] else { throw MachineValidationEvidenceError.invalidPropertyName }
            return name
        }.sorted()
        let footer = "{\"type\":\"complete\",\"completion\":\(try quoted(completion)),\"initialStates\":\(result.initialStates),\"states\":\(result.states),\"edges\":\(result.edges),\"violatedInvariants\":\(try quoted(failedNames)),\"reachedProperties\":\(try quoted(reachedNames)),\"deadlockFound\":\(result.deadlockFound),\"elapsed\":\(try quoted(String(describing: elapsed))),\"bodySha256\":\(try quoted(bodyHash))}\n"
        try file.write(contentsOf: Data(footer.utf8))
        try file.close()
        return result
    }
}
