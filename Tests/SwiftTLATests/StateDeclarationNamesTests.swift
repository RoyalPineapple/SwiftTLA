import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct StateDeclarationNamesTests {
    @Test("escaped Swift declarations retain unescaped model identities")
    func resolvesEscapedStateNames() throws {
        let compiled = try EscapedStateNamesModel.spec.compile()
        let names = Set(compiled.layout.variables.map(\.declaration.name))
        #expect(names.isSuperset(of: ["repeat", "default", "case"]))
        #expect(names.allSatisfy { !$0.contains("`") })
        let scenario = try #require(EscapedStateNamesModel.validationScenarios().first)
        #expect(EscapedStateNamesModel.formalPropertyNames[.`defer`] == "defer")
        let initial = try #require(scenario.initialMachines().first)
        #expect(initial.state.`repeat` == "payload")
        #expect(initial.state.`default` == 1)
        let next = try #require(initial.successors().first?.machine)
        #expect(next.state.`repeat` == "visited")
        #expect(next.state.`default` == 2)
    }

    @Test("mutable state-handle bindings fail before lowering")
    func rejectsMutableStateHandle() throws {
        let source = try parseSpecTestClosure("""
        {
            Algorithm("Counter", scoped: { scope in
                var count = scope.sharedVar(initial: 0)
                Do("advance") { Assign(count, to: count + 1) }
            })
        }
        """)
        let spec = SpecParser.parseSpecClosure(named: "MutableHandle", source)
        #expect(!spec.diagnostics.isEmpty)
        #expect(throws: (any Error).self) { try spec.compile() }
    }

    @Test("scoped state names derive from Swift bindings across builder scopes")
    func derivesStateNames() throws {
        let compiled = try BoundStateNamesModel.spec.compile()
        let names = Set(compiled.layout.variables.map(\.declaration.name))
        #expect(names.isSuperset(of: ["text", "count", "seen"]))
        #expect(!names.contains("payload"))
        let machines = try BoundStateNamesModel.initialMachines()
        #expect(machines.count == 2)
        for machine in machines {
            #expect(machine.state.text == "payload")
            let successors = try machine.successors()
            #expect(successors.count == 1)
            #expect(successors.first?.machine.state.text == "visited")
        }
    }
}
