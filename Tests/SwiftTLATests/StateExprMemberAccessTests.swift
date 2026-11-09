import Foundation
import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct StateExprMemberAccessTests {
    @Test func parseKnownProperties() throws {
        let s: StateExpr = .variable("s")
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("s.cardinality")) == StateExpr.cardinality(s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("s.flattened")) == StateExpr.unionAll(s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("s.subsets")) == StateExpr.powerSet(s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("s.domain")) == StateExpr.domain(s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("s.count")) == StateExpr.tupleLength(s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("s.head")) == StateExpr.tupleHead(s))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("s.tail")) == StateExpr.tupleTail(s))
    }

    @Test func parseUnknownPropertyAsRecordAccess() throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("msg.type")) == StateExpr.recordAccess(.variable("msg"), "type"))
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("ballot.val")) == StateExpr.recordAccess(.variable("ballot"), "val"))
    }

    @Test("Raw expression members retain source shapes and local shadowing",
        arguments: ["record", "array", "dictionary", "dictionaryString", "dictionaryNested", "dictionaryContext", "boundInteger", "boundRecord"])
    func scopedRawMembers(_ kind: String) throws {
        let source = Parser.parse(source: try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("GeneratedSwiftRecordFixtures.swift"), encoding: .utf8))
        let model = try #require(source.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
            .first { $0.name.text == "GeneratedSwiftRecord" })
        let metadata = try TLASpecVerifier.sourceTypes(in: model.memberBlock.members, enums: [])
        let member: String
        switch kind {
        case "record", "boundRecord": member = "packet.count"
        case "array": member = "history.count"
        case "boundInteger": member = "packet.expr"
        default: member = "lookup.count"
        }
        let lookupInitial = kind == "dictionaryString" ? "[\"key\": 1]"
            : kind == "dictionaryNested" ? "[0: [1, 2]]" : "[0: 1]"
        let lookup = kind == "dictionaryContext"
            ? "let lookup: SharedVariable<[Int: Int]> = scope.sharedVar(_name: \"storedLookup\", initial: [:])"
            : "let lookup = scope.sharedVar(_name: \"storedLookup\", initial: \(lookupInitial))"
        let selected = "Expr<Int>(StateExpr.firstMatch((when: (\(member) >= 0).stateExpr, then: 1), fallback: 0)) == 1"
        let quantified = kind.hasPrefix("bound")
        let predicate = kind == "boundInteger"
            ? "ForAll(in: IntRange(1, through: 2)) { packet in \(selected) }"
            : kind == "boundRecord"
                ? "ForAll(in: SetExpr<Packet>.literal(Packet(count: 1, ready: false))) { packet in \(selected) }"
                : selected
        let restored = quantified ? "Invariant(\"Restored\") { Expr<Int>(StateExpr.firstMatch((when: (packet.count >= 0).stateExpr, then: 1), fallback: 0)) == 1 }" : ""
        let parsed = SpecParser.parseSpecClosure(named: "GeneratedSwiftRecord", try parseSpecTestClosure("""
        { scope in
            let packet = scope.sharedVar(_name: "storedPacket", initial: Packet(count: 0, ready: false))
            let history = scope.sharedVar(_name: "storedHistory", initial: [1, 2])
            \(lookup)
            Invariant("Selected") { \(predicate) }
            \(restored)
        }
        """), sourceTypes: metadata)
        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let body = try #require(parsed.invariants.first).body
        func expected(_ value: StateExpr) -> StateExpr {
            .equal(.caseExpr([.greaterOrEqual(value, .int(0)), .int(1)], .int(0)), .int(1))
        }
        if quantified {
            guard case .forAll(let domain, let binder, let predicate) = body else {
                Issue.record("Expected the source quantifier and its local binding")
                return
            }
            if kind == "boundInteger" {
                #expect(domain == .integerRange(.int(1), .int(2)))
            } else {
                #expect(try compiledValue(domain) == .set([.record(["count": .int(1), "ready": .bool(false)])]))
            }
            let value: StateExpr = kind == "boundInteger" ? .variable(binder) : .recordAccess(.variable(binder), "count")
            let matches: Bool = predicate == expected(value)
            #expect(matches)
            #expect(try #require(parsed.invariants.last).body == expected(.recordAccess(.variable("storedPacket"), "count")))
        } else {
            let value: StateExpr = kind == "record" ? .recordAccess(.variable("storedPacket"), "count")
                : kind == "array" ? .tupleLength(.variable("storedHistory"))
                : .cardinality(.domain(.variable("storedLookup")))
            #expect(body == expected(value))
        }
        _ = try CompiledProgram(inputs: SourceTypeResolver(metadata: metadata).resolve(in: parsed.compile()))
    }
}
