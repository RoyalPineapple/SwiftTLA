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
