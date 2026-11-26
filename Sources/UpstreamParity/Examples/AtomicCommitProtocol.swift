import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct AtomicCommitProtocolModel: Sendable {
    package enum Member: String, CaseIterable, FiniteTLAValueDomain {
        case p0, p1, p2
        case ap1 = "p1_OF_PARTICIPANT", ap2 = "p2_OF_PARTICIPANT", ap3 = "p3_OF_PARTICIPANT"
        package static var defaultValue: Self { .p0 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue {
            switch self {
            case .p0, .p1, .p2: .constant(rawValue)
            case .ap1, .ap2, .ap3: .string(rawValue)
            }
        }
    }

    package enum VoteSymbol: String, CaseIterable, FiniteTLAValueDomain {
        case yes, no, waiting
        package static var defaultValue: Self { .waiting }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum DecisionSymbol: String, CaseIterable, FiniteTLAValueDomain {
        case undecided, commit, abort, notsent
        package static var defaultValue: Self { .undecided }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package typealias Vote = OneOf<VoteSymbol, String>
    package typealias Decision = OneOf<DecisionSymbol, String>

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
            let participants = scope.parameter(as: Set<Member>.self, in: Set<Set<Member>>([
                Set<Member>([]), Set([.p0]), Set([.p1]), Set([.p2]), Set([.p0, .p1]),
                Set([.p0, .p2]), Set([.p1, .p2]), Set([.p0, .p1, .p2]), Set([.ap1, .ap2, .ap3])
            ]))
            let stringTags = scope.parameter(as: Bool.self)
            let yes = If(stringTags, then: "yes".assuming(Vote.self), else: VoteSymbol.yes.assuming(Vote.self))
            let no = If(stringTags, then: "no".assuming(Vote.self), else: VoteSymbol.no.assuming(Vote.self))
            let waiting = If(stringTags, then: "waiting".assuming(Vote.self), else: VoteSymbol.waiting.assuming(Vote.self))
            let undecided = If(stringTags, then: "undecided".assuming(Decision.self), else: DecisionSymbol.undecided.assuming(Decision.self))
            let commit = If(stringTags, then: "commit".assuming(Decision.self), else: DecisionSymbol.commit.assuming(Decision.self))
            let abort = If(stringTags, then: "abort".assuming(Decision.self), else: DecisionSymbol.abort.assuming(Decision.self))
            let notsent = If(stringTags, then: "notsent".assuming(Decision.self), else: DecisionSymbol.notsent.assuming(Decision.self))
            let initialParticipants = SetExpr<Vote>.literal(yes, no).mapping { vote in
                Participant.expression(vote: vote, alive: true, decision: undecided, faulty: false, voteSent: false)
            }
            let participant: SharedVariable<[Member: Participant]> = scope.sharedVar(
                initiallyIn: Functions(from: participants, to: initialParticipants))
            let coordinator = scope.sharedVar(initial: Coordinator.expression(
                request: Dictionary<Member, Bool>.mapping(over: participants) { _ in false },
                vote: Dictionary<Member, Vote>.mapping(over: participants) { _ in waiting },
                broadcast: Dictionary<Member, Decision>.mapping(over: participants) { _ in notsent },
                decision: undecided, alive: true, faulty: false))
            let collecting = coordinator.alive && coordinator.decision == undecided
            let allRequested = participants.allSatisfy { member in coordinator.request[member] }

            let request = Do(Step.request, over: participants) { member in
                When(coordinator.alive && !coordinator.request[member])
                coordinator.request[member].set(true)
            }
            request
            let getVote = Do(Step.getVote, over: participants) { member in
                When(collecting && allRequested && coordinator.vote[member] == waiting && participant[member].voteSent)
                coordinator.vote[member].set(participant[member].vote)
            }
            getVote
            let detectFault = Do(Step.detectFault, over: participants) { member in
                When(collecting && allRequested && coordinator.vote[member] == waiting)
                When(!participant[member].alive && !participant[member].voteSent)
                coordinator.decision.set(abort)
            }
            detectFault
            let makeDecision = Do(Step.makeDecision, when: collecting) {
                When(participants.allSatisfy { member in coordinator.vote[member] != waiting })
                If(participants.allSatisfy { member in coordinator.vote[member] == yes }) {
                    coordinator.decision.set(commit)
                } else: {
                    coordinator.decision.set(abort)
                }
            }
            makeDecision
            let coordBroadcast = Do(Step.coordBroadcast, over: participants) { member in
                When(coordinator.alive && coordinator.decision != undecided)
                When(coordinator.broadcast[member] == notsent)
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
                When(participant[member].alive && participant[member].decision == undecided)
                When(participant[member].voteSent && participant[member].vote == no)
                participant[member].decision.set(abort)
            }
            abortOnVote
            let abortOnTimeoutRequest = Do(Step.abortOnTimeoutRequest, over: participants) { member in
                When(participant[member].alive && participant[member].decision == undecided)
                When(!coordinator.alive && !coordinator.request[member])
                participant[member].decision.set(abort)
            }
            abortOnTimeoutRequest
            let decide = Do(Step.decide, over: participants) { member in
                When(participant[member].alive && participant[member].decision == undecided)
                When(coordinator.broadcast[member] != notsent)
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

            let typeInvariant = Invariant("TypeInv")
            typeInvariant {
                participant.keys == participants.assuming(Set<Member>.self)
                participants.allSatisfy { member in
                    SetExpr<Vote>.literal(yes, no).contains(participant[member].vote)
                        && SetExpr<Decision>.literal(undecided, commit, abort).contains(participant[member].decision)
                        && Bool.all.contains(participant[member].alive)
                        && Bool.all.contains(participant[member].faulty)
                        && Bool.all.contains(participant[member].voteSent)
                }
                Functions(from: participants, to: Bool.all).contains(coordinator.request)
                Functions(from: participants, to: SetExpr<Vote>.literal(waiting, yes, no)).contains(coordinator.vote)
                Functions(from: participants, to: SetExpr<Decision>.literal(commit, abort, notsent)).contains(coordinator.broadcast)
                SetExpr<Decision>.literal(commit, abort, undecided).contains(coordinator.decision)
                Bool.all.contains(coordinator.alive)
                Bool.all.contains(coordinator.faulty)
            }
            Validation("simpleBroadcast") {
                Bind(participants, to: Set<Member>([.p0, .p1, .p2]))
                Bind(stringTags, to: false)
            }.checking(only: []).checkingDeadlock(false)
            Validation("APACP_SB") {
                Bind(participants, to: Set<Member>([.ap1, .ap2, .ap3]))
                Bind(stringTags, to: true)
            }.behavior(.initialAndNext).checking(only: [typeInvariant]).checkingDeadlock(false)
        }
    }
}
