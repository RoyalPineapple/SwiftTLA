// TCP connection establishment, close, and reset between two peers with independent message queues.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/tcp/tcp.tla
import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct TCPModel: Sendable {
    package enum Peer: String, CaseIterable, FiniteTLAValueDomain {
        case a = "A", b = "B"
        package static let finiteValues = allCases
        package static var defaultValue: Self { .a }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    private enum Step: String, CaseIterable {
        case passiveOpen = "PASSIVE_OPEN", activeOpen = "ACTIVE_OPEN", send = "SEND"
        case closeSynSent = "CLOSE_SYN_SENT", closeSynReceived = "CLOSE_SYN_RECEIVED"
        case closeListen = "CLOSE_LISTEN", closeEstablished = "CLOSE_ESTABLISHED", closeCloseWait = "CLOSE_CLOSE_WAIT"
        case synSent = "SynSent", synReceived = "SynReceived", listen = "Listen", established = "Established"
        case finWait1 = "FinWait1", finWait2 = "FinWait2", closing = "Closing", lastAck = "LastAck"
        case timeWait = "TimeWait", note2 = "Note2", note3 = "Note3"
    }
    package static var spec: TLASpec {
        #spec("MCtcp") { scope in
            Extends(.integers, .sequences)
            let peers = scope.parameter(tlaName: "Peers", as: Set<Peer>.self, in: Set<Set<Peer>>([Set<Peer>([.a, .b])]))
            Assume(peers.count == 2)
            let tcb = scope.sharedVar(initial: Dictionary<Peer, Bool>.mapping(over: peers) { _ in true })
            let initialStates = peers.mapping { initiator in
                Dictionary<Peer, String>.mapping(over: peers) { p in If(p == initiator, then: "SYN-SENT", else: "LISTEN") }
            }
            let connstate = scope.sharedVar(initiallyIn: initialStates)
            let network = scope.sharedVar(initial: Dictionary<Peer, [String]>.mapping(over: peers) { p in
                If(connstate[p] == "SYN-SENT", then: [String](), else: ["SYN"])
            })

            Do(Step.passiveOpen, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "CLOSED")
                connstate[local].set("LISTEN")
                tcb[local].set(true)
            }

            Do(Step.activeOpen, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "CLOSED")
                network[remote].set(network[remote].appending("SYN"))
                connstate[local].set("SYN-SENT")
                tcb[local].set(true)
            }

            let closeSynSent = Do(Step.closeSynSent, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "SYN-SENT")
                connstate[local].set("CLOSED")
                tcb[local].set(false)
            }

            Do(Step.closeSynReceived, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "SYN-RECEIVED")
                network[remote].set(network[remote].appending("FIN"))
                connstate[local].set("FIN-WAIT-1")
            }

            Do(Step.send, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "LISTEN")
                network[remote].set(network[remote].appending("SYN"))
                connstate[local].set("SYN-SENT")
            }

            Do(Step.closeListen, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "LISTEN")
                connstate[local].set("CLOSED")
                tcb[local].set(false)
            }

            Do(Step.closeEstablished, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "ESTABLISHED")
                network[remote].set(network[remote].appending("FIN"))
                connstate[local].set("FIN-WAIT-1")
            }

            Do(Step.closeCloseWait, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "CLOSE-WAIT")
                network[remote].set(network[remote].appending("FIN"))
                connstate[local].set("LAST-ACK")
            }

            let synSent = Do(Step.synSent, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "SYN-SENT" && !network[local].isEmpty)
                Either {
                    When(network[local].head() == "SYN")
                    network[local].set(network[local].tail())
                    network[remote].set(network[remote].appending("SYN,ACK"))
                    connstate[local].set("SYN-RECEIVED")
                } or: {
                    When(network[local].head() == "SYN,ACK")
                    network[local].set(network[local].tail())
                    network[remote].set(network[remote].appending("ACK"))
                    connstate[local].set("ESTABLISHED")
                }
            }

            let synReceived = Do(Step.synReceived, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "SYN-RECEIVED" && !network[local].isEmpty)
                Either {
                    When(network[local].head() == "RST")
                    network[local].set(network[local].tail())
                    connstate[local].set("LISTEN")
                } or: {
                    When(network[local].head() == "ACK")
                    network[local].set(network[local].tail())
                    connstate[local].set("ESTABLISHED")
                }
            }

            let listen = Do(Step.listen, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "LISTEN" && !network[local].isEmpty)
                When(network[local].head() == "SYN")
                network[local].set(network[local].tail())
                network[remote].set(network[remote].appending("SYN,ACK"))
                connstate[local].set("SYN-RECEIVED")
            }

            let established = Do(Step.established, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "ESTABLISHED" && !network[local].isEmpty)
                When(network[local].head() == "FIN")
                network[local].set(network[local].tail())
                network[remote].set(network[remote].appending("ACKofFIN"))
                connstate[local].set("CLOSE-WAIT")
            }

            let finWait1 = Do(Step.finWait1, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "FIN-WAIT-1" && !network[local].isEmpty)
                Either {
                    When(network[local].head() == "FIN")
                    network[local].set(network[local].tail())
                    network[remote].set(network[remote].appending("ACKofFIN"))
                    connstate[local].set("CLOSING")
                } or: {
                    When(network[local].head() == "ACKofFIN")
                    network[local].set(network[local].tail())
                    connstate[local].set("FIN-WAIT-2")
                }
            }

            let finWait2 = Do(Step.finWait2, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "FIN-WAIT-2" && !network[local].isEmpty)
                When(network[local].head() == "FIN")
                network[local].set(network[local].tail())
                network[remote].set(network[remote].appending("ACKofFIN"))
                connstate[local].set("TIME-WAIT")
            }

            let closing = Do(Step.closing, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "CLOSING" && !network[local].isEmpty)
                When(network[local].head() == "ACKofFIN")
                network[local].set(network[local].tail())
                connstate[local].set("TIME-WAIT")
            }

            let lastAck = Do(Step.lastAck, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "LAST-ACK" && !network[local].isEmpty)
                When(network[local].head() == "ACKofFIN")
                network[local].set(network[local].tail())
                connstate[local].set("CLOSED")
            }

            let timeWait = Do(Step.timeWait, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "TIME-WAIT" && tcb[local])
                connstate[local].set("CLOSED")
                tcb[local].set(false)
            }
            let note2 = Do(Step.note2, over: peers, peers) { local, remote in
                When(local != remote && connstate[local] == "FIN-WAIT-1")
                When(network[local].count >= 2 && network[local][1] == "FIN" && network[local][2] == "ACKofFIN")
                network[local].set(network[local].tail().tail())
                network[remote].set(network[remote].appending("ACKofFIN"))
                connstate[local].set("TIME-WAIT")
            }
            Do(Step.note3, over: peers, peers) { local, remote in
                When(local != remote)
                Either {
                    When(tcb[local])
                    network[remote].set(network[remote].appending("RST"))
                    connstate[local].set("TIME-WAIT")
                } or: {
                    When(!network[local].isEmpty && network[local].head() == "RST")
                    network[local].set(network[local].tail())
                    With(Set<String>(["LISTEN", "CLOSED"])) { next in connstate[local].set(next) }
                }
            }
            WeakFairness(anyOf: [synSent, synReceived, listen, established, finWait1, finWait2, closing, lastAck, timeWait, note2])
            WeakFairness(closeSynSent)

            let states = Set<String>(["LISTEN", "CLOSED", "SYN-SENT", "SYN-RECEIVED", "ESTABLISHED",
                                      "FIN-WAIT-1", "FIN-WAIT-2", "CLOSING", "CLOSE-WAIT", "LAST-ACK", "TIME-WAIT"])
            let messages = Set<String>(["SYN", "SYN,ACK", "ACK", "RST", "FIN", "ACKofFIN"])
            Invariant("TypeOK") {
                Functions(from: peers, to: Bool.all).contains(tcb)
                    && Functions(from: peers, to: states).contains(connstate)
                    && network.keys == peers && peers.allSatisfy { p in Sequences(of: messages).contains(network[p]) }
            }
            Invariant("Inv") {
                peers.allSatisfy { p in peers.allSatisfy { q in
                    !network[p].isEmpty || !network[q].isEmpty || ((connstate[p] == "ESTABLISHED") == (connstate[q] == "ESTABLISHED"))
                } }
            }
            let Prop = Temporal()
            Prop(forEach: peers) { p in
                .leadsTo(connstate[p] == "SYN-SENT", Set<String>(["ESTABLISHED", "LISTEN", "CLOSED"]).contains(connstate[p]))
            }
            Constraint(peers.allSatisfy { p in
                IntRange(1, through: network[p].count - 1).allSatisfy { i in network[p][i] != network[p][i + 1] }
            })
            // SingleActiveOpen excludes any edge satisfying OPEN or SEND, even when another action produced it.
            ActionConstraint(on: Triple.literal(tcb, connstate, network)) { before, after in
                !peers.contains { local in peers.contains { remote in
                    let remoteUnchanged = after.second()[remote] == before.second()[remote] && after.first()[remote] == before.first()[remote]
                    let opens = before.second()[local] == "CLOSED" && after.first()[local]
                    let passive = opens && after.second()[local] == "LISTEN" && after.third()[remote] == before.third()[remote]
                    let sends = before.second()[local] == "LISTEN" && after.first()[local] == before.first()[local]
                    let active = (opens || sends) && after.second()[local] == "SYN-SENT"
                        && after.third()[remote] == before.third()[remote].appending("SYN")
                    return local != remote && remoteUnchanged && after.third()[local] == before.third()[local] && (passive || active)
                } }
            }
            Validation("Upstream") { Bind(peers, to: Set<Peer>([.a, .b])) }
        }
    }
}
