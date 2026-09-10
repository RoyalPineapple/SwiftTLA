@testable import SwiftTLAPlugin
import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftTLA

@Suite("typed refinement declarations")
struct RefinementDeclarationTests {
  @Test("direct module rendering follows linked instance declarations")
  func rendersLinkedTarget() throws {
    let state = Var<Int>("state", 0)
    let abstract = TLASpec("Abstract") {
      Variable(state)
      Action("stay") { state.stays }
    }
    let instance = Instance("C", of: abstract)
    let concrete = TLASpec("Concrete") {
      instance
      Refinement(name: "Refines", instance: instance, mappings: [.init(state, from: 0)])
    }

    let source = try concrete.compile().renderedTLAModuleBundle().tla
    let instanceRange = try #require(source.range(of: "C == INSTANCE Abstract WITH state <- 0"))
    let refinementRange = try #require(source.range(of: "Refines == C!Spec"))
    #expect(instanceRange.lowerBound < refinementRange.lowerBound)
  }

  @Test("missing instance declaration fails during linking")
  func rejectsUndeclaredInstance() {
    let abstract = TLASpec("Abstract") {
      FormalDefinition("Spec", parameters: [], body: true)
    }
    let instance = Instance("C", of: abstract)
    let concrete = TLASpec("Concrete") {
      Refinement(name: "Refines", instance: instance, mappings: [])
    }

    do {
      _ = try concrete.compile()
      Issue.record("Expected refinement instance linking to fail.")
    } catch let diagnostic as CompilationDiagnostic {
      #expect(diagnostic.code == .unresolvedRefinementInstance)
    } catch {
      Issue.record("Expected a CompilationDiagnostic, got \(error).")
    }
  }

  @Test("missing typed target fails during linking")
  func rejectsMissingTarget() {
    let abstract = TLASpec("Abstract") {
      FormalDefinition("Other", parameters: [], body: true)
    }
    let instance = Instance("C", of: abstract)
    let concrete = TLASpec("Concrete") {
      instance
      Refinement(name: "Refines", instance: instance, mappings: [])
    }

    do {
      _ = try concrete.compile()
      Issue.record("Expected refinement target linking to fail.")
    } catch let diagnostic as CompilationDiagnostic {
      #expect(diagnostic.code == .unresolvedRefinementTarget)
    } catch {
      Issue.record("Expected a CompilationDiagnostic, got \(error).")
    }
  }

  @Test("parser retains the same refinement source declaration")
  func parserBindsDeclaredInstance() throws {
    let source = """
    {
      let abstractProtocol = TLASpec("AbstractProtocol") {
        Parameter("Value")
        let chosen = Var<SetExpr<Int>>("chosen", SetExpr<Int>())
        Variable(chosen)
        Action("Next") { chosen.stays }
      }
      let C = Instance("C", of: abstractProtocol)
      C
      Refinement(name: "Refines", instance: C, operator: .spec, mappings: [.init(FormalModuleParameter("Value"), from: SetExpr<Int>(0)), .init(Var<SetExpr<Int>>("chosen"), from: SetExpr<Int>())])
    }
    """
    let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
    let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

    #expect(parsed.diagnostics.isEmpty)
    #expect(parsed.moduleInstances.count == 1)
    #expect(parsed.refinements.count == 1)
    #expect(parsed.refinements.first?.name == "Refines")
    #expect(parsed.refinements.first?.instance.resolves(parsed.moduleInstances[0]) == true)

    let value = FormalModuleParameter("Value")
    let chosen = Var<SetExpr<Int>>("chosen", SetExpr<Int>())
    let abstractProtocol = TLASpec("AbstractProtocol") {
      value
      Variable(chosen)
      Action("Next") { chosen.stays }
    }
    let instance = Instance("C", of: abstractProtocol)
    let builder = TLASpec("Parsed") {
      instance
      Refinement(name: "Refines", instance: instance, mappings: [
        .init(value, from: SetExpr<Int>(0)),
        .init(chosen, from: SetExpr<Int>())
      ])
    }
    #expect(parsed.moduleInstances == builder.moduleInstances)
    let parsedCompilation = try parsed.compile()
    let builderCompilation = try builder.compile()
    #expect(parsedCompilation.identity == builderCompilation.identity)
  }

  @Test("parser retains typed temporal refinement target")
  func parserRetainsTemporalTarget() throws {
    let source = """
    {
      let abstractProtocol = TLASpec("AbstractProtocol") {
        let chosen = Var<Int>("chosen", 0)
        Variable(chosen)
        Action("Next") { chosen.stays }
      }
      let C = Instance("C", of: abstractProtocol)
      C
      Refinement(name: "Refines", instance: C, operator: .liveSpec, mappings: [])
    }
    """
    let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
    let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

    #expect(parsed.diagnostics.isEmpty)
    #expect(parsed.refinements.first?.operator == .liveSpec)
  }

