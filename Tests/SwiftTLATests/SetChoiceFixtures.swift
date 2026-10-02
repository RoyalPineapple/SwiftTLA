import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SetChoiceMachine {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("SetChoiceMachine") { scope in
            let members = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([1]), Set<Int>([1, 2])]))
            let selected = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                With(members) { member in
                    Assign(selected, to: member)
                }
            }
            let empty = Validation(label: "Empty") { Bind(members, to: Set<Int>([])) }
                .expectDeadlock(.violated)
            empty
            let singleton = Validation(label: "Singleton") { Bind(members, to: Set<Int>([1])) }
            singleton
            let multiple = Validation(label: "Multiple") { Bind(members, to: Set<Int>([1, 2])) }
            multiple
        }
    }
}
