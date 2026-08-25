import SwiftTLA

/// One compiled claim selected by a corpus TLC configuration.
package struct CanonicalCorpusCheck: Sendable {
    package enum Kind: String, CaseIterable, Sendable {
        case invariant
        case property
        case constraint
    }

    package let name: String
    package let kind: Kind

    package init(_ name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }
}

/// A corpus TLC configuration rendered from its declared checks and constants.
package struct CanonicalCorpusConfiguration: Sendable {
    package struct Constant: Sendable {
        package let name: String
        package let value: String

        package init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    package let checks: [CanonicalCorpusCheck]
    package let constants: [Constant]
    package let checkDeadlock: Bool?

    package init(
        checks: [CanonicalCorpusCheck] = [],
        constants: [Constant] = [],
        checkDeadlock: Bool? = nil
    ) {
        self.checks = checks
        self.constants = constants
        self.checkDeadlock = checkDeadlock
    }

    package var tlaText: String {
        var lines = ["SPECIFICATION Spec"]
        for kind in CanonicalCorpusCheck.Kind.allCases {
            let names = checks.compactMap { $0.kind == kind ? $0.name : nil }
            guard !names.isEmpty else { continue }
            let keyword = switch kind {
            case .invariant: "INVARIANTS"
            case .property: "PROPERTIES"
            case .constraint: "CONSTRAINT"
            }
            lines.append("\(keyword) \(names.joined(separator: " "))")
        }
        lines += constants.map { "CONSTANT \($0.name) = \($0.value)" }
        if let checkDeadlock {
            lines.append("CHECK_DEADLOCK \(checkDeadlock ? "TRUE" : "FALSE")")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func validate(against compilation: CompiledSpecification, entryID: String) throws {
        let compiledInvariants = Set(compilation.spec.invariants.map(\.name))
        let compiledProperties = Set(compilation.spec.temporalProperties.map(\.name))
            .union(compilation.spec.refinements.map(\.name))
        let compiledConstraints = compilation.spec.constraint == nil ? Set<String>() : ["StateConstraint"]

        for check in checks {
            let compiled = switch check.kind {
            case .invariant: compiledInvariants.contains(check.name)
            case .property: compiledProperties.contains(check.name)
            case .constraint: compiledConstraints.contains(check.name)
            }
            guard compiled else {
                throw CanonicalCorpusConfigurationError.unresolvedCheck(
                    entryID: entryID,
                    name: check.name,
                    kind: check.kind
                )
            }
        }
    }
}

package enum CanonicalCorpusConfigurationError: Error, Sendable, CustomStringConvertible {
    case unresolvedCheck(entryID: String, name: String, kind: CanonicalCorpusCheck.Kind)

    package var description: String {
        switch self {
        case let .unresolvedCheck(entryID, name, kind):
            "Canonical corpus entry '\(entryID)' configures \(kind.rawValue) '\(name)', but the compiled specification does not declare it."
        }
    }
}

/// Everything an immutable corpus export needs from one canonical model.
package struct CanonicalCorpusEntry: Sendable {
    package let id: String
    package let specification: @Sendable () -> TLASpec
    package let swiftConfiguration: CanonicalCorpusConfiguration
    package let plusCalConfiguration: CanonicalCorpusConfiguration

    package init(
        id: String,
        specification: @escaping @Sendable () -> TLASpec,
        swiftConfiguration: CanonicalCorpusConfiguration,
        plusCalConfiguration: CanonicalCorpusConfiguration
    ) {
        self.id = id
        self.specification = specification
        self.swiftConfiguration = swiftConfiguration
        self.plusCalConfiguration = plusCalConfiguration
    }

    package func validateConfigurationReferences(in compilation: CompiledSpecification) throws {
        try swiftConfiguration.validate(against: compilation, entryID: id)
        try plusCalConfiguration.validate(against: compilation, entryID: id)
    }
}

/// The corpus registry has no case-specific export or link behavior.
package enum CanonicalCorpus {
    package static let entries: [CanonicalCorpusEntry] = [
        BoulangerModel.corpusEntry,
        KVsnapModel.corpusEntry,
        VoteProofModel.corpusEntry
    ]
}
