// Example ID: generated-machine-testing

import SwiftTLA

func runGeneratedMachineTesting() throws {
    var machine = try BoundedCounter.makeMachine()
    let transitionBefore = machine.state
    try machine.send(.advance)
    let beforeFailure = machine.state

    assert(transitionBefore.value == 0)
    let isEnabled = try machine.isEnabled(.advance)
    assert(isEnabled == false)
    assert(machine.state.value == 1)

    var rejected = false
    do {
        try machine.send(.advance)
    } catch is GeneratedMachineError {
        rejected = true
    }
    assert(rejected)
    assert(machine.state == beforeFailure)
}
