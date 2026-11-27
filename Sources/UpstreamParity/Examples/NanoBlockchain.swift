// Nodes create and sign blocks, then validate received blocks against their own ledgers.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/NanoBlockchain/MCNano.tla
import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct NanoBlockchainModel: Sendable {
    package enum Atom: String, CaseIterable, FiniteTLAValueDomain {
        case h1, h2, h3, h4, h5, prv1, prv2, pub1, pub2, n1, n2
        case noHash = "NoHashVal", noBlock = "NoBlockVal"
        package static var defaultValue: Self { .noHash }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package struct Genesis: Hashable, Sendable {
        package let type: String
        package let account: Atom
        package let balance: Int
    }

    package struct Send: Hashable, Sendable {
        package let type: String
        package let previous: Atom
        package let balance: Int
        package let destination: Atom
    }

    package struct Open: Hashable, Sendable {
        package let type: String
        package let account: Atom
        package let source: Atom
        package let rep: Atom
    }

    package struct Receive: Hashable, Sendable {
        package let type: String
        package let previous: Atom
        package let source: Atom
    }

    package struct Change: Hashable, Sendable {
        package let type: String
        package let previous: Atom
        package let rep: Atom
    }

    package typealias AccountBlock = OneOf<Genesis, Open>
    package typealias Continuation = OneOf<Receive, Change>
    package typealias PreviousBlock = OneOf<Send, Continuation>
    package typealias Block = OneOf<AccountBlock, PreviousBlock>
    package struct Signature: Hashable, Sendable {
        package let data: Atom
        package let signedWith: Atom
    }
    package struct SignedBlock: Hashable, Sendable {
        package let block: Block
        package let signature: Signature
    }
    package typealias HashEntry = OneOf<Atom, Block>
    package typealias LedgerEntry = OneOf<Atom, SignedBlock>
    package typealias Ledger = Dictionary<Atom, LedgerEntry>
    private enum Step: String, CaseIterable { case next = "Next" }

    package static var spec: TLASpec {
        #spec("MCNano") { scope in
            let Hash = scope.parameter(as: Set<Atom>.self, in: Subsets(of: Set<Atom>([.h1, .h2, .h3, .h4, .h5])))
            let Node = Set<Atom>([.n1, .n2])
            let PrivateKey = Set<Atom>([.prv1, .prv2])
            let PublicKey = Set<Atom>([.pub1, .pub2])
            let GenesisBalance = 3
            let balances = IntRange(0, through: GenesisBalance)
            let keyPair = Select(from: Functions(from: PrivateKey, to: PublicKey)) { mapping in
                PublicKey.allSatisfy { key in PrivateKey.contains { signer in mapping[signer] == key } }
            }
            let ownership = Select(from: Functions(from: Node, to: PrivateKey)) { mapping in
                PrivateKey.allSatisfy { key in Node.contains { node in mapping[node] == key } }
            }
            let absent: LedgerEntry = LedgerEntry.first(Atom.noBlock)
            let unused: HashEntry = HashEntry.first(Atom.noBlock)
            let hashFunction = scope.sharedVar(initial: Dictionary<Atom, HashEntry>.mapping(over: Hash) { _ in unused })
            let lastHash = scope.sharedVar(initial: Atom.noHash)
            let distributedLedger = scope.sharedVar(initial: Dictionary<Atom, Ledger>.mapping(over: Node) { _ in
                Dictionary<Atom, LedgerEntry>.mapping(over: Hash) { _ in absent }
            })
            let received = scope.sharedVar(initial: Dictionary<Atom, Set<SignedBlock>>.mapping(over: Node) { _ in Set<SignedBlock>() })

            FormalDefinition("BlockAt", taking: Ledger.self, Atom.self) { ledger, h -> Expr<Block> in
                ledger[h].assuming(SignedBlock.self).block
            }
            FormalDefinition("ParentHash", taking: Block.self) { b -> Expr<Atom> in
                If(b.recordFields.contains("balance"), then: b.assuming(Send.self).previous,
                   else: If(b.recordFields.contains("source"), then: b.assuming(Receive.self).previous,
                            else: b.assuming(Change.self).previous))
            }
            FormalDefinition("AccountOf", taking: Block.self) { b -> Expr<Atom> in
                If(b.recordFields.contains("balance"), then: b.assuming(Genesis.self).account,
                   else: b.assuming(Open.self).account)
            }
            FormalDefinition("PublicKeyOf", taking: Ledger.self, Atom.self) { ledger, blockHash -> Expr<Atom> in
                LetRec("owner", taking: Atom.self, { (owner: LocalRecursion<Atom, Atom>, h: WithValue<Atom>) in
                    If(FormalCall(as: Block.self, "BlockAt", ledger, h).recordFields.contains("account"),
                       then: FormalCall(as: Atom.self, "AccountOf", FormalCall(as: Block.self, "BlockAt", ledger, h)),
                       else: owner(FormalCall(as: Atom.self, "ParentHash", FormalCall(as: Block.self, "BlockAt", ledger, h))))
                }, in: { owner in owner(blockHash) })
            }
            FormalDefinition("SourceHash", taking: Block.self) { b -> Expr<Atom> in
                If(b.recordFields.contains("account"), then: b.assuming(Open.self).source, else: b.assuming(Receive.self).source)
            }
            FormalDefinition("SendAtSource", taking: Ledger.self, Block.self) { ledger, b -> Expr<Send> in
                FormalCall(as: Block.self, "BlockAt", ledger, FormalCall(as: Atom.self, "SourceHash", b)).assuming(Send.self)
            }
            FormalDefinition("BalanceAt", taking: Ledger.self, Atom.self) { ledger, start -> Expr<Int> in
                LetRec("balance", taking: Atom.self, { (balance: LocalRecursion<Atom, Int>, h: WithValue<Atom>) in
                    If(FormalCall(as: Block.self, "BlockAt", ledger, h).recordFields.contains("balance"),
                       then: If(FormalCall(as: Block.self, "BlockAt", ledger, h).recordFields.contains("account"),
                                then: FormalCall(as: Block.self, "BlockAt", ledger, h).assuming(Genesis.self).balance,
                                else: FormalCall(as: Block.self, "BlockAt", ledger, h).assuming(Send.self).balance),
                       else: If(FormalCall(as: Block.self, "BlockAt", ledger, h).recordFields.contains("account"),
                                then: 0, else: balance(FormalCall(as: Atom.self, "ParentHash", FormalCall(as: Block.self, "BlockAt", ledger, h))))
                           + If(FormalCall(as: Block.self, "BlockAt", ledger, h).recordFields.contains("source"),
                                then: balance(FormalCall(as: Send.self, "SendAtSource", ledger, FormalCall(as: Block.self, "BlockAt", ledger, h)).previous)
                                    - FormalCall(as: Send.self, "SendAtSource", ledger, FormalCall(as: Block.self, "BlockAt", ledger, h)).balance,
                                else: 0))
                }, in: { balance in balance(start) })
            }
            let freeHashes = Hash.filter { h in hashFunction[h] == unused }
            FormalDefinition("HashOf", taking: Block.self) { b -> Expr<Atom> in
                If(Hash.contains { h in hashFunction[h] == HashEntry.second(b) },
                   then: Select(from: Hash) { h in hashFunction[h] == HashEntry.second(b) },
                   else: Select(from: freeHashes) { _ in true })
            }
            let broadcast = Macro { (b: MacroParameter<Block>, signer: MacroParameter<Atom>) in
                let h = FormalCall(as: Atom.self, "HashOf", b)
                let signed = SignedBlock.expression(block: b, signature: Signature.expression(data: h, signedWith: signer))
                Let(signed) { message in
                    received.set(Dictionary<Atom, Set<SignedBlock>>.mapping(over: Node) { n in received[n].inserting(message) })
                }
                lastHash.set(h)
                hashFunction[h].set(HashEntry.second(b))
            }

            Do(Step.next) {
                Either {
                    When(freeHashes.isEmpty) { Skip() }
                    When(!freeHashes.isEmpty) {
                        Either {
                            When(lastHash == Atom.noHash) {
                                With(PrivateKey) { key in
                                    let b = Block.first(AccountBlock.first(Genesis.expression(type: "genesis", account: keyPair[key], balance: GenesisBalance)))
                                    let h = FormalCall(as: Atom.self, "HashOf", b)
                                    let signed = SignedBlock.expression(block: b, signature: Signature.expression(data: h, signedWith: key))
                                    distributedLedger.set(Dictionary<Atom, Ledger>.mapping(over: Node) { n in
                                        Dictionary<Atom, LedgerEntry>.mapping(over: Hash) { slot in
                                            If(slot == h, then: LedgerEntry.second(signed), else: distributedLedger[n][slot])
                                        }
                                    })
                                    lastHash.set(h)
                                    hashFunction[h].set(HashEntry.second(b))
                                }
                            }
                            When(true) {
                                With(Node) { n in
                                    let ledger = distributedLedger[n]
                                    let signer = ownership[n]
                                    let account = keyPair[signer]
                                    Either {
                                        When(true) {
                                            With(PublicKey, Hash) { rep, src in
                                                When(ledger[src] != absent)
                                                let send = FormalCall(as: Block.self, "BlockAt", ledger, src)
                                                When(send.recordFields.contains("destination") && send.assuming(Send.self).destination == account)
                                                broadcast(Block.first(AccountBlock.second(Open.expression(type: "open", account: account, source: src, rep: rep))), signer)
                                            }
                                        }
                                        When(true) {
                                            With(Hash) { prev in
                                                When(ledger[prev] != absent && FormalCall(as: Atom.self, "PublicKeyOf", ledger, prev) == account)
                                                Either {
                                                    When(true) {
                                                        With(PublicKey, balances) { recipient, amount in
                                                            When(amount <= FormalCall(as: Int.self, "BalanceAt", ledger, prev))
                                                            broadcast(Block.second(PreviousBlock.first(Send.expression(type: "send", previous: prev, balance: amount, destination: recipient))), signer)
                                                        }
                                                    }
                                                    When(true) {
                                                        With(Hash) { src in
                                                            When(ledger[src] != absent)
                                                            let send = FormalCall(as: Block.self, "BlockAt", ledger, src)
                                                            When(send.recordFields.contains("destination") && send.assuming(Send.self).destination == account)
                                                            broadcast(Block.second(PreviousBlock.second(Continuation.first(Receive.expression(type: "receive", previous: prev, source: src)))), signer)
                                                        }
                                                    }
                                                    When(true) {
                                                        With(PublicKey) { rep in
                                                            broadcast(Block.second(PreviousBlock.second(Continuation.second(Change.expression(type: "change", previous: prev, rep: rep)))), signer)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            When(true) {
                                With(Node) { n in
                                    With(received[n]) { message in
                                        let b = message.block
                                        let ledger = distributedLedger[n]
                                        let h = FormalCall(as: Atom.self, "HashOf", b)
                                        let signer = keyPair[message.signature.signedWith]
                                        When(message.signature.data == h)
                                        If(b.recordFields.contains("account")) {
                                            When(b.recordFields.contains("source"))
                                            let opened = b.assuming(Open.self)
                                            When(ledger[opened.source] != absent)
                                            let send = FormalCall(as: Block.self, "BlockAt", ledger, opened.source)
                                            When(send.recordFields.contains("destination") && send.assuming(Send.self).destination == opened.account)
                                            When(signer == opened.account)
                                            When(!Hash.contains { x in ledger[x] != absent && FormalCall(as: Block.self, "BlockAt", ledger, x).recordFields.contains("account")
                                                && FormalCall(as: Atom.self, "AccountOf", FormalCall(as: Block.self, "BlockAt", ledger, x)) == opened.account })
                                        } else: {
                                            let prev = FormalCall(as: Atom.self, "ParentHash", b)
                                            When(ledger[prev] != absent && FormalCall(as: Atom.self, "PublicKeyOf", ledger, prev) == signer)
                                            If(b.recordFields.contains("balance")) {
                                                When(b.assuming(Send.self).balance <= FormalCall(as: Int.self, "BalanceAt", ledger, prev))
                                            } else: {
                                                If(b.recordFields.contains("source")) {
                                                    let src = b.assuming(Receive.self).source
                                                    When(ledger[src] != absent)
                                                    let send = FormalCall(as: Block.self, "BlockAt", ledger, src)
                                                    When(send.recordFields.contains("destination") && send.assuming(Send.self).destination == signer)
                                                    When(!Hash.contains { x in ledger[x] != absent && FormalCall(as: Block.self, "BlockAt", ledger, x).recordFields.contains("source")
                                                        && FormalCall(as: Atom.self, "SourceHash", FormalCall(as: Block.self, "BlockAt", ledger, x)) == src })
                                                }
                                            }
                                        }
                                        distributedLedger[n][h].set(LedgerEntry.second(message))
                                        received[n].remove(message)
                                        lastHash.set(h)
                                        hashFunction[h].set(HashEntry.second(b))
                                    }
                                }
                            }
                        }
                    }
                }
            }

            FormalDefinition("IsBlock", taking: Block.self) { b -> Expr<Bool> in
                (b.recordFields == Set<String>(["type", "account", "balance"])
                    && b.assuming(Genesis.self).type == "genesis"
                    && PublicKey.contains(b.assuming(Genesis.self).account)
                    && b.assuming(Genesis.self).balance == GenesisBalance)
                || (b.recordFields == Set<String>(["type", "previous", "balance", "destination"])
                    && b.assuming(Send.self).type == "send"
                    && Hash.contains(b.assuming(Send.self).previous)
                    && balances.contains(b.assuming(Send.self).balance)
                    && PublicKey.contains(b.assuming(Send.self).destination))
                || (b.recordFields == Set<String>(["type", "account", "source", "rep"])
                    && b.assuming(Open.self).type == "open"
                    && PublicKey.contains(b.assuming(Open.self).account)
                    && Hash.contains(b.assuming(Open.self).source)
                    && PublicKey.contains(b.assuming(Open.self).rep))
                || (b.recordFields == Set<String>(["type", "previous", "source"])
                    && b.assuming(Receive.self).type == "receive"
                    && Hash.contains(b.assuming(Receive.self).previous)
                    && Hash.contains(b.assuming(Receive.self).source))
                || (b.recordFields == Set<String>(["type", "previous", "rep"])
                    && b.assuming(Change.self).type == "change"
                    && Hash.contains(b.assuming(Change.self).previous)
                    && PublicKey.contains(b.assuming(Change.self).rep))
            }
            FormalDefinition("IsSignedBlock", taking: SignedBlock.self) { b -> Expr<Bool> in
                FormalCall(as: Bool.self, "IsBlock", b.block) && Hash.contains(b.signature.data) && PrivateKey.contains(b.signature.signedWith)
            }
            Invariant("TypeInvariant") {
                hashFunction.keys == Hash
                Hash.allSatisfy { h in hashFunction[h] == unused || FormalCall(as: Bool.self, "IsBlock", hashFunction[h].assuming(Block.self)) }
                Hash.contains(lastHash) || lastHash == Atom.noHash
                distributedLedger.keys == Node
                received.keys == Node
                Node.allSatisfy { n in
                    distributedLedger[n].keys == Hash && Hash.allSatisfy { h in
                        distributedLedger[n][h] == absent || FormalCall(as: Bool.self, "IsSignedBlock", distributedLedger[n][h].assuming(SignedBlock.self))
                    } && received[n].allSatisfy { b in FormalCall(as: Bool.self, "IsSignedBlock", b) }
                }
            }
            Invariant("SafetyInvariant") {
                Node.allSatisfy { n in Hash.allSatisfy { h in
                    distributedLedger[n][h] == absent || (distributedLedger[n][h].assuming(SignedBlock.self).signature.data == h
                        && keyPair[distributedLedger[n][h].assuming(SignedBlock.self).signature.signedWith] == FormalCall(as: Atom.self, "PublicKeyOf", distributedLedger[n], h))
                } }
            }
            Validation("Small") {
                Bind(Hash, to: Set<Atom>([.h1, .h2, .h3]))
            }.viewing(Pair.literal(distributedLedger, received))
            Validation("Medium") {
                Bind(Hash, to: Set<Atom>([.h1, .h2, .h3, .h4]))
            }.viewing(Pair.literal(distributedLedger, received))
            Validation("Large") {
                Bind(Hash, to: Set<Atom>([.h1, .h2, .h3, .h4, .h5]))
            }.viewing(Pair.literal(distributedLedger, received))
        }
    }
}
