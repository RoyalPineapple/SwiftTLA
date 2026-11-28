// Nodes elect the smallest identity by sending values downstream and replies upstream.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/YoYo/YoYoNoPruning.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct YoYoNoPruningModel: Sendable {
    package struct Down: Hashable, Sendable {
        package let phase: String
        package let sndr: Int
        package let val: Int
    }
    package struct Up: Hashable, Sendable {
        package let phase: String
        package let sndr: Int
        package let reply: String

    }
    package typealias Message = OneOf<Down, Up>
    private enum Step: String, CaseIterable { case downSource = "DownSource", downOther = "DownOther", upSource = "UpSource", upOther = "UpOther" }

    package static var spec: TLASpec {
        #spec("MCYoYoNoPruning") { scope in
            let nodes = IntRange(1, through: 5)
            let edges = Set<Set<Int>>([[1, 2], [1, 5], [3, 4], [3, 5], [4, 5]])
            let neighbors = Dictionary<Int, Set<Int>>.mapping(over: nodes) { n in
                nodes.filter { m in edges.contains(Set<Int>().inserting(n).inserting(m)) }
            }
            let phase = scope.sharedVar(initial: Dictionary<Int, String>.mapping(over: nodes) { _ in "down" })
            let incoming = scope.sharedVar(initial: Dictionary<Int, Set<Int>>.mapping(over: nodes) { n in neighbors[n].filter { m in m < n } })
            let outgoing = scope.sharedVar(initial: Dictionary<Int, Set<Int>>.mapping(over: nodes) { n in neighbors[n].filter { m in m > n } })
            let mailbox = scope.sharedVar(initial: Dictionary<Int, Set<Message>>.mapping(over: nodes) { _ in Set<Message>() })

            FormalDefinition("Sender", taking: Message.self) { msg -> Expr<Int> in
                If(msg.recordFields.contains("val"), then: msg.assuming(Down.self).sndr, else: msg.assuming(Up.self).sndr)
            }
            FormalDefinition("Minimum", taking: Set<Int>.self) { values -> Expr<Int> in
                Select(from: values) { x in values.allSatisfy { y in x <= y } }
            }
            Do(Step.downSource, over: nodes) { n in
                When(phase[n] == "down")
                When(incoming[n].isEmpty)
                let msg = Message.first(Down.expression(phase: "down", sndr: n, val: n))
                mailbox.set(Dictionary<Int, Set<Message>>.mapping(over: nodes) { m in
                    If(outgoing[n].contains(m), then: mailbox[m].inserting(msg), else: mailbox[m])
                })
                phase[n].set("up")
            }
            Do(Step.downOther, over: nodes) { n in
                When(phase[n] == "down")
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
            Do(Step.upSource, over: nodes) { n in
                When(phase[n] == "up")
                When(incoming[n].isEmpty)
                let upMsgs = mailbox[n].filter { msg in msg.recordFields.contains("reply") }
                let rejected = upMsgs.filter { msg in msg.assuming(Up.self).reply == "no" }.mapping { msg in msg.assuming(Up.self).sndr }
                When(upMsgs.mapping { msg in msg.assuming(Up.self).sndr } == outgoing[n])

                Let(rejected) { no in
                    outgoing[n].set(outgoing[n].subtracting(no))
                    incoming[n].set(no)
                    mailbox[n].set(mailbox[n].subtracting(upMsgs))
                }
                phase[n].set("down")
            }
            Do(Step.upOther, over: nodes) { n in
                When(phase[n] == "up")
                When(!incoming[n].isEmpty)
                let upMsgs = mailbox[n].filter { msg in msg.recordFields.contains("reply") }
                let rejected = upMsgs.filter { msg in msg.assuming(Up.self).reply == "no" }.mapping { msg in msg.assuming(Up.self).sndr }
                When(upMsgs.mapping { msg in msg.assuming(Up.self).sndr } == outgoing[n])

                let downMsgs = mailbox[n].filter { msg in
                    msg.recordFields.contains("val") && incoming[n].contains(FormalCall(as: Int.self, "Sender", msg))
                }
                let values = downMsgs.mapping { msg in msg.assuming(Down.self).val }
                let minimum = FormalCall(as: Int.self, "Minimum", values)
                let best = downMsgs.filter { msg in msg.assuming(Down.self).val == minimum }.mapping { msg in msg.assuming(Down.self).sndr }
                Let(incoming[n]) { previous in
                    Let(If(rejected.isEmpty, then: best, else: rejected)) { nextIncoming in
                        Let(If(rejected.isEmpty, then: outgoing[n].union(previous.subtracting(best)), else: outgoing[n].subtracting(rejected).union(previous))) { nextOutgoing in
                            mailbox.set(Dictionary<Int, Set<Message>>.mapping(over: nodes) { m in
                                let reply = If(rejected.isEmpty && best.contains(m), then: "yes", else: "no")
                                return If(previous.contains(m),
                                    then: mailbox[m].inserting(Message.second(Up.expression(phase: "up", sndr: n, reply: reply))),
                                    else: If(m == n, then: mailbox[m].subtracting(upMsgs.union(downMsgs)), else: mailbox[m]))
                            })
                            incoming[n].set(nextIncoming)
                            outgoing[n].set(nextOutgoing)
                        }
                    }
                }
                phase[n].set("down")
            }
            WeakFairnessNext()
            let downDomain = nodes.flatMapping { s in nodes.mapping { v in
                Message.first(Down.expression(phase: "down", sndr: s, val: v))
            } }
            let replies = Set<String>(["yes", "no"])
            let upDomain = nodes.flatMapping { s in replies.mapping { r in Message.second(Up.expression(phase: "up", sndr: s, reply: r)) } }
            let messages = downDomain.union(upDomain)
            Invariant("TypeOK") {

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
                    let toM = Message.second(Up.expression(phase: "up", sndr: n, reply: "no"))
                    let toN = Message.second(Up.expression(phase: "up", sndr: m, reply: "no"))
                    return outgoing[n].contains(m) == (incoming[m].contains(n)
                        || (outgoing[m].contains(n) && (mailbox[m].contains(toM) || mailbox[n].contains(toN))))
                } }
            }
            let sources = nodes.filter { n in incoming[n].isEmpty }
            let NoNewSource = Temporal()
            NoNewSource(.alwaysStep(on: sources) { before, after in after.isSubset(of: before) })
            let stable = sources == Set<Int>([1]) && nodes.allSatisfy { n in
                mailbox[n].allSatisfy { msg in If(msg.recordFields.contains("val"),
                    then: msg.assuming(Down.self).val == 1, else: msg.assuming(Up.self).reply == "yes") }
            }
            EventuallyAlways("Liveness", stable)
            Validation("Upstream") {}
        }
    }
}
