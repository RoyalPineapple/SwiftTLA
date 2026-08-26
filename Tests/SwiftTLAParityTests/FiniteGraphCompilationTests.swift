import SwiftTLA
import Testing
import UpstreamParity

struct FiniteGraphCompilationTests {
  @Test("bounded elevator action wrappers come from compilation")
  func compilesOrderedElevatorActionWrappers() throws {
    let calls = try MultiCarElevator.spec.compile().renderedActions()

    #expect(calls.count == 80)
    #expect(calls.first?.renderedName == "request__0_0_0")
    #expect(calls.first?.sourceName == "request")
    #expect(calls.first?.arguments == [.string("alice"), .int(0), .string("up")])
    #expect(calls.last?.renderedName == "completeRide__1_1_2")
    #expect(Set(calls.map(\.renderedName)).count == 80)
  }
}
