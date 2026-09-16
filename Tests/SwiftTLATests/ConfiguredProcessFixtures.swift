import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ConfiguredProcessMachine {
    enum Step: String, CaseIterable { case visit }

    static var spec: TLASpec {
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
            Eventually("AllVisited", selected == nodes)
            Validation("Empty") { Bind(nodes, to: Set<Int>([])) }
            Validation("One") { Bind(nodes, to: Set<Int>([1])) }
            Validation("Three") { Bind(nodes, to: Set<Int>([1, 2, 3])) }
        }
    }
}

@TLAModel
struct WeaklyFairConfiguredProcessMachine {
    enum Step: String, CaseIterable { case visit }

    static var spec: TLASpec {
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
            Eventually("AllVisited", selected == nodes)
            Validation("Empty") { Bind(nodes, to: Set<Int>([])) }
            Validation("One") { Bind(nodes, to: Set<Int>([1])) }
            Validation("Three") { Bind(nodes, to: Set<Int>([1, 2, 3])) }
        }
    }
}

@TLAModel
struct StronglyFairConfiguredProcessMachine {
    enum Step: String, CaseIterable { case visit }

    static var spec: TLASpec {
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
            Eventually("AllVisited", selected == nodes)
            Validation("Empty") { Bind(nodes, to: Set<Int>([])) }
            Validation("One") { Bind(nodes, to: Set<Int>([1])) }
            Validation("Three") { Bind(nodes, to: Set<Int>([1, 2, 3])) }
        }
    }
}
