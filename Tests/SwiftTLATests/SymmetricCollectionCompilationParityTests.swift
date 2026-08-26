import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing

@Suite(.serialized)
struct SymmetricCollectionCompilationParityTests {
  private struct Device: Identifiable {
    let id: Int
  }

  @Test("Symmetric scopes two through four retain model-value orbit counts")
  func scopesRetainModelValueOrbitCounts() throws {
    for scope in 2...4 {
      let spec = oracleSpec(scope: scope)
      let compilation = try spec.compile()
      let configuration = try FiniteExplorationConfiguration(maximumStateLimit: 100_000)
      let reduced = try ModelChecker(
        compilation: compilation,
        configuration: configuration,
        usesSymmetryReduction: true
      ).explore()

      #expect(reduced.graph.states.count == scope + 1)
      #expect(reduced.result.boundedScopes == [
        SymmetricCollectionScope(collectionName: "devices", verificationScope: scope)
      ])
      let bundle = compilation.renderedTLAModuleBundle()
      #expect(bundle.tla.contains("DevicesKeys == {DevicesMember0"))
      #expect(bundle.cfg.contains("CONSTANT DevicesMember\(scope - 1) = DevicesMember\(scope - 1)"))
      #expect(bundle.cfg.contains("SYMMETRY SymmDevices"))
      #expect(bundle.tla.contains("\"DevicesMember0\"") == false)

      let rawGraph = try ModelChecker(
        compilation: compilation,
        configuration: configuration,
        usesSymmetryReduction: false
      ).exploreGraph()
      #expect(rawGraph.states.count == 1 << scope)
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

}
