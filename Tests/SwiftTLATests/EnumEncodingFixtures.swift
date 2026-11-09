import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct EncodedEnumDomain {
    enum Datum: String, CaseIterable, FiniteTLAValueDomain {
        case first = "d1", second = "d2", text = "e\u{301}"
        static func == (lhs: Self, rhs: Self) -> Bool { true }
        func hash(into hasher: inout Hasher) { hasher.combine(0) }
        static var defaultValue: Self { .first }
        static let finiteValues = allCases
        var tlaValue: TLAValue {
            switch self {
            case .first, .second: .constant(rawValue)
            case .text: .string(rawValue)
            }
        }
    }
    enum Step: String, CaseIterable { case select }
    static var spec: TLASpec {
        #spec("EncodedEnumDomain") { scope in
            Extends(.randomization)
            let nominal = scope.parameter(as: Datum.self, in: SetExpr<Datum>.literal(Datum.first, Datum.second))
            let chosen = scope.sharedVar(in: RandomSubset(upTo: 1, from: SetExpr<Int>.literal(7)))
            let value = scope.sharedVar(in: Datum.all)
            Do(Step.select, over: Datum.all) { next in
                Assign(value, to: next)
                Assign(chosen, to: chosen)
            }
            Invariant("DistinctTags") {
                If(value == Datum.first,
                    then: value != Datum.second && value != Datum.text,
                    else: If(value == Datum.second,
                        then: value != Datum.first && value != Datum.text,
                        else: value == Datum.text && value != Datum.first && value != Datum.second))
            }
            Invariant("ParameterMember") { nominal == Datum.first || nominal == Datum.second }
            let all = Validation(label: "All") { Bind(nominal, to: Datum.first) }
            all
        }
    }
}
