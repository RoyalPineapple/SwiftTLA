import Foundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct DiskStoreModel {
    public enum Phase: String, CaseIterable, FiniteTLAValueDomain {
        case ready
        public static var defaultValue: Self { .ready }
        public static let finiteValues = allCases
        public var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum WriteProcess: String, FiniteTLAValueDomain { case writeEvent; static var defaultValue: Self { .writeEvent }; static let finiteValues: [Self] = [.writeEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum DeleteProcess: String, FiniteTLAValueDomain { case deleteEvent; static var defaultValue: Self { .deleteEvent }; static let finiteValues: [Self] = [.deleteEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum ClearProcess: String, FiniteTLAValueDomain { case clearEvent; static var defaultValue: Self { .clearEvent }; static let finiteValues: [Self] = [.clearEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum Step: String, CaseIterable { case write, delete, clear }
    public static var spec: TLASpec {
        #spec("DiskStoreModel") {
            Algorithm("DiskStoreModel", scoped: { scope in
                let phase = scope.sharedVar("phase", initial: Phase.ready)
                Each(WriteProcess.all) { _ in Do(Step.write) { When(phase == .ready); Assign(phase, to: Phase.ready); Goto(Step.write) } }
                Each(DeleteProcess.all) { _ in Do(Step.delete) { When(phase == .ready); Assign(phase, to: Phase.ready); Goto(Step.delete) } }
                Each(ClearProcess.all) { _ in Do(Step.clear) { When(phase == .ready); Assign(phase, to: Phase.ready); Goto(Step.clear) } }
                Invariant("diskStoreReady") { phase == .ready }
            })
        }
    }
}

public actor DiskStore {
    private var machine: DiskStoreModel
    private let dir: URL

    public init(name: String) throws {
        machine = try DiskStoreModel.makeMachine()
        dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/SwiftTLA/\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    public func write(name: String, data: Data) async throws {
        _ = try machine.send(.write)
        try data.write(to: dir.appendingPathComponent(name))
    }

    public func delete(name: String) async throws {
        _ = try machine.send(.delete)
        try FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }

    public func clear() async throws {
        _ = try machine.send(.clear)
        try FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
