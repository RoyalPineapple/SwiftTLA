import Foundation
import Testing
import UpstreamParity
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct GuardedStepExecutionTests {
    @Test("Process and procedure guards suppress failing bodies and discard only blocked choice updates",
        arguments: [0, 1], [0, 1])
    func guardsProcessAndProcedure(entryReady: Int, bodyReady: Int) throws {
        let initial = try #require(try GuardedProcesses.initialMachines().first {
            $0.state.entryReady == entryReady && $0.state.bodyReady == bodyReady
        })
        let graph = try ReachabilityGraph(initialMachines: [initial], maximumStates: 100)
        #expect(graph.deadlockedStates.isEmpty == (entryReady == 1 && bodyReady == 1))
        #expect(graph.transitions.keys.filter { $0.state.value == 0 }.count == 1)
        for node in GuardedProcesses.Node.allCases {
            var machine = initial
            let enter = GuardedProcesses.Action.enter(process: node)
            #expect(try machine.isEnabled(enter) == (entryReady == 1))
            if entryReady == 0 {
                #expect(try machine.successors(for: enter).isEmpty)
                #expect(throws: GeneratedMachineError.noMatchingSuccessor) { try machine.send(enter) }
                #expect(machine.snapshot == initial.snapshot)
                continue
            }
            _ = try machine.send(enter)
            #expect(machine.state.value == 1)
            let prepare = GuardedProcesses.Action.procedure_choose_prepare(process: node)
            let body = GuardedProcesses.Action.procedure_choose_body(process: node)
            for other in GuardedProcesses.Node.allCases where other != node {
                #expect(try !machine.isEnabled(.procedure_choose_prepare(process: other)))
            }
            #expect(try machine.violatedInvariants(atLevel: 2).isEmpty)
            let first = try machine.send(prepare)
            #expect(first.after.value == (bodyReady == 1 ? 3 : 1))
            if bodyReady == 1 {
                #expect(try machine.isEnabled(prepare))
                #expect(try !machine.isEnabled(body))
                #expect(try machine.violatedInvariants(atLevel: 3).isEmpty)
                let exit = try machine.send(prepare)
                #expect(exit.after.value == 3)
            }
            #expect(try !machine.isEnabled(prepare))
            let before = machine.snapshot
            let successors = try machine.successors(for: body)
            #expect(try machine.isEnabled(body) == (bodyReady == 1))
            #expect(Set(successors.map { $0.state.value }) == (bodyReady == 1 ? [1, 2] : []))
            #expect(throws: bodyReady == 1 ? GeneratedMachineError.ambiguousAction : .noMatchingSuccessor) {
                try machine.send(body)
            }
            #expect(machine.snapshot == before)
            #expect(Set(graph.transitions[before, default: []].filter { $0.action == body }.map(\.target))
                == Set(successors.map(\.snapshot)))
            for successor in successors {
                #expect(try successor.isEnabled(.finish(process: node)))
                for other in GuardedProcesses.Node.allCases where other != node {
                    #expect(try successor.isEnabled(.enter(process: other)))
                    #expect(try !successor.isEnabled(.finish(process: other)))
                }
            }
        }
