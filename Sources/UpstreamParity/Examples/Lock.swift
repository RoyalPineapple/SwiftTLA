import SwiftTLA
import SwiftTLAMacros

/// The two-process lock example from the PlusCal auxiliary-variables
/// collection. `l2` explicitly returns to `l0`, mirroring the source loop.
@TLAModel
public struct LockModel: Sendable {
    public enum Process: Int, CaseIterable {
        case one = 1
        case two = 2

}
