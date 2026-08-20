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

/// Everything an immutable corpus export needs from one canonical model.
public struct CanonicalCorpusEntry: Sendable {
    public let id: String
    public let specification: @Sendable () -> TLASpec
    public let swiftConfiguration: String
    public let plusCalConfiguration: String
    public let externalInputs: [CanonicalCorpusModuleInput]

    public init(
        id: String,
        specification: @escaping @Sendable () -> TLASpec,
        swiftConfiguration: String,
        plusCalConfiguration: String,
        externalInputs: [CanonicalCorpusModuleInput] = []
    ) {
        self.id = id
        self.specification = specification
        self.swiftConfiguration = swiftConfiguration
        self.plusCalConfiguration = plusCalConfiguration
        self.externalInputs = externalInputs
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
