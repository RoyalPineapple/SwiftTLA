import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GuardedAlgorithm {
    enum Step: String, CaseIterable { case choose, finish }

    static var spec: TLASpec {
        #spec("GuardedAlgorithm") {
            Algorithm("GuardedAlgorithm", scoped: { scope in
                let ready = scope.sharedVar(in: 0...1)
                let value = scope.sharedVar(initial: 0)
                Do(Step.choose, when: ready == 1) {
                    Assign(value, to: 1 / ready)
                    Choose(1...2) { choice in Assign(value, to: value * choice) }
                    Goto(Step.finish)
                }
                Do(Step.finish) { Stop() }
            })
        }
    }
}
