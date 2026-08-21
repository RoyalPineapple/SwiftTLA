import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftTLA

@Suite("typed refinement declarations")
struct RefinementDeclarationTests {
  @Test("finite exploration configuration rejects non-positive bounds")
  func rejectsNonPositiveExplorationBounds() {
    #expect(throws: FiniteExplorationConfigurationError.nonPositiveStateLimit(0)) {
      _ = try FiniteExplorationConfiguration(maximumStateLimit: 0)
    }
    #expect(throws: FiniteExplorationConfigurationError.nonPositiveStateLimit(-1)) {
      _ = try FiniteExplorationConfiguration(maximumStateLimit: -1)
    }
  }

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
      let C = Instance("C", of: ByzPaxosConsensus.module)
      C
      Refinement(name: "Refines", instance: C, operator: .spec, mappings: [.init(ByzPaxosConsensus.Value, from: 0), .init(ByzPaxosConsensus.chosen, from: 0)])
    }
    """
    let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
    let parsed = SpecParser.parseSpecClosure(closure)

    #expect(parsed.diagnostics.isEmpty)
    #expect(parsed.moduleInstances.count == 1)
    #expect(parsed.refinements.count == 1)
    #expect(parsed.refinements.first?.name == "Refines")
    #expect(parsed.refinements.first?.instance.resolves(parsed.moduleInstances[0]) == true)

    let instance = Instance("C", of: ByzPaxosConsensus.module)
    let builder = TLASpec("Parsed") {
      instance
      Refinement(name: "Refines", instance: instance, mappings: [.init(ByzPaxosConsensus.Value, from: 0), .init(ByzPaxosConsensus.chosen, from: 0)])
    }
    #expect(parsed.moduleInstances == builder.moduleInstances)
    #expect(parsed.refinements == builder.refinements)
  }

  @Test("parser retains typed temporal refinement target")
  func parserRetainsTemporalTarget() throws {
    let source = """
    {
      let C = Instance("C", of: ByzPaxosConsensus.module)
      C
      Refinement(name: "Refines", instance: C, operator: .liveSpec, mappings: [])
    }
    """
    let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
    let parsed = SpecParser.parseSpecClosure(closure)

    #expect(parsed.diagnostics.isEmpty)
    #expect(parsed.refinements.first?.operator == .liveSpec)
  }

  @Test("typed temporal capability reports its missing compiler support")
  func rejectsUnimplementedTemporalCapability() {
    let abstract = TLASpec("Abstract") {
      RequireCapability(.temporalFairnessSpecification)
    }

    do {
      _ = try abstract.compile()
      Issue.record("Expected the missing temporal capability to fail compilation.")
    } catch let diagnostic as CompilationDiagnostic {
      #expect(diagnostic.code == .unsupportedTemporalCapability)
      #expect(diagnostic.path == "capabilities.temporalFairnessSpecification")
    } catch {
      Issue.record("Expected a CompilationDiagnostic, got \(error).")
    }
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

    guard case .ok = try ModelChecker(compilation: try concrete.compile()).check().underlyingOutcome else {
      Issue.record("Expected the mapped concrete model to refine the abstract model.")
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

    let result = try ModelChecker(compilation: try concrete.compile()).check()
    guard case .refinementViolated(let refinement, .transition) = result else {
      Issue.record("Expected a refinement transition violation, got \(result).")
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

    let result = try ModelChecker(
      spec: concrete,
      configuration: try FiniteExplorationConfiguration(maximumStateLimit: 1)
    ).check()
    guard case .refinementUnproven(let refinement, .depthExceeded) = result else {
      Issue.record("Expected an unproven refinement result, got \(result).")
      return
    }
    #expect(refinement == "Refines")
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
}
