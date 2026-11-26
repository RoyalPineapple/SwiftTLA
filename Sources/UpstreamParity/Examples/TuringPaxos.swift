import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct TuringPaxosModel: Sendable {
    package enum Atom: String, CaseIterable, FiniteTLAValueDomain {
        case a1, a2, a3, v1, v2, none = "None"
        package static var defaultValue: Self { .none }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package struct Prepare: Hashable, Sendable {
        package let type: String
        package let bal: Int
    }
    package struct Promise: Hashable, Sendable {
        package let type: String
        package let acc: Atom
        package let bal: Int
        package let mbal: Int
        package let mval: Atom
    }
    package struct Propose: Hashable, Sendable {
        package let type: String
        package let bal: Int
        package let val: Atom
    }
    package struct Accept: Hashable, Sendable {
        package let type: String
        package let acc: Atom
        package let bal: Int
        package let val: Atom
    }
    package typealias PhaseOne = OneOf<Prepare, Promise>
    package typealias PhaseTwo = OneOf<Propose, Accept>
    package typealias Message = OneOf<PhaseOne, PhaseTwo>
    private enum Step: String, CaseIterable {
        case prepare = "Phase1a", promise = "Phase1b", propose = "Phase2a", accept = "Phase2b"
    }

    package static var spec: TLASpec {
        #spec("TuringPaxos") { scope in
            Extends(.integers, .finiteSets)
            let MaxBallot = scope.parameter(as: Int.self, in: 1...1)
            let values = scope.parameter(as: Set<Atom>.self, in: Set<Set<Atom>>([Set([.v1, .v2])]))
            let ballots = IntRange(0, through: MaxBallot)
            let acceptors = scope.parameter(as: Set<Atom>.self, in: Set<Set<Atom>>([Set([.a1, .a2, .a3])]))
            let quorums = scope.parameter(as: Set<Set<Atom>>.self, in: Set<Set<Set<Atom>>>([
                Set<Set<Atom>>([[Atom.a1, Atom.a2], [Atom.a1, Atom.a3], [Atom.a2, Atom.a3]])
            ]))
            let None = scope.parameter(as: Atom.self, in: Set<Atom>([Atom.none]))
            let maxBal = scope.sharedVar(initial: Dictionary<Atom, Int>.mapping(over: acceptors) { _ in -1 })
            let maxVBal = scope.sharedVar(initial: Dictionary<Atom, Int>.mapping(over: acceptors) { _ in -1 })
            let maxVal = scope.sharedVar(initial: Dictionary<Atom, Atom>.mapping(over: acceptors) { _ in None })
            let msgs = scope.sharedVar(initial: Set<Message>())

            let prepares = msgs.filter { m in m.recordFields == Set<String>(["type", "bal"]) }.mapping { m in m.assuming(Prepare.self) }
            let promises = msgs.filter { m in m.recordFields == Set<String>(["type", "acc", "bal", "mbal", "mval"]) }.mapping { m in m.assuming(Promise.self) }
            let proposals = msgs.filter { m in m.recordFields == Set<String>(["type", "bal", "val"]) }.mapping { m in m.assuming(Propose.self) }
            let accepts = msgs.filter { m in m.recordFields == Set<String>(["type", "acc", "bal", "val"]) }.mapping { m in m.assuming(Accept.self) }

            Do(Step.prepare, over: ballots) { b in
                msgs.insert(Message.first(PhaseOne.first(Prepare.expression(type: "1a", bal: b))))
            }
            Do(Step.promise, over: acceptors) { a in
                With(ballots) { b in
                    When(msgs.contains(Message.first(PhaseOne.first(Prepare.expression(type: "1a", bal: b)))))
                    When(b > maxBal[a])
                    msgs.insert(Message.first(PhaseOne.second(Promise.expression(
                        type: "1b", acc: a, bal: b, mbal: maxVBal[a], mval: maxVal[a]))))
                    maxBal[a].set(b)
                }
            }
            Do(Step.propose, over: ballots, values) { b, v in
                When(!proposals.contains { m in m.bal == b })
                With(quorums) { quorum in
                    let replies = promises.filter { m in m.bal == b && quorum.contains(m.acc) }
                    let voted = replies.filter { m in m.mbal >= 0 }
                    When(quorum.allSatisfy { a in replies.contains { m in m.acc == a } })
                    When(voted.isEmpty || voted.contains { m in m.mval == v && voted.allSatisfy { other in m.mbal >= other.mbal } })
                    msgs.insert(Message.second(PhaseTwo.first(Propose.expression(type: "2a", bal: b, val: v))))
                }
            }
            Do(Step.accept, over: acceptors) { a in
                With(ballots, values) { b, v in
                    When(msgs.contains(Message.second(PhaseTwo.first(Propose.expression(type: "2a", bal: b, val: v)))))
                    When(b >= maxBal[a])
                    maxBal[a].set(b)
                    maxVBal[a].set(b)
                    maxVal[a].set(v)
                    msgs.insert(Message.second(PhaseTwo.second(Accept.expression(type: "2b", acc: a, bal: b, val: v))))
                }
            }

            let votes = Dictionary<Atom, Set<Pair<Int, Atom>>>.mapping(over: acceptors) { a in
                accepts.filter { m in m.acc == a }.mapping { m in Pair<Int, Atom>.literal(m.bal, m.val) }
            }
            let previousBallots = IntRange(-1, through: MaxBallot)
            let previousValues = values.inserting(None)
            let valueTypes = maxBal.keys == acceptors && maxVBal.keys == acceptors && maxVal.keys == acceptors
                && acceptors.allSatisfy { a in
                    previousBallots.contains(maxBal[a]) && previousBallots.contains(maxVBal[a]) && previousValues.contains(maxVal[a])
                }
            let prepareTypes = prepares.allSatisfy { m in m.type == "1a" && ballots.contains(m.bal) }
            let promiseTypes = promises.allSatisfy { m in
                m.type == "1b" && ballots.contains(m.bal) && acceptors.contains(m.acc)
                    && previousBallots.contains(m.mbal) && previousValues.contains(m.mval)
            }
            let proposalTypes = proposals.allSatisfy { m in m.type == "2a" && ballots.contains(m.bal) && values.contains(m.val) }
            let acceptTypes = accepts.allSatisfy { m in
                m.type == "2b" && ballots.contains(m.bal) && acceptors.contains(m.acc) && values.contains(m.val)
            }
            let allMessagesTyped = prepares.count + promises.count + proposals.count + accepts.count == msgs.count
            let typeOK = valueTypes && allMessagesTyped && prepareTypes && promiseTypes && proposalTypes && acceptTypes
            let consistentMax = acceptors.allSatisfy { a in
                maxBal[a] >= maxVBal[a] && If(maxVBal[a] == -1, then: maxVal[a] == None,
                    else: votes[a].contains(Pair<Int, Atom>.literal(maxVBal[a], maxVal[a])))
            }
            let validPromises = promises.allSatisfy { m in
                maxBal[m.acc] >= m.bal && (m.mbal < 0 || votes[m.acc].contains(Pair<Int, Atom>.literal(m.mbal, m.mval)))
            }
            let safeProposals = proposals.allSatisfy { (m: WithValue<Propose>) in
                quorums.contains { (quorum: WithValue<Set<Atom>>) in
                    quorum.allSatisfy { a in maxBal[a] >= m.bal }
                        && IntRange(-1, through: m.bal - 1).contains { (c: WithValue<Int>) in
                            (c == -1 || quorum.contains { a in votes[a].contains(Pair<Int, Atom>.literal(c, m.val)) })
                                && quorum.allSatisfy { a in
                                    !votes[a].contains { (vote: WithValue<Pair<Int, Atom>>) in
                                        c < vote.first() && vote.first() < m.bal
                                    }
                                }
                        }
                }
            }
            let consistentProposals = proposals.allSatisfy { m in proposals.allSatisfy { other in other.bal != m.bal || other.val == m.val } }
            let acceptedProposals = accepts.allSatisfy { m in
                maxVBal[m.acc] >= m.bal && proposals.contains { proposal in proposal.bal == m.bal && proposal.val == m.val }
            }
            Invariant("Inv") { typeOK && consistentMax && validPromises && safeProposals && consistentProposals && acceptedProposals }
            let voting = Instance(of: TuringVotingModel.self) {
                Bind(\.MaxBallot, to: MaxBallot)
                Bind(\.values, projecting: values)
            }
            voting
            let prop_1560336937635612000 = Refinement(instance: voting) {
                Map(\.votes, projecting: votes)
                Map(\.maxBal, projecting: maxBal)
            }
            prop_1560336937635612000
            Validation("tiny") {
                Bind(MaxBallot, to: 1)
                Bind(acceptors, to: Set<Atom>([.a1, .a2, .a3]))
                Bind(quorums, to: Set<Set<Atom>>([[Atom.a1, Atom.a2], [Atom.a1, Atom.a3], [Atom.a2, Atom.a3]]))
                Bind(None, to: Atom.none)
                Bind(values, to: Set<Atom>([.v1, .v2]))
            }
        }
    }
}
