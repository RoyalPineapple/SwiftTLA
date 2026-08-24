import SwiftTLA
import SwiftTLAMacros

/// Dijkstra's original mutual-exclusion algorithm, bounded to the four
/// processes in the published LSpec model.
///
/// `temporary` begins as the upstream model's opaque `defaultInitValue`.
/// It then holds either the current owner or the set of peers still to
/// inspect. `OneOf` keeps that source-level TLA+ union explicit in Swift
/// without changing its formal representation.
@TLAModel
public struct DijkstraMutexModel: Sendable {
    public enum Process: String, CaseIterable {
        case one = "p1"
        case two = "p2"
        case three = "p3"

}
