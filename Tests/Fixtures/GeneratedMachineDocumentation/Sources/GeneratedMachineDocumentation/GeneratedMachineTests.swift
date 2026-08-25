// Example ID: generated-machine-testing

import SwiftTLA

func runGeneratedMachineTesting() throws {
    var machine = try BoundedCounter.makeMachine()
    let result = try machine.send(.advance)
    let beforeFailure = machine.state

    assert(result.before.value == 0)
    let isEnabled = try machine.isEnabled(.advance)
    assert(isEnabled == false)
    assert(result.after.value == 1)

    do {
        _ = try machine.send(.advance)
        assertionFailure("Expected an unavailable action")
    } catch is GeneratedMachineError {
        assert(machine.state == beforeFailure)
    }
}
