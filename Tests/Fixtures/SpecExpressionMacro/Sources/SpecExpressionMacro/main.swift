import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct Counter {
    enum Node: String, FiniteDomainKey {
        case only

        static let formalDomain: [Node] = [.only]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "fixture.spec-expression-node")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("Counter") {
            Algorithm("Counter") {
                let value = SharedVar(initial: 0)
                Each(Node.all) { _ in
                    let visits = LocalVar(initial: 0)
                    Do("advance") {
                        When(value < 1)
                        Assign(value, to: value + 1)
                        Assign(visits, to: visits + 1)
                        Stop()
                    }
                }
            }
        }
    }
}

var counter = Counter()
let result = try counter.apply(.advance(process: .only))
precondition(result.after.value == 1)
