import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct CheckedMultiplicationOverflow {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("CheckedMultiplicationOverflow") {
            let algorithm = Algorithm(label: "CheckedMultiplicationOverflow", scoped: { scope in
                let count = scope.sharedVar(_name: "count", in: Set<Int>([
                    3, 9_223_372_036_854_775_807, -9_223_372_036_854_775_807
                ]))
                Do(Step.advance) { Assign(count, to: count * 2) }
            })
            algorithm
        }
    }
}
