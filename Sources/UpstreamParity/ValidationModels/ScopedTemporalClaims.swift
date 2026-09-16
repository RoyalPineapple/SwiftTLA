import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ScopedTemporalClaims {
    package enum Step: String, CaseIterable { case toggle }

    package static var spec: TLASpec {
        #spec("ScopedTemporalClaims") { scope in
            let members = scope.parameter(as: Set<Int>.self, in: Set<Set<Int>>([Set<Int>([0, 1])]))
            let value = scope.sharedVar("value", initial: 0)
            let Bounded = Always()
            let Started = Eventually()
            let Recurs = AlwaysEventually()
            let Settles = EventuallyAlways()
            let Responds = LeadsTo()
            Algorithm("Toggle") {
                Each(members, fairness: .weak, scoped: { member, process in
                    let visited = process.localVar("visited", initial: false)
                    While(Step.toggle, true) {
                        Assign(value, to: 1 - value)
                        Assign(visited, to: true)
                    }
                    Recurs(value == member)
                    Settles(visited)
                })
                Bounded(value >= 0 && value <= 1)
                Responds(value == 0, value == 1)
            }
            Started(value == 1)
            Validation("All") { Bind(members, to: Set<Int>([0, 1])) }
        }
    }
}
