import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct TypedActionParameterTests {
    @Test("Finite bound action calls form the complete generated TLA transition relation")
    func finiteBoundCallsRejectMissingOrChangedInvocation() throws {
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(
            in: BoundOrderedAssignment.spec.compile()))
        let module = try program.renderModule().renderedModuleSource
        try StraightLineRenderedActionCheck.verifyFiniteInvocations(program.behavior,
            layout: program.layout, binders: program.binderNames, module: module)

        let wrongDomain = module.replacingOccurrences(of: "member \\in {1, 2}",
            with: "member \\in {1}")
        #expect(wrongDomain != module)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verifyFiniteInvocations(program.behavior,
                layout: program.layout, binders: program.binderNames, module: wrongDomain)
        }

        let wrongNext = module.replacingOccurrences(
            of: "Next == (\\E member \\in {1, 2}: select(member))",
            with: "Next == FALSE")
        #expect(wrongNext != module)
        do {
            try StraightLineRenderedActionCheck.verifyFiniteInvocations(program.behavior,
                layout: program.layout, binders: program.binderNames, module: wrongNext)
            Issue.record("The completed TLA transition relation omitted a compiled action invocation")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.Next.finiteInvocations")
        }
    }

    @Test("A bound ordered assignment keeps its source value through both emitted action routes")
    func boundOrderedAssignmentOutputRejectsRerouting() throws {
        let specification = BoundOrderedAssignment.spec
        let step = try #require(specification.sourceAtomicSteps.first)
        let lowered = ActionNormalization.complete(
            try AlgorithmLowerer.lowerAtomicStep(step).action, variables: specification.variables)
        try StraightLineAssignmentCheck.verify(step, lowered: lowered,
            stateRoots: ["value", "copied"])
        let inputs = try SourceTypeResolver().resolve(in: specification.compile())
        let program = try CompiledProgram(inputs: inputs)
        let source = try #require(specification.loweredSourceModel().actions.first)
        let untyped = try #require(inputs.semantics.behavior.actions.first)
        let action = try #require(program.behavior.actions.first)
        try StraightLineAssignmentCheck.verifyCompiled(source, bindings: action.bindings,
            body: action.body, layout: program.layout)
        try StraightLineAssignmentCheck.verifyResolved(untyped, resolved: action,
            variableTypes: inputs.variableTypes, resolvedVariableTypes: program.variableTypes,
            resolvedBindingTypes: program.bindingTypes)

        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("TypedActionParameterFixtures.swift")
        let syntax = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(syntax.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "BoundOrderedAssignment" })
        let compiled = try TLASpecVerifier.parseAndVerify(declaration)
        var emitter = NativeSwiftEmitter(model: compiled)
        let members = try emitter.machineMembers()
        let update = try #require(members.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let emittedAction = try #require(compiled.program.behavior.actions.first)
        let parts = try emitter.actionFunctions(emittedAction.body)
        try verifyGeneratedActionWriteOutput(update, action: emittedAction.body, program: compiled.program,
            stateFields: emitter.stateMemberNames, parts: parts.writes,
            conditions: parts.conditions, requireScalarLeaves: true,
            externalBindings: emittedAction.bindings)
        let api = try #require(compiled.api.actions.first)
        let boundRoutes = scalarBoundRoutes(program: compiled.program, actions: compiled.api.actions)
        #expect(boundRoutes.count == 1)
        let routes = compiled.api.actions.map { item in
            (name: item.swiftIdentifier, id: item.compiledAction.ordinal,
             formalName: compiled.program.layout.actions[item.compiledAction.ordinal].renderedName,
             publicBindings: item.bindings.filter(\.isPublic).count)
        }
        let candidates = compiled.api.actions.map { item in
            (name: item.swiftIdentifier, labels: item.bindings.filter(\.isPublic).map(\.swiftIdentifier))
        }
        try verifyGeneratedActionRoutingOutput(members, routes: [], allActions: routes,
            candidates: candidates, configurationArguments: "", boundRoutes: boundRoutes)
        let candidateIndex = try #require(members.firstIndex {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitActionCandidates"
        })
        let wrongCandidates = members[candidateIndex].description.replacingOccurrences(
            of: "[1, 2]", with: "[1]")
        #expect(wrongCandidates != members[candidateIndex].description)
        var wrongMembers = members
        wrongMembers[candidateIndex] = try #require(Parser.parse(source: wrongCandidates)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedActionRoutingOutput(wrongMembers, routes: [], allActions: routes,
                candidates: candidates, configurationArguments: "", boundRoutes: boundRoutes)
        }
        let dispatchIndex = try #require(members.firstIndex {
            $0.description.contains("private func _visitSuccessors(for action: Action,")
        })
        let binder = try #require(boundRoutes.first?.bindings.first?.name)
        let wrongUpdateSource = update.description.replacingOccurrences(
            of: "= \(binder)", with: "= state.state.value")
        #expect(wrongUpdateSource != update.description)
        let wrongUpdate = try #require(Parser.parse(source: wrongUpdateSource)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedActionWriteOutput(wrongUpdate, action: emittedAction.body, program: compiled.program,
                stateFields: emitter.stateMemberNames, parts: parts.writes,
                conditions: parts.conditions, requireScalarLeaves: true,
                externalBindings: emittedAction.bindings)
        }
        let wrongDispatch = members[dispatchIndex].description.replacingOccurrences(
            of: "\(binder): \(binder), checking:", with: "\(binder): 1, checking:")
        #expect(wrongDispatch != members[dispatchIndex].description)
        wrongMembers = members
        wrongMembers[dispatchIndex] = try #require(Parser.parse(source: wrongDispatch)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedActionRoutingOutput(wrongMembers, routes: [], allActions: routes,
                candidates: candidates, configurationArguments: "", boundRoutes: boundRoutes)
        }
        let formalIndex = try #require(members.firstIndex {
            $0.as(FunctionDeclSyntax.self)?.name.text == "formalCall"
        })
        let wrongFormal = members[formalIndex].description.replacingOccurrences(
            of: "TLAValue.int(\(binder))", with: "TLAValue.int(1)")
        #expect(wrongFormal != members[formalIndex].description)
        wrongMembers = members
        wrongMembers[formalIndex] = try #require(Parser.parse(source: wrongFormal)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedActionRoutingOutput(wrongMembers, routes: [], allActions: routes,
                candidates: candidates, configurationArguments: "", boundRoutes: boundRoutes)
        }

        let output = try program.renderModule()
        let module = output.renderedModuleSource
        let formalBinder = try #require(program.binderNames[action.bindings[0].binder])
        let header = "select(\(formalBinder)) == "
        let lines = module.split(separator: "\n").filter { $0.hasPrefix(header) }
        let body = try #require(lines.count == 1 ? lines[0].dropFirst(header.count) : nil)
        try StraightLineRenderedActionCheck.verifyDeclaration(action, named: "select",
            body: String(body), module: module, layout: program.layout, binders: program.binderNames,
            failureDeclarations: output.evaluationFailureDeclarations)
        let wrongModule = module.replacingOccurrences(of: header, with: "select(wrong) == ")
        #expect(wrongModule != module)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verifyDeclaration(action, named: "select",
                body: String(body), module: wrongModule, layout: program.layout, binders: program.binderNames,
                failureDeclarations: output.evaluationFailureDeclarations)
        }
        let machine = try BoundOrderedAssignment.makeMachine()
        #expect(try machine.actionCandidates() == [.select(member: 1), .select(member: 2)])
        for member in [1, 2] {
            var selected = machine
            _ = try selected.send(.select(member: member))
            #expect(selected.state.value == member && selected.state.copied == member)
            #expect(try machine.formalCall(for: .select(member: member)) ==
                FormalActionCall(name: "select", arguments: [.int(member)]))
        }
        #expect(api.bindings.count == 1)
    }

    @Test("Generated candidates pass each bound value to its labeled action argument")
    func candidateBindingOutputRejectsSubstitution() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("TypedActionParameterFixtures.swift")
        let syntax = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(syntax.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "TypedParameterSelection" })
        let compiled = try TLASpecVerifier.parseAndVerify(declaration)
        var emitter = NativeSwiftEmitter(model: compiled)
        let members = try emitter.machineMembers()
        let candidates = compiled.api.actions.map { api in
            (name: api.swiftIdentifier, labels: api.bindings.filter(\.isPublic).map(\.swiftIdentifier))
        }
        let allActions = compiled.api.actions.map { api in
            (name: api.swiftIdentifier, id: api.compiledAction.ordinal,
             formalName: compiled.program.layout.actions[api.compiledAction.ordinal].renderedName,
             publicBindings: api.bindings.filter(\.isPublic).count)
        }
        try verifyGeneratedActionRoutingOutput(members, routes: [], allActions: allActions,
            candidates: candidates, configurationArguments: "")

        let sourceIndex = try #require(members.firstIndex {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitActionCandidates"
        })
        let binding = try #require(compiled.program.behavior.actions.first?.bindings.first)
        let boundName = "_\(compiled.program.binderNames[binding.binder]!)_\(binding.binder.ordinal)"
        let wrongSource = members[sourceIndex].description.replacingOccurrences(
            of: "selection: \(boundName)", with: "selection: 1")
        #expect(wrongSource != members[sourceIndex].description)
        var wrongMembers = members
        wrongMembers[sourceIndex] = try #require(Parser.parse(source: wrongSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionRoutingOutput(wrongMembers, routes: [], allActions: allActions,
                candidates: candidates, configurationArguments: "")
            Issue.record("A generated candidate replaced its bound argument with a constant")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.candidateSource")
        }

        let dispatchIndex = try #require(members.firstIndex {
            $0.description.contains("private func _visitSuccessors(for action: Action,")
        })
        let ordinal = try #require(allActions.first?.id)
        let wrongRoute = members[dispatchIndex].description.replacingOccurrences(
            of: "Self._visitSuccessors\(ordinal)", with: "Self._visitSuccessors999")
        #expect(wrongRoute != members[dispatchIndex].description)
        wrongMembers = members
        wrongMembers[dispatchIndex] = try #require(Parser.parse(source: wrongRoute)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionRoutingOutput(wrongMembers, routes: [], allActions: allActions,
                candidates: candidates, configurationArguments: "")
            Issue.record("A selected action reached the wrong compiled successor")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.route.choose")
        }

        let formalIndex = try #require(members.firstIndex {
            $0.as(FunctionDeclSyntax.self)?.name.text == "formalCall"
        })
        let formalName = try #require(allActions.first?.formalName)
        let wrongLabel = members[formalIndex].description.replacingOccurrences(
            of: "name: \(String(reflecting: formalName))", with: "name: \"wrong\"")
        #expect(wrongLabel != members[formalIndex].description)
        wrongMembers = members
        wrongMembers[formalIndex] = try #require(Parser.parse(source: wrongLabel)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionRoutingOutput(wrongMembers, routes: [], allActions: allActions,
                candidates: candidates, configurationArguments: "")
            Issue.record("A selected action used the wrong formal label")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.label.choose")
        }
    }

    @Test("A typed step argument retains its domain, formal call, and assigned result")
    func declaredParametersPreserveNativeAndFormalBindings() throws {
        let machine = try TypedParameterSelection.makeMachine()
        #expect(try machine.enabledActions() == [.choose(selection: 1), .choose(selection: 2)])
        let result = try #require(TLAStateProjection.Token(validating: "result"))
        for selection in [1, 2] {
            var next = machine
            _ = try next.send(.choose(selection: selection))
            #expect(next.state.result == selection + 1)
            #expect(try machine.formalCall(for: .choose(selection: selection)) ==
                FormalActionCall(name: "choose", arguments: [.int(selection)]))
            #expect(try next.formalProjection(of: next.snapshot).value(for: result) == .int(selection + 1))
        }
    }

    @Test("Evaluation failures quantify every typed action argument and remain selected")
    func parameterizedEvaluationFailuresCoverEveryInvocation() throws {
        let rendered = try TypedParameterSelection.render()
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(definitions.contains("__SwiftTLAOverflowOperands0(selection) == <<selection, 1>>"))
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLAAnyEvaluationFailure0(selection) == ") })
        #expect(definitions.contains(#"__SwiftTLAEvaluationOK == ~((\E selection \in {1, 2}: __SwiftTLAAnyEvaluationFailure0(selection)))"#))
        let selected = try rendered.checkSelection(checking: [], checkDeadlock: false)
        #expect(selected.intrinsicInvariantNames == ["__SwiftTLAEvaluationOK"])
        let cfg = try #require(rendered.tlaBundle(checking: [], checkDeadlock: false).root.cfg)
        #expect(cfg.contains("INVARIANT __SwiftTLAEvaluationOK\n"))
    }

    @Test("Symbolic parameter failures retain the action guard and domain")
    func symbolicEvaluationFailuresUseGuardedDomain() throws {
        let scenario = try #require(BoundStepEnabledness.validationScenarios().first)
        let rendered = try scenario.render()
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLAOverflowFailure0(amount) == (((count < 2)) = TRUE /\\ ") })
        #expect(definitions.contains("__SwiftTLAOverflowOperands0(amount) == <<count, amount>>"))
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLAAnyEvaluationFailure0(amount) == ") })
        #expect(definitions.contains(#"__SwiftTLAEvaluationOK == ~((\E amount \in choices: __SwiftTLAAnyEvaluationFailure0(amount)))"#))
        let cfg = try #require(rendered.tlaBundle(checking: [], checkDeadlock: false).root.cfg)
        #expect(cfg.contains("INVARIANT __SwiftTLAEvaluationOK\n"))
    }
}

