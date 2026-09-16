import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct DependentRecordSetTests {
    @Test("Dependent record sets preserve parameters, nested bindings, and nominal fields")
    func generatedDomains() throws {
        let scenarios = try DependentRecordSetModel.validationScenarios()
        #expect(scenarios.count == 2)
        for (scenario, maximum) in zip(scenarios, [0, 4]) {
            let expected = Set((0...maximum).flatMap { first in
                (0...first).compactMap { second in
                    first + second <= maximum
                        ? DependentRecordSetModel.Pair(first: first, second: second) : nil
                }
            })
            let machines = try scenario.initialMachines()
            #expect(Set(machines.map { $0.state.pair }) == expected)
            for var machine in machines {
                let before = machine.state
                #expect(try machine.send(.stay).after == before)
            }
            let graph = try scenario.explore(maximumStates: 100)
            #expect(graph.transitions.count == expected.count)
            let bundle = try scenario.render().tlaBundle
            #expect(bundle.tla.contains("UNION"))
            #expect(bundle.tla.contains("first |->"))
            #expect(bundle.tla.contains("second |->"))
        }
    }

    @Test("Set flattening retains empty and duplicate set semantics")
    func flattenedValues() throws {
        let empty = IntRange(1, through: 0).flatMapping { value in
            IntRange(0, through: value)
        }
        let repeated = IntRange(0, through: 3).flatMapping { value in
            IntRange(0, through: value)
        }
        #expect(try compiledValue(empty.stateExpr) == .set([]))
        #expect(try compiledValue(repeated.stateExpr) == .set([.int(0), .int(1), .int(2), .int(3)]))
    }
}
