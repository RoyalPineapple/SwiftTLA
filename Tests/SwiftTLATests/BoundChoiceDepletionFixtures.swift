import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct BoundChoiceDepletionModel {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec { scope in
            let picked = scope.sharedVar(initial: 0)
            let source = scope.sharedVar(initial: Set<Int>([1, 2, 3]))
            Do(Step.pick) {
                With(source) { selected in
                    Assign(picked, to: selected)
                    Assign(source, to: source.removing(selected))
                }
            }
        }
    }
}
