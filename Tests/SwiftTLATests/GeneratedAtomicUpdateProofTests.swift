import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLAPlugin

@Suite("Generated atomic update proof input")
struct GeneratedAtomicUpdateProofTests {
    @Test("The proof input contains the generated Swift state and copy paths")
    func emittedSwiftTransitionMatchesProofInput() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("GeneratedAtomicUpdateProofFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(source.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "GeneratedAtomicCopyProofModel" })
        let model = try TLASpecVerifier.parseAndVerify(declaration)
        var emitter = NativeSwiftEmitter(model: model)
        let members = try emitter.machineMembers()
        let names = ["_Updates", "_initialStates", "_visitUpdates0", "_visitSuccessors0",
            "__swifttlaFormalProjectionTokens", "formalProjection", "formalCall"]
        let actual = try names.map { name in
            let member = try #require(members.first { item in
                item.as(StructDeclSyntax.self)?.name.text == name
                    || item.as(FunctionDeclSyntax.self)?.name.text == name
                    || item.as(VariableDeclSyntax.self)?.bindings.first?
                        .pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name
            })
            return "@@ \(name)\n" + member.description.trimmingCharacters(in: .newlines)
        }.joined(separator: "\n")
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedAtomicCopySwiftWitness.txt")
            .standardizedFileURL
        let checked = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(actual == checked.trimmingCharacters(in: .newlines))
    }

    @Test("The checked TLA module is the model's actual generated output")
    func renderedModuleMatchesProofInput() throws {
        let rendered = try GeneratedAtomicCopyProofModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedAtomicCopyProofModel.tla")
            .standardizedFileURL
        let checkedModule = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(rendered == checkedModule)

        let machine = try GeneratedAtomicCopyProofModel.makeMachine()
        #expect(try machine.formalCall(for: .copy).name == "copy")
        let successors = try machine.successors(for: .copy)
        #expect(successors.count == 1)
        let successor = try #require(successors.first)
        #expect(machine.state.first == 0 && machine.state.second == 1)
        #expect(successor.state.first == 1 && successor.state.second == 1)
    }
}
