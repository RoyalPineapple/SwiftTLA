import SwiftTLA

/// Everything an immutable corpus export needs from one canonical model.
package struct CanonicalCorpusEntry: Sendable {
    package let id: String
    package let rendered: @Sendable () throws -> RenderedSpecification
}

/// The corpus registry has no case-specific export or link behavior.
package enum CanonicalCorpus {
    package static let entries: [CanonicalCorpusEntry] = [
        BoulangerModel.corpusEntry,
        KVsnapModel.corpusEntry,
        TLCMCModel.corpusEntry,
        VoteProofModel.corpusEntry
    ]
}
