import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SequenceMembershipModel {
    enum Step: String, CaseIterable { case check, candidateFailure, domainFailure }

    static var spec: TLASpec {
        #spec("SequenceMembershipModel") { scope in
            let maximum = scope.parameter(as: Int.self, in: 0...100)
            let length = scope.parameter(as: Int.self, in: 0...100)
            let entry = scope.parameter(as: Int.self, in: 0...2)
            let sequence = scope.sharedVar(initial: ZeroBasedSequence<Int>.filled(length: length, with: entry))
            let result = scope.sharedVar(initial: false)
            let zero = scope.sharedVar(initial: 0)
            Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: maximum))
            Do(Step.check) {
                Assign(result, to: ZSequences.sequences(over: SetExpr<Int>.literal(0, 1)).contains(sequence))
            }
            Do(Step.candidateFailure) {
                Assign(result, to: ZSequences.sequences(over: SetExpr<Int>.literal(0, 1)).contains(
                    ZeroBasedSequence<Int>.filled(length: 1, with: 1 / zero)))
            }
            Do(Step.domainFailure) {
                Assign(result, to: ZSequences.sequences(over: SetExpr<Int>.literal(1 / zero)).contains(sequence))
            }
        }
    }
}
