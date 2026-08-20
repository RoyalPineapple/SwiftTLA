import SwiftTLA

/// A pinned nonstandard TLA+ source required by a canonical corpus entry.
///
/// These declarations belong beside the model that imports them. Exporters
/// materialize the declared closure; they do not dispatch on model IDs.
public struct CanonicalCorpusModuleInput: Sendable, Hashable {
    public struct Source: Sendable, Hashable {
        public let repository: String
        public let commit: String
        public let path: String

        public init(repository: String, commit: String, path: String) {
            self.repository = repository
            self.commit = commit
            self.path = path
        }
    }

    public let name: String
    public let source: Source
    public let sha256: String

    public init(name: String, source: Source, sha256: String) {
        self.name = name
        self.source = source
        self.sha256 = sha256
    }
}

/// One named claim selected by a corpus TLC configuration.
///
/// A check is either compiled from the SwiftTLA model or explicitly retained
/// as upstream-only TLA+ source. There is no implicit third category.
public struct CanonicalCorpusCheck: Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case invariant
        case property
        case constraint
    }

    public enum Support: Sendable {
        case compiled
        case externalOnly(reason: String)
    }

    public let name: String
    public let kind: Kind
    public let support: Support

    public init(_ name: String, kind: Kind, support: Support = .compiled) {
        self.name = name
        self.kind = kind
        self.support = support
    }
}

/// A corpus TLC configuration rendered from its declared checks and constants.
public struct CanonicalCorpusConfiguration: Sendable {
    public struct Constant: Sendable {
        public let name: String
        public let value: String

        public init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    public let checks: [CanonicalCorpusCheck]
    public let constants: [Constant]
    public let checkDeadlock: Bool?

    public init(
        checks: [CanonicalCorpusCheck] = [],
        constants: [Constant] = [],
        checkDeadlock: Bool? = nil
    ) {
        self.checks = checks
        self.constants = constants
        self.checkDeadlock = checkDeadlock
    }

    public var tlaText: String {
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
        let compiledConstraints = compilation.spec.constraint == nil ? Set<String>() : ["StateConstraint"]

        for check in checks {
            let compiled = switch check.kind {
            case .invariant: compiledInvariants.contains(check.name)
            case .property: compiledProperties.contains(check.name)
            case .constraint: compiledConstraints.contains(check.name)
            }
            if compiled { continue }
            guard case .externalOnly(let reason) = check.support, !reason.isEmpty else {
                throw CanonicalCorpusConfigurationError.unresolvedCheck(
                    entryID: entryID,
                    name: check.name,
                    kind: check.kind
                )
            }
        }
    }
}

public enum CanonicalCorpusConfigurationError: Error, Sendable, CustomStringConvertible {
    case unresolvedCheck(entryID: String, name: String, kind: CanonicalCorpusCheck.Kind)

    public var description: String {
        switch self {
        case let .unresolvedCheck(entryID, name, kind):
            "Canonical corpus entry '\(entryID)' configures \(kind.rawValue) '\(name)', but it is neither compiled nor declared external-only."
        }
    }
}

/// Everything an immutable corpus export needs from one canonical model.
public struct CanonicalCorpusEntry: Sendable {
    public let id: String
    public let specification: @Sendable () -> TLASpec
    public let swiftConfiguration: CanonicalCorpusConfiguration
    public let plusCalConfiguration: CanonicalCorpusConfiguration
    public let externalInputs: [CanonicalCorpusModuleInput]

    public init(
        id: String,
        specification: @escaping @Sendable () -> TLASpec,
        swiftConfiguration: CanonicalCorpusConfiguration,
        plusCalConfiguration: CanonicalCorpusConfiguration,
        externalInputs: [CanonicalCorpusModuleInput] = []
    ) {
        self.id = id
        self.specification = specification
        self.swiftConfiguration = swiftConfiguration
        self.plusCalConfiguration = plusCalConfiguration
        self.externalInputs = externalInputs
    }

    public func validateConfigurationReferences(in compilation: CompiledSpecification) throws {
        try swiftConfiguration.validate(against: compilation, entryID: id)
        try plusCalConfiguration.validate(against: compilation, entryID: id)
    }
}

/// The corpus registry has no case-specific export or link behavior.
public enum CanonicalCorpus {
    public static let entries: [CanonicalCorpusEntry] = [
        BoulangerModel.corpusEntry,
        KVsnapModel.corpusEntry,
        VoteProofModel.corpusEntry
    ]
}