#if compiler(>=6.2)
        if entryReady == 1 && bodyReady == 1 {
            let rendered = try GuardedProcesses.render()
            let module = rendered.tlaBundle.root
            let cfg = try #require(module.cfg)
            let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("GuardedStepExecutionFixtures.swift")
            let authored = try Data(contentsOf: source)
            let parsed = Parser.parse(source: String(decoding: authored, as: UTF8.self))
            let declaration = try #require(parsed.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
                .first { $0.name.text == String(describing: GuardedProcesses.self) })
            let frontend = try TLASpecVerifier.parseAndVerify(declaration)
            try #require(frontend.procedureLoopSources.count == 1)
            let loop = try #require(frontend.procedureLoopSources.first)
            try #require(loop.body != nil)
            let proof = try #require(try SequentialControlOutputEvidence.procedureLoopProof(
                source: loop, program: frontend.program, rendered: rendered))
            try checkBooleanProcedureGuard(in: declaration)
            let workers = rendered.actions.filter { $0.sourceName == loop.action }
            try #require(workers.count == 2)
            let original = workers.map { row in
                (header: row.renderedName, definition: "\(row.renderedName) == \(row.emittedInvocationName)")
            }
            let changed = zip(original, workers.reversed()).reduce(module.tla) { text, pair in
                let (alias, other) = pair
                return text.replacingOccurrences(of: alias.definition + "\n",
                    with: "\(alias.header) == \(other.emittedInvocationName)\n")
            }
            try #require(changed != module.tla)
            #expect(throws: CompilationDiagnostic.self) {
                try verifyRenderedActionDeclarations(changed, declarations: original)
            }
            Attachment.record(Array(authored), named: source.lastPathComponent)
            Attachment.record(Array(module.tla.utf8), named: "\(module.name).tla")
            Attachment.record(Array(cfg.utf8), named: "\(module.name).cfg")
            Attachment.record(Array(proof.bytes), named: "\(proof.name).tla")
        }
