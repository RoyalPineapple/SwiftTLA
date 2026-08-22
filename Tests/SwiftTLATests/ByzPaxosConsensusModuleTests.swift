import Testing
@testable import SwiftTLA

@Suite("byzpaxos Consensus formal module")
struct ByzPaxosConsensusModuleTests {
  @Test("typed declarations render the abstract consensus transition system")
  func typedAbstractConsensusModel() throws {
    let compilation = try ByzPaxosConsensus.module.compile()
    let module = try compilation.renderedTLAModuleBundle().tla

    #expect(ByzPaxosConsensus.module.formalOperatorDefinitions.isEmpty)
    #expect(module.contains("CONSTANTS Value"))
    #expect(module.contains("VARIABLES chosen"))
    #expect(module.contains("Init == chosen = {}"))
    #expect(module.contains("Next =="))
    #expect(module.contains("chosen' = {"))
    #expect(module.contains("Spec =="))
    #expect(module.contains("Success == <>"))
  }

  @Test("direct module dependencies must name a local declaration")
  func rejectsUnknownDirectModuleDependency() {
    let consumer = TLASpec("UnknownDependency") {
      FormalDefinition("Refines", parameters: [], body: true, dependsOn: ["Missing"])
    }

    #expect(throws: CompilationDiagnostic.self) {
      try consumer.compile()
    }
  }

  @Test("direct module dependencies can name executable formal operators")
  func rendersFormalOperatorDependencyBeforeItsUse() throws {
    let consumer = TLASpec("FormalDependency") {
      FormalDefinition("SafeAt", taking: Int.self) { _ in true }
      FormalDefinition(
        "TypeOK",
        parameters: [],
        body: FormalCall<Bool>("SafeAt", 1),
        dependsOn: ["SafeAt"]
      )
    }

    let compilation = try consumer.compile()
    let source = try compilation.renderedTLAModuleBundle().tla
    let operatorRange = try #require(source.range(of: "SafeAt(value0) == TRUE"))
    let useRange = try #require(source.range(of: "TypeOK == SafeAt(1)"))
    #expect(operatorRange.lowerBound < useRange.lowerBound)
  }

  @Test("direct module declaration cycles fail before rendering")
  func rejectsCyclicDirectModuleDependencies() {
    let consumer = TLASpec("CyclicDependencies") {
      FormalDefinition("First", parameters: [], body: true, dependsOn: ["Second"])
      FormalDefinition("Second", parameters: [], body: true, dependsOn: ["First"])
    }

    #expect(throws: CompilationDiagnostic.self) {
      try consumer.compile()
    }
  }
}
