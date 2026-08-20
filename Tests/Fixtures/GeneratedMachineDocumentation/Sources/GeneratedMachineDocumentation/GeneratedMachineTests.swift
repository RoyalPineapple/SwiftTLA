// Example ID: generated-machine-testing

import SwiftTLA

func runGeneratedMachineTesting() async throws {
    var machine = try BoundedCounter.makeMachine()
    let initial = try await machine.machineObservation()
    let result = try machine.apply(.advance)
    let beforeFailure = machine.state

    assert(initial.state.value == 0)
    assert(initial.availableActions == [.advance])
    assert(result.after.value == 1)

    do {
        _ = try machine.apply(.advance)
        assertionFailure("Expected an unavailable action")
    } catch is GeneratedMachineError {
        assert(machine.state == beforeFailure)
    }
}
