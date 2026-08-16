import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct NanoBlockchainModel {
    public static var spec: TLASpec {
        let nodes = ["n1", "n2"]
        let hashes = ["h1", "h2", "h3"]
        let privKeys = ["prv1", "prv2"]
        let genesisBal = 3
        let noBlock: TLAValue = .record(["block": .record(["type": .string("NoBlock")]),
                                          "signature": .record(["data": .string("NoHash"), "signedWith": .string("NoPriv")])])

        let emptyLedger: TLAValue = .function(
            Dictionary(uniqueKeysWithValues: hashes.map { (.string($0), noBlock) }))
        let initDL: TLAValue = .function([.string("n1"): emptyLedger, .string("n2"): emptyLedger])
        let initRecv: TLAValue = .function([.string("n1"): .set([]), .string("n2"): .set([])])

        return #spec("NanoBlockchain") {
            Extends("Integers")

            let lastHash = Var<String>("lastHash")
            let distributedLedger = Var<TLAValue>("distributedLedger")
            let received = Var<TLAValue>("received")
            Variable(lastHash, "NoHash")
            Variable(distributedLedger, initDL)
            Variable(received, initRecv)

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

            for priv in privKeys {
                Action("CreateGenesis_\(priv)") {
                    lastHash == "NoHash"
                        && ActionExpr.exists("h", from: StateExpr.setLiteral(hashes.map { .value(.string($0)) })) { h in
                            let sb = StateExpr.recordLiteral([
                                "block": .recordLiteral([
                                    "type": .value(.string("genesis")),
                                    "account": .value(.string(priv)),
                                    "balance": .value(.int(genesisBal))
                                ]),
                                "signature": .recordLiteral(["data": h, "signedWith": .value(.string(priv))])
                            ])
                            return lastHash.becomes(Expr<String>(h))
                                && .assign(distributedLedger.name, distributedLedger.stateExpr
                                    .updated(at: "n1", to: distributedLedger.stateExpr.applying("n1").updated(at: h, to: sb))
                                    .updated(at: "n2", to: distributedLedger.stateExpr.applying("n2").updated(at: h, to: sb)))
                                && received.stays
                        }
                }
            }

            for n in nodes {
                let priv = ["n1": "prv1", "n2": "prv2"][n]!
                Action("CreateSend_\(n)") {
                    lastHash != "NoHash"
                        && ActionExpr.exists("prev", from: StateExpr.setLiteral(hashes.map { .value(.string($0)) })) { prev in
                            distributedLedger.stateExpr.applying(n).applying(prev) != noBlock
                                && ActionExpr.exists("dest", from: StateExpr.setLiteral(["pub1", "pub2"].map { .value(.string($0)) })) { dest in
                                    ActionExpr.exists("h", from: StateExpr.setLiteral(hashes.map { .value(.string($0)) })) { h in
                                        let sb = StateExpr.recordLiteral([
                                            "block": .recordLiteral([
                                                "type": .value(.string("send")),
                                                "previous": prev,
                                                "balance": .value(.int(1)),
                                                "destination": dest
                                            ]),
                                            "signature": .recordLiteral(["data": h, "signedWith": .value(.string(priv))])
                                        ])
                                        return distributedLedger.stays
                                            && .assign(received.name, received.stateExpr
                                                .updated(at: n, to: StateExpr.union(received.stateExpr.applying(n),
                                                    StateExpr.singleton(sb))))
                                            && lastHash.stays
                                    }
                                }
                        }
                }
            }
        }
    }
}

extension Example {
    public static let nanoBlockchain = Entry(
        id: "NanoBlockchain/Small",
        upstreamSpec: "NanoBlockchain",
        upstreamModule: "specifications/NanoBlockchain/Nano.tla",
        upstreamCfg: "specifications/NanoBlockchain/MCNanoSmall.cfg",
        expectedDistinct: 24577,
        spec: NanoBlockchainModel.spec,
        notes: "2 nodes, 3 hashes. Genesis + Create + Process blocks. DefineRecursive for chain walking.",
    )
}
