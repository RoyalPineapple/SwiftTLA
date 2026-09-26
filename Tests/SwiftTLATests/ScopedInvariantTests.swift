import Testing
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ScopedInvariantTests {
    @Test("outer scenarios select inner predicates without changing the complete graph")
    func preservesScopesAndIdentity() throws {
        let scenarios = try ScopedInvariantMachine.validationScenarios()
        let all = try NativeScenarioRun(scenarios[0], maximumStates: 4)
        let selected = try NativeScenarioRun(scenarios[1], maximumStates: 4)
        try all.validateExpectations()
        try selected.validateExpectations()
        let exhaustive = try NativeModelRun(scenarios[0].explore(maximumStates: 4), rendered: scenarios[0].render())
        #expect(exhaustive.graph == selected.native.graph)
        #expect(exhaustive.graph.graph.states.count == 4)
        #expect(all.native.graph == nil)
        #expect(all.native.checks.properties["stable"] == .unavailable)
        #expect(scenarios[0].checking.properties == [.stable, .unvisited, .top])
        #expect(scenarios[1].checking.properties == [.stable, .top])
        let rendered = try scenarios[1].render()
        let cfg = try #require(rendered.tlaBundle.root.cfg)
        #expect(cfg.contains("INVARIANT stable"))
        #expect(cfg.contains("INVARIANT top"))
        #expect(!cfg.contains("INVARIANT unvisited"))
        #expect(try rendered.plusCalBundle().root.cfg == cfg)
        #expect(try ScopedInvariantMachine.spec.compile().identity == ScopedInvariantMachine.spec.compile().identity)
    }

    @Test("missing, duplicate, and bare forward definitions are rejected", arguments: 0..<3)
    func rejectsInvalidRegistration(variant: Int) throws {
        let registration = ["", "safe { true }\nsafe { false }", "safe"][variant]
        let parsed = SpecParser.parseSpecClosure(named: "Invalid", try parseSpecTestClosure("""
        {
            let safe = Invariant()
            \(registration)
            Validation("Check") {}.checking(only: [safe])
        }
        """))
        #expect(throws: (any Error).self) { try parsed.compile() }
    }

    @Test("a handle names its declaration and survives direct builder registration")
    func registersSameReference() throws {
        let handle = Invariant(_name: "safe")
        let predicate = handle { true }
        #expect(handle.reference == predicate.reference)
        #expect(predicate.name == "safe")
        let spec = TLASpec("Direct") {
            predicate
            Validation("Check") {}.checking(only: [handle])
        }
        let compiled = try spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        #expect(program.behavior.validationScenarios.count == 1)
    }
}
