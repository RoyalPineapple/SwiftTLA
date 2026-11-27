// Example ID: generated-machine-direct-action

import SwiftTLA

func runDirectAction() throws {
    var machine = try BoundedCounter.makeMachine()
    let actions = try machine.enabledActions()
    let transitionBefore = machine.state
    try machine.send(.advance)

    assert(actions == [.advance])
    assert(transitionBefore.value == 0)
    assert(machine.state.value == 1)
}
