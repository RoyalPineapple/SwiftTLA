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
            let resourceManagers = scope.parameter(tlaName: "RM", as: Set<Manager>.self, in: Set<Set<Manager>>([
                Set<Manager>([]), Set([.r1]), Set([.r2]), Set([.r3]),
                Set([.r1, .r2]), Set([.r1, .r3]), Set([.r2, .r3]),
                Set([.r1, .r2, .r3]), Set([.ap1, .ap2, .ap3])
            ]))
            let resourceManagerStates = scope.sharedVar(tlaName: "rmState", initial: Dictionary<Manager, Phase>.mapping(over: resourceManagers) { _ in Phase.working })
            let canCommit = resourceManagers.allSatisfy { manager in
                resourceManagerStates[manager] == Phase.prepared || resourceManagerStates[manager] == Phase.committed
            }
            let noManagerHasCommitted = !resourceManagers.contains { manager in resourceManagerStates[manager] == Phase.committed }

            Do(Step.prepare, over: resourceManagers) { manager in
                When(resourceManagerStates[manager] == Phase.working)
                resourceManagerStates[manager].set(Phase.prepared)
            }
            Do(Step.commitOrAbort, over: resourceManagers) { manager in
                Either {
                    When(resourceManagerStates[manager] == Phase.prepared && canCommit) {
                        resourceManagerStates[manager].set(Phase.committed)
                    }
                    When((resourceManagerStates[manager] == Phase.working || resourceManagerStates[manager] == Phase.prepared) && noManagerHasCommitted) {
                        resourceManagerStates[manager].set(Phase.aborted)
                    }
                }
            }

            Invariant("TCTypeOK") {
                Functions(from: resourceManagers, to: SetExpr<Phase>.literal(.working, .prepared, .committed, .aborted)).contains(resourceManagerStates)
            }
            Invariant("TCConsistent") {
                noManagerHasCommitted || !resourceManagers.contains { manager in resourceManagerStates[manager] == Phase.aborted }
            }
            Validation("threeManagers") {
                Bind(resourceManagers, to: Set<Manager>([.r1, .r2, .r3]))
            }.checkingDeadlock(false)
            Validation("APTCommit") {
                Bind(resourceManagers, to: Set<Manager>([.ap1, .ap2, .ap3]))
            }.checkingDeadlock(false)
        }
    }
}
