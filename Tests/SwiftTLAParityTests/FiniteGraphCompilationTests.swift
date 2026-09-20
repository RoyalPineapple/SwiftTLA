import Foundation
import SwiftTLA
import Testing
@testable import UpstreamParity

struct FiniteGraphCompilationTests {
  @Test("every declared finite graph case renders its generated model and preserves scenario selection")
  func rendersRegisteredGeneratedModels() throws {
    let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
      from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
    for declaration in manifest.cases {
      let scenario = try declaration.resolveScenario()
      let rendered = try scenario?.render() ?? declaration.sourceModel.render()
      try rendered.tlaBundle.validateDeclaredClosure()
      #expect(!rendered.tlaBundle.tla.isEmpty)
      if scenario != nil {
        #expect(throws: EvidenceFormatError.invalidField(record: declaration.sourceModel.rawValue,
          field: "model-owned scenario")) { try declaration.sourceModel.render() }
      }
    }
  }

  @Test("The elevator initializes native typed records and action parameters")
  func initializesNativeElevator() throws {
    let machine = try MultiCarElevator.makeMachine()
    #expect(Set(machine.state.cars.keys) == [.carA, .carB])
    let first = try #require(machine.state.cars[.carA])
    let second = try #require(machine.state.cars[.carB])
    #expect(first.floor == .ground)
    #expect(second.floor == .top)
    #expect(!first.doorsOpen && !second.doorsOpen)
    #expect(first.rider == "none" && second.rider == "none")
    let typedCar: MultiCarElevator.Car = first
    #expect(typedCar == MultiCarElevator.Car(floor: .ground, doorsOpen: false, rider: "none"))
    #expect(machine.state.calls.isEmpty)
    #expect(machine.state.lastMoveDoorClosed)
    #expect(try machine.violatedInvariants().isEmpty)
    #expect(try machine.isEnabled(.request(person: .alice, floor: .ground, direction: .up)))
    #expect(try !machine.isEnabled(.assign(person: .alice, car: .carA, direction: .up)))
  }

  @Test("three typed arguments update ordinary records without changing unrelated cars")
  func dispatchesElevatorArguments() throws {
    var machine = try MultiCarElevator.makeMachine()
    _ = try machine.send(.request(person: .bob, floor: .top, direction: .down))
    let typedCalls: Set<MultiCarElevator.Call> = machine.state.calls
    #expect(typedCalls == [MultiCarElevator.Call(person: .bob, floor: .top, direction: .down)])
    _ = try machine.send(.assign(person: .bob, car: .carB, direction: .down))
    _ = try machine.send(.move(car: .carB, direction: .down, floor: .middle))
    #expect(machine.state.cars[.carB] == MultiCarElevator.Car(floor: .middle, doorsOpen: false, rider: "bob"))
    #expect(machine.state.cars[.carA] == MultiCarElevator.Car(floor: .ground, doorsOpen: false, rider: "none"))
    _ = try machine.send(.openDoor(car: .carB, floor: .middle, direction: .down))
    #expect(try !machine.isEnabled(.move(car: .carB, direction: .up, floor: .top)))
    _ = try machine.send(.completeRide(person: .bob, car: .carB, floor: .middle))
    #expect(machine.state.cars[.carB]?.rider == "none")
    #expect(machine.state.calls == typedCalls)
  }

  @Test("both elevator exports retain each named action and every ordered argument combination exactly once")
  func exportsAllElevatorArguments() throws {
    let people: [TLAValue] = [.string("alice"), .string("bob")]
    let cars: [TLAValue] = [.string("carA"), .string("carB")]
    let floors: [TLAValue] = [.int(0), .int(1), .int(2)]
    let directions: [TLAValue] = [.string("up"), .string("down")]
    let signatures: [(String, [[TLAValue]])] = [
      ("request", [people, floors, directions]),
      ("assign", [people, cars, directions]),
      ("move", [cars, directions, floors]),
      ("openDoor", [cars, floors, directions]),
      ("board", [people, cars, floors]),
      ("closeDoor", [cars, floors, directions]),
      ("completeRide", [people, cars, floors])
    ]
    for calls in [try MultiCarElevator.render().actions, try MultiCarElevator.spec.compile().render().actions] {
      #expect(calls.count == 80)
      #expect(Set(calls.map(\.renderedName)).count == 80)
      for (name, domains) in signatures {
        for first in domains[0] {
          for second in domains[1] {
            for third in domains[2] {
              #expect(calls.filter { $0.sourceName == name && $0.arguments == [first, second, third] }.count == 1)
            }
          }
        }
      }
    }
  }
}
