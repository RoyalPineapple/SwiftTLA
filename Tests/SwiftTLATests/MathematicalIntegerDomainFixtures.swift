import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct MathematicalIntegerDomainModel: Sendable {
    enum Step: String, CaseIterable { case increment }

    static var spec: TLASpec {
        #spec("MathematicalIntegerDomain") { model in
            let Values = model.parameter(as: Set<Int>.self, in: Subsets(of: Int.all))
            let mathematicalIntegerDomain = Algorithm(label: "MathematicalIntegerDomain", scoped: { scope in
                let value = scope.sharedVar(in: Int.all)
                let copy: SharedVariable<Int> = scope.sharedVar(initial: value + 1)
                let sequence = scope.sharedVar(in: Sequences(of: Values))
                Invariant("TypeOK") {
                    Values.isSubset(of: Int.all)
                        && Int.all.contains(value)
                        && Int.all.contains(copy)
                        && Sequences(of: Int.all).contains(sequence)
                }
                Do(Step.increment) { Assign(value, to: value + 1) }
            })
            mathematicalIntegerDomain
        }
    }
}
