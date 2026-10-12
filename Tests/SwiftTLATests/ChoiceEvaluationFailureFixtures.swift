import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SingleCandidateDivisionFailureModel: Sendable {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("SingleCandidateDivisionFailureModel") { scope in
            let divisor = scope.sharedVar(initial: 0)
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                Choose(0...0) { candidate in
                    Assign(result, to: 1 / divisor)
                }
            }
        }
    }
}

@TLAModel
struct MixedCandidateDivisionFailureModel: Sendable {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("MixedCandidateDivisionFailureModel") { scope in
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                Choose(0...1) { candidate in
                    Assign(result, to: 1 / candidate)
                }
            }
        }
    }
}

@TLAModel
struct EitherBranchDivisionFailureModel: Sendable {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("EitherBranchDivisionFailureModel") { scope in
            let divisor = scope.sharedVar(initial: 0)
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                Either {
                    Assign(result, to: 1 / divisor)
                } or: {
                    Assign(result, to: 1)
                }
            }
        }
    }
}
