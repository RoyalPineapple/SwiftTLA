import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ScopedInvariantMachine {
    enum Step: String, CaseIterable { case visit }

    static var spec: TLASpec {
        #spec("ScopedInvariantMachine") { scope in
            let nodes = scope.parameter(as: Set<Int>.self, in: Set<Set<Int>>([Set<Int>([1, 2])]))
            let stable = Invariant()
            let unvisited = Invariant()
            let top = Invariant()
            let visits = Algorithm(label: "Visits", scoped: { algorithm in
                let value = algorithm.sharedVar(_name: "value", initial: 0)
                Each(nodes, scoped: { member, process in
                    let visited = process.localVar(_name: "visited", initial: false)
                    Do(Step.visit) {
                        Assign(visited, to: true)
                        Goto(Step.visit)
                    }
                    unvisited { visited == false }
                })
                stable { value == 0 }
            })
            visits
            top { true }
            let all = Validation(label: "All") { Bind(nodes, to: Set<Int>([1, 2])) }.expect(unvisited, .violated)
            all
            let selected = Validation(label: "Selected") { Bind(nodes, to: Set<Int>([1, 2])) }.checking(only: [stable, top])
            selected
        }
    }
}
