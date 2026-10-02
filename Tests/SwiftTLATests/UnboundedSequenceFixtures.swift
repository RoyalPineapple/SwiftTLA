import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct UnboundedSequenceModel: Sendable {
    enum Step: String, CaseIterable { case append }

    static var spec: TLASpec {
        #spec("UnboundedSequence") {
            let unboundedSequence = Algorithm(label: "UnboundedSequence", scoped: { scope in
                let sequence = scope.sharedVar(in: Sequences(of: Set<Int>([1, 2])))
                Invariant("Elements") { Sequences(of: Set<Int>([1, 2])).contains(sequence) }
                Do(Step.append) {
                    Assign(sequence, to: sequence.appending(1))
                }
            })
            unboundedSequence
        }
    }
}
