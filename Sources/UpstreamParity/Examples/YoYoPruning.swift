// Nodes elect the smallest identity by sending values downstream and replies upstream.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/YoYo/YoYoPruning.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct YoYoPruningModel: Sendable {
    package struct Down: Hashable, Sendable {
        package let phase: String
        package let sndr: Int
        package let val: Int
    }
    package struct Up: Hashable, Sendable {
        package let phase: String
        package let sndr: Int
        package let reply: String
        package let prune: Bool
    }
    package typealias Message = OneOf<Down, Up>
    private enum Step: String, CaseIterable { case downSource = "DownSource", downOther = "DownOther", upSource = "UpSource", upOther = "UpOther" }

    package static var spec: TLASpec {
        #spec("MCYoYoPruning") { scope in
            let nodes = IntRange(1, through: 5)
            let edges = Set<Set<Int>>([[1, 2], [1, 5], [3, 4], [3, 5], [4, 5]])
            let neighbors = Dictionary<Int, Set<Int>>.mapping(over: nodes) { n in
                nodes.filter { m in edges.contains(Set<Int>().inserting(n).inserting(m)) }
            }
            let phase = scope.sharedVar(initial: Dictionary<Int, String>.mapping(over: nodes) { _ in "down" })
            let incoming = scope.sharedVar(initial: Dictionary<Int, Set<Int>>.mapping(over: nodes) { n in neighbors[n].filter { m in m < n } })
            let outgoing = scope.sharedVar(initial: Dictionary<Int, Set<Int>>.mapping(over: nodes) { n in neighbors[n].filter { m in m > n } })
            let mailbox = scope.sharedVar(initial: Dictionary<Int, Set<Message>>.mapping(over: nodes) { _ in Set<Message>() })
            let active = scope.sharedVar(initial: Dictionary<Int, Bool>.mapping(over: nodes) { _ in true })
            FormalDefinition("Sender", taking: Message.self) { msg -> Expr<Int> in
                If(msg.recordFields.contains("val"), then: msg.assuming(Down.self).sndr, else: msg.assuming(Up.self).sndr)
            }
            FormalDefinition("Minimum", taking: Set<Int>.self) { values -> Expr<Int> in
                Select(from: values) { x in values.allSatisfy { y in x <= y } }
            }
            let downSource = Do(Step.downSource, over: nodes) { n in
                When(active[n] && phase[n] == "down")
                When(incoming[n].isEmpty && !outgoing[n].isEmpty)
                let msg = Message.first(Down.expression(phase: "down", sndr: n, val: n))
                mailbox.set(Dictionary<Int, Set<Message>>.mapping(over: nodes) { m in
                    If(outgoing[n].contains(m), then: mailbox[m].inserting(msg), else: mailbox[m])
                })
                phase[n].set("up")
            }
            let downOther = Do(Step.downOther, over: nodes) { n in
                When(active[n] && phase[n] == "down")
                When(!incoming[n].isEmpty)
                let downMsgs = mailbox[n].filter { msg in msg.recordFields.contains("val") }
                When(downMsgs.mapping { msg in msg.assuming(Down.self).sndr } == incoming[n])
                let value = FormalCall(as: Int.self, "Minimum", downMsgs.mapping { msg in msg.assuming(Down.self).val })
                let msg = Message.first(Down.expression(phase: "down", sndr: n, val: value))
                mailbox.set(Dictionary<Int, Set<Message>>.mapping(over: nodes) { m in
                    If(outgoing[n].contains(m), then: mailbox[m].inserting(msg), else: mailbox[m])
                })
                phase[n].set("up")
            }
            let upSource = Do(Step.upSource, over: nodes) { n in
                When(active[n] && phase[n] == "up")
                When(incoming[n].isEmpty && !outgoing[n].isEmpty)
                let upMsgs = mailbox[n].filter { msg in msg.recordFields.contains("reply") }
                let rejected = upMsgs.filter { msg in msg.assuming(Up.self).reply == "no" }.mapping { msg in msg.assuming(Up.self).sndr }
                When(upMsgs.mapping { msg in msg.assuming(Up.self).sndr } == outgoing[n])
                let pruned = upMsgs.filter { msg in msg.assuming(Up.self).prune }.mapping { msg in msg.assuming(Up.self).sndr }
                Let(rejected) { no in
                    outgoing[n].set(outgoing[n].subtracting(no.union(pruned)))
                    incoming[n].set(no.subtracting(pruned))
                    mailbox[n].set(mailbox[n].subtracting(upMsgs))
                }
                phase[n].set("down")
            }
            let upOther = Do(Step.upOther, over: nodes) { n in
                When(active[n] && phase[n] == "up")
                When(!incoming[n].isEmpty)
                let upMsgs = mailbox[n].filter { msg in msg.recordFields.contains("reply") }
                let rejected = upMsgs.filter { msg in msg.assuming(Up.self).reply == "no" }.mapping { msg in msg.assuming(Up.self).sndr }
                When(upMsgs.mapping { msg in msg.assuming(Up.self).sndr } == outgoing[n])
                let pruned = upMsgs.filter { msg in msg.assuming(Up.self).prune }.mapping { msg in msg.assuming(Up.self).sndr }
                let downMsgs = mailbox[n].filter { msg in
                    msg.recordFields.contains("val") && incoming[n].contains(FormalCall(as: Int.self, "Sender", msg))
                }
                let values = downMsgs.mapping { msg in msg.assuming(Down.self).val }
                let minimum = FormalCall(as: Int.self, "Minimum", values)
                let best = downMsgs.filter { msg in msg.assuming(Down.self).val == minimum }.mapping { msg in msg.assuming(Down.self).sndr }
                let lone = outgoing[n].isEmpty && incoming[n].count == 1
                let choices = Functions(from: values, to: incoming[n]).filter { keep in
                    values.allSatisfy { v in downMsgs.contains(Message.first(Down.expression(phase: "down", sndr: keep[v], val: v))) }
                }
                With(choices) { keep in
                    Let(lone) { wasLone in
                        Let(incoming[n]) { previous in
                            Let(If(rejected.isEmpty, then: If(wasLone, then: Set<Int>(), else: Set<Int>().inserting(keep[minimum])), else: rejected.subtracting(pruned))) { nextIncoming in
                                Let(If(rejected.isEmpty, then: outgoing[n].subtracting(pruned).union(values.removing(minimum).mapping { v in keep[v] }), else: outgoing[n].subtracting(rejected.union(pruned)).union(values.mapping { v in keep[v] }))) { nextOutgoing in
                                    mailbox.set(Dictionary<Int, Set<Message>>.mapping(over: nodes) { m in
                                        let reply = If(rejected.isEmpty && best.contains(m), then: "yes", else: "no")
                                        return If(previous.contains(m),
                                            then: mailbox[m].inserting(Message.second(Up.expression(phase: "up", sndr: n, reply: reply, prune: (rejected.isEmpty && wasLone) || m != keep[Select(from: downMsgs) { msg in msg.assuming(Down.self).sndr == m }.assuming(Down.self).val]))),
                                            else: If(m == n, then: mailbox[m].subtracting(upMsgs.union(downMsgs)), else: mailbox[m]))
                                    })
                                    incoming[n].set(nextIncoming)
                                    outgoing[n].set(nextOutgoing)
                                }
                            }
                        }
                        active[n].set(!wasLone)
                    }
                }
                phase[n].set("down")
            }
            WeakFairnessNext()
            let downDomain = nodes.flatMapping { s in nodes.mapping { v in
                Message.first(Down.expression(phase: "down", sndr: s, val: v))
            } }
            let replies = Set<String>(["yes", "no"])
            let upDomain = nodes.flatMapping { s in replies.flatMapping { r in Set<Bool>([true, false]).mapping { b in Message.second(Up.expression(phase: "up", sndr: s, reply: r, prune: b)) } } }
            let messages = downDomain.union(upDomain)
            Invariant("TypeOK") {
                active.keys == nodes
                phase.keys == nodes && incoming.keys == nodes && outgoing.keys == nodes && mailbox.keys == nodes
                nodes.allSatisfy { n in
                    Set<String>(["down", "up"]).contains(phase[n]) && incoming[n].isSubset(of: neighbors[n])
                        && outgoing[n].isSubset(of: neighbors[n]) && mailbox[n].isSubset(of: messages)
                        && mailbox[n].allSatisfy { msg in
                            let sender = FormalCall(as: Int.self, "Sender", msg)
                            let down = msg.recordFields.contains("val")
                            return If(down, then: outgoing[sender].contains(n), else: outgoing[n].contains(sender))
                                && mailbox[n].allSatisfy { other in
                                    other.recordFields.contains("val") != down || FormalCall(as: Int.self, "Sender", other) != sender || other == msg
                                }
                        }
                }
            }
            Invariant("NeighborInv") {
                nodes.allSatisfy { n in nodes.allSatisfy { m in
                    let toM = Message.second(Up.expression(phase: "up", sndr: n, reply: "no", prune: false))
                    let toN = Message.second(Up.expression(phase: "up", sndr: m, reply: "no", prune: false))
                    return outgoing[n].contains(m) == (incoming[m].contains(n)
                        || (outgoing[m].contains(n) && (mailbox[m].contains(toM) || mailbox[n].contains(toN)))
                        || (!incoming[m].contains(n) && !outgoing[m].contains(n) && replies.contains { r in mailbox[n].contains(Message.second(Up.expression(phase: "up", sndr: m, reply: r, prune: true))) }))
                } }
            }
            let terminated = nodes.allSatisfy { n in
                If(n == 1, then: incoming[n].isEmpty && outgoing[n].isEmpty, else: !active[n]) && mailbox[n].isEmpty
            }
            let enabled = nodes.contains { n in downSource.isEnabled(for: n) || downOther.isEnabled(for: n)
                    || upSource.isEnabled(for: n) || upOther.isEnabled(for: n) }
            Invariant("FinishIffTerminated") { !enabled == terminated }
            Eventually("Liveness", terminated)
            Validation("Upstream") {}.checkingDeadlock(false)
        }
    }
}
