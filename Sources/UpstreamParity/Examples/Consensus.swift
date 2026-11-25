import SwiftTLA
import SwiftTLAMacros

/// The three-value PlusCal consensus model from the Byzantine Paxos example.
///
/// The model states the core safety boundary: one nondeterministically
/// selected value may be chosen, and every execution preserves that choice.
/// The source uses a parameterless `Choose()` macro, a guarded `when`, and a
/// scoped `with`.
@TLAModel
package struct ConsensusModel: Sendable {
    package enum Choice: String, CaseIterable, FiniteTLAValueDomain {
        case one = "v1"
        case two = "v2"
        case three = "v3"

        package static var defaultValue: Self { .one }
        package static let finiteValues = allCases

        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    private enum Step: String, CaseIterable {
        // TLC exposes the translated single loop body as Next.
        case choose = "Next"
    }

    package static var spec: TLASpec {
        #spec("Consensus") { configuration in
            Extends(.finiteSets)
            Extends(.integers)
            let Value = configuration.parameter(as: Set<Choice>.self, in: Set<Set<Choice>>([Set([.one, .two, .three])]))
            let Consensus = Algorithm(fairness: .weak) { scope in
                let chosen = scope.sharedVar(initial: Set<Choice>())

                let choose = Macro {
                    When(chosen.isEmpty)
                    With(Value) { value in
                        chosen.insert(value)
                    }
                }

                Loop(Step.choose) {
                    choose()
                }

                let wellTyped = chosen.isSubset(of: Value)
                Invariant("TypeOK") { wellTyped }
                Invariant("Inv") {
                    wellTyped
                    chosen.count <= 1
                }
                Eventually("Success", !chosen.isEmpty)
            }
            Consensus
            Validation("published", label: "Consensus") {
                Bind(Value, to: Set<Choice>([.one, .two, .three]))
            }.checkingDeadlock(false)
        }
    }
}

extension Example {
    package static let consensus = FiniteModelFixture(
        expectedDistinct: 4,
        maximumStateLimit: 50_000,
        spec: ConsensusModel.spec,
    )
}
