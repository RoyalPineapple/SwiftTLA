import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin
@testable import UpstreamParity

@Suite struct OrderedStepTests {
    @Test("Generated ordered writes retain the proved arithmetic and read order")
    func generatedOrderedWriteProofInput() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("OrderedStepFixtures.swift")
        let syntax = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(syntax.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "OrderedCopyModel" })
        let compiled = try TLASpecVerifier.parseAndVerify(declaration)
        let actions = compiled.program.behavior.actions
        let variable = try #require(compiled.program.layout.variables.first {
            $0.declaration.name == "x"
        })
        #expect(actions.count == 3)
        func captures(in node: CompiledActionExpr) -> [(BinderID, CompiledExpression)] {
            switch node {
            case .define(let id, let value, let body):
                return [(id, value)] + captures(in: body)
            case .and(let left, let right), .or(let left, let right),
                 .ifElse(_, let left, let right):
                return captures(in: left) + captures(in: right)
            case .existsAction(_, _, let body): return captures(in: body)
            case .assign, .unchanged, .guard_: return []
            }
        }
        for (index, action) in actions.prefix(2).enumerated() {
            let ordered = captures(in: action.body)
            guard ordered.count == 2 else {
                Issue.record("The ordered source step no longer has two captured writes")
                return
            }
            let first = ordered[0].0
            let firstValue = ordered[0].1
            let secondValue = ordered[1].1
            guard case .add = firstValue.operation,
                  firstValue.children.count == 2,
                  case .stateVariable(let read) = firstValue.children[0].operation,
                  case .value(.integer(1)) = firstValue.children[1].operation,
                  read == variable.id else {
                Issue.record("The ordered source step no longer lowers to the proved first addition")
                return
            }
            if index == 0 {
                guard case .boundValue(let copied) = secondValue.operation,
                      copied == first else {
                    Issue.record("The copy no longer reads the first checked result")
                    return
                }
            } else {
                guard case .add = secondValue.operation,
                      secondValue.children.count == 2,
                      case .boundValue(let prior) = secondValue.children[0].operation,
                      case .value(.integer(1)) = secondValue.children[1].operation,
                      prior == first else {
                    Issue.record("The second addition no longer reads the first checked result")
                    return
                }
            }
        }
        var emitter = NativeSwiftEmitter(model: compiled)
        let members = try emitter.machineMembers()
        let visitors = try ["_visitUpdates0", "_visitUpdates1", "_visitUpdates2"].map { name in
            try #require(members.first {
                $0.as(FunctionDeclSyntax.self)?.name.text == name
            })
        }
        let dispatch = try #require(members.first {
            $0.description.contains("private func _visitSuccessors(for action: Action,")
        })
        let formalCall = try #require(members.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "formalCall"
        })
        let witness = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/OrderedCopySwiftVisitors.txt")
            .standardizedFileURL
        let expected = try String(contentsOf: witness, encoding: .utf8)
        func tokens(_ source: String) -> [String] {
            Parser.parse(source: source).tokens(viewMode: .sourceAccurate).map(\.text)
        }
        let actual = (visitors + [dispatch, formalCall]).map(\.description).joined(separator: "\n")
        #expect(tokens(actual) == tokens(expected))
        let wrongSecondRead = visitors[1].description.replacingOccurrences(
            of: "let _arithmetic0: Int = ___atomic_2_2",
            with: "let _arithmetic0: Int = state.state.x")
        #expect(wrongSecondRead != visitors[1].description)
        #expect(tokens(([
            visitors[0].description, wrongSecondRead, visitors[2].description,
            dispatch.description, formalCall.description
        ]).joined(separator: "\n")) != tokens(expected))
        let secondAction = actions[1]
        let emittedWrites = try emitter.actionFunctions(secondAction.body).writes
        try verifyGeneratedActionWriteOutput(visitors[1], action: secondAction.body,
            program: compiled.program, stateFields: emitter.stateMemberNames, parts: emittedWrites)
        let wrongSecondVisitor = try #require(Parser.parse(source: wrongSecondRead)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongSecondVisitor, action: secondAction.body,
                program: compiled.program, stateFields: emitter.stateMemberNames, parts: emittedWrites)
            Issue.record("A generated addition reread pre-step state instead of its inherited operand")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
            #expect(diagnostic.expected == "the captured value reads its compiled source")
        }
        let wrongRoute = dispatch.description.replacingOccurrences(
            of: "Self._visitSuccessors1", with: "Self._visitSuccessors0")
        #expect(wrongRoute != dispatch.description)
        let routes = compiled.api.actions.map { api in
            (name: api.swiftIdentifier, id: api.compiledAction.ordinal,
             formalName: compiled.program.layout.actions[api.compiledAction.ordinal].renderedName)
        }
        let allActions = compiled.api.actions.map { api in
            (name: api.swiftIdentifier, id: api.compiledAction.ordinal,
             formalName: compiled.program.layout.actions[api.compiledAction.ordinal].renderedName,
             publicBindings: api.bindings.filter(\.isPublic).count)
        }
        let candidatePlans = compiled.api.actions.map { api in
            (name: api.swiftIdentifier,
             labels: api.bindings.filter(\.isPublic).map(\.swiftIdentifier))
        }
        try verifyGeneratedActionRoutingOutput(members, routes: routes, allActions: allActions,
            candidates: candidatePlans, configurationArguments: "")
        let wrongDispatch = try #require(Parser.parse(source: wrongRoute)
            .statements.first?.item.as(DeclSyntax.self))
        var wrongMembers = members
        let dispatchIndex = try #require(wrongMembers.firstIndex {
            $0.description.contains("private func _visitSuccessors(for action: Action,")
        })
        wrongMembers[dispatchIndex] = wrongDispatch
        do {
            try verifyGeneratedActionRoutingOutput(wrongMembers, routes: routes, allActions: allActions,
                candidates: candidatePlans,
                configurationArguments: "")
            Issue.record("A generated action routed to the wrong compiled visitor")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.route."))
        }
        let wrongLabel = formalCall.description.replacingOccurrences(
            of: "name: \"copy\"", with: "name: \"wrong\"")
        #expect(wrongLabel != formalCall.description)
        let wrongFormalCall = try #require(Parser.parse(source: wrongLabel)
            .statements.first?.item.as(DeclSyntax.self))
        let formalIndex = try #require(wrongMembers.firstIndex {
            $0.as(FunctionDeclSyntax.self)?.name.text == "formalCall"
        })
        wrongMembers = members
        wrongMembers[formalIndex] = wrongFormalCall
        do {
            try verifyGeneratedActionRoutingOutput(wrongMembers, routes: routes, allActions: allActions,
                candidates: candidatePlans,
                configurationArguments: "")
            Issue.record("A generated action used the wrong formal label")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.label.copy")
        }
        let candidateIndex = try #require(members.firstIndex {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_actions"
        })
        let wrongCandidates = members[candidateIndex].description.replacingOccurrences(
            of: "try _visitActionCandidates { result.append($0) }",
            with: "try _visitActionCandidates { _ in }")
        #expect(wrongCandidates != members[candidateIndex].description)
        wrongMembers = members
        wrongMembers[candidateIndex] = try #require(Parser.parse(source: wrongCandidates)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionRoutingOutput(wrongMembers, routes: routes, allActions: allActions,
                candidates: candidatePlans, configurationArguments: "")
            Issue.record("A generated candidate list discarded every action")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.candidates")
        }
        let visitorIndex = try #require(members.firstIndex {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitSuccessors"
                && $0.as(FunctionDeclSyntax.self)?.signature.parameterClause.parameters.last?.firstName.text
                    == "onEvaluationFailure"
        })
        let wrongEnumeration = members[visitorIndex].description.replacingOccurrences(
            of: "try _visitActionCandidates(_visitAction)",
            with: "try _visitActionCandidates { _ in }")
        #expect(wrongEnumeration != members[visitorIndex].description)
        wrongMembers = members
        wrongMembers[visitorIndex] = try #require(Parser.parse(source: wrongEnumeration)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionRoutingOutput(wrongMembers, routes: routes, allActions: allActions,
                candidates: candidatePlans, configurationArguments: "")
            Issue.record("Generated checking ignored every action candidate")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.enumeration")
        }
        let sourceIndex = try #require(members.firstIndex {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitActionCandidates"
        })
        let wrongSource = members[sourceIndex].description.replacingOccurrences(
            of: "try visit(.repeatWrites)", with: "try visit(.copy)")
        #expect(wrongSource != members[sourceIndex].description)
        wrongMembers = members
        wrongMembers[sourceIndex] = try #require(Parser.parse(source: wrongSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionRoutingOutput(wrongMembers, routes: routes, allActions: allActions,
                candidates: candidatePlans, configurationArguments: "")
            Issue.record("Generated candidate traversal duplicated one action")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.candidateSource")
        }
    }

    @Test("Later reads observe earlier writes in one atomic transition")
    func orderedReadsAndRepeatedWrites() throws {
        var machine = try OrderedCopyModel.makeMachine()
        let initial = machine.snapshot
        let transition = try machine.send(.copy)
        #expect(transition.before.x == 1)
        #expect(transition.before.y == 0)
        #expect(transition.after.x == 2)
        #expect(transition.after.y == 2)
        let afterCopy = machine.snapshot
        let repeated = try machine.send(.repeatWrites)
        #expect(repeated.before == transition.after)
        #expect(repeated.after.x == 4)
        #expect(repeated.after.y == 2)
        let afterRepeat = machine.snapshot
        let initialMachines = try OrderedCopyModel.initialMachines()
        #expect(initialMachines.count == 1)
        #expect(initialMachines.first?.snapshot == initial)
        let graph = try ReachabilityGraph(
            initialMachines: initialMachines, maximumStates: 4)
        #expect(graph.transitions.count == 3)
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 3)
        let copyEdges = try #require(graph.transitions[initial])
        #expect(copyEdges.count == 1)
        #expect(copyEdges.first?.action == .copy)
        #expect(copyEdges.first?.target == afterCopy)
        let repeatedEdges = try #require(graph.transitions[afterCopy])
        #expect(repeatedEdges.count == 1)
        #expect(repeatedEdges.first?.action == .repeatWrites)
        #expect(repeatedEdges.first?.target == afterRepeat)
        let terminatingEdges = try #require(graph.transitions[afterRepeat])
        #expect(terminatingEdges.count == 1)
        #expect(terminatingEdges.first?.action == .Terminating)
        #expect(terminatingEdges.first?.target == afterRepeat)
    }

    @Test("The checked repeated-write module matches normalized generated TLA")
    func renderedRepeatedWriteProofInput() throws {
        let rendered = try OrderedCopyModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/OrderedCopy.tla")
            .standardizedFileURL
        let checkedModule = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(Int.min <= -2_000_000_000 && 2_000_000_000 <= Int.max)
        let normalized = rendered
            .replacingOccurrences(of: "EXTENDS Integers, FiniteSets, Sequences\n\nVARIABLES",
                with: "EXTENDS Integers, FiniteSets, Sequences\n\nCONSTANTS OrderedIntMin, OrderedIntMax\n\nVARIABLES")
            .replacingOccurrences(of: TLAValue.int(.min).description, with: "OrderedIntMin")
            .replacingOccurrences(of: TLAValue.int(.max).description, with: "OrderedIntMax")
        #expect(normalized == checkedModule)
    }

    @Test("A later checked addition reports the failing operands")
    func laterAdditionFailure() throws {
        let machine = try OrderedOverflowModel.makeMachine()
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try machine.successors(for: .advance)
        }

        let rendered = try OrderedOverflowModel.render()
        let lines = rendered.tlaBundle.root.tla.split(separator: "\n")
        let laterFailure = try #require(lines.first { $0.hasPrefix("__SwiftTLAOverflowFailure0_1 ==") })
        let operands = try #require(lines.first { $0.hasPrefix("__SwiftTLAOverflowOperands0_1 ==") })
        #expect(laterFailure.contains("LET __atomic_0 == (count + 1)"))
        #expect(operands.contains("<<__atomic_0, 1>>"))
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
    }

    @Test("Nested checked additions retain the selected failure in both outputs")
    func nestedAdditionFailure() throws {
        let machine = try NestedAdditionOverflowModel.makeMachine()
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try machine.successors(for: .advance)
        }

        let rendered = try NestedAdditionOverflowModel.render()
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(definitions.filter { $0.hasPrefix("__SwiftTLAOverflowFailure") }.count == 2)
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLAOverflowOperands0_1 ==") && $0.contains("count + 1") })
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))

        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(
            in: NestedAdditionOverflowModel.spec.compile()))
        let action = try #require(program.behavior.actions.first)
        let output = try program.renderModule()
        let name = try #require(program.layout.actions.first?.renderedName)
        let header = "\(name) == "
        let body = try #require(output.renderedModuleSource.split(separator: "\n")
            .first { $0.hasPrefix(header) }?.dropFirst(header.count))
        try StraightLineRenderedActionCheck.verifyDeclaration(action, named: name,
            body: String(body), module: output.renderedModuleSource,
            layout: program.layout, binders: program.binderNames,
            failureDeclarations: output.evaluationFailureDeclarations)
        for prefix in ["__SwiftTLAOverflowFailure0_1 == ",
                       "__SwiftTLAAnyEvaluationFailure0 == "] {
            let original = try #require(output.evaluationFailureDeclarations.first {
                $0.hasPrefix(prefix)
            })
            let changed = "\(prefix)FALSE"
            let wrongModule = output.renderedModuleSource.replacingOccurrences(of: original, with: changed)
            let wrongDeclarations = output.evaluationFailureDeclarations.map { $0 == original ? changed : $0 }
            #expect(wrongModule != output.renderedModuleSource)
            #expect(wrongDeclarations != output.evaluationFailureDeclarations)
            #expect(throws: CompilationDiagnostic.self) {
                try StraightLineRenderedActionCheck.verifyDeclaration(action, named: name,
                    body: String(body), module: wrongModule, layout: program.layout,
                    binders: program.binderNames, failureDeclarations: wrongDeclarations)
            }
        }
        try StraightLineRenderedActionCheck.verifyUnboundEvaluationSelection(program.behavior,
            module: output.renderedModuleSource,
            failureDeclarations: output.evaluationFailureDeclarations,
            evaluationInvariant: "__SwiftTLAEvaluationOK",
            configuration: output.configuration)
        let selection = try #require(output.evaluationFailureDeclarations.first {
            $0.hasPrefix("__SwiftTLAEvaluationOK == ")
        })
        let omittedFailure = "__SwiftTLAEvaluationOK == TRUE"
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verifyUnboundEvaluationSelection(program.behavior,
                module: output.renderedModuleSource.replacingOccurrences(of: selection, with: omittedFailure),
                failureDeclarations: output.evaluationFailureDeclarations.map {
                    $0 == selection ? omittedFailure : $0
                },
                evaluationInvariant: "__SwiftTLAEvaluationOK",
                configuration: output.configuration)
        }
    }

    @Test("Choices and following statements read their current branch values")
    func orderedChoice() throws {
        let machine = try OrderedGuardModel.makeMachine()
        let successors = try machine.successors(for: .choose)
        #expect(successors.count == 1)
        let next = try #require(successors.first)
        #expect(next.state.value == 2)
        #expect(next.state.copied == 2)
    }

    @Test("A later blocked guard discards every earlier write")
    func blockedBranchDoesNotCommit() throws {
        var machine = try OrderedBlockedModel.makeMachine()
        let before = machine.snapshot
        #expect(try machine.successors(for: .advance).isEmpty)
        #expect(throws: GeneratedMachineError.noMatchingSuccessor) {
            try machine.send(.advance)
        }
        #expect(machine.snapshot == before)
    }
    @Test("Assertions read the value at their position in the step")
    func assertionReadsUpdatedValue() throws {
        let graph = try ReachabilityGraph(
            initialMachines: OrderedAssertionModel.initialMachines(), maximumStates: 4)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.transitions.count == 2)
    }

    @Test("a failing algorithm assertion is a generated safety violation")
    func failingAssertionIsChecked() throws {
        guard case .counterexample(let result) = try ReachabilityGraph.check(
            initialMachines: FailingAssertionModel.initialMachines(), maximumStates: 2) else {
            Issue.record("Expected an assertion counterexample")
            return
        }
        guard case .invariant(let property) = try #require(result.violations.first) else {
            Issue.record("Expected the assertion to be checked as an invariant")
            return
        }
        #expect(FailingAssertionModel.formalPropertyNames[property] == "__pcal_assert_0")
        #expect(result.trace.count == 1)
    }

    @Test("Procedure arguments capture earlier writes in the caller")
    func callReadsUpdatedValue() throws {
        let scenario = try #require(OrderedCallModel.validationScenarios().first)
        let graph = try scenario.explore(maximumStates: 8)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.transitions.keys.contains { $0.state.output == 7 })
        #expect(graph.transitions.keys.allSatisfy { $0.state.output == 0 || $0.state.output == 7 })
        let run = try NativeScenarioRun(scenario, maximumStates: 8)
        try run.validateExpectations()
        let rendered = try scenario.render()
        #expect(rendered.actions.contains { $0.sourceName == "procedure.copy.enter" && $0.emittedBaseName == "enter" })
        let emitted = Set(rendered.actions.map(\.emittedInvocationName))
        for transitions in graph.transitions.values {
            for transition in transitions {
                #expect(emitted.contains(try graph.formalCall(for: transition.action).description))
            }
        }
        _ = try rendered.plusCalBundle()
    }

    @Test("Ordinary let captures at its declaration and preserves shadowed values")
    func savedValuesAreStable() throws {
        var machine = try SavedStepValueModel.makeMachine()
        let result = try machine.send(.advance)
        #expect(result.after.count == 4)
        #expect(result.after.copied == 3)
        let graph = try ReachabilityGraph(
            initialMachines: SavedStepValueModel.initialMachines(), maximumStates: 4)
        #expect(graph.safetyViolations.isEmpty)

        let compilation = try SavedStepValueModel.spec.compile()
        let initial = try firstCompiledState(in: compilation)
        let next = try #require(try compiledSuccessors(
            named: "advance", arguments: [], in: compilation, from: initial).first)
        #expect(try renderedValue(named: "count", in: next, compilation: compilation) == .int(4))
        #expect(try renderedValue(named: "copied", in: next, compilation: compilation) == .int(3))
    }

}
