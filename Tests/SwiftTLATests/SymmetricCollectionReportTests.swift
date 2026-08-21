import SwiftTLA
import Testing

@Suite(.serialized)
struct SymmetricCollectionReportTests {
  private struct Device: Identifiable {
    let id: Int
  }

  @Test("Symmetric verification reports its finite scope and bounded-only disclaimer")
  func successfulResultIsWrappedWithScope() throws {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      Invariant("valid") { devices.allSatisfy { $0 == 0 } }
    }

    let result = try ModelChecker(spec: spec).check()
    guard case .bounded(let scopes, let outcome) = result else {
      Issue.record("Expected bounded result, got \(result)")
      return
    }
    #expect(scopes == [SymmetricCollectionScope(collectionName: "devices", verificationScope: 2)])
    #expect({ if case .ok = outcome { true } else { false } }())
    #expect(result.description.contains("BOUNDED VERIFICATION"))
    #expect(result.description.contains("devices: 2 exchangeable members"))
    #expect(result.description.contains("does not prove larger populations"))
  }

  @Test("Ordinary verification results retain their existing shape and text")
  func ordinaryResultIsNotWrapped() throws {
    let counter = Var<Int>("counter")
    let spec = TLASpec("Counter") {
      Variable(counter, 0)
    }

    let result = try ModelChecker(spec: spec).check()
    #expect({ if case .ok = result { true } else { false } }())
    #expect(result.description == "OK — explored 1 state(s)")
  }

  @Test("Symmetric checker failures retain the bounded scope wrapper")
  func checkerFailureIsWrappedWithScope() throws {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      Assume(false)
    }

    let result = try ModelChecker(spec: spec).check()
    guard case .bounded(let scopes, let outcome) = result,
          case .error("ASSUME failed") = outcome else {
      Issue.record("Expected wrapped assumption failure, got \(result)")
      return
    }
    #expect(scopes == [SymmetricCollectionScope(collectionName: "devices", verificationScope: 2)])
  }

  @Test("Invariant violations retain the symmetric bounded scope wrapper")
  func invariantViolationIsBounded() throws {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      Invariant("mustBeOne") { devices.allSatisfy { $0 == 1 } }
    }

    let result = try ModelChecker(spec: spec).check()
    assertBounded(result) { if case .invariantViolated = $0 { true } else { false } }
  }

  @Test("Depth limits retain the symmetric bounded scope wrapper")
  func depthLimitIsBounded() throws {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      CollectionAction("advance", on: devices) { member in
        devices[member] == 0 && devices.update(member, to: 1)
      }
    }

    let result = try ModelChecker(spec: spec, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 1)).check()
    assertBounded(result) { if case .depthExceeded = $0 { true } else { false } }
  }

  @Test("Deadlocks retain the symmetric bounded scope wrapper")
  func deadlockIsBounded() throws {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      DeadlockCheck()
    }

    let result = try ModelChecker(spec: spec).check()
    assertBounded(result) { if case .deadlocked = $0 { true } else { false } }
  }

  @Test("Liveness violations retain the symmetric bounded scope wrapper")
  func livenessViolationIsBounded() throws {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      Eventually("reachesOne", devices.contains { $0 == 1 })
    }

    let result = try ModelChecker(spec: spec).checkLiveness()
    assertBounded(result) { if case .livenessViolated = $0 { true } else { false } }
  }

  @Test("Thrown ASSUME evaluation failures retain bounded reporting")
  func thrownAssumeEvaluationFailureIsBounded() throws {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      Assume(StateExpr.variable("missing"))
    }

    let result = try ModelChecker(spec: spec).check()
    guard case .bounded(let scopes, let outcome) = result,
          case .error(let message) = outcome else {
      Issue.record("Expected wrapped ASSUME evaluation error, got \(result)")
      return
    }
    #expect(scopes == [SymmetricCollectionScope(collectionName: "devices", verificationScope: 2)])
    #expect(message.contains("Undefined variable: missing"))
    #expect(result.description.contains("does not prove larger populations"))
  }

  @Test("Thrown liveness evaluation failures retain bounded reporting")
  func thrownLivenessEvaluationFailureIsBounded() throws {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      Always("defined", .variable("missing"))
    }

    let result = try ModelChecker(spec: spec).checkLiveness()
    guard case .bounded(let scopes, let outcome) = result,
          case .error(let message) = outcome else {
      Issue.record("Expected wrapped liveness evaluation error, got \(result)")
      return
    }
    #expect(scopes == [SymmetricCollectionScope(collectionName: "devices", verificationScope: 2)])
    #expect(message.contains("Undefined variable: missing"))
    #expect(result.description.contains("does not prove larger populations"))
  }

  private func assertBounded(_ result: CheckResult, outcomeMatches: (CheckResult) -> Bool) {
    guard case .bounded(let scopes, let outcome) = result else {
      Issue.record("Expected bounded result, got \(result)")
      return
    }
    #expect(scopes == [SymmetricCollectionScope(collectionName: "devices", verificationScope: 2)])
    #expect(outcomeMatches(outcome), "Expected bounded outcome, got \(outcome)")
    #expect(result.description.contains("does not prove larger populations"))
  }
}
