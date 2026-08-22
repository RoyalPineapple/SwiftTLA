import SwiftTLA
import SwiftTLAMacros

/// The bounded three-node Echo spanning-tree algorithm from the upstream
/// TLA+ Examples repository.
///
/// A record is the message on the network. The `inbox` finite function gives
/// every node its own set of messages, while each `Each(Node.all)` body is an
/// independently scheduled PlusCal process.
@TLAModel
public struct EchoModel: Sendable {
    public enum Node: String, TLAValueType, FiniteDomainKey {
        case a, b, c

        public static let formalDomain: [Self] = [.a, .b, .c]
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.echo.node")
        public static var defaultValue: Self { .a }
    }

    public enum MessageKind: String, TLAValueType {
        case message = "m"
        case acknowledgement = "c"

        public static var defaultValue: Self { .message }
    }

    public struct MessageFields {
        public let kind: MessageKind
        public let sender: Node
    }

    public enum MessageSchema: TLARecordSchema {
        public typealias Fields = MessageFields

        public static let fieldNames: Set<String> = ["kind", "sender"]
        public static let defaultRecord: TLAValue = .record([
            "kind": MessageKind.message.tlaValue,
            "sender": Node.a.tlaValue
        ])

        public static func fieldName<Value>(for field: KeyPath<MessageFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \MessageFields.kind { return "kind" }
            if key == \MessageFields.sender { return "sender" }
            return nil
        }

        public static let kind = field(\MessageFields.kind)
        public static let sender = field(\MessageFields.sender)
    }

    private enum Step: String, PlusCalLabel, CaseIterable {
        case n0, n1, n2
    }

    public static var spec: TLASpec {
        #spec("Echo") {
            Extends(.finiteSets)
            Algorithm("Echo", scoped: { scope in
                let inbox = scope.sharedVar("inbox", initial: Function<Node, SetExpr<Record<MessageSchema>>>.literal(
                    (.a, SetExpr<Record<MessageSchema>>()),
                    (.b, SetExpr<Record<MessageSchema>>()),
                    (.c, SetExpr<Record<MessageSchema>>())
                ))

                Each(Node.all, scoped: { selfID, scope in
                    // The root never reads `parent`; its concrete default keeps
                    // the Swift value type finite while matching the algorithm.
                    let parent: LocalVariable<Node> = scope.localVar("parent", initial: .a)
                    let children: LocalVariable<SetExpr<Node>> = scope.localVar("children", initial: SetExpr<Node>())
                    let received: LocalVariable<Int> = scope.localVar("received", initial: 0)

                    Do(Step.n0) {
                        If(selfID == .a) {
                            Assign(inbox, to: Function<Node, SetExpr<Record<MessageSchema>>>.mapping { destination in
                                If(SetExpr<Node>.literal(.a, .b, .c).removing(selfID).contains(destination),
                                   then: inbox[destination].inserting(Record<MessageSchema>.literal(
                                       .init(MessageSchema.kind, .message),
                                       .init(MessageSchema.sender, selfID)
                                   )),
                                   else: inbox[destination])
                            })
                        }
                    }

                    While(Step.n1, received.expr < SetExpr<Node>.literal(.a, .b, .c).removing(selfID).cardinality) {
                        With(inbox[selfID]) { message in
                            Let(inbox.updating(selfID, to: inbox[selfID].removing(message))) { networkAfterReceive in
                                Assign(received, to: received.expr + 1)
                                If(selfID != .a && received.expr == 0) {
                                    Assert(message[MessageSchema.kind] == .message)
                                    Assign(parent, to: message[MessageSchema.sender])
                                    Assign(inbox, to: Function<Node, SetExpr<Record<MessageSchema>>>.mapping { destination in
                                        If(SetExpr<Node>.literal(.a, .b, .c).removing(selfID).removing(message[MessageSchema.sender]).contains(destination),
                                           then: networkAfterReceive[destination].inserting(Record<MessageSchema>.literal(
                                               .init(MessageSchema.kind, .message),
                                               .init(MessageSchema.sender, selfID)
                                           )),
                                           else: networkAfterReceive[destination])
                                    })
                                } else: {
                                    Assign(inbox, to: networkAfterReceive.expr)
                                }
                                If(message[MessageSchema.kind] == .acknowledgement) {
                                    Assign(children, to: children.expr.inserting(message[MessageSchema.sender]))
                                }
                            }
                        }
                    }

                    Do(Step.n2) {
                        If(selfID != .a) {
                            Assert(SetExpr<Node>.literal(.a, .b, .c).removing(selfID).contains(parent.expr))
                            Assign(inbox, to: inbox.updating(parent, to: inbox[parent].inserting(
                                Record<MessageSchema>.literal(
                                    .init(MessageSchema.kind, .acknowledgement),
                                    .init(MessageSchema.sender, selfID)
                                )
                            )))
                        }
                    }
                })
            })
        }
    }
}

extension Example {
    /// A bounded source port of MCEcho: three fully connected nodes and `a`
    /// as TLC's deterministic choice of initiator. The typed record spells
    /// the upstream `sndr` field as the clearer Swift name `sender`.
    public static let echo = Entry(
        id: "echo/Echo",
        upstreamSpec: "echo",
        upstreamModule: "specifications/echo/Echo.tla",
        upstreamCfg: "specifications/echo/MCEcho.cfg",
        expectedDistinct: 75,
        spec: EchoModel.spec,
        notes: "Bounded Echo source port on the three-node fully connected graph. Native and upstream TLC state count = 75; exact graph comparison remains separate evidence."
    )
}
