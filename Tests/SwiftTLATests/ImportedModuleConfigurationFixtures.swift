import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ConfiguredModuleMachine {
    enum Step: String, CaseIterable { case keep }

    static var spec: TLASpec {
        #spec("ConfiguredModuleMachine") { scope in
            let maximum = scope.parameter(as: Int.self, in: 0...3)
            Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: maximum))
            Algorithm("Worker", scoped: { algorithm in
                let value = algorithm.sharedVar(initial: maximum)
                Do(Step.keep) { Assign(value, to: value) }
            })
            Validation("Zero") { Bind(maximum, to: 0) }
            Validation("Three") { Bind(maximum, to: 3) }
        }
    }
}
