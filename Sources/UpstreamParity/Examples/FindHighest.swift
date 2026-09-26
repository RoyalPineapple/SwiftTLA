import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct FindHighestModel: Sendable {
    private enum Step: String, CaseIterable {
        case lb
    }

    package static var spec: TLASpec {
        #spec("Highest") { model in
            Extends(.integers)
            let MaxLength = model.parameter(as: Int.self, in: 3...3)
            let MaxNat = model.parameter(as: Int.self, in: 4...4)
            let TypeOK = Invariant()
            let InductiveInvariant = Invariant()
            let DoneIndexValue = Invariant()
            let Correctness = Invariant()
            Algorithm("Highest", scoped: { scope in
                let f = scope.sharedVar(in: Sequences(
                    of: IntRange(0, through: MaxNat),
                    lengths: IntRange(0, through: MaxNat)
                ))
                let h = scope.sharedVar(initial: -1)
                let i = scope.sharedVar(initial: 1)

                While(Step.lb, i <= f.count) {
                    Assign(h, to: If(h >= f[i], then: h, else: f[i]))
                    Assign(i, to: i + 1)
                }

                StateConstraint(f.count <= MaxLength)
                TypeOK {
                    f.count <= MaxNat
                    ForAll(in: IntRange(1, through: f.count)) { index in
                        f[index] >= 0 && f[index] <= MaxNat
                    }
                    i >= 1 && i <= f.count + 1 && i <= MaxNat
                    h >= -1 && h <= MaxNat
                }
                InductiveInvariant {
                    ForAll(in: IntRange(1, through: i - 1)) { index in
                        f[index] <= h
                    }
                }
                DoneIndexValue {
                    (!Finished()) || i == f.count + 1
                }
                Correctness {
                    (!Finished()) || ForAll(in: IntRange(1, through: f.count)) { index in
                        f[index] <= h
                    }
                }
            })
            Validation("MCFindHighest") {
                Bind(MaxLength, to: 3)
                Bind(MaxNat, to: 4)
            }
        }
    }
}
