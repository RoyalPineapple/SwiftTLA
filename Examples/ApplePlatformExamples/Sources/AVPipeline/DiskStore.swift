import Foundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct DiskStoreModel {
    public enum Phase: String, CaseIterable, FiniteDomainKey {
        case ready
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.disk-store-phase")
        public var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum Process: String, FiniteDomainKey { case diskEvent
        static let formalDomain: [Self] = [.diskEvent]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.disk-store-process")
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum Step: String, PlusCalLabel { case write, delete, clear }
    public static var spec: TLASpec {
        #spec("DiskStoreModel") {
            Algorithm("DiskStoreModel") {
                let phase = SharedVar(initial: Phase.ready)
                Each(Process.all) { _ in
                    Do(Step.write) { When(phase == .ready); Assign(phase, to: Phase.ready); Goto(Step.write) }
                    Do(Step.delete) { When(phase == .ready); Assign(phase, to: Phase.ready); Goto(Step.delete) }
                    Do(Step.clear) { When(phase == .ready); Assign(phase, to: Phase.ready); Goto(Step.clear) }
                }
                Invariant("diskStoreReady") { phase == .ready }
            }
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
    public func write(name: String, data: Data) async throws { _ = try? await machine.execute(DiskStoreModel.Machine.ActionLabel.write.toInvocation()); try data.write(to: dir.appendingPathComponent(name)) }
    public func delete(name: String) async { _ = try? await machine.execute(DiskStoreModel.Machine.ActionLabel.delete.toInvocation()); try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
    public func clear() async { _ = try? await machine.execute(DiskStoreModel.Machine.ActionLabel.clear.toInvocation()); try? FileManager.default.removeItem(at: dir); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
}
