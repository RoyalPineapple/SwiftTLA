import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct ModuleCompositionTests {
  @Test func constantsAndAssume() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Extends(.naturals)
      Constant("N", 10)
      Assume(StateExpr.greaterOrEqual(.variable("N"), .value(.int(1))))
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    let tla = try spec.compile().render().tlaBundle.tla
    #expect(tla.contains("CONSTANTS N"))
    #expect(tla.contains("ASSUME"))
  }

  @Test func fairnessWF() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("advance") { x.becomes(x + 1).when(x < 3) }
      WeakFairnessNext()
    }
    let tla = try spec.compile().render().tlaBundle.tla
    #expect(tla.contains("WF_x(Next)"))  // single var → no tuple brackets
  }

  @Test func generatedCfgReferencesNamedDefinitions() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Config") {
      Variable(x, 0)
      Action("advance") { x.becomes(x + 1).when(x < 2) }
      Invariant("TypeOK") { x >= 0 }
      Constraint(x <= 2)
      WeakFairnessNext()
    }

    #expect(try spec.compile().render().tlaBundle.cfg.contains("CONSTRAINT StateConstraint"))
    #expect(!(try spec.compile().render().tlaBundle.cfg.contains("CONSTRAINT (")))
    #expect(!(try spec.compile().render().tlaBundle.cfg.contains("WF_")))
  }

  @Test func generatedCfgAssignsConstants() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("ConstantsConfig") {
      Constant("N", 3)
      Variable(x, 0)
    }

    #expect(try spec.compile().render().tlaBundle.cfg.contains("CONSTANT N = 3"))
  }

  @Test func invariantOutput() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
      Invariant("Safety") { x >= 0 }
    }
    let bundle = try spec.compile().render().tlaBundle
    #expect(bundle.tla.contains("Safety == (x >= 0)"))
    #expect(bundle.cfg.contains("INVARIANT Safety"))
  }

  @Test func definitionsOutput() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      FormalDefinition("Min", parameters: [.value("m"), .value("n")], body: .ifThenElse(.lessThan(.variable("m"), .variable("n")), .variable("m"), .variable("n")))
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    let tla = try spec.compile().render().tlaBundle.tla
    #expect(tla.contains("Min(m, n) == (IF (m < n) THEN m ELSE n)"))
  }

  @Test func extendsNaturals() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Extends(.naturals)
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    let tla = try spec.compile().render().tlaBundle.tla
    #expect(tla.contains("Naturals"))
  }
}
