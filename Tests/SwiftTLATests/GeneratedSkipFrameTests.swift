import Foundation
import Testing
import SwiftParser
import SwiftSyntax
import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Generated Skip frame")
struct GeneratedSkipFrameTests {
    @Test("A source Skip keeps the complete generated state and renders an unchanged frame")
    func skipPreservesCompleteStateInBothOutputs() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("GeneratedSkipFrameFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(source.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "GeneratedSkipFrameModel" })
        let model = try TLASpecVerifier.parseAndVerify(declaration)
        let actions = model.program.behavior.actions
        let action = try #require(actions.first)
        #expect(actions.count == 1)
        #expect(action.bindings.isEmpty)
        let variable = try #require(model.program.layout.variables.first)
        guard model.program.layout.variables.count == 1,
              case .and(let guardPart, let framePart) = action.body,
              case .guard_(let predicate) = guardPart,
              case .value(.boolean(true)) = predicate.operation,
              case .unchanged(let framedVariable) = framePart else {
            Issue.record("Skip must lower to a true guard and a complete unchanged frame")
            return
        }
        #expect(framedVariable == variable.id)

        var emitter = NativeSwiftEmitter(model: model)
        let members = try emitter.machineMembers()
        let visitUpdates = try #require(members.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let swift = visitUpdates.description
        let witness = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedSkipFrameSwiftWitness.txt")
            .standardizedFileURL
        let expected = try String(contentsOf: witness, encoding: .utf8)
        let expectedTokens = Array(Parser.parse(source: expected).tokens(viewMode: .sourceAccurate)).map(\.text)
        #expect(Array(Parser.parse(source: swift).tokens(viewMode: .sourceAccurate)).map(\.text)
            == expectedTokens)
        let wrongRead = swift.replacingOccurrences(of: "state.state.value", with: "1")
        let wrongReadVisitor = try #require(Parser.parse(source: wrongRead)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedUnchangedActionOutput(wrongReadVisitor, parts: [
                (id: 1, slot: emitter.variable(variable.id), stateRead: "state.state.value"),
            ])
        }

        let tla = try GeneratedSkipFrameModel.render().tlaBundle.root.tla
        let module = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedSkipFrameModel.tla")
            .standardizedFileURL
        #expect(tla == (try String(contentsOf: module, encoding: .utf8)))

        let machine = try GeneratedSkipFrameModel.makeMachine()
        let successors = try machine.successors(for: .stay)
        #expect(successors.count == 1)
        let successor = try #require(successors.first)
        #expect(machine.state.value == 0)
        #expect(successor.state.value == 0)
        #expect(try machine.formalCall(for: .stay).name == "stay")
    }
}
