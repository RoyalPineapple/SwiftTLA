import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct AtomicCommitProtocolModel: Sendable {
    package enum Member: String, CaseIterable, FiniteTLAValueDomain {
        case p0, p1, p2
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
        case sendVote, abortOnVote, abortOnTimeoutRequest, decide, parDie
    }

    package static var spec: TLASpec {
        #spec("AtomicCommitProtocol") { scope in
            let participants = scope.parameter(as: Set<Member>.self, in: Subsets(of: Member.all.assuming(Set<Member>.self)))
            let initialParticipants = SetExpr<Vote>.literal(.yes, .no).mapping { vote in
                Participant.expression(vote: vote, alive: true, decision: Decision.undecided, faulty: false, voteSent: false)
            }
            let participant: SharedVariable<[Member: Participant]> = scope.sharedVar(
                initiallyIn: Functions(from: participants, to: initialParticipants))
            let coordinator = scope.sharedVar(initial: Coordinator.expression(
                request: Dictionary<Member, Bool>.mapping(over: participants) { _ in false },
                vote: Dictionary<Member, Vote>.mapping(over: participants) { _ in Vote.waiting },
                broadcast: Dictionary<Member, Decision>.mapping(over: participants) { _ in Decision.notsent },
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
            let decide = Do(Step.decide, over: participants) { member in
                When(participant[member].alive && participant[member].decision == Decision.undecided)
                When(coordinator.broadcast[member] != Decision.notsent)
                participant[member].decision.set(coordinator.broadcast[member])
            }
            decide
            Do(Step.parDie, over: participants) { member in
                When(participant[member].alive)
                participant[member].alive.set(false)
                participant[member].faulty.set(true)
            }

            WeakFairness(eachOf: [sendVote, abortOnVote, abortOnTimeoutRequest, decide])
            WeakFairness(anyOf: [makeDecision, request, getVote, detectFault, coordBroadcast])

            Validation("simpleBroadcast") {
                Bind(participants, to: Set<Member>([.p0, .p1, .p2]))
            }.checkingDeadlock(false)
        }
    }
}
