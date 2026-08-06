import SwiftTLA

/// Legacy registry — delegates to Example enum.
/// Individual ports live under Sources/UpstreamParity/Examples/.
public enum ParityCatalog {
    public static let all: [Example.Entry] = Example.all
    public static var ids: [String] { all.map(\.id) }

    public static func entry(id: String) -> Example.Entry? {
        all.first { $0.id == id }
    }
}
