import SwiftTLA

/// Everything an immutable corpus export needs from one canonical model.
package struct CanonicalCorpusEntry: Sendable {
    package let id: String
    package let specification: @Sendable () -> TLASpec
    package let rendered: @Sendable () throws -> RenderedSpecification

    package init(
        id: String,
        specification: @escaping @Sendable () -> TLASpec,
        rendered: @escaping @Sendable () throws -> RenderedSpecification
    ) {
        self.id = id
        self.specification = specification
        self.rendered = rendered
    }
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
