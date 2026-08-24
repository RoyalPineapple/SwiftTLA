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
    public enum Value: String, CaseIterable {
        case one = "v1"
        case two = "v2"
        case three = "v3"

}
