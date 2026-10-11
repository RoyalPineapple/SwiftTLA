import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLAPlugin

@Suite("Generated selection proof input")
struct GeneratedSelectionProofTests {
    @Test("Generated selections match their proof witnesses")
    func generatedSelectionOutputsMatchProofWitnesses() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("TypedSelectionFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let cases = [
            (model: "IncreasingSelection", witness: "GeneratedSelectionSwiftWitness.txt", cache: false),
            (model: "BooleanSelection", witness: "GeneratedBooleanSelectionSwiftWitness.txt", cache: true),
            (model: "EnumSelection", witness: "GeneratedEnumSelectionSwiftWitness.txt", cache: true),
            (model: "StringSelection", witness: "GeneratedStringSelectionSwiftWitness.txt", cache: true),
            (model: "MissingStringSelection", witness: "GeneratedMissingStringSelectionSwiftWitness.txt", cache: true)
        ]
        for entry in cases {
            let declaration = try #require(source.statements.compactMap {
                $0.item.as(StructDeclSyntax.self)
            }.first { $0.name.text == entry.model })
            let model = try TLASpecVerifier.parseAndVerify(declaration)
            var emitter = NativeSwiftEmitter(model: model)
            let members = try emitter.machineMembers()
            let update = try #require(members.first {
                $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
            })
            var emitted = update.description
            if entry.cache {
                let cache = try #require(members.first { $0.description.contains("let _closedChoice0") })
                emitted = cache.description + "\n" + emitted
            }
            let binderPattern = try Regex(#"___binder_SpecParser_[0-9]+_0_1"#)
            let binders = Set(emitted.matches(of: binderPattern).map { String(emitted[$0.range]) })
            #expect(binders.count == 1)
            let normalized = emitted.replacing(binderPattern, with: "__PROOF_MEMBER__")
            let witness = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("../../Verification/Semantics/\(entry.witness)")
                .standardizedFileURL
            let expected = Array(Parser.parse(source: try String(contentsOf: witness, encoding: .utf8))
                .tokens(viewMode: .sourceAccurate)).map(\.text)
            let actual = Array(Parser.parse(source: normalized).tokens(viewMode: .sourceAccurate)).map(\.text)
            #expect(actual == expected, "Generated output changed for \(entry.model)")
        }
    }
}
