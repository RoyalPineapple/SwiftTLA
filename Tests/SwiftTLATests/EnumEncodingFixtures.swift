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
            let rawText = scope.sharedVar(initial: Expr(Datum.text).assuming(String.self))
            let texts = scope.sharedVar(initial: SetExpr<String>.literal(
                Expr(Datum.text).assuming(String.self), Expr("é")))
            Do(Step.select, over: Datum.all) { next in
                Assign(value, to: next)
                Assign(chosen, to: chosen)
                Assign(rawText, to: If(next == Datum.text, then: next.assuming(String.self),
                    else: Expr(Datum.text).assuming(String.self)))
                Assign(texts, to: texts.union(SetExpr<String>.literal(rawText)))
            }
            Invariant("DistinctTags") {
                If(value == Datum.first,
                    then: value != Datum.second && value != Datum.text,
                    else: If(value == Datum.second,
                        then: value != Datum.first && value != Datum.text,
                        else: value == Datum.text && value != Datum.first && value != Datum.second))
            }
            Invariant("ParameterMember") { nominal == Datum.first || nominal == Datum.second }
            Invariant("RawTextPreserved") {
                Dictionary<String, Int>.mapping(over: texts) { _ in 1 }.keys.cardinality == 2
                    && texts.cardinality == 2 && rawText != "é"
            }
            let all = Validation(label: "All") { Bind(nominal, to: Datum.first) }
            all
        }
    }
}
