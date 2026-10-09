import Testing
import SwiftTLA

struct GeneratedDependentInitialAlgorithmTests {
    @Test("generated initialization preserves a dependent typed function")
    func generatedInitialStatesPreserveDependency() throws {
        let machines = try GeneratedDependentInitialAlgorithm.initialMachines()
        let mirrors = try #require(TLAStateProjection.Token(validating: "mirrors"))
        #expect(machines.count == 2)
        #expect(Set(machines.map { $0.state.seed }) == [false, true])
        for machine in machines {
            #expect(machine.state.mirrors[.left] == (machine.state.seed ? .active : .inactive))
            #expect(machine.state.mirrors[.right] == .inactive)
            #expect(try machine.formalProjection(of: machine.snapshot).value(for: mirrors) == .function([
                .string("left"): .string(machine.state.seed ? "active" : "inactive"),
                .string("right"): .string("inactive")
            ]))
        }
    }
}
