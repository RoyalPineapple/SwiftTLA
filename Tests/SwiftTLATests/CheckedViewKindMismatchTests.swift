import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Checked view kind mismatch")
struct CheckedViewKindMismatchTests {
    @Test("A tuple viewed as a sequence preserves field order and checks every element")
    func tupleSequenceView() throws {
        var machine = try CheckedTupleSequence.makeMachine()
        try machine.send(.copy)
        #expect(machine.state.items == [.first(3), .second(true)])
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            try machine.send(.copyIntegers)
        }
        #expect(machine.snapshot == before)
    }

    @Test("Only total field checks on a stable record can use record-set membership")
    func recordMembershipPreservesReachedFailures() throws {
        let shape = FormalValueShape.record([.init(name: "tag", shape: .finite(typeName: "Tag", values: [.int(1)])),
            .init(name: "balance", shape: .integer)])
        func predicate(_ balance: CompiledValueType, group: Bool) throws -> String {
            let source = CompiledValueType.record([.init(name: "tag", type: .int), .init(name: "balance", type: balance)])
            return try shape.predicate(for: "r", sourceType: source, recordInput: group ? source : nil)
        }
        #expect(try predicate(.int, group: true).contains(#"r \in [tag: {1}, balance: Int]"#))
        let fields = CompiledValueType.record([.init(name: "tag", type: .int), .init(name: "balance", type: .int)])
        let distinctKeys = CompiledValueType.oneOf(.record([.init(name: "other", type: .unknown)]), fields)
        #expect(try shape.predicate(for: "r", sourceType: distinctKeys, recordInput: distinctKeys)
            .contains(#"r \in [tag: {1}, balance: Int]"#))
        let uncertain = CompiledValueType.oneOf(.dictionary(.string, .unknown), fields)
        #expect(try shape.predicate(for: "r", sourceType: uncertain, recordInput: uncertain)
            == shape.predicate(for: "r", sourceType: uncertain))
        // A rejected tag must still short-circuit a potentially invalid integer membership.
        #expect(try predicate(.unknown, group: true) == predicate(.unknown, group: false))
        #expect(try !predicate(.int, group: false).contains("balance: Int"))
    }

    @Test("A checked record may carry variants distinguished by their field names")
    func checkedRecordVariants() {
        let debit = FormalValueShape.record([.init(name: "amount", shape: .integer)])
        let credit = FormalValueShape.record([.init(name: "account", shape: .string)])
        let payload = FormalValueShape.union(debit, credit)
        let envelope = FormalValueShape.record([.init(name: "block", shape: payload)])
        #expect(envelope.isSupported)
        #expect(envelope.accepts(CompiledValue(formal: .record(["block": .record(["amount": .int(1)])]))))
        #expect(envelope.accepts(CompiledValue(formal: .record(["block": .record(["account": .string("a")])]))))
        #expect(!envelope.accepts(CompiledValue(formal: .record(["block": .record(["previous": .int(1)])]))))
        #expect(!FormalValueShape.union(debit, .sequence(.integer)).isSupported)
    }

    @Test("Nested collection views reject disjoint member kinds without partial predicates")
    func nestedCollectionViewsRemainTotal() throws {
        let set = try FormalValueShape.set(.sequence(.integer))
            .predicate(for: "members", sourceType: .set(.int))
        #expect(set.contains(": FALSE"))
        #expect(!set.contains("DOMAIN _shapeMember0"))

        let function = try FormalValueShape.function(key: .integer, value: .sequence(.integer))
            .predicate(for: "mapping", sourceType: .dictionary(.int, .int))
        #expect(function.contains("/\\ (FALSE)"))
        #expect(!function.contains("DOMAIN mapping[_shapeMember0]"))

        let tuple = try FormalValueShape.tuple([.sequence(.integer)])
            .predicate(for: "pair", sourceType: .tuple([.int]))
        #expect(tuple.contains("/\\ (FALSE)"))
        #expect(!tuple.contains("DOMAIN pair[1]"))

        let wrongLength = try FormalValueShape.tuple([.integer, .integer])
            .predicate(for: "pair", sourceType: .tuple([.int]))
        #expect(wrongLength == "FALSE")

        #expect(throws: CompilationDiagnostic.self) {
            try FormalValueShape.record([]).predicate(for: "unknown", sourceType: .named("Missing"))
        }
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
        let expectedProofModule = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(source == expectedProofModule)
        let cfg = try #require(rendered.tlaBundle(checking: [], checkDeadlock: false).root.cfg)
        #expect(cfg.contains("INVARIANT __SwiftTLAEvaluationOK\n"))
    }

    @Test("A finite scalar-to-record view reports a total formal failure")
    func finiteScalarToRecordFailure() throws {
        var machine = try FiniteCheckedRecordView.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            try machine.send(.inspect)
        }
        #expect(machine.snapshot == before)

        let rendered = try FiniteCheckedRecordView.render()
        #expect(rendered.intrinsicInvariantNames == ["__SwiftTLAEvaluationOK"])
        let source = rendered.tlaBundle.root.tla
        #expect(!source.contains("DOMAIN level"))
        let proofInput = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/FiniteCheckedRecordView.tla")
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
        let expectedSwift = nativeWitnessSource(try String(contentsOf: swiftInput, encoding: .utf8))
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

    @Test("A set element's scalar-to-sequence view fails without a partial formal predicate")
    func setElementKindMismatch() throws {
        var machine = try NestedCheckedSetView.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            try machine.send(.inspect)
        }
        #expect(machine.snapshot == before)

        let rendered = try NestedCheckedSetView.render()
        #expect(rendered.intrinsicInvariantNames == ["__SwiftTLAEvaluationOK"])
        let source = rendered.tlaBundle.root.tla
        #expect(source.contains("\\A _shapeMember0 \\in _checkedValue : FALSE"))
        #expect(!source.contains("DOMAIN _shapeMember0"))
        let proofInput = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/NestedCheckedSetView.tla")
            .standardizedFileURL
        #expect(source == (try String(contentsOf: proofInput, encoding: .utf8)))
        let cfg = try #require(rendered.tlaBundle(checking: [], checkDeadlock: false).root.cfg)
        #expect(cfg.contains("INVARIANT __SwiftTLAEvaluationOK\n"))

        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("CheckedViewKindMismatchFixtures.swift")
        let parsed = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(parsed.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "NestedCheckedSetView" })
        var emitter = NativeSwiftEmitter(model: try TLASpecVerifier.parseAndVerify(declaration))
        let visitor = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text.hasPrefix("_visitUpdates") == true
                && $0.description.contains("NativeMachineEvaluationError.noMatchingCase")
        })
        let swiftInput = proofInput.deletingLastPathComponent()
            .appendingPathComponent("NestedCheckedSetViewSwiftVisitor.txt")
        let expectedSwift = nativeWitnessSource(try String(contentsOf: swiftInput, encoding: .utf8))
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