#endif
    }

    private func checkBooleanProcedureGuard(in declaration: StructDeclSyntax) throws {
        let booleanSource = declaration.description
            .replacingOccurrences(of: "let bodyReady = scope.sharedVar(initiallyIn: 0...1)",
                                  with: "let bodyReady = scope.sharedVar(initial: true)")
            .replacingOccurrences(of: "parameters: Int.self", with: "parameters: Bool.self")
            .replacingOccurrences(of: "divisor > 0", with: "divisor")
            .replacingOccurrences(of: "divisor && value == 1", with: "bodyReady && divisor && value == 1")
            .replacingOccurrences(of: "1 / divisor", with: "1")
        let parsed = Parser.parse(source: booleanSource)
        let variant = try #require(parsed.statements.first?.item.as(StructDeclSyntax.self))
        let compiled = try TLASpecVerifier.parseAndVerify(variant)
        let loop = try #require(compiled.procedureLoopSources.first)
        let shared = try #require(compiled.program.layout.variables.first { $0.declaration.name == "bodyReady" })
        let local = try #require(compiled.program.layout.variables.first { loop.localRoots.contains($0.declaration.name) })
        let value = try #require(compiled.program.layout.variables.first { $0.declaration.name == "value" })
        let enter = try #require(compiled.program.layout.testActionID(named: "enter"))
        let prepare = try #require(compiled.program.layout.testActionID(named: loop.action))
        let runtime = CompiledRuntime(program: compiled.program)
        let entries = try runtime.initialStates().flatMap { try runtime.successors(for: enter, from: $0) }
        let entered = try #require(entries.first)
        let worker = try #require(entered.arguments.first)
        let permission: CompiledValue? = switch try entered.state.value(for: local.id) {
        case .function(let values): values[worker]
        default: nil
        }
        #expect(try entered.state.value(for: shared.id) == .boolean(true))
        #expect(permission == .boolean(true))
        #expect(try entered.state.value(for: value.id) == .integer(1))
        let successors = try runtime.successors(for: prepare, from: entered.state)
        let completed = try #require(successors.first { $0.arguments == entered.arguments })
        #expect(try completed.state.value(for: value.id) == .integer(3))

        let module = try compiled.program.renderModule()
        let configuration = module.configuration
        let rendered = try RenderedSpecification(_generatedModule: module.moduleName, source: module.renderedModuleSource,
            compilationIdentity: compiled.program.identity.value, declarations: configuration.declarations,
            _generatedConstants: module.constantValues, checkDeadlock: configuration.checkDeadlock,
            _generatedIntegerBitWidth: Int.bitWidth, _generatedIntrinsicInvariants: configuration.intrinsicInvariants,
            invariants: configuration.invariants, reachabilityProperties: configuration.reachabilityProperties,
            properties: configuration.properties, refinements: configuration.refinements, symmetry: configuration.symmetry,
            actions: module.renderedActions)
        let proof = try #require(try SequentialControlOutputEvidence.procedureLoopProof(
            source: loop, program: compiled.program, rendered: rendered))
        let input = try #require(String(decoding: proof.bytes, as: UTF8.self).split(separator: "\n").first {
            $0.hasPrefix("AuthoredProcedureLoopInput(worker) ==")
        })
        #expect(input.contains(#"\#(shared.formalName) \in BOOLEAN"#))
        #expect(input.contains(#"\#(local.formalName)[worker] \in BOOLEAN"#))
        #expect(!input.contains(#"\#(shared.formalName) \in Int"#))
        #expect(!input.contains(#"\#(local.formalName)[worker] \in Int"#))
    }

    @Test("Whole-step guards precede body evaluation and preserve every enabled branch", arguments: [0, 1])
    func guardsAlgorithmExecution(ready: Int) throws {
        var machine = try GuardedAlgorithm.makeMachine(.init(ready: ready, value: 0))
        let initial = machine.snapshot
        let successors = try machine.successors(for: .choose)
        #expect(try machine.isEnabled(.choose) == (ready == 1))
        #expect(Set(successors.map { $0.state.value }) == (ready == 1 ? [1, 2] : []))
        #expect(throws: ready == 1 ? GeneratedMachineError.ambiguousAction : .noMatchingSuccessor) {
            try machine.send(.choose)
        }
        #expect(machine.snapshot == initial)

        let graph = try ReachabilityGraph(initialMachines: [machine], maximumStates: 5)
        #expect(Set(graph.transitions[initial, default: []].map(\.target)) == Set(successors.map(\.snapshot)))
        #expect(graph.transitions.count == (ready == 1 ? 5 : 1))
        #expect(graph.deadlockedStates == (ready == 1 ? [] : [initial]))
        for var successor in successors {
            #expect(try !successor.isEnabled(.choose))
            #expect(try successor.isEnabled(.finish))
            let state = successor.state
            _ = try successor.send(.finish)
            #expect(successor.state == state)
            #expect(try successor.isEnabled(.Terminating))
        }
    }

    @Test("An overflowing step guard reports failure without a successor")
    func guardOverflowMatchesGeneratedFailure() throws {
        var successful = try CheckedGuardOverflow.makeMachine(.init(count: 1))
        let transition = try successful.send(.advance)
        #expect(transition.before.count == 1 && transition.after.count == 0)

        let failing = try CheckedGuardOverflow.makeMachine(.init(count: Int.max))
        let before = failing.snapshot
        #expect(throws: NativeMachineEvaluationError.integerOverflow(
            .addition, operands: [Int.max, 1])) {
            try failing.successors(for: .advance)
        }
        #expect(failing.snapshot == before)

        let rendered = try CheckedGuardOverflow.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let output = rendered.tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/CheckedGuardOverflow.tla")
            .standardizedFileURL
        #expect(output == (try String(contentsOf: proofInput, encoding: .utf8)))
        let compilation = try CheckedGuardOverflow.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "CheckedGuardOverflow", program: program))
        let compiledAction = try #require(program.behavior.actions.first)
        let action = try #require(try emitter.machineMembers().first {
            $0.description.contains("private static func _visitUpdates0(")
        })
        let parts = try emitter.actionFunctions(compiledAction)
        try verifyGeneratedActionWriteOutput(action, action: compiledAction.body, program: program,
            stateFields: emitter.stateMemberNames, parts: parts.writes, conditions: parts.conditions)
        let swiftWitness = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/CheckedGuardOverflowSwiftWitness.txt")
            .standardizedFileURL
        let expected = Array(Parser.parse(source: nativeWitnessSource(try String(contentsOf: swiftWitness, encoding: .utf8)))
            .tokens(viewMode: .sourceAccurate)).map(\.text).filter { !$0.isEmpty }
        #expect(Array(action.tokens(viewMode: .sourceAccurate)).map(\.text).filter { !$0.isEmpty } == expected)
        let invertedGuard = action.description.replacingOccurrences(of: "> 0) else", with: "< 0) else")
        #expect(invertedGuard != action.description)
        let changed = try #require(Parser.parse(source: invertedGuard)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedActionWriteOutput(changed, action: compiledAction.body, program: program,
                stateFields: emitter.stateMemberNames, parts: parts.writes, conditions: parts.conditions)
        }
    }
}
