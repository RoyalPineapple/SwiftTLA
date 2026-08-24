import SwiftTLA
import SwiftTLAMacros

public struct NanoBlockchainModel: Sendable {
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
            Extends(.integers)

            let lastHash = Var<String>("lastHash")
            let distributedLedger = Var<TLAValue>("distributedLedger")
            let received = Var<TLAValue>("received")
            Variable(lastHash, "NoHash")
            Variable(distributedLedger, initDL)
            Variable(received, initRecv)

            Invariant("TypeInvariant") {
                StateExpr.in(lastHash.stateExpr, .setLiteral(
                    hashes.map { .value(.string($0)) } + [.value(.string("NoHash"))]))
            }

            for priv in privKeys {
                Action("CreateGenesis_\(priv)") {
                    lastHash == "NoHash"
                        && ActionExpr.exists("h", from: StateExpr.setLiteral(hashes.map { .value(.string($0)) })) { h in
                            let sb = StateExpr.record([
                                "block": StateExpr.record([
                                    "type": .value(.string("genesis")),
                                    "account": .value(.string(priv)),
                                    "balance": .value(.int(genesisBal))
                                ]),
                                "signature": StateExpr.record(["data": h, "signedWith": .value(.string(priv))])
                            ])
                            return lastHash.becomes(Expr<String>(h))
                                && .assign(.named(distributedLedger.name), distributedLedger.stateExpr
                                    .updated(at: "n1", to: distributedLedger.stateExpr.applying("n1").updated(at: h, to: sb))
                                    .updated(at: "n2", to: distributedLedger.stateExpr.applying("n2").updated(at: h, to: sb)))
                                && received.stays
                        }
                }
            }

            for (n, priv) in zip(nodes, privKeys) {
                Action("CreateSend_\(n)") {
                    lastHash != "NoHash"
                        && ActionExpr.exists("prev", from: StateExpr.setLiteral(hashes.map { .value(.string($0)) })) { prev in
                            distributedLedger.stateExpr.applying(n).applying(prev) != noBlock
                                && ActionExpr.exists("dest", from: StateExpr.setLiteral(["pub1", "pub2"].map { .value(.string($0)) })) { dest in
                                    ActionExpr.exists("h", from: StateExpr.setLiteral(hashes.map { .value(.string($0)) })) { h in
                                        let sb = StateExpr.record([
                                            "block": StateExpr.record([
                                                "type": .value(.string("send")),
                                                "previous": prev,
                                                "balance": .value(.int(1)),
                                                "destination": dest
                                            ]),
                                            "signature": StateExpr.record(["data": h, "signedWith": .value(.string(priv))])
                                        ])
                                        return distributedLedger.stays
                                            && .assign(.named(received.name), received.stateExpr
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
        notes: "2 nodes, 3 hashes. Genesis and CreateSend transitions.",
    )
}
