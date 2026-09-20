import SwiftTLA
import SwiftTLAMacros

/// The bounded KeyValueStore snapshot-isolation model from the upstream
/// PlusCal corpus.
///
/// `ops` deliberately remains process-local.  `family(for:)` is used only by
/// the published cross-transaction invariant, where the upstream model reads
/// the complete generated local function through `Range(ops)`.
@TLAModel
package struct KVsnapModel: Sendable {
    package static let corpusEntry = CanonicalCorpusEntry(
        id: "kvsnap-upstream-port",
        rendered: { try KVsnapModel.render() }
    )

    package enum Key: String, CaseIterable, FiniteTLAValueDomain {
        case k1, k2

        package var tlaValue: TLAValue { .constant(rawValue) }

        package init?(formalValue: TLAValue) {
            guard case .constant(let rawValue) = formalValue else { return nil }
            self.init(rawValue: rawValue)
        }
    }

    package enum Transaction: String, CaseIterable, FiniteTLAValueDomain {
        case t1, t2, t3

        package var tlaValue: TLAValue { .constant(rawValue) }

        package init?(formalValue: TLAValue) {
            guard case .constant(let rawValue) = formalValue else { return nil }
            self.init(rawValue: rawValue)
        }
    }

    package enum NoValue: String, CaseIterable, FiniteTLAValueDomain {
        case noVal = "NoVal"

        package var tlaValue: TLAValue { .constant(rawValue) }

        package init?(formalValue: TLAValue) {
            guard case .constant(let rawValue) = formalValue else { return nil }
            self.init(rawValue: rawValue)
        }
    }

    package enum OperationKind: String, CaseIterable, FiniteTLAValueDomain {
        case read, write
    }

    package typealias Value = OneOf<Transaction, NoValue>

    package struct Operation: Hashable, Sendable {
        package let op: OperationKind
        package let key: Key
        package let value: Value
    }

    private enum Step: String, CaseIterable {
        case start = "START"
        case read = "READ"
        case update = "UPDATE"
        case commit = "COMMIT"
    }

    package static var spec: TLASpec {
        #spec("KVsnap") {
            Extends(.integers, .sequences, .finiteSets)
            Import(KeyValueStoreUtil.module)

            // These upstream model values retain their TLA+ identities and
            // bind through the emitted configuration.
            Constant("k1", Key.k1)
            Constant("k2", Key.k2)
            Constant("t1", Transaction.t1)
            Constant("t2", Transaction.t2)
            Constant("t3", Transaction.t3)
            Constant("NoVal", NoValue.noVal)
            Symmetry("TxId", Set(Transaction.all))

            Instance("CC", of: ClientCentric.module, with: [
                ModuleArgument("Keys", value: SetExpr<Key>.literal(.k1, .k2)),
                ModuleArgument("Values", value: SetExpr<Value>.literal(
                    Value.first(.t1), Value.first(.t2), Value.first(.t3), Value.second(.noVal)
                )),
            ])
            FormalDefinition(
                "InitialState",
                parameters: [],
                body: Function<Key, Value>.mapping { _ in Value.second(Expr<NoValue>(.noVal)) }.raw
            )
            Algorithm("KVsnap", scoped: { scope in
                let store: SharedVariable<Function<Key, Value>> = scope.sharedVar(initial: FormalCall("InitialState"))
                let tx = scope.sharedVar(initial: SetExpr<Transaction>())
                let missed = scope.sharedVar(initial: Function<Transaction, SetExpr<Key>>.mapping { _ in SetExpr<Key>() })

                Each(Transaction.all, fairness: .weak, scoped: { selfID, scope in
                    let snapshotStore: LocalVariable<Function<Key, Value>> = scope.localVar(initial: FormalCall("InitialState")
                    )
                    let read_keys: LocalVariable<SetExpr<Key>> = scope.localVar(initial: SetExpr<Key>())
                    let write_keys: LocalVariable<SetExpr<Key>> = scope.localVar(initial: SetExpr<Key>())
                    let ops: LocalVariable<[Operation]> = scope.localVar(initial: [])

                    Do(Step.start) {
                        Assign(tx, to: tx.inserting(selfID))
                        Assign(snapshotStore, to: store)
                        With(NonEmptySubsets(of: SetExpr<Key>.literal(.k1, .k2))) { reads in
                            With(NonEmptySubsets(of: SetExpr<Key>.literal(.k1, .k2))) { writes in
                                Assign(read_keys, to: reads.expr)
                                Assign(write_keys, to: writes.expr)
                            }
                        }
                    }

                    Do(Step.read) {
                        let reads: Expr<Set<Operation>> = read_keys.expr.mapping { key in
                            ModuleCall(as: Operation.self, "CC", "r", key.expr, snapshotStore[key.expr])
                        }
                        Assign(
                            ops,
                            to: ops.expr.concatenating(
                                InjectiveSequence(from: reads)
                            )
                        )
                    }

                    Do(Step.update) {
                        Assign(snapshotStore, to: Function<Key, Value>.mapping { key in
                            If(
                                write_keys.expr.contains(key),
                                then: Value.first(selfID.expr),
                                else: snapshotStore[key.expr]
                            )
                        })
                    }

                    Do(Step.commit) {
                        If(missed[selfID].intersection(write_keys.expr).isEmpty) {
                            Let(tx.removing(selfID.expr)) { committedTransactions in
                                Assign(tx, to: committedTransactions.expr)
                                Assign(missed, to: Function<Transaction, SetExpr<Key>>.mapping { other in
                                    If(
                                        committedTransactions.expr.contains(other),
                                        then: missed[other.expr].union(write_keys.expr),
                                        else: missed[other.expr]
                                    )
                                })
                                Assign(store, to: Function<Key, Value>.mapping { key in
                                    If(
                                        write_keys.expr.contains(key),
                                        then: snapshotStore[key.expr],
                                        else: store[key.expr]
                                    )
                                })
                                let writes: Expr<Set<Operation>> = write_keys.expr.mapping { key in
                                    ModuleCall(as: Operation.self, "CC", "w", key.expr, Value.first(selfID.expr))
                                }
                                Assign(
                                    ops,
                                    to: ops.expr.concatenating(
                                        InjectiveSequence(from: writes)
                                    )
                                )
                            }
                        }
                    }

                    Invariant("SnapshotIsolation") {
                        ModuleCall(
                            as: Bool.self,
                            "CC", "SnapshotIsolation",
                            FormalCall(as: Function<Key, Value>.self, "InitialState"),
                            Range(ops.family(for: Transaction.self))
                        )
                    }
                })

                Invariant("TypeOK") {
                    Functions(from: Key.all, to: SetExpr<Value>.literal(
                        Value.first(.t1), Value.first(.t2), Value.first(.t3), Value.second(.noVal)
                    )).contains(store.expr)
                        && tx.isSubset(of: SetExpr<Transaction>.literal(.t1, .t2, .t3))
                        && Functions(
                            from: Transaction.all,
                            to: Subsets(of: SetExpr<Key>.literal(.k1, .k2))
                        ).contains(missed.expr)
                }
                Eventually("Termination", ForAll(Transaction.all) { Finished($0) })
            })
        }
    }
}
