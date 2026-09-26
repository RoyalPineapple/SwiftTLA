import SwiftTLA
import SwiftTLAMacros

/// Chang–Roberts leader election over a fixed ring of twelve independent actors.
///
/// Every node begins with its own identifier in its inbox. A delivery keeps a
/// larger identifier moving clockwise, drops a smaller one, and elects the
/// identifier that returns to its originating node. The generated machine owns
/// transition execution; a view only chooses which enabled delivery to make.
@TLAModel
public struct ChangRoberts {
    public enum Node: String, CaseIterable {
        case one, two, three, four, five, six, seven, eight, nine, ten, eleven, twelve
    }

    private enum Step: String, CaseIterable {
        case deliver
    }

    public struct Message: Hashable, Sendable {
        public let candidate: Int
        public let from: Node
        public let to: Node
    }

    public static var spec: TLASpec {
        #spec("ChangRoberts") { scope in
            let identifiers: SharedVariable<[Node: Int]> = scope.sharedVar(initial:
                [.one: 8, .two: 2, .three: 11, .four: 9,
                 .five: 12, .six: 3, .seven: 1, .eight: 5,
                 .nine: 10, .ten: 6, .eleven: 4, .twelve: 7])
            let next: SharedVariable<[Node: Node]> = scope.sharedVar(initial:
                [.one: .two, .two: .three, .three: .four, .four: .five,
                 .five: .six, .six: .seven, .seven: .eight, .eight: .nine,
                 .nine: .ten, .ten: .eleven, .eleven: .twelve, .twelve: .one])
            let messages = scope.sharedVar(initial: Set<Message>([
                Message(candidate: 7, from: .twelve, to: .one),
                Message(candidate: 8, from: .one, to: .two),
                Message(candidate: 2, from: .two, to: .three),
                Message(candidate: 11, from: .three, to: .four),
                Message(candidate: 9, from: .four, to: .five),
                Message(candidate: 12, from: .five, to: .six),
                Message(candidate: 3, from: .six, to: .seven),
                Message(candidate: 1, from: .seven, to: .eight),
                Message(candidate: 5, from: .eight, to: .nine),
                Message(candidate: 10, from: .nine, to: .ten),
                Message(candidate: 6, from: .ten, to: .eleven),
                Message(candidate: 4, from: .eleven, to: .twelve)
            ]))
            let leader = scope.sharedVar(initial: 0)
            Algorithm("ChangRoberts") {
                Each(Node.all, fairness: .weak) { node in
                    Do(Step.deliver) {
                        With(messages) { message in
                            When(leader == 0 && message.to == node)
                            Either {
                                When(message.candidate == identifiers[node])
                                Assign(leader, to: message.candidate)
                                Assign(messages, to: messages.removing(message))
                            } or: {
                                Either {
                                    When(message.candidate > identifiers[node])
                                    Assign(messages, to: messages.removing(message).inserting(
                                        Message.expression(
                                            candidate: message.candidate,
                                            from: node,
                                            to: next[node]
                                        )
                                    ))
                                } or: {
                                    When(message.candidate < identifiers[node])
                                    Assign(messages, to: messages.removing(message))
                                }
                            }
                        }
                        Goto(Step.deliver)
                    }
                }
            }
            let LeaderDomain = Invariant()
            LeaderDomain { leader >= 0 && leader <= 12 }
        }
    }
}
