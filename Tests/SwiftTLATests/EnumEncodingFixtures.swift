import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct EncodedEnumDomain {
    enum Datum: String, CaseIterable, FiniteTLAValueDomain {
        case first = "d1", second = "d2", text = "e\u{301}"
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
            let chosen = scope.sharedVar(in: RandomSubset(upTo: 1, from: SetExpr<Int>.literal(7)))
            let value = scope.sharedVar(in: Datum.all)
            Do(Step.select, over: Datum.all) { next in
                Assign(value, to: next)
                Assign(chosen, to: chosen)
            }
            let all = Validation(label: "All") {}
            all
        }
    }
}
