import SwiftTLA
import SwiftTLAMacros

/// The `Increase` algorithm from the upstream LearnProofs `AddTwo` module.
///
/// The original PlusCal loop has one transition: add two and repeat. Its
/// proof names two useful state properties: the value never becomes negative
/// and it remains even. The upstream module has no finite TLC configuration,
/// so this source-faithful model is checked by the builder/parser fidelity
/// gate rather than added to the finite graph-count catalogue.
@TLAModel
public struct AddTwoModel: Sendable {
    private enum Label: String, PlusCalLabel, CaseIterable {
        case increase
    }

    public static var spec: TLASpec {
        #spec("AddTwo") {
            Extends(.naturals)
            Algorithm("Increase", scoped: { scope in
                let x = scope.sharedVar("x", initial: 0)

                Do(Label.increase) {
                    Assign(x, to: x + 2)
                    Goto(Label.increase)
                }

                // The published source has no TLC configuration. Keep this
                // exploration limit explicit and separate from its proofs.
                StateConstraint(x < 10)
                Invariant("TypeOK") { x >= 0 }
                Invariant("Even") { x % 2 == 0 }
            })
        }
    }
}
