import SwiftTLACompilerSupport
import Foundation
import Testing
@testable import UpstreamParity
import SwiftParser
import SwiftSyntax
import SwiftTLAMacros
@testable import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Generated atomic update proof input")
struct GeneratedAtomicUpdateProofTests {
    @Test("Generated captures keep the compiled identity of each declaration")
    func generatedCaptureBindingIdentity() throws {
        let spec = TLASpec(name: "CaptureIdentity", variables: [.init(name: "result", initial: .int(0))],
            actions: [.init(name: "choose", body: .ifElse(.lessThan(.variable("result"), .int(1)),
                .define("first", .int(3), .define("second", .int(7),
                    .define("read", .variable("first"), .assign(.named("result"), .variable("read"))))),
                .unchanged(.named("result"))))], invariants: [])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: spec.compile()))
        let action = try #require(program.behavior.actions.first)
        guard case .ifElse(_, let selected, _) = action.body,
              case .define(let first, _, let secondDefinition) = selected,
              case .define(let second, _, let readDefinition) = secondDefinition,
              case .define(let read, let value, _) = readDefinition else {
            Issue.record("Expected three compiled definitions in the selected arm")
            return
        }
        try #require(value.operation == .boundValue(first))
        try #require(action.body.orderedAlternativeFailureRegions.isEmpty)

        var emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "CaptureIdentity", program: program))
        let members = try emitter.machineMembers()
        let parts = try emitter.actionFunctions(action)
        let name = "_visitUpdates\(action.id.ordinal)"
        let originalVisitor = try #require(member(named: name, in: members))
        func verify(_ declaration: DeclSyntax) throws {
            try verifyGeneratedActionWriteOutput(declaration, action: action.body, program: program,
                stateFields: emitter.stateMemberNames, parts: parts.writes, conditions: parts.conditions,
                requireScalarLeaves: true)
        }
        try verify(originalVisitor)

        let firstName = emitter.binder(first), secondName = emitter.binder(second), readName = emitter.binder(read)
        let original = members.map(\.description).joined(separator: "\n")
        let operand = "let \(readName) = \(firstName)"
        let renamedOperand = "let \(readName) = \(secondName)"
        let temporaryName = "__capturePermutationPlaceholder"
        try #require(original.components(separatedBy: operand).count == 2 && !original.contains(temporaryName))
        let changed = original.replacingOccurrences(of: firstName, with: temporaryName)
            .replacingOccurrences(of: secondName, with: firstName)
            .replacingOccurrences(of: temporaryName, with: secondName)
            .replacingOccurrences(of: renamedOperand, with: operand)
        try #require(changed != original && changed.contains(operand))

        let condition = try #require(parts.conditions.first)
        let predicate = Parser.parse(source: condition.value).tokens(viewMode: .sourceAccurate)
            .filter { $0.tokenKind != .endOfFile }.map(\.text)
        let originalArm = try nativeConditionalActionPlans(original, program: program, predicate: predicate).ifTrue
        let changedArm = try nativeConditionalActionPlans(changed, program: program, predicate: predicate).ifTrue
        guard case .record(let originalTrace) = try originalArm.integerTrace(count: 3),
              case .record(let changedTrace) = try changedArm.integerTrace(count: 3) else {
            Issue.record("Expected decoded native assignment histories")
            return
        }
        #expect(originalTrace.value(named: "declarations") == .tuple([.int(first.ordinal), .int(second.ordinal), .int(read.ordinal)]))
        #expect(changedTrace.value(named: "declarations") == .tuple([.int(second.ordinal), .int(first.ordinal), .int(read.ordinal)]))
        let accepted = originalArm.capturePlans, redirected = changedArm.capturePlans
        try #require(accepted.count == 3 && redirected.count == 3)
        #expect(accepted[0].literals == [.int(3)] && redirected[1].literals == [.int(7)])
        #expect(accepted[2].reads == [.tuple([.string("capture"), .int(1)])])
        #expect(redirected[2].reads == [.tuple([.string("capture"), .int(2)])])

        let changedVisitor = try #require(member(named: name, in: Parser.parse(source: changed)
            .statements.compactMap { $0.item.as(DeclSyntax.self) }))
        do {
            try verify(changedVisitor)
            Issue.record("Capture declarations exchanged compiled identities despite consistent forwarding")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.expected == "the declaration for compiled binder \(first.ordinal)")
            #expect(diagnostic.actual == secondName)
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }
    }

    @Test("A shared conditional write feeds the selector and can fail before selection")
    func sharedConditionalWriteSelectsOrStops() throws {
        let owner = packageRoot().appendingPathComponent(
            "Sources/UpstreamParity/ValidationModels/GeneratedScalarConditionalProofModel.swift")
        let original = try String(contentsOf: owner, encoding: .utf8)
        let originalName = "GeneratedScalarConditionalProofModel"
        let modelName = "GeneratedScalarConditionalSharedPrefixProofModel"
        try #require(original.components(separatedBy: originalName).count == 3)
        let authored = original.replacingOccurrences(of: originalName, with: modelName)
        let prefix = "If(left < right) {"
        let field = "let selected = scope.sharedVar(initial: false)"
        let trueWrite = "Assign(selected, to: true)"
        let falseWrite = "Assign(selected, to: false)"
        for marker in [prefix, field, trueWrite, falseWrite] {
            try #require(authored.components(separatedBy: marker).count == 2)
        }
        let variant = authored
            .replacingOccurrences(of: field, with: """
                \(field)
                let increment = scope.sharedVar(initiallyIn: SetExpr<Int>.literal(-2, 0, 9223372036854775807))
                """)
            .replacingOccurrences(of: prefix, with: """
                Assign(right, to: 3)
                Assign(left, to: left + increment)
                \(prefix)
                """)
            .replacingOccurrences(of: trueWrite, with: """
                Assign(right, to: 9223372036854775807 + right)
                \(trueWrite)
                """)
            .replacingOccurrences(of: falseWrite, with: """
                Assign(right, to: 4)
                Assign(right, to: right)
                \(falseWrite)
                """)
        let declaration = try #require(Parser.parse(source: variant).statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == modelName })
        let compilation = try TLASpecVerifier.parseAndVerify(declaration)
        let program = compilation.program
        let module = try program.renderModule()
        let action = try #require(program.behavior.actions.first)
        let name = "__SwiftTLAActionFailureHistory\(action.id.ordinal) == "
        let histories = module.renderedModuleSource.split(separator: "\n").filter { $0.hasPrefix(name) }
        try #require(histories.count == 1)
        let history = String(try #require(histories.first))
        #expect(history.components(separatedBy: "branch |-> <<>>").count == 2)
        #expect(history.components(separatedBy: "branch |-> 0").count == 2)
        #expect(!history.contains("branch |-> 1"))

        let client = try runExternalGeneratedConsumer(variant + #"""

        @main struct ObserveSharedConditionalWrite {
            static func main() throws {
                let models = try \#(modelName).initialMachines()
                for increment in [-2, 0, Int.max] {
                    guard let machine = models.first(where: { $0.state.left == 4 && $0.state.increment == increment })
                    else { fatalError("Missing authored initial state") }
                    var attempted = machine
                    if increment == 0 {
                        let transition = try attempted.send(.choose)
                        guard transition.action == .choose, transition.before == machine.state,
                              attempted.state == transition.after, transition.after.left == 4,
                              transition.after.right == 4, !transition.after.selected
                        else { fatalError("The false arm did not commit its updates") }
                        continue
                    }
                    let prefix = increment == Int.max
                    let reason = NativeMachineEvaluationError.integerOverflow(.addition,
                        operands: prefix ? [4, Int.max] : [Int.max, 3])
                    let expectedLocation: NativeAlternativeFailure.Location = prefix ? .sharedPrefix : .arm(0)
                    let outcome = try MachineValidator.run(initialMachines: [machine], maximumStates: 1,
                        checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { _ in }
                    guard let history = outcome.orderedActionFailureHistory, history.count == 1,
                          let failure = history.first?.failure, outcome.edges == 0,
                          outcome.completion == .evaluationFailure(reason), outcome.firstEvaluationFailure == reason,
                          failure.action == 0, failure.reason == reason, failure.location == expectedLocation,
                          failure.target == (prefix ? 0 : 1),
                          failure.before.map(\.binding).elementsEqual((failure.site - failure.before.count)..<failure.site),
                          failure.before.map(\.target) == (prefix ? [1] : [1, 0]),
                          failure.before.map(\.value) == (prefix ? [3] : [3, 2])
                    else { fatalError("Unexpected local failure observation") }
                    do {
                        _ = try attempted.send(.choose)
                        fatalError("A failed action returned a successor")
                    } catch let error as NativeMachineEvaluationError {
                        guard error == reason, attempted.state == machine.state
                        else { fatalError("A failed action changed the machine or error") }
                    }
                }
            }
        }
        """#)
        try #require(client.status == 0, Comment(rawValue: client.output))

        var emitter = NativeSwiftEmitter(model: compilation)
        let native = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        let library = packageRoot().appendingPathComponent("Sources/SwiftTLA")
        let operations = try String(contentsOf: library.appendingPathComponent("NativeMachineOperations.swift"), encoding: .utf8)
        let checking = try String(contentsOf: library.appendingPathComponent("CheckingContext.swift"), encoding: .utf8)
        let parsed = try parsedConditionalSource(declaration, modelName: modelName)
        let proof = try ConditionalActionEvidence.arithmeticHistoryProof(authoredSource: variant, modelName: modelName,
            parsed: parsed, program: program, rendered: module, nativeSource: native, operations: operations, checking: checking,
            sendBindingModule: "SwiftTLA\(modelName)PublicSendBinding")
        recordConditionalProof(modelName: modelName, authored: variant, native: native, tla: module.renderedModuleSource,
            configuration: proof.configuration, modules: [(proof.name, proof.bytes), proof.configured, proof.domain] + proof.arms)
    }

    @Test("Conditional overflow records the first failing addition and its preceding writes")
    func conditionalOverflowKeepsTheSelectedArmHistory() throws {
        let owner = packageRoot().appendingPathComponent(
            "Sources/UpstreamParity/ValidationModels/GeneratedScalarConditionalProofModel.swift")
        let original = try String(contentsOf: owner, encoding: .utf8)
        let modelName = "GeneratedScalarConditionalOverflowProofModel"
        let originalName = "GeneratedScalarConditionalProofModel"
        try #require(original.components(separatedBy: originalName).count == 3)
        var authored = original.replacingOccurrences(of: originalName, with: modelName)
        let stepCase = "case choose }"
        try #require(original.components(separatedBy: stepCase).count == 2)
        let renamedLabelControl = original.replacingOccurrences(of: stepCase, with: #"case choose = "rawValue" }"#)
        let selectedField = "let selected = scope.sharedVar(initial: false)"
        try #require(authored.components(separatedBy: selectedField).count == 2)
        authored = authored.replacingOccurrences(of: selectedField, with: """
            \(selectedField)
            let increment = scope.sharedVar(initiallyIn: SetExpr<Int>.literal(0, 1))
            """)
        for (flag, prefix, local, target, expression) in [
            ("true", ["Assign(left, to: 13)"], "left", "right", "left + increment"),
            ("false", ["Assign(right, to: 9223372036854775807)", "Assign(left, to: increment + 17)"],
             "right", "left", "(right + increment) + 2"),
        ] {
            let finalWrite = "Assign(selected, to: \(flag))"
            try #require(authored.components(separatedBy: finalWrite).count == 2)
            let writes = prefix + [
                "Assign(\(local), to: 9223372036854775807)",
                "Assign(\(target), to: \(expression))",
                finalWrite,
            ]
            authored = authored.replacingOccurrences(of: finalWrite, with: writes.joined(separator: "\n                    "))
        }
        let declaration = try #require(Parser.parse(source: authored).statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == modelName })
        let compilation = try TLASpecVerifier.parseAndVerify(declaration)
        let program = compilation.program
        let rendered = try program.renderModule()
        let tla = rendered.renderedModuleSource
        let history = tla.split(separator: "\n").filter { $0.hasPrefix("__SwiftTLAActionFailureHistory0 == ") }
        #expect(history.count == 1)

        let client = try runExternalGeneratedConsumer(authored + "\n" + renamedLabelControl + #"""

        @main struct ObserveConditionalOverflow {
            static func main() throws {
                let models = try GeneratedScalarConditionalOverflowProofModel.initialMachines()
                let ordered = models.sorted {
                    ($0.state.left, $0.state.increment) < ($1.state.left, $1.state.increment)
                }
                for var machine in ordered {
                    let before = machine.state
                    if machine.state.left < machine.state.right && machine.state.increment == 0 {
                        let transition = try machine.send(.choose)
                        let expected = GeneratedScalarConditionalOverflowProofModel.State(
                            left: Int.max, right: Int.max, selected: true, increment: 0)
                        let label = try machine.formalCall(for: transition.action)
                        print("success \(label.name == "choose" && label.arguments.isEmpty && transition.action == .choose && transition.before == before && transition.after == expected && machine.state == expected)")
                        continue
                    }
                    let outcome = try MachineValidator.run(initialMachines: [machine], maximumStates: 1,
                        checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { _ in }
                    let amount = machine.state.increment == 0 ? 2 : 1
                    let expected = NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, amount])
                    do {
                        _ = try machine.send(.choose)
                        print("unexpected successor")
                    } catch let failure as NativeMachineEvaluationError {
                        print("send overflow \(failure == expected && machine.state == before)")
                    }
                    print("entry \(machine.state.left) increment \(machine.state.increment) edges \(outcome.edges) overflow \(outcome.completion == .evaluationFailure(expected))")
                    for event in outcome.orderedActionFailureHistory ?? [] {
                        let f = event.failure
                        guard case .arm(let branch) = f.location else { fatalError("Expected a reached arm") }
                        let before = f.before.map { "\($0.target)=\($0.value)" }.joined(separator: ",")
                        let bindings = f.before.map(\.binding)
                        let orderedBindings = f.site >= bindings.count && bindings.elementsEqual((f.site - bindings.count)..<f.site)
                        print("branch \(branch) target \(f.target) before \(before) ordered \(orderedBindings) reason \(f.reason == expected)")
                    }
                }

                let renamed = try GeneratedScalarConditionalProofModel.initialMachines()
                if var machine = renamed.first(where: { $0.state.left < $0.state.right }) {
                    let before = machine.state
                    let transition = try machine.send(.action_rawValue)
                    let label = try machine.formalCall(for: transition.action)
                    let expected = GeneratedScalarConditionalProofModel.State(left: 2, right: 3, selected: true)
                    print("renamed label \(label.name == "rawValue" && label.arguments.isEmpty && transition.action == .action_rawValue && transition.before == before && transition.after == expected && machine.state == expected)")
                } else {
                    print("renamed label false")
                }
            }
        }
        """#)
        try #require(client.status == 0, Comment(rawValue: client.output))
        #expect(client.output.split(separator: "\n").map(String.init) == [
            "success true",
            "send overflow true",
            "entry 2 increment 1 edges 0 overflow true",
            "branch 0 target 1 before 0=13,0=\(Int.max) ordered true reason true",
            "send overflow true",
            "entry 4 increment 0 edges 0 overflow true",
            "branch 1 target 0 before 1=\(Int.max),0=17,1=\(Int.max) ordered true reason true",
            "send overflow true",
            "entry 4 increment 1 edges 0 overflow true",
            "branch 1 target 0 before 1=\(Int.max),0=18,1=\(Int.max) ordered true reason true",
            "renamed label true",
        ])
        var emitter = NativeSwiftEmitter(model: compilation)
        let native = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        let library = packageRoot().appendingPathComponent("Sources/SwiftTLA")
        let operations = try String(contentsOf: library.appendingPathComponent("NativeMachineOperations.swift"), encoding: .utf8)
        let checking = try String(contentsOf: library.appendingPathComponent("CheckingContext.swift"), encoding: .utf8)
        let parsed = try parsedConditionalSource(declaration, modelName: modelName)
        let proof = try ConditionalActionEvidence.arithmeticHistoryProof(authoredSource: authored, modelName: modelName,
            parsed: parsed, program: program, rendered: rendered, nativeSource: native, operations: operations, checking: checking)

        try #require(proof.configured.name == proof.name + "ConfiguredProof")

        let sharedRecorders = Parser.parse(source: checking).statements.compactMap {
            $0.item.as(FunctionDeclSyntax.self)
        }.filter { $0.name.text == "_recordNativeSharedPrefixFailure" }
        try #require(sharedRecorders.count == 1)
        let sharedRecorder = try #require(sharedRecorders.first).description
        try #require(checking.components(separatedBy: sharedRecorder).count == 2)
        let armOnlyChecking = checking.replacingOccurrences(of: sharedRecorder, with: "")
        func verifyArmRecording(_ checkingSource: String) throws {
            _ = try ConditionalActionEvidence.arithmeticHistoryProof(authoredSource: authored, modelName: modelName,
                parsed: parsed, program: program, rendered: rendered, nativeSource: native, operations: operations,
                checking: checkingSource)
        }
        try verifyArmRecording(armOnlyChecking)
        for (original, corrupted) in [
            ("recordsAlternativeFailures = true", "recordsAlternativeFailures = false"),
            ("guard recordsAlternativeFailures else { return [] }", "guard !recordsAlternativeFailures else { return [] }"),
            ("location: .arm(branch)", "location: .arm(branch + 1)"),
        ] {
            try #require(armOnlyChecking.components(separatedBy: original).count == 2)
            let changedChecking = armOnlyChecking.replacingOccurrences(of: original, with: corrupted)
            try #require(changedChecking != armOnlyChecking)
            #expect(throws: InitialFailureEvidenceError.unsupportedGeneratedOutput) {
                try verifyArmRecording(changedChecking)
            }
        }

        let rightInitializer = "scope.sharedVar(initial: 3)"
        try #require(authored.components(separatedBy: rightInitializer).count == 2)
        let changedInitial = authored.replacingOccurrences(of: rightInitializer, with: "scope.sharedVar(initial: 5)")
        let changedInput = try #require(try AuthoredCopySyntax.conditionalProofInput(source: changedInitial, modelName: modelName))
        let changedRight = try #require(changedInput.declarations.first { $0.name == "right" })
        #expect(changedRight.initializer?.literal == .int(5))
        #expect(throws: InitialFailureEvidenceError.unsupportedGeneratedOutput) {
            try ConditionalActionEvidence.arithmeticHistoryProof(authoredSource: changedInitial, modelName: modelName,
                parsed: parsed, program: program, rendered: rendered, nativeSource: native, operations: operations, checking: checking)
        }

        // A reordered source has the same field names but assigns different failure-target ordinals.
        var lines = authored.components(separatedBy: "\n")
        let leftFields = lines.indices.filter { lines[$0].contains("let left = scope.sharedVar(") }
        let rightFields = lines.indices.filter { lines[$0].contains("let right = scope.sharedVar(") }
        try #require(leftFields.count == 1 && rightFields.count == 1)
        lines.swapAt(leftFields[0], rightFields[0])
        let reordered = lines.joined(separator: "\n")
        let reorderedInput = try #require(try AuthoredCopySyntax.conditionalProofInput(source: reordered, modelName: modelName))
        #expect(reorderedInput.fieldOrder == ["right", "left", "selected", "increment"])
        #expect(throws: InitialFailureEvidenceError.unsupportedGeneratedOutput) {
            try ConditionalActionEvidence.arithmeticHistoryProof(authoredSource: reordered, modelName: modelName,
                parsed: parsed, program: program, rendered: rendered, nativeSource: native, operations: operations, checking: checking)
        }

        let action = try #require(program.behavior.actions.first)
        let label = try #require(program.layout.actions.first { $0.id == action.id }?.renderedName)
        let physical = try #require(OrderedRHSPhysicalAction.decodeConditional(in: tla, action: action, program: program))
        let captures = physical.ifFalse.action.captures
        try #require(captures.count == 5)
        let earlier = captures[0], latest = captures[2], addition = captures[3]
        try #require(earlier.plan.literals == [.int(Int.max)] && latest.plan.literals == earlier.plan.literals)
        try #require(addition.additionNodes == [3, 5])
        try #require(addition.plan.reads.first == .tuple([.string("capture"), .int(3)]))

        // Redirect only the evaluated RHS. The earlier writer has the same value.
        let declarationText = try #require(tla.split(separator: "\n").first { $0.hasPrefix("\(label) == ") })
        let increment = try #require(program.layout.variables.first { $0.declaration.name == "increment" }).formalName
        let rhs = "LET \(addition.binding) == ((\(latest.binding) + \(increment)) + 2) IN"
        try #require(declarationText.components(separatedBy: rhs).count == 2)
        let occurrence = try #require(declarationText.range(of: rhs))
        let redirected = "LET \(addition.binding) == ((\(earlier.binding) + \(increment)) + 2) IN"
        let corrupted = tla.replacingCharacters(in: occurrence, with: redirected)
        #expect(OrderedRHSPhysicalAction.decodeConditional(in: corrupted, action: action, program: program) == nil)

        func nativeLocal(_ binding: String) throws -> String {
            let binder = try #require(program.binderNames.first { $0.value == binding }?.key)
            return "_\(binding)_\(binder.ordinal)"
        }
        let earlierLocal = try nativeLocal(earlier.binding)
        let latestLocal = try nativeLocal(latest.binding)
        let operand = "let _arithmetic0: \(nativeIntTypeTokens.joined()) = "
        try #require(native.components(separatedBy: operand + latestLocal).count == 2)
        let corruptedNative = native.replacingOccurrences(of: operand + latestLocal, with: operand + earlierLocal)
        let predicate = Parser.parse(source: "(state.state.left < state.state.right)")
            .tokens(viewMode: .sourceAccurate).filter { $0.tokenKind != .endOfFile }.map(\.text)
        let decoded = try nativeConditionalActionPlans(native, program: program, predicate: predicate)
        let redirectedNative = try nativeConditionalActionPlans(corruptedNative, program: program, predicate: predicate)
        #expect(decoded.ifFalse.capturePlans[3].reads.first == .tuple([.string("capture"), .int(3)]))
        #expect(redirectedNative.ifFalse.capturePlans[3].reads.first == .tuple([.string("capture"), .int(1)]))

        let visitor = try #require(Parser.parse(source: corruptedNative).statements.compactMap { $0.item.as(DeclSyntax.self) }
            .first { $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates\(action.id.ordinal)" })
        let parts = try emitter.actionFunctions(action)
        do {
            try verifyGeneratedActionWriteOutput(visitor, action: action.body, program: program,
                stateFields: emitter.stateMemberNames, parts: parts.writes, conditions: parts.conditions)
            Issue.record("The generated Swift operand read an earlier writer with the same value")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
            #expect(diagnostic.expected == "the captured value reads its compiled source")
            #expect(diagnostic.actual.contains("expected \(latestLocal), actual \(earlierLocal) "))
        }

        recordConditionalProof(modelName: modelName, authored: authored, native: native, tla: tla,
            configuration: proof.configuration, modules: [(proof.name, proof.bytes), proof.configured, proof.domain] + proof.arms)
    }

    private func parsedConditionalSource(_ declaration: StructDeclSyntax, modelName: String) throws -> TLASpec {
        let members = declaration.memberBlock.members
        let source = try TLASpecVerifier.findSpec(in: members, defaultName: modelName)
        let literal = try #require(source)
        let enums = try TLASpecVerifier.collectEnumVariables(from: members)
        let parser = ParserSession(sourceTypes: try TLASpecVerifier.sourceTypes(in: members, enums: enums))
        parser.sourceModelTypeName = modelName
        return parser.parseSpecClosure(named: literal.name, literal.closure)
    }

    private func recordConditionalProof(modelName: String, authored: String, native: String, tla: String,
                                        configuration: String, modules: [(name: String, bytes: Data)]) {
        Attachment.record(Array(authored.utf8), named: "\(modelName).swift")
        Attachment.record(Array(native.utf8), named: "\(modelName)NativeMembers.swift")
        Attachment.record(Array(tla.utf8), named: "\(modelName).tla")
        Attachment.record(Array(configuration.utf8), named: "\(modelName).cfg")
        for module in modules {
            Attachment.record(Array(module.bytes), named: "\(module.name).tla")
        }
    }

    @Test("The compiler stack action returns the child slots supplied by its visitor")
    func stackActionReturnsItsWrittenChildSlots() throws {
        let before = OrderedIntTraversalPass.State(pending: [.init(first: 7, second: false)], leftChild: 2, rightChild: 3)
        var machine = OrderedIntTraversalPass._machineForRefinement(before)
        let transition = try machine.send(.expand)
        let expected = OrderedIntTraversalPass.State(pending: [
            .init(first: 7, second: true), .init(first: 3, second: false), .init(first: 2, second: false)
        ], leftChild: 2, rightChild: 3)
        #expect(transition.after == expected)
        #expect(machine.state == expected)

        let operationsPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/SwiftTLA/NativeMachineOperations.swift")
        let operations = try String(contentsOf: operationsPath, encoding: .utf8)
        let runtime = try decodeTraversalSeedSequenceRuntime(operations)
        #expect(runtime.prefixFloor == 0)
        #expect(runtime.elementMinimum == 1)
        #expect(runtime.elementOffset == 1)
        let clamp = "sequence.prefix(Swift.max(0, length))"
        try #require(operations.components(separatedBy: clamp).count == 2)
        let retainingFirstFrame = operations.replacingOccurrences(of: clamp, with: "sequence.prefix(Swift.max(1, length))")
        do {
            _ = try decodeTraversalSeedSequenceRuntime(retainingFirstFrame)
            Issue.record("The stack proof accepted a prefix that retains a removed frame")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.traversal.operations.sequencePrefix")
        }

        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/UpstreamParity/CompilerPasses/OrderedIntTraversalPass.swift")
        let file = Parser.parse(source: try String(contentsOf: path, encoding: .utf8))
        let owner = try #require(file.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
            .first { $0.name.text == "OrderedIntTraversalPass" })
        var emitter = NativeSwiftEmitter(model: try TLASpecVerifier.parseAndVerify(owner))
        var members = try emitter.machineMembers()
        _ = try decodeGeneratedTraversalSeedOutput(members)
        let index = try #require(members.firstIndex { $0.as(StructDeclSyntax.self)?.name.text == "_Updates" })
        let correct = members[index].description
        let original = "leftChild: _value_leftChild_1 ?? state.state.leftChild"
        try #require(correct.components(separatedBy: original).count == 2)
        let crossed = correct.replacingOccurrences(of: original, with: "leftChild: _value_rightChild_2 ?? state.state.leftChild")
        try #require(crossed != correct)
        members[index] = try #require(Parser.parse(source: crossed).statements.first?.item.as(DeclSyntax.self))
        #expect(throws: InitialFailureEvidenceError.unsupportedGeneratedOutput) {
            try decodeGeneratedTraversalSeedOutput(members)
        }
    }

    @Test("The proof input contains the generated Swift state and copy paths")
    func emittedSwiftTransitionMatchesProofInput() throws {
        let model = try compiledProofModel()
        var emitter = NativeSwiftEmitter(model: model)
        let members = try emitter.machineMembers()
        let names = ["State", "Snapshot", "__swifttlaFormalProjectionTokens",
            "formalProjection", "formalCall"]
        let actual = try names.map { name in
            let selected = try #require(member(named: name, in: members))
            return "@@ \(name)\n" + selected.description
                .replacingOccurrences(of: #"(?m)^[ \t]+$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .newlines)
        }.joined(separator: "\n")
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedAtomicCopySwiftWitness.txt")
            .standardizedFileURL
        let checked = nativeWitnessSource(try String(contentsOf: proofInput, encoding: .utf8))
        #expect(actual == checked.trimmingCharacters(in: .newlines))

        let initials = try #require(members.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
        })
        let values = try #require(try checkedInitialValues(initials.description))
        #expect(values.first == 0 && values.second == 1)
        let wrongGuard = initials.description.replacingOccurrences(
            of: "_selectedInitial?.second", with: "_selectedInitial?.first")
        #expect(wrongGuard != initials.description)
        #expect(try checkedInitialValues(wrongGuard).map { _ in true } == nil)

        let siteConversion = "SwiftTLA._nativeInitialFailure("
        let siteOrdinal = "evaluatingInitializerOrdinal,"
        try #require(initials.description.components(separatedBy: siteConversion).count == 2)
        try #require(initials.description.components(separatedBy: siteOrdinal).count == 2)
        let callerSite = initials.description.replacingOccurrences(of: siteConversion,
            with: "SwiftTLA.InitialEvaluationFailure(").replacingOccurrences(of: siteOrdinal,
            with: "site: evaluatingInitializerOrdinal.map(SwiftTLA.InitialEvaluationFailure.Site.initializer) ?? .selectedInvariant,")
        try #require(callerSite != initials.description)
        let wrongSite = try #require(Parser.parse(source: callerSite).statements.first?.item.as(DeclSyntax.self))
        try emitter.verifyIntInitialOutput(initials)
        do {
            try emitter.verifyIntInitialOutput(wrongSite)
            Issue.record("An initializer failure using caller construction or Optional operations was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native._initialStates.completeIntOutput")
        }

        let prefixEntry = "SwiftTLA._nativeFormalProjectionEntry(Self.__swifttlaFormalProjectionTokens, at: 0,"
        try #require(initials.description.components(separatedBy: prefixEntry).count == 2)
        for callerEntry in [
            "SwiftTLA.TLAStateProjection.Entry(token: SwiftTLA._nativeFormalProjectionToken(Self.__swifttlaFormalProjectionTokens, at: 0),",
            "SwiftTLA._nativeFormalProjectionEntry([Self.__swifttlaFormalProjectionTokens[0]], at: 0,",
        ] {
            let altered = initials.description.replacingOccurrences(of: prefixEntry, with: callerEntry)
            try #require(altered != initials.description)
            let wrongEntry = try #require(Parser.parse(source: altered).statements.first?.item.as(DeclSyntax.self))
            do {
                try emitter.verifyIntInitialOutput(wrongEntry)
                Issue.record("An initial prefix using caller entry construction or token-array indexing was accepted")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "native._initialStates.completeIntOutput")
            }
        }

        let templateFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedAtomicCopySwiftTemplate.txt")
            .standardizedFileURL
        let template = Parser.parse(source: nativeWitnessSource(try String(contentsOf: templateFile, encoding: .utf8)))
        let templateMembers = template.statements.compactMap { $0.item.as(DeclSyntax.self) }
        let bindings = try checkedTransitionBindings(members, templateMembers)
        #expect(bindings["__PROOF_FIRST_FIELD__"] == "first")
        #expect(bindings["__PROOF_SECOND_FIELD__"] == "second")
        #expect(bindings["__PROOF_READ__"] == "second")
        #expect(bindings["__PROOF_ACTION__"] == "copy")
        let initialConstruction = try [
            #require(member(named: "_initialStates", in: members)),
            #require(member(named: "_completedInitialStates", in: members)),
            #require(member(named: "initialOutcomes", parameterCount: 0, in: members)),
            #require(member(named: "initialMachines", parameterCount: 0, in: members)),
            #require(member(named: "makeMachine", parameterCount: 0, in: members)),
            #require(member(named: "makeMachine", parameterCount: 1, in: members)),
        ]
        let emittedConstructor = try #require(member(named: "makeMachine", parameterCount: 0, in: members))
        let uniqueBinding = try #require(emittedConstructor.as(FunctionDeclSyntax.self)?.body?.statements.first)
        try #require(emittedConstructor.description.components(separatedBy: uniqueBinding.description).count == 2)
        let wrongUniqueness = emittedConstructor.description.replacingOccurrences(
            of: uniqueBinding.description, with: "let execution = try (Self._completedInitialStates(_selectedInitial: nil as State?) as [Snapshot])[0]\n")
        #expect(wrongUniqueness != emittedConstructor.description)
        let wrongConstructor = try #require(Parser.parse(source: wrongUniqueness)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(wrongConstructor.as(FunctionDeclSyntax.self)?.name.text == "makeMachine")
        let completedResult = " as [Snapshot]"
        try #require(emittedConstructor.description.components(separatedBy: completedResult).count == 2)
        let inferredCompletedResult = emittedConstructor.description.replacingOccurrences(of: completedResult, with: "")
        try #require(inferredCompletedResult != emittedConstructor.description)
        let wrongCompletedResult = try #require(Parser.parse(source: inferredCompletedResult)
            .statements.first?.item.as(DeclSyntax.self))
        let publicOutcomes = initialConstruction[2].description
        let initialMachines = initialConstruction[3].description
        let conversion = "SwiftTLA._mapNativeOutcomes(try Self._completedInitialStates(_selectedInitial: nil as State?) as [Snapshot])"
        try #require(initialMachines.components(separatedBy: conversion).count == 2)
        let wrongMapping = initialMachines.replacingOccurrences(of: conversion,
            with: "(try Self._completedInitialStates(_selectedInitial: nil as State?) as [Snapshot]).map")
        try #require(wrongMapping != initialMachines)
        let wrongOutcomes = try #require(Parser.parse(source: wrongMapping)
            .statements.first?.item.as(DeclSyntax.self))
        let outcomeConversion = "return SwiftTLA._mapNativeInitialOutcomes(outcome) { Self(execution: $0) }"
        try #require(publicOutcomes.components(separatedBy: outcomeConversion).count == 2)
        let callerReads = publicOutcomes.replacingOccurrences(of: outcomeConversion,
            with: "return SwiftTLA._nativeInitialOutcomes(states: SwiftTLA._mapNativeOutcomes(outcome.states) { Self(execution: $0) }, failures: outcome.failures)")
        try #require(callerReads != publicOutcomes)
        let wrongOutcomeReads = try #require(Parser.parse(source: callerReads)
            .statements.first?.item.as(DeclSyntax.self))
        let completedOutcomes = initialConstruction[1].description
        let completion = "return try SwiftTLA._completeNativeInitialOutcomes(outcome)"
        try #require(completedOutcomes.components(separatedBy: completion).count == 2)
        let callerCompletion = completedOutcomes.replacingOccurrences(of: completion,
            with: "if let failure = outcome.firstFailure { throw failure }\nreturn outcome.states")
        try #require(callerCompletion != completedOutcomes)
        let wrongCompletionReads = try #require(Parser.parse(source: callerCompletion)
            .statements.first?.item.as(DeclSyntax.self))
        let initialCall = "Self._initialStates(_selectedInitial: nil as State?)"
        try #require(publicOutcomes.components(separatedBy: initialCall).count == 2)
        let defaultedCall = publicOutcomes.replacingOccurrences(of: initialCall, with: "Self._initialStates()")
        try #require(defaultedCall != publicOutcomes)
        let wrongInitialCall = try #require(Parser.parse(source: defaultedCall)
            .statements.first?.item.as(DeclSyntax.self))
        let nominalResult = "let outcome: SwiftTLA.InitialEvaluationOutcomes<Snapshot> ="
        try #require(publicOutcomes.components(separatedBy: nominalResult).count == 2)
        let inferredResult = publicOutcomes.replacingOccurrences(of: nominalResult, with: "let outcome =")
        try #require(inferredResult != publicOutcomes)
        let wrongResultContext = try #require(Parser.parse(source: inferredResult)
            .statements.first?.item.as(DeclSyntax.self))
        let factoryCall = "SwiftTLA._nativeInitialOutcomes(states:"
        try #require(initials.description.components(separatedBy: factoryCall).count == 2)
        let callerFactory = initials.description.replacingOccurrences(
            of: factoryCall, with: "SwiftTLA.InitialEvaluationOutcomes(states:")
        try #require(callerFactory != initials.description)
        let wrongOutcomeFactory = try #require(Parser.parse(source: callerFactory)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try emitter.verifyIntInitialOutput(wrongOutcomeFactory)
            Issue.record("An initializer using a caller-specialized outcome constructor was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native._initialStates.completeIntOutput")
        }
        try verifyGeneratedInitialConstruction(initialConstruction, configured: false)
        for (index, declaration) in [(4, wrongConstructor), (4, wrongCompletedResult), (3, wrongOutcomes), (2, wrongInitialCall),
                                      (2, wrongResultContext), (2, wrongOutcomeReads), (1, wrongCompletionReads)] {
            var wrongConstruction = initialConstruction
            wrongConstruction[index] = declaration
            do {
                try verifyGeneratedInitialConstruction(wrongConstruction, configured: false)
                Issue.record("A generated constructor with changed uniqueness, state conversion or helper binding was accepted")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "native.initialConstruction")
            }
        }
        let emittedUpdate = try #require(member(named: "_visitUpdates0", in: members))
        let expectedUpdate = try #require(member(named: "_visitUpdates0", in: templateMembers))
        let wrongRead = Parser.parse(source: emittedUpdate.description.replacingOccurrences(
            of: "state.state.second", with: "state.state.first"))
        let wrongReadMember = try #require(wrongRead.statements.first?.item.as(DeclSyntax.self))
        #expect(templateBindings(wrongReadMember, expectedUpdate)?["__PROOF_READ__"] == "first")
        let emittedUpdates = try #require(member(named: "_Updates", in: members))
        let firstSlot = try #require(bindings["__PROOF_FIRST_SLOT__"])
        let secondSlot = try #require(bindings["__PROOF_SECOND_SLOT__"])
        let wrongWriteSource = emittedUpdate.description.replacingOccurrences(
            of: "_Updates(\(firstSlot): ___atomic_0_0)",
            with: "_Updates(\(secondSlot): ___atomic_0_0)")
        #expect(wrongWriteSource != emittedUpdate.description)
        let wrongWrite = try #require(Parser.parse(source: wrongWriteSource)
            .statements.first?.item.as(DeclSyntax.self))
        let compiledAction = try #require(model.program.behavior.actions.first)
        let expectedWrites: [(id: Int, slot: String, value: String)] = [
            (id: 5, slot: firstSlot, value: "___atomic_0_0"),
            (id: 3, slot: secondSlot, value: "___atomic_1_1")
        ]
        try verifyGeneratedActionWriteOutput(emittedUpdate, action: compiledAction.body,
            program: model.program, stateFields: emitter.stateMemberNames,
            parts: expectedWrites)
        let wrongContinuationSource = emittedUpdate.description.replacingOccurrences(
            of: "_actionPart3(___atomic_0_0, ___atomic_1_1, candidate, emit)",
            with: "_actionPart3(___atomic_0_0, ___atomic_1_1, updates, emit)")
        #expect(wrongContinuationSource != emittedUpdate.description)
        let wrongContinuation = try #require(Parser.parse(source: wrongContinuationSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongContinuation, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames,
                parts: expectedWrites)
            Issue.record("A generated conjunction discarded the first child's update")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.conjunction.2")
        }
        let wrongAssignedSource = emittedUpdate.description.replacingOccurrences(
            of: "_Updates(\(firstSlot): ___atomic_0_0)",
            with: "_Updates(\(firstSlot): ___atomic_1_1)")
        #expect(wrongAssignedSource != emittedUpdate.description)
        let wrongAssigned = try #require(Parser.parse(source: wrongAssignedSource)
            .statements.first?.item.as(DeclSyntax.self))
        let selfConsistentWrongWrites = expectedWrites.map {
            (id: $0.id, slot: $0.slot, value: $0.id == 5 ? "___atomic_1_1" : $0.value)
        }
        do {
            try verifyGeneratedActionWriteOutput(wrongAssigned, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames,
                parts: selfConsistentWrongWrites)
            Issue.record("A generated Int assignment used another captured value")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.write.5")
        }
        do {
            try verifyGeneratedActionWriteOutput(wrongReadMember, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames,
                parts: expectedWrites)
            Issue.record("A captured state value read a different compiled field")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.binding.0")
        }
        let wrongInheritedReadSource = emittedUpdate.description.replacingOccurrences(
            of: "let ___atomic_1_1 = ___atomic_0_0",
            with: "let ___atomic_1_1 = state.state.first")
        #expect(wrongInheritedReadSource != emittedUpdate.description)
        let wrongInheritedRead = try #require(Parser.parse(source: wrongInheritedReadSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongInheritedRead, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames, parts: expectedWrites)
            Issue.record("A captured binding reread pre-step state")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.binding.1")
        }
        let wrongBindingSource = emittedUpdate.description.replacingOccurrences(
            of: "try _actionPart1(___atomic_0_0, updates, emit)",
            with: "try _actionPart1(state.state.first, updates, emit)")
        #expect(wrongBindingSource != emittedUpdate.description)
        let wrongBinding = try #require(Parser.parse(source: wrongBindingSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongBinding, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames,
                parts: expectedWrites)
            Issue.record("A generated action replaced a captured value before its child")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.binding.0")
        }
        let wrongInheritedSource = emittedUpdate.description.replacingOccurrences(
            of: "try _actionPart2(___atomic_0_0, ___atomic_1_1, updates, emit)",
            with: "try _actionPart2(state.state.first, ___atomic_1_1, updates, emit)")
        #expect(wrongInheritedSource != emittedUpdate.description)
        let wrongInherited = try #require(Parser.parse(source: wrongInheritedSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongInherited, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames,
                parts: expectedWrites)
            Issue.record("A generated action replaced an earlier captured value before its child")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.binding.1")
        }
        let wrongChildSource = emittedUpdate.description.replacingOccurrences(
            of: "try _actionPart3(", with: "try _actionPart5(")
        #expect(wrongChildSource != emittedUpdate.description)
        let wrongChild = try #require(Parser.parse(source: wrongChildSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongChild, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames,
                parts: expectedWrites)
            Issue.record("A generated action called the wrong child part")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.part.2")
        }
        let missingEntrySource = emittedUpdate.description.replacingOccurrences(
            of: "try _actionPart0(_Updates(), emit)", with: "try emit(_Updates())")
        #expect(missingEntrySource != emittedUpdate.description)
        let missingEntry = try #require(Parser.parse(source: missingEntrySource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(missingEntry, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames,
                parts: expectedWrites)
            Issue.record("A generated action never entered its root part")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.entry")
        }
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedActionWriteOutput(wrongWrite, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames,
                parts: expectedWrites)
        }
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedActionWriteOutput(emittedUpdate, action: compiledAction.body,
                program: model.program, stateFields: emitter.stateMemberNames, parts: [])
        }
        let wrongMergeSource = emittedUpdates.description.replacingOccurrences(
            of: "&result.\(secondSlot)", with: "&result.\(firstSlot)")
        #expect(wrongMergeSource != emittedUpdates.description)
        let wrongMerge = Parser.parse(source: wrongMergeSource)
        let wrongMergeMember = try #require(wrongMerge.statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedUpdateMergeOutput(wrongMergeMember, slots: [firstSlot, secondSlot])
        }
        let recordEmitter = NativeSwiftEmitter(model: try swiftRecordModel())
        let recordUpdates = try #require(try recordEmitter.updateDeclarations().first)
        let recordSlots = recordEmitter.program.layout.variables.map { recordEmitter.variable($0.id) }
        let recordTypes = Dictionary(uniqueKeysWithValues: try recordEmitter.program.layout.variables.compactMap {
            slot -> (String, String)? in
            let type = recordEmitter.program.variableTypes[slot.id]!
            return recordEmitter.containsSourceNominal(type) ? (recordEmitter.variable(slot.id), try recordEmitter.swiftType(type)) : nil
        })
        try verifyGeneratedUpdateMergeOutput(recordUpdates, slots: recordSlots, recordTypes: recordTypes)
        let recordSlot = try #require(recordTypes.keys.first)
        try #require(recordTypes.count == 1)
        let relation = "return _mergeEqual_\(recordSlot)(lhs, rhs)"
        try #require(recordUpdates.description.components(separatedBy: relation).count - 1 == 1)
        let ignoredIncoming = recordUpdates.description.replacingOccurrences(
            of: relation, with: "return _mergeEqual_\(recordSlot)(lhs, lhs)")
        #expect(ignoredIncoming != recordUpdates.description)
        let ignoredMerge = Parser.parse(source: ignoredIncoming).statements.first?.item.as(DeclSyntax.self)
        do {
            try verifyGeneratedUpdateMergeOutput(ignoredMerge, slots: recordSlots, recordTypes: recordTypes)
            Issue.record("A record-update compatibility relation that ignores the incoming value was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native._Updates.merging")
        }

        let firstField = try #require(bindings["__PROOF_FIRST_FIELD__"])
        let secondField = try #require(bindings["__PROOF_SECOND_FIELD__"])
        let projectionTokens = try #require(member(named: "__swifttlaFormalProjectionTokens", in: members))
        let projection = try #require(member(named: "formalProjection", in: members))
        let projectionFields = [firstField, secondField].map { field in
            (formalName: field, route: "snapshot.state.\(field)", type: CompiledValueType.int,
                value: "SwiftTLA._nativeFormalInt(snapshot.state.\(field))")
        }
        try verifyGeneratedFormalProjectionOutput([projectionTokens, projection], fields: projectionFields)
        for (callee, replacement, occurrences, reason) in [
            ("SwiftTLA._nativeFormalInt(", "SwiftTLA.TLAValue.int(", 2,
                "the projected Int value for \(firstField) does not use the library integer conversion"),
            ("SwiftTLA._nativeFormalProjection(", "SwiftTLA.TLAStateProjection(validating:", 1,
                "the projection call shape or formal token ordering differs from the checked rule"),
        ] {
            try #require(projection.description.components(separatedBy: callee).count - 1 == occurrences)
            let wrongSource = projection.description.replacingOccurrences(of: callee, with: replacement)
            try #require(wrongSource != projection.description)
            let wrong = try #require(Parser.parse(source: wrongSource).statements.first?.item.as(DeclSyntax.self))
            let wrongFields = projectionFields.map { field in
                (formalName: field.formalName, route: field.route, type: field.type,
                    value: field.value.replacingOccurrences(of: callee, with: replacement))
            }
            do {
                try verifyGeneratedFormalProjectionOutput([projectionTokens, wrong], fields: wrongFields)
                Issue.record("A caller-replaceable projection call was accepted")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "native.formalProjection")
                #expect(diagnostic.actual == reason)
            }
        }
        let wrongProjectionSource = projection.description.replacingOccurrences(
            of: "snapshot.state.\(secondField)", with: "snapshot.state.\(firstField)")
        #expect(wrongProjectionSource != projection.description)
        let wrongProjection = try #require(Parser.parse(source: wrongProjectionSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedFormalProjectionOutput([projectionTokens, wrongProjection], fields: [
                (formalName: firstField, route: "snapshot.state.\(firstField)", type: .int,
                    value: "SwiftTLA._nativeFormalInt(snapshot.state.\(firstField))"),
                (formalName: secondField, route: "snapshot.state.\(secondField)", type: .int,
                    value: "SwiftTLA._nativeFormalInt(snapshot.state.\(firstField))"),
            ])
            Issue.record("A projection routed through the wrong state field was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.actual == "the projected value for \(secondField) reads a different snapshot field")
        }
        let emittedState = try #require(member(named: "State", in: members))
        try verifyGeneratedStateConstructorOutput(emittedState, fields: [
            (name: firstField, type: nativeIntType, ordinal: 0, formalName: firstField),
            (name: secondField, type: nativeIntType, ordinal: 1, formalName: secondField),
        ])
        let wrongStateSource = emittedState.description.replacingOccurrences(
            of: "self.\(secondField) = _value1", with: "self.\(secondField) = _value0")
        #expect(wrongStateSource != emittedState.description)
        let wrongState = Parser.parse(source: wrongStateSource)
        let wrongStateMember = try #require(wrongState.statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedStateConstructorOutput(wrongStateMember, fields: [
                (name: firstField, type: nativeIntType, ordinal: 0, formalName: firstField),
                (name: secondField, type: nativeIntType, ordinal: 1, formalName: secondField),
            ])
        }
        let wrongIdentitySource = emittedState.description.replacingOccurrences(
            of: "formalName: \"\(secondField)\"", with: "formalName: \"\(firstField)\"")
        #expect(wrongIdentitySource != emittedState.description)
        let wrongIdentity = try #require(Parser.parse(source: wrongIdentitySource)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedStateConstructorOutput(wrongIdentity, fields: [
                (name: firstField, type: nativeIntType, ordinal: 0, formalName: firstField),
                (name: secondField, type: nativeIntType, ordinal: 1, formalName: secondField),
            ])
        }
        let wrongApplySource = emittedUpdates.description.replacingOccurrences(
            of: "\(secondSlot) ?? state.state.\(secondField)",
            with: "\(secondSlot) ?? state.state.\(firstField)")
        #expect(wrongApplySource != emittedUpdates.description)
        let wrongApply = Parser.parse(source: wrongApplySource)
        let wrongApplyMember = try #require(wrongApply.statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedUpdateApplyOutput(wrongApplyMember, publicFields: [
                (label: firstField, field: firstField, slot: firstSlot),
                (label: secondField, field: secondField, slot: secondSlot),
            ], hiddenSlots: [])
        }
        let emittedDispatch = try #require(members.first { declaration in
            guard let function = declaration.as(FunctionDeclSyntax.self) else { return false }
            return function.name.text == "_visitSuccessors"
                && function.signature.parameterClause.parameters.contains {
                    $0.firstName.text == "onEvaluationFailure"
                }
        })
        let expectedDispatch = try #require(templateMembers.first { declaration in
            guard let function = declaration.as(FunctionDeclSyntax.self) else { return false }
            return function.name.text == "_visitSuccessors"
                && function.signature.parameterClause.parameters.contains {
                    $0.firstName.text == "onEvaluationFailure"
                }
        })
        #expect(templateBindings(emittedDispatch, expectedDispatch) != nil)
        let wrongFound = Parser.parse(source: emittedDispatch.description.replacingOccurrences(
            of: "found = true", with: "found = false"))
        let wrongFoundMember = try #require(wrongFound.statements.first?.item.as(DeclSyntax.self))
        #expect(templateBindings(wrongFoundMember, expectedDispatch) == nil)
    }

    @Test("A generated write is absent, compatible, or conflicting without changing a rejected value")
    func updateMergeRule() {
        var current: Int? = nil
        #expect(_NativeMachineOperations.mergeUpdate(&current, nil))
        #expect(current == nil)
        #expect(_NativeMachineOperations.mergeUpdate(&current, 3))
        #expect(current == 3)
        #expect(_NativeMachineOperations.mergeUpdate(&current, 3))
        #expect(current == 3)
        #expect(_NativeMachineOperations.mergeUpdate(&current, nil))
        #expect(current == 3)
        #expect(!_NativeMachineOperations.mergeUpdate(&current, 4))
        #expect(current == 3)
    }

    @Test("A captured Boolean reads its compiled state field")
    func capturedBooleanReadsCompiledField() throws {
        let compiled = try GeneratedBooleanCaptureProofModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "GeneratedBooleanCaptureProofModel", program: program))
        let members = try emitter.machineMembers()
        let visitor = try #require(member(named: "_visitUpdates0", in: members))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body, program: program,
            stateFields: emitter.stateMemberNames, parts: writes)
        var wrongSource = visitor.description
        let capturedRead = try #require(wrongSource.range(of: "state.state.mirror"))
        wrongSource.replaceSubrange(capturedRead, with: "state.state.flag")
        let wrong = try #require(Parser.parse(source: wrongSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrong, action: action.body, program: program,
                stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A captured Boolean read the wrong state field")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }
    }

    @Test("A captured Boolean equality uses its compiled operands and operator")
    func capturedBooleanEqualityKeepsCompiledComparison() throws {
        let compiled = try GeneratedBooleanEqualityProofModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        guard case .define(_, let comparison, _) = action.body,
              case .equal = comparison.operation, comparison.children.count == 2,
              case .stateVariable(let lhs) = comparison.children[0].operation,
              case .stateVariable(let rhs) = comparison.children[1].operation else {
            Issue.record("The Boolean source comparison was not lowered to two state reads")
            return
        }
        let variables = program.layout.variables
        #expect(lhs == variables.first(where: { $0.declaration.name == "mirror" })?.id)
        #expect(rhs == variables.first(where: { $0.declaration.name == "flag" })?.id)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "GeneratedBooleanEqualityProofModel", program: program))
        let visitor = try #require(member(named: "_visitUpdates0", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body, program: program,
            stateFields: emitter.stateMemberNames, parts: writes)
        var changedSource = visitor.description
        let equality = try #require(changedSource.range(of: " == "))
        changedSource.replaceSubrange(equality, with: " != ")
        let changed = try #require(Parser.parse(source: changedSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(changed, action: action.body, program: program,
                stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A captured Boolean equality accepted a changed operator")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }

        let rendered = try GeneratedBooleanEqualityProofModel.render().tlaBundle.root.tla
        let declaration = try #require(rendered.split(separator: "\n").first {
            $0.hasPrefix("compare == ")
        })
        #expect(String(declaration) == "compare == (LET __atomic_0 == (mirror = flag) IN (LET __atomic_1 == __atomic_0 IN ((TRUE /\\ flag' = __atomic_1) /\\ UNCHANGED mirror)))")
        #expect(rendered.contains("Init ==\n  /\\ flag = FALSE\n  /\\ mirror = FALSE"))

        let machine = try GeneratedBooleanEqualityProofModel.makeMachine()
        #expect(machine.state.flag == false && machine.state.mirror == false)
        #expect(try machine.formalCall(for: .compare).name == "compare")
        let successor = try #require(machine.successors(for: .compare).first)
        #expect(successor.state.flag && successor.state.mirror == false)
    }

    @Test("A fallible captured equality keeps its checked operand and operator")
    func capturedEqualityKeepsCheckedAddition() throws {
        let compiled = try GeneratedCheckedEqualityProofModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "GeneratedCheckedEqualityProofModel", program: program))
        let visitor = try #require(member(named: "_visitUpdates0", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body, program: program,
            stateFields: emitter.stateMemberNames, parts: writes)
        var changedSource = visitor.description
        let equality = try #require(changedSource.range(of: " == "))
        changedSource.replaceSubrange(equality, with: " != ")
        let changed = try #require(Parser.parse(source: changedSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(changed, action: action.body, program: program,
                stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A captured equality with checked addition accepted a changed operator")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }

        let rendered = try GeneratedCheckedEqualityProofModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedCheckedEqualityProofModel.tla")
            .standardizedFileURL
        #expect(rendered == (try String(contentsOf: proofInput, encoding: .utf8)))

        let machines = try GeneratedCheckedEqualityProofModel.initialMachines()
        #expect(machines.count == 2)
        let passing = try #require(machines.first { $0.state.left == 2 })
        let successor = try #require(passing.successors(for: .compare).first)
        #expect(successor.state.left == 2 && successor.state.right == 3)
        #expect(successor.state.matched)
        var overflowing = try #require(machines.first { $0.state.left == Int.max })
        let before = overflowing.snapshot
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try overflowing.send(.compare)
        }
        #expect(overflowing.snapshot == before)
    }

    @Test("A captured scalar predicate keeps its compiled comparison and negation")
    func capturedPredicateKeepsCompiledOperators() throws {
        let compiled = try GeneratedPredicateCaptureProofModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        guard case .define(_, let predicate, _) = action.body,
              case .not = predicate.operation, predicate.children.count == 1,
              case .lessThan = predicate.children[0].operation,
              predicate.children[0].children.count == 2,
              case .stateVariable(let lhs) = predicate.children[0].children[0].operation,
              case .stateVariable(let rhs) = predicate.children[0].children[1].operation else {
            Issue.record("The source predicate did not lower to negated integer comparison")
            return
        }
        #expect(lhs == program.layout.variables.first(where: { $0.declaration.name == "left" })?.id)
        #expect(rhs == program.layout.variables.first(where: { $0.declaration.name == "right" })?.id)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "GeneratedPredicateCaptureProofModel", program: program))
        let visitor = try #require(member(named: "_visitUpdates0", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body, program: program,
            stateFields: emitter.stateMemberNames, parts: writes)

        for (original, replacement) in [
            (" < ", " > "),
            ("_NativeMachineOperations.booleanNot", "_NativeMachineOperations.booleanOr"),
        ] {
            var source = visitor.description
            let range = try #require(source.range(of: original))
            source.replaceSubrange(range, with: replacement)
            let changed = try #require(Parser.parse(source: source)
                .statements.first?.item.as(DeclSyntax.self))
            do {
                try verifyGeneratedActionWriteOutput(changed, action: action.body, program: program,
                    stateFields: emitter.stateMemberNames, parts: writes)
                Issue.record("A captured predicate accepted a changed operator: \(original)")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.hasPrefix("native.action.binding."))
            }
        }

        let rendered = try GeneratedPredicateCaptureProofModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedPredicateCaptureProofModel.tla")
            .standardizedFileURL
        #expect(rendered == (try String(contentsOf: proofInput, encoding: .utf8)))

        var machine = try GeneratedPredicateCaptureProofModel.makeMachine()
        #expect(machine.state.left == 2 && machine.state.right == 3)
        _ = try machine.send(.compare)
        #expect(machine.state.matched == false)
    }

    @Test("A generated scalar guard evaluates its compiled predicate")
    func scalarGuardKeepsCompiledPredicate() throws {
        let compiled = try GeneratedScalarGuardProofModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "GeneratedScalarGuardProofModel", program: program))
        let visitor = try #require(member(named: "_visitUpdates0", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body, program: program,
            stateFields: emitter.stateMemberNames, parts: writes)

        var source = visitor.description
        let comparison = try #require(source.range(of: " < "))
        source.replaceSubrange(comparison, with: " > ")
        let changed = try #require(Parser.parse(source: source)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(changed, action: action.body, program: program,
                stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("The generated scalar guard accepted a changed predicate")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.guard."))
        }

        let write = try #require(writes.first)
        let replacement = write.value == "false" ? "true" : "false"
        let originalWrite = "_Updates(\(write.slot): \(write.value))"
        let changedWrite = "_Updates(\(write.slot): \(replacement))"
        #expect(visitor.description.contains(originalWrite))
        let wrongAssignment = try #require(Parser.parse(source:
            visitor.description.replacingOccurrences(of: originalWrite, with: changedWrite))
            .statements.first?.item.as(DeclSyntax.self))
        let selfConsistentWrongWrites = writes.map {
            (id: $0.id, slot: $0.slot, value: $0.id == write.id ? replacement : $0.value)
        }
        do {
            try verifyGeneratedActionWriteOutput(wrongAssignment, action: action.body, program: program,
                stateFields: emitter.stateMemberNames, parts: selfConsistentWrongWrites)
            Issue.record("A generated assignment changed the compiled value")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.write.\(write.id)")
        }

        let rendered = try GeneratedScalarGuardProofModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedScalarGuardProofModel.tla")
            .standardizedFileURL
        #expect(rendered == (try String(contentsOf: proofInput, encoding: .utf8)),
            "Actual generated TLA+: \(rendered)")

        let machines = try GeneratedScalarGuardProofModel.initialMachines()
        #expect(machines.count == 2)
        var enabled = try #require(machines.first { $0.state.left == 2 })
        let disabled = try #require(machines.first { $0.state.left == 4 })
        #expect(enabled.state.right == 3 && !enabled.state.advanced)
        _ = try enabled.send(.advance)
        #expect(enabled.state.advanced)
        #expect(try disabled.successors(for: .advance).isEmpty)
    }

    @Test("A String guard preserves its equality and complete labeled step")
    func stringGuardPreservesEqualityAndLabeledStep() throws {
        let compiled = try GeneratedStringGuardProofModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "GeneratedStringGuardProofModel", program: program))
        let visitor = try #require(member(named: "_visitUpdates0", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body, program: program,
            stateFields: emitter.stateMemberNames, parts: writes)

        let source = visitor.description
        let changed = source.replacingOccurrences(
            of: "state.state.left == state.state.right",
            with: "state.state.left != state.state.right")
        #expect(changed != source)
        let mutant = try #require(Parser.parse(source: changed)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(mutant, action: action.body, program: program,
                stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A changed String comparison was accepted inside the Boolean guard")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.guard."))
        }
        let omittedGuard = source.replacingOccurrences(
            of: "state.state.left == state.state.right", with: "true")
        #expect(omittedGuard != source)
        let omittedGuardMutant = try #require(Parser.parse(source: omittedGuard)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(omittedGuardMutant, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("An omitted String comparison was accepted inside the Boolean guard")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.guard."))
        }
        let inequality = "state.state.left != SwiftTLA._NativeString(formalString: \"beta\")"
        try #require(source.components(separatedBy: inequality).count == 2)
        let invertedInequality = source.replacingOccurrences(of: inequality,
            with: "state.state.left == SwiftTLA._NativeString(formalString: \"beta\")")
        try #require(invertedInequality != source)
        let inequalityMutant = try #require(Parser.parse(source: invertedInequality)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(inequalityMutant, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A changed String inequality was accepted inside the Boolean guard")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.guard."))
        }

        let rendered = try GeneratedStringGuardProofModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedStringGuardProofModel.tla")
            .standardizedFileURL
        #expect(rendered == (try String(contentsOf: proofInput, encoding: .utf8)),
            "Actual generated TLA+: \(rendered)")

        let machines = try GeneratedStringGuardProofModel.initialMachines()
        #expect(machines.count == 2)
        let machine = try #require(machines.first { $0.state.left == "alpha" })
        let disabled = try #require(machines.first { $0.state.left == "beta" })
        #expect(machine.state.left == "alpha")
        #expect(machine.state.right == "alpha")
        #expect(!machine.state.advanced)
        let successors = try machine.successors(for: .advance)
        #expect(successors.count == 1)
        let successor = try #require(successors.first)
        #expect(successor.state.left == "alpha")
        #expect(successor.state.right == "alpha")
        #expect(successor.state.advanced)
        #expect(disabled.state.right == "alpha")
        #expect(!disabled.state.advanced)
        #expect(try disabled.successors(for: .advance).isEmpty)
    }

    @Test("A generated collection guard retains its predicate")
    func collectionGuardRetainsPredicate() throws {
        let compiled = try SetStepMachine.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        #expect(program.behavior.actions.count == 2)
        let action = try #require(program.behavior.actions.last)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "SetStepMachine", program: program))
        let visitor = try #require(member(named: "_visitUpdates1", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames, parts: writes)
        let source = visitor.description
        let omitted = source.replacingOccurrences(
            of: #"guard [^\n]+ else \{ return \}\s*try emit\(updates\)"#,
            with: "try emit(updates)", options: .regularExpression)
        #expect(omitted != source)
        let mutant = try #require(Parser.parse(source: omitted)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(mutant, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A generated collection step accepted an omitted guard")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.guard."))
        }
        let unconditional = source.replacingOccurrences(
            of: #"guard [^\n]+ else \{ return \}"#,
            with: "guard true else { return }", options: .regularExpression)
        #expect(unconditional != source)
        let unconditionalMutant = try #require(Parser.parse(source: unconditional)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(unconditionalMutant, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A generated collection step accepted an unconditional guard")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.guard."))
        }
    }

    @Test("A generated array step retains its compiled guard and appended value")
    func arrayStepRetainsGuardAndValue() throws {
        let compiled = try ArrayStepMachine.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "ArrayStepMachine", program: program))
        let visitor = try #require(member(named: "_visitUpdates0", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames, parts: writes)
        let omitted = visitor.description.replacingOccurrences(
            of: #"guard [^\n]+ else \{ return \}\s*try emit\(updates\)"#,
            with: "try emit(updates)", options: .regularExpression)
        #expect(omitted != visitor.description)
        let mutant = try #require(Parser.parse(source: omitted)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(mutant, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A generated array step accepted an omitted guard")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.guard."))
        }
        let changedBound = visitor.description.replacingOccurrences(of: "< 2", with: "< 3")
        #expect(changedBound != visitor.description)
        let changedBoundMutant = try #require(Parser.parse(source: changedBound)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(changedBoundMutant, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A generated array step accepted a changed length bound")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.guard."))
        }
        let originalAppend = "_NativeMachineOperations.sequenceAppend(_sequenceValue, _appendedValue)"
        let changedAppend = "_sequenceValue"
        let wrongVisitorSource = visitor.description.replacingOccurrences(
            of: originalAppend, with: changedAppend)
        #expect(wrongVisitorSource != visitor.description)
        let wrongVisitor = try #require(Parser.parse(source: wrongVisitorSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongVisitor, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A generated array step accepted an omitted appended element")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }
    }

    @Test("Pure sequence append and concatenation retain their actual Swift and TLA operands")
    func sequenceConcatenationRetainsOrder() throws {
        let specification = #spec("SequenceExpressionOutput") { scope in
            let front = scope.sharedVar(initial: [Int]([1]))
            let back = scope.sharedVar(initial: [Int]([2, 2]))
            Do(SequenceConcatenationMachine.Step.combine) {
                Assign(front, to: front.appending(3).concatenating(back))
            }
        }
        let compiled = try specification.compile()
        let sourceAction = try #require(try specification.loweredSourceModel().actions.first)
        let untypedAction = try #require(compiled.semantics.behavior.actions.first)
        try StraightLineAssignmentCheck.verifyCompiled(sourceAction,
            bindings: untypedAction.bindings, body: untypedAction.body, layout: compiled.layout)
        for mutation in ["append read", "concatenation read", "concatenation order",
                         "appended element", "omitted append", "changed constructor"] {
            var changed = 0
            let body = untypedAction.body.map { expression in
                guard expression.operation == .tupleConcatenate,
                      expression.children.count == 2 else { return expression }
                let append = expression.children[0]
                guard append.operation == .tupleAppend, append.children.count == 2 else {
                    return expression
                }
                let sequence = append.children[0]
                let element = append.children[1]
                let right = expression.children[1]
                let operands: [CompiledExpression]
                switch mutation {
                case "append read":
                    operands = [.init(operation: .tupleAppend, resultType: append.resultType,
                        children: [right, element]), right]
                case "concatenation read": operands = [append, sequence]
                case "concatenation order": operands = [right, append]
                case "appended element":
                    operands = [.init(operation: .tupleAppend, resultType: append.resultType,
                        children: [sequence, .init(operation: .value(.integer(4)),
                            resultType: element.resultType, children: [])]), right]
                case "omitted append": operands = [sequence, right]
                default:
                    changed += 1
                    return append
                }
                changed += 1
                return .init(operation: expression.operation, resultType: expression.resultType,
                    children: operands)
            }
            try #require(changed == 1)
            do {
                try StraightLineAssignmentCheck.verifyCompiled(sourceAction,
                    bindings: untypedAction.bindings, body: body, layout: compiled.layout)
                Issue.record("Sequence \(mutation) escaped normalized-source verification")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "actions.\(sourceAction.name).compiledAssignments")
            }
        }
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "SequenceExpressionOutput", program: program))
        let visitor = try #require(member(named: "_visitUpdates0", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames, parts: writes)
        let swapped = visitor.description.replacingOccurrences(
            of: "sequenceConcatenate(_leftElements, _rightElements)",
            with: "sequenceConcatenate(_rightElements, _leftElements)")
        #expect(swapped != visitor.description)
        let mutant = try #require(Parser.parse(source: swapped)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(mutant, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A generated concatenation accepted reversed operands")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }
        let changedAppend = visitor.description.replacingOccurrences(
            of: "sequenceAppend(_sequenceValue, _appendedValue)",
            with: "sequenceAppend(_sequenceValue, 4)")
        #expect(changedAppend != visitor.description)
        let wrongElement = try #require(Parser.parse(source: changedAppend)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongElement, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A nested append accepted a changed element")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }

        let output = try program.renderModule()
        let renderer = CompiledTLARenderer(moduleName: program.moduleName,
            reservedNames: [], layout: program.layout,
            bindings: .init(binders: program.binderNames), operators: .init(),
            actions: program.behavior.actions, functions: program.functions,
            enums: program.enums, parameterDomains: program.behavior.parameterDomains)
        let rendered = try renderer.action(action.body)
        #expect(output.renderedModuleSource.contains(rendered))
        try StraightLineRenderedActionCheck.verify(action.body, rendered: rendered,
            layout: program.layout, binders: program.binderNames, required: true)
        for (original, replacement) in [
            ("(Append(front, 3) \\o back)", "(back \\o Append(front, 3))"),
            ("Append(front, 3)", "Append(back, 3)"),
            ("Append(front, 3)", "Append(front, 4)"),
        ] {
            let changed = rendered.replacingOccurrences(of: original, with: replacement)
            #expect(changed != rendered)
            do {
                try StraightLineRenderedActionCheck.verify(action.body, rendered: changed,
                    layout: program.layout, binders: program.binderNames, required: true)
                Issue.record("The actual TLA sequence output accepted a changed operand")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "tla.action.scalarAssignments")
            }
        }
    }

    @Test("Nested sequence operands retain their evaluation and concatenation order")
    func nestedSequenceConcatenationRetainsOrder() throws {
        let compiled = try FallibleSequenceConcatenationMachine.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "FallibleSequenceConcatenationMachine", program: program))
        let visitor = try #require(member(named: "_visitUpdates0", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames, parts: writes)
        let swapped = visitor.description.replacingOccurrences(
            of: "sequenceConcatenate(_leftElements, _rightElements)",
            with: "sequenceConcatenate(_rightElements, _leftElements)")
        #expect(swapped != visitor.description)
        let mutant = try #require(Parser.parse(source: swapped)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(mutant, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A nested concatenation accepted reversed operands")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }
        let wrongLength = visitor.description.replacingOccurrences(
            of: "let _prefixLength = state.state.frontLength",
            with: "let _prefixLength = state.state.backLength")
        #expect(wrongLength != visitor.description)
        let wrongLengthVisitor = try #require(Parser.parse(source: wrongLength)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongLengthVisitor, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A nested concatenation accepted the wrong first prefix length")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }
    }

    @Test("Nested append retains its prefix length and element")
    func nestedSequenceAppendRetainsOperands() throws {
        let compiled = try FallibleSequenceAppendMachine.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "FallibleSequenceAppendMachine", program: program))
        let visitor = try #require(member(named: "_visitUpdates0", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames, parts: writes)
        let wrongLength = visitor.description.replacingOccurrences(
            of: "let _prefixLength = state.state.length",
            with: "let _prefixLength = state.state.values.count")
        #expect(wrongLength != visitor.description)
        let mutant = try #require(Parser.parse(source: wrongLength)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(mutant, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A nested append accepted the wrong prefix length")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }
    }

    @Test("Sequence length retains its fallible prefix operand")
    func nestedSequenceLengthRetainsPrefix() throws {
        let compiled = try FallibleSequenceLengthMachine.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "FallibleSequenceLengthMachine", program: program))
        let visitor = try #require(member(named: "_visitUpdates0", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames, parts: writes)
        let wrongLength = visitor.description.replacingOccurrences(
            of: "let _prefixLength = state.state.length",
            with: "let _prefixLength = state.state.values.count")
        #expect(wrongLength != visitor.description)
        let mutant = try #require(Parser.parse(source: wrongLength)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(mutant, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("Sequence length accepted a changed prefix length")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }
    }

    @Test("Sequence head retains its fallible prefix operand")
    func nestedSequenceHeadRetainsPrefix() throws {
        let compiled = try FallibleSequenceHeadMachine.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "FallibleSequenceHeadMachine", program: program))
        let visitor = try #require(member(named: "_visitUpdates0", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames, parts: writes)
        let wrongLength = visitor.description.replacingOccurrences(
            of: "let _prefixLength = state.state.length",
            with: "let _prefixLength = state.state.values.count")
        #expect(wrongLength != visitor.description)
        let mutant = try #require(Parser.parse(source: wrongLength)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(mutant, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("Sequence head accepted a changed prefix length")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }
    }

    @Test("Sequence head retains its compiled array operand")
    func sequenceHeadRetainsOperand() throws {
        let compiled = try EmptySequenceReadMachine.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        #expect(program.behavior.actions.count == 2)
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "EmptySequenceReadMachine", program: program))
        let visitor = try #require(member(named: "_visitUpdates0", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames, parts: writes)
        let wrongSource = visitor.description.replacingOccurrences(
            of: "sequenceHead(state.state.sequence)", with: "sequenceHead([\(nativeIntType)]())")
        #expect(wrongSource != visitor.description)
        let mutant = try #require(Parser.parse(source: wrongSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(mutant, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("Sequence head accepted a changed array operand")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }
    }

    @Test("Sequence tail retains its compiled array operand")
    func sequenceTailRetainsOperand() throws {
        let compiled = try EmptySequenceReadMachine.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        #expect(program.behavior.actions.count == 2)
        let action = try #require(program.behavior.actions.last)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "EmptySequenceReadMachine", program: program))
        let visitor = try #require(member(named: "_visitUpdates1", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames, parts: writes)
        let wrongSource = visitor.description.replacingOccurrences(
            of: "sequenceTail(state.state.sequence)", with: "sequenceTail([\(nativeIntType)]())")
        #expect(wrongSource != visitor.description)
        let mutant = try #require(Parser.parse(source: wrongSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(mutant, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("Sequence tail accepted a changed array operand")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }
    }

    @Test("Sequence edits retain their compiled sequence and index operands")
    func sequenceEditsRetainOperands() throws {
        let compiled = try SequenceEditBoundsMachine.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        #expect(program.behavior.actions.count == 2)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "SequenceEditBoundsMachine", program: program))
        let members = try emitter.machineMembers()
        for (actionIndex, original, replacement) in [
            (0, "let _sequenceValue = state.state.row", "let _sequenceValue = [\(nativeIntType)]()"),
            (0, "let _sequenceIndex = state.state.position", "let _sequenceIndex = 1"),
            (1, "let _sequenceValue = state.state.row", "let _sequenceValue = [\(nativeIntType)]()"),
            (1, "let _prefixLength = state.state.position", "let _prefixLength = 1")
        ] {
            let action = program.behavior.actions[actionIndex]
            let visitor = try #require(member(named: "_visitUpdates\(actionIndex)", in: members))
            let writes = try emitter.actionFunctions(action).writes
            try verifyGeneratedActionWriteOutput(visitor, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            let wrongOperand = visitor.description.replacingOccurrences(
                of: original, with: replacement)
            #expect(wrongOperand != visitor.description)
            let mutant = try #require(Parser.parse(source: wrongOperand)
                .statements.first?.item.as(DeclSyntax.self))
            do {
                try verifyGeneratedActionWriteOutput(mutant, action: action.body,
                    program: program, stateFields: emitter.stateMemberNames, parts: writes)
                Issue.record("A sequence edit accepted a changed compiled operand: \(original)")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.hasPrefix("native.action.binding."))
            }
        }
    }

    @Test("Indexed sequence reads retain their compiled operands")
    func indexedSequenceReadRetainsOperands() throws {
        let compiled = try ArrayReadOutsideDomainMachine.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "ArrayReadOutsideDomainMachine", program: program))
        let visitor = try #require(member(named: "_visitUpdates0", in: emitter.machineMembers()))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames, parts: writes)
        for (original, replacement) in [
            ("let _sequenceValue = state.state.sequence", "let _sequenceValue = [\(nativeIntType)]()"),
            ("let _sequenceIndex = 1", "let _sequenceIndex = 2")
        ] {
            let wrongOperand = visitor.description.replacingOccurrences(of: original, with: replacement)
            #expect(wrongOperand != visitor.description)
            let mutant = try #require(Parser.parse(source: wrongOperand)
                .statements.first?.item.as(DeclSyntax.self))
            do {
                try verifyGeneratedActionWriteOutput(mutant, action: action.body,
                    program: program, stateFields: emitter.stateMemberNames, parts: writes)
                Issue.record("An indexed sequence read accepted a changed operand: \(original)")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.hasPrefix("native.action.binding."))
            }
        }
    }

    @Test("A generated scalar conditional selects its compiled predicate")
    func scalarConditionalKeepsCompiledPredicate() throws {
        let compiled = try GeneratedScalarConditionalProofModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "GeneratedScalarConditionalProofModel", program: program))
        let members = try emitter.machineMembers()
        let visitor = try #require(member(named: "_visitUpdates0", in: members))
        let parts = try emitter.actionFunctions(action)
        try verifyGeneratedActionWriteOutput(visitor, action: action.body, program: program,
            stateFields: emitter.stateMemberNames, parts: parts.writes, conditions: parts.conditions)

        let condition = try #require(parts.conditions.first)
        let replacement = condition.value == "false" ? "true" : "false"
        let original = "visitConditional({ \(condition.value) }"
        let changed = "visitConditional({ \(replacement) }"
        #expect(visitor.description.contains(original))
        let wrongCondition = try #require(Parser.parse(source:
            visitor.description.replacingOccurrences(of: original, with: changed))
            .statements.first?.item.as(DeclSyntax.self))
        let selfConsistentWrongConditions = parts.conditions.map {
            (id: $0.id, value: $0.id == condition.id ? replacement : $0.value)
        }
        do {
            try verifyGeneratedActionWriteOutput(wrongCondition, action: action.body,
                program: program, stateFields: emitter.stateMemberNames,
                parts: parts.writes, conditions: selfConsistentWrongConditions)
            Issue.record("A generated conditional changed its compiled predicate")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.conditional.\(condition.id)")
        }

        let rendered = try GeneratedScalarConditionalProofModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedScalarConditionalProofModel.tla")
            .standardizedFileURL
        #expect(rendered == (try String(contentsOf: proofInput, encoding: .utf8)),
            "Actual generated TLA+: \(rendered)")

        let native = members.map(\.description).joined(separator: "\n")
        let trueWrite = try #require(parts.writes.first {
            $0.slot.hasPrefix("_value_selected_") &&
                ($0.value == "true" || visitor.description.contains("let \($0.value) = true"))
        })
        let correctWrite = "_Updates(\(trueWrite.slot): \(trueWrite.value))"
        try #require(native.components(separatedBy: correctWrite).count == 2)
        let changedWrite = native.replacingOccurrences(of: correctWrite, with: "_Updates(\(trueWrite.slot): false)")
        let owner = packageRoot().appendingPathComponent(
            "Sources/UpstreamParity/ValidationModels/GeneratedScalarConditionalProofModel.swift")
        let authored = try Data(contentsOf: owner)
        try checkScopedConditionalOperands(in: String(decoding: authored, as: UTF8.self))
        let proof = try Data(contentsOf: proofInput.deletingLastPathComponent()
            .appendingPathComponent("GeneratedScalarConditionalProof.tla"))
        let evidenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: evidenceRoot) }
        for (name, source) in [("positive", native), ("changed-write", changedWrite)] {
            try ConditionalActionEvidence.prepare(sourceSHA: String(repeating: "a", count: 40),
                authoredSource: authored, nativeSource: Data(source.utf8), proofSource: proof,
                to: evidenceRoot.appendingPathComponent(name))
        }
        func physicalPlan(_ name: String) throws -> Substring {
            let input = evidenceRoot.appendingPathComponent(name).appendingPathComponent("GeneratedScalarConditionalNative.tla")
            let text = try String(contentsOf: input, encoding: .utf8)
            return try #require(text.split(separator: "\n").first { $0.hasPrefix("NativeChoosePlans == ") })
        }
        #expect(try physicalPlan("changed-write") != physicalPlan("positive"))
        #expect(try physicalPlan("changed-write").contains("<<\"selected\", <<\"literal\", FALSE>>>>"))

        let machines = try GeneratedScalarConditionalProofModel.initialMachines()
        #expect(machines.count == 2)
        #expect(Set(machines.map(\.state.left)) == Set([2, 4]))
        #expect(machines.allSatisfy { $0.state.right == 3 && !$0.state.selected })
        for machine in machines {
            var selected = machine
            _ = try selected.send(.choose)
            #expect(selected.state.selected == (machine.state.left < machine.state.right))
        }
    }

    private func checkScopedConditionalOperands(in source: String) throws {
        let yes = "Assign(selected, to: true)"
        let no = "Assign(selected, to: false)"
        try #require(source.components(separatedBy: yes).count == 2)
        try #require(source.components(separatedBy: no).count == 2)
        let changed = source
            .replacingOccurrences(of: yes, with: """
                Assign(left, to: (right + 1) + 2)
                Assign(left, to: left + 2)
                Assign(right, to: left + 3)
                \(yes)
                """)
            .replacingOccurrences(of: no, with: """
                Assign(right, to: left + 4)
                Assign(right, to: right + 5)
                Assign(left, to: right + 6)
                \(no)
                """)
        let declaration = try #require(Parser.parse(source: changed).statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "GeneratedScalarConditionalProofModel" })
        let compilation = try TLASpecVerifier.parseAndVerify(declaration)
        let program = compilation.program
        let action = try #require(program.behavior.actions.first)
        let rendered = try program.renderModule()
        let tla = rendered.renderedModuleSource
        let decoded = try #require(OrderedRHSPhysicalAction.decodeConditional(in: tla, action: action, program: program))
        let first = decoded.ifTrue.action
        let second = decoded.ifFalse.action
        for (arm, original, final) in [(first, "right", "left"), (second, "left", "right")] {
            try #require(arm.captures.count == 4)
            #expect(arm.captures[0].plan.reads.first == .tuple([.string("state"), .string(original)]))
            #expect(arm.captures[1].plan.reads.first == .tuple([.string("capture"), .int(1)]))
            #expect(arm.captures[2].plan.reads.first == .tuple([.string("capture"), .int(2)]))
            #expect(arm.writes[final] == .tuple([.string("capture"), .int(2)]))
            #expect(arm.writes[original] == .tuple([.string("capture"), .int(3)]))
        }
        let evidence = try #require(decoded.overflowProbes(in: rendered, actionOrdinal: action.id.ordinal,
            namedHistory: "__SwiftTLAActionFailureHistory\(action.id.ordinal)",
            regions: action.body.orderedAlternativeFailureRegions, program: program))
        #expect(evidence.sites.map(\.owner) == [.arm(0), .arm(0), .arm(0), .arm(0), .arm(1), .arm(1), .arm(1)])
        #expect(evidence.sites.map(\.row) == [1, 1, 2, 3, 1, 2, 3])
        #expect(evidence.sites.map(\.node) == [3, 5, 3, 3, 3, 3, 3])
        let local = "left' = \(second.captures[2].binding)"
        try #require(tla.components(separatedBy: local).count == 2)
        let wrong = tla.replacingOccurrences(of: local, with: "left' = \(first.captures[0].binding)")
        try #require(wrong != tla)
        #expect(OrderedRHSPhysicalAction.decodeConditional(in: wrong, action: action, program: program) == nil)

        var emitter = NativeSwiftEmitter(model: compilation)
        let native = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        let predicate = Parser.parse(source: "(state.state.left < state.state.right)")
            .tokens(viewMode: .sourceAccurate).filter { $0.tokenKind != .endOfFile }.map(\.text)
        let emitted = try nativeConditionalActionPlans(native, program: program, predicate: predicate)
        for (observed, rendered) in [(emitted.ifTrue, decoded.ifTrue), (emitted.ifFalse, decoded.ifFalse)] {
            let sites = rendered.action.captures.enumerated().compactMap { $0.element.additionNodes.isEmpty ? nil : $0.offset + 1 }
            let expected = try conditionalArmOperands(rendered.action.captures.map(\.plan), writeOrder: rendered.writeOrder,
                writes: rendered.action.writes, failureAppendSites: sites)
            #expect(try observed.operands() == expected)
        }

        func nativeLocal(_ name: String) throws -> String {
            let binder = try #require(program.binderNames.first { $0.value == name }?.key)
            return "_\(name)_\(binder.ordinal)"
        }
        let originalRead = "let _arithmetic0: \(nativeIntTypeTokens.joined()) = \(try nativeLocal(second.captures[0].binding))"
        let crossedRead = "let _arithmetic0: \(nativeIntTypeTokens.joined()) = \(try nativeLocal(first.captures[0].binding))"
        try #require(native.components(separatedBy: originalRead).count == 2)
        let wrongNative = native.replacingOccurrences(of: originalRead, with: crossedRead)
        #expect(throws: InitialFailureEvidenceError.unsupportedGeneratedOutput) {
            try nativeConditionalActionPlans(wrongNative, program: program, predicate: predicate)
        }

        let region = try #require(action.body.orderedAlternativeFailureRegions.first { $0.armOrdinal == 1 })
        try #require(region.bindings.count >= 3)
        let prior = region.bindings[0], site = region.bindings[2]
        try #require(prior.target != site.target)
        let preceding = "binding: \(prior.binder.ordinal), target: \(prior.target.ordinal)"
        let route = "branch: 1, site: \(site.binder.ordinal), target: \(site.target.ordinal), before: [(\(preceding),"
        try #require(native.components(separatedBy: route).count == 2)
        for tampered in [route.replacingOccurrences(of: "branch: 1", with: "branch: 0"),
                         route.replacingOccurrences(of: preceding,
                            with: "binding: \(prior.binder.ordinal), target: \(site.target.ordinal)")] {
            let wrongObserver = native.replacingOccurrences(of: route, with: tampered)
            #expect(throws: InitialFailureEvidenceError.unsupportedGeneratedOutput) {
                try nativeConditionalActionPlans(wrongObserver, program: program, predicate: predicate)
            }
        }
    }

    @Test("Ordered copy emission is independent of field names")
    func generatedCopyRuleUsesResolvedFieldNames() throws {
        let model = try compiledProofModel(named: "RenamedAtomicCopyProofModel")
        var emitter = NativeSwiftEmitter(model: model)
        let members = try emitter.machineMembers()
        let templateFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/GeneratedAtomicCopySwiftTemplate.txt")
            .standardizedFileURL
        let template = Parser.parse(source: nativeWitnessSource(try String(contentsOf: templateFile, encoding: .utf8)))
        let bindings = try checkedTransitionBindings(
            members, template.statements.compactMap { $0.item.as(DeclSyntax.self) })
        #expect(bindings["__PROOF_FIRST_FIELD__"] == "left")
        #expect(bindings["__PROOF_SECOND_FIELD__"] == "right")
        #expect(bindings["__PROOF_READ__"] == "right")
        #expect(bindings["__PROOF_ACTION__"] == "copy")
    }

    @Test("Do lowering captures the ordered copy as complete compiled updates")
    func compiledCopyKeepsOrderedReadsAndTargets() throws {
        for (modelName, firstName, secondName) in [
            ("GeneratedAtomicCopyProofModel", "first", "second"),
            ("RenamedAtomicCopyProofModel", "left", "right"),
        ] {
            let program = try compiledProofModel(named: modelName).program
            let variables = program.layout.variables
            let first = try #require(variables.first { $0.declaration.name == firstName })
            let second = try #require(variables.first { $0.declaration.name == secondName })
            let action = try #require(program.behavior.actions.first)
            guard variables.count == 2, program.behavior.actions.count == 1, action.bindings.isEmpty,
                  case .define(let firstCapture, let firstRead, let firstTail) = action.body,
                  case .stateVariable(let source) = firstRead.operation,
                  case .define(let secondCapture, let secondRead, let writes) = firstTail,
                  case .boundValue(let copiedFirst) = secondRead.operation,
                  case .and(let firstPart, let secondWrite) = writes,
                  case .and(let guardPart, let firstWrite) = firstPart,
                  case .guard_(let guardValue) = guardPart,
                  case .value(.boolean(true)) = guardValue.operation,
                  case .assign(let firstTarget, let firstValue) = firstWrite,
                  case .boundValue(let firstValueBinding) = firstValue.operation,
                  case .assign(let secondTarget, let secondValue) = secondWrite,
                  case .boundValue(let secondValueBinding) = secondValue.operation else {
                Issue.record("The compiled action no longer has the proved ordered-copy structure")
                return
            }
            #expect(source == second.id)
            #expect(copiedFirst == firstCapture)
            #expect(firstTarget == first.id && firstValueBinding == firstCapture)
            #expect(secondTarget == second.id && secondValueBinding == secondCapture)
            let onlyLeafExpressions = [firstRead, secondRead, guardValue, firstValue, secondValue]
                .allSatisfy { $0.children.isEmpty }
            #expect(onlyLeafExpressions)
        }
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

        let stateNames = try compiledProofModel().program.layout.variables.map(\.declaration.name)
        let missingVariable = rendered.replacingOccurrences(
            of: "VARIABLES first, second\n", with: "VARIABLES first\n")
        #expect(missingVariable != rendered)
        do {
            try verifyRenderedVariableDeclaration(missingVariable, names: stateNames)
            Issue.record("A missing emitted state variable was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.variables")
            #expect(diagnostic.actual == "VARIABLES first")
        }

        let copyDefinition = "copy == (LET __atomic_0 == second IN (LET __atomic_1 == __atomic_0 IN ((TRUE /\\ first' = __atomic_0) /\\ second' = __atomic_1)))"
        try verifyRenderedActionDeclarations(rendered, declarations: [("copy", copyDefinition)])
        let changedAction = rendered.replacingOccurrences(
            of: "second' = __atomic_1", with: "second' = first")
        #expect(changedAction != rendered)
        do {
            try verifyRenderedActionDeclarations(changedAction, declarations: [("copy", copyDefinition)])
            Issue.record("A changed emitted action was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.actions.copy")
        }

        let machine = try GeneratedAtomicCopyProofModel.makeMachine()
        #expect(try machine.formalCall(for: .copy).name == "copy")
        let successors = try machine.successors(for: .copy)
        #expect(successors.count == 1)
        let successor = try #require(successors.first)
        #expect(machine.state.first == 0 && machine.state.second == 1)
        #expect(successor.state.first == 1 && successor.state.second == 1)
        let dispatched = try machine.successors()
        #expect(dispatched.count == 1)
        #expect(dispatched.first?.action == .copy)
        #expect(dispatched.first?.machine.state.first == 1)
        #expect(dispatched.first?.machine.state.second == 1)
    }

    private func checkedInitialValues(_ source: String) throws -> (first: Int, second: Int)? {
        let integerType = NSRegularExpression.escapedPattern(for: nativeIntType)
        let pattern = #"""
        \A private \s+ static \s+ func \s+ _initialStates
        \( _selectedInitial: \s* State\? \s* = \s* nil \)
        \s* throws \s* -> \s* SwiftTLA\.InitialEvaluationOutcomes \s* < \s* Snapshot \s* > \s* \{
        \s* var \s+ result: \s* \[Snapshot\] \s* = \s* \[\]
        \s* var \s+ failures: \s* \[SwiftTLA\.InitialEvaluationFailure\] \s* = \s* \[\]
        \s* var \s+ evaluatingInitializerOrdinal: \s* \#(integerType)\?
        \s* var \s+ evaluatingInitialBindings: \s* @Sendable \s* \(\) \s* throws \s* -> \s* SwiftTLA\.TLAStateProjection
        \s* = \s* \{ \s* try \s+ SwiftTLA\._nativeFormalProjection \( \s* \[\] \) \s* \}
        \s* try \s+ SwiftTLA\._visitNativeInitialBranch \s* \( \s* \{
        \s* evaluatingInitialBindings \s* = \s* \{ \s* try \s+ SwiftTLA\._nativeFormalProjection \( \s* \[\] \) \s* \}
        \s* evaluatingInitializerOrdinal \s* = \s* 0
        \s* let \s+ _value_first_0: \s* \#(integerType) \s* = \s* (-?[0-9]+)
        \s* evaluatingInitializerOrdinal \s* = \s* nil
        \s* if \s+ SwiftTLA\._nativeIntInitialMatches \( _selectedInitial\?\.first, \s* _value_first_0 \) \s* \{
        \s* evaluatingInitialBindings \s* = \s* \{ \s* \[_value_first_0\] \s+ in
        \s* try \s+ SwiftTLA\._nativeFormalProjection \( \s* \[
        SwiftTLA\._nativeFormalProjectionEntry\(Self\.__swifttlaFormalProjectionTokens,\s*at:\s*0,
        \s* value: \s* SwiftTLA\._nativeFormalInt\(_value_first_0\) \) \] \) \s* \}
        \s* evaluatingInitializerOrdinal \s* = \s* 1
        \s* let \s+ _value_second_1: \s* \#(integerType) \s* = \s* (-?[0-9]+)
        \s* evaluatingInitializerOrdinal \s* = \s* nil
        \s* if \s+ SwiftTLA\._nativeIntInitialMatches \( _selectedInitial\?\.second, \s* _value_second_1 \) \s* \{
        \s* SwiftTLA\._appendNativeOutcome \( &result, \s* Snapshot \( state: \s* State \( first: \s* _value_first_0, \s* second: \s* _value_second_1 \) \) \)
        \s* \} \s* \}
        \s* \}, \s* onEvaluationFailure: \s* \{ \s* failure \s+ in
        \s* SwiftTLA\._appendNativeOutcome \( &failures, \s* SwiftTLA\._nativeInitialFailure \(
        \s* evaluatingInitializerOrdinal,
        \s* failure: \s* failure, \s* projectingBefore: \s* evaluatingInitialBindings \) \)
        \s* \} \s* \)
        \s* return \s+ SwiftTLA\._nativeInitialOutcomes \s* \( \s* states: \s* result, \s* failures: \s* failures \)
        \s* \} \s* \z
        """#
        let regex = try NSRegularExpression(pattern: pattern, options: .allowCommentsAndWhitespace)
        let text = source as NSString
        guard let match = regex.firstMatch(in: source, range: NSRange(location: 0, length: text.length)),
              match.range == NSRange(location: 0, length: text.length),
              let first = Int(text.substring(with: match.range(at: 1))),
              let second = Int(text.substring(with: match.range(at: 2))) else { return nil }
        return (first, second)
    }

    private func compiledProofModel(named name: String = "GeneratedAtomicCopyProofModel") throws -> MacroCompilation {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("GeneratedAtomicUpdateProofFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(source.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == name })
        return try TLASpecVerifier.parseAndVerify(declaration)
    }

    private func checkedTransitionBindings(
        _ actualMembers: [DeclSyntax], _ templateMembers: [DeclSyntax]
    ) throws -> [String: String] {
        var all: [String: String] = [:]
        let declarations: [(String, Int?)] = [
            ("_Updates", nil), ("_visitUpdates0", 3), ("_visitSuccessors0", 3),
            ("visitSuccessors", 2), ("_visitActionCandidates", 1),
            ("_visitSuccessors", 3), ("_visitSuccessors", 2),
        ]
        for (name, parameterCount) in declarations {
            let emitted = try #require(member(named: name, parameterCount: parameterCount, in: actualMembers))
            let expected = try #require(member(named: name, parameterCount: parameterCount, in: templateMembers))
            let bindings = try #require(templateBindings(emitted, expected))
            for (key, value) in bindings {
                if let previous = all[key] { _ = try #require(previous == value) }
                all[key] = value
            }
        }
        return all
    }

    private func member(named name: String, parameterCount: Int? = nil, in declarations: [DeclSyntax]) -> DeclSyntax? {
        declarations.first { item in
            if let function = item.as(FunctionDeclSyntax.self) {
                return function.name.text == name && (parameterCount == nil
                    || function.signature.parameterClause.parameters.count == parameterCount)
            }
            return parameterCount == nil && (item.as(StructDeclSyntax.self)?.name.text == name
                || item.as(VariableDeclSyntax.self)?.bindings.first?
                    .pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name)
        }
    }

    private func templateBindings(_ actual: DeclSyntax, _ template: DeclSyntax) -> [String: String]? {
        let actualTokens = Array(actual.tokens(viewMode: .sourceAccurate)).map(\.text)
        let expectedTokens = Array(template.tokens(viewMode: .sourceAccurate)).map(\.text)
        guard actualTokens.count == expectedTokens.count else { return nil }
        var bindings: [String: String] = [:]
        for (actual, expected) in zip(actualTokens, expectedTokens) {
            if expected.hasPrefix("__PROOF_") {
                if let previous = bindings[expected], previous != actual { return nil }
                bindings[expected] = actual
            } else if actual != expected {
                return nil
            }
        }
        return bindings
    }
}
