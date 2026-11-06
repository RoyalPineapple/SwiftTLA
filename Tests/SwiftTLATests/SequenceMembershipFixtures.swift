import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SequenceMembershipModel {
    enum Step: String, CaseIterable { case check, candidateFailure, domainFailure }

    static var spec: TLASpec {
        #spec("SequenceMembershipModel") { scope in
            let maximum = scope.parameter(as: Int.self, in: 0...100)
            let length = scope.parameter(as: Int.self, in: 0...100)
            let __zeroBasedSequenceIndex_1 = scope.parameter(as: Int.self, in: 0...2)
            let __zeroBasedSequenceIndex = scope.sharedVar(initial: 0)
            let sequence = scope.sharedVar(initial: If(length == 2,
                then: ZeroBasedSequence<Int>.literal(__zeroBasedSequenceIndex_1 + __zeroBasedSequenceIndex,
                    __zeroBasedSequenceIndex_1 + __zeroBasedSequenceIndex + 1),
                else: ZeroBasedSequence<Int>.filled(length: length, with: __zeroBasedSequenceIndex_1 + __zeroBasedSequenceIndex)))
            let result = scope.sharedVar(initial: false)
            Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: maximum))
            Do(Step.check) {
                Assign(result, to: ZSequences.sequences(over: Set<Int>([0, 1])).contains(sequence))
            }
            Do(Step.candidateFailure) {
                Assign(result, to: ZSequences.sequences(over: Set<Int>([0, 1])).contains(
                    ZeroBasedSequence<Int>.filled(length: 1, with: 1 / __zeroBasedSequenceIndex)))
            }
            Do(Step.domainFailure) {
                Assign(result, to: ZSequences.sequences(over: Set<Int>([]).inserting(1 / __zeroBasedSequenceIndex)).contains(sequence))
            }
        }
    }
}
