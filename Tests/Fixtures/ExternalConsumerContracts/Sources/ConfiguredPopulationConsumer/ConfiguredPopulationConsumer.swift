import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct DeviceContract {
    enum Label: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("Devices") { scope in
            let count = scope.parameter(as: Int.self, in: 1...4)
            let devices: Expr<Set<Int>> = IntRange(1, through: count)
            let phase = scope.sharedVar(initial:
                Dictionary<Int, Int>.mapping(over: devices) { _ in 0 })
            let NonnegativePhase = Invariant()

            let advance = Algorithm(scoped: { scope in
                Each(devices, scoped: { (device: ProcessIdentifier<Int>, scope: ProcessScope) in
                    Do(Label.advance) {
                        Assign(phase[device], to: phase[device] + 1)
                        Goto(Label.advance)
                    }
                })
            })
            advance
            NonnegativePhase {
                ForAll(in: devices) { device in phase[device] >= 0 }
            }

            let twoDevices = Validation { Bind(count, to: 2) }
            twoDevices
        }
    }
}

let configuration = try DeviceContract.Configuration(count: 2)
var machine = try DeviceContract.makeMachine(configuration: configuration)
guard machine.state.phase == [1: 0, 2: 0] else {
    throw FixtureError.invalidInitialState
}
let transition = try machine.send(.advance(process: 1))
guard transition.after.phase == [1: 1, 2: 0], machine.state.phase == transition.after.phase else {
    throw FixtureError.invalidTransition
}
let scenarios = try DeviceContract.validationScenarios()
guard scenarios.count == 1,
      scenarios[0].checking.properties == [.NonnegativePhase],
      try scenarios[0].render().tlaBundle.cfg.contains("CONSTANT count = 2") else {
    throw FixtureError.invalidScenario
}

private enum FixtureError: Error {
    case invalidInitialState
    case invalidTransition
    case invalidScenario
}
