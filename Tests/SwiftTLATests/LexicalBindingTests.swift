import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct LexicalBindingTests {
    @Test("Lexical reads across alternatives, guards, and conditionals retain their scope in both outputs")
    func boundReadSurvivesActionControlScopes() throws {
        let specification = TLASpec(name: "ScopedActionBinding", variables: [
            .init(name: "value", initial: .int(1)),
            .init(name: "offset", initial: .int(.max)),
            .init(name: "enabled", initial: .bool(true)),
        ], actions: [.init(name: "evaluate", body:
            .define("saved", .add(.variable("value"), .int(1)),
                .or(.guard_(.bool(false)),
                    .ifElse(.variable("enabled"),
                        .define("nested", .add(.variable("saved"), .int(1)),
                            .and(.guard_(.variable("enabled")),
                                .ifElse(.variable("enabled"),
                                    .assign(.named("value"), .add(.variable("nested"), .variable("offset"))),
                                    .assign(.named("value"), .variable("saved"))))),
                        .assign(.named("value"), .variable("saved"))))))], invariants: [])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let action = try #require(program.behavior.actions.first)
        let source = try #require(specification.loweredSourceModel().actions.first)
        try StraightLineAssignmentCheck.verifyCompiled(source, bindings: action.bindings,
            body: action.body, layout: program.layout)
        let bindings = definitions(in: action.body)
        let saved = try #require(bindings.first)
        let nested = try #require(bindings.last)
        #expect(saved.id != nested.id)
        var selectedSum: CompiledExpression?
        _ = action.body.map { expression in
            if expression.operation == .add, expression.children.count == 2,
               expression.children[0].operation == .boundValue(nested.id) {
                selectedSum = expression
            }
            return expression
        }
        let sum = try #require(selectedSum)
        let priorRead = try #require(saved.value.children.first)
        let outerRead = CompiledExpression(operation: .boundValue(saved.id),
            resultType: sum.children[0].resultType, children: [])

        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "ScopedActionBinding", program: program))
        let visitor = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let parts = try emitter.actionFunctions(action.body)
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames, parts: parts.writes,
            conditions: parts.conditions, requireScalarLeaves: true)
        let output = try program.renderModule()
        let renderer = CompiledTLARenderer(moduleName: program.moduleName,
            reservedNames: [], layout: program.layout,
            bindings: .init(binders: program.binderNames), operators: .init(),
            actions: program.behavior.actions, functions: program.functions,
            enums: program.enums, parameterDomains: program.behavior.parameterDomains)
        let actionName = try #require(program.layout.actions.first { $0.id == action.id }?.renderedName)
        let header = "\(actionName) == "
        let declaration = try #require(output.renderedModuleSource.split(separator: "\n").first {
            $0.hasPrefix(header)
        })
        let body = String(declaration.dropFirst(header.count))
        try StraightLineRenderedActionCheck.verify(action.body, rendered: body,
            layout: program.layout, binders: program.binderNames, required: true)
        func verifyFailure(_ module: String, _ failures: [String]) throws {
            try StraightLineRenderedActionCheck.verifyEvaluationSelection(program.behavior,
                module: module, failureDeclarations: failures,
                evaluationInvariant: "__SwiftTLAEvaluationOK",
                configuration: output.configuration, renderer: renderer)
        }
        try verifyFailure(output.renderedModuleSource, output.evaluationFailureDeclarations)
        let operandTuple = "<<\(try renderer.state(sum.children[0])), \(try renderer.state(sum.children[1]))>>"
        let selected = try #require(output.evaluationFailureDeclarations.first {
            $0.hasPrefix("__SwiftTLAOverflowOperands") && $0.contains(operandTuple)
        })
        for operand in [priorRead, outerRead] {
            let wrongSum = CompiledExpression(operation: sum.operation, resultType: sum.resultType,
                children: [operand, sum.children[1]])
            var changedRead = false
            let wrongAction = action.body.map { expression in
                guard expression == sum else { return expression }
                changedRead = true
                return wrongSum
            }
            try #require(changedRead)
            do {
                try StraightLineAssignmentCheck.verifyCompiled(source, bindings: action.bindings,
                    body: wrongAction, layout: program.layout)
                Issue.record("A compiled branch read state or an outer scope instead of its inner binding")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "actions.\(source.name).compiledAssignments")
            }
            let expression = try emitter.expression(sum)
            let changedExpression = try emitter.expression(wrongSum)
            let changed = visitor.description.replacingOccurrences(of: expression, with: changedExpression)
            #expect(changed != visitor.description)
            let changedVisitor = try #require(Parser.parse(source: changed).statements.first?.item.as(DeclSyntax.self))
            do {
                try verifyGeneratedActionWriteOutput(changedVisitor, action: action.body,
                    program: program, stateFields: emitter.stateMemberNames,
                    parts: parts.writes.map {
                        (id: $0.id, slot: $0.slot, value: $0.value.replacingOccurrences(
                            of: expression, with: changedExpression))
                    }, conditions: parts.conditions, requireScalarLeaves: true)
                Issue.record("A Swift branch read the wrong lexical scope despite matching write metadata")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.hasPrefix("native.action.write."))
            }
            let wrongBody = try body.replacingOccurrences(of: renderer.state(sum), with: renderer.state(wrongSum))
            #expect(wrongBody != body)
            do {
                try StraightLineRenderedActionCheck.verify(action.body, rendered: wrongBody,
                    layout: program.layout, binders: program.binderNames, required: true)
                Issue.record("A TLA+ branch read the wrong lexical scope")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "tla.action.scalarAssignments")
            }
            let wrongOperands = try selected.replacingOccurrences(of: operandTuple,
                with: "<<\(renderer.state(operand)), \(renderer.state(sum.children[1]))>>")
            #expect(wrongOperands != selected)
            do {
                try verifyFailure(output.renderedModuleSource.replacingOccurrences(of: selected, with: wrongOperands),
                    output.evaluationFailureDeclarations.map { $0 == selected ? wrongOperands : $0 })
                Issue.record("A selected TLA+ branch failure used operands from the wrong lexical scope")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "tla.evaluationSelection")
            }
        }
    }

    private func definitions(in action: CompiledActionExpr) -> [(id: BinderID, value: CompiledExpression)] {
        var result: [(id: BinderID, value: CompiledExpression)] = []
        var pending = [action]
        while let node = pending.popLast() {
            switch node {
            case .define(let id, let value, let child):
                result.append((id, value))
                pending.append(child)
            case .and(let left, let right), .or(let left, let right),
                 .ifElse(_, let left, let right): pending += [right, left]
            default: break
            }
        }
        return result
    }

    @Test("successive saved values keep distinct identities and types after an assignment")
    func preservesSavedValues() throws {
        var machine = try SavedValuesMachine.makeMachine()
        _ = try machine.send(.save)
        #expect(machine.state.value == 9)
        #expect(machine.state.result == 123)
        #expect(machine.state.valid)
        let graph = try ReachabilityGraph(initialMachines: SavedValuesMachine.initialMachines(), maximumStates: 2)
        #expect(graph.transitions.count == 2)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.transitions.keys.contains(machine.snapshot))
    }
}
