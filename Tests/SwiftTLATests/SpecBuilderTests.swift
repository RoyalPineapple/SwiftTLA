import Testing
@testable import SwiftTLA

@Suite("Specification builder")
struct SpecBuilderTests {
  @Test("preserves source order across many declarations")
  func preservesSourceOrderAcrossManyDeclarations() {
    let spec = TLASpec("Ordered") {
      Variable("first", 0)
      Variable("second", 0)
      Variable("third", 0)
      Variable("fourth", 0)
      Variable("fifth", 0)
      Variable("sixth", 0)
      Variable("seventh", 0)
      Variable("eighth", 0)
      Variable("ninth", 0)
      Variable("tenth", 0)
      Variable("eleventh", 0)
      Variable("twelfth", 0)
    }

    #expect(spec.variables.map(\.name) == [
      "first", "second", "third", "fourth", "fifth", "sixth",
      "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth"
    ])
  }

  @Test("variable declarations require an explicit initial value")
  func variableDeclarationsRequireExplicitInitialValue() {
    let values = Var<SetExpr<Int>>("values")
    let specifications = [
      TLASpec("VariableDeclaration") { Variable(values) },
      TLASpec("VariableComponent") { values }
    ]

    for specification in specifications {
      do {
        _ = try specification.compile()
        Issue.record("Expected compilation to reject the variable declaration")
      } catch let diagnostic as CompilationDiagnostic {
        #expect(diagnostic.code == .missingVariableInitializer)
        #expect(diagnostic.path == "variables.values.initExpr")
      } catch {
        Issue.record("Expected CompilationDiagnostic, got \(error)")
      }
    }
  }
}
