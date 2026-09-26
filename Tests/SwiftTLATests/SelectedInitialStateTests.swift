import Testing
import SwiftTLA

struct SelectedInitialStateTests {
    @Test("Selected initialization preserves dependent values and domains")
    func validatesDependentInitialization() throws {
        let initial = SelectedInitialStateModel.State(value: 100_000, copy: 100_001, neighbor: 100_001)
        var machine = try SelectedInitialStateModel.makeMachine(initial)
        #expect(machine.state == initial)
        #expect(try machine.send(.advance).after.value == 100_001)

        for invalid in [
            SelectedInitialStateModel.State(value: -1, copy: 0, neighbor: 0),
            .init(value: 100_001, copy: 100_002, neighbor: 100_001),
            .init(value: 7, copy: 7, neighbor: 8),
            .init(value: 7, copy: 8, neighbor: 9)
        ] {
            #expect(throws: GeneratedMachineError.invalidInitialState) {
                try SelectedInitialStateModel.makeMachine(invalid)
            }
        }
    }
}
