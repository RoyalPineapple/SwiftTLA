import SwiftTLA
import SwiftTLAMacros

/// The compiled fixture registry is deliberately small: a manifest selects a
/// named fixture, never an arbitrary in-process specification or closure.
struct PublicWorkflowGeneratedFixture {
  let builderSpec: TLASpec
  let machine: PublicWorkflowGeneratedMachineHarness

  init(builderSpec: TLASpec, machine: PublicWorkflowGeneratedMachineHarness) {
    self.builderSpec = builderSpec
    self.machine = machine
  }
}

enum PublicWorkflowGeneratedFixtureRegistry {
  static func fixture(id: String) throws -> PublicWorkflowGeneratedFixture {
    switch id {
    case "p4-generated-counter":
      let runtime = try SpecRuntime(compilation: P4GeneratedCounterFixture.compiledSpecification())
      return PublicWorkflowGeneratedFixture(
        builderSpec: P4GeneratedCounterFixture.spec,
        machine: PublicWorkflowGeneratedMachineHarness(
          initialStates: try runtime.initialStateProjections(),
          actionNames: ["advance"],
          apply: { state, actionName in
            generatedActionResult(runtime, actionName: actionName, in: state)
          },
          propertyOutcomes: runtime.propertyOutcomes(in:)))
    case "p4-generated-counter-intentional-mismatch":
      let runtime = try SpecRuntime(compilation: P4GeneratedCounterMismatchFixture.compiledSpecification())
      return PublicWorkflowGeneratedFixture(
        builderSpec: P4GeneratedCounterMismatchFixture.spec,
        machine: PublicWorkflowGeneratedMachineHarness(
          initialStates: try runtime.initialStateProjections(),
          actionNames: ["advance"],
          apply: { state, actionName in
            P4GeneratedCounterMismatchFixture.intentionalMismatchActionOutcome(runtime: runtime, actionName: actionName, in: state)
          },
          propertyOutcomes: runtime.propertyOutcomes(in:)))
    case "p4-generated-counter-evaluation-failed":
      let runtime = try SpecRuntime(compilation: P4GeneratedCounterFixture.compiledSpecification())
      return PublicWorkflowGeneratedFixture(
        builderSpec: P4GeneratedCounterFixture.spec,
        machine: PublicWorkflowGeneratedMachineHarness(
          initialStates: try runtime.initialStateProjections(),
          actionNames: ["advance"],
          apply: { _, actionName in
            .evaluationFailed(
              actionName: actionName,
              diagnostic: .init(code: .evaluationError, message: "fixture failure"))
          },
          propertyOutcomes: runtime.propertyOutcomes(in:)))
    case "p4-generated-counter-evaluation-unavailable":
      let runtime = try SpecRuntime(compilation: P4GeneratedCounterFixture.compiledSpecification())
      return PublicWorkflowGeneratedFixture(
        builderSpec: P4GeneratedCounterFixture.spec,
        machine: PublicWorkflowGeneratedMachineHarness(
          initialStates: try runtime.initialStateProjections(),
          actionNames: ["advance"],
          apply: { _, actionName in
            .evaluationUnavailable(
              actionName: actionName,
              diagnostic: .init(code: .evaluatorUnavailable, message: "fixture unavailable"))
          },
          propertyOutcomes: runtime.propertyOutcomes(in:)))
    default:
      throw PublicWorkflowGovernanceError.invalidField(
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
    runtime: SpecRuntime,
    actionName: String,
    in state: TLAStateProjection
  ) -> GeneratedActionResult {
    switch generatedActionResult(runtime, actionName: actionName, in: state) {
    case .enabled(let actionName, _):
      do {
        guard let token = TLAStateProjection.Token(validating: "value") else {
          return .evaluationFailed(
            actionName: actionName,
            diagnostic: .init(code: .evaluationError, message: "invalid fixture state token")
          )
        }
        return .enabled(actionName: actionName, successors: [try state.replacing(.int(2), for: token)])
      } catch {
        return .evaluationFailed(
          actionName: actionName,
          diagnostic: .init(code: .evaluationError, message: String(describing: error))
        )
      }
    case let outcome:
      return outcome
    }
  }
}

func generatedActionResult(
  _ runtime: SpecRuntime,
  actionName: String,
  in state: TLAStateProjection
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
