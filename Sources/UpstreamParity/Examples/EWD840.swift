import SwiftTLA
import SwiftTLAMacros

/// Dijkstra's three-node termination detector from EWD 840.
@TLAModel
public struct EWD840Model: Sendable {
    public enum Node: Int, CaseIterable {
        case zero = 0
        case one = 1
        case two = 2

}
