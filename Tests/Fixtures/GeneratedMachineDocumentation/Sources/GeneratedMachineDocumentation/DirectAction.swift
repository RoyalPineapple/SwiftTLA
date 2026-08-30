// Example ID: generated-machine-direct-action

import SwiftTLA

func runDirectAction() throws {
    var machine = try BoundedCounter.makeMachine()
    let actions = try machine.enabledActions()
    let transition = try machine.send(.advance)

    assert(actions == [.advance])
    assert(transition.action == .advance)
    assert(transition.before.value == 0)
    assert(transition.after.value == 1)
    assert(machine.state.value == 1)
}
