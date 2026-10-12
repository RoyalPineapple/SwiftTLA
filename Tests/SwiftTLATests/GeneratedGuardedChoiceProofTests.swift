import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Generated guarded choice proof input")
struct GeneratedGuardedChoiceProofTests {
    @Test("The emitted Swift visitor has the checked guarded-choice traversal")
    func emittedSwiftChoice() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("GeneratedGuardedChoiceProofFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(source.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "GeneratedGuardedChoiceProofModel" })
        let compiled = try TLASpecVerifier.parseAndVerify(declaration)
        let action = try #require(compiled.program.behavior.actions.first)
        guard compiled.program.behavior.actions.count == 1,
              case .and(.guard_, .existsAction(let candidate, let domain, let body)) = action.body,
              case .integerRange = domain.operation,
              domain.children.count == 2,
              case .value(.integer(1)) = domain.children[0].operation,
              case .value(.integer(2)) = domain.children[1].operation,
              case .define(let captured, let selected, let writes) = body,
              case .boundValue(let selectedBinder) = selected.operation,
              selectedBinder == candidate,
              case .and(_, .assign(let target, let assigned)) = writes,
              case .boundValue(let assignedBinder) = assigned.operation,
              assignedBinder == captured,
              target == compiled.program.layout.variables.first?.id else {
            Issue.record("The source choice no longer lowers to the proved guarded candidate assignment")
            return
        }
        var emitter = NativeSwiftEmitter(model: compiled)
        let update = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let witness = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedGuardedChoiceSwiftWitness.txt")
            .standardizedFileURL
        let expected = try #require(Parser.parse(source: String(contentsOf: witness, encoding: .utf8))
            .statements.first?.item.as(FunctionDeclSyntax.self))
        let actualTokens = update.tokens(viewMode: .sourceAccurate).map(\.text)
        #expect(actualTokens == expected.tokens(viewMode: .sourceAccurate).map(\.text))

        let droppedCandidate = Parser.parse(source: update.description.replacingOccurrences(
            of: "integerRange(1, 2)", with: "integerRange(1, 1)"))
        let mutant = try #require(droppedCandidate.statements.first?.item.as(FunctionDeclSyntax.self))
        #expect(mutant.tokens(viewMode: .sourceAccurate).map(\.text) != actualTokens)
    }

    @Test("The checked guarded-choice TLA module is actual output, with two native successors")
    func generatedMachineChoice() throws {
        let rendered = try GeneratedGuardedChoiceProofModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedGuardedChoiceProofModel.tla")
            .standardizedFileURL
        #expect(rendered == (try String(contentsOf: proofInput, encoding: .utf8)))

        let machine = try GeneratedGuardedChoiceProofModel.makeMachine()
        #expect(try machine.formalCall(for: .choose).name == "choose")
        #expect(machine.state.selected == 0)
        let successors = try machine.successors(for: .choose)
        #expect(Set(successors.map(\.state.selected)) == [1, 2])
        for successor in successors {
            #expect(try !successor.isEnabled(.choose))
        }
    }
}
