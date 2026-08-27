import Testing

@testable import SwiftTLA
import UpstreamParity

@Suite("MultiCarElevator parity")
struct MultiCarElevatorParityTests {
  @Test("bounded source model has the admitted reachable-state count")
  func boundedSourceModelHasAdmittedReachableStateCount() throws {
    let checker = ModelChecker(
      compilation: try MultiCarElevator.spec.compile(),
      configuration: try FiniteExplorationConfiguration(
        maximumStateLimit: 30_000,
        symmetryReduction: .disabled
      )
    )
    guard case .ok(let stateCount) = try checker.check() else {
      Issue.record("Bounded MultiCarElevator safety model did not complete successfully")
      return
    }
    #expect(stateCount == 3_276)
  }
}
