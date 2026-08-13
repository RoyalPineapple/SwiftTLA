import SwiftTLA
import SwiftTLAMacros

/// The compiled fixture registry is deliberately small: a manifest selects a
/// named fixture, never an arbitrary in-process specification or closure.
struct PublicWorkflowGeneratedFixtureV1 {
  let builderSpec: TLASpec
  let machine: PublicWorkflowGeneratedMachineHarnessV1

  init(builderSpec: TLASpec, machine: PublicWorkflowGeneratedMachineHarnessV1) {
    self.builderSpec = builderSpec
    self.machine = machine
  }
}

enum PublicWorkflowGeneratedFixtureRegistryV1 {
  static func fixture(id: String) throws -> PublicWorkflowGeneratedFixtureV1 {
    switch id {
    case "p4-generated-counter":
      return PublicWorkflowGeneratedFixtureV1(
        builderSpec: P4GeneratedCounterFixture.spec,
        machine: PublicWorkflowGeneratedMachineHarnessV1(
          initialStates: P4GeneratedCounterFixture.runtime.initialStates(),
          actionNames: ["advance"],
          apply: { state, actionName in
            P4GeneratedCounterFixture.generatedActionOutcome(actionName: actionName, in: state)
          },
          propertyOutcomes: P4GeneratedCounterFixture.generatedPropertyOutcomes(in:)))
    case "p4-generated-counter-intentional-mismatch":
      return PublicWorkflowGeneratedFixtureV1(
        builderSpec: P4GeneratedCounterMismatchFixture.spec,
        machine: PublicWorkflowGeneratedMachineHarnessV1(
          initialStates: P4GeneratedCounterMismatchFixture.runtime.initialStates(),
          actionNames: ["advance"],
          apply: { state, actionName in
            P4GeneratedCounterMismatchFixture.intentionalMismatchActionOutcome(actionName: actionName, in: state)
          },
          propertyOutcomes: P4GeneratedCounterMismatchFixture.generatedPropertyOutcomes(in:)))
    case "p4-generated-counter-evaluation-failed":
      return PublicWorkflowGeneratedFixtureV1(
        builderSpec: P4GeneratedCounterFixture.spec,
        machine: PublicWorkflowGeneratedMachineHarnessV1(
          initialStates: P4GeneratedCounterFixture.runtime.initialStates(),
          actionNames: ["advance"],
          apply: { _, actionName in
            .evaluationFailed(
              actionName: actionName,
              diagnostic: .init(code: .evaluationError, message: "fixture failure"))
          },
          propertyOutcomes: P4GeneratedCounterFixture.generatedPropertyOutcomes(in:)))
    case "p4-generated-counter-evaluation-unavailable":
      return PublicWorkflowGeneratedFixtureV1(
        builderSpec: P4GeneratedCounterFixture.spec,
        machine: PublicWorkflowGeneratedMachineHarnessV1(
          initialStates: P4GeneratedCounterFixture.runtime.initialStates(),
          actionNames: ["advance"],
          apply: { _, actionName in
            .evaluationUnavailable(
              actionName: actionName,
              diagnostic: .init(code: .evaluatorUnavailable, message: "fixture unavailable"))
          },
          propertyOutcomes: P4GeneratedCounterFixture.generatedPropertyOutcomes(in:)))
    default:
      throw PublicWorkflowGovernanceErrorV1.invalidField(
        record: id, field: "compiled generated fixture registry")
    }
  }
}

@TLAModel
struct P4GeneratedCounterFixture {
  static var spec: TLASpec {
    TLASpec("P4GeneratedCounter") {
      let value = Var<Int>("value")
      Variable(value, 0)
      Action("advance") { value.becomes(value + 1).when(value < 1) }
      Invariant("withinBounds") { value >= 0 && value <= 1 }
    }
  }

  @TLAObservable
  final class Observable {}

  @TLAActor
  actor Actor {}
}

@TLAModel
struct P4GeneratedCounterMismatchFixture {
  static var spec: TLASpec {
    TLASpec("P4GeneratedCounterIntentionalMismatch") {
      let value = Var<Int>("value")
      Variable(value, 0)
      Action("advance") { value.becomes(value + 1).when(value < 1) }
      Invariant("withinBounds") { value >= 0 && value <= 1 }
    }
  }

  @TLAObservable
  final class Observable {}

  @TLAActor
  actor Actor {}

  static func intentionalMismatchActionOutcome(
    actionName: String,
    in state: [String: TLAValue]
  ) -> SpecRuntime.RuntimeActionOutcome {
    switch generatedActionOutcome(actionName: actionName, in: state) {
    case .enabled(let actionName, _):
      return .enabled(actionName: actionName, successors: [["value": .int(2)]])
    case let outcome:
      return outcome
    }
  }
}