extension TypedActionParameterTests {
    @Test("collection updates accept typed keys and replacement parameters")
    func collectionUpdatesPreserveParameters() throws {
        let machine = try CollectionParameterUpdates.makeMachine()
        #expect(try machine.enabledActions().count == 4)
        let table = try #require(TLAStateProjection.Token(validating: "table"))
        let partial = try #require(TLAStateProjection.Token(validating: "partial"))
        let sequence = try #require(TLAStateProjection.Token(validating: "sequence"))
        for key in CollectionParameterUpdates.Key.allCases {
            for value in [1, 2] {
                var next = machine
                _ = try next.send(.replace(key: key, value: value))
                #expect(next.state.table[key] == value)
                #expect(next.state.partial == [key: value])
                #expect(next.state.sequence == [0: value, 1: 0])
                #expect(try machine.formalCall(for: .replace(key: key, value: value)) ==
                    FormalActionCall(name: "replace", arguments: [.string(key.rawValue), .int(value)]))
                let projected = try next.formalProjection(of: next.snapshot)
                #expect(projected.value(for: table) == .function([
                    .string("first"): .int(key == .first ? value : 0),
                    .string("second"): .int(key == .second ? value : 0)
                ]))
                #expect(projected.value(for: partial) == .function([.string(key.rawValue): .int(value)]))
                #expect(projected.value(for: sequence) == .function([.int(0): .int(value), .int(1): .int(0)]))
            }
        }
    }
}