  @Test("bounded refinement accepts abstract steps and stuttering")
  func checksMappedInitialStatesAndEdges() throws {
    let abstractValue = Var<Int>("abstractValue", 0)
    let abstract = TLASpec("Abstract") {
      Variable(abstractValue)
      Action("advance") {
        abstractValue.becomes(abstractValue + 1).when(abstractValue < 1)
      }
    }
    let concreteValue = Var<Int>("concreteValue", 0)
    let instance = Instance("C", of: abstract)
    let concrete = TLASpec("Concrete") {
      Variable(concreteValue)
      Action("advance") {
        concreteValue.becomes(concreteValue + 1).when(concreteValue < 1)
      }
      instance
      Refinement(name: "Refines", instance: instance, mappings: [.init(abstractValue, from: concreteValue)])
    }

    guard case .ok = try ModelChecker(compilation: try concrete.compile(), configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).check() else {
      Issue.record("Expected the mapped concrete model to refine the abstract model.")
      return
    }
  }

  @Test("refinement mappings use compiled action enabledness")
  func mapsActionEnabledness() throws {
    let abstractEnabled = Var<Bool>("abstractEnabled", true)
    let abstract = TLASpec("Abstract") {
      Variable(abstractEnabled)
      Action("advance") {
        abstractEnabled.becomes(false).when(abstractEnabled)
      }
    }
    let concreteValue = Var<Int>("concreteValue", 0)
    let concreteAdvance = Action("advance") {
      concreteValue.becomes(concreteValue + 1).when(concreteValue < 1)
    }
    let instance = Instance("C", of: abstract)
    let concrete = TLASpec("Concrete") {
      Variable(concreteValue)
      concreteAdvance
      instance
      Refinement(
        name: "Refines",
        instance: instance,
        mappings: [.init(abstractEnabled, from: StateExpr.enabled(concreteAdvance))]
      )
    }

    guard case .ok = try ModelChecker(
      compilation: try concrete.compile(),
      configuration: try .init(maximumStateLimit: 10, symmetryReduction: .disabled)
    ).check() else {
      Issue.record("Expected action enabledness to preserve the abstract transition.")
      return
    }
  }

  @Test("bounded refinement reports a concrete edge outside the abstract relation")
  func rejectsUnmappedConcreteEdge() throws {
    let abstractValue = Var<Int>("abstractValue", 0)
    let abstract = TLASpec("Abstract") {
      Variable(abstractValue)
      Action("advance") {
        abstractValue.becomes(abstractValue + 1).when(abstractValue < 1)
      }
    }
    let concreteValue = Var<Int>("concreteValue", 0)
    let instance = Instance("C", of: abstract)
    let concrete = TLASpec("Concrete") {
      Variable(concreteValue)
      Action("advance") {
        concreteValue.becomes(concreteValue + 2).when(concreteValue < 1)
      }
      instance
      Refinement(name: "Refines", instance: instance, mappings: [.init(abstractValue, from: concreteValue)])
    }

    let outcome = try ModelChecker(compilation: try concrete.compile(), configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).check()
    guard case .refinementViolated(let refinement, .transition) = outcome else {
      Issue.record("Expected a refinement transition violation, got \(outcome).")
      return
    }
    #expect(refinement == "Refines")
  }

  @Test("incomplete exploration leaves refinement unproven")
  func reportsUnprovenRefinement() throws {
    let abstractValue = Var<Int>("abstractValue", 0)
    let abstract = TLASpec("Abstract") {
      Variable(abstractValue)
      Action("advance") {
        abstractValue.becomes(abstractValue + 1).when(abstractValue < 1)
      }
    }
    let concreteValue = Var<Int>("concreteValue", 0)
    let instance = Instance("C", of: abstract)
    let concrete = TLASpec("Concrete") {
      Variable(concreteValue)
      Action("advance") {
        concreteValue.becomes(concreteValue + 1).when(concreteValue < 1)
      }
      instance
      Refinement(name: "Refines", instance: instance, mappings: [.init(abstractValue, from: concreteValue)])
    }

    let outcome = try ModelChecker(
      compilation: try concrete.compile(),
      configuration: try FiniteExplorationConfiguration(maximumStateLimit: 1, symmetryReduction: .disabled)
    ).check()
    guard case .refinementUnproven(let refinement, .depthExceeded) = outcome else {
      Issue.record("Expected an unproven refinement outcome, got \(outcome).")
      return
    }
    #expect(refinement == "Refines")
  }

