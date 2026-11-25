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
        case participate = "RS"
        case primary = "TS", commit = "TC", abort = "TA"
        case afterCommit = "F1", afterAbort = "F2"
        case backup = "BTS", backupCommit = "BTC", backupAbort = "BTA"
    }

    package static var spec: TLASpec {
        #spec("BackupTransactionManager") { scope in
            let RM = scope.parameter(as: Set<Manager>.self, in: Subsets(of: Manager.all.assuming(Set<Manager>.self)))
            let RMMAYFAIL = scope.parameter(as: Bool.self)
            let TMMAYFAIL = scope.parameter(as: Bool.self)
            let TypeOK = Invariant()
            let Consistency = Invariant()
            let Termination = Temporal()
            let protocolSteps = Algorithm { scope in
                let rmState = scope.sharedVar(initial: Dictionary<Manager, Phase>.mapping(over: RM) { _ in Phase.working })
                let tmState = scope.sharedVar(initial: Decision.undecided)
                let anyCommitted = RM.contains { manager in rmState[manager] == Phase.committed }
                let canCommit = RM.allSatisfy { manager in rmState[manager] == Phase.prepared } || anyCommitted
                let canAbort = RM.contains { manager in
                    rmState[manager] == Phase.aborted || rmState[manager] == Phase.failed
                } && !anyCommitted

                Each(RM, fairness: .weak) { manager in
                    While(Step.participate, rmState[manager] == Phase.working || rmState[manager] == Phase.prepared) {
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
                    Do(Step.primary) {
                        Either {
                            When(canCommit) { Goto(Step.commit) }
                            When(canAbort) { Goto(Step.abort) }
                        }
                    }
                    Do(Step.commit) { tmState.set(Decision.commit) }
                    Do(Step.afterCommit) {
                        If(TMMAYFAIL) { tmState.set(Decision.hidden) }
                        Stop()
                    }
                    Do(Step.abort) { tmState.set(Decision.abort) }
                    Do(Step.afterAbort) { If(TMMAYFAIL) { tmState.set(Decision.hidden) } }
                }

                Process(id: 10, fairness: .weak) {
                    Do(Step.backup) {
                        When(tmState == Decision.hidden)
                        Either {
                            When(canCommit) { Goto(Step.backupCommit) }
                            When(canAbort) { Goto(Step.backupAbort) }
                        }
                    }
                    Do(Step.backupCommit) { tmState.set(Decision.commit); Stop() }
                    Do(Step.backupAbort) { tmState.set(Decision.abort) }
                }

                TypeOK {
                    Functions(from: RM, to: SetExpr<Phase>.literal(.working, .prepared, .committed, .aborted, .failed)).contains(rmState)
                    SetExpr<Decision>.literal(.undecided, .commit, .abort, .hidden).contains(tmState)
                }
                Consistency { !anyCommitted || !RM.contains { manager in rmState[manager] == Phase.aborted } }
                Termination(.eventually(RM.allSatisfy { manager in Finished(manager) } && Finished(0) && Finished(10)))
            }
            protocolSteps
            Validation("threeManagers") {
                Bind(RM, to: Set<Manager>([.rm1, .rm2, .rm3]))
                Bind(RMMAYFAIL, to: true)
                Bind(TMMAYFAIL, to: true)
            }.checking(only: [TypeOK, Consistency])
        }
    }
}
