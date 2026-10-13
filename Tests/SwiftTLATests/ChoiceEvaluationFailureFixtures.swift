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

@TLAModel
struct EitherDistinctFailuresModel: Sendable {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("EitherDistinctFailuresModel") { scope in
            let divisor = scope.sharedVar(initial: 0)
            let modulus = scope.sharedVar(initial: -1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                Either {
                    Assign(result, to: 1 / divisor)
                } or: {
                    Assign(result, to: 1 % modulus)
                }
            }
        }
    }
}

@TLAModel
struct EitherChoiceAfterDivisionFailureModel: Sendable {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("EitherChoiceAfterDivisionFailureModel") { scope in
            let divisor = scope.sharedVar(in: 0...1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                Either {
                    Assign(result, to: 1 / divisor)
                } or: {
                    Assign(result, to: Select(from: Set<Int>([1])) { _ in false })
                }
            }
        }
    }
}

@TLAModel
struct CandidateChoiceFailureModel: Sendable {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("CandidateChoiceFailureModel") { scope in
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                Choose(0...1) { candidate in
                    Assign(result, to: Select(from: Set<Int>([1])) { selected in
                        selected.expr == candidate
                    })
                }
            }
        }
    }
}

@TLAModel
struct OrderedCandidateFailuresModel: Sendable {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("OrderedCandidateFailuresModel") { scope in
            let modulus = scope.sharedVar(initial: -1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                Choose(0...1) { candidate in
                    Assign(result, to: If(candidate == 0,
                        then: 1 / candidate,
                        else: 1 % modulus))
                }
            }
        }
    }
}

@TLAModel
struct OrderedEnumCandidateFailuresModel: Sendable {
    enum Candidate: String, CaseIterable, FiniteTLAValueDomain {
        case zed, alpha
        static var defaultValue: Self { .zed }
        static let finiteValues = allCases
    }
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("OrderedEnumCandidateFailuresModel") { scope in
            let divisor = scope.sharedVar(initial: 0)
            let modulus = scope.sharedVar(initial: -1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                Choose(Candidate.all) { candidate in
                    Assign(result, to: If(candidate == Candidate.alpha,
                        then: 1 % divisor,
                        else: 1 % modulus))
                }
            }
        }
    }
}

@TLAModel
struct ParameterizedStringCandidateFailuresModel: Sendable {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("ParameterizedStringCandidateFailuresModel") { scope in
            let members = scope.parameter(as: Set<String>.self,
                in: Set<Set<String>>([Set<String>(["alpha", "zed"]), Set<String>(["zed"])]))
            let divisor = scope.sharedVar(initial: 0)
            let modulus = scope.sharedVar(initial: -1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                With(members) { candidate in
                    Assign(result, to: If(candidate == "alpha",
                        then: 1 / divisor,
                        else: 1 % modulus))
                }
            }
            let bothFail = Validation(label: "Both fail") {
                Bind(members, to: Set<String>(["alpha", "zed"]))
            }
            bothFail
            let laterFailure = Validation(label: "Later failure") {
                Bind(members, to: Set<String>(["zed"]))
            }
            laterFailure
        }
    }
}

@TLAModel
struct BoundBodyChoiceFailureModel: Sendable {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("BoundBodyChoiceFailureModel") { scope in
            let source = scope.sharedVar(in: 0...1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                Let(source) { bound in
                    Assign(result, to: Select(from: Set<Int>([1])) { selected in
                        selected.expr == bound.expr
                    })
                }
            }
        }
    }
}

@TLAModel
struct ConditionalChoiceThenModuloFailureModel: Sendable {
    enum Step: String, CaseIterable { case compute }

    static var spec: TLASpec {
        #spec("ConditionalChoiceThenModuloFailureModel") { scope in
            let selector = scope.sharedVar(in: 0...1)
            let divisor = scope.sharedVar(in: 0...1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.compute) {
                If(Select(from: Set<Bool>([true])) { _ in selector == 1 }) {
                    Assign(result, to: 1 % divisor)
                } else: {
                    Assign(result, to: 2)
                }
            }
        }
    }
}

@TLAModel
struct ExpressionConditionalFailureModel: Sendable {
    enum Step: String, CaseIterable { case compute }

    static var spec: TLASpec {
        #spec("ExpressionConditionalFailureModel") { scope in
            let mode = scope.sharedVar(in: 0...1)
            let divisor = scope.sharedVar(in: 0...1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.compute) {
                Assign(result, to: If(mode == 1,
                    then: Select(from: Set<Int>([1])) { _ in false },
                    else: 1 % divisor))
            }
        }
    }
}

@TLAModel
struct ShortCircuitFailureModel: Sendable {
    enum Step: String, CaseIterable { case conjunction, disjunction }

    static var spec: TLASpec {
        #spec("ShortCircuitFailureModel") { scope in
            let enabled = scope.sharedVar(in: SetExpr<Bool>.literal(false, true))
            let divisor = scope.sharedVar(in: 0...1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.conjunction) {
                When(enabled && (1 % divisor == 0))
                Assign(result, to: 1)
            }
            Do(Step.disjunction) {
                When(enabled || (1 % divisor == 0))
                Assign(result, to: 2)
            }
        }
    }
}

@TLAModel
struct BoundConditionalBodyFailureModel: Sendable {
    enum Step: String, CaseIterable { case compute }

    static var spec: TLASpec {
        #spec("BoundConditionalBodyFailureModel") { scope in
            let mode = scope.sharedVar(in: 0...1)
            let divisor = scope.sharedVar(in: 0...1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.compute) {
                Let(If(mode == 1,
                    then: Select(from: Set<Int>([1])) { _ in false },
                    else: 1)) { bound in
                    Assign(result, to: bound.expr % divisor)
                }
            }
        }
    }
}
