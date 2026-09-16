import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct RecurringPopulation {
    package enum Step: String, CaseIterable { case toggle }

    package static var spec: TLASpec {
        #spec("RecurringPopulation") { scope in
            let members = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([0]), Set<Int>([0, 1]), Set<Int>([2])]))
            let value = scope.sharedVar(initial: 0)
            let EachRecurs = AlwaysEventually()
            let EachVisits = Eventually()
            Algorithm("Toggle") {
                Each(members, fairness: .weak, scoped: { member, process in
                    let visited = process.localVar(initial: false)
                    While(Step.toggle, true) {
                        Assign(value, to: 1 - value)
                        Assign(visited, to: true)
                    }
                    EachRecurs(value == member)
                    EachVisits(visited)
                })
            }
            Validation("Empty") { Bind(members, to: Set<Int>([])) }
            Validation("One") { Bind(members, to: Set<Int>([0])) }
            Validation("Two") { Bind(members, to: Set<Int>([0, 1])) }
            Validation("Outside cycle") { Bind(members, to: Set<Int>([2])) }
                .expect(EachRecurs, .violated)
        }
    }
}
