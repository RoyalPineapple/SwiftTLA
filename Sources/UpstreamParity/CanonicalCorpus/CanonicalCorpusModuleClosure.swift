/// A pinned nonstandard TLA+ module required by one canonical corpus model.
///
/// These inputs are resolved while SwiftTLA builds the immutable corpus
/// artifact. ValidationEvidence stages the resulting bundle unchanged.
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

/// The source-owned linker inputs for canonical upstream examples.
public enum CanonicalCorpusModuleClosure {
    public static func inputs(for caseID: String) -> [CanonicalCorpusModuleInput] {
        switch caseID {
        case "voteproof-upstream-port":
            return voteProofTLAPSClosure
        default:
            return []
        }
    }

    private static let voteProofTLAPSClosure: [CanonicalCorpusModuleInput] = [
        .init(
            name: "NaturalsInduction",
            source: .init(repository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5", path: "library/NaturalsInduction.tla"),
            sha256: "08f52420cdaaf11292ed366782b5ce5b596bb7cbe789526a1cfd8806dbf98624"
        ),
        .init(
            name: "WellFoundedInduction",
            source: .init(repository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5", path: "library/WellFoundedInduction.tla"),
            sha256: "6f2f274c2e987d1edcf004d8e37b053f1f82b912e66d6a51bae0af8012ddcbec"
        ),
        .init(
            name: "FiniteSetTheorems",
            source: .init(repository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5", path: "library/FiniteSetTheorems.tla"),
            sha256: "484bf0f9ab6a69ef45f7282f7f92dcf1e6ae139e44117b0d5a4427635818e773"
        ),
        .init(
            name: "TLAPS",
            source: .init(repository: "tlaplus/tlapm", commit: "4600b24c6d95a25ff081ad37b63b2a01c29d43a5", path: "library/TLAPS.tla"),
            sha256: "9afe54984062748a0568966434cc0945d682f8cd89fdbc38f73b5579751b0c55"
        ),
        .init(
            name: "Functions",
            source: .init(repository: "tlaplus/CommunityModules", commit: "a8068a4c21ed76b339b9a2aa6de69d78f64f6422", path: "modules/Functions.tla"),
            sha256: "b54ff63b7c76c327525c17c188d5f9f5e53d92f3fd701f5e2ba54f0f54391063"
        ),
        .init(
            name: "Folds",
            source: .init(repository: "tlaplus/CommunityModules", commit: "a8068a4c21ed76b339b9a2aa6de69d78f64f6422", path: "modules/Folds.tla"),
            sha256: "aa59063fd600bb640b2ae24dc85ef770277ef5bf7955092b76b8b471790086da"
        )
    ]
}
