import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SetStepMachine {
    enum Step: String, CaseIterable { case add, remove }

    static var spec: TLASpec {
        #spec("SetStepMachine") { scope in
            let seen = scope.sharedVar(initial: Set<Int>())
            Do(Step.add) { Assign(seen, to: seen.inserting(1)) }
            Do(Step.remove) {
                When(seen.contains(1))
                Assign(seen, to: seen.removing(1))
            }
            let bounded = Invariant()
            bounded { seen.isEmpty || seen.contains(1) }
        }
    }
}

@TLAModel
struct ArrayStepMachine {
    enum Step: String, CaseIterable { case append }

    static var spec: TLASpec {
        #spec("ArrayStepMachine") { scope in
            let values = scope.sharedVar(initial: [Int]())
            Do(Step.append) {
                When(values.count < 2)
                Assign(values, to: values.appending(1))
            }
            let bounded = Invariant()
            bounded { values.count <= 2 }
        }
    }
}

@TLAModel
struct SequenceConcatenationMachine {
    enum Step: String, CaseIterable { case combine }

    static var spec: TLASpec {
        #spec("SequenceConcatenationMachine") { scope in
            let front = scope.sharedVar(initial: [Int]([1]))
            let back = scope.sharedVar(initial: [Int]([2, 2]))
            Do(Step.combine) {
                When(front.count == 1)
                Assign(front, to: front.concatenating(back))
            }
            let bounded = Invariant()
            bounded { front.count <= 3 && back.count == 2 }
        }
    }
}

@TLAModel
struct FiniteInitialStepMachine {
    enum Step: String, CaseIterable { case prepare }

    static var spec: TLASpec {
        #spec("FiniteInitialStepMachine") { scope in
            let phase = scope.sharedVar(in: Set<Int>([1, 2]))
            Do(Step.prepare) {
                When(phase == 1)
                Assign(phase, to: 2)
            }
            let knownPhase = Invariant()
            knownPhase { phase == 1 || phase == 2 }
        }
    }
}
