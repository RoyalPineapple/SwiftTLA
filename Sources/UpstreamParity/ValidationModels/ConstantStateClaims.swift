import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ConstantStateClaims {
    package enum Step: String, CaseIterable { case stay }

    package static var spec: TLASpec {
        #spec("ConstantStateClaims") { scope in
            let enabled = scope.parameter(as: Bool.self)
            let trueInvariant = Invariant()
            let falseInvariant = Invariant()
            let initialWitness = Reachable()
            let absentWitness = Reachable()
            let configuredWitness = Reachable()
            Algorithm("Loop", scoped: { algorithm in
                let value = algorithm.sharedVar(initial: 0)
                Do(Step.stay) {
                    Assign(value, to: value)
                    Goto(Step.stay)
                }
            })
            trueInvariant { true }
            falseInvariant { false }
            initialWitness { true }
            absentWitness { false }
            configuredWitness { enabled }
            Validation("Enabled") { Bind(enabled, to: true) }
                .expect(falseInvariant, .violated)
                .expect(absentWitness, .violated)
            Validation("Disabled") { Bind(enabled, to: false) }
                .expect(falseInvariant, .violated)
                .expect(absentWitness, .violated)
                .expect(configuredWitness, .violated)
        }
    }
}
