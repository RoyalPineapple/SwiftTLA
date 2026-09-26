import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct MathematicalIntegerDomainModel: Sendable {
    enum Step: String, CaseIterable { case increment }

    static var spec: TLASpec {
        #spec("MathematicalIntegerDomain") { model in
            let Values = model.parameter(as: Set<Int>.self, in: Subsets(of: Int.all))
            Algorithm("MathematicalIntegerDomain", scoped: { scope in
                let value = scope.sharedVar(in: Int.all)
                let sequence = scope.sharedVar(in: Sequences(of: Values))
                Invariant("TypeOK") {
                    Values.isSubset(of: Int.all)
                        && Int.all.contains(value)
                        && Sequences(of: Int.all).contains(sequence)
                }
                Do(Step.increment) { Assign(value, to: value + 1) }
            })
        }
    }
}
