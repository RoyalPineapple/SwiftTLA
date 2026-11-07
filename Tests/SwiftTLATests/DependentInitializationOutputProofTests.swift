import Foundation
@testable import SwiftTLA
@testable import SwiftTLAPlugin
import SwiftParser
import SwiftSyntax
import SwiftTLAMacros
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
            StraightLineRenderedActionCheck.initialIntStatePredicate(named: "seed"),
            StraightLineRenderedActionCheck.initialIntStatePredicate(named: "choice"),
        ]
        let missingDependentClause = rendered.replacingOccurrences(
            of: "  /\\ choice \\in (IF (seed = 0) THEN {0} ELSE {0, 1})\n", with: "")
        #expect(missingDependentClause != rendered)
        do {
            try verifyRenderedInitialConjunction(missingDependentClause, predicates: predicates)
            Issue.record("A missing dependent initializer was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.Init")
            let remaining = predicates.filter { !$0.hasPrefix("choice \\in ") }
            #expect(diagnostic.actual == (["Init =="] + remaining.map { "  /\\ \($0)" }).joined(separator: "\n"))
        }

        let compilation = try DependentInitializationOutputProofModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let independentDomains = Dictionary(uniqueKeysWithValues: program.behavior.initializations.compactMap {
            initialization -> (String, String)? in
            let name = program.layout.variables[initialization.variable.ordinal].declaration.name
            guard let predicate = StraightLineRenderedActionCheck.initialIntPredicate(
                initialization.initialization, named: name, layout: program.layout) else { return nil }
            return (name, predicate)
        })
        #expect(independentDomains.count == 2)
        for initialization in compilation.semantics.behavior.initializations {
            guard case .memberOf = initialization.initialization else { continue }
            let name = compilation.layout.variables[initialization.variable.ordinal].declaration.name
            #expect(StraightLineRenderedActionCheck.initialIntPredicate(
                initialization.initialization, named: name, layout: compilation.layout) == independentDomains[name])
        }
        try verifyRenderedInitialConjunction(rendered, predicates: predicates,
            expectedControlLocations: ["pc": "finish"], expectedIntPredicates: independentDomains,
            expectedIntStateNames: ["seed", "choice"], expectedPredicateCount: 5,
            requireCompleteSimpleInitials: true)
        let extraConjunct = rendered.replacingOccurrences(of: "Init ==\n",
            with: "Init ==\n  /\\ FALSE\n")
        #expect(extraConjunct != rendered)
        do {
            try verifyRenderedInitialConjunction(extraConjunct, predicates: ["FALSE"] + predicates,
                expectedControlLocations: ["pc": "finish"], expectedIntPredicates: independentDomains,
                expectedIntStateNames: ["seed", "choice"], expectedPredicateCount: 5,
                requireCompleteSimpleInitials: true)
            Issue.record("Complete TLA Init corruption accepted: extraConjunct")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.Init")
        }
        let wrongRange = rendered.replacingOccurrences(of: "seed \\in 0..1", with: "seed \\in 0..2")
        #expect(wrongRange != rendered)
        do {
            try verifyRenderedInitialConjunction(wrongRange,
                predicates: predicates.map { $0.replacingOccurrences(of: "seed \\in 0..1", with: "seed \\in 0..2") },
                expectedControlLocations: ["pc": "finish"], expectedIntPredicates: independentDomains,
                expectedIntStateNames: ["seed", "choice"], expectedPredicateCount: 5,
                requireCompleteSimpleInitials: true)
            Issue.record("Complete TLA Init corruption accepted: rangeBounds")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.Init")
        }

        let fallible = #spec("DependentInitializationOutputProofModel") {
            let proof = Algorithm(label: "DependentInitializationOutputProofModel", scoped: { scope in
                let seed = scope.sharedVar(in: 0...1)
                let choice = scope.sharedVar(in: If(seed == 0,
                    then: SetExpr<Int>.literal(0),
                    else: SetExpr<Int>.literal(seed, seed + 9_223_372_036_854_775_807)))
                Do(DependentInitializationOutputProofModel.Step.finish) {
                    Assign(choice, to: choice)
                    Stop()
                }
            })
            proof
        }
        let fallibleProgram = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: fallible.compile()))
        let outcomes = try CompiledRuntime(program: fallibleProgram).initialOutcomes()
        try #require(outcomes.states.count == 1)
        let seedID = try #require(fallibleProgram.layout.variables.first { $0.declaration.name == "seed" }).id
        let choiceID = try #require(fallibleProgram.layout.variables.first { $0.declaration.name == "choice" }).id
        #expect(try outcomes.states[0].value(for: seedID) == .integer(0))
        #expect(try outcomes.states[0].value(for: choiceID) == .integer(0))
        #expect(outcomes.firstFailure == .integerOverflow(.addition, operands: [1, Int.max]))
        #expect(outcomes.firstFailureInitializerOrdinal == choiceID.ordinal)
        var fallibleEmitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "DependentInitializationOutputProofModel", program: fallibleProgram))
        let native = try #require(try fallibleEmitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
        })
        try #require(native.description.contains("SwiftTLA._NativeMachineOperations.add(_arithmetic0, _arithmetic1)"))
        try fallibleEmitter.verifyIntInitialOutput(native)
        let changedNativeOutputs = [
            ("additionOperand", native.description.replacingOccurrences(
                of: "SwiftTLA._NativeMachineOperations.add(_arithmetic0, _arithmetic1)",
                with: "SwiftTLA._NativeMachineOperations.add(_arithmetic0, 0)")),
            ("initializerSite", native.description.replacingOccurrences(
                of: "evaluatingInitializerOrdinal = \(choiceID.ordinal)",
                with: "evaluatingInitializerOrdinal = \(seedID.ordinal)")),
            ("earlyReturn", native.description.replacingOccurrences(
                of: "var result: [Snapshot] = []",
                with: "var result: [Snapshot] = []\nreturn InitialEvaluationOutcomes(states: result, failures: [])")),
        ]
        for (label, changed) in changedNativeOutputs {
            try #require(changed != native.description)
            let declaration = try #require(Parser.parse(source: changed).statements.first?.item.as(DeclSyntax.self))
            do {
                try fallibleEmitter.verifyIntInitialOutput(declaration)
                Issue.record("Fallible domain native corruption accepted: \(label)")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "native._initialStates.completeIntOutput")
            }
        }
        let fallibleTLA = try fallibleProgram.renderModule().renderedModuleSource
        if !fallibleTLA.contains("__SwiftTLAInitialOverflowFailure\(choiceID.ordinal)(") {
            Issue.record("Fallible memberOf domain lost its TLA initial failure relation")
        } else {
            try #require(fallibleTLA.split(separator: "\n").contains {
                $0.hasPrefix("  /\\ (IF ") && $0.contains("THEN choice \\in ")
            })
            #expect(!fallibleTLA.contains("__SwiftTLASelectedInitialFailureRecord"))
            let index = try #require(fallibleProgram.behavior.initializations.firstIndex {
                $0.variable == choiceID
            })
            let prefix = fallibleProgram.behavior.initializations[..<index]
            guard case .memberOf(let domain) = fallibleProgram.behavior.initializations[index].initialization else {
                Issue.record("The actual fallible domain changed its initializer kind")
                return
            }
            let declaration = try #require(fallibleTLA.split(separator: "\n").first {
                $0.hasPrefix("__SwiftTLAInitialOverflowFailure\(choiceID.ordinal)(")
            }).description
            let separator = try #require(declaration.range(of: " == "))
            let header = String(declaration[..<separator.lowerBound])
            let relation = String(declaration[separator.upperBound...])
            let open = try #require(header.firstIndex(of: "("))
            let close = try #require(header.lastIndex(of: ")"))
            let operandsName = String(header[header.index(after: open)..<close])
            let binderPattern = try NSRegularExpression(
                pattern: #"(?:LET|\\E) (__SwiftTLAInitialValue[0-9]+_*) (?:==|\\in)"#)
            let boundNames = binderPattern.matches(in: relation,
                range: NSRange(relation.startIndex..<relation.endIndex, in: relation)).compactMap {
                match -> String? in
                Range(match.range(at: 1), in: relation).map { String(relation[$0]) }
            }
            try #require(boundNames.count == prefix.count)
            let names = Dictionary(uniqueKeysWithValues: zip(prefix.map(\.variable), boundNames))
            let renderer = CompiledTLARenderer(moduleName: fallibleProgram.moduleName,
                reservedNames: [], layout: fallibleProgram.layout,
                bindings: .init(binders: fallibleProgram.binderNames), operators: .init(),
                actions: fallibleProgram.behavior.actions, functions: fallibleProgram.functions,
                enums: fallibleProgram.enums, parameterDomains: fallibleProgram.behavior.parameterDomains)
            let failure = try #require(try renderer.expressionEvaluationFailures(domain, stateNames: names).first)
            let operands = try #require(failure.operands)
            let operation = try #require(fallibleTLA.split(separator: "\n").first {
                $0.hasPrefix("__SwiftTLAInitialOverflowOperation\(choiceID.ordinal) == ")
            }).description
            let aggregateName = "__SwiftTLAAnyInitialEvaluationFailure"
            let aggregate = try #require(fallibleTLA.split(separator: "\n").first {
                $0.hasPrefix("\(aggregateName) == ")
            })
            let selected = String(aggregate.dropFirst("\(aggregateName) == ".count))
            try #require(selected.hasPrefix("(") && selected.hasSuffix(")"))
            let selection = String(selected.dropFirst().dropLast())
            try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(domain,
                after: prefix, names: names,
                emitted: [(failure, relation, operandsName, selection, operation, nil)],
                siteOrdinal: nil, layout: fallibleProgram.layout)
            for label in ["payload", "prefix", "missingRelation"] {
                var changedModule = fallibleTLA
                var emitted: [(failure: RenderedEvaluationFailure, relation: String,
                    operandsName: String?, selection: String, operationDeclaration: String?, record: String?)]
                    = [(failure, relation, operandsName, selection, operation, nil)]
                switch label {
                case "payload":
                    emitted[0].relation = relation.replacingOccurrences(of: "\(operandsName) = \(operands)",
                        with: "\(operandsName) = <<0, 0>>")
                    try #require(emitted[0].relation != relation)
                    changedModule = changedModule.replacingOccurrences(of: declaration,
                        with: "\(header) == \(emitted[0].relation)")
                case "prefix":
                    emitted[0].relation = relation.replacingOccurrences(of: " \\in 0..1:", with: " \\in 0..0:")
                    emitted[0].selection = selection.replacingOccurrences(of: " \\in 0..1:", with: " \\in 0..0:")
                    try #require(emitted[0].relation != relation && emitted[0].selection != selection)
                    changedModule = changedModule.replacingOccurrences(of: declaration,
                        with: "\(header) == \(emitted[0].relation)")
                        .replacingOccurrences(of: String(aggregate),
                            with: "\(aggregateName) == (\(emitted[0].selection))")
                default:
                    changedModule = changedModule.replacingOccurrences(of: declaration + "\n", with: "")
                    emitted.removeAll()
                }
                try #require(changedModule != fallibleTLA)
                try #require(changedModule.split(separator: "\n").filter {
                    $0.hasPrefix("__SwiftTLAInitialOverflowFailure\(choiceID.ordinal)(")
                }.count == emitted.count)
                if let output = emitted.first {
                    try #require(changedModule.contains("\(header) == \(output.relation)"))
                    try #require(changedModule.contains("\(aggregateName) == (\(output.selection))"))
                }
                do {
                    try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(domain,
                        after: prefix, names: names, emitted: emitted,
                        siteOrdinal: nil, layout: fallibleProgram.layout)
                    Issue.record("Fallible domain TLA corruption accepted: \(label)")
                } catch let diagnostic as CompilationDiagnostic {
                    #expect(diagnostic.path == "tla.initialEvaluationFailures")
                }
            }
            let independent = try #require(StraightLineRenderedActionCheck.initialIntPredicate(
                .memberOf(domain), named: "choice", layout: fallibleProgram.layout))
            let initStart = try #require(fallibleTLA.range(of: "Init ==\n"))
            let tail = fallibleTLA[initStart.upperBound...]
            let initEnd = try #require(tail.range(of: "\n\n"))
            let clauses = tail[..<initEnd.lowerBound].split(separator: "\n")
            try #require(clauses.allSatisfy { $0.hasPrefix("  /\\ ") })
            let predicates = clauses.map { String($0.dropFirst("  /\\ ".count)) }
            try verifyRenderedInitialConjunction(fallibleTLA, predicates: predicates,
                expectedIntPredicates: ["choice": independent])
            let unguarded = "choice \\in \(try renderer.state(domain))"
            for (label, replacement) in [
                ("definedness", unguarded),
                ("branchValue", independent.replacingOccurrences(of: "THEN {0} ELSE", with: "THEN {1} ELSE")),
            ] {
                try #require(replacement != independent)
                let changedModule = fallibleTLA.replacingOccurrences(of: independent, with: replacement)
                try #require(changedModule != fallibleTLA)
                do {
                    try verifyRenderedInitialConjunction(changedModule,
                        predicates: predicates.map { $0 == independent ? replacement : $0 },
                        expectedIntPredicates: ["choice": independent])
                    Issue.record("Fallible domain TLA Init corruption accepted: \(label)")
                } catch let diagnostic as CompilationDiagnostic {
                    #expect(diagnostic.path == "tla.Init")
                }
            }
        }

        let plainSet = #spec("DependentInitializationOutputProofModel") {
            let proof = Algorithm(label: "DependentInitializationOutputProofModel", scoped: { scope in
                let seed = scope.sharedVar(in: 0...1)
                let choice = scope.sharedVar(in: SetExpr<Int>.literal(seed, seed + 9_223_372_036_854_775_807))
                Do(DependentInitializationOutputProofModel.Step.finish) {
                    Assign(choice, to: choice)
                    Stop()
                }
            })
            proof
        }
        let afterRange = #spec("DependentInitializationOutputProofModel") {
            let proof = Algorithm(label: "DependentInitializationOutputProofModel", scoped: { scope in
                let seed = scope.sharedVar(in: 0...1)
                let choice = scope.sharedVar(initial: seed + 9_223_372_036_854_775_807)
                Do(DependentInitializationOutputProofModel.Step.finish) {
                    Assign(choice, to: choice)
                    Stop()
                }
            })
            proof
        }
        for (label, specification, expectedChoices) in [
            ("plainSet", plainSet, [0, Int.max]),
            ("afterRange", afterRange, [Int.max]),
        ] {
            let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
            let seed = try #require(program.layout.variables.first { $0.declaration.name == "seed" }).id
            let choice = try #require(program.layout.variables.first { $0.declaration.name == "choice" }).id
            let outcomes = try CompiledRuntime(program: program).initialOutcomes()
            try #require(outcomes.states.count == expectedChoices.count)
            #expect(try outcomes.states.map { try $0.value(for: seed) }
                == expectedChoices.map { _ in CompiledValue.integer(0) })
            #expect(Set(try outcomes.states.map { try $0.value(for: choice) })
                == Set(expectedChoices.map(CompiledValue.integer)))
            #expect(outcomes.firstFailure == .integerOverflow(.addition, operands: [1, Int.max]))
            #expect(outcomes.firstFailureInitializerOrdinal == choice.ordinal)
            var emitter = NativeSwiftEmitter(model: try MacroCompilation(
                typeName: "DependentInitializationOutputProofModel", program: program))
            _ = try emitter.machineMembers()
            let tla = try program.renderModule().renderedModuleSource
            if !tla.contains("__SwiftTLAInitialOverflowFailure\(choice.ordinal)(") {
                Issue.record("Fallible Int initialization lost its TLA failure relation: \(label)")
            }
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
        let emittedMembers = try emitter.machineMembers()
        let initialIndex = try #require(emittedMembers.firstIndex {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
        })
        let initialDeclarations = Array(emittedMembers[initialIndex...])
        let initialStates = try #require(initialDeclarations.first)
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
        ((\(name) == 0) ? Set<\(nativeIntType)>([0]) : Set<\(nativeIntType)>([0, 1])).sorted(by: { (lhs: \(nativeIntType), rhs: \(nativeIntType)) -> \(nativeBoolType) in
        return lhs < rhs
        })
        """
        func verify(_ declaration: DeclSyntax) throws {
            try verifyGeneratedInitialBindings(declaration, expected: expected,
                expectedLoops: expectedLoops,
                expectedCandidateSources: ["\(choiceName)Candidates": expectedChoiceSource],
                expectedControlLocations: Dictionary(uniqueKeysWithValues:
                    model.program.behavior.initializations.compactMap { initialization -> (String, Int)? in
                        guard case .value(let expression) = initialization.initialization,
                              case .controlLocation(let location) = expression.operation else { return nil }
                        return (emitter.variable(initialization.variable), location.ordinal)
                    }))
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
            of: "Set<\(nativeIntType)>([0, 1])).sorted", with: "Set<\(nativeIntType)>([0])).sorted")
        #expect(wrongCandidateSource != initialStates.description)
        let wrongCandidate = try #require(Parser.parse(source: wrongCandidateSource).statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verify(wrongCandidate)
        }

        let lines = initialStates.description.split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        var expectedMembershipSources: [String: String] = [:]
        for initialization in model.program.behavior.initializations {
            guard case .memberOf = initialization.initialization else { continue }
            let variableName = emitter.variable(initialization.variable)
            let prefix = "let \(variableName)_isMember = "
            let line = try #require(lines.first { $0.hasPrefix(prefix) })
            expectedMembershipSources[variableName] = String(line.dropFirst(prefix.count))
        }
        func verifySelection(_ declaration: DeclSyntax) throws {
            try emitter.verifyInitialSelection(declaration,
                expectedMembershipSources: expectedMembershipSources)
        }
        try verifySelection(initialStates)
        let wrongSelectionSource = initialStates.description.replacingOccurrences(
            of: "return \(choiceName)_isMember",
            with: "return !\(choiceName)_isMember")
        #expect(wrongSelectionSource != initialStates.description)
        let wrongSelection = try #require(Parser.parse(source: wrongSelectionSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifySelection(wrongSelection)
            Issue.record("An initializer that reverses the selected membership filter was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native._initialStates.selection.\(choiceName)")
        }

        let wrongOperationSource = initialStates.description.replacingOccurrences(
            of: "_NativeMachineOperations.initialCandidates(",
            with: "_NativeMachineOperations.uncheckedCandidates(")
        #expect(wrongOperationSource != initialStates.description)
        let wrongOperation = try #require(Parser.parse(source: wrongOperationSource)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifySelection(wrongOperation)
        }

        let wrongMembershipSource = initialStates.description.replacingOccurrences(
            of: "let \(choiceName)_isMember = ",
            with: "let \(choiceName)_isMember = !")
        #expect(wrongMembershipSource != initialStates.description)
        let wrongMembership = try #require(Parser.parse(source: wrongMembershipSource)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifySelection(wrongMembership)
        }

        let wrongStateSource = initialStates.description.replacingOccurrences(
            of: "choice: \(choiceName)", with: "choice: \(name)")
        #expect(wrongStateSource != initialStates.description)
        let wrongState = try #require(Parser.parse(source: wrongStateSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try emitter.verifyInitialStateAssembly(wrongState)
            Issue.record("An initializer that appends the wrong complete state was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native._initialStates.assembly")
        }

        func verifyComplete(_ declaration: DeclSyntax) throws {
            try verify(declaration)
            try verifySelection(declaration)
            try emitter.verifyInitialStateAssembly(declaration)
            try emitter.verifyIntInitialOutput(declaration)
            try verifyRandomSubsetInitialSupport(declaration, expected: [])
            try verifyGeneratedInitialConstruction(
                [declaration] + Array(initialDeclarations.dropFirst()), configured: false)
        }
        try verifyComplete(initialStates)
        let callback = "try SwiftTLA._NativeMachineOperations.visitInitialBranch({"
        let callbackRange = try #require(initialStates.description.range(of: callback))
        var earlyReturn = initialStates.description
        earlyReturn.replaceSubrange(callbackRange, with: callback + "\nreturn\n")
        let prunedSibling = initialStates.description.replacingOccurrences(
            of: "for \(choiceName) in \(choiceName)Candidates {",
            with: "for \(choiceName) in \(choiceName)Candidates {\nif \(choiceName) == 1 { continue }\n")
        let wrongRangeBounds = initialStates.description.replacingOccurrences(
            of: "let bounds = (0, 1)", with: "let bounds = (0, 2)")
        for (label, source) in [("earlyReturn", earlyReturn), ("prunedSibling", prunedSibling),
                                ("rangeBounds", wrongRangeBounds)] {
            #expect(source != initialStates.description)
            let mutated = try #require(Parser.parse(source: source).statements.first?.item.as(DeclSyntax.self))
            do {
                try verifyComplete(mutated)
                Issue.record("Complete Swift initialization corruption accepted: \(label)")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "native._initialStates.completeIntOutput")
            }
        }

        let namedSource = try String(contentsOf: fixture, encoding: .utf8)
            .replacingOccurrences(of: "enum Step: String, CaseIterable { case finish }",
                with: "enum Seed: Int, CaseIterable { case zero = 0, one = 1 }\n    enum Step: String, CaseIterable { case finish }")
            .replacingOccurrences(of: "let seed = scope.sharedVar(in: 0...1)",
                with: "let seed = scope.sharedVar(in: SetExpr<Seed>.literal(.zero, .one))")
            .replacingOccurrences(of: "If(seed == 0,", with: "If(seed == Seed.zero,")
        let namedDeclaration = try #require(Parser.parse(source: namedSource).statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "DependentInitializationOutputProofModel" })
        let named = try TLASpecVerifier.parseAndVerify(namedDeclaration)
        let namedSeed = try #require(named.program.layout.variables.first {
            $0.declaration.name == "seed"
        })
        #expect(named.program.variableTypes[namedSeed.id] == .named("Seed"))
        _ = try named.program.renderModule()
        var namedEmitter = NativeSwiftEmitter(model: named)
        _ = try namedEmitter.machineMembers()

        let mathematicalSource = try String(contentsOf: fixture, encoding: .utf8)
            .replacingOccurrences(of: "let seed = scope.sharedVar(in: 0...1)",
                with: "let seed = scope.sharedVar(in: Int.all)")
        let mathematicalDeclaration = try #require(Parser.parse(source: mathematicalSource)
            .statements.compactMap { $0.item.as(StructDeclSyntax.self) }
            .first { $0.name.text == "DependentInitializationOutputProofModel" })
        let mathematical = try TLASpecVerifier.parseAndVerify(mathematicalDeclaration)
        let mathematicalSeed = try #require(mathematical.program.layout.variables.first {
            $0.declaration.name == "seed"
        })
        let mathematicalInitialization = try #require(mathematical.program.behavior.initializations.first {
            $0.variable == mathematicalSeed.id
        }?.initialization)
        guard case .memberOf(let mathematicalDomain) = mathematicalInitialization else {
            Issue.record("The mathematical Int initializer must retain its membership domain")
            return
        }
        #expect(mathematicalDomain.operation == .integerSet)
        #expect(mathematicalDomain.children.isEmpty)
        #expect(mathematicalDomain.resultType == .set(.int))
        _ = try mathematical.program.renderModule()
        var mathematicalEmitter = NativeSwiftEmitter(model: mathematical)
        let mathematicalInitial = try #require(try mathematicalEmitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
        })
        try mathematicalEmitter.verifyIntInitialOutput(mathematicalInitial)
        let emitted = mathematicalInitial.description
        let enumeration = "(try SwiftTLA._NativeMachineOperations.integerSet())"
        let membership = "return { _ in true }"
        try #require(emitted.components(separatedBy: enumeration).count == 2)
        try #require(emitted.components(separatedBy: membership).count == 2)
        for (label, changed) in [
            ("enumeration", emitted.replacingOccurrences(of: enumeration, with: "Set<\(nativeIntType)>()")),
            ("membership", emitted.replacingOccurrences(of: membership, with: "return { _ in false }")),
            ("earlyReturn", emitted.replacingOccurrences(of: "var result: [Snapshot] = []",
                with: "var result: [Snapshot] = []\nif _selectedInitial == nil { return InitialEvaluationOutcomes(states: result, failures: []) }")),
        ] {
            try #require(changed != emitted)
            let corrupted = try #require(Parser.parse(source: changed).statements.first?.item.as(DeclSyntax.self))
            do {
                try mathematicalEmitter.verifyIntInitialOutput(corrupted)
                Issue.record("Complete Swift integerSet corruption accepted: \(label)")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "native._initialStates.completeIntOutput")
            }
        }

        let specification = try #require(try TLASpecVerifier.findSpec(in: declaration.memberBlock.members))
        try #require(declaration.description.components(separatedBy: specification.closure.description).count == 2)
        let assumptionOnlySource = declaration.description.replacingOccurrences(
            of: specification.closure.description, with: "{ Assume(true) }")
        let assumptionOnlyDeclaration = try #require(Parser.parse(source: assumptionOnlySource)
            .statements.first?.item.as(StructDeclSyntax.self))
        let assumptionOnly = try TLASpecVerifier.parseAndVerify(assumptionOnlyDeclaration)
        #expect(assumptionOnly.program.layout.variables.isEmpty)
        #expect(assumptionOnly.program.behavior.initializations.isEmpty)
        let emptyStateOutcomes = try CompiledRuntime(program: assumptionOnly.program).initialOutcomes()
        #expect(emptyStateOutcomes.states.count == 1)
        #expect(emptyStateOutcomes.failures.isEmpty)
        var assumptionOnlyEmitter = NativeSwiftEmitter(model: assumptionOnly)
        let emptyStateInitial = try #require(try assumptionOnlyEmitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
        })
        try assumptionOnlyEmitter.verifyIntInitialOutput(emptyStateInitial)
        let appendEmptyState = "result.append(Snapshot(state: State()))"
        try #require(emptyStateInitial.description.components(separatedBy: appendEmptyState).count == 2)
        let droppedEmptyState = emptyStateInitial.description.replacingOccurrences(of: appendEmptyState, with: "")
        try #require(droppedEmptyState != emptyStateInitial.description)
        let corruptedEmptyState = try #require(Parser.parse(source: droppedEmptyState)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try assumptionOnlyEmitter.verifyIntInitialOutput(corruptedEmptyState)
            Issue.record("A generated initializer that loses the only empty state was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native._initialStates.completeIntOutput")
        }
    }
}
