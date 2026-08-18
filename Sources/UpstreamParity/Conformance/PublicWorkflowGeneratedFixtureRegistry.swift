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
            generatedActionResult(P4GeneratedCounterFixture.runtime, actionName: actionName, in: state)
          },
          propertyOutcomes: P4GeneratedCounterFixture.runtime.propertyOutcomes(in:)))
    case "p4-generated-counter-intentional-mismatch":
      return PublicWorkflowGeneratedFixtureV1(
        builderSpec: P4GeneratedCounterMismatchFixture.spec,
        machine: PublicWorkflowGeneratedMachineHarnessV1(
          initialStates: P4GeneratedCounterMismatchFixture.runtime.initialStates(),
          actionNames: ["advance"],
          apply: { state, actionName in
            P4GeneratedCounterMismatchFixture.intentionalMismatchActionOutcome(actionName: actionName, in: state)
          },
          propertyOutcomes: P4GeneratedCounterMismatchFixture.runtime.propertyOutcomes(in:)))
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
          propertyOutcomes: P4GeneratedCounterFixture.runtime.propertyOutcomes(in:)))
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
          propertyOutcomes: P4GeneratedCounterFixture.runtime.propertyOutcomes(in:)))
    default:
      throw PublicWorkflowGovernanceErrorV1.invalidField(
        record: id, field: "compiled generated fixture registry")
    }
  }
}

@TLAModel
struct P4GeneratedCounterFixture: Sendable {
  static var spec: TLASpec {
    #spec("P4GeneratedCounter") {
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
struct P4GeneratedCounterMismatchFixture: Sendable {
  static var spec: TLASpec {
    #spec("P4GeneratedCounterIntentionalMismatch") {
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
  ) -> GeneratedActionResult {
    switch generatedActionResult(runtime, actionName: actionName, in: state) {
    case .enabled(let actionName, _):
      return .enabled(actionName: actionName, successors: [["value": .int(2)]])
    case let outcome:
      return outcome
    }
  }
}

func generatedActionResult(
  _ runtime: SpecRuntime,
  actionName: String,
  in state: [String: TLAValue]
) -> GeneratedActionResult {
  guard runtime.spec.actions.contains(where: { $0.name == actionName }) else {
    return .actionNotFound(actionName: actionName)
  }
  do {
    let successors = try runtime.successors(.init(name: actionName), from: state)
    return successors.isEmpty
      ? .disabled(actionName: actionName)
      : .enabled(actionName: actionName, successors: successors)
  } catch let error as SpecRuntime.RuntimeError {
    switch error {
    case .enumerationFailed(_, _, let underlying):
      if case SpecRuntime.RuntimeError.evaluationUnavailable(let message) = underlying {
        return .evaluationUnavailable(
          actionName: actionName,
          diagnostic: .init(code: .evaluatorUnavailable, message: message))
      }
      if let eval = underlying as? EvalError {
        return .evaluationFailed(
          actionName: actionName,
          diagnostic: .init(code: .evaluationError, message: eval.description))
      }
      if let action = underlying as? ActionError {
        return .evaluationFailed(
          actionName: actionName,
          diagnostic: .init(code: .actionError, message: action.description))
      }
      return .evaluationFailed(
        actionName: actionName,
        diagnostic: .init(code: .evaluationError, message: String(describing: underlying)))
    case .actionNotFound:
      return .actionNotFound(actionName: actionName)
    default:
      return .evaluationFailed(
        actionName: actionName,
        diagnostic: .init(code: .evaluationError, message: String(describing: error)))
    }
  } catch {
    return .evaluationFailed(
      actionName: actionName,
      diagnostic: .init(code: .evaluationError, message: String(describing: error)))
  }
}
