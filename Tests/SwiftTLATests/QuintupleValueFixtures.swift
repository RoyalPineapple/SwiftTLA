import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct QuintupleValueModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("QuintupleValue") { scope in
            let value = scope.sharedVar(initial: Quintuple(
                first: 0, second: false, third: "open", fourth: 1, fifth: true))
            Do(Step.advance) {
                Assign(value, to: Quintuple.literal(
                    value.first() + 1, value.second(), value.third(),
                    value.fourth() + 1, value.fifth()))
            }
        }
    }
}
