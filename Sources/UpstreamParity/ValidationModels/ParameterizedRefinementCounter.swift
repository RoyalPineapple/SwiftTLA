import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ParameterizedRefinementCounter {
    package enum Step: String, CaseIterable {
        case advance
    }

    package static var spec: TLASpec {
        #spec("ParameterizedRefinementCounter") { scope in
            let limit = scope.parameter(as: Int.self, in: 1...2)
            let abstract = TLASpec("ParameterizedAbstractCounter") {
                let abstractValue = Var<Int>("abstractValue")
                Parameter("Limit")
                let abstractLimit = Var<Int>("Limit")
                Variable(abstractValue, abstractLimit)
                SwiftTLA.Action("advance") {
                    abstractValue.becomes(abstractValue + 1).when(abstractValue < abstractLimit + 1)
                }
            }
            let count = scope.sharedVar(initial: limit + 1)
            Do(Step.advance, when: count < limit + 2) {
                Assign(count, to: count + 1)
            }
            let target = Instance("Target", of: abstract)
            target
            let Refines = Refinement(instance: target, mappings: [
                .init(FormalModuleParameter("Limit"), from: limit + 1),
                .init(Var<Int>("abstractValue"), from: count)
            ])
            Refines
            let limitOne = Validation(label: "Limit one") { Bind(limit, to: 1) }
                .expectDeadlock(.violated)
            limitOne
            let limitTwo = Validation(label: "Limit two") { Bind(limit, to: 2) }
                .expectDeadlock(.violated)
            limitTwo
        }
    }
}
