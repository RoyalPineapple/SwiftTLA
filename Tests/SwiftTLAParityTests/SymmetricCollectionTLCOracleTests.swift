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
      let graph = try ModelChecker(spec: spec).exploreGraph()
      let result = try ModelChecker(spec: spec).check()

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
      #expect(try ModelChecker(spec: unreduced).exploreGraph().states.count == 1 << scope)
    }
  }

  @Test("The configured TLC command checks symmetric scopes and rejects quoted members")
  func symmetricCollectionsCommandExecutesTLC() throws {
    let root = packageRoot()
    let jar = ProcessInfo.processInfo.environment["TLA_TOOLS_JAR"]
      ?? root.appendingPathComponent(".build/tla-tools/tla2tools.jar").path
    let configuredJava = [
      ProcessInfo.processInfo.environment["TLC_JAVA"],
      ProcessInfo.processInfo.environment["JAVA_HOME"].map { "\($0)/bin/java" },
      "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin/java",
      "/usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin/java"
    ].compactMap { $0 }.contains { FileManager.default.isExecutableFile(atPath: $0) }
    let executable = [
      testProductExecutable(named: "tlc-validate"),
      root.appendingPathComponent(".build/out/Products/Debug/tlc-validate").path,
      root.appendingPathComponent(".build/debug/tlc-validate").path
    ].compactMap { $0 }.first(where: FileManager.default.isExecutableFile(atPath:))
    guard FileManager.default.fileExists(atPath: jar), configuredJava, let executable else { return }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = ["symmetric-collections"]
    process.currentDirectoryURL = root
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    guard process.terminationStatus == 0 else {
      Issue.record("TLC command failed:\n\(output)")
      return
    }
    for (scope, states) in zip(2...4, 3...5) {
      #expect(output.contains("symmetric scope \(scope) — Swift/TLC \(states) orbit states"))
    }
    #expect(output.contains("quoted-string symmetry control rejected by TLC"))
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
    let parsedSpec = TLASpec(
      name: "ParserParity2",
      variables: parsed.variables.map { NamedVar(name: $0.name, initial: $0.initial, initialSet: $0.initialSet) },
      actions: parsed.actions.map { NamedAction(name: $0.name, body: $0.body) },
      invariants: parsed.invariants.map { NamedInvariant(name: $0.name, body: $0.body) },
      symmetricCollections: parsed.symmetricCollections.map(\.declaration)
    )

    #expect(parsed.diagnostics.isEmpty)
    #expect(parsed.symmetricCollections.map { $0.declaration.metadata }
      == runtime.symmetricCollections.map(\.metadata))
    #expect(normalizedActions(parsed.actions.map { NamedAction(name: $0.name, body: $0.body) })
      == normalizedActions(runtime.actions))
    #expect(try parsedSpec.compile().initialStateProjections() == runtime.compile().initialStateProjections())
    #expect(try ModelChecker(spec: parsedSpec).check().description == ModelChecker(spec: runtime).check().description)
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
    let bounded = try ModelChecker(spec: oracleSpec(scope: 2)).check()
    #expect(bounded.description.contains("devices: 2 exchangeable members"))
    #expect(bounded.description.contains("does not prove larger populations"))

    let counter = Var<Int>("counter")
    let ordinary = TLASpec("Ordinary") { Variable(counter, 0) }
    let ordinaryResult = try ModelChecker(spec: ordinary).check()
    #expect({ if case .ok = ordinaryResult { true } else { false } }())
    #expect(ordinaryResult.description == "OK — explored 1 state(s)")
    #expect(!(try ordinary.compile().renderedTLAModuleBundle().tla.contains("TLC")))
    #expect(!(try ordinary.compile().renderedTLAModuleBundle().cfg.contains("SYMMETRY")))

    let lazy = Var<Int>("lazy")
    let lazySpec = TLASpec("LazyInit") {
      Variable(from: lazy.name, StateExpr.set([1, 2, 3]))
    }
    #expect(try ModelChecker(spec: lazySpec).exploreGraph().states.count == 3)
    #expect(try lazySpec.compile().renderedTLAModuleBundle().tla.contains("Init == lazy \\in {1, 2, 3}"))

    #expect(try ModelChecker(spec: Example.gameOfLife.spec, maxStates: 10).exploreGraph().states.count == 2)
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
    return TLASpec("ParserParity\(scope)") {
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

  private func testProductExecutable(named name: String) -> String? {
    Bundle.allBundles
      .first { $0.bundleURL.lastPathComponent == "SwiftTLATests.xctest" }
      .map { $0.bundleURL.deletingLastPathComponent().appendingPathComponent(name).path }
  }
