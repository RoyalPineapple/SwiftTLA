import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct FairRefinementTarget {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("FairRefinementTarget") { scope in
            let N = scope.parameter(as: Int.self, in: Set<Int>([1]))
            let value = scope.sharedVar(initial: 0)
            let advance = Do(Step.advance, when: value == 0) {
                Assign(value, to: N)
            }
            advance
            WeakFairness(advance)
            let FairTarget = Validation { Bind(N, to: 1) }
            FairTarget
        }
    }
}

@TLAModel
struct StutteringRefinementSource {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec("StutteringRefinementSource") { scope in
            let value = scope.sharedVar(initial: 0)
            Do(Step.stay) { Skip() }

            let abstract = Instance(of: FairRefinementTarget.self) { Bind(\.N, to: 1) }
            abstract
            let Full = Refinement(instance: abstract) {
                Map(\.value, from: value)
            }
            Full
            let Safety = Refinement(instance: abstract, behavior: .initialAndNext) {
                Map(\.value, from: value)
            }
            Safety
        }
    }
}
