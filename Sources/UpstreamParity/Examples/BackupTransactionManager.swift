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
            let RM = scope.parameter(as: Set<Manager>.self, in: Subsets(of: Manager.all.assuming(Set<Manager>.self)))
            let RMMAYFAIL = scope.parameter(as: Bool.self)
            let TMMAYFAIL = scope.parameter(as: Bool.self)
            let typeOK = Invariant("TypeOK")
            let consistency = Invariant("Consistency")
            let Termination = Temporal()
            Algorithm("protocolSteps") { scope in
                let rmState = scope.sharedVar(initial: Dictionary<Manager, Phase>.mapping(over: RM) { _ in Phase.working })
                let tmState = scope.sharedVar(initial: Decision.undecided)
                let anyCommitted = RM.contains { manager in rmState[manager] == Phase.committed }
                let canCommit = RM.allSatisfy { manager in rmState[manager] == Phase.prepared } || anyCommitted
                let canAbort = RM.contains { manager in
                    rmState[manager] == Phase.aborted || rmState[manager] == Phase.failed
                } && !anyCommitted

                Each(RM, fairness: .weak) { manager in
                    While(Step.prepareDecideOrFail, rmState[manager] == Phase.working || rmState[manager] == Phase.prepared) {
                        Either {
                            When(rmState[manager] == Phase.working) { rmState[manager].set(Phase.prepared) }
                            When(tmState == Decision.commit) { rmState[manager].set(Phase.committed) }
                            When(rmState[manager] == Phase.working || tmState == Decision.abort) {
                                rmState[manager].set(Phase.aborted)
                            }
                            When(true) {
                                If(RMMAYFAIL && !RM.contains { other in rmState[other] == Phase.failed }) {
                                    rmState[manager].set(Phase.failed)
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
                    Do(Step.recordPrimaryCommit) { tmState.set(Decision.commit) }
                    Do(Step.finishAfterCommit) {
                        If(TMMAYFAIL) { tmState.set(Decision.hidden) }
                        Stop()
                    }
                    Do(Step.recordPrimaryAbort) { tmState.set(Decision.abort) }
                    Do(Step.finishAfterAbort) {
                        If(TMMAYFAIL) { tmState.set(Decision.hidden) }
                    }
                }

                Process(id: 10, fairness: .weak) {
                    Do(Step.recoverHiddenDecision) {
                        When(tmState == Decision.hidden)
                        Either {
                            When(canCommit) { Goto(Step.recordBackupCommit) }
                            When(canAbort) { Goto(Step.recordBackupAbort) }
                        }
                    }
                    Do(Step.recordBackupCommit) {
                        tmState.set(Decision.commit)
                        Stop()
                    }
                    Do(Step.recordBackupAbort) { tmState.set(Decision.abort) }
                }

                typeOK {
                    Functions(from: RM, to: SetExpr<Phase>.literal(.working, .prepared, .committed, .aborted, .failed)).contains(rmState)
                    SetExpr<Decision>.literal(.undecided, .commit, .abort, .hidden).contains(tmState)
                }
                consistency { !anyCommitted || !RM.contains { manager in rmState[manager] == Phase.aborted } }
                Termination(.eventually(RM.allSatisfy { manager in Finished(manager) } && Finished(0) && Finished(10)))
            }
            Validation("threeManagers") {
                Bind(RM, to: Set<Manager>([.rm1, .rm2, .rm3]))
                Bind(RMMAYFAIL, to: true)
                Bind(TMMAYFAIL, to: true)
            }.checking(only: [typeOK, consistency])
        }
    }
}
