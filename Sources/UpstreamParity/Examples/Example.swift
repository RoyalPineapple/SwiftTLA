import SwiftTLA

/// Namespace for upstream parity ports.
/// Each port lives in its own file and extends this enum.
public enum Example {
    public struct Entry: Sendable {
        public let id: String
        public let upstreamSpec: String
        public let upstreamModule: String
        public let upstreamCfg: String?
        public let expectedDistinct: Int
        public let expectedResult: String
        public let spec: TLASpec
        public let notes: String
        public let matchesUpstreamTLC: Bool
        public init(id: String, upstreamSpec: String, upstreamModule: String, upstreamCfg: String?,
                    expectedDistinct: Int, expectedResult: String, spec: TLASpec,
                    notes: String, matchesUpstreamTLC: Bool) {
            self.id = id; self.upstreamSpec = upstreamSpec; self.upstreamModule = upstreamModule
            self.upstreamCfg = upstreamCfg; self.expectedDistinct = expectedDistinct
            self.expectedResult = expectedResult; self.spec = spec; self.notes = notes
            self.matchesUpstreamTLC = matchesUpstreamTLC
        }
    }
    public static let all: [Entry] = []
}
