import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Checked view kind mismatch")
struct CheckedViewKindMismatchTests {
    @Test("Nested collection views reject disjoint member kinds without partial predicates")
    func nestedCollectionViewsRemainTotal() {
        let set = FormalValueShape.set(.sequence(.integer))
            .predicate(for: "members", sourceType: .set(.int))
        #expect(set.contains(": FALSE"))
        #expect(!set.contains("DOMAIN _shapeMember0"))

        let function = FormalValueShape.function(key: .integer, value: .sequence(.integer))
            .predicate(for: "mapping", sourceType: .dictionary(.int, .int))
        #expect(function.contains("/\\ (FALSE)"))
        #expect(!function.contains("DOMAIN mapping[_shapeMember0]"))

        let tuple = FormalValueShape.tuple([.sequence(.integer)])
            .predicate(for: "pair", sourceType: .tuple([.int]))
        #expect(tuple.contains("/\\ (FALSE)"))
        #expect(!tuple.contains("DOMAIN pair[1]"))

        let wrongLength = FormalValueShape.tuple([.integer, .integer])
            .predicate(for: "pair", sourceType: .tuple([.int]))
        #expect(wrongLength == "FALSE")
    }

    @Test("A scalar-to-record checked view reports a matched failure without a successor")
    func scalarToRecordFailure() throws {
        var machine = try IncompatibleCheckedRecordView.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            try machine.send(.inspect)
        }
        #expect(machine.snapshot == before)

        let rendered = try IncompatibleCheckedRecordView.render()
        #expect(rendered.intrinsicInvariantNames == ["__SwiftTLAEvaluationOK"])
        let source = rendered.tlaBundle.root.tla
        #expect(!source.contains("DOMAIN count"))
        #expect(source.contains("__SwiftTLANoMatchingCaseFailure0"))
        let proofInput = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/IncompatibleCheckedRecordView.tla")
            .standardizedFileURL
        #expect(source == (try String(contentsOf: proofInput, encoding: .utf8)))
        let cfg = try #require(rendered.tlaBundle(checking: [], checkDeadlock: false).root.cfg)
        #expect(cfg.contains("INVARIANT __SwiftTLAEvaluationOK\n"))
    }

    @Test("A nested scalar-to-sequence view fails before inspecting the scalar")
    func nestedScalarToSequenceFailure() throws {
        var machine = try NestedCheckedRecordView.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            try machine.send(.inspect)
        }
        #expect(machine.snapshot == before)

        let rendered = try NestedCheckedRecordView.render()
        #expect(rendered.intrinsicInvariantNames == ["__SwiftTLAEvaluationOK"])
        let source = rendered.tlaBundle.root.tla
        #expect(!source.contains("DOMAIN record[\"nested\"]"))
        #expect(source.contains("__SwiftTLANoMatchingCaseFailure0"))
        let proofInput = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/NestedCheckedRecordView.tla")
            .standardizedFileURL
        #expect(source == (try String(contentsOf: proofInput, encoding: .utf8)))
        let cfg = try #require(rendered.tlaBundle(checking: [], checkDeadlock: false).root.cfg)
        #expect(cfg.contains("INVARIANT __SwiftTLAEvaluationOK\n"))
    }

    @Test("A sequence element's scalar-to-sequence view fails without a partial formal predicate")
    func sequenceElementKindMismatch() throws {
        var machine = try NestedCheckedSequenceView.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            try machine.send(.inspect)
        }
        #expect(machine.snapshot == before)

        let rendered = try NestedCheckedSequenceView.render()
        #expect(rendered.intrinsicInvariantNames == ["__SwiftTLAEvaluationOK"])
        let source = rendered.tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/NestedCheckedSequenceView.tla")
            .standardizedFileURL
        #expect(source == (try String(contentsOf: proofInput, encoding: .utf8)))
        let cfg = try #require(rendered.tlaBundle(checking: [], checkDeadlock: false).root.cfg)
        #expect(cfg.contains("INVARIANT __SwiftTLAEvaluationOK\n"))

        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("CheckedViewKindMismatchFixtures.swift")
        let parsed = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(parsed.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "NestedCheckedSequenceView" })
        var emitter = NativeSwiftEmitter(model: try TLASpecVerifier.parseAndVerify(declaration))
        let visitor = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text.hasPrefix("_visitUpdates") == true
                && $0.description.contains("NativeMachineEvaluationError.noMatchingCase")
        })
        let swiftInput = proofInput.deletingLastPathComponent()
            .appendingPathComponent("NestedCheckedSequenceViewSwiftVisitor.txt")
        let expectedSwift = try String(contentsOf: swiftInput, encoding: .utf8)
        func tokens(_ source: String) -> [String] {
            Parser.parse(source: source).tokens(viewMode: .sourceAccurate).map(\.text)
        }
        #expect(tokens(visitor.description) == tokens(expectedSwift))
        let unchecked = visitor.description.replacingOccurrences(
            of: "default: throw NativeMachineEvaluationError.noMatchingCase",
            with: "default: return [1]")
        #expect(unchecked != visitor.description)
        #expect(tokens(unchecked) != tokens(expectedSwift))
    }
}
