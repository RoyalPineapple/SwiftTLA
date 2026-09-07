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

    @Test("Choices execute only in the selected conditional branch")
    func conditionalChoicesDoNotDisappearOrEvaluateInactiveDomains() throws {
        let choice = ActionExpr.chooseAction(.named("chosen"), .setLiteral([.int(1), .int(2)]))
        let invalid = ActionExpr.chooseAction(.named("chosen"), .int(99))
        #expect(try successors(of: .ifElse(.bool(true), choice, invalid)) == [[.int(1), .int(0)], [.int(2), .int(0)]])
        #expect(try successors(of: .ifElse(.bool(false), invalid, choice)) == [[.int(1), .int(0)], [.int(2), .int(0)]])
    }

    @Test("Disjunctive choices enumerate independent branches")
    func disjunctionsDoNotShareSelections() throws {
        let action = ActionExpr.or(
            .chooseAction(.named("chosen"), .setLiteral([.int(1)])),
            .chooseAction(.named("chosen"), .setLiteral([.int(2)]))
        )
        #expect(try successors(of: action) == [[.int(1), .int(0)], [.int(2), .int(0)]])
    }

    @Test("Choice domains retain existential and local definition bindings")
    func nestedDomainsUseTheirLexicalBindings() throws {
        let existential = ActionExpr.existsAction(
            "member", .setLiteral([.int(3), .int(4)]),
            .and(
                .chooseAction(.named("chosen"), .setLiteral([.variable("member")])),
                .assign(.named("copied"), .variable("member"))
            )
        )
        #expect(try successors(of: existential) == [[.int(3), .int(3)], [.int(4), .int(4)]])
        let definition = ActionExpr.define(
            "domain", .setLiteral([.int(5), .int(6)]),
            .chooseAction(.named("chosen"), .variable("domain"))
        )
        #expect(try successors(of: definition) == [[.int(5), .int(0)], [.int(6), .int(0)]])
    }

    @Test("Chosen values remain visible throughout a conjunction")
    func selectionsAreVisibleToEarlierAndLaterExpressions() throws {
        let action = ActionExpr.and(
            .assign(.named("copied"), .variable("chosen")),
            .and(
                .chooseAction(.named("chosen"), .setLiteral([.int(1), .int(2)])),
                .guard_(.equal(.variable("chosen"), .int(2)))
            )
        )
        #expect(try successors(of: action) == [[.int(2), .int(2)]])
        let nested = ActionExpr.and(
            .assign(.named("copied"), .variable("chosen")),
            .ifElse(.bool(true), .chooseAction(.named("chosen"), .setLiteral([.int(7)])), .guard_(.bool(false)))
        )
        #expect(try successors(of: nested) == [[.int(7), .int(0)]])
        let subsequent = ActionExpr.and(
            .ifElse(.bool(true), .chooseAction(.named("chosen"), .setLiteral([.int(7)])), .guard_(.bool(false))),
            .and(
                .guard_(.equal(.variable("chosen"), .int(7))),
                .assign(.named("copied"), .variable("chosen"))
            )
        )
        #expect(try successors(of: subsequent) == [[.int(7), .int(7)]])
    }

    @Test("Repeated choices constrain the same slot by domain intersection")
    func repeatedChoicesNeverOverwriteAnEarlierSelection() throws {
        let first = ActionExpr.chooseAction(.named("chosen"), .setLiteral([.int(1), .int(2)]))
        let second = ActionExpr.chooseAction(.named("chosen"), .setLiteral([.int(2), .int(3)]))
        #expect(try successors(of: .and(first, second)) == [[.int(2), .int(0)]])
        #expect(try successors(of: .and(second, first)) == [[.int(2), .int(0)]])
        #expect(try successors(of: .and(first, .chooseAction(.named("chosen"), .setLiteral([.int(9)])))).isEmpty)
        let scoped = ActionExpr.and(first, .define("domain", .setLiteral([.int(2), .int(3)]), .chooseAction(.named("chosen"), .variable("domain"))))
        #expect(try successors(of: scoped) == [[.int(2), .int(0)]])
    }

    @Test("Assignments remain simultaneous while choice slots are selected")
    func assignmentsDoNotBecomeImperativeUpdates() throws {
        let action = ActionExpr.and(
            .assign(.named("chosen"), .int(1)),
            .assign(.named("copied"), .variable("chosen"))
        )
        #expect(try successors(of: action) == [[.int(1), .int(0)]])
    }

    @Test("Disabled guards short circuit local definitions, branch conditions, and domains")
    func falseGuardsDoNotEvaluateUnreachableExpressions() throws {
        let undefined = StateExpr.divide(.int(1), .int(0))
        let unreachable: [ActionExpr] = [
            .chooseAction(.named("chosen"), undefined),
            .define("local", undefined, .assign(.named("copied"), .variable("local"))),
            .ifElse(.equal(undefined, .int(0)), .guard_(.bool(true)), .guard_(.bool(false))),
            .existsAction("member", undefined, .chooseAction(.named("chosen"), .setLiteral([.variable("member")]))),
            .ifElse(.bool(true), .chooseAction(.named("chosen"), undefined), .guard_(.bool(false)))
        ]
        for action in unreachable {
            #expect(try successors(of: .and(.guard_(.bool(false)), action)).isEmpty)
        }
    }

    @Test("An explicit assignment cannot overwrite a conflicting choice")
    func assignmentsRespectChosenSlotValues() throws {
        let choice = ActionExpr.chooseAction(.named("chosen"), .setLiteral([.int(2)]))
        #expect(try successors(of: .and(choice, .assign(.named("chosen"), .int(2)))) == [[.int(2), .int(0)]])
        #expect(throws: CompiledEvaluationError.self) {
            try successors(of: .and(choice, .assign(.named("chosen"), .int(3))))
        }
    }


    @Test("Repeated normalization preserves conditional choice scopes and frame clauses")
    func normalizationIsIdempotentForConditionalChoices() {
        let variables = [
            NamedVar(name: "chosen", initialization: .value(.int(0)), origin: .source),
            NamedVar(name: "copied", initialization: .value(.int(0)), origin: .source)
        ]
        let action = ActionExpr.ifElse(
            .equal(.variable("copied"), .int(0)),
            .chooseAction(.named("chosen"), .setLiteral([.int(1)])),
            .and(.unchanged(.named("chosen")), .assign(.named("copied"), .int(2)))
        )
        let once = ActionNormalization.complete(action, variables: variables)
        let twice = ActionNormalization.complete(once, variables: variables)
        #expect(once == twice)
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
