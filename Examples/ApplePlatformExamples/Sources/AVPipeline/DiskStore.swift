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
    private enum WriteProcess: String, FiniteDomainKey { case writeEvent; static let formalDomain: [Self] = [.writeEvent]; static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.disk-store.write"); var tlaValue: TLAValue { .string(rawValue) } }
    private enum DeleteProcess: String, FiniteDomainKey { case deleteEvent; static let formalDomain: [Self] = [.deleteEvent]; static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.disk-store.delete"); var tlaValue: TLAValue { .string(rawValue) } }
    private enum ClearProcess: String, FiniteDomainKey { case clearEvent; static let formalDomain: [Self] = [.clearEvent]; static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.disk-store.clear"); var tlaValue: TLAValue { .string(rawValue) } }
    private enum Step: String, PlusCalLabel { case write, delete, clear }
    public static var spec: TLASpec {
        #spec("DiskStoreModel") {
            Algorithm("DiskStoreModel") {
                let phase = SharedVar(initial: Phase.ready)
                Each(WriteProcess.all) { _ in Do(Step.write) { When(phase == .ready); Assign(phase, to: Phase.ready); Goto(Step.write) } }
                Each(DeleteProcess.all) { _ in Do(Step.delete) { When(phase == .ready); Assign(phase, to: Phase.ready); Goto(Step.delete) } }
                Each(ClearProcess.all) { _ in Do(Step.clear) { When(phase == .ready); Assign(phase, to: Phase.ready); Goto(Step.clear) } }
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
    public func write(name: String, data: Data) async throws { _ = try? await machine.apply(.write); try data.write(to: dir.appendingPathComponent(name)) }
    public func delete(name: String) async { _ = try? await machine.apply(.delete); try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
    public func clear() async { _ = try? await machine.apply(.clear); try? FileManager.default.removeItem(at: dir); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
}