// These calls exercise the public protocol boundary without expression wrappers.
extension TypedActionParameterTests {
    @Test("Collection inputs and callbacks preserve typed parameter expressions")
    func collectionInputsAcceptTypedParameters() {
        let value = ActionParameter("value", values: [1, 2])
        let flag = ActionParameter("flag", values: [false, true])
        let members = Var("members", SetExpr<Int>(1, 2))
        let sequence = Var<TupleExpr<Int>>("sequence")
        #expect(members.mapping(file: "test", line: 1, column: 1) { _ in value }.stateExpr == members.expr.mapping(file: "test", line: 1, column: 1) { _ in value.expr }.stateExpr)
        #expect(members.union(members).stateExpr == members.expr.union(members.expr).stateExpr)
        #expect(sequence.concatenating(sequence).stateExpr == sequence.expr.concatenating(sequence.expr).stateExpr)
        #expect(SetExpr<Int>.literal(value, value + 1).stateExpr == .setLiteral([value.stateExpr, (value + 1).stateExpr]))
        #expect(TupleExpr<Int>.literal(value, 3).stateExpr == .tupleLiteral([value.stateExpr, 3.stateExpr]))
        #expect(Exists(in: members, file: "test", line: 1, column: 1) { _ in flag }.stateExpr ==
            Exists(in: members.expr, file: "test", line: 1, column: 1) { _ in flag.expr }.stateExpr)
    }
}
