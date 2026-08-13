import Foundation
import Testing
@testable import SwiftTLA

@Suite("Formal shape contracts")
struct FormalShapeTests {
    @Test("finite maps retain declared-domain order in equality and hashing")
    func finiteMapUsesOrderedDomain() throws {
        let forward = try FiniteMap<ShapeKey, Int>(
            domain: [.first, .second],
            values: [.first: 1, .second: 2]
        )
        let reverse = try FiniteMap<ShapeKey, Int>(
            domain: [.second, .first],
            values: [.first: 1, .second: 2]
        )
        let sameForward = try FiniteMap<ShapeKey, Int>(
            domain: [.first, .second],
            values: [.second: 2, .first: 1]
        )

        #expect(forward == sameForward)
        #expect(forward != reverse)
        #expect(forward.hashValue == sameForward.hashValue)
        #expect(forward.keys == [.first, .second])
    }

    @Test("finite maps reject invalid declared domains and incomplete values")
    func finiteMapRejectsInvalidDomains() {
        #expect(throws: FormalShapeValidationError.emptyFiniteDomain) {
            _ = try DomainShape<Int>(id: "empty", name: "Empty", members: [])
        }
        #expect(throws: FormalShapeValidationError.emptyFiniteDomain) {
            _ = try FiniteMap<EmptyShapeKey, Int>(values: [:])
        }
        #expect(throws: FormalShapeValidationError.duplicateFiniteDomainMember) {
            _ = try FiniteMap<ShapeKey, Int>(
                domain: [.first, .first],
                values: [.first: 1]
            )
        }
        #expect(throws: FormalShapeValidationError.incompleteFiniteMap) {
            _ = try FiniteMap<ShapeKey, Int>(values: [.first: 1])
        }
    }

    @Test("shape contracts retain declared order and exclude provenance from equality")
    func shapesAreOrderedValueContracts() throws {
        let first = try FieldShape<ShapeRecord, Int>(id: "record.first", name: "first")
        let second = try FieldShape<ShapeRecord, String>(id: "record.second", name: "second")
        let record = try RecordShape<ShapeRecord>(
            id: "record", name: "Record", fields: [first.erased, second.erased], provenance: "first.swift:10"
        )
        let provenanceTwin = try RecordShape<ShapeRecord>(
            id: "record", name: "Record", fields: [first.erased, second.erased], provenance: "other.swift:99"
        )

        #expect(record == provenanceTwin)
        #expect(record.fields.map(\.name) == ["first", "second"])
        #expect(record.fields.map(\.typeIdentity) == [FormalTypeIdentity.of(Int.self), FormalTypeIdentity.of(String.self)])
    }

    @Test("formal type identities are stable across fresh processes")
    func formalTypeIdentityIsStableAcrossProcesses() throws {
        let first = try identityProbeOutput()
        let second = try identityProbeOutput()

        #expect(first == "example.file-private-shape-v1")
        #expect(second == first)
    }

    @Test("tagged TLA values round trip nested values and fail closed")
    func tlaValueCodecIsLosslessAndStrict() throws {
        let value: TLAValue = .function([
            .tuple([.int(1), .string("one")]): .record([
                "nested": .set([.bool(true), .constant("N")])
            ])
        ])
        let encoded = try JSONEncoder().encode(value)

        #expect(try JSONDecoder().decode(TLAValue.self, from: encoded) == value)
        #expect(throws: TLAValueCodingError.unknownTag("other")) {
            _ = try JSONDecoder().decode(TLAValue.self, from: Data(#"{"version":1,"tag":"other"}"#.utf8))
        }
        #expect(throws: TLAValueCodingError.malformedValue("int")) {
            _ = try JSONDecoder().decode(TLAValue.self, from: Data(#"{"version":1,"tag":"int"}"#.utf8))
        }
        #expect(throws: TLAValueCodingError.malformedValue("int")) {
            _ = try JSONDecoder().decode(TLAValue.self, from: Data(#"{"version":1,"tag":"int","value":1,"extra":true}"#.utf8))
        }
    }
}

private enum ShapeKey: String, FiniteDomainKey {
    case first
    case second

    static let formalDomain: [ShapeKey] = [.first, .second]
    static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.shape-key-v1")
    var tlaValue: TLAValue { .string(rawValue) }
}

private enum EmptyShapeKey: String, FiniteDomainKey {
    case placeholder

    static let formalDomain: [EmptyShapeKey] = []
    static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.empty-shape-key-v1")
    var tlaValue: TLAValue { .string(rawValue) }
}

private struct ShapeRecord: FormalValue {
    static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.shape-record-v1")

    var tlaValue: TLAValue { .record([:]) }
}

private func identityProbeOutput() throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let productDirectory = Bundle.main.bundleURL.deletingLastPathComponent()
    let candidates = [
        productDirectory.appendingPathComponent("FormalTypeIdentityProbe"),
        root.appendingPathComponent(".build/debug/FormalTypeIdentityProbe")
    ]
    guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
        throw IdentityProbeError.missingExecutable
    }
    let output = Pipe()
    let probe = Process()
    probe.currentDirectoryURL = root
    probe.executableURL = executable
    probe.standardOutput = output
    try probe.run()
    probe.waitUntilExit()
    guard probe.terminationStatus == 0 else {
        throw IdentityProbeError.executionFailed(probe.terminationStatus)
    }
    return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private enum IdentityProbeError: Error {
    case missingExecutable
    case executionFailed(Int32)
}
