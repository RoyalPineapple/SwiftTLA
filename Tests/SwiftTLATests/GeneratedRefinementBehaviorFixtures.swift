import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct FairRefinementTarget {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("FairRefinementTarget") { scope in
            Constant("EnabledValue", true)
            Constant("FiniteValues", SetExpr<Int>(1, 2))
            Constant("TextValue", "left = right")
            Constant("Minimum", -1)
            Constant("QuotedText", "a\"b")
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
    enum Step: String, CaseIterable { case stay, advance }

    static var spec: TLASpec {
        #spec("StutteringRefinementSource") { scope in
            let flag = scope.parameter(as: Bool.self, in: Set<Bool>([false, true]))
            let value = scope.sharedVar(initial: 0)
            Do(Step.stay, when: flag || !flag) { Skip() }
            Do(Step.advance, when: value == 0) { Assign(value, to: 1) }

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
