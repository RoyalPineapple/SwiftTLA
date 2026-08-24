// Example ID: generated-machine-direct-action

import SwiftTLA

func runDirectAction() throws {
    var machine = try BoundedCounter.makeMachine()
    let actions = try machine.enabledActions()
    let result = try machine.send(.advance)

    assert(actions == [.advance])
    assert(result.action == .advance)
    assert(result.before.value == 0)
    assert(result.after.value == 1)
    assert(machine.state.value == 1)
}
