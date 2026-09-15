import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct SetConfigurationTests {
    @Test("Swift set parameters preserve generated types across scenario populations")
    func variesPopulation() throws {
        let scenarios = try SetConfiguredMachine.validationScenarios()
        #expect(scenarios.count == 2)
        #expect(scenarios.map { $0.configuration.nodes.count } == [1, 3])
        let first = try scenarios[0].render()
        let second = try scenarios[1].render()
        #expect(first.tlaBundle.tla == second.tlaBundle.tla)
        #expect(first.tlaBundle.cfg.contains("CONSTANT nodes = {1}"))
        #expect(second.tlaBundle.cfg.contains("CONSTANT nodes = {1, 2, 3}"))
        #expect(first.checkNames == ["Members", "Quorum"])
        for scenario in scenarios {
            var machine = try #require(scenario.initialMachines().first)
            let transition = try machine.send(.adopt)
            let selected: Set<Int> = transition.after.selected
            #expect(selected == scenario.configuration.nodes)
            #expect(transition.before.selected.isEmpty)
            let graph = try scenario.explore(maximumStates: 10)
            #expect(graph.transitions.count == 2)
            #expect(graph.deadlockedStates.count == 1)
            guard case .reached = graph.reachabilityResults["Quorum"] else {
                Issue.record("Missing quorum witness")
                continue
            }
        }
    }

    @Test("set membership and parameter-dependent domains reject invalid configurations")
    func validatesDomains() throws {
        #expect(throws: GeneratedMachineStateDiagnostic.self) {
            try SetConfiguredMachine.Configuration(nodes: [2], quorum: 1)
        }
        #expect(throws: GeneratedMachineStateDiagnostic.self) {
            try SetConfiguredMachine.Configuration(nodes: [1], quorum: 2)
        }
        #expect(throws: GeneratedMachineStateDiagnostic.self) {
            try SetConfiguredMachine.Configuration(nodes: [], quorum: 0)
        }
        let configuration = try SetConfiguredMachine.Configuration(nodes: [1, 2, 3], quorum: 3)
        #expect(configuration.nodes == [1, 2, 3])
    }

    @Test("Swift set projection rejects invalid and lossy values")
    func validatesProjection() throws {
        let value: Set<Set<Int>> = [[1], [2, 3]]
        #expect(Set<Set<Int>>(formalValue: value.tlaValue) == value)
        #expect(Set<Int>(formalValue: .set([.int(1), .string("1")])) == nil)
        #expect(Set<Int>(formalValue: .tuple([.int(1)])) == nil)
        let collision: Set<CollidingSetMember> = [.init(id: 1), .init(id: 2)]
        #expect(collision.sourceIssue != nil)
        guard case .sourceIssue = collision.stateExpr else {
            Issue.record("Lossy set projection must fail before lowering")
            return
        }
        #expect(Set<CollidingSetMember>(formalValue: .set([.int(1)])) == nil)
        let scope = SpecificationScope()
        let parameter = ModelParameter<Set<CollidingSetMember>>(reference: .init(name: "members"))
        let binding = Bind(parameter, to: collision)
        #expect(binding.value == collision.stateExpr)
        let variable = scope.sharedVar("members", initial: collision)
        guard case .expression(.sourceIssue) = scope.declarations[0].initialization else {
            Issue.record("A variable initializer discarded the invalid set diagnostic")
            return
        }
        #expect(variable.becomes(collision) == .assign(.named("members"), collision.stateExpr))
    }

    @Test("set types and parameter identities survive lowering")
    func retainsResolvedTypes() throws {
        let spec = SetConfiguredMachine.spec
        let compilation = try spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let parameter = try #require(program.layout.parameters.first)
        #expect(parameter.reference == spec.parameters[0].reference)
        #expect(program.bindingTypes[parameter.binder] == .set(.int))
        #expect(program.behavior.parameterDomains[parameter.binder]?.resultType == .set(.set(.int)))
        for scenario in program.behavior.validationScenarios {
            #expect(scenario.bindings[parameter.binder]?.resultType == .set(.int))
        }
        let predicate = try #require(program.behavior.invariants.first { $0.name == "Members" })
        #expect(predicate.predicate.expression.children[1].operation == .boundValue(parameter.binder))
        #expect(predicate.predicate.expression.children[1].resultType == .set(.int))
    }

    @Test("qualified Swift set constructors retain their declared type")
    func parsesQualifiedConstructor() throws {
        let source = Parser.parse(source: "Swift.Set<Int>([1, 2])")
        let expression = try #require(source.statements.first?.item.as(ExprSyntax.self))
        #expect(SpecParser.decodeTypedFacadeValue(expression) == .setLiteral([.int(1), .int(2)]))
    }
}
