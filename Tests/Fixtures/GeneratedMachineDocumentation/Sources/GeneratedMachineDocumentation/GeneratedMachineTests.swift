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

    var rejected = false
    do {
        _ = try machine.send(.advance)
    } catch is GeneratedMachineError {
        rejected = true
    }
    assert(rejected)
    assert(machine.state == beforeFailure)
}
