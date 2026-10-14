import Foundation
@testable import SwiftTLA
@testable import SwiftTLAPlugin
import SwiftParser
import SwiftSyntax
import Testing

@Suite("Dependent initialization output proof input")
struct DependentInitializationOutputProofTests {
    @Test("Generated initial machines and checked TLA module retain dependent choices")
    func emittedInitialStates() throws {
        let machines = try DependentInitializationOutputProofModel.initialMachines()
        #expect(Set(machines.map { [$0.state.seed, $0.state.choice] }) == [[0, 0], [1, 0], [1, 1]])

        let rendered = try DependentInitializationOutputProofModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/DependentInitializationOutputProofModel.tla")
            .standardizedFileURL
        let checkedModule = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(rendered == checkedModule)

        let predicates = [
            "pc = \"finish\"",
            "seed \\in 0..1",
            "choice \\in (IF (seed = 0) THEN {0} ELSE {0, 1})",
        ]
        let missingDependentClause = rendered.replacingOccurrences(
            of: "  /\\ choice \\in (IF (seed = 0) THEN {0} ELSE {0, 1})\n", with: "")
        #expect(missingDependentClause != rendered)
        do {
            try verifyRenderedInitialConjunction(missingDependentClause, predicates: predicates)
            Issue.record("A missing dependent initializer was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.Init")
            #expect(diagnostic.actual == "Init ==\n  /\\ pc = \"finish\"\n  /\\ seed \\in 0..1")
        }
    }

    @Test("Generated Swift initial bindings follow the compiled initialization plan")
    func generatedSwiftInitialBindingsFollowPlan() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("DependentInitializationOutputProofFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(source.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "DependentInitializationOutputProofModel" })
        let model = try TLASpecVerifier.parseAndVerify(declaration)
        var emitter = NativeSwiftEmitter(model: model)
        let initialStates = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
        })
        let expected = model.program.behavior.initializations.map { initialization in
            let name = emitter.variable(initialization.variable)
            switch initialization.initialization {
            case .value: return "let \(name)"
            case .memberOf: return "for \(name)"
            }
        }
        try verifyGeneratedInitialBindings(initialStates, expected: expected)

        let seed = try #require(model.program.layout.variables.first {
            $0.declaration.name == "seed"
        })
        let name = emitter.variable(seed.id)
        let truncated = initialStates.description.replacingOccurrences(
            of: "for \(name) in ",
            with: "let \(name) = 0\nfor _discard in ")
        #expect(truncated != initialStates.description)
        let changed = try #require(Parser.parse(source: truncated).statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedInitialBindings(changed, expected: expected)
        }
    }
}
