import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct StateDeclarationNamesTests {
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
