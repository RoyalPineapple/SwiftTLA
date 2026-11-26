// A transaction manager collects prepared messages and tells the participants to commit or
// abort.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/transaction_commit/TwoPhase.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct TwoPhaseCommitModel: Sendable {
    package enum Manager: String, CaseIterable, FiniteTLAValueDomain {
        case r1, r2, r3
        package static var defaultValue: Self { .r1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum Phase: String, CaseIterable {
        case working, prepared, committed, aborted
    }

    package enum Coordinator: String, CaseIterable {
        case undecided = "init"
        case committed, aborted
    }

    package struct Prepared: Hashable, Sendable {
        package let type: String
        package let rm: Manager
    }

    package struct Broadcast: Hashable, Sendable {
        package let type: String
    }

    package typealias Message = OneOf<Prepared, Broadcast>

    private enum Step: String, CaseIterable {
        case recordPreparedManager = "TMRcvPrepared"
        case broadcastCommit = "TMCommit"
        case broadcastAbort = "TMAbort"
        case prepareAndNotifyCoordinator = "RMPrepare"
        case abortLocally = "RMChooseToAbort"
        case applyCommitMessage = "RMRcvCommitMsg"
        case applyAbortMessage = "RMRcvAbortMsg"
    }

    package static var spec: TLASpec {
        #spec("TwoPhase") { scope in
            let resourceManagers = scope.parameter(tlaName: "RM", as: Set<Manager>.self, in: Subsets(of: Manager.all.assuming(Set<Manager>.self)))
            let resourceManagerStates = scope.sharedVar(tlaName: "rmState", initial: Dictionary<Manager, Phase>.mapping(over: resourceManagers) { _ in Phase.working })
            let coordinatorState = scope.sharedVar(tlaName: "tmState", initial: Coordinator.undecided)
            let preparedManagers = scope.sharedVar(tlaName: "tmPrepared", initial: Set<Manager>())
            let messages = scope.sharedVar(tlaName: "msgs", initial: Set<Message>())

            let commitMessage: Message = Message.second(Broadcast(type: "Commit"))
            let abortMessage: Message = Message.second(Broadcast(type: "Abort"))

            Do(Step.recordPreparedManager, over: resourceManagers) { manager in
                When(coordinatorState == Coordinator.undecided)
                When(messages.contains(Message.first(Prepared.expression(type: "Prepared", rm: manager))))
                preparedManagers.insert(manager)
            }
            Do(Step.broadcastCommit, when: coordinatorState == Coordinator.undecided && preparedManagers == resourceManagers) {
                coordinatorState.set(Coordinator.committed)
                messages.insert(commitMessage)
            }
            Do(Step.broadcastAbort, when: coordinatorState == Coordinator.undecided) {
                coordinatorState.set(Coordinator.aborted)
                messages.insert(abortMessage)
            }
            Do(Step.prepareAndNotifyCoordinator, over: resourceManagers) { manager in
                When(resourceManagerStates[manager] == Phase.working)
                resourceManagerStates[manager].set(Phase.prepared)
                messages.insert(Message.first(Prepared.expression(type: "Prepared", rm: manager)))
            }
            Do(Step.abortLocally, over: resourceManagers) { manager in
                When(resourceManagerStates[manager] == Phase.working)
                resourceManagerStates[manager].set(Phase.aborted)
            }
            Do(Step.applyCommitMessage, over: resourceManagers) { manager in
                When(messages.contains(commitMessage))
                resourceManagerStates[manager].set(Phase.committed)
            }
            Do(Step.applyAbortMessage, over: resourceManagers) { manager in
                When(messages.contains(abortMessage))
                resourceManagerStates[manager].set(Phase.aborted)
            }

            Invariant("TPTypeOK") {
                Functions(from: resourceManagers, to: SetExpr<Phase>.literal(.working, .prepared, .committed, .aborted)).contains(resourceManagerStates)
                SetExpr<Coordinator>.literal(.undecided, .committed, .aborted).contains(coordinatorState)
                preparedManagers.isSubset(of: resourceManagers)
                messages.allSatisfy { message in
                    message == commitMessage || message == abortMessage || resourceManagers.contains { manager in
                        message == Message.first(Prepared.expression(type: "Prepared", rm: manager))
                    }
                }
            }
            Validation("threeManagers") {
                Bind(resourceManagers, to: Set<Manager>([.r1, .r2, .r3]))
            }
        }
    }
}
