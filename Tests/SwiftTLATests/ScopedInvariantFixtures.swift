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
            Algorithm("Visits", scoped: { algorithm in
                let value = algorithm.sharedVar("value", initial: 0)
                Each(nodes, scoped: { member, process in
                    let visited = process.localVar("visited", initial: false)
                    Do(Step.visit) {
                        Assign(visited, to: true)
                        Goto(Step.visit)
                    }
                    unvisited { visited == false }
                })
                stable { value == 0 }
            })
            top { true }
            Validation("All") { Bind(nodes, to: Set<Int>([1, 2])) }.expect(unvisited, .violated)
            Validation("Selected") { Bind(nodes, to: Set<Int>([1, 2])) }.checking(only: [stable, top])
        }
    }
}
