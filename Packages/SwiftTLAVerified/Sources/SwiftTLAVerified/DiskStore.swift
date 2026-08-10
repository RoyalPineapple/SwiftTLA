import SwiftTLA
import SwiftTLAMacros
import Foundation

@TLAActor
public actor DiskStore {
    public static var spec: TLASpec {
        TLASpec("DiskStore") {
            let phase = Var("phase", 0)
            Variable(phase)

            Action("ready")   { phase == 0 && phase.becomes(1) }
            Action("write")   { phase == 1 && phase.stays }
            Action("delete")  { phase == 1 && phase.stays }
            Action("clear")   { phase == 1 && phase.stays }

            Invariant("validPhase") { phase >= 0 && phase <= 1 }
        }
    }

    private let dir: URL

    public init(name: String) {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/SwiftTLA/\(name)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        dir = base
        _ready()
    }

    public func write(name: String, data: Data) throws {
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
    }

    public func delete(name: String) {
        let url = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
