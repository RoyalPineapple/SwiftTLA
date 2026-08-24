import SwiftTLA
import SwiftTLAMacros

/// The two-switch prisoner puzzle.
///
/// The scheduler makes the nondeterministic visitor choice explicit. The
/// shared switch state and per-prisoner signal counts are typed formal values.
@TLAModel
public struct PrisonersModel: Sendable {
    public enum NonCounterPrisoner: String, CaseIterable {
        case two = "p2"
        case three = "p3"
        case four = "p4"

}
