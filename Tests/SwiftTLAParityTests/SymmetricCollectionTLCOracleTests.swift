import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity
import Foundation

@Suite(.serialized)
struct SymmetricCollectionTLCOracleTests {
  private struct Device: Identifiable {
    let id: Int
  }

  @Test("Symmetric scopes two through four retain model-value orbit counts")
  func scopesRetainModelValueOrbitCounts() throws {
    for scope in 2...4 {
      let spec = oracleSpec(scope: scope)
      let graph = try ModelChecker(compilation: try spec.compile(), configuration: try .init(maximumStateLimit: 100_000)).exploreGraph()
      let result = try ModelChecker(compilation: try spec.compile(), configuration: try .init(maximumStateLimit: 100_000)).check()

      #expect(graph.states.count == scope + 1)
      #expect(result.boundedScopes == [
        SymmetricCollectionScope(collectionName: "devices", verificationScope: scope)
      ])
      let bundle = try spec.compile().renderedTLAModuleBundle()
      #expect(bundle.tla.contains("DevicesKeys == {DevicesMember0"))
      #expect(bundle.cfg.contains("CONSTANT DevicesMember\(scope - 1) = DevicesMember\(scope - 1)"))
      #expect(bundle.cfg.contains("SYMMETRY SymmDevices"))
      #expect(!bundle.tla.contains("\"DevicesMember0\""))

