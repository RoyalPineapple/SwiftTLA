import Testing
import SwiftTLA

struct SymbolicConfigurationTests {
    @Test("Configuration validates symbolic membership without enumerating legal domains")
    func validatesMembership() throws {
        let input = Array(repeating: 2, count: 10_000)
        let configuration = try SymbolicConfigurationModel.Configuration(
            members: [1, 2], input: input, limit: 1_000_000_000)
        var machine = try SymbolicConfigurationModel.makeMachine(configuration: configuration)
        #expect(machine.state.sequence == input)
        #expect(try machine.send(.append).after.sequence == input + [1])

        let empty = try SymbolicConfigurationModel.Configuration(members: [], input: [], limit: 0)
        #expect(try SymbolicConfigurationModel.makeMachine(configuration: empty).state.sequence.isEmpty)
        for (members, input, limit): (Set<Int>, [Int], Int) in [
            ([1, 2], [3], 0), ([], [1], 0), ([3], [], 0),
            ([1, 2], [], -1), ([1, 2], [], 1_000_000_001)
        ] {
            #expect(throws: GeneratedMachineStateDiagnostic.self) {
                try SymbolicConfigurationModel.Configuration(members: members, input: input, limit: limit)
            }
        }
        let scenarios = try SymbolicConfigurationModel.validationScenarios()
        #expect(scenarios.count == 1)
        #expect(scenarios[0].configuration.input == [1, 2])
        let first = try SymbolicConfigurationModel.render(configuration: configuration).tlaBundle
        let second = try SymbolicConfigurationModel.render(configuration: empty).tlaBundle
        let emptyBinding = "__SwiftTLAParameter1 == <<>>"
        let inputBinding = "__SwiftTLAParameter1 == \(input.tlaValue)"
        #expect(second.tla.contains(emptyBinding))
        #expect(first.tla == second.tla.replacingOccurrences(of: emptyBinding, with: inputBinding))
        #expect(first.cfg != second.cfg)
        #expect(first.tla.contains("input \\in Seq(members)"))
    }
}
