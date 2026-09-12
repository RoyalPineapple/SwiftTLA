@testable import SwiftTLA
import Testing

struct ChoiceScopeTests {
    private func successors(of action: ActionExpr) throws -> Set<[TLAValue]> {
        let compilation = try canonicalTestSpec(
            variables: [("chosen", .value(.int(0))), ("copied", .value(.int(0)))],
            actions: [("pick", action, [])]
        ).compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let id = try #require(compilation.layout.testActionID(named: "pick"))
        return try Set(runtime.successors(for: id, from: initial).map { successor in
            try compilation.layout.variables.map {
                try successor.state.value(for: $0.id).rendered(using: compilation.layout)
            }
        })
    }

    @Test("Only the selected conditional choice domain is evaluated")
    func conditionalChoicesDoNotEvaluateInactiveDomains() throws {
        let choice = ActionExpr.existsAction("selected", .setLiteral([.int(1), .int(2)]),
            .assign(.named("chosen"), .variable("selected")))
        let invalid = ActionExpr.existsAction("selected", .int(99),
            .assign(.named("chosen"), .variable("selected")))
        #expect(try successors(of: .ifElse(.bool(true), choice, invalid)) == [[.int(1), .int(0)], [.int(2), .int(0)]])
        #expect(try successors(of: .ifElse(.bool(false), invalid, choice)) == [[.int(1), .int(0)], [.int(2), .int(0)]])
    }

    @Test("Choice branches retain independent lexical bindings")
    func disjunctionsAndDefinitionsDoNotShareSelections() throws {
        let action = ActionExpr.or(
            .existsAction("selected", .setLiteral([.int(1)]), .assign(.named("chosen"), .variable("selected"))),
            .define("domain", .setLiteral([.int(2)]),
                .existsAction("selected", .variable("domain"), .assign(.named("chosen"), .variable("selected"))))
        )
        #expect(try successors(of: action) == [[.int(1), .int(0)], [.int(2), .int(0)]])
    }

    @Test("Nested choice domains use outer binders and explicit predicates constrain members")
    func nestedDomainsUseLexicalBindings() throws {
        let action = ActionExpr.existsAction("first", .setLiteral([.int(1), .int(2)]),
            .existsAction("second", .setLiteral([.variable("first")]),
                .guard_(.in(.variable("second"), .setLiteral([.int(2), .int(3)])))
                && .assign(.named("chosen"), .variable("first"))
                && .assign(.named("copied"), .variable("second"))))
        #expect(try successors(of: action) == [[.int(2), .int(2)]])
    }

    @Test("Choosing a value does not mutate the state read by other assignments")
    func stateReadsRemainSimultaneousAndSelectionsAreExplicit() throws {
        let action = ActionExpr.existsAction("selected", .setLiteral([.int(2)]),
            .assign(.named("chosen"), .variable("selected"))
                && .assign(.named("copied"), .variable("chosen")))
        #expect(try successors(of: action) == [[.int(2), .int(0)]])
        let copiedSelection = ActionExpr.existsAction("selected", .setLiteral([.int(2)]),
            .assign(.named("chosen"), .variable("selected"))
                && .assign(.named("copied"), .variable("selected")))
        #expect(try successors(of: copiedSelection) == [[.int(2), .int(2)]])
    }

