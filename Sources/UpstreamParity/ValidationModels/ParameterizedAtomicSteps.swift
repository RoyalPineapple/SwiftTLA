import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ParameterizedAtomicSteps: Sendable {
    package enum Step: String, CaseIterable { case select, transfer }

    package static var spec: TLASpec {
        #spec("ParameterizedAtomicSteps") { scope in
            let members = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([0]), Set<Int>([0, 1])]))
            let value = scope.sharedVar(initial: 0)
            let copied = scope.sharedVar(initial: 0)
            let ordered = Invariant()
            Do(Step.select, over: members) { member in
                Assign(value, to: member)
                Assign(copied, to: value)
                Assert(copied == member)
            }
            Do(Step.transfer, over: members, members) { source, destination in
                When(source != destination && value == source)
                Assign(value, to: destination)
                Assign(copied, to: value)
                Assert(copied == destination)
            }
            ordered { value == copied && value >= 0 && value <= 1 }
            Validation("Empty") { Bind(members, to: Set<Int>([])) }.expectDeadlock(.violated)
            Validation("One") { Bind(members, to: Set<Int>([0])) }
            Validation("Two") { Bind(members, to: Set<Int>([0, 1])) }
        }
    }
}
