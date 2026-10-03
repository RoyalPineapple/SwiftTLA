import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct DeviceContract {
    enum DeviceID: String, CaseIterable { case east, west }
    enum Label: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("Devices") { scope in
            let devices = scope.parameter(as: Set<DeviceID>.self,
                in: Subsets(of: Set<DeviceID>([.east, .west])))
            let phase = scope.sharedVar(initial:
                Dictionary<DeviceID, Int>.mapping(over: devices) { _ in 0 })
            let NonnegativePhase = Invariant()

            let advance = Algorithm(scoped: { scope in
                Each(devices, scoped: { (device: ProcessIdentifier<DeviceID>, scope: ProcessScope) in
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

            let twoDevices = Validation { Bind(devices, to: Set<DeviceID>([.east, .west])) }
            twoDevices
        }
    }
}

let configuration = try DeviceContract.Configuration(devices: [.east, .west])
var machine = try DeviceContract.makeMachine(configuration: configuration)
guard machine.state.phase == [.east: 0, .west: 0] else {
    throw FixtureError.invalidInitialState
}
let transition = try machine.send(.advance(process: .east))
guard transition.after.phase == [.east: 1, .west: 0], machine.state.phase == transition.after.phase else {
    throw FixtureError.invalidTransition
}
guard try machine.formalCall(for: .advance(process: .east)) ==
        FormalActionCall(name: "advance", arguments: [DeviceContract.DeviceID.east.tlaValue]),
      let phaseToken = TLAStateProjection.Token(validating: "phase"),
      try machine.formalProjection(of: machine.snapshot).value(for: phaseToken) ==
        TLAValue.function([
            DeviceContract.DeviceID.east.tlaValue: .int(1),
            DeviceContract.DeviceID.west.tlaValue: .int(0)
        ]) else {
    throw FixtureError.invalidFormalProjection
}
let actor = try DeviceContract.Actor(configuration: configuration)
let actorTransition = try await actor.send(.advance(process: .east))
guard actorTransition == transition, await actor.state == machine.state else {
    throw FixtureError.invalidActorTransition
}
let singletonConfiguration = try DeviceContract.Configuration(devices: [.east])
var singleton = try DeviceContract.makeMachine(configuration: singletonConfiguration)
let otherSingleton = try DeviceContract.makeMachine(
    configuration: .init(devices: [.west]))
guard singleton.state.phase != otherSingleton.state.phase,
      !singleton.hasSameConfiguration(as: otherSingleton) else {
    throw FixtureError.mergedDistinctPopulations
}
do {
    _ = try ReachabilityGraph(
        initialMachines: [singleton, otherSingleton], maximumStates: 10)
    throw FixtureError.mergedDistinctPopulations
} catch ExplorationError.configurationMismatch {
}
do {
    _ = try singleton.send(.advance(process: .west))
    throw FixtureError.acceptedAbsentMember
} catch GeneratedMachineError.noMatchingSuccessor {
    guard singleton.state.phase == [.east: 0] else {
        throw FixtureError.invalidRejectedAction
    }
}
let scenarios = try DeviceContract.validationScenarios()
guard scenarios.count == 1,
      scenarios[0].checking.properties == [.NonnegativePhase],
      try scenarios[0].render().tlaBundle.cfg.contains("CONSTANT devices") else {
    throw FixtureError.invalidScenario
}

private enum FixtureError: Error {
    case invalidInitialState
    case invalidTransition
    case invalidFormalProjection
    case invalidActorTransition
    case acceptedAbsentMember
    case invalidRejectedAction
    case mergedDistinctPopulations
    case invalidScenario
}
