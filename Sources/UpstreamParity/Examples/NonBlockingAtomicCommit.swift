// This atomic commit protocol adds recovery steps so participants can decide despite failures.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/acp/ACP_NB.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct NonBlockingAtomicCommitModel: Sendable {
    package enum Member: String, CaseIterable, FiniteTLAValueDomain {
        case p0, p1
        package static var defaultValue: Self { .p0 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum Vote: String, CaseIterable, FiniteTLAValueDomain {
        case yes, no, waiting
        package static var defaultValue: Self { .waiting }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum Decision: String, CaseIterable, FiniteTLAValueDomain {
        case undecided, commit, abort, notsent
        package static var defaultValue: Self { .undecided }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package struct Participant: Hashable, Sendable {
        package let vote: Vote
        package let alive: Bool
        package let decision: Decision
        package let faulty: Bool
        package let forward: [Member: Decision]
        package let voteSent: Bool
    }

    package struct Coordinator: Hashable, Sendable {
        package let request: [Member: Bool]
        package let vote: [Member: Vote]
        package let broadcast: [Member: Decision]
        package let decision: Decision
        package let alive: Bool
        package let faulty: Bool
    }

    private enum Step: String, CaseIterable {
        case request, getVote, detectFault, makeDecision, coordBroadcast, coordDie
        case sendVote, abortOnVote, abortOnTimeoutRequest, parDie
        case forward, preDecideOnForward, preDecide, decideNB, abortOnTimeout
        case decide, decideOnForward
    }

    package static var spec: TLASpec {
        #spec("NonBlockingAtomicCommit") { scope in
            let participants = scope.parameter(as: Set<Member>.self, in: Subsets(of: Member.all.assuming(Set<Member>.self)))
            // The faulty upstream variant delivers a decision before forwarding it to every peer.
            let decideBeforeForwarding = scope.parameter(as: Bool.self)
            let unsent = Dictionary<Member, Decision>.mapping(over: participants) { _ in Decision.notsent }
            let initialParticipants = SetExpr<Vote>.literal(.yes, .no).mapping { vote in
                Participant.expression(vote: vote, alive: true, decision: Decision.undecided, faulty: false, forward: unsent, voteSent: false)
            }
            let participant: SharedVariable<[Member: Participant]> = scope.sharedVar(
                initiallyIn: Functions(from: participants, to: initialParticipants))
            let coordinator = scope.sharedVar(initial: Coordinator.expression(
                request: Dictionary<Member, Bool>.mapping(over: participants) { _ in false },
                vote: Dictionary<Member, Vote>.mapping(over: participants) { _ in Vote.waiting },
                broadcast: unsent,
                decision: Decision.undecided, alive: true, faulty: false))
            let collecting = coordinator.alive && coordinator.decision == Decision.undecided
            let allRequested = participants.allSatisfy { member in coordinator.request[member] }

            let request = Do(Step.request, over: participants) { member in
                When(coordinator.alive && !coordinator.request[member])
                coordinator.request[member].set(true)
            }
            request
            let getVote = Do(Step.getVote, over: participants) { member in
                When(collecting && allRequested && coordinator.vote[member] == Vote.waiting && participant[member].voteSent)
                coordinator.vote[member].set(participant[member].vote)
            }
            getVote
            let detectFault = Do(Step.detectFault, over: participants) { member in
                When(collecting && allRequested && coordinator.vote[member] == Vote.waiting)
                When(!participant[member].alive && !participant[member].voteSent)
                coordinator.decision.set(Decision.abort)
            }
            detectFault
            let makeDecision = Do(Step.makeDecision, when: collecting) {
                When(participants.allSatisfy { member in coordinator.vote[member] != Vote.waiting })
                If(participants.allSatisfy { member in coordinator.vote[member] == Vote.yes }) {
                    coordinator.decision.set(Decision.commit)
                } else: {
                    coordinator.decision.set(Decision.abort)
                }
            }
            makeDecision
            let coordBroadcast = Do(Step.coordBroadcast, over: participants) { member in
                When(coordinator.alive && coordinator.decision != Decision.undecided)
                When(coordinator.broadcast[member] == Decision.notsent)
                coordinator.broadcast[member].set(coordinator.decision)
            }
            coordBroadcast
            Do(Step.coordDie, when: coordinator.alive) {
                coordinator.alive.set(false)
                coordinator.faulty.set(true)
            }

            let sendVote = Do(Step.sendVote, over: participants) { member in
                When(participant[member].alive && coordinator.request[member])
                participant[member].voteSent.set(true)
            }
            sendVote
            let abortOnVote = Do(Step.abortOnVote, over: participants) { member in
                When(participant[member].alive && participant[member].decision == Decision.undecided)
                When(participant[member].voteSent && participant[member].vote == Vote.no)
                participant[member].decision.set(Decision.abort)
            }
            abortOnVote
            let abortOnTimeoutRequest = Do(Step.abortOnTimeoutRequest, over: participants) { member in
                When(participant[member].alive && participant[member].decision == Decision.undecided)
                When(!coordinator.alive && !coordinator.request[member])
                participant[member].decision.set(Decision.abort)
            }
            abortOnTimeoutRequest
            let forward = Do(Step.forward, over: participants, participants) { sender, receiver in
                When(sender != receiver && participant[sender].alive)
                let message = If(decideBeforeForwarding, then: participant[sender].decision, else: participant[sender].forward[sender])
                When(message != Decision.notsent)
                When(participant[sender].forward[receiver] == Decision.notsent)
                participant[sender].forward[receiver].set(message)
            }
            forward
            let preDecideOnForward = Do(Step.preDecideOnForward, over: participants, participants) { receiver, sender in
                When(!decideBeforeForwarding)
                When(receiver != sender && participant[receiver].alive)
                When(participant[receiver].forward[receiver] == Decision.notsent)
                When(participant[sender].forward[receiver] != Decision.notsent)
                participant[receiver].forward[receiver].set(participant[sender].forward[receiver])
            }
            preDecideOnForward
            let preDecide = Do(Step.preDecide, over: participants) { member in
                When(!decideBeforeForwarding)
                When(participant[member].alive && participant[member].forward[member] == Decision.notsent)
                When(coordinator.broadcast[member] != Decision.notsent)
                participant[member].forward[member].set(coordinator.broadcast[member])
            }
            preDecide
            let decideNB = Do(Step.decideNB, over: participants) { member in
                When(!decideBeforeForwarding)
                When(participant[member].alive)
                When(participants.allSatisfy { peer in participant[member].forward[peer] != Decision.notsent })
                participant[member].decision.set(participant[member].forward[member])
            }
            decideNB
            let decide = Do(Step.decide, over: participants) { member in
                When(decideBeforeForwarding && participant[member].alive && participant[member].decision == Decision.undecided)
                When(coordinator.broadcast[member] != Decision.notsent)
                participant[member].decision.set(coordinator.broadcast[member])
            }
            decide
            let decideOnForward = Do(Step.decideOnForward, over: participants, participants) { receiver, sender in
                When(decideBeforeForwarding && receiver != sender && participant[receiver].alive)
                When(participant[receiver].decision == Decision.undecided && participant[sender].forward[receiver] != Decision.notsent)
                participant[receiver].decision.set(participant[sender].forward[receiver])
            }
            decideOnForward
            let abortOnTimeout = Do(Step.abortOnTimeout, over: participants) { member in
                When(participant[member].alive && participant[member].decision == Decision.undecided && !coordinator.alive)
                When(participants.allSatisfy { live in
                    !participant[live].alive || coordinator.broadcast[live] == Decision.notsent
                })
                When(participants.allSatisfy { sender in
                    participant[sender].alive || participants.allSatisfy { receiver in
                        !participant[receiver].alive || participant[sender].forward[receiver] == Decision.notsent
                    }
                })
                participant[member].decision.set(Decision.abort)
            }
            abortOnTimeout
            Do(Step.parDie, over: participants) { member in
                When(participant[member].alive)
                participant[member].alive.set(false)
                participant[member].faulty.set(true)
            }

            WeakFairness(eachOf: [sendVote, abortOnVote, abortOnTimeoutRequest, forward, preDecideOnForward, abortOnTimeout, preDecide, decideNB, decide, decideOnForward])
            WeakFairness(anyOf: [makeDecision, request, getVote, detectFault, coordBroadcast])

            let anyCommit = participants.contains { member in participant[member].decision == Decision.commit }
            let anyAbort = participants.contains { member in participant[member].decision == Decision.abort }
            let anyFault = coordinator.faulty || participants.contains { member in participant[member].faulty }
            let AC1 = Temporal()
            AC1(.always(!anyCommit || !anyAbort))
            let AC2 = Temporal()
            AC2(.always(!anyCommit || participants.allSatisfy { member in participant[member].vote == Vote.yes }))
            let AC3_1 = Temporal()
            AC3_1(.always(!anyAbort || anyFault || participants.contains { member in participant[member].vote == Vote.no }))
            let AC4_alt = Temporal()
            AC4_alt(.alwaysStep(on: participant) { before, after in
                participants.allSatisfy { member in
                    (before[member].decision != Decision.commit || after[member].decision == Decision.commit)
                        && (before[member].decision != Decision.abort || after[member].decision == Decision.abort)
                }
            })
            let AC3_2 = Temporal()
            AC3_2(.eventually(anyFault || participants.allSatisfy { member in
                participant[member].decision == Decision.commit || participant[member].decision == Decision.abort
            }))
            let AC5 = Temporal()
            AC5(.eventually(participants.allSatisfy { member in
                participant[member].decision == Decision.commit || participant[member].decision == Decision.abort
                    || participant[member].faulty
            }))

            Validation("twoParticipants") {
                Bind(participants, to: Set<Member>([.p0, .p1]))
                Bind(decideBeforeForwarding, to: false)
            }.checking(only: [AC1, AC2, AC3_1, AC4_alt, AC3_2, AC5]).checkingDeadlock(false)
            Validation("earlyDecision") {
                Bind(participants, to: Set<Member>([.p0, .p1]))
                Bind(decideBeforeForwarding, to: true)
            }.checking(only: [AC1]).checkingDeadlock(false).expect(AC1, .violated)
        }
    }
}
