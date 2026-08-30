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
      let spec = symmetricSpec(scope: scope)
      let compilation = try spec.compile()
      let reducedConfiguration = try FiniteExplorationConfiguration(
        maximumStateLimit: 100_000,
        symmetryReduction: .enabled(maximumPermutationCount: 100_000))
      let reduced = try ModelChecker(
        compilation: compilation,
        configuration: reducedConfiguration
      ).explore()

      #expect(reduced.graph.states.count == scope + 1)
      #expect({ if case .ok = reduced.result { true } else { false } }())
      let bundle = compilation.renderedTLAModuleBundle()
      #expect(bundle.tla.contains("DevicesKeys == {DevicesMember0"))
      #expect(bundle.cfg.contains("CONSTANT DevicesMember\(scope - 1) = DevicesMember\(scope - 1)"))
      #expect(bundle.cfg.contains("SYMMETRY SymmDevices"))
      #expect(bundle.tla.contains("\"DevicesMember0\"") == false)

      let rawGraph = try ModelChecker(
        compilation: compilation,
        configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100_000, symmetryReduction: .disabled)
      ).exploreGraph()
      #expect(rawGraph.states.count == 1 << scope)
    }
  }

  @Test("Parser and result-builder collection specifications retain metadata, AST, states, and checking outcomes")
  func parserAndResultBuilderUseTheSameOpaqueMemberSemantics() throws {
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
    let built = parserParitySpec(scope: 2)
    let parsedCompilation = try parsed.compile(specificationName: "OpaqueMemberSemantics2")
    let builtCompilation = try built.compile()

    #expect(parsed.diagnostics.isEmpty)
    #expect(parsed.symmetricCollections.map(\.metadata)
      == built.symmetricCollections.map(\.metadata))
    #expect(parsedCompilation.description == builtCompilation.description)
    let parsedInitialStates = try CompiledRuntime(compilation: parsedCompilation).initialStates()
      .map { try $0.projection(using: parsedCompilation.layout) }
    let builtInitialStates = try CompiledRuntime(compilation: builtCompilation).initialStates()
      .map { try $0.projection(using: builtCompilation.layout) }
    #expect(parsedInitialStates == builtInitialStates)
    let configuration = try FiniteExplorationConfiguration(
      maximumStateLimit: 100_000,
      symmetryReduction: .enabled(maximumPermutationCount: 100_000))
    #expect(try ModelChecker(compilation: parsedCompilation, configuration: configuration).check().description
      == ModelChecker(compilation: builtCompilation, configuration: configuration).check().description)
  }

  private func symmetricSpec(scope: Int) -> TLASpec {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    return TLASpec("SymmetricScope\(scope)") {
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
