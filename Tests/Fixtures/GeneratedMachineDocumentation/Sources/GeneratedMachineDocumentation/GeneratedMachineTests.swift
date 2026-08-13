// Example ID: generated-machine-testing

import SwiftTLA

func runGeneratedMachineTesting() async throws {
    var machine = BoundedCounter()
    let initial = await machine.machineObservation()
    let evidence = try machine.apply(.advance)
    let beforeFailure = machine.tlaSnapshot()

    assert(initial.state["value"] == .int(0))
    assert(initial.availableInvocations == [.init(name: "advance")])
    assert(evidence.after["value"] == .int(1))

    do {
        _ = try machine.apply(.advance)
        assertionFailure("Expected an unavailable action")
    } catch is GeneratedMachineError {
        assert(machine.tlaSnapshot() == beforeFailure)
    }
}
