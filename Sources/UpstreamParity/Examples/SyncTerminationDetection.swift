import SwiftTLA
import SwiftTLAMacros

/// The three-node bounded termination detector from EWD 840.
@TLAModel
public struct SyncTerminationDetectionModel: Sendable {
    public enum Node: Int, CaseIterable {
        case zero = 0
        case one = 1
        case two = 2

}
