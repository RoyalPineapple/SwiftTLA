import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct RefinementScenarioCounter {
    package enum Step: String, CaseIterable { case advance }

    package static var spec: TLASpec {
        #spec { scope in
            let stride = scope.parameter(as: Int.self, in: 1...2)
            let bounded = Invariant()
            let abstract = TLASpec("UnitCounter") {
                Algorithm("UnitLoop", scoped: { scope in
                    let value = scope.sharedVar(initial: 0)
                    While(Step.advance, true) {
                        When(value < 2)
                        Assign(value, to: value + 1)
                    }
                })
            }
            let Loop = Algorithm(scoped: { scope in
                let count = scope.sharedVar(initial: 0)
                While(Step.advance, true) {
                    When(count < 2)
                    Assign(count, to: count + stride)
                }
                bounded { count <= 3 }
            })
            Loop
            let target = Instance("Target", of: abstract)
            target
            let UnitSteps = Refinement(instance: target,
                mappings: [.init(Var<Int>("value"), from: StateExpr.variable("count"))],
                label: "Unit-step behavior")
            UnitSteps
            let unitSteps = Validation(label: "Unit steps") { Bind(stride, to: 1) }
                .expectDeadlock(.violated)
            unitSteps
            let skippedStep = Validation(label: "Skipped step") { Bind(stride, to: 2) }
                .expect(UnitSteps, .violated)
                .expectDeadlock(.violated)
            skippedStep
        }
    }
}
