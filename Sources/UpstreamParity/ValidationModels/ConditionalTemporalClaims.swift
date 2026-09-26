import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ConditionalTemporalClaims {
    package enum Step: String, CaseIterable { case converge }

    package static var spec: TLASpec {
        #spec("ConditionalTemporalClaims") { scope in
            let startsHere = Temporal()
            let missesOtherInitial = Temporal()
            Algorithm("Converge", fairness: .weak, scoped: { algorithm in
                let value = algorithm.sharedVar(in: 0...1)
                Do(Step.converge) {
                    Assign(value, to: 2)
                    Goto(Step.converge)
                }
                startsHere(.conditional(value == 0,
                    then: .all([.eventually(value == 0), .eventuallyAlways(value == 2),
                        (value == 0).leadsTo(value == 2)]),
                    else: .conditional(value == 1,
                        then: .eventually(value == 1), else: .always(false))))
                missesOtherInitial(.conditional(value == 0,
                    then: .eventually(value == 1), else: .eventually(value == 2)))
            })
            Validation("Merged paths") {}.expect(missesOtherInitial, .violated)
        }
    }
}
