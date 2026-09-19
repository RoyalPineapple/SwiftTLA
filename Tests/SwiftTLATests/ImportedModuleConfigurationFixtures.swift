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

@TLAModel
struct ConfiguredSequenceMachine {
    enum Step: String, CaseIterable { case rotate }

    static var spec: TLASpec {
        #spec("ConfiguredSequenceMachine") { scope in
            let maximum = scope.parameter(as: Int.self, in: 0...2)
            let lengthPreserved = Invariant()
            let rotationsPreserveLength = Invariant()
            Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: maximum))
            Algorithm("Worker", scoped: { algorithm in
                let sequence = algorithm.sharedVar(in: ZSequences.sequences(over: Set<Int>([0, 1])))
                let length = algorithm.sharedVar(initial: ZSequences.length(of: sequence))
                Do(Step.rotate) {
                    Assign(sequence, to: ZSequences.rotation(of: sequence, leftBy: 1))
                }
                lengthPreserved { ZSequences.length(of: sequence) == length }
                rotationsPreserveLength {
                    ForAll(in: ZSequences.rotations(of: sequence)) { rotation in
                        ZSequences.length(of: rotation.seq) == length && rotation.shift >= 0
                    }
                }
            })
            Validation("Empty") { Bind(maximum, to: 0) }
            Validation("Pairs") { Bind(maximum, to: 2) }
        }
    }
}
