// Transactions take snapshots. A commit succeeds only if no concurrent commit touched its writes.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/KeyValueStore/KeyValueStore.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct TransactionalKeyValueStoreModel: Sendable {
    package enum Key: String, CaseIterable, FiniteTLAValueDomain {
        case k1, k2
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum Transaction: String, CaseIterable, FiniteTLAValueDomain {
        case t1, t2, t3
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum Value: String, CaseIterable, FiniteTLAValueDomain {
        case v1, v2, absent = "NoVal"
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case open = "OpenTx"
        case next = "Next"
    }

    package static var spec: TLASpec {
        #spec("MCKVS") { scope in
            let keys = Set<Key>([Key.k1, Key.k2])
            let values = SetExpr<Value>.literal(.v1, .v2)
            let transactions = SetExpr<Transaction>.literal(.t1, .t2, .t3)
            let emptyStore = Dictionary<Key, Value>.mapping(over: keys) { _ in Value.absent.expr }
            let emptyLog = Dictionary<Transaction, Set<Key>>.mapping(over: transactions) { _ in Set<Key>() }
            let store = scope.sharedVar(initial: emptyStore)
            let tx = scope.sharedVar(initial: Set<Transaction>())
            let snapshotStore = scope.sharedVar(initial: Dictionary<Transaction, [Key: Value]>.mapping(over: transactions) { _ in emptyStore })
            let written = scope.sharedVar(initial: emptyLog)
            let missed = scope.sharedVar(initial: emptyLog)

            Do(Step.open, over: transactions) { transaction in
                When(!tx.contains(transaction))
                tx.insert(transaction)
                snapshotStore[transaction].set(store)
            }

            // The published Next chooses an open transaction internally for every remaining operation.
            Do(Step.next) {
                With(tx) { transaction in
                    Either {
                        When(true) {
                            With(keys) { key in
                                With(values) { value in
                                    // Add and Update both write a different value and mark the same key.
                                    When(snapshotStore[transaction][key] != value)
                                    snapshotStore[transaction].set(snapshotStore[transaction].updating(key, to: value))
                                    written[transaction].set(written[transaction].inserting(key))
                                }
                            }
                        }
                        When(true) {
                            With(keys) { key in
                                When(snapshotStore[transaction][key] != Value.absent)
                                snapshotStore[transaction].set(snapshotStore[transaction].updating(key, to: Value.absent.expr))
                                written[transaction].set(written[transaction].inserting(key))
                            }
                        }
                        When(true) {
                            tx.remove(transaction)
                            snapshotStore[transaction].set(emptyStore)
                            written[transaction].set(Set<Key>())
                            missed[transaction].set(Set<Key>())
                        }
                        When(missed[transaction].intersection(written[transaction]).isEmpty) {
                            store.set(Dictionary<Key, Value>.mapping(over: keys) { key in
                                If(written[transaction].contains(key), then: snapshotStore[transaction][key], else: store[key])
                            })
                            missed.set(Dictionary<Transaction, Set<Key>>.mapping(over: transactions) { other in
                                If(other != transaction && tx.contains(other), then: missed[other].union(written[transaction]), else: Set<Key>())
                            })
                            tx.remove(transaction)
                            snapshotStore[transaction].set(emptyStore)
                            written[transaction].set(Set<Key>())
                        }
                    }
                }
            }

            let stores = Functions(from: keys, to: values.inserting(Value.absent))
            Invariant("TypeInvariant") {
                stores.contains(store) && tx.isSubset(of: transactions)
                    && Functions(from: transactions, to: stores).contains(snapshotStore)
                    && Functions(from: transactions, to: Subsets(of: keys)).contains(written)
                    && Functions(from: transactions, to: Subsets(of: keys)).contains(missed)
            }
            Invariant("TxLifecycle") {
                tx.allSatisfy { transaction in
                    keys.allSatisfy { key in
                        store[key] == snapshotStore[transaction][key] || written[transaction].contains(key) || missed[transaction].contains(key)
                    }
                }
                transactions.subtracting(tx).allSatisfy { transaction in
                    keys.allSatisfy { key in snapshotStore[transaction][key] == Value.absent }
                        && written[transaction].isEmpty && missed[transaction].isEmpty
                }
            }

            Validation("Small") {}
        }
    }
}
