import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct PublicWorkflowCompilerPipelineCounterV1 {
  public static var verificationStateLimit: Int { 4 }

  public static var spec: TLASpec {
    #spec("CompilerPipelineCounter") {
      let count = Var<Int>("count", 0)
      Variable(count)
      Action("advance") { count.becomes(count + 1).when(count < 1) }
    }
  }
}

struct PublicWorkflowCompilerPipelineFixtureV1 {
  let compile: () throws -> CompiledSpecification
  let metadata: () -> GeneratedMachineMetadata
  let verificationStateLimit: () -> Int
  let verifyGeneratedMachine: (GeneratedMachineMetadata?, Int) -> GeneratedMachineContractReport
}

enum PublicWorkflowCompilerPipelineFixtureRegistryV1 {
  static func fixture(id: String) throws -> PublicWorkflowCompilerPipelineFixtureV1 {
    switch id {
    case "compiler-pipeline-counter":
      return .init(
        compile: { try PublicWorkflowCompilerPipelineCounterV1.compiledSpecification() },
        metadata: { PublicWorkflowCompilerPipelineCounterV1.generatedMachineMetadata },
        verificationStateLimit: { PublicWorkflowCompilerPipelineCounterV1.verificationStateLimit },
        verifyGeneratedMachine: { metadata, maxStates in
          PublicWorkflowCompilerPipelineCounterV1.verifyGeneratedMachineContract(metadata: metadata, verificationStateLimit: maxStates)
        })
    case "compiler-pipeline-structural-invalid":
      return .init(
        compile: {
          let count = NamedVar(name: "count", initial: .int(0))
          return try TLASpec("CompilerPipelineStructuralInvalid", variables: [count, count], actions: [], invariants: []).compile()
        },
        metadata: { fatalError("structural-invalid fixture has no generated metadata") },
        verificationStateLimit: { fatalError("structural-invalid fixture has no generated machine") },
        verifyGeneratedMachine: { _, _ in fatalError("structural-invalid fixture has no generated machine") })
    default:
      throw PublicWorkflowGovernanceErrorV1.invalidField(record: id, field: "compiler pipeline fixture")
    }
  }
}