  @Test("refinement preserves concrete failures instead of diagnosing a state limit")
  func preservesConcreteExplorationFailures() throws {
    let abstractValue = Var<Int>("abstractValue", 0)
    let abstract = TLASpec("AbstractFailureEvidence") { Variable(abstractValue) }
    let concreteValue = Var<Int>("concreteValue", 0)
    let instance = Instance("C", of: abstract)
    let declaration = TLASpec("ConcreteFailureEvidence") {
      Variable(concreteValue)
      instance
      Refinement(name: "Refines", instance: instance, mappings: [.init(abstractValue, from: concreteValue)])
    }
    let failures: [(ModelCheckingFailureKind, [NamedInvariant], StateExpr?, Bool, VariableInitialization)] = [
      (.invariantViolated, [.init(name: "safe", body: false)], nil, false, .value(.int(0))),
      (.deadlock, [], nil, true, .value(.int(0))),
      (.assumption, [], false, false, .value(.int(0))),
      (.initialState, [], nil, false, .memberOf(.value(.set([]))))
    ]
    let declaredVariable = try #require(declaration.variables.first)
    for (kind, invariants, assume, checkDeadlock, initialization) in failures {
      let spec = TLASpec(
        name: declaration.name,
        variables: [.init(
          name: declaredVariable.name, initialization: initialization,
          generatedSwiftType: declaredVariable.generatedSwiftType, origin: declaredVariable.origin
        )],
        actions: [], invariants: invariants, assume: assume, checkDeadlock: checkDeadlock,
        moduleInstances: declaration.moduleInstances, refinements: declaration.refinements
      )
      let outcome = try ModelChecker(
        compilation: spec.compile(), configuration: .init(maximumStateLimit: 10, symmetryReduction: .disabled)
      ).check()
      #expect(outcome.diagnostic?.kind == kind)
      if case .refinementUnproven = outcome {
        Issue.record("A concrete \(kind) failure must not be replaced by an unproven refinement.")
      }
    }
  }

  @Test("refinement requires the abstract model assumptions to hold")
  func checksAbstractAssumptions() throws {
    let abstractValue = Var<Int>("abstractValue", 0)
    let concreteValue = Var<Int>("concreteValue", 0)
    for assumption in [false, true] {
      let abstract = TLASpec(
        name: "AbstractAssumption", variables: [.init(name: abstractValue.name, initial: .int(0))],
        actions: [], invariants: [], assume: .value(.bool(assumption))
      )
      let instance = Instance("C", of: abstract)
      let concrete = TLASpec("ConcreteAssumption") {
        Variable(concreteValue)
        instance
        Refinement(name: "Refines", instance: instance, mappings: [.init(abstractValue, from: concreteValue)])
      }
      let outcome = try ModelChecker(
        compilation: concrete.compile(), configuration: .init(maximumStateLimit: 10, symmetryReduction: .disabled)
      ).check()
      if assumption {
        guard case .ok = outcome else {
          Issue.record("Expected valid abstract assumptions to permit refinement.")
          continue
        }
      } else {
        #expect(outcome.diagnostic?.kind == .assumption)
      }
    }
  }

  @Test("refinement owns instance substitutions")
  func rejectsDuplicateInstanceMapping() {
    let abstractValue = Var<Int>("abstractValue", 0)
    let abstract = TLASpec("Abstract") {
      Variable(abstractValue)
      Action("stay") { abstractValue.stays }
    }
    let concreteValue = Var<Int>("concreteValue", 0)
    let instance = Instance("C", of: abstract, with: [.init("abstractValue", value: 0)])
    let concrete = TLASpec("Concrete") {
      Variable(concreteValue)
      instance
      Refinement(name: "Refines", instance: instance, mappings: [.init(abstractValue, from: concreteValue)])
    }

    do {
      _ = try concrete.compile()
      Issue.record("Expected duplicate mapping validation to fail.")
    } catch let diagnostic as CompilationDiagnostic {
      #expect(diagnostic.code == .invalidRefinementParameterMapping)
    } catch {
      Issue.record("Expected a CompilationDiagnostic, got \(error).")
    }
  }

  @Test("refinement parameters reject state hidden behind an operator")
  func rejectsStateDependentOperatorMapping() {
    let parameter = FormalModuleParameter("Limit")
    let abstractValue = Var<Int>("abstractValue", 0)
    let abstract = TLASpec("Abstract") {
      parameter
      Variable(abstractValue)
      Action("stay") { abstractValue.stays }
    }
    let concreteValue = Var<Int>("concreteValue", 0)
    let instance = Instance("C", of: abstract)
    let current: Expr<Int> = FormalCall("Current")
    let concrete = TLASpec("Concrete") {
      Variable(concreteValue)
      FormalDefinition("Current", parameters: [], body: concreteValue)
      instance
      Refinement(name: "Refines", instance: instance, mappings: [
        .init(parameter, from: current),
        .init(abstractValue, from: concreteValue)
      ])
    }

    do {
      _ = try concrete.compile()
      Issue.record("Expected state-dependent parameter binding to fail.")
    } catch let diagnostic as CompilationDiagnostic {
      #expect(diagnostic.code == .stateDependentRefinementParameter)
    } catch {
      Issue.record("Expected a CompilationDiagnostic, got \(error).")
    }
  }
}
