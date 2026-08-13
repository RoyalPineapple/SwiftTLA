extension TLASpec {
    /// The deterministic text formats that SwiftTLA can render without invoking TLC.
    public enum ExportFormat: String, CaseIterable, Sendable {
        /// A complete TLA+ module suitable for SANY or TLC.
        case tla

        /// The TLC configuration paired with a TLA+ module.
        case cfg

        /// Compatibility spelling for callers that name the TLA+ module explicitly.
        public static let tlaModule = Self.tla

        /// Compatibility spelling for callers that name the TLC configuration explicitly.
        public static let tlaCfg = Self.cfg
    }

    /// Renders an export format in-process. Rendering is deterministic and performs no I/O.
    public func export(_ format: ExportFormat) -> String {
        switch format {
        case .tla:
            tlaModule
        case .cfg:
            tlaCfg
        }
    }
}
