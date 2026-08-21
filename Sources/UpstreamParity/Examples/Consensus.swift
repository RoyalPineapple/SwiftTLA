import SwiftTLA
import SwiftTLAMacros

/// The published PlusCal consensus safety model.
///
/// This is intentionally not a consensus protocol implementation. It states
/// the core safety boundary: one nondeterministically selected value may be
/// chosen, and no execution can choose a second value. The source uses a
/// parameterless `Choose()` macro, a guarded `when`, and a scoped `with`.
@TLAModel
public struct ConsensusModel: Sendable {
    public enum Value: String, CaseIterable, FiniteDomainKey {
        case one = "v1"
        case two = "v2"
        case three = "v3"

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(
            rawValue: "upstream.byzpaxos.consensus.value"
        )

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, PlusCalLabel {
        case choose = "lbl"
    }

    public static var spec: TLASpec {
        #spec("Consensus") {
            Extends("FiniteSets")
            Extends("Integers")
            Algorithm("Consensus") {
                let chosen = SharedVar(initial: SetExpr<Value>())

                let choose = Macro {
                    When(chosen.isEmpty)
                    With(Value.all) { value in
                        Assign(chosen, to: chosen.inserting(value))
                    }
                }

                While(Step.choose, true) {
                    choose()
                }

                Invariant("TypeOK") {
                    chosen.isSubset(of: SetExpr<Value>.literal(.one, .two, .three))
                }
                Invariant("Inv") {
                    chosen.cardinality <= 1
                }
                Eventually("Success", !chosen.isEmpty)
                WeakFairnessNext()
            }
        }
    }
}

extension Example {
    public static let consensus = Entry(
        id: "byzpaxos/Consensus",
        upstreamSpec: "byzpaxos",
        upstreamModule: "specifications/byzpaxos/Consensus.tla",
        upstreamCfg: "specifications/byzpaxos/Consensus.cfg",
        expectedDistinct: 4,
        spec: ConsensusModel.spec,
        notes: "Published PlusCal consensus safety model with Value = {v1, v2, v3}."
    )
}
