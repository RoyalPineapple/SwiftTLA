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

        let closure = try parseSpecTestClosure("""
        { scope in
            let first = scope.sharedVar(in: 0...2)
            let second = scope.sharedVar(initial: first + 9223372036854775807)
        }
        """)
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in:
            SpecParser.parseSpecClosure(named: "InitialSibling", closure).compile()))
        let outcomes = try CompiledRuntime(program: program).initialOutcomes()
        try #require(outcomes.states.count == 1)
        let first = try #require(TLAStateProjection.Token(validating: "first"))
        let second = try #require(TLAStateProjection.Token(validating: "second"))
        let state = try outcomes.states[0].projection(using: program.layout)
        #expect(state.value(for: first) == .int(0))
        #expect(state.value(for: second) == .int(.max))
        try #require(outcomes.failures.count == 2)
        for (failure, value) in zip(outcomes.failures, [1, 2]) {
            #expect(failure.site == .initializer(1))
            #expect(failure.failure == .integerOverflow(.addition, operands: [value, Int.max]))
            #expect(try failure.formalBindingsBeforeFailure() == TLAStateProjection(validating: [
                .init(token: first, value: .int(value))
            ]))
        }
        let module = try program.renderModule().renderedModuleSource
        let eventDeclaration = try #require(module.split(separator: "\n").first {
            $0.hasPrefix("__SwiftTLAInitialFailureEvents == ")
        })
        #expect(!module.contains("__SwiftTLASelectedInitialFailureRecord"))
        let eventSet = String(eventDeclaration.dropFirst("__SwiftTLAInitialFailureEvents == UNION {".count).dropLast())
        let relationDeclaration = try #require(module.split(separator: "\n").first {
            $0.hasPrefix("__SwiftTLAInitialOverflowFailure1(")
        }).description
        let parts = relationDeclaration.components(separatedBy: " == ")
        try #require(parts.count == 2)
        let header = parts[0]
        let open = try #require(header.firstIndex(of: "("))
        let close = try #require(header.lastIndex(of: ")"))
        let operandsName = String(header[header.index(after: open)..<close])
        let binderPattern = try NSRegularExpression(pattern: #"\\E ([A-Za-z_][A-Za-z_0-9]*) \\in"#)
        let match = try #require(binderPattern.firstMatch(in: parts[1],
            range: NSRange(parts[1].startIndex..<parts[1].endIndex, in: parts[1])))
        let binderRange = try #require(Range(match.range(at: 1), in: parts[1]))
        let binder = String(parts[1][binderRange])
        let prefix = program.behavior.initializations.prefix(1)
        let names = [prefix[0].variable: binder]
        guard case .value(let expression) = program.behavior.initializations[1].initialization else {
            throw InvalidInitialFailureShape.unexpected
        }
        let renderer = CompiledTLARenderer(moduleName: program.moduleName,
            reservedNames: [], layout: program.layout,
            bindings: .init(binders: program.binderNames), operators: .init(),
            actions: program.behavior.actions, functions: program.functions,
            enums: program.enums, parameterDomains: program.behavior.parameterDomains)
        let failure = try #require(try renderer.expressionEvaluationFailures(expression, stateNames: names).first)
        let aggregate = try #require(module.split(separator: "\n").first {
            $0.hasPrefix("__SwiftTLAAnyInitialEvaluationFailure == ")
        })
        let selection = String(aggregate.dropFirst("__SwiftTLAAnyInitialEvaluationFailure == (".count).dropLast())
        let operation = try #require(module.split(separator: "\n").first {
            $0.hasPrefix("__SwiftTLAInitialOverflowOperation1 == ")
        }).description
        func verifyEvents(_ events: [String]) throws {
            try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(expression,
                after: prefix, names: names,
                emitted: [(failure, parts[1], operandsName, selection, operation, nil)],
                siteOrdinal: 1, eventSets: events, layout: program.layout)
        }
        try verifyEvents([eventSet])
        let before = "before |-> <<[name |-> \"first\", value |-> \(binder)]>>"
        let corruptions = [
            ("site", eventSet.replacingOccurrences(of: "site |-> 1", with: "site |-> 0")),
            ("prefix", eventSet.replacingOccurrences(of: before, with: "before |-> <<>>")),
            ("branch", eventSet.replacingOccurrences(of: " \\in 0..2}", with: " \\in 0..1}"))
        ]
        for (label, corrupted) in corruptions {
            try #require(corrupted != eventSet)
            do {
                try verifyEvents([corrupted])
                Issue.record("Initial failure event-set corruption accepted: \(label)")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "tla.initialEvaluationFailures")
            }
        }
        #expect(throws: CompilationDiagnostic.self) { try verifyEvents([]) }
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
        func prefix(_ entries: [(String, TLAValue)]) throws -> TLAStateProjection {
            try TLAStateProjection(validating: entries.map { name, value in
                .init(token: try #require(TLAStateProjection.Token(validating: name)), value: value)
            })
        }
        let beforeInvariant = try prefix([("pc", .string("stay")), ("divisor", .int(0)), ("quotient", .int(1))])
        let beforeInitializer = try prefix([("pc", .string("stay")), ("divisor", .int(1))])
        for failures in [generated.failures, compiled.failures] {
            #expect(failures.count == 2)
            guard failures.count == 2 else { continue }
            #expect(failures.map(\.failure) == [.negativeModuloDivisor(-1), .divisionByZero])
            #expect(failures.map(\.site) == [.selectedInvariant, .initializer(2)])
            #expect(try failures[0].formalBindingsBeforeFailure() == beforeInvariant)
            #expect(try failures[1].formalBindingsBeforeFailure() == beforeInitializer)
        }
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
        let sourceCompilation = try CheckedAdditionPrefixInitialModel.spec.compile()
        let sourceFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/UpstreamParity/ValidationModels/CheckedAdditionPrefixInitialModel.swift")
            .standardizedFileURL
        let syntax = Parser.parse(source: try String(contentsOf: sourceFile, encoding: .utf8))
        let declaration = try #require(syntax.statements.compactMap { $0.item.as(StructDeclSyntax.self) }.first)
        let parsedModel = try TLASpecVerifier.parseAndVerify(declaration)
        for layout in [sourceCompilation.layout, parsedModel.program.layout] {
            let intNames = Set(layout.variables.filter {
                $0.resolvedValueType.map { $0 == .int } ?? ($0.generatedSwiftType == "Int")
            }.map { $0.declaration.name })
            #expect(intNames == ["first", "second", "last"])
        }
        #expect(StraightLineRenderedActionCheck.requiredInitialIntFailureObservations(
            parsedModel.program.behavior, layout: parsedModel.program.layout).selected)
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
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(
            in: sourceCompilation))
        let requiresRecord = StraightLineRenderedActionCheck.requiredInitialIntFailureObservations(
            program.behavior, layout: program.layout).selected
        #expect(requiresRecord)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verifyInitialFailureRecord(rendered,
                name: nil, predicates: predicates,
                records: [], required: requiresRecord)
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
        try emitter.verifyIntInitialOutput(swiftOutput)
        let secondField = try #require(program.layout.variables.first { $0.declaration.name == "second" })
        let firstField = try #require(program.layout.variables.first { $0.declaration.name == "first" })
        let correctPrefix = "TLAValue.int(\(emitter.variable(secondField.id)))"
        #expect(swiftOutput.description.components(separatedBy: correctPrefix).count == 2)
        let wrongPrefix = swiftOutput.description.replacingOccurrences(of: correctPrefix,
            with: "TLAValue.int(\(emitter.variable(firstField.id)))")
        #expect(wrongPrefix != swiftOutput.description)
        let wrongPrefixOutput = try #require(Parser.parse(source: wrongPrefix)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try emitter.verifyIntInitialOutput(wrongPrefixOutput)
        }
        let siteAssignment = "evaluatingInitializerOrdinal = \(last.id.ordinal)"
        let wrongSwift = swiftOutput.description.replacingOccurrences(of: siteAssignment,
            with: "evaluatingInitializerOrdinal = \(last.id.ordinal - 1)")
        #expect(wrongSwift != swiftOutput.description)
        let wrongSwiftOutput = try #require(Parser.parse(source: wrongSwift)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try emitter.verifyIntInitialOutput(wrongSwiftOutput)
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
        let pc = try #require(program.layout.variables.first { $0.declaration.origin == .programCounter })
        let firstName = try #require(names[firstField.id])
        let pcName = try #require(names[pc.id])
        let secondName = try #require(names[secondField.id])
        let before = "<<[name |-> \"first\", value |-> \(firstName)], [name |-> \"pc\", value |-> \(pcName)], [name |-> \"second\", value |-> \(secondName)]>>"
        let record = relation.replacingOccurrences(of: relationOperands,
            with: "[site |-> 3, kind |-> \"integerOverflow.addition\", operands |-> \(operands), before |-> \(before)]")
        #expect(selectedRecord.contains("before |-> \(before)"))
        try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(expression,
            after: prefix, names: names,
            emitted: [(checkedFailure, relation, operandsName, predicates[1], operationDeclaration, record)],
            siteOrdinal: 3, eventSets: nil, layout: program.layout)

        let secondBinding = "[name |-> \"second\", value |-> \(secondName)]"
        #expect(record.components(separatedBy: secondBinding).count == 2)
        for changedPrefix in [
            "<<>>",
            before.replacingOccurrences(of: secondBinding,
                with: "[name |-> \"second\", value |-> \(firstName)]"),
        ] {
            let wrongPrefixRecord = record.replacingOccurrences(of: before, with: changedPrefix)
            #expect(wrongPrefixRecord != record)
            #expect(throws: CompilationDiagnostic.self) {
                try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(expression,
                    after: prefix, names: names,
                    emitted: [(checkedFailure, relation, operandsName, predicates[1], operationDeclaration, wrongPrefixRecord)],
                    siteOrdinal: 3, eventSets: nil, layout: program.layout)
            }
        }

        let missingOperand = CompiledExpression(operation: .add, resultType: .int,
            children: Array(expression.children.prefix(1)))
        do {
            try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(missingOperand,
                after: prefix, names: names,
                emitted: [(checkedFailure, relation, operandsName, predicates[1], operationDeclaration, record)],
                siteOrdinal: 3, eventSets: nil, layout: program.layout)
            Issue.record("A malformed compiled addition escaped the emitted-output check")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.initialEvaluationFailures")
        }

        do {
            try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(expression,
                after: prefix, names: names,
                emitted: [(checkedFailure, relation, operandsName, predicates[1], operationDeclaration,
                    record.replacingOccurrences(of: "site |-> 3", with: "site |-> 2"))],
                siteOrdinal: 3, eventSets: nil, layout: program.layout)
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
                eventSets: nil, layout: program.layout)
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
                eventSets: nil, layout: program.layout)
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
                eventSets: nil, layout: program.layout)
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
        #expect(result.fairnessEnabledness == nil)
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
        let wrongRecordCapture = TLAModuleBundle(root: .init(name: recordedCheck.root.name,
            tla: recordedCheck.tla.replacingOccurrences(
                of: "PrintT(__SwiftTLASelectedInitialFailureRecord)", with: "PrintT(FALSE)"),
            cfg: recordedCheck.root.cfg), imports: recordedCheck.imports,
            provenance: recordedCheck.provenance)
        #expect(wrongRecordCapture.tla != recordedCheck.tla)
        do {
            try StraightLineRenderedActionCheck.verifyInitialFailureCheckBundle(wrongRecordCapture,
                base: generated.tlaBundle, aggregate: aggregate, constants: [],
                record: "__SwiftTLASelectedInitialFailureRecord")
            Issue.record("The wrong initial failure record capture escaped the output check")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.initialEvaluationSelection")
        }
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

    @Test("Internal errors and collection capacity limits are not relabeled as model failures")
    func rejectsUnmappedFailure() {
        #expect(throws: EvalError.expected(.integer, actual: [])) {
            try _NativeMachineOperations.visitInitialBranch {
                throw EvalError.expected(.integer, actual: [])
            } onEvaluationFailure: { _ in
                Issue.record("An internal value-shape error must not become an initial outcome")
            }
        }
        let count = Int.bitWidth - 1
        let domain = StateExpr.setLiteral((0..<count).map { .int($0) })
        let cases: [(native: NativeMachineEvaluationError, compiled: EvalError,
                     expression: StateExpr, operation: () throws -> Void)] = [
            (.powerSetTooLarge(actualCount: count, maximumCount: Int.bitWidth - 2),
             .powerSetTooLarge(actualCount: count, maximumCount: Int.bitWidth - 2),
             .powerSet(domain), { _ = try _NativeMachineOperations.powerSet(Set(0..<count)) }),
            (.collectionCardinalityOverflow(.integerRange, operands: [0, Int.max]),
             .collectionCardinalityOverflow(.integerRange, operands: [0, Int.max]),
             .integerRange(.int(0), .int(Int.max)),
             { _ = try _NativeMachineOperations.integerRange(0, Int.max) }),
            (.collectionCardinalityOverflow(.functionSet, operands: [count, 2]),
             .collectionCardinalityOverflow(.functionSet, operands: [count, 2]),
             .functionSet(domain, .setLiteral([.int(0), .int(1)])),
             { _ = try _NativeMachineOperations.functionSet(Set(0..<count), Set([0, 1])) })
        ]
        for entry in cases {
            #expect(throws: entry.native) {
                try _NativeMachineOperations.visitInitialBranch(entry.operation) { _ in
                    Issue.record("A native collection capacity limit became a completed model failure")
                }
            }
            #expect(throws: entry.compiled) {
                try _NativeMachineOperations.visitInitialBranch {
                    _ = try compiledValue(entry.expression)
                } onEvaluationFailure: { _ in
                    Issue.record("A compiled collection capacity limit became a completed model failure")
                }
            }
        }
    }
}
