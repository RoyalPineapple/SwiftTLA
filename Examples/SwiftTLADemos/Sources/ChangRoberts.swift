import SwiftTLA
import SwiftTLAMacros

/// Chang–Roberts leader election over a fixed ring of twelve independent actors.
///
/// Every node begins with its own identifier in its inbox. A delivery keeps a
/// larger identifier moving clockwise, drops a smaller one, and elects the
/// identifier that returns to its originating node. The generated actor owns
/// the transition runtime; a view only chooses which enabled delivery to make.
@TLAModel
public struct ChangRoberts {
    public enum Node: String, CaseIterable, FiniteDomainKey {
        case one, two, three, four, five, six, seven, eight, nine, ten, eleven, twelve

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.chang-roberts.node")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, PlusCalLabel {
        case deliver
    }

    public struct MessageFields {
        public let candidate: Int
        public let from: Node
        public let to: Node
    }

    public enum MessageSchema: TLARecordSchema {
        public typealias Fields = MessageFields

        public static let fieldNames: Set<String> = ["candidate", "from", "to"]
        public static let defaultRecord: TLAValue = .record([
            "candidate": .int(1), "from": .string(Node.one.rawValue), "to": .string(Node.two.rawValue)
        ])

        public static func fieldName<Value>(for field: KeyPath<MessageFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \MessageFields.candidate { return "candidate" }
            if key == \MessageFields.from { return "from" }
            if key == \MessageFields.to { return "to" }
            return nil
        }

        public static let candidate = field(\MessageFields.candidate)
        public static let from = field(\MessageFields.from)
        public static let to = field(\MessageFields.to)
    }

    public static var spec: TLASpec {
        #spec("ChangRoberts") {
            Algorithm("ChangRoberts") {
                let identifiers = SharedVar(initial: Function<Node, Int>.literal(
                    (.one, 8), (.two, 2), (.three, 11), (.four, 9),
                    (.five, 12), (.six, 3), (.seven, 1), (.eight, 5),
                    (.nine, 10), (.ten, 6), (.eleven, 4), (.twelve, 7)
                ))
                let next = SharedVar(initial: Function<Node, Node>.literal(
                    (.one, .two), (.two, .three), (.three, .four), (.four, .five),
                    (.five, .six), (.six, .seven), (.seven, .eight), (.eight, .nine),
                    (.nine, .ten), (.ten, .eleven), (.eleven, .twelve), (.twelve, .one)
                ))
                let messages = SharedVar(initial: SetExpr<Record<MessageSchema>>.literal(
                    Record.literal(.init(MessageSchema.candidate, 7), .init(MessageSchema.from, .twelve), .init(MessageSchema.to, .one)),
                    Record.literal(.init(MessageSchema.candidate, 8), .init(MessageSchema.from, .one), .init(MessageSchema.to, .two)),
                    Record.literal(.init(MessageSchema.candidate, 2), .init(MessageSchema.from, .two), .init(MessageSchema.to, .three)),
                    Record.literal(.init(MessageSchema.candidate, 11), .init(MessageSchema.from, .three), .init(MessageSchema.to, .four)),
                    Record.literal(.init(MessageSchema.candidate, 9), .init(MessageSchema.from, .four), .init(MessageSchema.to, .five)),
                    Record.literal(.init(MessageSchema.candidate, 12), .init(MessageSchema.from, .five), .init(MessageSchema.to, .six)),
                    Record.literal(.init(MessageSchema.candidate, 3), .init(MessageSchema.from, .six), .init(MessageSchema.to, .seven)),
                    Record.literal(.init(MessageSchema.candidate, 1), .init(MessageSchema.from, .seven), .init(MessageSchema.to, .eight)),
                    Record.literal(.init(MessageSchema.candidate, 5), .init(MessageSchema.from, .eight), .init(MessageSchema.to, .nine)),
                    Record.literal(.init(MessageSchema.candidate, 10), .init(MessageSchema.from, .nine), .init(MessageSchema.to, .ten)),
                    Record.literal(.init(MessageSchema.candidate, 6), .init(MessageSchema.from, .ten), .init(MessageSchema.to, .eleven)),
                    Record.literal(.init(MessageSchema.candidate, 4), .init(MessageSchema.from, .eleven), .init(MessageSchema.to, .twelve))
                ))
                let leader = SharedVar(initial: 0)

                Each(Node.all, fairness: .weak) { node in
                    Do(Step.deliver) {
                        With(messages) { message in
                            When(leader == 0 && message[MessageSchema.to] == node)
                            Either {
                                When(message[MessageSchema.candidate] == identifiers[node])
                                Assign(leader, to: message[MessageSchema.candidate])
                                Assign(messages, to: messages.removing(message))
                            } or: {
                                Either {
                                    When(message[MessageSchema.candidate] > identifiers[node])
                                    Assign(messages, to: messages.removing(message).inserting(
                                        Record<MessageSchema>.literal(
                                            .init(MessageSchema.candidate, message[MessageSchema.candidate]),
                                            .init(MessageSchema.from, node),
                                            .init(MessageSchema.to, next[node])
                                        )
                                    ))
                                } or: {
                                    When(message[MessageSchema.candidate] < identifiers[node])
                                    Assign(messages, to: messages.removing(message))
                                }
                            }
                        }
                        Goto(Step.deliver)
                    }
                }

                Invariant("LeaderDomain") {
                    leader >= 0 && leader <= 12
                }
            }
        }
    }

    @TLAActor
    public actor Actor {}

    @TLAObservable
    public final class Observable {}
}
