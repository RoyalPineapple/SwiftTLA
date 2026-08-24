import SwiftTLA
import SwiftTLAMacros

/// The bounded N=2 instance of Lamport's PlusCal Bakery algorithm.
///
/// The source algorithm is authored as one fair process family. The lowerer
/// creates the function-shaped process-local state and program counter that
/// the upstream PlusCal translator creates.
@TLAModel
public struct BakeryN2Model: Sendable {
    public enum Process: Int, CaseIterable {
        case one = 1
        case two = 2

}
