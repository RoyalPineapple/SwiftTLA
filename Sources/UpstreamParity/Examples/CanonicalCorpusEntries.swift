import CanonicalUpstreamCorpus

extension Example {
    public static let boulanger = Entry(
        id: "Boulanger/Boulanger",
        upstreamSpec: "Boulanger",
        upstreamModule: "specifications/Boulanger/Boulanger.tla",
        upstreamCfg: "specifications/Boulanger/MCBoulanger.cfg",
        expectedDistinct: 0,
        verificationStateLimit: 1,
        spec: BoulangerModel.spec,
        notes: "Canonical Boulanger source port. External validation retains the bounded official PlusCal and TLC comparison."
    )

    public static let kvsnap = Entry(
        id: "KeyValueStore/KVsnap",
        upstreamSpec: "KeyValueStore",
        upstreamModule: "specifications/KeyValueStore/KVsnap.tla",
        upstreamCfg: "specifications/KeyValueStore/MCKVsnap.cfg",
        expectedDistinct: 0,
        verificationStateLimit: 1,
        spec: KVsnapModel.spec,
        notes: "Canonical KVsnap source port. The independent ValidationEvidence benchmark retains the bounded TLC count and graph evidence."
    )

    public static let voteProof = Entry(
        id: "byzpaxos/VoteProof",
        upstreamSpec: "byzpaxos",
        upstreamModule: "specifications/byzpaxos/VoteProof.tla",
        upstreamCfg: "specifications/byzpaxos/VoteProof.cfg",
        expectedDistinct: 0,
        verificationStateLimit: 1,
        spec: VoteProofModel.spec,
        notes: "Canonical VoteProof source port. External validation retains the bounded official PlusCal and TLC comparison."
    )
}
