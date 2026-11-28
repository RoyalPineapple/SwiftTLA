// Replicas elect a leader, recover earlier votes and agree on a log of client commands.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/MultiPaxos-SMR/MultiPaxos.tla
import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct MultiPaxosSMRModel: Sendable {
    package enum Atom: String, CaseIterable, FiniteTLAValueDomain {
        case s1, s2, s3, w1, r1
        package static let finiteValues = allCases
        package static var defaultValue: Self { .s1 }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package typealias Value = OneOf<String, Atom>
    package struct Vote: Hashable, Sendable { package let bal: Int; package let cmd: Value }
    package struct Slot: Hashable, Sendable {
        package let status: String
        package let cmd: Value
        package let voted: Vote
    }
    package struct Node: Hashable, Sendable {
        package let leader: Value
        package let kvalue: Value
        package let commitUpTo: Int
        package let balPrepared: Int
        package let balMaxKnown: Int
        package let insts: [Slot]
    }
    package struct Prepare: Hashable, Sendable {
        package let type: String
        package let src: Atom
        package let bal: Int
    }
    package struct PrepareReply: Hashable, Sendable {
        package let type: String
        package let src: Atom
        package let bal: Int
        package let votes: [Vote]
    }
    package struct Accept: Hashable, Sendable {
        package let type: String
        package let src: Atom
        package let bal: Int
        package let slot: Int
        package let cmd: Value
    }
    package typealias PhaseOne = OneOf<Prepare, PrepareReply>
    package struct AcceptReply: Hashable, Sendable {
        package let type: String
        package let src: Atom
        package let bal: Int
        package let slot: Int
    }
    package struct CommitNotice: Hashable, Sendable {
        package let type: String
        package let upto: Int
    }
    package typealias Confirmation = OneOf<AcceptReply, CommitNotice>
    package typealias PhaseTwo = OneOf<Accept, Confirmation>
    package typealias Message = OneOf<PhaseOne, PhaseTwo>
    package struct Request: Hashable, Sendable { package let type: String; package let cmd: Atom }
    package struct Ack: Hashable, Sendable { package let type: String; package let cmd: Atom; package let val: Value }
    package typealias Event = OneOf<Request, Ack>
    private enum Step: String, CaseIterable { case rloop }

    package static var spec: TLASpec {
        #spec("MultiPaxos_MC") { model in
            Extends(.integers, .finiteSets, .sequences)
            let replicas = model.parameter(tlaName: "Replicas", as: Set<Atom>.self, in: Set<Set<Atom>>([Set<Atom>([.s1, .s2, .s3])]))
            let writes = model.parameter(tlaName: "Writes", as: Set<Atom>.self, in: Set<Set<Atom>>([Set<Atom>([.w1])]))
            let reads = model.parameter(tlaName: "Reads", as: Set<Atom>.self, in: Set<Set<Atom>>([Set<Atom>([.r1])]))
            let maxBallot = model.parameter(tlaName: "MaxBallot", as: Int.self, in: 2...2)
            let noLeader: Value = Value.first("none")
            let noValue: Value = Value.first("nil")
            let commands = writes.union(reads)
            let slots = commands.count
            let typeOK = Invariant("TypeOK")
            let linearizability = Invariant("Linearizability")
            let validCommands = commands.mapping { c in Value.second(c) }.inserting(noValue)
            let validValues = writes.mapping { w in Value.second(w) }.inserting(noValue)
            let validLeaders = replicas.mapping { r in Value.second(r) }.inserting(noLeader)
            // ConditionalPerm returns the empty set for Small’s singleton Writes and Reads.
            let replicaSymmetry = Symmetry(replicas)
            Assume(replicas.count >= 1 && writes.count >= 1 && maxBallot >= 2)
            Algorithm("MultiPaxos") { scope in
                let messages = scope.sharedVar(tlaName: "msgs", initial: Set<Message>())
                let node = scope.sharedVar(initial: Dictionary<Atom, Node>.mapping(over: replicas) { _ in
                    Node.expression(leader: noLeader, kvalue: noValue, commitUpTo: 0, balPrepared: 0, balMaxKnown: 0,
                        insts: SequenceMapping(length: slots) { _ in
                            Slot(status: "Empty", cmd: noValue, voted: Vote(bal: 0, cmd: noValue))
                        })
                })
                // The two CHOOSE permutations are unique for Small's singleton Writes and Reads.
                let pending = scope.sharedVar(initial: [Atom.w1, Atom.r1])
                let observed = scope.sharedVar(initial: [Event]())
                let eventPositions = IntRange(1, through: observed.count)
                let events = eventPositions.mapping { i in observed[i] }
                let requested = events.filter { event in
                    event.recordFields == Set<String>(["type", "cmd"]) && event.assuming(Request.self).type == "Req"
                }.mapping { event in event.assuming(Request.self).cmd }
                let acknowledged = events.filter { event in
                    event.recordFields == Set<String>(["type", "cmd", "val"]) && event.assuming(Ack.self).type == "Ack"
                }.mapping { event in event.assuming(Ack.self).cmd }
                let terminated = pending.isEmpty && requested.count == slots && acknowledged.count == slots
                Each(replicas) { replica in
                    Do(Step.rloop) {
                        If(terminated) { Stop() } else: {
                            let current = node[replica]
                            let ballots = IntRange(1, through: maxBallot)
                            let votes = SequenceMapping(length: slots) { i in current.insts[i].voted }
                            let resetSlots = SequenceMapping(length: slots) { i in
                                Slot.expression(status: If(current.insts[i].status == "Accepting", then: "Preparing", else: current.insts[i].status),
                                                cmd: current.insts[i].cmd, voted: current.insts[i].voted)
                            }
                            Either {
                                When(current.leader != Value.second(replica)) {
                                    With(ballots) { ballot in
                                        When(ballot > current.balMaxKnown)
                                        When(!replicas.contains { source in
                                            messages.contains(Message.first(PhaseOne.first(Prepare.expression(type: "Prepare", src: source, bal: ballot))))
                                        })
                                        node[replica].set(Node.expression(leader: Value.second(replica), kvalue: current.kvalue,
                                            commitUpTo: current.commitUpTo, balPrepared: 0, balMaxKnown: ballot, insts: resetSlots))
                                        messages.insert(Message.first(PhaseOne.first(Prepare.expression(type: "Prepare", src: replica, bal: ballot))))
                                        messages.insert(Message.first(PhaseOne.second(PrepareReply.expression(type: "PrepareReply", src: replica, bal: ballot, votes: votes))))
                                    }
                                }
                                When(true) {
                                    With(replicas, ballots) { source, ballot in
                                        When(messages.contains(Message.first(PhaseOne.first(Prepare.expression(type: "Prepare", src: source, bal: ballot)))))
                                        When(ballot > current.balMaxKnown)
                                        node[replica].set(Node.expression(leader: Value.second(source), kvalue: current.kvalue,
                                            commitUpTo: current.commitUpTo, balPrepared: current.balPrepared, balMaxKnown: ballot, insts: resetSlots))
                                        messages.insert(Message.first(PhaseOne.second(PrepareReply.expression(type: "PrepareReply", src: replica, bal: ballot, votes: votes))))
                                    }
                                }
                                When(current.leader == Value.second(replica) && current.balPrepared == 0) {
                                    let replies = messages.filter { m in
                                        m.recordFields == Set<String>(["type", "src", "bal", "votes"])
                                    }.mapping { m in m.assuming(PrepareReply.self) }.filter { reply in
                                        reply.bal == current.balMaxKnown
                                    }
                                    When(replies.count >= replicas.count / 2 + 1)
                                    Let(SequenceMapping(length: slots) { i in
                                        If(replies.allSatisfy { reply in reply.votes[i].bal == 0 }, then: noValue,
                                           else: Select(from: replies) { candidate in
                                               replies.allSatisfy { other in other.votes[i].bal <= candidate.votes[i].bal }
                                           }.votes[i].cmd)
                                    }) { recovered in
                                        Let(SequenceMapping(length: slots) { i in
                                            Slot.expression(status: If(current.insts[i].status == "Preparing"
                                                || (current.insts[i].status == "Empty" && recovered[i] != noValue),
                                                then: "Accepting", else: current.insts[i].status),
                                                cmd: recovered[i], voted: current.insts[i].voted)
                                        }) { preparedSlots in
                                            node[replica].set(Node.expression(leader: current.leader, kvalue: current.kvalue,
                                                commitUpTo: current.commitUpTo, balPrepared: current.balMaxKnown,
                                                balMaxKnown: current.balMaxKnown, insts: preparedSlots))
                                            messages.formUnion(IntRange(1, through: slots).filter { i in
                                                preparedSlots[i].status == "Accepting"
                                            }.mapping { i in
                                                Message.second(PhaseTwo.first(Accept.expression(type: "Accept", src: replica,
                                                    bal: current.balMaxKnown, slot: i, cmd: preparedSlots[i].cmd)))
                                            })
                                        }
                                    }
                                }
                                When(current.leader == Value.second(replica) && current.balPrepared == current.balMaxKnown) {
                                    let emptySlots = IntRange(1, through: slots).filter { i in current.insts[i].status == "Empty" }
                                    let unseen = IntRange(1, through: pending.count).filter { i in
                                        current.insts.allSatisfy { slot in slot.cmd != Value.second(pending[i]) }
                                    }
                                    When(!emptySlots.isEmpty && !unseen.isEmpty)
                                    Let(Select(from: emptySlots) { i in emptySlots.allSatisfy { j in i <= j } }) { index in
                                        Let(Select(from: unseen) { i in unseen.allSatisfy { j in i <= j } }) { first in
                                            let command = pending[first]
                                            let vote = Vote.expression(bal: current.balPrepared, cmd: Value.second(command))
                                            node[replica].insts.set(SequenceMapping(length: slots) { i in
                                                If(i == index, then: Slot.expression(status: "Accepting", cmd: Value.second(command), voted: vote),
                                                   else: current.insts[i])
                                            })
                                            messages.insert(Message.second(PhaseTwo.first(Accept.expression(type: "Accept",
                                                src: replica, bal: current.balPrepared, slot: index, cmd: Value.second(command)))))
                                            messages.insert(Message.second(PhaseTwo.second(Confirmation.first(AcceptReply.expression(type: "AcceptReply",
                                                src: replica, bal: current.balPrepared, slot: index)))))
                                            let request = Event.first(Request.expression(type: "Req", cmd: command))
                                            If(!observed.contains(request)) { observed.set(observed.appending(request)) }
                                        }
                                    }
                                }
                                When(true) {
                                    let accepts = messages.filter { m in
                                        m.recordFields == Set<String>(["type", "src", "bal", "slot", "cmd"])
                                    }.mapping { m in m.assuming(Accept.self) }
                                    With(accepts) { accept in
                                        When(accept.bal >= current.balMaxKnown && accept.bal > current.insts[accept.slot].voted.bal)
                                        let vote = Vote.expression(bal: accept.bal, cmd: accept.cmd)
                                        node[replica].set(Node.expression(leader: Value.second(accept.src), kvalue: current.kvalue,
                                            commitUpTo: current.commitUpTo, balPrepared: current.balPrepared, balMaxKnown: accept.bal,
                                            insts: SequenceMapping(length: slots) { i in
                                                If(i == accept.slot, then: Slot.expression(status: "Accepting", cmd: accept.cmd, voted: vote),
                                                   else: current.insts[i])
                                            }))
                                        messages.insert(Message.second(PhaseTwo.second(Confirmation.first(AcceptReply.expression(
                                            type: "AcceptReply", src: replica, bal: accept.bal, slot: accept.slot)))))
                                    }
                                }
                                When(current.commitUpTo < slots) {
                                    Let(current.commitUpTo + 1) { index in
                                        let slot = current.insts[index]
                                        When(slot.status == "Accepting")
                                        let notice = Message.second(PhaseTwo.second(Confirmation.second(
                                            CommitNotice.expression(type: "CommitNotice", upto: index))))
                                        Either {
                                            When(current.leader == Value.second(replica) && current.balPrepared == current.balMaxKnown) {
                                                let replies = replicas.filter { source in
                                                    messages.contains(Message.second(PhaseTwo.second(Confirmation.first(AcceptReply.expression(
                                                        type: "AcceptReply", src: source, bal: current.balPrepared, slot: index)))))
                                                }
                                                When(replies.count >= replicas.count / 2 + 1)
                                                let ack = Event.second(Ack.expression(type: "Ack", cmd: slot.cmd.assuming(Atom.self),
                                                    val: current.kvalue))
                                                If(!observed.contains(ack)) { observed.set(observed.appending(ack)) }
                                                pending.set(pending.selecting { command in Value.second(command) != slot.cmd })
                                                messages.insert(notice)
                                            }
                                            When(current.leader != Value.second(replica)) {
                                                When(messages.contains(notice))
                                            }
                                        }
                                        let committed = Slot.expression(status: "Committed", cmd: slot.cmd, voted: slot.voted)
                                        node[replica].set(Node.expression(leader: current.leader,
                                            kvalue: If(writes.contains { w in Value.second(w) == slot.cmd }, then: slot.cmd, else: current.kvalue),
                                            commitUpTo: index, balPrepared: current.balPrepared, balMaxKnown: current.balMaxKnown,
                                            insts: SequenceMapping(length: slots) { i in If(i == index, then: committed, else: current.insts[i]) }))
                                    }
                                }
                            }
                            Goto(Step.rloop)
                        }
                    }
                }
                let positions = IntRange(1, through: slots)
                let ballotRange = IntRange(0, through: maxBallot)
                typeOK {
                    let validNodes = replicas.allSatisfy { r in
                        let n = node[r]
                        return validLeaders.contains(n.leader) && validValues.contains(n.kvalue)
                            && IntRange(0, through: slots).contains(n.commitUpTo)
                            && ballotRange.contains(n.balPrepared) && ballotRange.contains(n.balMaxKnown)
                            && n.insts.count == slots && n.insts.allSatisfy { slot in
                                Set<String>(["Empty", "Preparing", "Accepting", "Committed"]).contains(slot.status)
                                    && validCommands.contains(slot.cmd) && ballotRange.contains(slot.voted.bal)
                                    && validCommands.contains(slot.voted.cmd)
                            }
                    }
                    let ballots = IntRange(1, through: maxBallot)
                    let validMessages = messages.allSatisfy { m in
                        let keys = m.recordFields
                        let prepare = m.assuming(Prepare.self)
                        let reply = m.assuming(PrepareReply.self)
                        let accept = m.assuming(Accept.self)
                        let accepted = m.assuming(AcceptReply.self)
                        let notice = m.assuming(CommitNotice.self)
                        let isPrepare = (keys == Set<String>(["type", "src", "bal"])
                                && prepare.type == "Prepare" && replicas.contains(prepare.src) && ballots.contains(prepare.bal))
                        let isPrepareReply = (keys == Set<String>(["type", "src", "bal", "votes"]) && reply.type == "PrepareReply"
                                && replicas.contains(reply.src) && ballots.contains(reply.bal) && reply.votes.count == slots
                                && reply.votes.allSatisfy { v in ballotRange.contains(v.bal) && validCommands.contains(v.cmd) })
                        let isAccept = (keys == Set<String>(["type", "src", "bal", "slot", "cmd"]) && accept.type == "Accept"
                                && replicas.contains(accept.src) && ballots.contains(accept.bal) && positions.contains(accept.slot)
                                && commands.contains { c in Value.second(c) == accept.cmd })
                        let isAcceptReply = (keys == Set<String>(["type", "src", "bal", "slot"]) && accepted.type == "AcceptReply"
                                && replicas.contains(accepted.src) && ballots.contains(accepted.bal) && positions.contains(accepted.slot))
                        let isCommitNotice = (keys == Set<String>(["type", "upto"]) && notice.type == "CommitNotice" && positions.contains(notice.upto))
                        return isPrepare || isPrepareReply || isAccept || isAcceptReply || isCommitNotice
                    }
                    let pendingValues = IntRange(1, through: pending.count).mapping { i in pending[i] }
                    let validEvents = events.allSatisfy { event in
                        let req = event.assuming(Request.self)
                        let ack = event.assuming(Ack.self)
                        return (event.recordFields == Set<String>(["type", "cmd"]) && req.type == "Req" && commands.contains(req.cmd))
                            || (event.recordFields == Set<String>(["type", "cmd", "val"]) && ack.type == "Ack"
                                && commands.contains(ack.cmd) && validValues.contains(ack.val))
                    }
                    validMessages && validNodes && pending.count <= slots && pendingValues.count == pending.count
                        && pendingValues.isSubset(of: commands) && observed.count <= 2 * slots && events.count == observed.count
                        && requested.count >= acknowledged.count && validEvents
                }
                linearizability {
                    let orders = Sequences(of: commands, lengths: IntRange(slots, through: slots))
                    !terminated || orders.contains { order in
                        let covers = positions.mapping { j in order[j] } == commands
                        let linear = positions.allSatisfy { j in
                            let ackIndex = Select(from: eventPositions) { i in
                                observed[i].recordFields == Set<String>(["type", "cmd", "val"])
                                    && observed[i].assuming(Ack.self).type == "Ack"
                                    && observed[i].assuming(Ack.self).cmd == order[j]
                            }
                            let lastWrite = Select(from: IntRange(0, through: j - 1)) { k in
                                (k == 0 || writes.contains(order[k])) && IntRange(k + 1, through: j - 1).allSatisfy { l in reads.contains(order[l]) }
                            }
                            let result = observed[ackIndex].assuming(Ack.self).val
                            return (lastWrite == 0 && result == noValue) || (lastWrite > 0 && result == Value.second(order[lastWrite]))
                        }
                        let realTime = positions.allSatisfy { later in
                            IntRange(1, through: later).allSatisfy { earlier in
                                let ackIndex = Select(from: eventPositions) { i in
                                    observed[i].recordFields == Set<String>(["type", "cmd", "val"])
                                        && observed[i].assuming(Ack.self).type == "Ack"
                                    && observed[i].assuming(Ack.self).cmd == order[later]
                                }
                                let reqIndex = Select(from: eventPositions) { i in
                                    observed[i] == Event.first(Request.expression(type: "Req", cmd: order[earlier]))
                                }
                                return ackIndex >= reqIndex
                            }
                        }
                        return covers && linear && realTime
                    }
                }
            }
            Validation("Small") {
                Bind(replicas, to: Set<Atom>([.s1, .s2, .s3]))
                Bind(writes, to: Set<Atom>([.w1]))
                Bind(reads, to: Set<Atom>([.r1]))
                Bind(maxBallot, to: 2)
            }.usingSymmetry(replicaSymmetry)
        }
    }
}
