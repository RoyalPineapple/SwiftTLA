// Processes order requests by Lamport timestamps and acknowledge them over pairwise FIFO links.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/lamport_mutex/LamportMutex.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct LamportDistributedMutexModel: Sendable {
    package struct Message: Hashable, Sendable {
        package let type: String
        package let clock: Int
    }

    private enum Step: String, CaseIterable {
        case request = "Request", receiveRequest = "ReceiveRequest", receiveAck = "ReceiveAck"
        case enter = "Enter", exit = "Exit", receiveRelease = "ReceiveRelease"
    }

    package static var spec: TLASpec {
        #spec("MCLamportMutex") { scope in
            let N = scope.parameter(as: Int.self, in: 1...3)
            let maxClock = scope.parameter(as: Int.self, in: 1...6)
            let MaxNat = scope.parameter(as: Int.self, in: 1...7)
            let processes = IntRange(1, through: N)
            let naturals = IntRange(0, through: MaxNat)
            let timestamps = IntRange(1, through: MaxNat)
            let messages = timestamps.mapping { time in Message.expression(type: "req", clock: time) }
                .inserting(Message.expression(type: "ack", clock: 0))
                .inserting(Message.expression(type: "rel", clock: 0))
            let emptyRequests = Dictionary<Int, Int>.mapping(over: processes) { _ in 0 }
            let emptyLinks = Dictionary<Int, [Message]>.mapping(over: processes) { _ in [Message]() }
            let clock = scope.sharedVar(initial: Dictionary<Int, Int>.mapping(over: processes) { _ in 1 })
            let req = scope.sharedVar(initial: Dictionary<Int, [Int: Int]>.mapping(over: processes) { _ in emptyRequests })
            let ack = scope.sharedVar(initial: Dictionary<Int, Set<Int>>.mapping(over: processes) { _ in Set<Int>() })
            let network = scope.sharedVar(initial: Dictionary<Int, [Int: [Message]]>.mapping(over: processes) { _ in emptyLinks })
            let crit = scope.sharedVar(initial: Set<Int>())
            let broadcast = Macro { (sender: MacroParameter<Int>, message: MacroParameter<Message>) in
                network[sender].set(Dictionary<Int, [Message]>.mapping(over: processes) { recipient in
                    If(sender == recipient, then: network[sender][recipient], else: network[sender][recipient].appending(message))
                })
            }

            Do(Step.request, over: processes) { requester in
                When(req[requester][requester] == 0)
                req[requester].set(req[requester].updating(requester, to: clock[requester]))
                broadcast(requester, Message.expression(type: "req", clock: clock[requester]))
                ack[requester].set(Set<Int>().inserting(requester))
            }
            Do(Step.receiveRequest, over: processes, processes) { receiver, sender in
                When(receiver != sender && !network[sender][receiver].isEmpty)
                Let(network[sender][receiver].head()) { message in
                    When(message.type == "req")
                    req[receiver].set(req[receiver].updating(sender, to: message.clock))
                    clock[receiver].set(If(message.clock > clock[receiver], then: message.clock, else: clock[receiver]) + 1)
                    let incoming = network[sender].updating(receiver, to: network[sender][receiver].tail())
                    let outgoing = network[receiver].updating(sender, to: network[receiver][sender].appending(Message.expression(type: "ack", clock: 0)))
                    network.set(network.updating(sender, to: incoming).updating(receiver, to: outgoing))
                }
            }
            Do(Step.receiveAck, over: processes, processes) { receiver, sender in
                When(receiver != sender && !network[sender][receiver].isEmpty)
                When(network[sender][receiver].head().type == "ack")
                ack[receiver].set(ack[receiver].inserting(sender))
                network[sender].set(network[sender].updating(receiver, to: network[sender][receiver].tail()))
            }
            Do(Step.enter, over: processes) { requester in
                When(ack[requester] == processes)
                When(processes.allSatisfy { peer in
                    peer == requester || req[requester][peer] == 0 || req[requester][requester] < req[requester][peer]
                        || (req[requester][requester] == req[requester][peer] && requester < peer)
                })
                crit.insert(requester)
            }
            Do(Step.exit, over: processes) { requester in
                When(crit.contains(requester))
                crit.remove(requester)
                broadcast(requester, Message.expression(type: "rel", clock: 0))
                req[requester].set(req[requester].updating(requester, to: 0))
                ack[requester].set(Set<Int>())
            }
            Do(Step.receiveRelease, over: processes, processes) { receiver, sender in
                When(receiver != sender && !network[sender][receiver].isEmpty)
                When(network[sender][receiver].head().type == "rel")
                req[receiver].set(req[receiver].updating(sender, to: 0))
                network[sender].set(network[sender].updating(receiver, to: network[sender][receiver].tail()))
            }

            Constraint(processes.allSatisfy { process in clock[process] <= maxClock })
            Invariant("TypeOK") {
                crit.isSubset(of: processes) && clock.keys == processes && req.keys == processes
                    && ack.keys == processes && network.keys == processes
                processes.allSatisfy { sender in
                    timestamps.contains(clock[sender]) && ack[sender].isSubset(of: processes)
                        && req[sender].keys == processes && network[sender].keys == processes
                        && processes.allSatisfy { receiver in
                            naturals.contains(req[sender][receiver]) && IntRange(1, through: network[sender][receiver].count).allSatisfy { position in
                                messages.contains(network[sender][receiver][position])
                            }
                        }
                }
            }
            Invariant("BoundedNetwork") {
                processes.allSatisfy { sender in processes.allSatisfy { receiver in network[sender][receiver].count <= 3 } }
            }
            Invariant("Mutex") { crit.count <= 1 }
            Validation("Upstream") {
                Bind(N, to: 3)
                Bind(maxClock, to: 6)
                Bind(MaxNat, to: 7)
            }
        }
    }
}
