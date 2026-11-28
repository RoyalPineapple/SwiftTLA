// A replicated log coordinates checkpoint leases. A second configuration deliberately replaces a lease too soon.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/CheckpointCoordination/CheckpointCoordination.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct CheckpointCoordinationModel: Sendable {
    package enum Member: String, CaseIterable, FiniteTLAValueDomain {
        case n1, n2, n3, noNode = "NoNode"
        package static var defaultValue: Self { .noNode }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum EmptyLease: String, CaseIterable, FiniteTLAValueDomain {
        case none = "NoCheckpointLease"
        package static var defaultValue: Self { .none }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package struct CheckpointLease: Hashable, Sendable {
        package let node: Member
        package let counter: Int
    }
    package struct LogCheckpoint: Hashable, Sendable {
        package let log: [Member]
        package let counter: Int
    }
    package typealias Lease = OneOf<CheckpointLease, EmptyLease>
    package typealias Link = Pair<Member, Member>
    private enum Step: String, CaseIterable {
        case nodeFailure = "NodeFailure", nodeRecovery = "NodeRecovery"
        case networkFailure = "NetworkFailure", networkRecovery = "NetworkRecovery", electLeader = "ElectLeader"
        case send = "SendReplicatedRequest", propagate = "PropagateReplicatedRequest", process = "ProcessReplicatedRequest"
        case start = "StartCheckpoint", finish = "FinishCheckpoint", timeout = "TriggerTimeout"
    }

    package static var spec: TLASpec {
        #spec("MCCheckpointCoordination") { scope in
            let Node = scope.parameter(as: Set<Member>.self, in: Set<Set<Member>>([Set<Member>([Member.n1, Member.n2, Member.n3])]))
            let Majority = scope.parameter(as: Int.self, in: 2...2)
            let MaxLog = scope.parameter(as: Int.self, in: 3...3)
            let MaxNat = scope.parameter(as: Int.self, in: 5...5)
            let incorrectlyReplaceLeaderLease = scope.parameter(as: Bool.self, in: Set<Bool>([false, true]))
            let NoNode = Member.noNode
            let noLease: Expr<Lease> = Lease.second(EmptyLease.none.expr)
            let links = Node.flatMapping { (from: WithValue<Member>) in
                Node.mapping { (to: WithValue<Member>) in Pair<Member, Member>.literal(from, to) }
            }
            let blank = SequenceMapping(length: MaxLog) { _ in Member.noNode.expr }
            let IsNodeUp = scope.sharedVar(initial: Dictionary<Member, Bool>.mapping(over: Node) { _ in true })
            let NetworkPath = scope.sharedVar(initial: Dictionary<Link, Bool>.mapping(over: links) { _ in true })
            let Leader = scope.sharedVar(initial: Member.noNode)
            let ReplicatedLog = scope.sharedVar(initial: Dictionary<Member, [Member]>.mapping(over: Node) { _ in blank })
            let ExecutionCounter = scope.sharedVar(initial: Dictionary<Member, Int>.mapping(over: Node) { _ in 1 })
            let LastVotePayload = scope.sharedVar(initial: Dictionary<Member, Int>.mapping(over: Node) { _ in 1 })
            let CurrentLease = scope.sharedVar(initial: Dictionary<Member, Lease>.mapping(over: Node) { _ in noLease })
            let CanTakeCheckpoint = scope.sharedVar(initial: Dictionary<Member, Bool>.mapping(over: Node) { _ in false })
            let IsTakingCheckpoint = scope.sharedVar(initial: Dictionary<Member, Bool>.mapping(over: Node) { _ in false })
            let TimeoutCounter = scope.sharedVar(initial: 1)
            let LatestCheckpoint = scope.sharedVar(initial: LogCheckpoint.expression(log: blank, counter: 1))

            let oneWay = Dictionary<Link, Bool>.mapping(over: links) { link in
                IsNodeUp[link.first()] && IsNodeUp[link.second()] && NetworkPath[link]
            }
            let connected = Dictionary<Link, Bool>.mapping(over: links) { link in
                oneWay[link] && oneWay[Pair<Member, Member>.literal(link.second(), link.first())]
            }
            let quorum = Dictionary<Member, Bool>.mapping(over: Node) { leader in
                IsNodeUp[leader] && Node.filter { n in connected[Pair<Member, Member>.literal(leader, n)] }.count >= Majority
            }
            let indices = IntRange(1, through: MaxLog)
            let openIndices = indices.filter { i in
                Node.allSatisfy { n in i > ReplicatedLog[n].count || ReplicatedLog[n].at(i) == NoNode }
            }
            let firstOpen = Select(from: openIndices) { i in openIndices.allSatisfy { other in i <= other } }

            Do(Step.nodeFailure, over: Node) { n in
                IsNodeUp[n].set(false)
                If(n == Leader) { Leader.set(NoNode) }
                ExecutionCounter[n].set(1)
                LastVotePayload[n].set(1)
                CurrentLease[n].set(noLease)
                CanTakeCheckpoint[n].set(false)
                IsTakingCheckpoint[n].set(false)
            }
            let recover = Do(Step.nodeRecovery, over: Node) { n in
                When(!IsNodeUp[n])
                IsNodeUp[n].set(true)
                let saved = LatestCheckpoint.log.prefix(length: LatestCheckpoint.counter - 1)
                let remaining = If(ReplicatedLog[n].count < LatestCheckpoint.counter, then: 0,
                                   else: ReplicatedLog[n].count - LatestCheckpoint.counter + 1)
                ReplicatedLog[n].set(saved.concatenating(SequenceMapping(length: remaining) { i in
                    ReplicatedLog[n].at(LatestCheckpoint.counter + i - 1)
                }))
                ExecutionCounter[n].set(LatestCheckpoint.counter)
                LastVotePayload[n].set(1)
                CurrentLease[n].set(noLease)
                CanTakeCheckpoint[n].set(false)
                IsTakingCheckpoint[n].set(false)
            }
            Do(Step.networkFailure, over: Node, Node) { src, dst in
                When(src != dst)
                NetworkPath[Pair<Member, Member>.literal(src, dst)].set(false)
            }
            let networkRecovery = Do(Step.networkRecovery, over: Node, Node) { src, dst in
                NetworkPath[Pair<Member, Member>.literal(src, dst)].set(true)
            }
            let start = Do(Step.start, over: Node) { n in
                When(CanTakeCheckpoint[n])
                IsTakingCheckpoint[n].set(true)
            }
            let elect = Do(Step.electLeader, over: Node) { n in
                When(Leader == NoNode && IsNodeUp[n] && !IsTakingCheckpoint[n] && quorum[n])
                When(ExecutionCounter[n] == firstOpen)
                Leader.set(n)
                CanTakeCheckpoint[n].set(false)
            }
            let send = Do(Step.send, over: Node) { prospect in
                When(Leader != NoNode && quorum[Leader] && Leader != prospect && connected[Pair<Member, Member>.literal(Leader, prospect)])
                let lease = CurrentLease[Leader]
                When(lease == noLease || lease.assuming(CheckpointLease.self).counter < TimeoutCounter ||
                     (connected[Pair<Member, Member>.literal(Leader, lease.assuming(CheckpointLease.self).node)] &&
                      lease.assuming(CheckpointLease.self).counter < LastVotePayload[lease.assuming(CheckpointLease.self).node]) ||
                     (incorrectlyReplaceLeaderLease && lease.assuming(CheckpointLease.self).node == Leader))
                Let(firstOpen) { index in
                    ReplicatedLog.set(Dictionary<Member, [Member]>.mapping(over: Node) { n in
                        If(oneWay[Pair<Member, Member>.literal(Leader, n)], then: SequenceMapping(length: MaxLog) { i in
                            If(i == index, then: prospect.expr,
                               else: If(i <= ReplicatedLog[n].count, then: ReplicatedLog[n].at(i), else: NoNode))
                        }, else: ReplicatedLog[n])
                    })
                    CurrentLease[Leader].set(Lease.first(CheckpointLease.expression(node: prospect, counter: index)))
                }
            }
            let propagate = Do(Step.propagate, over: Node, Node) { src, dst in
                When(oneWay[Pair<Member, Member>.literal(src, dst)])
                ReplicatedLog[dst].set(SequenceMapping(length: MaxLog) { i in
                    If(i <= ReplicatedLog[dst].count && ReplicatedLog[dst].at(i) != NoNode,
                       then: ReplicatedLog[dst].at(i),
                       else: If(i <= ReplicatedLog[src].count, then: ReplicatedLog[src].at(i), else: NoNode))
                })
            }
            let process = Do(Step.process, over: Node) { n in
                When(IsNodeUp[n] && !IsTakingCheckpoint[n])
                Let(ExecutionCounter[n]) { i in
                    When(i >= 1 && i <= ReplicatedLog[n].count && ReplicatedLog[n].at(i) != NoNode)
                    let request = ReplicatedLog[n].at(i)
                    CanTakeCheckpoint[n].set(Leader != n && n == request && i >= TimeoutCounter)
                    If(n != Leader) {
                        CurrentLease[n].set(If(i < TimeoutCounter, then: noLease,
                            else: Lease.first(CheckpointLease.expression(node: request, counter: i))))
                    }
                    ExecutionCounter[n].set(i + 1)
                }
            }
            let finish = Do(Step.finish, over: Node) { n in
                When(IsTakingCheckpoint[n])
                LastVotePayload[n].set(ExecutionCounter[n])
                CurrentLease[n].set(noLease)
                CanTakeCheckpoint[n].set(false)
                IsTakingCheckpoint[n].set(false)
                LatestCheckpoint.set(LogCheckpoint.expression(log: ReplicatedLog[n].prefix(length: ExecutionCounter[n] - 1),
                                                              counter: ExecutionCounter[n]))
            }
            Do(Step.timeout) {
                When(Node.contains { n in
                    TimeoutCounter >= 1 && TimeoutCounter <= ReplicatedLog[n].count && ReplicatedLog[n].at(TimeoutCounter) != NoNode
                })
                CanTakeCheckpoint.set(Dictionary<Member, Bool>.mapping(over: Node) { n in
                    CanTakeCheckpoint[n] && CurrentLease[n].assuming(CheckpointLease.self).counter > TimeoutCounter
                })
                IsTakingCheckpoint.set(Dictionary<Member, Bool>.mapping(over: Node) { n in
                    IsTakingCheckpoint[n] && CurrentLease[n].assuming(CheckpointLease.self).counter > TimeoutCounter
                })
                TimeoutCounter += 1
            }
            WeakFairness(each: recover)
            WeakFairness(each: networkRecovery)
            StrongFairness(each: elect)
            StrongFairness(each: send)
            StrongFairness(each: propagate)
            StrongFairness(each: process)
            StrongFairness(each: start)
            StrongFairness(each: finish)

            Constraint(!openIndices.isEmpty)
            let logValues = Node.inserting(NoNode)
            let logs = Sequences(of: logValues)
            Invariant("TypeInvariant") {
                IsNodeUp.keys == Node && NetworkPath.keys == links && logValues.contains(Leader)
                ReplicatedLog.keys == Node && Node.allSatisfy { n in logs.contains(ReplicatedLog[n]) }
                Functions(from: Node, to: indices).contains(ExecutionCounter)
                Functions(from: Node, to: indices).contains(LastVotePayload)
                CurrentLease.keys == Node && Node.allSatisfy { n in
                    CurrentLease[n] == noLease || (Node.contains(CurrentLease[n].assuming(CheckpointLease.self).node)
                        && indices.contains(CurrentLease[n].assuming(CheckpointLease.self).counter))
                }
                CanTakeCheckpoint.keys == Node && IsTakingCheckpoint.keys == Node
                indices.contains(TimeoutCounter) && indices.contains(LatestCheckpoint.counter) && logs.contains(LatestCheckpoint.log)
            }
            let safe = Invariant("SafetyInvariant")
            safe {
                Leader == NoNode || (!CanTakeCheckpoint[Leader] && !IsTakingCheckpoint[Leader] &&
                    Node.allSatisfy { n in
                        (!CanTakeCheckpoint[n] && !IsTakingCheckpoint[n]) ||
                        (CurrentLease[Leader] != noLease && CurrentLease[Leader].assuming(CheckpointLease.self).node == n)
                    })
                Node.filter { n in CanTakeCheckpoint[n] }.count <= 1
                Node.filter { n in IsTakingCheckpoint[n] }.count <= 1
                Node.allSatisfy { n in
                    (!IsTakingCheckpoint[n] || CanTakeCheckpoint[n]) &&
                    (!CanTakeCheckpoint[n] || (CurrentLease[n] != noLease &&
                        CurrentLease[n].assuming(CheckpointLease.self).node == n &&
                        CurrentLease[n].assuming(CheckpointLease.self).counter >= TimeoutCounter))
                }
                indices.allSatisfy { i in
                    Node.allSatisfy { a in Node.allSatisfy { b in
                        i > ReplicatedLog[a].count || i > ReplicatedLog[b].count ||
                        ReplicatedLog[a].at(i) == NoNode || ReplicatedLog[b].at(i) == NoNode ||
                        ReplicatedLog[a].at(i) == ReplicatedLog[b].at(i)
                    } }
                }
            }

            let NodeSymmetry = Symmetry(Node)
            Validation("Upstream") {
                Bind(Node, to: Set<Member>([Member.n1, Member.n2, Member.n3]))
                Bind(Majority, to: 2)
                Bind(MaxLog, to: 3)
                Bind(MaxNat, to: 5)
                Bind(incorrectlyReplaceLeaderLease, to: false)
            }.usingSymmetry(NodeSymmetry)
            Validation("IncorrectLease") {
                Bind(Node, to: Set<Member>([Member.n1, Member.n2, Member.n3]))
                Bind(Majority, to: 2)
                Bind(MaxLog, to: 3)
                Bind(MaxNat, to: 5)
                Bind(incorrectlyReplaceLeaderLease, to: true)
            }.usingSymmetry(NodeSymmetry).expect(safe, .violated)
        }
    }
}
