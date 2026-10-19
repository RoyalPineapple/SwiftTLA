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

@TLAModel
struct GeneratedBooleanCaptureProofModel {
    enum Step: String, CaseIterable { case copy }

    static var spec: TLASpec {
        #spec("GeneratedBooleanCaptureProofModel") { scope in
            let flag = scope.sharedVar(initial: false)
            let mirror = scope.sharedVar(initial: true)
            Do(Step.copy) {
                Let(mirror) { captured in
                    Assign(flag, to: captured)
                }
            }
        }
    }
}

@TLAModel
struct GeneratedBooleanEqualityProofModel {
    enum Step: String, CaseIterable { case compare }

    static var spec: TLASpec {
        #spec("GeneratedBooleanEqualityProofModel") { scope in
            let flag = scope.sharedVar(initial: false)
            let mirror = scope.sharedVar(initial: false)
            Do(Step.compare) {
                Let(mirror == flag) { matches in
                    Assign(flag, to: matches)
                }
            }
        }
    }
}

@TLAModel
struct GeneratedCheckedEqualityProofModel {
    enum Step: String, CaseIterable { case compare }

    static var spec: TLASpec {
        #spec("GeneratedCheckedEqualityProofModel") { scope in
            let left = scope.sharedVar(in: SetExpr<Int>.literal(2, 9_223_372_036_854_775_807))
            let right = scope.sharedVar(initial: 3)
            let matched = scope.sharedVar(initial: false)
            Do(Step.compare) {
                Let(left + 1 == right) { result in
                    Assign(matched, to: result)
                }
            }
        }
    }
}

@TLAModel
struct GeneratedPredicateCaptureProofModel {
    enum Step: String, CaseIterable { case compare }

    static var spec: TLASpec {
        #spec("GeneratedPredicateCaptureProofModel") { scope in
            let left = scope.sharedVar(initial: 2)
            let right = scope.sharedVar(initial: 3)
            let matched = scope.sharedVar(initial: false)
            Do(Step.compare) {
                Let(!(left < right)) { result in
                    Assign(matched, to: result)
                }
            }
        }
    }
}

@TLAModel
struct GeneratedScalarGuardProofModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("GeneratedScalarGuardProofModel") { scope in
            let left = scope.sharedVar(in: SetExpr<Int>.literal(2, 4))
            let right = scope.sharedVar(initial: 3)
            let advanced = scope.sharedVar(initial: false)
            Do(Step.advance) {
                When(left < right)
                Assign(advanced, to: true)
            }
        }
    }
}
