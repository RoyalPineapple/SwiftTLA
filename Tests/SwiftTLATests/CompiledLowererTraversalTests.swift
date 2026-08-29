import Testing
@testable import SwiftTLA

@Suite("Compiled expression lowering")
struct CompiledLowererTraversalTests {
    @Test("deep action bindings retain identities through compilation and rendering")
    func deepActionBindingsRetainIdentities() throws {
        func nestedAction(prefix: String) -> ActionExpr {
            var body = ActionExpr.assign(.named("value"), .variable("\(prefix)127"))
            for level in (0..<128).reversed() {
                body = .define(
                    "\(prefix)\(level)",
                    .variable(level == 0 ? "value" : "\(prefix)\(level - 1)"),
                    body
                )
            }
            return body
        }

        let action = nestedAction(prefix: "bound")
        #expect(alphaKey(action) == alphaKey(nestedAction(prefix: "renamed")))

        let compilation = try TLASpec(
            name: "DeepActionBindings",
            variables: [NamedVar(name: "value", initial: .int(0))],
            actions: [NamedAction(name: "deep", body: action)],
            invariants: []
        ).compile()
        let compiledAction = try #require(compilation.semantics.actions.first)
        let value = try #require(compilation.layout.variableID(named: "value"))
        var compiled = compiledAction.body
        var previousBinder: BinderID?
        for level in 0..<128 {
            guard case .define(let binder, let boundValue, let body) = compiled else {
                Issue.record("Expected definition at action depth \(level)")
                return
            }
            if let previousBinder {
                guard case .boundValue(let referenced) = boundValue else {
                    Issue.record("Expected action depth \(level) to reference its enclosing binder")
                    return
                }
                #expect(referenced == previousBinder)
            } else {
                guard case .stateVariable(let referenced) = boundValue else {
                    Issue.record("Expected the outer action binding to reference the state variable")
                    return
                }
                #expect(referenced == value)
            }
            previousBinder = binder
            compiled = body
        }
        guard case .assign(let assigned, .boundValue(let referenced)) = compiled else {
            Issue.record("Expected the deepest action binding to feed the assignment")
            return
        }
        #expect(assigned == value)
        #expect(referenced == previousBinder)

        var renderedBody = "value' = bound127"
        for level in (0..<128).reversed() {
            let value = level == 0 ? "value" : "bound\(level - 1)"
            renderedBody = "LET bound\(level) == \(value) IN \(renderedBody)"
        }
        #expect(compilation.renderedTLAModuleBundle().tla.contains("deep == \(renderedBody)"))
    }

    @Test("local operator calls retain their bound compiler identities")
    func localOperatorCallsRetainIdentities() throws {
        let expression = StateExpr.letIn(
            [.init("Identity", parameters: ["input"], body: .variable("input"))],
            .operatorApplication(.reference("Identity", arity: 1), [.value(.int(3))])
        )
        let compilation = try TLASpec(
            name: "LocalOperatorIdentity",
            variables: [],
            actions: [],
            invariants: [.init(name: "Identity", body: expression)]
        ).compile()
        let invariant = try #require(compilation.semantics.invariants.first)
        guard case .letIn(
            let operations,
            .operatorApplication(let reference, let arguments)
        ) = invariant.body,
        operations.count == 1,
        let operation = operations.first,
        arguments.count == 1,
        let argument = arguments.first,
        case .value(.value(.int(3))) = argument,
        case .boundValue(let bodyBinder) = operation.body,
        let parameter = operation.parameters.first
        else {
            Issue.record("Expected one bound local operator call")
            return
        }

        #expect(operation.id == reference)
        #expect(parameter == bodyBinder)
    }

    @Test("nested LET declarations and action binders compile on explicit stacks")
    func nestedLetAndActionBindingsUseValidationStacks() throws {
        var condition = StateExpr.bool(true)
        for level in 0..<128 {
            let operation = "Identity\(level)"
            condition = .letIn(
                [.init(operation, parameters: ["value"], body: .variable("value"))],
                .operatorApplication(.reference(operation, arity: 1), [.value(condition)])
            )
        }

        var action = ActionExpr.guard_(condition)
        for level in 0..<128 {
            action = .define("value\(level)", .int(level), action)
        }

        let compilation = try TLASpec(
            name: "NestedBindings",
            variables: [],
            actions: [.init(name: "step", body: action)],
            invariants: []
        ).compile()

        #expect(compilation.semantics.actions.count == 1)
    }
}
