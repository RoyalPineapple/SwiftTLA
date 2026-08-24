import Foundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct DiskStoreModel {
    public enum Phase: String, CaseIterable {
        case ready
                Each(WriteProcess.all) { _ in Do(Step.write) { When(phase == .ready); Assign(phase, to: Phase.ready); Goto(Step.write) } }
                Each(DeleteProcess.all) { _ in Do(Step.delete) { When(phase == .ready); Assign(phase, to: Phase.ready); Goto(Step.delete) } }
                Each(ClearProcess.all) { _ in Do(Step.clear) { When(phase == .ready); Assign(phase, to: Phase.ready); Goto(Step.clear) } }
                Invariant("diskStoreReady") { phase == .ready }
            })
        }
    }
    @TLAActor public actor Machine {}
}

public actor DiskStore {
    private let machine = DiskStoreModel.Machine()
    private let dir: URL
    public init(name: String) {
        dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/SwiftTLA/\(name)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    public func write(name: String, data: Data) async throws { _ = try? await machine.send(.write); try data.write(to: dir.appendingPathComponent(name)) }
    public func delete(name: String) async { _ = try? await machine.send(.delete); try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
    public func clear() async { _ = try? await machine.send(.clear); try? FileManager.default.removeItem(at: dir); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
}
