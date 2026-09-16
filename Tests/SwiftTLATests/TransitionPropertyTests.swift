import Testing
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct TransitionPropertyTests {
    @Test("Typed before and after records share native transitions and preserve fair property outcomes")
    func nativeClaims() throws {
        for (scenario, limit) in zip(try TransitionPropertyClaims.validationScenarios(), [2, 3]) {
            let run = try NativeScenarioRun(scenario, maximumStates: 20)
            try run.validateExpectations()
            let graph = try scenario.explore(maximumStates: 20)
            #expect(graph.transitions.count == limit + 1)
            for property: TransitionPropertyClaims.Property in [.increases, .preservesMarker, .composed, .selectedStuttering] {
                #expect(graph.temporalResults[property]?.status == .satisfied)
            }
            let failure = try #require(graph.temporalResults[.preservesParity])
            #expect(failure.status == .violated)
            let witness = try #require(failure.witness)
            let counts = witness.prefix.map { $0.state.value.count }
            let changesParity = zip(counts, counts.dropFirst()).contains { pair in pair.0 % 2 != pair.1 % 2 }
            #expect(changesParity)
            guard case .violated(let trace) = run.native.checks.properties["preservesParity"] else {
                Issue.record("Expected a transition counterexample")
                continue
            }
            try trace.validate(in: run.native.graph.graph)
            let bundle = try scenario.render().tlaBundle
            #expect(bundle.tla.contains("(value)'"))
            #expect(bundle.tla.contains("preservesParity"))
            #expect(bundle.cfg.contains("PROPERTY"))
        }
    }

    @Test("Typed step constructors retain a structured successor read")
    func retainsStructuredExpression() {
        let value = Var<Int>("value")
        let condition: TemporalCondition<Expr<Bool>> = .alwaysStep(on: value) { before, after in after > before }
        #expect(condition.map(\.stateExpr) == .always(.or(
            .equal(.variable("value"), .nextState(.variable("value"))),
            .greaterThan(.nextState(.variable("value")), .variable("value")))))
    }

    @Test("Successor reads outside transition predicates and nested primes fail during lowering")
    func rejectsInvalidContexts() throws {
        let next = StateExpr.nextState(.variable("value"))
        let specifications = [
            canonicalTestSpec(variables: [("value", .value(.int(0)))],
                invariants: [("invalid", .equal(next, .value(.int(0))))]),
            canonicalTestSpec(variables: [("value", .value(.int(0)))],
                temporal: [("invalid", .eventually(.equal(next, .value(.int(0)))))]),
            canonicalTestSpec(variables: [("value", .value(.int(0)))],
                temporal: [("invalid", .always(.equal(.nextState(next), .value(.int(0)))))])
        ]
        for spec in specifications {
            #expect(throws: CompilationDiagnostic.self) { try spec.compile() }
        }
    }

    @Test("Transition-local aliases retain resolved bindings until native emission")
    func resolvesAliasesBeforeStateSelection() throws {
        let specification = canonicalTestSpec(variables: [("value", .value(.int(0)))],
            temporal: [("increases", .always(.letValue("saved", .variable("value"),
                .greaterThan(.nextState(.variable("saved")), .variable("saved")))))])
        let compilation = try specification.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        guard case .always(let query) = program.behavior.temporalProperties[0].expression else {
            Issue.record("Expected a resolved always predicate")
            return
        }
        guard case .letValue(let binding) = query.expression.operation else {
            Issue.record("Expected the resolved alias binding")
            return
        }
        let comparison = query.expression.children[1]
        #expect(comparison.operation == .greaterThan)
        let next = comparison.children[0]
        #expect(next.operation == .nextState)
        #expect(next.resultType == .int)
        #expect(next.children[0].operation == comparison.children[1].operation)
        #expect(next.children[0].operation == .boundValue(binding))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "Aliases", program: program))
        let source = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        #expect(source.contains("nextState.state.value"))
        #expect(!source.contains("CompiledRuntime"))
    }

    @Test("Malformed step predicates fail compilation", arguments: [
        ".alwaysStep(on: value) { before in before > 0 }",
        ".alwaysStep(on: value) { before, after in 1 }",
        ".alwaysStep(value) { before, after in after > before }"
    ])
    func rejectsMalformedSyntax(_ condition: String) throws {
        let spec = SpecParser.parseSpecClosure(named: "Invalid", try parseSpecTestClosure("""
        { scope in
            let value = scope.sharedVar(initial: 0)
            let claim = Temporal()
            claim(\(condition))
            Validation("Check") {}
        }
        """))
        #expect(throws: (any Error).self) {
            let compilation = try spec.compile()
            _ = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        }
    }
}
