import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ConfiguredDictionaryValues: Sendable {
    package enum Step: String, CaseIterable { case fill }

    package static var spec: TLASpec {
        #spec("ConfiguredDictionaryValues") { scope in
            let jugs = scope.parameter(as: Set<String>.self,
                in: Set<Set<String>>([Set<String>([]), Set<String>(["small"]), Set<String>(["small", "big"])]))
            let capacity = scope.parameter(as: [String: Int].self,
                in: Functions(from: jugs, to: Set<Int>([3, 5])))
            let contents = scope.sharedVar(initial: capacity)
            let total = Invariant()
            let sameKey = Invariant()
            let hasCapacity = Invariant()
            Do(Step.fill, over: jugs) { jug in
                Assign(contents[jug], to: capacity[jug])
            }
            total { Functions(from: jugs, to: Set<Int>([3, 5])).contains(contents) }
            sameKey {
                ForAll(in: jugs, and: jugs) { first, second in
                    first != second || contents[first] == contents[second]
                }
            }
            hasCapacity {
                Exists(in: jugs, and: Set<Int>([3, 5])) { jug, amount in contents[jug] == amount } == !jugs.isEmpty
            }
            Validation("Empty") {
                Bind(jugs, to: Set<String>([]))
                Bind(capacity, to: [:])
            }.expectDeadlock(.violated)
            Validation("Typed empty") {
                Bind(jugs, to: Set<String>([]))
                Bind(capacity, to: Dictionary<String, Int>())
            }.expectDeadlock(.violated)
            Validation("One jug") {
                Bind(jugs, to: Set<String>(["small"]))
                Bind(capacity, to: ["small": 3])
            }
            Validation("Two jugs") {
                Bind(jugs, to: Set<String>(["small", "big"]))
                Bind(capacity, to: ["small": 3, "big": 5])
            }
        }
    }
}
