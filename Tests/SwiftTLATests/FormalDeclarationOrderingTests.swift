import Testing
@testable import SwiftTLA

@Suite("formal declaration ordering")
struct FormalDeclarationOrderingTests {
  @Test("dependencies must name a local declaration")
  func rejectsUnknownDependency() {
    let specification = TLASpec("UnknownDependency") {
      FormalDefinition("Refines", parameters: [], body: true, dependsOn: ["Missing"])
    }

    #expect(throws: CompilationDiagnostic.self) {
      try specification.compile()
    }
  }

  @Test("operator dependencies render before their use")
  func rendersDependencyBeforeUse() throws {
    let specification = TLASpec("FormalDependency") {
      FormalDefinition("SafeAt", taking: Int.self) { _ in true }
      let safeAt: Expr<Bool> = FormalCall("SafeAt", 1)
      FormalDefinition(
        "TypeOK",
        parameters: [],
        body: safeAt,
        dependsOn: ["SafeAt"]
      )
    }

    let source = try specification.compile().renderedTLAModuleBundle().tla
    let dependency = try #require(source.range(of: "SafeAt(value0) == TRUE"))
    let use = try #require(source.range(of: "TypeOK == SafeAt(1)"))
    #expect(dependency.lowerBound < use.lowerBound)
  }

  @Test("declaration cycles fail before rendering")
  func rejectsCycle() {
    let specification = TLASpec("CyclicDependencies") {
      FormalDefinition("First", parameters: [], body: true, dependsOn: ["Second"])
      FormalDefinition("Second", parameters: [], body: true, dependsOn: ["First"])
    }

    #expect(throws: CompilationDiagnostic.self) {
      try specification.compile()
    }
  }
}
