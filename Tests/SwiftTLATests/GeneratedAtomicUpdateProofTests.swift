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
        let names = ["State", "Snapshot", "_Updates", "_visitUpdates0", "_visitSuccessors0",
            "__swifttlaFormalProjectionTokens", "formalProjection", "formalCall"]
        let actual = try names.map { name in
            let member = try #require(members.first { item in
                item.as(StructDeclSyntax.self)?.name.text == name
                    || item.as(FunctionDeclSyntax.self)?.name.text == name
                    || item.as(VariableDeclSyntax.self)?.bindings.first?
                        .pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name
            })
            return "@@ \(name)\n" + member.description
                .replacingOccurrences(of: #"(?m)^[ \t]+$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .newlines)
        }.joined(separator: "\n")
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedAtomicCopySwiftWitness.txt")
            .standardizedFileURL
        let checked = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(actual == checked.trimmingCharacters(in: .newlines))

        let initials = try #require(members.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
        })
        let values = try #require(try checkedInitialValues(initials.description))
        #expect(values.first == 0 && values.second == 1)
        let wrongGuard = initials.description.replacingOccurrences(
            of: "_selectedInitial!.second", with: "_selectedInitial!.first")
        #expect(wrongGuard != initials.description)
        #expect(try checkedInitialValues(wrongGuard).map { _ in true } == nil)
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

    private func checkedInitialValues(_ source: String) throws -> (first: Int, second: Int)? {
        let pattern = #"""
        \A private \s+ static \s+ func \s+ _initialStates
        \( _selectedInitial: \s* State\? \s* = \s* nil \)
        \s* throws \s* -> \s* \[Snapshot\] \s* \{
        \s* var \s+ result: \s* \[Snapshot\] \s* = \s* \[\]
        \s* let \s+ _value_first_0: \s* Int \s* = \s* (-?[0-9]+)
        \s* if \s+ _selectedInitial \s* == \s* nil \s* \|\| \s* _selectedInitial!\.first \s* == \s* _value_first_0 \s* \{
        \s* let \s+ _value_second_1: \s* Int \s* = \s* (-?[0-9]+)
        \s* if \s+ _selectedInitial \s* == \s* nil \s* \|\| \s* _selectedInitial!\.second \s* == \s* _value_second_1 \s* \{
        \s* result\.append \( Snapshot \( state: \s* State \( first: \s* _value_first_0, \s* second: \s* _value_second_1 \) \) \)
        \s* \} \s* \} \s* return \s+ result \s* \} \s* \z
        """#
        let regex = try NSRegularExpression(pattern: pattern, options: .allowCommentsAndWhitespace)
        let text = source as NSString
        guard let match = regex.firstMatch(in: source, range: NSRange(location: 0, length: text.length)),
              match.range == NSRange(location: 0, length: text.length),
              let first = Int(text.substring(with: match.range(at: 1))),
              let second = Int(text.substring(with: match.range(at: 2))) else { return nil }
        return (first, second)
    }
}
