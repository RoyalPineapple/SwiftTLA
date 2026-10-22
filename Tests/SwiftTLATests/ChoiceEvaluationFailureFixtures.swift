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
struct ParameterizedModelValueCandidateFailuresModel: Sendable {
    enum Member: String, CaseIterable, FiniteTLAValueDomain {
        case zed = "z", alpha = "a"
        static var defaultValue: Self { .zed }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .constant(rawValue) }
    }
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("ParameterizedModelValueCandidateFailuresModel") { scope in
            let members = scope.parameter(as: Set<Member>.self,
                in: Set<Set<Member>>([Set<Member>([.alpha, .zed]), Set<Member>([.zed])]))
            let divisor = scope.sharedVar(initial: 0)
            let modulus = scope.sharedVar(initial: -1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                With(members) { candidate in
                    Assign(result, to: If(candidate == Member.alpha,
                        then: 1 / divisor,
                        else: 1 % modulus))
                }
            }
            let bothFail = Validation(label: "Both fail") {
                Bind(members, to: Set<Member>([.alpha, .zed]))
            }
            bothFail
            let laterFailure = Validation(label: "Later failure") {
                Bind(members, to: Set<Member>([.zed]))
            }
            laterFailure
        }
    }
}

@TLAModel
struct ParameterDerivedDictionaryKeyFailuresModel: Sendable {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("ParameterDerivedDictionaryKeyFailuresModel") { scope in
            let tables = scope.parameter(as: [[String: Int]].self,
                in: Set<[[String: Int]]>([[["zed": 1, "alpha": 2]]]))
            let divisor = scope.sharedVar(initial: 0)
            let modulus = scope.sharedVar(initial: -1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                With(tables[1].keys) { candidate in
                    Assign(result, to: If(candidate == "alpha",
                        then: 1 / divisor,
                        else: 1 % modulus))
                }
            }
            let configured = Validation {
                Bind(tables, to: [["zed": 1, "alpha": 2]])
            }
            configured
        }
    }
}

@TLAModel
struct StateDependentStringCandidateFailuresModel: Sendable {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("StateDependentStringCandidateFailuresModel") { scope in
            let members = scope.sharedVar(initial: Set<String>(["alpha", "zed"]))
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
struct NestedShortCircuitFailureModel: Sendable {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("NestedShortCircuitFailureModel") { scope in
            let enabled = scope.sharedVar(in: SetExpr<Bool>.literal(false, true))
            let ready = scope.sharedVar(in: SetExpr<Bool>.literal(false, true))
            let divisor = scope.sharedVar(in: 0...1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.advance) {
                When(enabled && (ready || (1 % divisor == 0)))
                Assign(result, to: 1)
            }
        }
    }
}

@TLAModel
struct ConditionalShortCircuitFailureModel: Sendable {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("ConditionalShortCircuitFailureModel") { scope in
            let enabled = scope.sharedVar(in: SetExpr<Bool>.literal(false, true))
            let ready = scope.sharedVar(in: SetExpr<Bool>.literal(false, true))
            let divisor = scope.sharedVar(in: 0...1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.advance) {
                When(enabled && If(ready, then: true, else: 1 % divisor == 0))
                Assign(result, to: 1)
            }
        }
    }
}

@TLAModel
struct BranchingBooleanFailureModel: Sendable {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("BranchingBooleanFailureModel") { scope in
            let enabled = scope.sharedVar(in: SetExpr<Bool>.literal(false, true))
            let ready = scope.sharedVar(in: SetExpr<Bool>.literal(false, true))
            let divisor = scope.sharedVar(in: 0...1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.advance) {
                When(If(enabled, then: ready && (1 % divisor == 0),
                    else: !(ready && true)))
                Assign(result, to: 1)
            }
        }
    }
}

@TLAModel
struct ConditionalBooleanAssignmentModel: Sendable {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("ConditionalBooleanAssignmentModel") { scope in
            let enabled = scope.sharedVar(in: SetExpr<Bool>.literal(false, true))
            let ready = scope.sharedVar(in: SetExpr<Bool>.literal(false, true))
            let divisor = scope.sharedVar(in: 0...1)
            let result = scope.sharedVar(initial: false)
            Do(Step.advance) {
                Assign(result,
                    to: If(enabled, then: ready && (1 % divisor == 0), else: !ready))
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

@TLAModel
struct ConjunctiveAlternativeFailureModel: Sendable {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("ConjunctiveAlternativeFailureModel") { scope in
            let divisor = scope.sharedVar(initial: 0)
            let selected = scope.sharedVar(initial: -1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                Either {
                    Assign(selected, to: 0)
                } or: {
                    Assign(selected, to: 1)
                }
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
struct BranchwiseConjunctionFailureOrderModel: Sendable {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("BranchwiseConjunctionFailureOrderModel") { scope in
            let divisor = scope.sharedVar(in: 0...1)
            let modulus = scope.sharedVar(in: Set<Int>([-1, 0, 1, 2]))
            let selected = scope.sharedVar(initial: -1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                Either {
                    Assign(selected, to: 0)
                } or: {
                    Assign(selected, to: 1 % modulus)
                }
                Assign(result, to: 1 / divisor)
            }
        }
    }
}

@TLAModel
struct UndefinedChoiceDomainModel: Sendable {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("UndefinedChoiceDomainModel") { scope in
            let divisor = scope.sharedVar(in: 0...1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                With(SetExpr<Int>.literal(1 / divisor)) { candidate in
                    Assign(result, to: candidate)
                }
            }
        }
    }
}
