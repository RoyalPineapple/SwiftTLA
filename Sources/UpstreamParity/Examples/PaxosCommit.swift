// Each resource manager runs one Paxos instance. All must prepare to commit; one abort suffices.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/transaction_commit/PaxosCommit.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct PaxosCommitModel: Sendable {
    package enum Manager: String, CaseIterable, FiniteTLAValueDomain {
        case r1, r2
        package static let defaultValue = Self.r1
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package enum Acceptor: String, CaseIterable, FiniteTLAValueDomain {
        case a1, a2, a3
        package static let defaultValue = Self.a1
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package struct AcceptedState: Hashable, Sendable {
        package let mbal: Int
        package let bal: Int
        package let val: String
    }
    package struct Prepare: Hashable, Sendable {
        package let type: String
        package let ins: Manager
        package let bal: Int
    }
    package struct Promise: Hashable, Sendable {
        package let type: String
        package let ins: Manager
        package let mbal: Int
        package let bal: Int
        package let val: String
        package let acc: Acceptor
    }
    package struct Proposal: Hashable, Sendable {
        package let type: String
        package let ins: Manager
        package let bal: Int
        package let val: String
    }
    package struct Vote: Hashable, Sendable {
        package let type: String
        package let acc: Acceptor
        package let ins: Manager
        package let bal: Int
        package let val: String
    }
    package struct Decision: Hashable, Sendable {
        package let type: String
    }
    package typealias PhaseOne = OneOf<Prepare, Promise>
    package typealias PhaseTwo = OneOf<Proposal, Vote>
    package typealias PhaseMessage = OneOf<PhaseOne, PhaseTwo>
    package typealias Message = OneOf<PhaseMessage, Decision>

    private enum Step: String, CaseIterable {
        case prepare = "RMPrepare", abort = "RMChooseToAbort"
        case receiveCommit = "RMRcvCommitMsg", receiveAbort = "RMRcvAbortMsg"
        case requestPromise = "Phase1a", promise = "Phase1b"
        case propose = "Phase2a", vote = "Phase2b", decide = "Decide"
    }

    package static var spec: TLASpec {
        #spec("PaxosCommit") { scope in
            Extends(.integers, .finiteSets)
            let managers = Set<Manager>([Manager.r1, Manager.r2])
            let acceptors = Set<Acceptor>([Acceptor.a1, Acceptor.a2, Acceptor.a3])
            let quorums = scope.parameter(as: Set<Set<Acceptor>>.self, in: Set<Set<Set<Acceptor>>>([
                Set<Set<Acceptor>>([[Acceptor.a1, Acceptor.a2], [Acceptor.a1, Acceptor.a3], [Acceptor.a2, Acceptor.a3]])
            ]))
            Assume(quorums.allSatisfy { q in q.isSubset(of: acceptors) })
            Assume(quorums.allSatisfy { q in quorums.allSatisfy { other in !q.intersection(other).isEmpty } })
            let ballots = IntRange(0, through: 1)
            let laterBallots = IntRange(1, through: 1)
            let outcomes = Set<String>(["prepared", "aborted"])
            let initial = AcceptedState.expression(mbal: 0, bal: -1, val: "none")
            let rmState = scope.sharedVar(initial: Dictionary<Manager, String>.mapping(over: managers) { _ in "working" })
            let aState = scope.sharedVar(initial: Dictionary<Manager, [Acceptor: AcceptedState]>.mapping(over: managers) { _ in
                Dictionary<Acceptor, AcceptedState>.mapping(over: acceptors) { _ in initial }
            })
            let msgs = scope.sharedVar(initial: Set<Message>())
            let prepares = msgs.filter { m in m.recordFields == Set<String>(["type", "ins", "bal"]) }.mapping { m in m.assuming(Prepare.self) }
            let promises = msgs.filter { m in m.recordFields == Set<String>(["type", "ins", "mbal", "bal", "val", "acc"]) }.mapping { m in m.assuming(Promise.self) }
            let proposals = msgs.filter { m in m.recordFields == Set<String>(["type", "ins", "bal", "val"]) }.mapping { m in m.assuming(Proposal.self) }
            let votes = msgs.filter { m in m.recordFields == Set<String>(["type", "ins", "bal", "val", "acc"]) }.mapping { m in m.assuming(Vote.self) }
            let decisions = msgs.filter { m in m.recordFields == Set<String>(["type"]) }.mapping { m in m.assuming(Decision.self) }

            Do(Step.prepare, over: managers) { manager in
                When(rmState[manager] == "working")
                rmState[manager].set("prepared")
                msgs.insert(Message.first(PhaseMessage.second(PhaseTwo.first(Proposal.expression(type: "phase2a", ins: manager, bal: 0, val: "prepared")))))
            }
            Do(Step.abort, over: managers) { manager in
                When(rmState[manager] == "working")
                rmState[manager].set("aborted")
                msgs.insert(Message.first(PhaseMessage.second(PhaseTwo.first(Proposal.expression(type: "phase2a", ins: manager, bal: 0, val: "aborted")))))
            }
            Do(Step.receiveCommit, over: managers) { manager in
                When(msgs.contains(Message.second(Decision.expression(type: "Commit"))))
                rmState[manager].set("committed")
            }
            Do(Step.receiveAbort, over: managers) { manager in
                When(msgs.contains(Message.second(Decision.expression(type: "Abort"))))
                rmState[manager].set("aborted")
            }
            Do(Step.requestPromise, over: laterBallots, managers) { ballot, manager in
                msgs.insert(Message.first(PhaseMessage.first(PhaseOne.first(Prepare.expression(type: "phase1a", ins: manager, bal: ballot)))))
            }
            Do(Step.promise, over: acceptors) { acceptor in
                With(managers, laterBallots) { manager, ballot in
                    When(msgs.contains(Message.first(PhaseMessage.first(PhaseOne.first(Prepare.expression(type: "phase1a", ins: manager, bal: ballot))))))
                    When(aState[manager][acceptor].mbal < ballot)
                    msgs.insert(Message.first(PhaseMessage.first(PhaseOne.second(Promise.expression(
                        type: "phase1b", ins: manager, mbal: ballot, bal: aState[manager][acceptor].bal,
                        val: aState[manager][acceptor].val, acc: acceptor)))))
                    aState[manager][acceptor].mbal.set(ballot)
                }
            }
            Do(Step.propose, over: laterBallots, managers) { ballot, manager in
                When(!proposals.contains { m in m.bal == ballot && m.ins == manager })
                With(quorums) { quorum in
                    let replies = promises.filter { m in m.ins == manager && m.mbal == ballot && quorum.contains(m.acc) }
                    When(quorum.allSatisfy { acceptor in replies.contains { m in m.acc == acceptor } })
                    let value = If(replies.allSatisfy { m in m.bal == -1 }, then: "aborted", else:
                        Select(from: replies) { m in replies.allSatisfy { other in other.bal <= m.bal } }.val)
                    msgs.insert(Message.first(PhaseMessage.second(PhaseTwo.first(Proposal.expression(type: "phase2a", ins: manager, bal: ballot, val: value)))))
                }
            }
            Do(Step.vote, over: acceptors) { acceptor in
                With(managers, ballots, outcomes) { manager, ballot, value in
                    When(msgs.contains(Message.first(PhaseMessage.second(PhaseTwo.first(Proposal.expression(type: "phase2a", ins: manager, bal: ballot, val: value))))))
                    When(aState[manager][acceptor].mbal <= ballot)
                    aState[manager][acceptor].set(AcceptedState.expression(mbal: ballot, bal: ballot, val: value))
                    msgs.insert(Message.first(PhaseMessage.second(PhaseTwo.second(Vote.expression(type: "phase2b", acc: acceptor, ins: manager, bal: ballot, val: value)))))
                }
            }
            let prepared = managers.filter { manager in ballots.contains { ballot in quorums.contains { quorum in
                quorum.allSatisfy { acceptor in msgs.contains(Message.first(PhaseMessage.second(PhaseTwo.second(
                    Vote.expression(type: "phase2b", acc: acceptor, ins: manager, bal: ballot, val: "prepared"))))) }
            } } }
            let aborted = managers.filter { manager in ballots.contains { ballot in quorums.contains { quorum in
                quorum.allSatisfy { acceptor in msgs.contains(Message.first(PhaseMessage.second(PhaseTwo.second(
                    Vote.expression(type: "phase2b", acc: acceptor, ins: manager, bal: ballot, val: "aborted"))))) }
            } } }
            Do(Step.decide) {
                Either {
                    When(managers.allSatisfy { manager in prepared.contains(manager) }) {
                        msgs.insert(Message.second(Decision.expression(type: "Commit")))
                    }
                    When(!aborted.isEmpty) { msgs.insert(Message.second(Decision.expression(type: "Abort"))) }
                }
            }
            let states = Set<String>(["working", "prepared", "committed", "aborted"])
            let previousBallots = IntRange(-1, through: 1)
            let previousValues = Set<String>(["prepared", "aborted", "none"])
            Invariant("PCTypeOK") {
                Functions(from: managers, to: states).contains(rmState)
                aState.keys == managers && managers.allSatisfy { manager in
                    aState[manager].keys == acceptors && acceptors.allSatisfy { acceptor in
                        let state = aState[manager][acceptor]
                        return ballots.contains(state.mbal) && previousBallots.contains(state.bal) && previousValues.contains(state.val)
                    }
                }
                prepares.count + promises.count + proposals.count + votes.count + decisions.count == msgs.count
                prepares.allSatisfy { m in m.type == "phase1a" && managers.contains(m.ins) && laterBallots.contains(m.bal) }
                promises.allSatisfy { m in m.type == "phase1b" && managers.contains(m.ins) && acceptors.contains(m.acc)
                    && ballots.contains(m.mbal) && previousBallots.contains(m.bal) && previousValues.contains(m.val) }
                proposals.allSatisfy { m in m.type == "phase2a" && managers.contains(m.ins) && ballots.contains(m.bal) && outcomes.contains(m.val) }
                votes.allSatisfy { m in m.type == "phase2b" && managers.contains(m.ins) && acceptors.contains(m.acc)
                    && ballots.contains(m.bal) && outcomes.contains(m.val) }
                decisions.allSatisfy { m in m.type == "Commit" || m.type == "Abort" }
            }
            Validation("published") {
                Bind(quorums, to: Set<Set<Acceptor>>([[Acceptor.a1, Acceptor.a2], [Acceptor.a1, Acceptor.a3], [Acceptor.a2, Acceptor.a3]]))
            }
        }
    }
}