      let unreduced = TLASpec(
        name: "Unreduced\(scope)",
        variables: spec.variables,
        actions: spec.actions,
        invariants: spec.invariants
      )
      #expect(try ModelChecker(compilation: try unreduced.compile(), configuration: try .init(maximumStateLimit: 100_000)).exploreGraph().states.count == 1 << scope)
    }
  }

  @Test("Parser and runtime collection specifications retain metadata, AST, states, and bounded outcomes")
  func parserRuntimeParityUsesTheSameOpaqueMemberSemantics() throws {
    let source = """
    {
      let devices = SymmetricCollectionVar<Device, Int>("devices")
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      CollectionAction("advance", on: devices) { member in
        devices[member] == 0 && devices.update(member, to: devices[member] + 1)
      }
    }
    """
    let closure = try #require(
      Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self)
    )
    let parsed = SpecParser.parseSpecClosure(closure)
    let runtime = parserParitySpec(scope: 2)
    let parsedCompilation = try parsed.compile(specificationName: "OpaqueMemberSemantics2")
    let runtimeCompilation = try runtime.compile()

    #expect(parsed.diagnostics.isEmpty)
    #expect(parsed.symmetricCollections.map(\.metadata)
      == runtime.symmetricCollections.map(\.metadata))
    #expect(parsedCompilation.description == runtimeCompilation.description)
    let parsedInitialStates = try CompiledRuntime(compilation: parsedCompilation).initialStates()
      .map { try $0.projection(using: parsedCompilation.layout) }
    let runtimeInitialStates = try CompiledRuntime(compilation: runtimeCompilation).initialStates()
      .map { try $0.projection(using: runtimeCompilation.layout) }
    #expect(parsedInitialStates == runtimeInitialStates)
    #expect(try ModelChecker(compilation: parsedCompilation, configuration: try .init(maximumStateLimit: 100_000)).check().description == ModelChecker(compilation: runtimeCompilation, configuration: try .init(maximumStateLimit: 100_000)).check().description)
  }

  @Test("Every opaque member identity misuse family produces symmetry guidance")
  func everyIdentityMisuseIsDiagnosed() throws {
    let cases = [
      "member == member",
      "member < member",
      "String(describing: member)",
      "\"\\(member)\"",
      "StateExpr.set([member])",
      "StateExpr.tuple([member])",
      "StateExpr.record([\"member\": member])",
      "StateExpr.function(domain: StateExpr.set([member]), 0)",
      "return member",
      "let capture = { member }",
      "devices.domain == StateExpr.set([])",
      "other.update(member, to: 1)"
    ]

    for body in cases {
      let parsed = try parseCollectionAction(body)
      #expect(!parsed.diagnostics.isEmpty, "Expected opaque-member diagnostic for: \(body)")
      #expect(parsed.diagnostics.contains {
        $0.message.contains("opaque") && $0.message.contains("non-symmetric collection")
      }, "Expected symmetry guidance for: \(body); got: \(parsed.diagnostics)")
    }
  }

  @Test("Bounded claims, ordinary results, lazy initial states, and Game of Life remain stable")
  func boundedAndOrdinaryBehaviorRemainStable() throws {
    let bounded = try ModelChecker(compilation: try oracleSpec(scope: 2).compile(), configuration: try .init(maximumStateLimit: 100_000)).check()
    #expect(bounded.description.contains("devices: 2 exchangeable members"))
    #expect(bounded.description.contains("does not prove larger populations"))

    let counter = Var<Int>("counter")
    let ordinary = TLASpec("Ordinary") { Variable(counter, 0) }
    let ordinaryResult = try ModelChecker(compilation: try ordinary.compile(), configuration: try .init(maximumStateLimit: 100_000)).check()
    #expect({ if case .ok = ordinaryResult { true } else { false } }())
    #expect(ordinaryResult.description == "OK — explored 1 state(s)")
    #expect(!(try ordinary.compile().renderedTLAModuleBundle().tla.contains("TLC")))
    #expect(!(try ordinary.compile().renderedTLAModuleBundle().cfg.contains("SYMMETRY")))

    let lazy = Var<Int>("lazy")
    let lazySpec = TLASpec("LazyInit") {
      Variable(from: lazy.name, StateExpr.set([1, 2, 3]))
    }
    #expect(try ModelChecker(compilation: try lazySpec.compile(), configuration: try .init(maximumStateLimit: 100_000)).exploreGraph().states.count == 3)
    #expect(try lazySpec.compile().renderedTLAModuleBundle().tla.contains("Init == lazy \\in {1, 2, 3}"))

    #expect(try ModelChecker(compilation: try Example.gameOfLife.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10)).exploreGraph().states.count == 2)
    let gameOfLifeCFG = try Example.gameOfLife.spec.compile().renderedTLAModuleBundle().cfg
    #expect(gameOfLifeCFG.contains("SPECIFICATION Spec"))
    #expect(gameOfLifeCFG.contains("INVARIANT TypeOK"))
    #expect(!gameOfLifeCFG.contains("SYMMETRY"))
  }

  private func oracleSpec(scope: Int) -> TLASpec {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    return TLASpec("SymmetricOracle\(scope)") {
      SymmetricCollection(devices, verificationScope: scope, initial: 0)
      CollectionAction("advance", on: devices) { member in
        devices[member] == 0 && devices.update(member, to: 1)
      }
      Invariant("ValidPhase") { devices.allSatisfy { $0 == 0 || $0 == 1 } }
    }
  }

  private func parserParitySpec(scope: Int) -> TLASpec {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    return TLASpec("OpaqueMemberSemantics\(scope)") {
      SymmetricCollection(devices, verificationScope: scope, initial: 0)
      CollectionAction("advance", on: devices) { member in
        devices[member] == 0 && devices.update(member, to: devices[member] + 1)
      }
    }
  }

  private func parseCollectionAction(_ body: String) throws -> SpecParser.ParsedSpecComponents {
    let source = """
    {
      let devices = SymmetricCollectionVar<Device, Int>("devices")
      let other = SymmetricCollectionVar<Device, Int>("other")
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      SymmetricCollection(other, verificationScope: 2, initial: 0)
      CollectionAction("invalid", on: devices) { member in
        \(body)
      }
    }
    """
    let closure = try #require(
      Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self)
    )
    return SpecParser.parseSpecClosure(closure)
  }

}
