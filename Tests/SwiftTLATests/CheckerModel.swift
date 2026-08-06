import SwiftTLA

/// Back-compat wrapper — prefer `TLASpec.bfsChecker(maxStates:)`.
public func createCheckerSpec(maxStates: Int = 20) -> TLASpec {
    .bfsChecker(maxStates: maxStates)
}
