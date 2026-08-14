// Example ID: generated-machine-direct-action

import SwiftTLA

func runDirectAction() throws {
    var machine = BoundedCounter()
    let actions = try machine.availableActions()
    let result = try machine.apply(.advance(process: .only))

    assert(actions == [.advance(process: .only)])
    assert(result.action == .advance(process: .only))
    assert(result.before.value == 0)
    assert(result.after.value == 1)
    assert(machine.state.value == 1)
}
