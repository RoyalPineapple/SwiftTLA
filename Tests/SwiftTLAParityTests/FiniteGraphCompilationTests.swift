import Foundation
import SwiftTLA
import Testing
import UpstreamParity

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
    #expect(machine.state.calls.isEmpty)
    #expect(machine.state.lastMoveDoorClosed)
    #expect(try machine.violatedInvariants().isEmpty)
    #expect(try machine.isEnabled(.request(person: .alice, floor: .ground, direction: .up)))
    #expect(try !machine.isEnabled(.assign(person: .alice, car: .carA, direction: .up)))
  }

  @Test("bounded elevator action wrappers come from compilation")
  func compilesOrderedElevatorActionWrappers() throws {
    let calls = try MultiCarElevator.spec.compile().render().actions

    #expect(calls.count == 80)
    #expect(calls.first?.renderedName == "request__0_0_0")
    #expect(calls.first?.sourceName == "request")
    #expect(calls.first?.arguments == [.string("alice"), .int(0), .string("up")])
    #expect(calls.last?.renderedName == "completeRide__1_1_2")
    #expect(Set(calls.map(\.renderedName)).count == 80)
  }
}
