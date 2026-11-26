// Resource managers can prepare, commit, or abort a transaction under a shared decision rule.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/transaction_commit/TCommit.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct TransactionCommitModel: Sendable {
    package enum Manager: String, CaseIterable, FiniteTLAValueDomain {
        case r1, r2, r3
        case ap1 = "r1_OF_RM", ap2 = "r2_OF_RM", ap3 = "r3_OF_RM"
        package static var defaultValue: Self { .r1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue {
            switch self {
            case .r1, .r2, .r3: .constant(rawValue)
            case .ap1, .ap2, .ap3: .string(rawValue)
            }
        }
    }

    package enum Phase: String, CaseIterable, TLAValueType {
        case working, prepared, committed, aborted
        package static var defaultValue: Self { .working }
    }

    private enum Step: String, CaseIterable {
        case prepare = "Prepare"
        case commitOrAbort = "Decide"
    }

    package static var spec: TLASpec {
        #spec("TCommit") { scope in
            let RM = scope.parameter(as: Set<Manager>.self, in: Set<Set<Manager>>([
                Set<Manager>([]), Set([.r1]), Set([.r2]), Set([.r3]),
                Set([.r1, .r2]), Set([.r1, .r3]), Set([.r2, .r3]),
                Set([.r1, .r2, .r3]), Set([.ap1, .ap2, .ap3])
            ]))
            let rmState = scope.sharedVar(initial: Dictionary<Manager, Phase>.mapping(over: RM) { _ in Phase.working })
            let canCommit = RM.allSatisfy { manager in
                rmState[manager] == Phase.prepared || rmState[manager] == Phase.committed
            }
            let noManagerHasCommitted = !RM.contains { manager in rmState[manager] == Phase.committed }

            Do(Step.prepare, over: RM) { manager in
                When(rmState[manager] == Phase.working)
                rmState[manager].set(Phase.prepared)
            }
            Do(Step.commitOrAbort, over: RM) { manager in
                Either {
                    When(rmState[manager] == Phase.prepared && canCommit) {
                        rmState[manager].set(Phase.committed)
                    }
                    When((rmState[manager] == Phase.working || rmState[manager] == Phase.prepared) && noManagerHasCommitted) {
                        rmState[manager].set(Phase.aborted)
                    }
                }
            }

            Invariant("TCTypeOK") {
                Functions(from: RM, to: SetExpr<Phase>.literal(.working, .prepared, .committed, .aborted)).contains(rmState)
            }
            Invariant("TCConsistent") {
                noManagerHasCommitted || !RM.contains { manager in rmState[manager] == Phase.aborted }
            }
            Validation("threeManagers") {
                Bind(RM, to: Set<Manager>([.r1, .r2, .r3]))
            }.checkingDeadlock(false)
            Validation("APTCommit") {
                Bind(RM, to: Set<Manager>([.ap1, .ap2, .ap3]))
            }.checkingDeadlock(false)
        }
    }
}
