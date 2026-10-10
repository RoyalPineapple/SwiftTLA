import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLAPlugin

@Suite("Conditional step proof input")
struct ConditionalStepProofTests {
    @Test("The emitted Swift conditional retains both complete branches")
    func generatedConditionalOutputMatchesProofRule() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ConditionalStepProofFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(source.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "ConditionalStepProofModel" })
        let model = try TLASpecVerifier.parseAndVerify(declaration)
        var emitter = NativeSwiftEmitter(model: model)
        let members = try emitter.machineMembers()
        let update = try #require(members.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedConditionalStepSwiftWitness.txt")
            .standardizedFileURL
        let checked = try String(contentsOf: proofInput, encoding: .utf8)
        let expected = Array(Parser.parse(source: checked).tokens(viewMode: .sourceAccurate))
            .map(\.text).filter { !$0.isEmpty }
        let actual = Array(update.tokens(viewMode: .sourceAccurate))
            .map(\.text).filter { !$0.isEmpty }
        #expect(actual == expected)

        let invertedGuard = update.description.replacingOccurrences(
            of: "guard ___atomic_0_0 else", with: "guard (!___atomic_0_0) else")
        #expect(invertedGuard != update.description)
        let mutant = Array(Parser.parse(source: invertedGuard).tokens(viewMode: .sourceAccurate))
            .map(\.text).filter { !$0.isEmpty }
        #expect(mutant != expected)
    }

    @Test("A conditional branch reads the value written earlier in its atomic step")
    func generatedConditionalBranches() throws {
        let initial = try ConditionalStepProofModel.initialMachines()
        #expect(initial.count == 2)
        for machine in initial {
            let successors = try machine.successors(for: .choose)
            #expect(successors.count == 1)
            let successor = try #require(successors.first)
            #expect(successor.state.value == (machine.state.chooseFirst ? 2 : 1))
            #expect(successor.state.chooseFirst == !machine.state.chooseFirst)
            #expect(try !successor.isEnabled(.choose))
        }
        let rendered = try ConditionalStepProofModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/ConditionalStepProofModel.tla")
            .standardizedFileURL
        #expect(rendered == (try String(contentsOf: proofInput, encoding: .utf8)))
    }
}
