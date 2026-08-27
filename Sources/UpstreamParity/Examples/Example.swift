import SwiftTLA

package enum Example {
    package struct Entry: Sendable {
        package let id: String
        package let upstreamSpec: String
        package let upstreamModule: String
        package let upstreamCfg: String?
        package let expectedDistinct: Int
        package let maximumStateLimit: Int
        package let spec: TLASpec
        package let notes: String

        package init(id: String, upstreamSpec: String, upstreamModule: String, upstreamCfg: String?,
                    expectedDistinct: Int, maximumStateLimit: Int,
                    spec: TLASpec, notes: String) {
            self.id = id; self.upstreamSpec = upstreamSpec; self.upstreamModule = upstreamModule
            self.upstreamCfg = upstreamCfg; self.expectedDistinct = expectedDistinct
            self.maximumStateLimit = maximumStateLimit
            self.spec = spec; self.notes = notes
        }
    }
}
