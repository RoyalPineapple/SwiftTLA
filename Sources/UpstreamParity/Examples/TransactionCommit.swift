import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct TransactionCommitModel: Sendable {
    package enum Manager: String, CaseIterable, FiniteTLAValueDomain {
        case r1, r2, r3
        package static var defaultValue: Self { .r1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum Phase: String, CaseIterable, TLAValueType {
        case working, prepared, committed, aborted
        package static var defaultValue: Self { .working }
    }

    private enum Step: String, CaseIterable {
        case prepare = "Prepare"
        case decide = "Decide"
    }

    package static var spec: TLASpec {
        #spec("TCommit") { scope in
            let RM = scope.parameter(as: Set<Manager>.self, in: Subsets(of: Manager.all.assuming(Set<Manager>.self)))
            let rmState = scope.sharedVar(initial: Dictionary<Manager, Phase>.mapping(over: RM) { _ in Phase.working })
            let canCommit = RM.allSatisfy { manager in
                rmState[manager] == Phase.prepared || rmState[manager] == Phase.committed
            }
            let noneCommitted = !RM.contains { manager in rmState[manager] == Phase.committed }

            Do(Step.prepare, over: RM) { manager in
                When(rmState[manager] == Phase.working)
                rmState[manager].set(Phase.prepared)
            }
            Do(Step.decide, over: RM) { manager in
                Either {
                    When(rmState[manager] == Phase.prepared && canCommit) {
                        rmState[manager].set(Phase.committed)
                    }
                    When((rmState[manager] == Phase.working || rmState[manager] == Phase.prepared) && noneCommitted) {
                        rmState[manager].set(Phase.aborted)
                    }
                }
            }

            Invariant("TCTypeOK") {
                Functions(from: RM, to: SetExpr<Phase>.literal(.working, .prepared, .committed, .aborted)).contains(rmState)
            }
            Invariant("TCConsistent") {
                noneCommitted || !RM.contains { manager in rmState[manager] == Phase.aborted }
            }
            let threeManagers = Validation {
                Bind(RM, to: Set<Manager>([.r1, .r2, .r3]))
            }.checkingDeadlock(false)
            threeManagers
        }
    }
}
