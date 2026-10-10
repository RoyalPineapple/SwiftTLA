import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GeneratedAtomicCopyProofModel {
    enum Step: String, CaseIterable { case copy }

    static var spec: TLASpec {
        #spec("GeneratedAtomicCopyProofModel") { scope in
            let first = scope.sharedVar(initial: 0)
            let second = scope.sharedVar(initial: 1)
            let copy = Do(Step.copy) {
                Assign(first, to: second)
                Assign(second, to: first)
            }
            copy
        }
    }
}

@TLAModel
struct RenamedAtomicCopyProofModel {
    enum Step: String, CaseIterable { case copy }

    static var spec: TLASpec {
        #spec("RenamedAtomicCopyProofModel") { scope in
            let left = scope.sharedVar(initial: 0)
            let right = scope.sharedVar(initial: 1)
            let copy = Do(Step.copy) {
                Assign(left, to: right)
                Assign(right, to: left)
            }
            copy
        }
    }
}
