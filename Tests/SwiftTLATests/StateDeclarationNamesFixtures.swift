import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct BoundStateNamesModel {
    enum Step: String, CaseIterable { case visit }

    static var spec: TLASpec {
        #spec("BoundStateNames") { specification in
            let text = specification.sharedVar(initial: "payload")
            Algorithm("Workers", scoped: { algorithm in
                let count = algorithm.sharedVar(in: 0...1)
                Each(Set<Int>([1]), scoped: { member, process in
                    let seen = process.localVar(initial: false)
                    Do(Step.visit) {
                        Assign(count, to: count + member)
                        Assign(text, to: "visited")
                        Assign(seen, to: true)
                        Stop()
                    }
                })
            })
        }
    }
}

@TLAModel
struct EscapedStateNamesModel {
    enum Step: String, CaseIterable { case visit }

    static var spec: TLASpec {
        #spec("EscapedStateNames") { `class` in
            let `repeat` = `class`.sharedVar(initial: "payload")
            let `switch` = `class`.parameter(as: Int.self, in: 0...1)
            let `defer` = Invariant()
            Algorithm("Workers", scoped: { `struct` in
                let `default` = `struct`.sharedVar(initial: `switch`)
                Each(Set<Int>([1]), scoped: { member, `enum` in
                    let `case` = `enum`.localVar(initial: false)
                    Do(Step.visit) {
                        Assign(`default`, to: `default` + member)
                        Assign(`repeat`, to: "visited")
                        Assign(`case`, to: true)
                        Stop()
                    }
                })
                `defer` { `default` <= 2 }
            })
            Validation("One") { Bind(`switch`, to: 1) }.checking(only: [`defer`])
        }
    }
}
