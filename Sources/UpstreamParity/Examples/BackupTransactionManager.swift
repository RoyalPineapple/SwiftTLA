// A backup transaction manager can take over the decision in a two-phase commit protocol.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/transaction_commit/2PCwithBTM.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct BackupTransactionManagerModel: Sendable {
    package enum Manager: String, CaseIterable, FiniteTLAValueDomain {
        case rm1, rm2, rm3
        package static var defaultValue: Self { .rm1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package enum Phase: String, CaseIterable {
        case working, prepared, committed, aborted, failed
    }
    package enum Decision: String, CaseIterable {
        case undecided = "init"
        case commit, abort, hidden
    }
    private enum Step: String, CaseIterable {
        case prepareDecideOrFail = "RS"
        case choosePrimaryDecision = "TS"
        case recordPrimaryCommit = "TC"
        case recordPrimaryAbort = "TA"
        case finishAfterCommit = "F1"
        case finishAfterAbort = "F2"
        case recoverHiddenDecision = "BTS"
        case recordBackupCommit = "BTC"
        case recordBackupAbort = "BTA"
    }

    package static var spec: TLASpec {
        #spec("BackupTransactionManager") { scope in
            let resourceManagers = scope.parameter(tlaName: "RM", as: Set<Manager>.self, in: Subsets(of: Manager.all.assuming(Set<Manager>.self)))
            let resourceManagersMayFail = scope.parameter(tlaName: "RMMAYFAIL", as: Bool.self)
            let transactionManagerMayFail = scope.parameter(tlaName: "TMMAYFAIL", as: Bool.self)
            let typeOK = Invariant("TypeOK")
            let consistency = Invariant("Consistency")
            let Termination = Temporal()
            Algorithm("protocolSteps") { scope in
                let resourceManagerStates = scope.sharedVar(tlaName: "rmState", initial: Dictionary<Manager, Phase>.mapping(over: resourceManagers) { _ in Phase.working })
                let coordinatorDecision = scope.sharedVar(tlaName: "tmState", initial: Decision.undecided)
                let anyCommitted = resourceManagers.contains { manager in resourceManagerStates[manager] == Phase.committed }
                let canCommit = resourceManagers.allSatisfy { manager in resourceManagerStates[manager] == Phase.prepared } || anyCommitted
                let canAbort = resourceManagers.contains { manager in
                    resourceManagerStates[manager] == Phase.aborted || resourceManagerStates[manager] == Phase.failed
                } && !anyCommitted

                Each(resourceManagers, fairness: .weak) { manager in
                    While(Step.prepareDecideOrFail, resourceManagerStates[manager] == Phase.working || resourceManagerStates[manager] == Phase.prepared) {
                        Either {
                            When(resourceManagerStates[manager] == Phase.working) { resourceManagerStates[manager].set(Phase.prepared) }
                            When(coordinatorDecision == Decision.commit) { resourceManagerStates[manager].set(Phase.committed) }
                            When(resourceManagerStates[manager] == Phase.working || coordinatorDecision == Decision.abort) {
                                resourceManagerStates[manager].set(Phase.aborted)
                            }
                            When(true) {
                                If(resourceManagersMayFail && !resourceManagers.contains { other in resourceManagerStates[other] == Phase.failed }) {
                                    resourceManagerStates[manager].set(Phase.failed)
                                }
                            }
                        }
                    }
                }

                Process(id: 0, fairness: .weak) {
                    Do(Step.choosePrimaryDecision) {
                        Either {
                            When(canCommit) { Goto(Step.recordPrimaryCommit) }
                            When(canAbort) { Goto(Step.recordPrimaryAbort) }
                        }
                    }
                    Do(Step.recordPrimaryCommit) { coordinatorDecision.set(Decision.commit) }
                    Do(Step.finishAfterCommit) {
                        If(transactionManagerMayFail) { coordinatorDecision.set(Decision.hidden) }
                        Stop()
                    }
                    Do(Step.recordPrimaryAbort) { coordinatorDecision.set(Decision.abort) }
                    Do(Step.finishAfterAbort) {
                        If(transactionManagerMayFail) { coordinatorDecision.set(Decision.hidden) }
                    }
                }

                Process(id: 10, fairness: .weak) {
                    Do(Step.recoverHiddenDecision) {
                        When(coordinatorDecision == Decision.hidden)
                        Either {
                            When(canCommit) { Goto(Step.recordBackupCommit) }
                            When(canAbort) { Goto(Step.recordBackupAbort) }
                        }
                    }
                    Do(Step.recordBackupCommit) {
                        coordinatorDecision.set(Decision.commit)
                        Stop()
                    }
                    Do(Step.recordBackupAbort) { coordinatorDecision.set(Decision.abort) }
                }

                typeOK {
                    Functions(from: resourceManagers, to: SetExpr<Phase>.literal(.working, .prepared, .committed, .aborted, .failed)).contains(resourceManagerStates)
                    SetExpr<Decision>.literal(.undecided, .commit, .abort, .hidden).contains(coordinatorDecision)
                }
                consistency { !anyCommitted || !resourceManagers.contains { manager in resourceManagerStates[manager] == Phase.aborted } }
                Termination(.eventually(resourceManagers.allSatisfy { manager in Finished(manager) } && Finished(0) && Finished(10)))
            }
            Validation("threeManagers") {
                Bind(resourceManagers, to: Set<Manager>([.rm1, .rm2, .rm3]))
                Bind(resourceManagersMayFail, to: true)
                Bind(transactionManagerMayFail, to: true)
            }.checking(only: [typeOK, consistency])
        }
    }
}
