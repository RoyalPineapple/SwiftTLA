import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin
import UpstreamParity

private enum InvalidInitialFailureShape: Error { case unexpected }

@Suite("Initial branch failures")
struct InitialBranchFailureTests {
    @Test("A failed dependent expression does not discard its valid initial sibling")
    func preservesValidInitialSibling() throws {
        let generated = try DependentDivisionInitialModel.initialOutcomes()
        #expect(generated.states.map(\.state) == [.init(divisor: 1, quotient: 1)])
        #expect(generated.firstFailure == .divisionByZero)

        let compilation = try DependentDivisionInitialModel.spec.compile()
        let compiled = try CompiledRuntime(compilation: compilation).initialOutcomes()
        #expect(compiled.states.count == 1)
        #expect(compiled.firstFailure == generated.firstFailure)
        let quotient = try #require(compilation.layout.testVariableID(named: "quotient"))
        #expect(try compiled.states[0].value(for: quotient) == .integer(1))
    }

    @Test("Rendered dependent division retains its initial failure outcome")
    func renderedDependentDivisionFailure() throws {
        let tla = try DependentDivisionInitialModel.render().tlaBundle.tla
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/DependentDivisionInitialModel.tla")
            .standardizedFileURL
        let checkedModule = try String(contentsOf: fixture, encoding: .utf8)
        #expect(tla == checkedModule)
    }

    @Test("Rendered selected initial invariant retains its failed branch")
    func renderedSelectedInvariantFailure() throws {
        let tla = try SelectedInitialInvariantFailureModel.render().tlaBundle.tla
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/SelectedInitialInvariantFailureModel.tla")
            .standardizedFileURL
        let checkedModule = try String(contentsOf: fixture, encoding: .utf8)
        #expect(tla == checkedModule)
    }

    @Test("A selected invariant failure retains its valid initial sibling")
    func preservesValidSiblingWhenSelectedInvariantFails() throws {
        let generated = try SelectedInitialInvariantFailureModel.initialOutcomes()
        #expect(generated.states.map(\.state) == [.init(divisor: 1, quotient: 1)])
        #expect(generated.firstFailure == .divisionByZero)

        let compilation = try SelectedInitialInvariantFailureModel.spec.compile()
        let compiled = try CompiledRuntime(compilation: compilation).initialOutcomes()
        #expect(compiled.states.count == 1)
        #expect(compiled.firstFailure == generated.firstFailure)
        let divisor = try #require(compilation.layout.testVariableID(named: "divisor"))
        #expect(try compiled.states[0].value(for: divisor) == .integer(1))
    }

    @Test("An earlier branch's invariant failure precedes a later initializer failure")
    func preservesFirstFailureOrderAcrossBranches() throws {
        let generated = try InitialFailureOrderModel.initialOutcomes()
        #expect(generated.states.isEmpty)
        #expect(generated.firstFailure == .negativeModuloDivisor(-1))

        let compiled = try CompiledRuntime(compilation: InitialFailureOrderModel.spec.compile()).initialOutcomes()
        #expect(compiled.states.isEmpty)
        #expect(compiled.firstFailure == generated.firstFailure)
    }

    @Test("An out-of-domain function read retains the valid initial branch")
    func preservesValidFunctionReadSibling() throws {
        let generated = try DependentFunctionReadInitialModel.initialOutcomes()
        #expect(generated.states.count == 1)
        #expect(generated.states[0].state.key == 0)
        #expect(generated.states[0].state.result == 42)
        #expect(generated.firstFailure == .functionArgumentOutsideDomain)

        let compilation = try DependentFunctionReadInitialModel.spec.compile()
        let compiled = try CompiledRuntime(compilation: compilation).initialOutcomes()
        #expect(compiled.states.count == 1)
        #expect(compiled.firstFailure == generated.firstFailure)
        let key = try #require(compilation.layout.testVariableID(named: "key"))
        let result = try #require(compilation.layout.testVariableID(named: "result"))
        #expect(try compiled.states[0].value(for: key) == .integer(0))
        #expect(try compiled.states[0].value(for: result) == .integer(42))
    }

