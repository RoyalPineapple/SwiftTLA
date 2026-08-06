import SwiftTLA
import SwiftTLAModels

/// Back-compat wrapper — prefer `BFSExplorer.spec`.
public func createBFSExplorerSpec() -> TLASpec {
    BFSExplorer.spec
}
