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
        specification: { KVsnapModel.spec },
        swiftConfiguration: .init(
            checks: [
                .init("TypeOK", kind: .invariant),
                .init("SnapshotIsolation", kind: .invariant),
                .init("Termination", kind: .property)
            ],
            constants: [
                .init("k1", "k1"), .init("k2", "k2"),
                .init("t1", "t1"), .init("t2", "t2"), .init("t3", "t3"),
                .init("NoVal", "NoVal")
            ]
        ),
        plusCalConfiguration: .init(
            checks: [
                .init("TypeOK", kind: .invariant),
                .init("SnapshotIsolation", kind: .invariant),
                .init("Termination", kind: .property)
            ],
            constants: [
                .init("k1", "k1"), .init("k2", "k2"),
                .init("t1", "t1"), .init("t2", "t2"), .init("t3", "t3"),
                .init("NoVal", "NoVal")
            ]
        )
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

    package enum NoValue: String, TLAValueType {
        case noVal = "NoVal"

        package var tlaValue: TLAValue { .constant(rawValue) }

        package init?(formalValue: TLAValue) {
            guard case .constant(let rawValue) = formalValue else { return nil }
            self.init(rawValue: rawValue)
        }
    }

    package enum OperationKind: String, TLAValueType {
        case read, write
    }

    package typealias Value = OneOf<Transaction, NoValue>

    package struct OperationFields {
        package let operation: OperationKind
        package let key: Key
        package let value: Value
    }

    package enum OperationSchema: TLARecordSchema {
        package typealias Fields = OperationFields

        package static let fields: [TLARecordFieldDeclaration<Self>] = [
            .init(operation, default: OperationKind.read),
            .init(key, default: Key.k1),
            .init(value, default: Value.second(.noVal)),
        ]

        package static func fieldName<Value>(for field: KeyPath<OperationFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \OperationFields.operation { return "op" }
            if key == \OperationFields.key { return "key" }
            if key == \OperationFields.value { return "value" }
            return nil
        }

        package static let operation = field(\OperationFields.operation)
        package static let key = field(\OperationFields.key)
        package static let value = field(\OperationFields.value)
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
                let store: SharedVariable<Function<Key, Value>> = scope.sharedVar("store", initial: FormalCall("InitialState"))
                let tx = scope.sharedVar("tx", initial: SetExpr<Transaction>())
                let missed = scope.sharedVar("missed", initial: Function<Transaction, SetExpr<Key>>.mapping { _ in SetExpr<Key>() })

                Each(Transaction.all, fairness: .weak, scoped: { selfID, scope in
                    let snapshotStore: LocalVariable<Function<Key, Value>> = scope.localVar("snapshotStore", initial: FormalCall("InitialState")
                    )
                    let readKeys: LocalVariable<SetExpr<Key>> = scope.localVar("readKeys", initial: SetExpr<Key>())
                    let writeKeys: LocalVariable<SetExpr<Key>> = scope.localVar("writeKeys", initial: SetExpr<Key>())
                    let ops: LocalVariable<TupleExpr<Record<OperationSchema>>> = scope.localVar("ops", initial: TupleExpr<Record<OperationSchema>>())

                    Do(Step.start) {
                        Assign(tx, to: tx.inserting(selfID))
                        Assign(snapshotStore, to: store)
                        With(NonEmptySubsets(of: SetExpr<Key>.literal(.k1, .k2))) { reads in
                            With(NonEmptySubsets(of: SetExpr<Key>.literal(.k1, .k2))) { writes in
                                Assign(readKeys, to: reads.expr)
                                Assign(writeKeys, to: writes.expr)
                            }
                        }
                    }

                    Do(Step.read) {
                        let reads: Expr<SetExpr<Record<OperationSchema>>> = readKeys.expr.mapping { key in
                            ModuleCall("CC", "r", key.expr, snapshotStore[key.expr])
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
                                writeKeys.expr.contains(key),
                                then: Value.first(selfID.expr),
                                else: snapshotStore[key.expr]
                            )
                        })
                    }

                    Do(Step.commit) {
                        If(missed[selfID].intersection(writeKeys.expr).isEmpty) {
                            Let(tx.removing(selfID.expr)) { committedTransactions in
                                Assign(tx, to: committedTransactions.expr)
                                Assign(missed, to: Function<Transaction, SetExpr<Key>>.mapping { other in
                                    If(
                                        committedTransactions.expr.contains(other),
                                        then: missed[other.expr].union(writeKeys.expr),
                                        else: missed[other.expr]
                                    )
                                })
                                Assign(store, to: Function<Key, Value>.mapping { key in
                                    If(
                                        writeKeys.expr.contains(key),
                                        then: snapshotStore[key.expr],
                                        else: store[key.expr]
                                    )
                                })
                                let writes: Expr<SetExpr<Record<OperationSchema>>> = writeKeys.expr.mapping { key in
                                    ModuleCall("CC", "w", key.expr, Value.first(selfID.expr))
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
                Eventually("Termination", All(Transaction.all) { Finished($0) })
            })
        }
    }
}
