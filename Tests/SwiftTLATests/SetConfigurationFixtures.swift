import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SetConfiguredMachine {
    enum Step: String, CaseIterable { case adopt }

    static var spec: TLASpec {
        #spec("SetConfiguredMachine") { scope in
            let nodes = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([1]), Set<Int>([1, 2, 3])]))
            let quorum = scope.parameter(as: Int.self, in: IntRange(1, through: nodes.cardinality))
            let selected = scope.sharedVar(_name: "selected", initial: Set<Int>([]))
            let selection = Algorithm(label: "Selection") {
                Do(Step.adopt, when: selected.isEmpty) {
                    Assign(selected, to: nodes)
                    Goto(Step.adopt)
                }
            }
            selection
            Invariant("Members") { selected.isSubset(of: nodes) }
            Reachable("Quorum") { selected.cardinality >= quorum }
            let oneNode = Validation(label: "One node") {
                Bind(nodes, to: Set<Int>([1]))
                Bind(quorum, to: 1)
            }.expectDeadlock(.violated)
            oneNode
            let threeNodes = Validation(label: "Three nodes") {
                Bind(nodes, to: Set<Int>([1, 2, 3]))
                Bind(quorum, to: 2)
            }.expectDeadlock(.violated)
            threeNodes
        }
    }
}

struct CollidingSetMember: TLAValueType, Hashable {
    let id: Int
    static var defaultValue: Self { .init(id: 0) }
    var tlaValue: TLAValue { .int(0) }
    init(id: Int) { self.id = id }
    init?(formalValue: TLAValue) { self.id = 0 }
}
