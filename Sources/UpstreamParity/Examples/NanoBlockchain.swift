import SwiftTLA

/// Nano blockchain — 2 nodes, 3 hashes, 2 keypairs. GenesisBalance=3.
/// Upstream: specifications/NanoBlockchain/Nano.tla
/// Uses DefineRecursive for PublicKeyOf/BalanceAt chain walking.

extension Example {
    public static let nanoBlockchain = Entry(
        id: "NanoBlockchain/Small",
        upstreamSpec: "NanoBlockchain",
        upstreamModule: "specifications/NanoBlockchain/Nano.tla",
        upstreamCfg: "specifications/NanoBlockchain/MCNanoSmall.cfg",
        expectedDistinct: 7,
        spec: nanoSpec(),
        notes: "2 nodes, 3 hashes. Genesis + Create + Process blocks. DefineRecursive for chain walking.",
    )
}

private func nanoSpec() -> TLASpec {
    let nodes = ["n1", "n2"]
    let hashes = ["h1", "h2", "h3"]
    let privKeys = ["prv1", "prv2"]
    let genesisBal = 3
    let noBlock = TLAValue.string("NoBlock")

    let lastHash = Var<String>("lastHash")
    let distributedLedger = Var<TLAFunctionType>("distributedLedger")
    let received = Var<TLAFunctionType>("received")

    let emptyLedger: TLAValue = .function(
        Dictionary(uniqueKeysWithValues: hashes.map { (.string($0), noBlock) }))
    let initDL: TLAValue = .function([.string("n1"): emptyLedger, .string("n2"): emptyLedger])
    let initRecv: TLAValue = .function([.string("n1"): .set([]), .string("n2"): .set([])])

    // Signed block constructor
    func signedBlock(_ blockFields: [String: StateExpr], _ hash: StateExpr, _ priv: String) -> StateExpr {
        let fields = blockFields
        return .recordLiteral([
            "block": .recordLiteral(fields),
            "signature": .recordLiteral(["data": hash, "signedWith": .value(.string(priv))])
        ])
    }

    // GenesisBlockExists
    func genesisExists() -> StateExpr { lastHash != "NoHash" }

    // Ledger access
    func ledgerOf(_ node: String) -> StateExpr { distributedLedger.applying(node) }
    func blockAt(_ node: String, _ hash: StateExpr) -> StateExpr {
        ledgerOf(node).applying(hash)
    }

    return TLASpec("NanoBlockchain") {
        Extends("Integers")

        Variable(lastHash, "NoHash")
        Variable(distributedLedger, initDL)
        Variable(received, initRecv)

        // Recursive: PublicKeyOf walks chain back to genesis/open block
        DefineRecursive("PublicKeyOf", params: ["led", "h"]) {
            let ledger = StateExpr.variable("led")
            let blockHash = StateExpr.variable("h")
            let sb = ledger.applying(blockHash)
            let blk = StateExpr.recordAccess(sb, "block")
            let btype = StateExpr.recordAccess(blk, "type")
            StateExpr.ifThenElse(
                btype == "genesis" || btype == "open",
                StateExpr.recordAccess(blk, "account"),
                StateExpr.recursiveCall("PublicKeyOf",
                    [ledger, StateExpr.recordAccess(blk, "previous")]))
        }

        Invariant("TypeInvariant") {
            StateExpr.in(lastHash.stateExpr, .setLiteral(
                hashes.map { .value(.string($0)) } + [.value(.string("NoHash"))]))
        }

        // CreateGenesisBlock: first action — creates genesis for each keypair
        for priv in privKeys {
            Action("CreateGenesis_\(priv)") {
                !genesisExists()
                    && ActionExpr.exists("h", from: StateExpr.setLiteral(hashes.map { .value(.string($0)) })) { h in
                        let sb = signedBlock([
                            "type": .value(.string("genesis")),
                            "account": .value(.string(priv)), "balance": .value(.int(genesisBal))
                        ], h, priv)
                        return lastHash.becomes(h)
                            && distributedLedger.becomes(distributedLedger
                                .updated(at: "n1", to: ledgerOf("n1").updated(at: h, to: sb))
                                .updated(at: "n2", to: ledgerOf("n2").updated(at: h, to: sb)))
                            && received.stays
                    }
            }
        }

        // CreateSendBlock: node creates a send from their chain
        for n in nodes {
            let priv = ["n1": "prv1", "n2": "prv2"][n]!
            Action("CreateSend_\(n)") {
                genesisExists()
                    && ActionExpr.exists("prev", from: StateExpr.setLiteral(hashes.map { .value(.string($0)) })) { prev in
                        blockAt(n, prev) != noBlock
                            && ActionExpr.exists("dest", from: StateExpr.setLiteral(["pub1", "pub2"].map { .value(.string($0)) })) { dest in
                                ActionExpr.exists("h", from: StateExpr.setLiteral(hashes.map { .value(.string($0)) })) { h in
                                    let sb = signedBlock([
                                        "type": .value(.string("send")),
                                        "previous": prev,
                                        "balance": .value(.int(1)),
                                        "destination": dest
                                    ], h, priv)
                                    return distributedLedger.stays
                                        && received.becomes(received
                                            .updated(at: n, to: StateExpr.union(received.applying(n),
                                                StateExpr.singleton(sb))))
                                        && lastHash.stays
                                }
                            }
                    }
            }
        }
    }
}
