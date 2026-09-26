import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ScopedReachabilityClaims {
    package enum Step: String, CaseIterable { case visit }

    package static var spec: TLASpec {
        #spec("ScopedReachabilityClaims") { scope in
            let members = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([0, 1])]))
            let AllOwn = Reachable()
            let AllVisited = Reachable()
            let EitherOwns = Reachable()
            let Initial = Reachable()
            Algorithm("Ownership", scoped: { algorithm in
                let owner = algorithm.sharedVar(initial: 0)
                Each(members, scoped: { member, process in
                    let visited = process.localVar(initial: false)
                    Do(Step.visit) {
                        Assign(owner, to: member)
                        Assign(visited, to: true)
                        Goto(Step.visit)
                    }
                    AllOwn { owner == member }
                    AllVisited { visited }
                })
                EitherOwns { owner == 0 || owner == 1 }
            })
            Initial { true }
            Validation("Exclusive") { Bind(members, to: Set<Int>([0, 1])) }
                .expect(AllOwn, .violated)
            Validation("Empty") { Bind(members, to: Set<Int>([])) }
            Validation("Selected") { Bind(members, to: Set<Int>([0, 1])) }
                .checking(only: [AllVisited])
        }
    }
}
