import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ConfiguredProcessMachine {
    package enum Step: String, CaseIterable { case visit }

    package static var spec: TLASpec {
        #spec("ConfiguredProcessMachine") { scope in
            let nodes = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([1]), Set<Int>([1, 2, 3])]))
            let selected = scope.sharedVar("selected", initial: Set<Int>([]))
            Algorithm("Visits") {
                Each(nodes, scoped: { member, process in
                    let visited = process.localVar("visited", initial: false)
                    Do(Step.visit) {
                        Assign(selected, to: selected.inserting(member))
                        Assign(visited, to: true)
                    }
                })
            }
            Invariant("Members") { selected.isSubset(of: nodes) }
            Reachable("Complete") { selected == nodes }
            let allVisited = Eventually("AllVisited", selected == nodes)
            allVisited
            Validation("Empty") { Bind(nodes, to: Set<Int>([])) }
            Validation("One") { Bind(nodes, to: Set<Int>([1])) }.expect(allVisited, .violated)
            Validation("Three") { Bind(nodes, to: Set<Int>([1, 2, 3])) }.expect(allVisited, .violated)
        }
    }
}

@TLAModel
package struct WeaklyFairConfiguredProcessMachine {
    package enum Step: String, CaseIterable { case visit }

    package static var spec: TLASpec {
        #spec("WeaklyFairConfiguredProcessMachine") { scope in
            let nodes = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([1]), Set<Int>([1, 2, 3])]))
            let selected = scope.sharedVar("selected", initial: Set<Int>([]))
            Algorithm("Visits") {
                Each(nodes, fairness: .weak) { member in
                    While(Step.visit, true) {
                        Assign(selected, to: selected.inserting(member))
                    }
                }
            }
            let allVisited = Eventually("AllVisited", selected == nodes)
            allVisited
            Validation("Empty") { Bind(nodes, to: Set<Int>([])) }
            Validation("One") { Bind(nodes, to: Set<Int>([1])) }
            Validation("Three") { Bind(nodes, to: Set<Int>([1, 2, 3])) }
            Validation("One without specification fairness") { Bind(nodes, to: Set<Int>([1])) }
                .behavior(.initialAndNext).expect(allVisited, .violated)
        }
    }
}

@TLAModel
package struct StronglyFairConfiguredProcessMachine {
    package enum Step: String, CaseIterable { case visit }

    package static var spec: TLASpec {
        #spec("StronglyFairConfiguredProcessMachine") { scope in
            let nodes = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([1]), Set<Int>([1, 2, 3])]))
            let selected = scope.sharedVar("selected", initial: Set<Int>([]))
            Algorithm("Visits") {
                Each(nodes, fairness: .strong) { member in
                    While(Step.visit, true) {
                        Assign(selected, to: selected.inserting(member))
                    }
                }
            }
            let allVisited = Eventually("AllVisited", selected == nodes)
            allVisited
            Validation("Empty") { Bind(nodes, to: Set<Int>([])) }
            Validation("One") { Bind(nodes, to: Set<Int>([1])) }
            Validation("Three") { Bind(nodes, to: Set<Int>([1, 2, 3])) }
            Validation("One without specification fairness") { Bind(nodes, to: Set<Int>([1])) }
                .behavior(.initialAndNext).expect(allVisited, .violated)
        }
    }
}
