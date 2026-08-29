import SwiftTLA
import SwiftTLAMacros

/// The `Increase` algorithm from the upstream LearnProofs `AddTwo` module.
///
/// The original PlusCal loop has one transition: add two and repeat. Its
/// proof requires two state properties: the value is nonnegative and even.
/// The upstream module has no finite TLC configuration,
/// so this source-faithful model is checked by the builder/parser fidelity
/// gate.
@TLAModel
package struct AddTwoModel: Sendable {
    private enum Label: String, CaseIterable {
        case increase
    }

    package static var spec: TLASpec {
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
