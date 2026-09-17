import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ConditionalPopulation {
    enum Step: String, CaseIterable { case toggle }

    static var spec: TLASpec {
        #spec("ConditionalPopulation") { scope in
            let members = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([0, 1])]))
            let value = scope.sharedVar(initial: 0)
            let selected = Temporal()
            Algorithm("Toggle") {
                Each(members, fairness: .weak, scoped: { member, process in
                    While(Step.toggle, true) { Assign(value, to: 1 - value) }
                    selected(.conditional(value == member,
                        then: .alwaysStep(on: value) { before, after in before != after },
                        else: .eventually(value == member)))
                })
            }
        }
    }
}
