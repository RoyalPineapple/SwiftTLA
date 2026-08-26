import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import SwiftTLAMacros

private func parseClosure(_ source: String) throws -> ClosureExprSyntax {
  try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
}

private func parseExpression(_ source: String) throws -> ExprSyntax {
  try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
}

@TLAModel
private struct ImportedFormalModuleGeneratedModel {
  static var spec: TLASpec {
    #spec("ImportedFormalModuleGeneratedModel") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2))
      Algorithm("ImportedFormalModuleGeneratedModel", scoped: { scope in
        let value = scope.sharedVar("value", initial: 0)
        Do(TestControlLabel.keep) { Assign(value, to: value.expr) }
      })
    }
  }
}

@TLAModel
private struct InstancedFormalModuleGeneratedModel {
  static var spec: TLASpec {
    #spec("InstancedFormalModuleGeneratedModel") {
      Instance("Folding", of: Folds.module)
      Algorithm("InstancedFormalModuleGeneratedModel", scoped: { scope in
        let value = scope.sharedVar("value", initial: 0)
        Do(TestControlLabel.keep) { Assign(value, to: value.expr) }
      })
    }
  }
}

@Suite("TLA+ module bundles")
struct TLAModuleBundleTests {
  @Test("a generated model preserves its imported module")
  func generatedModelRetainsImportedModule() throws {
    let bundle = try ImportedFormalModuleGeneratedModel.spec.compile().renderedTLAModuleBundle()

    #expect(bundle.imports.map(\.name) == ["ZSequences"])
    #expect(try #require(bundle.root.cfg).contains("CONSTANT Nat <- [ZSequences]ZSequencesNat"))
  }

