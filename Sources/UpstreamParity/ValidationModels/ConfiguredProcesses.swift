import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ConfiguredProcessMachine {
    package enum Step: String, CaseIterable { case visit }

    package static var spec: TLASpec {
        #spec { scope in
            let nodes = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([1]), Set<Int>([1, 2, 3])]))
            let selected = scope.sharedVar(initial: Set<Int>([]))
            let Visits = Algorithm {
                Each(nodes, scoped: { member, process in
                    let visited = process.localVar(initial: false)
                    Do(Step.visit) {
                        Assign(selected, to: selected.inserting(member))
                        Assign(visited, to: true)
                    }
                })
            }
            Visits
            Invariant("Members") { selected.isSubset(of: nodes) }
            Reachable("Complete") { selected == nodes }
            let allVisited = Eventually("AllVisited", selected == nodes)
            allVisited
            let Empty = Validation { Bind(nodes, to: Set<Int>([])) }
            Empty
            let One = Validation { Bind(nodes, to: Set<Int>([1])) }.expect(allVisited, .violated)
            One
            let Three = Validation { Bind(nodes, to: Set<Int>([1, 2, 3])) }.expect(allVisited, .violated)
            Three
        }
    }
}

@TLAModel
package struct WeaklyFairConfiguredProcessMachine {
    package enum Step: String, CaseIterable { case visit }

    package static var spec: TLASpec {
        #spec { scope in
            let nodes = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([1]), Set<Int>([1, 2, 3])]))
            let selected = scope.sharedVar(initial: Set<Int>([]))
            let Visits = Algorithm {
                Each(nodes, fairness: .weak) { member in
                    While(Step.visit, true) {
                        Assign(selected, to: selected.inserting(member))
                    }
                }
            }
            Visits
            let allVisited = Eventually("AllVisited", selected == nodes)
            allVisited
            let Empty = Validation { Bind(nodes, to: Set<Int>([])) }
            Empty
            let One = Validation { Bind(nodes, to: Set<Int>([1])) }
            One
            let Three = Validation { Bind(nodes, to: Set<Int>([1, 2, 3])) }
            Three
            let oneWithoutSpecificationFairness = Validation(label: "One without specification fairness") { Bind(nodes, to: Set<Int>([1])) }
                .behavior(.initialAndNext).expect(allVisited, .violated)
            oneWithoutSpecificationFairness
        }
    }
}

@TLAModel
package struct StronglyFairConfiguredProcessMachine {
    package enum Step: String, CaseIterable { case visit }

    package static var spec: TLASpec {
        #spec { scope in
            let nodes = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([1]), Set<Int>([1, 2, 3])]))
            let selected = scope.sharedVar(initial: Set<Int>([]))
            let Visits = Algorithm {
                Each(nodes, fairness: .strong) { member in
                    While(Step.visit, true) {
                        Assign(selected, to: selected.inserting(member))
                    }
                }
            }
            Visits
            let allVisited = Eventually("AllVisited", selected == nodes)
            allVisited
            let Empty = Validation { Bind(nodes, to: Set<Int>([])) }
            Empty
            let One = Validation { Bind(nodes, to: Set<Int>([1])) }
            One
            let Three = Validation { Bind(nodes, to: Set<Int>([1, 2, 3])) }
            Three
            let oneWithoutSpecificationFairness = Validation(label: "One without specification fairness") { Bind(nodes, to: Set<Int>([1])) }
                .behavior(.initialAndNext).expect(allVisited, .violated)
            oneWithoutSpecificationFairness
        }
    }
}