    @Test("A later initial overflow remains visible after an earlier checked addition")
    func preservesFailureAfterFallibleInitialPrefix() throws {
        let generated = try CheckedAdditionPrefixInitialModel.initialOutcomes()
        #expect(generated.states.isEmpty)
        #expect(generated.firstFailure == .integerOverflow(.addition,
            operands: [3, Int.max]))

        let rendered = try CheckedAdditionPrefixInitialModel.render().tlaBundle.root.tla
        let selectedRecordName = "__SwiftTLASelectedInitialFailureRecord"
        let selectedRecord = try #require(rendered.split(separator: "\n").first {
            $0.hasPrefix("\(selectedRecordName) == ")
        })
        #expect(selectedRecord.contains("site |-> 3"))
        #expect(selectedRecord.contains("kind |-> \"integerOverflow.addition\""))
        #expect(selectedRecord.contains("operands |-> <<"))
        let aggregateName = "__SwiftTLAAnyInitialEvaluationFailure"
        let aggregate = try #require(rendered.split(separator: "\n").first {
            $0.hasPrefix("\(aggregateName) == ")
        })
        let predicates = String(aggregate.dropFirst("\(aggregateName) == ".count))
            .components(separatedBy: " \\/ ").map { String($0.dropFirst().dropLast()) }
        guard predicates.count == 2 else { throw InvalidInitialFailureShape.unexpected }
        #expect(!rendered.contains("ASSUME ~\(aggregateName)"))
        try StraightLineRenderedActionCheck.verifyInitialFailureAggregate(rendered,
            predicates: predicates, name: aggregateName)
        let wrongRecord = rendered.replacingOccurrences(of: "site |-> 3",
            with: "site |-> 2")
        #expect(wrongRecord != rendered)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verifyInitialFailureRecord(wrongRecord,
                declaration: String(selectedRecord))
        }
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verifyInitialFailureRecord(rendered,
                name: nil, predicates: predicates,
                records: Array(repeating: String(selectedRecord), count: predicates.count),
                required: true)
        }
        let missingFailure = rendered.replacingOccurrences(of: String(aggregate),
            with: "\(aggregateName) == \(predicates[0])")
        do {
            try StraightLineRenderedActionCheck.verifyInitialFailureAggregate(missingFailure,
                predicates: predicates, name: aggregateName)
            Issue.record("A missing initial failure escaped the emitted-output check")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.initialEvaluationAggregate")
        }
        let failures = rendered.split(separator: "\n").filter {
            $0.hasPrefix("__SwiftTLAInitialOverflowFailure3(")
        }
        let failure = try #require(failures.count == 1 ? failures[0] : nil)
        #expect(failure.contains("THEN (LET __SwiftTLAInitialValue2 =="))
        #expect(rendered.contains("__SwiftTLAInitialOverflowOperation3 == \"addition\""))

        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(
            in: CheckedAdditionPrefixInitialModel.spec.compile()))
        let last = try #require(program.layout.variables.first { $0.declaration.name == "last" })
        #expect(generated.firstFailureInitializerOrdinal == last.id.ordinal)
        let compiledOutcome = try CompiledRuntime(program: program).initialOutcomes()
        #expect(compiledOutcome.firstFailureInitializerOrdinal == last.id.ordinal)
        #expect(compiledOutcome.firstFailure == generated.firstFailure)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "CheckedAdditionPrefixInitialModel", program: program))
        let swiftOutput = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
        })
        try emitter.verifyDeterministicIntInitialOutput(swiftOutput)
        let siteAssignment = "evaluatingInitializerOrdinal = \(last.id.ordinal)"
        let wrongSwift = swiftOutput.description.replacingOccurrences(of: siteAssignment,
            with: "evaluatingInitializerOrdinal = \(last.id.ordinal - 1)")
        #expect(wrongSwift != swiftOutput.description)
        let wrongSwiftOutput = try #require(Parser.parse(source: wrongSwift)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try emitter.verifyDeterministicIntInitialOutput(wrongSwiftOutput)
            Issue.record("A wrong generated Swift failure site escaped the output check")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native._initialStates.completeIntOutput")
        }
        guard let index = program.behavior.initializations.firstIndex(where: {
            $0.variable == last.id
        }) else {
            throw InvalidInitialFailureShape.unexpected
        }
        guard case .value(let expression) = program.behavior.initializations[index].initialization else {
            throw InvalidInitialFailureShape.unexpected
        }
        let prefix = program.behavior.initializations[..<index]
        let binders = String(failure).components(separatedBy: "LET ").dropFirst().map {
            String($0.prefix(while: { $0 != " " }))
        }
        guard binders.count == prefix.count else { throw InvalidInitialFailureShape.unexpected }
        let names = Dictionary(uniqueKeysWithValues: zip(prefix.map(\.variable), binders))
        let renderer = CompiledTLARenderer(moduleName: program.moduleName,
            reservedNames: [], layout: program.layout,
            bindings: .init(binders: program.binderNames), operators: .init(),
            actions: program.behavior.actions, functions: program.functions,
            enums: program.enums, parameterDomains: program.behavior.parameterDomains)
        let checkedFailure = try #require(try renderer.expressionEvaluationFailures(
            expression, stateNames: names).first)
        guard let separator = failure.range(of: " == ") else {
            throw InvalidInitialFailureShape.unexpected
        }
        let header = String(failure[..<separator.lowerBound])
        let relation = String(failure[separator.upperBound...])
        let open = try #require(header.firstIndex(of: "("))
        let close = try #require(header.lastIndex(of: ")"))
        let operandsName = String(header[header.index(after: open)..<close])
        let operationDeclaration = try #require(rendered.split(separator: "\n").first {
            $0.hasPrefix("__SwiftTLAInitialOverflowOperation3 == ")
        }).description
        let operands = try #require(checkedFailure.operands)
        let relationOperands = "\(operandsName) = \(operands)"
        #expect(relation.contains(relationOperands))
        let record = relation.replacingOccurrences(of: relationOperands,
            with: "[site |-> 3, kind |-> \"integerOverflow.addition\", operands |-> \(operands)]")
        try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(expression,
            after: prefix, names: names,
            emitted: [(checkedFailure, relation, operandsName, predicates[1], operationDeclaration, record)],
            siteOrdinal: 3, layout: program.layout)

        let missingOperand = CompiledExpression(operation: .add, resultType: .int,
            children: Array(expression.children.prefix(1)))
        do {
            try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(missingOperand,
                after: prefix, names: names,
                emitted: [(checkedFailure, relation, operandsName, predicates[1], operationDeclaration, record)],
                siteOrdinal: 3, layout: program.layout)
            Issue.record("A malformed compiled addition escaped the emitted-output check")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.initialEvaluationFailures")
        }

        do {
            try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(expression,
                after: prefix, names: names,
                emitted: [(checkedFailure, relation, operandsName, predicates[1], operationDeclaration,
                    record.replacingOccurrences(of: "site |-> 3", with: "site |-> 2"))],
                siteOrdinal: 3, layout: program.layout)
            Issue.record("A changed initial failure site escaped the emitted-output check")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.initialEvaluationFailures")
        }

        #expect(predicates[1] != "FALSE")
        do {
            try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(expression,
                after: prefix, names: names,
                emitted: [(checkedFailure, relation, operandsName, "FALSE", operationDeclaration, record)],
                siteOrdinal: 3,
                layout: program.layout)
            Issue.record("A changed initial failure selection escaped the emitted-output check")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.initialEvaluationFailures")
        }
        do {
            try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(expression,
                after: prefix, names: names,
                emitted: [(checkedFailure, relation, operandsName, predicates[1],
                    operationDeclaration.replacingOccurrences(of: "\"addition\"", with: "\"subtraction\""), record)],
                siteOrdinal: 3,
                layout: program.layout)
            Issue.record("A changed initial overflow kind escaped the emitted-output check")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.initialEvaluationFailures")
        }

        let secondVariable = try #require(program.layout.variables.first {
            $0.declaration.name == "second"
        })
        let second = try #require(program.behavior.initializations.first {
            $0.variable == secondVariable.id
        })
        guard case .value(let secondExpression) = second.initialization else {
            throw InvalidInitialFailureShape.unexpected
        }
        let defined = try #require(try renderer.evaluationDefined(secondExpression,
            stateNames: names))
        let wrong = relation.replacingOccurrences(
            of: "(IF \(defined) THEN (LET __SwiftTLAInitialValue2 ==",
            with: "(IF TRUE THEN (LET __SwiftTLAInitialValue2 ==")
        #expect(wrong != relation)
        do {
            try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(expression,
                after: prefix, names: names,
                emitted: [(checkedFailure, wrong, operandsName, predicates[1], operationDeclaration, record)],
                siteOrdinal: 3,
                layout: program.layout)
            Issue.record("A later initial failure escaped its checked prefix")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.initialEvaluationFailures")
        }
    }

    @Test("Generated validation reports an initial overflow when no state exists")
    func checksFailureOnlyInitialOutcome() throws {
        let scenario = try #require(CheckedAdditionPrefixInitialModel.validationScenarios().first)
        var emitted = false
        let result = try scenario.runValidation(maximumStates: 4, checking: scenario.checking,
            stopOnViolation: false, stopOnReachability: false) { _ in emitted = true }
        #expect(!emitted)
        #expect(result.initialStates == 0 && result.states == 0 && result.edges == 0)
        #expect(result.firstEvaluationFailure == .integerOverflow(.addition, operands: [3, Int.max]))
        #expect(result.completion == .evaluationFailure(.integerOverflow(.addition,
            operands: [3, Int.max])))
    }

    @Test("Initial failure has a separate checkable TLA+ output")
    func selectsInitialFailureWithoutChangingTheProofModule() throws {
        let compiled = try CheckedAdditionPrefixInitialModel.spec.compile().render()
        let generated = try CheckedAdditionPrefixInitialModel.render()
        let check = try #require(try generated.initialEvaluationFailureBundle())
        let compiledCheck = try #require(try compiled.initialEvaluationFailureBundle())
        let recordedCheck = try #require(try generated.initialEvaluationFailureBundle(capturingRecord: true))
        #expect(recordedCheck.tla.contains("PrintT(__SwiftTLASelectedInitialFailureRecord)"))
        #expect(recordedCheck.tla.contains(
            #"\#(recordedCheck.root.name)__ProbeInit == FALSE /\ Init"#))
        #expect(check.root == compiledCheck.root)
        #expect(check.imports == compiledCheck.imports)
        #expect(!generated.tlaBundle.tla.contains("ASSUME ~__SwiftTLAAnyInitialEvaluationFailure"))
        #expect(check.cfg.contains("INIT "))
        #expect(check.cfg.contains("NEXT "))
        #expect(check.cfg.contains("CHECK_DEADLOCK FALSE"))
        #expect(check.imports.map(\.name).contains(generated.tlaBundle.root.name))

        let aggregate = "__SwiftTLAAnyInitialEvaluationFailure"
        let wrong = TLAModuleBundle(root: .init(name: check.root.name,
            tla: check.tla.replacingOccurrences(of: "ASSUME ~\(aggregate)",
                with: "ASSUME \(aggregate)"), cfg: check.root.cfg),
            imports: check.imports, provenance: check.provenance)
        #expect(wrong.tla != check.tla)
        do {
            try StraightLineRenderedActionCheck.verifyInitialFailureCheckBundle(wrong,
                base: generated.tlaBundle, aggregate: aggregate, constants: [])
            Issue.record("The wrong initial failure polarity escaped the output check")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.initialEvaluationSelection")
        }
        let missingInit = TLAModuleBundle(root: .init(name: check.root.name,
            tla: check.tla, cfg: check.cfg.split(separator: "\n")
                .filter { !$0.hasPrefix("INIT ") }.joined(separator: "\n") + "\n"),
            imports: check.imports, provenance: check.provenance)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verifyInitialFailureCheckBundle(missingInit,
                base: generated.tlaBundle, aggregate: aggregate, constants: [])
        }
    }

    @Test("An invalid compiled value shape is not relabeled as a model failure")
    func rejectsUnmappedFailure() {
        #expect(throws: EvalError.expected(.integer, actual: [])) {
            try _NativeMachineOperations.visitInitialBranch {
                throw EvalError.expected(.integer, actual: [])
            } onEvaluationFailure: { _ in
                Issue.record("An internal value-shape error must not become an initial outcome")
            }
        }
    }
}
