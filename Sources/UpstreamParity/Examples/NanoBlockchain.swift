import SwiftTLA
import SwiftTLAMacros

package struct NanoBlockchainModel: Sendable {
    package enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case n1
        case n2

        package static let defaultValue = Self.n1
        package static let finiteValues = allCases
    }

    package enum BlockHash: String, CaseIterable, FiniteTLAValueDomain {
        case h1
        case h2
        case h3

        package static let defaultValue = Self.h1
        package static let finiteValues = allCases
    }

    package enum HashReference: String, CaseIterable, FiniteTLAValueDomain {
        case none = "NoHash"
        case h1
        case h2
        case h3

        package static let defaultValue = Self.none
        package static let finiteValues = allCases

        fileprivate static func hash(_ hash: Expr<BlockHash>) -> Expr<Self> {
            Expr(hash.raw)
        }
    }

    package enum PrivateKey: String, CaseIterable, FiniteTLAValueDomain {
        case prv1
        case prv2

        package static let defaultValue = Self.prv1
        package static let finiteValues = allCases
    }

    package enum SigningKey: String, CaseIterable, FiniteTLAValueDomain {
        case none = "NoPriv"
        case prv1
        case prv2

        package static let defaultValue = Self.none
        package static let finiteValues = allCases

        fileprivate init(_ privateKey: PrivateKey) {
            switch privateKey {
            case .prv1: self = .prv1
            case .prv2: self = .prv2
            }
        }
    }

    package enum PublicKey: String, CaseIterable, FiniteTLAValueDomain {
        case pub1
        case pub2

        package static let defaultValue = Self.pub1
        package static let finiteValues = allCases
    }

    package enum Block: TLAValueType, Hashable, Sendable {
        case none
        case genesis(account: PrivateKey, balance: Int)
        case send(previous: BlockHash, balance: Int, destination: PublicKey)

        package static let defaultValue = Self.none

        package init?(formalValue: TLAValue) {
            guard case .record(let record) = formalValue,
                  let formalType = record.value(named: "type"),
                  let type = String(formalValue: formalType)
            else { return nil }

            switch type {
            case "NoBlock":
                guard Set(record.fields.map(\.name)) == ["type"] else { return nil }
                self = .none
            case "genesis":
                guard Set(record.fields.map(\.name)) == ["type", "account", "balance"],
                      let formalAccount = record.value(named: "account"),
                      let account = PrivateKey(formalValue: formalAccount),
                      let formalBalance = record.value(named: "balance"),
                      let balance = Int(formalValue: formalBalance)
                else { return nil }
                self = .genesis(account: account, balance: balance)
            case "send":
                guard Set(record.fields.map(\.name)) == ["type", "previous", "balance", "destination"],
                      let formalPrevious = record.value(named: "previous"),
                      let previous = BlockHash(formalValue: formalPrevious),
                      let formalBalance = record.value(named: "balance"),
                      let balance = Int(formalValue: formalBalance),
                      let formalDestination = record.value(named: "destination"),
                      let destination = PublicKey(formalValue: formalDestination)
                else { return nil }
                self = .send(previous: previous, balance: balance, destination: destination)
            default:
                return nil
            }
        }

        package var tlaValue: TLAValue {
            switch self {
            case .none:
                .record(["type": .string("NoBlock")])
            case .genesis(let account, let balance):
                .record([
                    "type": .string("genesis"),
                    "account": account.tlaValue,
                    "balance": balance.tlaValue,
                ])
            case .send(let previous, let balance, let destination):
                .record([
                    "type": .string("send"),
                    "previous": previous.tlaValue,
                    "balance": balance.tlaValue,
                    "destination": destination.tlaValue,
                ])
            }
        }

        fileprivate static func genesis(
            account: PrivateKey,
            balance: Int
        ) -> Expr<Self> {
            Expr(.record([
                "type": .value(.string("genesis")),
                "account": .value(account.tlaValue),
                "balance": .value(balance.tlaValue),
            ]))
        }

        fileprivate static func send(
            previous: Expr<BlockHash>,
            balance: Int,
            destination: Expr<PublicKey>
        ) -> Expr<Self> {
            Expr(.record([
                "type": .value(.string("send")),
                "previous": previous.raw,
                "balance": .value(balance.tlaValue),
                "destination": destination.raw,
            ]))
        }
    }

    package struct SignatureFields {
        package let data: HashReference
        package let signedWith: SigningKey
    }

    package enum SignatureSchema: TLARecordSchema {
        package typealias Fields = SignatureFields

        package static let fieldNames: Set<String> = ["data", "signedWith"]
        package static let defaultRecord: TLAValue = .record([
            "data": HashReference.none.tlaValue,
            "signedWith": SigningKey.none.tlaValue,
        ])

        package static func fieldName<Value>(for field: KeyPath<Fields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \Fields.data { return "data" }
            if key == \Fields.signedWith { return "signedWith" }
            return nil
        }

        package static let data = field(\Fields.data)
        package static let signedWith = field(\Fields.signedWith)
    }

    package struct SignedBlockFields {
        package let block: Block
        package let signature: Record<SignatureSchema>
    }

    package enum SignedBlockSchema: TLARecordSchema {
        package typealias Fields = SignedBlockFields

        package static let fieldNames: Set<String> = ["block", "signature"]
        package static let defaultRecord: TLAValue = .record([
            "block": Block.none.tlaValue,
            "signature": SignatureSchema.defaultRecord,
        ])

        package static func fieldName<Value>(for field: KeyPath<Fields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \Fields.block { return "block" }
            if key == \Fields.signature { return "signature" }
            return nil
        }

        package static let block = field(\Fields.block)
        package static let signature = field(\Fields.signature)
    }

    package typealias Signature = Record<SignatureSchema>
    package typealias SignedBlock = Record<SignedBlockSchema>
    package typealias Ledger = Function<BlockHash, SignedBlock>
    package typealias DistributedLedger = Function<Node, Ledger>
    package typealias ReceivedBlocks = Function<Node, SetExpr<SignedBlock>>

    package static var spec: TLASpec {
        #spec("NanoBlockchain") { scope in
            Extends(.integers)
            let lastHash = scope.sharedVar("lastHash", initial: HashReference.none)
            let distributedLedger: SharedVariable<DistributedLedger> = scope.sharedVar(
                "distributedLedger",
                initial: DistributedLedger()
            )
            let received: SharedVariable<ReceivedBlocks> = scope.sharedVar(
                "received",
                initial: ReceivedBlocks()
            )

            Invariant("TypeInvariant") {
                StateExpr.in(
                    lastHash.stateExpr,
                    SetExpr<HashReference>.literal(.none, .h1, .h2, .h3).stateExpr
                )
            }

            for privateKey in PrivateKey.finiteValues {
                SwiftTLA.Action("CreateGenesis_\(privateKey.rawValue)") {
                    lastHash == HashReference.none
                        && ActionExpr.exists(
                            "h",
                            from: SetExpr<BlockHash>.literal(.h1, .h2, .h3)
                        ) { formalHash in
                            let hash = Expr<BlockHash>(formalHash)
                            let signedBlock = signedBlock(
                                block: Block.genesis(
                                    account: privateKey,
                                    balance: 3
                                ),
                                hash: hash,
                                privateKey: privateKey
                            )
                            return lastHash.becomes(HashReference.hash(hash))
                                && distributedLedger.becomes(
                                    distributedLedger
                                        .updating(.n1) { ledger in
                                            ledger.updating(hash, to: signedBlock)
                                        }
                                        .updating(.n2) { ledger in
                                            ledger.updating(hash, to: signedBlock)
                                        }
                                )
                                && received.stays
                        }
                }
            }

            for (node, privateKey) in zip(Node.finiteValues, PrivateKey.finiteValues) {
                SwiftTLA.Action("CreateSend_\(node.rawValue)") {
                    StateExpr.not(lastHash == HashReference.none)
                        && ActionExpr.exists(
                            "prev",
                            from: SetExpr<BlockHash>.literal(.h1, .h2, .h3)
                        ) { formalPrevious in
                            let previous = Expr<BlockHash>(formalPrevious)
                            return StateExpr.not(
                                distributedLedger[node][previous] == SignedBlock.defaultValue
                            )
                                && ActionExpr.exists(
                                    "dest",
                                    from: SetExpr<PublicKey>.literal(.pub1, .pub2)
                                ) { formalDestination in
                                    let destination = Expr<PublicKey>(formalDestination)
                                    return ActionExpr.exists(
                                        "h",
                                        from: SetExpr<BlockHash>.literal(.h1, .h2, .h3)
                                    ) { formalHash in
                                        let hash = Expr<BlockHash>(formalHash)
                                        let signedBlock = signedBlock(
                                            block: Block.send(
                                                previous: previous,
                                                balance: 1,
                                                destination: destination
                                            ),
                                            hash: hash,
                                            privateKey: privateKey
                                        )
                                        return distributedLedger.stays
                                            && received.becomes(
                                                received.updating(node) { blocks in
                                                    blocks.inserting(signedBlock)
                                                }
                                            )
                                            && lastHash.stays
                                    }
                                }
                        }
                }
            }
        }
    }

    private static func signedBlock(
        block: Expr<Block>,
        hash: Expr<BlockHash>,
        privateKey: PrivateKey
    ) -> Expr<SignedBlock> {
        let signature = Signature.literal(
            .init(SignatureSchema.data, Expr<HashReference>(hash.raw)),
            .init(SignatureSchema.signedWith, SigningKey(privateKey))
        )
        return SignedBlock.literal(
            .init(SignedBlockSchema.block, block),
            .init(SignedBlockSchema.signature, signature)
        )
    }
}

extension Example {
    package static let nanoBlockchain = Entry(
        id: "NanoBlockchain/Small",
        upstreamSpec: "NanoBlockchain",
        upstreamModule: "specifications/NanoBlockchain/Nano.tla",
        upstreamCfg: "specifications/NanoBlockchain/MCNanoSmall.cfg",
        expectedDistinct: 24577,
        maximumStateLimit: 50_000,
        spec: NanoBlockchainModel.spec,
        notes: "2 nodes and 3 hashes with typed blocks, signatures, ledgers, and received sets."
    )
}
