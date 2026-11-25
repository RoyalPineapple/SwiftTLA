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
        case receivePrepared = "TMRcvPrepared"
        case commit = "TMCommit"
        case abort = "TMAbort"
        case prepare = "RMPrepare"
        case chooseToAbort = "RMChooseToAbort"
        case receiveCommit = "RMRcvCommitMsg"
        case receiveAbort = "RMRcvAbortMsg"
    }

    package static var spec: TLASpec {
        #spec("TwoPhase") { scope in
            let RM = scope.parameter(as: Set<Manager>.self, in: Subsets(of: Manager.all.assuming(Set<Manager>.self)))
            let rmState = scope.sharedVar(initial: Dictionary<Manager, Phase>.mapping(over: RM) { _ in Phase.working })
            let tmState = scope.sharedVar(initial: Coordinator.undecided)
            let tmPrepared = scope.sharedVar(initial: Set<Manager>())
            let msgs = scope.sharedVar(initial: Set<Message>())

            let commit: Message = Message.second(Broadcast(type: "Commit"))
            let abort: Message = Message.second(Broadcast(type: "Abort"))

            Do(Step.receivePrepared, over: RM) { manager in
                When(tmState == Coordinator.undecided)
                When(msgs.contains(Message.first(Prepared.expression(type: "Prepared", rm: manager))))
                tmPrepared.insert(manager)
            }
            Do(Step.commit, when: tmState == Coordinator.undecided && tmPrepared == RM) {
                tmState.set(Coordinator.committed)
                msgs.insert(commit)
            }
            Do(Step.abort, when: tmState == Coordinator.undecided) {
                tmState.set(Coordinator.aborted)
                msgs.insert(abort)
            }
            Do(Step.prepare, over: RM) { manager in
                When(rmState[manager] == Phase.working)
                rmState[manager].set(Phase.prepared)
                msgs.insert(Message.first(Prepared.expression(type: "Prepared", rm: manager)))
            }
            Do(Step.chooseToAbort, over: RM) { manager in
                When(rmState[manager] == Phase.working)
                rmState[manager].set(Phase.aborted)
            }
            Do(Step.receiveCommit, over: RM) { manager in
                When(msgs.contains(commit))
                rmState[manager].set(Phase.committed)
            }
            Do(Step.receiveAbort, over: RM) { manager in
                When(msgs.contains(abort))
                rmState[manager].set(Phase.aborted)
            }

            Invariant("TPTypeOK") {
                Functions(from: RM, to: SetExpr<Phase>.literal(.working, .prepared, .committed, .aborted)).contains(rmState)
                SetExpr<Coordinator>.literal(.undecided, .committed, .aborted).contains(tmState)
                tmPrepared.isSubset(of: RM)
                msgs.allSatisfy { message in
                    message == commit || message == abort || RM.contains { manager in
                        message == Message.first(Prepared.expression(type: "Prepared", rm: manager))
                    }
                }
            }
            Validation("threeManagers") {
                Bind(RM, to: Set<Manager>([.r1, .r2, .r3]))
            }
        }
    }
}
