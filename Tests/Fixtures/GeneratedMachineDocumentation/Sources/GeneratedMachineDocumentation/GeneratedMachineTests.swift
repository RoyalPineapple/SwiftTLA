// Example ID: generated-machine-testing

import SwiftTLA

func runGeneratedMachineTesting() throws {
    var machine = try BoundedCounter.makeMachine()
    let transition = try machine.send(.advance)
    let beforeFailure = machine.state

    assert(transition.before.value == 0)
    let isEnabled = try machine.isEnabled(.advance)
    assert(isEnabled == false)
    assert(transition.after.value == 1)

    do {
        _ = try machine.send(.advance)
        assertionFailure("Expected an unavailable action")
    } catch is GeneratedMachineError {
        assert(machine.state == beforeFailure)
    }
}
