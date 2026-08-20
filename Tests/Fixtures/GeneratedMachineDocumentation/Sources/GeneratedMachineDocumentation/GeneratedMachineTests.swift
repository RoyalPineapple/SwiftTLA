// Example ID: generated-machine-testing

import SwiftTLA

func runGeneratedMachineTesting() async throws {
    var machine = try BoundedCounter.makeMachine()
    let initial = await machine.machineObservation()
    let result = try machine.apply(.advance)
    let beforeFailure = machine.state

    assert(initial.projection != nil)
    assert(initial.availableInvocations == [.init(name: "advance", arguments: [.string("only")])])
    assert(result.after.value == 1)

    do {
        _ = try machine.apply(.advance)
        assertionFailure("Expected an unavailable action")
    } catch is GeneratedMachineError {
        assert(machine.state == beforeFailure)
    }
}
