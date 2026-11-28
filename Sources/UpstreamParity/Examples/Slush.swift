// Nodes sample their peers and change color when enough replies agree.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SlushProtocol/Slush.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct SlushModel: Sendable {
    package enum ID: String, CaseIterable, FiniteTLAValueDomain {
        case n1, n2, n3, n4, l1, l2, l3, l4, q1, q2, q3, q4
        case client = "ClientRequest"
        package static var defaultValue: Self { .n1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue {
            switch self {
            case .client: .string(rawValue)
            case .n1, .n2, .n3, .n4, .l1, .l2, .l3, .l4, .q1, .q2, .q3, .q4: .constant(rawValue)
            }
        }
    }

    package enum Color: String, CaseIterable, FiniteTLAValueDomain {
        case red = "Red", blue = "Blue", none = "NoColor"
        package static var defaultValue: Self { .none }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue {
            switch self {
            case .red, .blue: .string(rawValue)
            case .none: .constant(rawValue)
            }
        }
    }

    package enum MissingMessage: String, CaseIterable, FiniteTLAValueDomain {
        case none = "NoMessage"
        package static var defaultValue: Self { .none }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum MessageKind: String, CaseIterable, FiniteTLAValueDomain {
        case query = "QueryMessageType", reply = "QueryReplyMessageType", termination = "TerminationMessageType"
        package static var defaultValue: Self { .query }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .string(rawValue) }
    }

    package struct Exchange: Hashable, Sendable {
        package let type: MessageKind
        package let src: ID
        package let dst: ID
        package let color: Color
    }

    package struct Termination: Hashable, Sendable {
        package let type: MessageKind
        package let pid: ID
    }

    package typealias Message = OneOf<Exchange, Termination>

    private enum Step: String, CaseIterable {
        case queryLoop = "QueryReplyLoop", wait = "WaitForQueryMessageOrTermination"
        case respond = "RespondToQueryMessage", requireColor = "RequireColorAssignment"
        case execute = "ExecuteSlushLoop", sample = "QuerySampleSet", tally = "TallyQueryReplies"
        case terminate = "SlushLoopTermination", clientLoop = "ClientRequestLoop", assign = "AssignColorToNode"
    }

    package static var spec: TLASpec {
        #spec("Slush") { scope in
            let SlushIterationCount = scope.parameter(as: Int.self, in: Int.all)
            let SampleSetSize = scope.parameter(as: Int.self, in: Int.all)
            let PickFlipThreshold = scope.parameter(as: Int.self, in: Int.all)
            let Node = scope.parameter(as: Set<ID>.self, in: Subsets(of: Set<ID>([.n1, .n2, .n3, .n4])))
            let SlushLoopProcess = scope.parameter(as: Set<ID>.self, in: Subsets(of: Set<ID>([.l1, .l2, .l3, .l4])))
            let SlushQueryProcess = scope.parameter(as: Set<ID>.self, in: Subsets(of: Set<ID>([.q1, .q2, .q3, .q4])))
            let HostMapping = scope.parameter(as: Set<Set<ID>>.self, in: Set<Set<Set<ID>>>([
                Set<Set<ID>>([[ID.n1, ID.l1, ID.q1], [ID.n2, ID.l2, ID.q2], [ID.n3, ID.l3, ID.q3]])
            ]))
            let NoColor = scope.parameter(as: Color.self, in: Set<Color>([.none]))
            let NoMessage = scope.parameter(as: MissingMessage.self, in: Set<MissingMessage>([.none]))
            Assume(Node.count == SlushLoopProcess.count && Node.count == SlushQueryProcess.count)
            Assume(SlushIterationCount >= 0 && SampleSetSize >= 0 && PickFlipThreshold >= 0)
            let HostMappingType = Node.count == HostMapping.count && HostMapping.allSatisfy { group in
                group.count == 3 && group.contains { member in Node.contains(member) }
                    && group.contains { member in SlushLoopProcess.contains(member) }
                    && group.contains { member in SlushQueryProcess.contains(member) }
            }
            Assume(HostMappingType)
            let hostOf = Dictionary<ID, ID>.mapping(over: SlushLoopProcess.union(SlushQueryProcess)) { pid in
                Select(from: Node) { node in HostMapping.contains { group in group.contains(node) && group.contains(pid) } }
            }
            let colors = SetExpr<Color>.literal(.red, .blue)
            let finished = SlushLoopProcess.mapping { pid in
                Message.second(Termination.expression(type: MessageKind.termination, pid: pid))
            }
            let typeInvariant = Invariant("TypeInvariant")

            Algorithm("Slush") { scope in
                let pick = scope.sharedVar(initial: Dictionary<ID, Color>.mapping(over: Node) { _ in NoColor })
                let message = scope.sharedVar(initial: Set<Message>())
                let envelopes = message.filter { m in m.recordFields == Set<String>(["type", "src", "dst", "color"]) }

                Each(SlushQueryProcess) { pid in
                    let requests = envelopes.filter { m in m.assuming(Exchange.self).type == MessageKind.query && m.assuming(Exchange.self).dst == pid }
                    Do(Step.queryLoop) {
                        If(message == finished) { Stop() } else: { Goto(Step.wait) }
                    }
                    Do(Step.wait) {
                        When(!requests.isEmpty || message == finished)
                        If(message == finished) { Goto(Step.queryLoop) } else: { Goto(Step.respond) }
                    }
                    Do(Step.respond) {
                        With(requests) { envelope in
                            let msg = envelope.assuming(Exchange.self)
                            Let(If(pick[hostOf[pid]] == NoColor, then: msg.color, else: pick[hostOf[pid]])) { color in
                                pick[hostOf[pid]].set(color)
                                message.remove(envelope)
                                message.insert(Message.first(Exchange.expression(type: MessageKind.reply, src: pid, dst: msg.src, color: color)))
                            }
                        }
                        Goto(Step.queryLoop)
                    }
                }

                Each(SlushLoopProcess) { pid, scope in
                    let sampleSet = scope.localVar(initial: Set<ID>())
                    let loopVariant = scope.localVar(initial: 0)
                    let replyEnvelopes = envelopes.filter { m in
                        m.assuming(Exchange.self).type == MessageKind.reply && m.assuming(Exchange.self).dst == pid && sampleSet.contains(m.assuming(Exchange.self).src)
                    }
                    Do(Step.requireColor) {
                        When(pick[hostOf[pid]] != NoColor)
                    }
                    Do(Step.execute) {
                        If(loopVariant < SlushIterationCount) { Goto(Step.sample) } else: { Goto(Step.terminate) }
                    }
                    Do(Step.sample) {
                        let others = SlushQueryProcess.filter { other in hostOf[other] != hostOf[pid] }
                        With(Subsets(of: others).filter { group in group.count == SampleSetSize }) { group in
                            sampleSet.set(group)
                            message.set(message.union(group.mapping { dst in
                                Message.first(Exchange.expression(type: MessageKind.query, src: pid, dst: dst, color: pick[hostOf[pid]]))
                            }))
                        }
                    }
                    Do(Step.tally) {
                        Let(replyEnvelopes) { received in
                            let replies = received.mapping { m in m.assuming(Exchange.self) }
                            When(sampleSet.allSatisfy { src in replies.contains { m in m.src == src } })
                            If(replies.filter { m in m.color == Color.red }.count >= PickFlipThreshold) {
                                pick[hostOf[pid]].set(Color.red)
                            } else: {
                                If(replies.filter { m in m.color == Color.blue }.count >= PickFlipThreshold) {
                                    pick[hostOf[pid]].set(Color.blue)
                                }
                            }
                            message.set(message.subtracting(received))
                        }
                        sampleSet.set(Set<ID>())
                        loopVariant += 1
                        Goto(Step.execute)
                    }
                    Do(Step.terminate) {
                        message.insert(Message.second(Termination.expression(type: MessageKind.termination, pid: pid)))
                        Stop()
                    }
                }

                Process(id: ID.client) {
                    Do(Step.clientLoop) {
                        If(Node.contains { node in pick[node] == NoColor }) { Goto(Step.assign) } else: { Stop() }
                    }
                    Do(Step.assign) {
                        With(Node, colors) { node, color in
                            If(pick[node] == NoColor) { pick[node].set(color) }
                        }
                        Goto(Step.clientLoop)
                    }
                }

                typeInvariant {
                    Functions(from: Node, to: colors.inserting(NoColor)).contains(pick)
                    message.allSatisfy { m in
                        finished.contains(m) || (envelopes.contains(m) && colors.contains(m.assuming(Exchange.self).color) &&
                            ((m.assuming(Exchange.self).type == MessageKind.query && SlushLoopProcess.contains(m.assuming(Exchange.self).src) && SlushQueryProcess.contains(m.assuming(Exchange.self).dst)) ||
                             (m.assuming(Exchange.self).type == MessageKind.reply && SlushQueryProcess.contains(m.assuming(Exchange.self).src) && SlushLoopProcess.contains(m.assuming(Exchange.self).dst))))
                    }
                }
            }
            Validation("SlushSmall") {
                Bind(Node, to: Set<ID>([.n1, .n2, .n3]))
                Bind(SlushLoopProcess, to: Set<ID>([.l1, .l2, .l3]))
                Bind(SlushQueryProcess, to: Set<ID>([.q1, .q2, .q3]))
                Bind(HostMapping, to: Set<Set<ID>>([[.n1, .l1, .q1], [.n2, .l2, .q2], [.n3, .l3, .q3]]))
                Bind(NoColor, to: Color.none)
                Bind(NoMessage, to: MissingMessage.none)
                Bind(SlushIterationCount, to: 1)
                Bind(SampleSetSize, to: 2)
                Bind(PickFlipThreshold, to: 2)
            }
            Validation("SlushMedium") {
                Bind(Node, to: Set<ID>([.n1, .n2, .n3]))
                Bind(SlushLoopProcess, to: Set<ID>([.l1, .l2, .l3]))
                Bind(SlushQueryProcess, to: Set<ID>([.q1, .q2, .q3]))
                Bind(HostMapping, to: Set<Set<ID>>([[.n1, .l1, .q1], [.n2, .l2, .q2], [.n3, .l3, .q3]]))
                Bind(NoColor, to: Color.none)
                Bind(NoMessage, to: MissingMessage.none)
                Bind(SlushIterationCount, to: 4)
                Bind(SampleSetSize, to: 1)
                Bind(PickFlipThreshold, to: 1)
            }
        }
    }
}
