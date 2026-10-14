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
        for seed in [-1, 0, 1, 2] {
            for choice in [-1, 0, 1, 2] {
                let selected = DependentInitializationOutputProofModel.State(seed: seed, choice: choice)
                if (seed == 0 && choice == 0) || (seed == 1 && (choice == 0 || choice == 1)) {
                    #expect(try DependentInitializationOutputProofModel.makeMachine(selected).state == selected)
                } else {
                    #expect(throws: GeneratedMachineError.invalidInitialState) {
                        try DependentInitializationOutputProofModel.makeMachine(selected)
                    }
                }
            }
        }

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
        var expectedLoops: [String: String] = [:]
        for initialization in model.program.behavior.initializations {
            guard case .memberOf = initialization.initialization else { continue }
            let name = emitter.variable(initialization.variable)
            expectedLoops[name] = "\(name)Candidates"
        }
        let seed = try #require(model.program.layout.variables.first {
            $0.declaration.name == "seed"
        })
        let name = emitter.variable(seed.id)
        let choice = try #require(model.program.layout.variables.first {
            $0.declaration.name == "choice"
        })
        let choiceName = emitter.variable(choice.id)
        let expectedChoiceSource = """
        ((\(name) == 0) ? Set<Int>([0]) : Set<Int>([0, 1])).sorted(by: { (lhs: Int, rhs: Int) -> Bool in
        return lhs < rhs
        })
        """
        func verify(_ declaration: DeclSyntax) throws {
            try verifyGeneratedInitialBindings(declaration, expected: expected,
                expectedLoops: expectedLoops,
                expectedCandidateSources: ["\(choiceName)Candidates": expectedChoiceSource])
        }
        try verify(initialStates)

        let truncated = initialStates.description.replacingOccurrences(
            of: "for \(name) in ",
            with: "let \(name) = 0\nfor _discard in ")
        #expect(truncated != initialStates.description)
        let changed = try #require(Parser.parse(source: truncated).statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verify(changed)
        }

        let wrongDomain = initialStates.description.replacingOccurrences(
            of: "for \(choiceName) in \(choiceName)Candidates",
            with: "for \(choiceName) in []")
        #expect(wrongDomain != initialStates.description)
        let wrongLoop = try #require(Parser.parse(source: wrongDomain).statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verify(wrongLoop)
        }

        let wrongCandidateSource = initialStates.description.replacingOccurrences(
            of: "Set<Int>([0, 1])).sorted", with: "Set<Int>([0])).sorted")
        #expect(wrongCandidateSource != initialStates.description)
        let wrongCandidate = try #require(Parser.parse(source: wrongCandidateSource).statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verify(wrongCandidate)
        }
    }
}