    @Test("Runtime and rendering agree on selected arguments and formal operator state reads")
    func formalCallsDistinguishSelectedValuesFromCurrentState() throws {
        let action = ActionExpr.existsAction("selected", .setLiteral([.int(1), .int(2)]),
            .guard_(.equal(.variable("selected"), .int(2)))
                && .assign(.named("chosen"), .variable("selected"))
                && .assign(.named("copied"), .operatorApplication(.reference("Echo", arity: 1), [.value(.variable("selected"))]))
                && .assign(.named("observed"), .operatorApplication(.reference("Read", arity: 0), [])))
        let compilation = try canonicalTestSpec(
            variables: [("chosen", .value(.int(0))), ("copied", .value(.int(0))), ("observed", .value(.int(-1)))],
            actions: [("pick", action, [])],
            formalOperatorDefinitions: [
                .init(name: "Echo", parameters: [.value("input")], body: .variable("input")),
                .init(name: "Read", parameters: [], body: .variable("chosen"))
            ]
        ).compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let next = try #require(try runtime.successors(from: initial).first)
        let result = try compilation.layout.variables.map { try next.state.value(for: $0.id) }
        #expect(result == [.integer(2), .integer(2), .integer(0)])
        let rendered = try compilation.render().tlaBundle.tla
        #expect(rendered.contains("chosen' = selected"))
        #expect(rendered.contains("copied' = Echo(selected)"))
        #expect(rendered.contains("observed' = Read"))
        #expect(rendered.contains("Read == chosen"))
    }

    @Test("Disabled guards do not evaluate unreachable definitions, conditions, or domains")
    func falseGuardsShortCircuitUndefinedExpressions() throws {
        let undefined = StateExpr.divide(.int(1), .int(0))
        let unreachable: [ActionExpr] = [
            .define("local", undefined, .assign(.named("copied"), .variable("local"))),
            .ifElse(.equal(undefined, .int(0)), .guard_(.bool(true)), .guard_(.bool(false))),
            .existsAction("selected", undefined, .assign(.named("chosen"), .variable("selected")))
        ]
        for action in unreachable {
            #expect(try successors(of: .and(.guard_(.bool(false)), action)).isEmpty)
        }
    }

    @Test("Repeated normalization preserves conditional choice scopes and frame clauses")
    func normalizationIsIdempotentForBoundChoices() {
        let variables = [
            NamedVar(name: "chosen", initialization: .value(.int(0)), origin: .source),
            NamedVar(name: "copied", initialization: .value(.int(0)), origin: .source)
        ]
        let action = ActionExpr.ifElse(
            .equal(.variable("copied"), .int(0)),
            .existsAction("selected", .setLiteral([.int(1)]), .assign(.named("chosen"), .variable("selected"))),
            .and(.unchanged(.named("chosen")), .assign(.named("copied"), .int(2)))
        )
        let once = ActionNormalization.complete(action, variables: variables)
        #expect(once == ActionNormalization.complete(once, variables: variables))
        let disabled = ActionExpr.guard_(.bool(false))
        #expect(ActionNormalization.complete(disabled, variables: variables) == disabled)
    }

    @Test("Conditional normalization retains explicit control transfers and implicit fallthrough")
    func generatedControlPathsRetainTheirDestinations() throws {
        for jumps in [false, true] {
            let algorithm = Algorithm("ConditionalControl", scoped: { scope in
                let flag = scope.sharedVar("flag", initial: jumps)
                let count = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.advance) {
                    If(flag) {
                        Goto(TestControlLabel.done)
                    } else: {
                        Assign(count, to: 1)
                    }
                }
                Do(TestControlLabel.copy) {
                    Assign(count, to: 2)
                    Stop()
                }
                Do(TestControlLabel.done) { Stop() }
            })
            let compilation = try TLASpec("ConditionalControl") { algorithm }.compile()
            let runtime = CompiledRuntime(compilation: compilation)
            let initial = try #require(try runtime.initialStates().first)
            let advance = try #require(compilation.layout.testActionID(named: "advance"))
            let next = try #require(try runtime.successors(for: advance, from: initial).first)
            let counter = try #require(compilation.layout.variables.first { $0.declaration.origin == .programCounter })
            let count = try #require(compilation.layout.testVariableID(named: "count"))
            #expect(try next.state.value(for: counter.id).rendered(using: compilation.layout)
                == .string(jumps ? "done" : "copy"))
            #expect(try next.state.value(for: count) == .integer(jumps ? 0 : 1))
        }
    }

}