  @Test("the parser records imports for builder fidelity")
  func parserRetainsImportedModule() throws {
    let source = "{ Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2)) }"
    let closure = try parseClosure(source)
    let parsed = SpecParser.parseSpecClosure(closure)
    let runtime = TLASpec("Imported") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2))
    }
    let parserTree = canonicalTestSpec(
      variables: [], actions: [], invariants: [], imports: parsed.imports,
      importConfigurations: parsed.importConfigurations
    )
    let runtimeTree = canonicalTestSpec(
      variables: [], actions: [], invariants: [], imports: runtime.imports,
      importConfigurations: runtime.importConfigurations
    )

    #expect(try parserTree.compile().identity == runtimeTree.compile().identity)
  }

  @Test("the parser retains formal module parameters for builder fidelity")
  func parserRetainsFormalModuleParameters() throws {
    let source = "{ Parameter(\"Base\") }"
    let closure = try parseClosure(source)
    let parsed = SpecParser.parseSpecClosure(closure)
    let runtime = TLASpec("Parameterized") {
      Parameter("Base")
    }
    let parserTree = canonicalTestSpec(
      variables: [], actions: [], invariants: [], formalParameters: parsed.formalParameters
    )
    let runtimeTree = canonicalTestSpec(
      variables: [], actions: [], invariants: [], formalParameters: runtime.formalParameters
    )

    #expect(parsed.diagnostics.isEmpty)
    #expect(try parserTree.compile().identity == runtimeTree.compile().identity)
  }

  @Test("a generated model preserves a named module instance")
  func generatedModelRetainsNamedModuleInstance() throws {
    let bundle = try InstancedFormalModuleGeneratedModel.spec.compile().renderedTLAModuleBundle()

    #expect(bundle.imports.map(\.name) == ["Folds"])
    #expect(bundle.root.tla.contains("Folding == INSTANCE Folds"))
  }

  @Test("the parser preserves qualified ZSequences calls")
  func parserRetainsQualifiedModuleCalls() throws {
    let source = "ZSequences.rotation(of: corpus, leftBy: 1)"
    let expression = try parseExpression(source)
    let parsed = SpecParser.decodeStateExpr(expression)

    #expect(parsed == .recursiveCall("Rotation", [.variable("corpus"), .int(1)]))
  }

  @Test("ZSequences keeps the upstream operators in its own importable module")
  func zeroBasedSequenceModuleIsExecutable() throws {
    let sequence = ZeroBasedSequence<Int>.literal(3, 1, 2)
    let rotated = ZSequences.rotation(of: sequence, leftBy: Expr(.int(1)))
    let configured = TLASpec("ConfiguredZSequences") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2))
    }
    let result = try compiledValue(
      rotated.raw,
      recursiveFunctions: try FormalModuleClosure.resolve(root: configured)
        .linkedOperators.recursiveFunctions
    )
    #expect(result == .function([
      .int(0): .int(1), .int(1): .int(2), .int(2): .int(3)
    ]))

    let corpus = Var<ZeroBasedSequence<Int>>("corpus", .init())
    let consumer = TLASpec("UsesZSequences") {
      Import(ZSequences.module)
      Variable(corpus, ZeroBasedSequence<Int>())
      Invariant("RotationOrdering") {
        ZSequences.lexicographicallyPrecedesOrEquals(
          ZSequences.rotation(of: Expr(corpus.stateExpr), leftBy: Expr(.int(0))),
          ZSequences.rotation(of: Expr(corpus.stateExpr), leftBy: Expr(.int(0)))
        )
      }
    }

    #expect(try consumer.compile().renderedTLAModuleBundle().tla.contains("EXTENDS Integers, FiniteSets, Sequences, ZSequences"))
    let bundle = try consumer.compile().renderedTLAModuleBundle()
    #expect(bundle.imports.map { $0.name } == ["ZSequences"])
    #expect(bundle.imports[0].tla.contains("Rotation(sequence, shift) =="))
    #expect(!bundle.imports[0].tla.contains("VARIABLES"))
    #expect(!bundle.imports[0].tla.contains("Spec =="))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try consumer.compile().materializeModuleBundle(to: directory)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("UsesZSequences.tla").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ZSequences.tla").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("bundle-manifest.json").path))
    let check = try ModelChecker(compilation: try consumer.compile(), configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).check()
    guard case .ok = check else {
      Issue.record("The imported ZSequences operators did not evaluate successfully.")
      return
    }
  }

  @Test("an imported module keeps its source boundary while receiving a typed TLC replacement")
  func importedModuleUsesScopedFiniteReplacement() throws {
    let consumer = TLASpec("BoundedZSequences") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2))
    }

    #expect(try consumer.compile().renderedTLAModuleBundle().tla.contains("ZSequencesNat == 0..2"))
    #expect(try consumer.compile().renderedTLAModuleBundle().cfg.contains("CONSTANT Nat <- [ZSequences]ZSequencesNat"))
    let bundle = try consumer.compile().renderedTLAModuleBundle()
    #expect(bundle.imports.map(\.name) == ["ZSequences"])
    #expect(!bundle.root.tla.contains("ZSeq(elements) =="))

    let sequences = try compiledValue(
      .recursiveCall("ZSeq", [.setLiteral([.int(0), .int(1)])]),
      recursiveFunctions: try FormalModuleClosure.resolve(root: consumer)
        .linkedOperators.recursiveFunctions
    )
    guard case .set(let values) = sequences else {
      Issue.record("The bounded ZSeq result was not a set.")
      return
    }
    #expect(values.count == 7)

    let corpus = Var<ZeroBasedSequence<Int>>("corpus", .init())
    let initialized = TLASpec("InitializedZSequences") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2))
      Variable(from: corpus.name, ZSequences.sequences(over: SetExpr<Int>.literal(0, 1)).raw)
    }
    let compilation = try initialized.compile()
    #expect(try CompiledRuntime(compilation: compilation).initialStates().count == 7)
  }

  @Test("an import remains a source dependency and resolves its operators at runtime")
  func importedOperatorIsBundledAndExecutable() throws {
    let arithmetic = TLASpec("FormalArithmetic") {
      DefineRecursive("Twice", params: ["value"]) {
        StateExpr.variable("value") * 2
      }
    }
    let value = Var<Int>("value", 1)
    let consumer = TLASpec("UsesFormalArithmetic") {
      Import(arithmetic)
      Variable(value, 1)
      Invariant("TwiceIsTwo") {
        StateExpr.recursiveCall("Twice", [value.stateExpr]) == 2
      }
    }

    #expect(try consumer.compile().renderedTLAModuleBundle().tla.contains("EXTENDS Integers, FiniteSets, Sequences, FormalArithmetic"))
    #expect(!(try consumer.compile().renderedTLAModuleBundle().tla.contains("Twice(value) ==")))
    let bundle = try consumer.compile().renderedTLAModuleBundle()
    #expect(bundle.imports.map { $0.name } == ["FormalArithmetic"])
    #expect(bundle.imports.first?.tla.contains("Twice(value) ==") == true)
    let check = try ModelChecker(compilation: try consumer.compile(), configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).check()
    guard case .ok = check else {
      Issue.record("The imported operator did not evaluate successfully.")
      return
    }
  }

  @Test("a named instance stays a separate source module")
  func namedModuleInstanceIsBundled() throws {
    let arithmetic = TLASpec("InstanceArithmetic") {
      DefineRecursive("Twice", params: ["value"]) {
        StateExpr.variable("value") * 2
      }
    }
    let value = Var<Int>("value", 1)
    let consumer = TLASpec("UsesInstanceArithmetic") {
      let math = Instance("Math", of: arithmetic)
      math
      Variable(value, 1)
      Action("Stay") { value.stateExpr == 1 }
      Invariant("ValueIsTwoTimesOne") { math.call("Twice", value.stateExpr) == 2 }
    }

    #expect(try consumer.compile().renderedTLAModuleBundle().tla.contains("Math == INSTANCE InstanceArithmetic"))
    #expect(try consumer.compile().renderedTLAModuleBundle().tla.contains("ValueIsTwoTimesOne == (Math!Twice(value) = 2)"))
    #expect(!(try consumer.compile().renderedTLAModuleBundle().tla.contains("EXTENDS Integers, FiniteSets, Sequences, InstanceArithmetic")))
    let bundle = try consumer.compile().renderedTLAModuleBundle()
    #expect(bundle.imports.map(\.name) == ["InstanceArithmetic"])
    #expect(bundle.imports[0].tla.contains("Twice(value) =="))

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try consumer.compile().materializeModuleBundle(to: directory)
    #expect(FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("InstanceArithmetic.tla").path
    ))
    #expect(FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("bundle-manifest.json").path
    ))
    let result = try ModelChecker(compilation: try consumer.compile(), configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).check()
    guard case .ok = result else {
      Issue.record("The checker did not resolve the qualified module operator.")
      return
    }
  }

  @Test("an instance keeps recursive calls inside its namespace")
  func namedModuleInstanceKeepsRecursiveCallsQualified() throws {
    let counting = TLASpec("InstanceCounting") {
      DefineRecursive("CountDown", params: ["number"]) {
        let number = StateExpr.variable("number")
        return .ifThenElse(
          .equal(number, .int(0)),
          .int(0),
          .add(.int(1), .recursiveCall("CountDown", [.subtract(number, .int(1))]))
        )
      }
    }
    let value = Var<Int>("value", 3)
    let consumer = TLASpec("UsesInstanceCounting") {
      let math = Instance("Math", of: counting)
      math
      Variable(value, 3)
      Action("Stay") { value.stateExpr == 3 }
      Invariant("CountsDown") { math.call("CountDown", value.stateExpr) == 3 }
    }

    let resolved = try FormalModuleClosure.resolve(root: consumer)
      .linkedOperators.recursiveFunctions
    #expect(resolved.map(\.name) == ["Math!CountDown"])
    #expect(resolved[0].body.description.contains("Math!CountDown"))
    let result = try ModelChecker(compilation: try consumer.compile(), configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).check()
    guard case .ok = result else {
      Issue.record("The checker did not resolve recursive instance calls.")
      return
    }
  }

  @Test("an instance applies its declared module parameters")
  func namedModuleInstanceAppliesArguments() throws {
    let arithmetic = TLASpec("ParameterizedArithmetic") {
      Parameter("Base")
      DefineRecursive("AddBase", params: ["number"]) {
        StateExpr.variable("number") + StateExpr.variable("Base")
      }
    }
    let value = Var<Int>("value", 3)
    let consumer = TLASpec("UsesParameterizedArithmetic") {
      let math = Instance("Math", of: arithmetic, with: [ModuleArgument("Base", value: 2)])
      math
      Variable(value, 3)
      Action("Stay") { value.stateExpr == 3 }
      Invariant("AddsBase") { math.call("AddBase", value.stateExpr) == 5 }
    }

    #expect(try consumer.compile().renderedTLAModuleBundle().tla.contains("Math == INSTANCE ParameterizedArithmetic WITH Base <- 2"))
    let bundle = try consumer.compile().renderedTLAModuleBundle()
    #expect(bundle.imports[0].tla.contains("CONSTANTS Base"))
    #expect(!bundle.imports[0].tla.contains("ASSUME Base"))
    let result = try ModelChecker(compilation: try consumer.compile(), configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).check()
    guard case .ok = result else {
      Issue.record("The checker did not apply the module argument.")
      return
    }
  }

  @Test("an instance can bind a state-level module parameter")
  func namedModuleInstanceAppliesVariableArgument() throws {
    let arithmetic = TLASpec("VariableParameterizedArithmetic") {
      Parameter("Base", kind: .variable)
      DefineRecursive("AddBase", params: ["number"]) {
        StateExpr.variable("number") + StateExpr.variable("Base")
      }
    }
    let value = Var<Int>("value", 3)
    let consumer = TLASpec("UsesVariableParameterizedArithmetic") {
      let math = Instance(
        "Math", of: arithmetic,
        with: [ModuleArgument("Base", value: value.stateExpr)]
      )
      math
      Variable(value, 3)
      Action("Stay") { value.stateExpr == 3 }
      Invariant("AddsItsStateParameter") { math.call("AddBase", value.stateExpr) == 6 }
    }

    #expect(try consumer.compile().renderedTLAModuleBundle().tla.contains("Math == INSTANCE VariableParameterizedArithmetic WITH Base <- value"))
    #expect(try consumer.compile().renderedTLAModuleBundle().imports[0].tla.contains("VARIABLES Base"))
    let result = try ModelChecker(compilation: try consumer.compile(), configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).check()
    guard case .ok = result else {
      Issue.record("The checker did not substitute the state parameter.")
      return
    }
  }

}
