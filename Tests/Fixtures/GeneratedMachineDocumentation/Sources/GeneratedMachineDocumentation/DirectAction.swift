// Example ID: generated-machine-direct-action

import SwiftTLA

func runDirectAction() throws {
    var machine = BoundedCounter()
    let actions = try machine.availableActions()
    let evidence = try machine.apply(.advance)

    assert(actions == [.advance])
    assert(evidence.label == .advance)
    assert(evidence.before["value"] == .int(0))
    assert(evidence.after["value"] == .int(1))
    assert(machine.tlaSnapshot()["value"] == .int(1))
}
