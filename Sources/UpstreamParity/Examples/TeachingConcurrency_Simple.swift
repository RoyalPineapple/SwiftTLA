import SwiftTLA
import SwiftTLAMacros

/// Two bounded instances of the upstream `Simple` PlusCal algorithm.
///
/// The upstream model has one `x` and one `y` function, indexed by the
/// process identifier. `Each` lowers to exactly that function-shaped state
/// and its generated `pc` function; the Swift source does not unroll a
/// separate action or program counter for every process.
public struct TeachingSimpleN2Model: Sendable {
    public enum Process: Int, CaseIterable, FiniteTLAValueDomain {
        case p0
        case p1

        public static var defaultValue: Self { .p0 }
        public static let finiteValues = allCases
}
