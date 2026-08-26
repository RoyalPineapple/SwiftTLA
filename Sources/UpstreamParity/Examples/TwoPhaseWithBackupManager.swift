import SwiftTLA
import SwiftTLAMacros

/// The upstream PlusCal two-phase-commit model with a backup transaction manager.
///
/// The published configuration fixes both failure switches to `TRUE`. This port
/// keeps that bounded configuration and expresses its three fair process groups,
/// typed state functions, and `Prepare`, `Decide`, and `Fail` statement macros.
package struct TwoPhaseWithBackupManagerModel: Sendable {
    package enum ResourceManager: String, CaseIterable, FiniteTLAValueDomain {
        case one = "rm1"
        case two = "rm2"
        case three = "rm3"

        package static var defaultValue: Self { .one }
        package static let finiteValues = allCases

        package var tlaValue: TLAValue { .string(rawValue) }
    }

    package enum TransactionManager: String, CaseIterable, FiniteTLAValueDomain {
        case primary = "tm"

        package static var defaultValue: Self { .primary }
        package static let finiteValues = allCases

        package var tlaValue: TLAValue { .string(rawValue) }
    }

    package enum BackupTransactionManager: String, CaseIterable, FiniteTLAValueDomain {
        case backup = "btm"

        package static var defaultValue: Self { .backup }
        package static let finiteValues = allCases

        package var tlaValue: TLAValue { .string(rawValue) }
    }

    package enum ResourceManagerState: String, TLAValueType {
        case working
        case prepared
        case committed
        case aborted
        case failed

        package static var defaultValue: Self { .working }
    }

    package enum TransactionManagerState: String, TLAValueType {
        case initial = "init"
        case commit
        case abort
        case hidden

        package static var defaultValue: Self { .initial }
    }

    private enum Step: String, CaseIterable {
        case resourceManager = "RS"
        case transactionStart = "TS"
        case transactionCommit = "TC"
        case transactionHideCommit = "F1"
        case transactionAbort = "TA"
        case transactionHideAbort = "F2"
        case backupStart = "BTS"
        case backupCommit = "BTC"
        case backupAbort = "BTA"
    }

    package static var spec: TLASpec {
        #spec("TwoPhaseWithBackupManager") {
            Extends(.integers)
            Algorithm("TransactionCommit", scoped: { scope in
                let resourceManagerState = scope.sharedVar("resourceManagerState", initial: Function<ResourceManager, ResourceManagerState>.literal(
                    (.one, .working),
                    (.two, .working),
                    (.three, .working)
                ))
                let transactionManagerState = scope.sharedVar("transactionManagerState", initial: TransactionManagerState.initial)

                let prepare = Macro { (manager: MacroParameter<ResourceManager>) in
                    Await(resourceManagerState[manager] == .working)
                    Assign(resourceManagerState, to: resourceManagerState.updating(manager, to: .prepared))
                }
                let decide = Macro { (manager: MacroParameter<ResourceManager>) in
                    Either {
                        Await(transactionManagerState == .commit)
                        Assign(resourceManagerState, to: resourceManagerState.updating(manager, to: .committed))
                    } or: {
                        Await(
                            resourceManagerState[manager] == .working
                                || transactionManagerState == .abort
                        )
                        Assign(resourceManagerState, to: resourceManagerState.updating(manager, to: .aborted))
                    }
                }
                let fail = Macro { (manager: MacroParameter<ResourceManager>) in
                    If(All(ResourceManager.all) { resourceManager in
                        resourceManagerState[resourceManager] != .failed
                    }) {
                        Assign(resourceManagerState, to: resourceManagerState.updating(manager, to: .failed))
                    }
                }

                Each(ResourceManager.all, fairness: .weak) { manager in
                    While(
                        Step.resourceManager,
                        resourceManagerState[manager] == .working
                            || resourceManagerState[manager] == .prepared
                    ) {
                        Either {
                            prepare(manager)
                        } or: {
                            Either {
                                decide(manager)
                            } or: {
                                fail(manager)
                            }
                        }
                    }
                }

                Each(TransactionManager.all, fairness: .weak) { _ in
                    Do(Step.transactionStart) {
                        Either {
                            When(
                                All(ResourceManager.all) { manager in
                                    resourceManagerState[manager] == .prepared
                                }
                                    || !All(ResourceManager.all) { manager in
                                        resourceManagerState[manager] != .committed
                                    }
                            )
                            Goto(Step.transactionCommit)
                        } or: {
                            When(
                                !All(ResourceManager.all) { manager in
                                    resourceManagerState[manager] != .aborted
                                        && resourceManagerState[manager] != .failed
                                }
                                    && All(ResourceManager.all) { manager in
                                        resourceManagerState[manager] != .committed
                                    }
                            )
                            Goto(Step.transactionAbort)
                        }
                    }
                    Do(Step.transactionCommit) {
                        Assign(transactionManagerState, to: TransactionManagerState.commit)
                    }
                    Do(Step.transactionHideCommit) {
                        Assign(transactionManagerState, to: TransactionManagerState.hidden)
                        Stop()
                    }
                    Do(Step.transactionAbort) {
                        Assign(transactionManagerState, to: TransactionManagerState.abort)
                    }
                    Do(Step.transactionHideAbort) {
                        Assign(transactionManagerState, to: TransactionManagerState.hidden)
                        Stop()
                    }
                }

                Each(BackupTransactionManager.all, fairness: .weak) { _ in
                    Do(Step.backupStart) {
                        Either {
                            When(
                                (
                                    All(ResourceManager.all) { manager in
                                        resourceManagerState[manager] == .prepared
                                    }
                                        || !All(ResourceManager.all) { manager in
                                            resourceManagerState[manager] != .committed
                                        }
                                )
                                    && transactionManagerState == .hidden
                            )
                            Goto(Step.backupCommit)
                        } or: {
                            When(
                                !All(ResourceManager.all) { manager in
                                    resourceManagerState[manager] != .aborted
                                        && resourceManagerState[manager] != .failed
                                }
                                    && All(ResourceManager.all) { manager in
                                        resourceManagerState[manager] != .committed
                                    }
                                    && transactionManagerState == .hidden
                            )
                            Goto(Step.backupAbort)
                        }
                    }
                    Do(Step.backupCommit) {
                        Assign(transactionManagerState, to: TransactionManagerState.commit)
                        Stop()
                    }
                    Do(Step.backupAbort) {
                        Assign(transactionManagerState, to: TransactionManagerState.abort)
                        Stop()
                    }
                }

                Invariant("TypeOK") {
                    All(ResourceManager.all) { manager in
                        resourceManagerState[manager] == .working
                            || resourceManagerState[manager] == .prepared
                            || resourceManagerState[manager] == .committed
                            || resourceManagerState[manager] == .aborted
                            || resourceManagerState[manager] == .failed
                    }
                        && (
                            transactionManagerState == .initial
                                || transactionManagerState == .commit
                                || transactionManagerState == .abort
                                || transactionManagerState == .hidden
                        )
                }
                Invariant("Consistency") {
                    All(ResourceManager.all) { first in
                        All(ResourceManager.all) { second in
                            !(resourceManagerState[first] == .aborted
                                && resourceManagerState[second] == .committed)
                        }
                    }
                }
            })
        }
    }
}

extension Example {
    package static let twoPhaseWithBackupManager = Entry(
        id: "transaction_commit/2PCwithBTM",
        upstreamSpec: "transaction_commit",
        upstreamModule: "specifications/transaction_commit/2PCwithBTM.tla",
        upstreamCfg: "specifications/transaction_commit/2PCwithBTM.cfg",
        expectedDistinct: 1_245,
        maximumStateLimit: 200_000,
        spec: TwoPhaseWithBackupManagerModel.spec,
        notes: "Published PlusCal two-phase commit with a backup transaction manager. TLC = 1,245."
    )
}
