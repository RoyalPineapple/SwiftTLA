import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct OrderedOverflowModel {
    package enum Step: String, CaseIterable { case advance }

    package static var spec: TLASpec {
        #spec("OrderedOverflow") {
            let algorithm = Algorithm(label: "OrderedOverflow", scoped: { scope in
                let count = scope.sharedVar(initial: 9_223_372_036_854_775_806)
                Do(Step.advance) {
                    Assign(count, to: count + 1)
                    Assign(count, to: count + 1)
                }
            })
            algorithm
        }
    }
}
