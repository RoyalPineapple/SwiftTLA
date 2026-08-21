import SwiftTLA
import SwiftTLAMacros

/// The compiled fixture registry maps each declared fixture to its source model.
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
      let compilation = try P4GeneratedCounterFixture.compiledSpecification()
      return PublicWorkflowGeneratedFixture(
        builderSpec: P4GeneratedCounterFixture.spec,
        machine: PublicWorkflowGeneratedMachineHarness(
          initialStates: try compilation.initialStateProjections(),
          actions: try actions(named: ["advance"], in: compilation),
          apply: { state, action in
            generatedActionResult(compilation, action: action, in: state)
          },
          propertyOutcomes: compilation.propertyOutcomes(in:)))
    case "p4-generated-counter-intentional-mismatch":
      let compilation = try P4GeneratedCounterMismatchFixture.compiledSpecification()
      return PublicWorkflowGeneratedFixture(
        builderSpec: P4GeneratedCounterMismatchFixture.spec,
        machine: PublicWorkflowGeneratedMachineHarness(
          initialStates: try compilation.initialStateProjections(),
          actions: try actions(named: ["advance"], in: compilation),
          apply: { state, action in
            P4GeneratedCounterMismatchFixture.intentionalMismatchActionOutcome(compilation: compilation, action: action, in: state)
          },
          propertyOutcomes: compilation.propertyOutcomes(in:)))
    case "p4-generated-counter-evaluation-failed":
      let compilation = try P4GeneratedCounterFixture.compiledSpecification()
      return PublicWorkflowGeneratedFixture(
        builderSpec: P4GeneratedCounterFixture.spec,
        machine: PublicWorkflowGeneratedMachineHarness(
          initialStates: try compilation.initialStateProjections(),
          actions: try actions(named: ["advance"], in: compilation),
          apply: { _, _ in
            .evaluationFailed(
              .init(code: .evaluationError, message: "fixture failure"))
          },
          propertyOutcomes: compilation.propertyOutcomes(in:)))
    case "p4-generated-counter-evaluation-unavailable":
      let compilation = try P4GeneratedCounterFixture.compiledSpecification()
      return PublicWorkflowGeneratedFixture(
        builderSpec: P4GeneratedCounterFixture.spec,
        machine: PublicWorkflowGeneratedMachineHarness(
          initialStates: try compilation.initialStateProjections(),
          actions: try actions(named: ["advance"], in: compilation),
          apply: { _, _ in
            .evaluationUnavailable(
              .init(code: .evaluatorUnavailable, message: "fixture unavailable"))
          },
          propertyOutcomes: compilation.propertyOutcomes(in:)))
    default:
      throw PublicWorkflowGovernanceError.invalidField(
        record: id, field: "compiled generated fixture registry")
    }
  }

  private static func actions(
    named names: [String],
    in compilation: CompiledSpecification
  ) throws -> [PublicWorkflowGeneratedAction] {
    try names.map { name in
      guard let id = compilation.actionID(named: name) else {
        throw PublicWorkflowGovernanceError.invalidField(
          record: compilation.identity.value,
          field: "compiled fixture action \(name)"
        )
      }
      return .init(id: id, renderedName: name)
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
    compilation: CompiledSpecification,
    action: ActionID,
    in state: TLAStateProjection
  ) -> GeneratedActionResult {
    switch generatedActionResult(compilation, action: action, in: state) {
    case .enabled:
      do {
        guard let token = TLAStateProjection.Token(validating: "value") else {
          return .evaluationFailed(
            .init(code: .evaluationError, message: "invalid fixture state token")
          )
        }
        return .enabled(successors: [try state.replacing(.int(2), for: token)])
      } catch {
        return .evaluationFailed(
          .init(code: .evaluationError, message: String(describing: error))
        )
      }
    case let outcome:
      return outcome
    }
  }
}

func generatedActionResult(
  _ compilation: CompiledSpecification,
  action: ActionID,
  in state: TLAStateProjection
) -> GeneratedActionResult {
  do {
    let successors = try compilation.successors(for: action, arguments: [], from: state)
    return successors.isEmpty
      ? .disabled
      : .enabled(successors: successors)
  } catch {
    return .evaluationFailed(
      .init(
        code: .evaluationError,
        message: String(describing: error)
      )
    )
  }
}
