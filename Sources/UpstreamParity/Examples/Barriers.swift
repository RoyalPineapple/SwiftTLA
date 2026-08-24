import SwiftTLA
import SwiftTLAMacros

/// The upstream two-chamber barrier, expressed with the same PlusCal
/// statement macros (`Lock`, `Unlock`, `Wait`, and `Signal`) as its source.
@TLAModel
public struct BarriersN6Model: Sendable {
    public enum Process: Int, CaseIterable {
        case one = 1
        case two = 2
        case three = 3
        case four = 4
        case five = 5
        case six = 6

}
