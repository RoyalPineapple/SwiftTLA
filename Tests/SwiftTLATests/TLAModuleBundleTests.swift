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
  enum Step: String, CaseIterable { case keep }

  static var spec: TLASpec {
    #spec("ImportedFormalModuleGeneratedModel") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2))
      Algorithm("ImportedFormalModuleGeneratedModel", scoped: { scope in
        let value = scope.sharedVar("value", initial: 0)
        Do(Step.keep) { Assign(value, to: value.expr) }
      })
    }
  }
}

@TLAModel
private struct InstancedFormalModuleGeneratedModel {
  enum Step: String, CaseIterable { case keep }

  static var spec: TLASpec {
    #spec("InstancedFormalModuleGeneratedModel") {
      Instance("Folding", of: Folds.module)
      Algorithm("InstancedFormalModuleGeneratedModel", scoped: { scope in
        let value = scope.sharedVar("value", initial: 0)
        Do(Step.keep) { Assign(value, to: value.expr) }
      })
    }
  }
}

@Suite("TLA+ module bundles")
struct TLAModuleBundleTests {
  @Test("an external bundle requires a rooted dependency graph")
  func externalBundleRequiresRootedDependencies() {
    let root = TLAModuleFile(name: "Root", tla: "---- MODULE Root ----\n====\n")
    let imported = TLAModuleFile(name: "Imported", tla: "---- MODULE Imported ----\n====\n")
    let disconnected = TLAModuleBundle.external(root: root, imports: [imported])

    #expect(throws: TLAModuleBundleIntegrityError.unreachableModule(
      module: "Imported",
      root: "Root"
    )) {
      try disconnected.validateDeclaredClosure()
    }

    let connected = TLAModuleBundle.external(
      root: root,
      imports: [imported],
      dependencies: [.init(
        importingModule: "Root",
        importedModule: "Imported",
        structuralPath: ["Root", "Imported"]
      )]
    )
    #expect(throws: Never.self) {
      try connected.validateDeclaredClosure()
    }
  }

  @Test("a compiled bundle rejects an undeclared source file")
  func compiledBundleRejectsUndeclaredSource() throws {
    let compiled = try TLASpec("Root") {}.compile().renderedTLAModuleBundle()
    let bundle = TLAModuleBundle(
      root: compiled.root,
      imports: compiled.imports + [
        TLAModuleFile(name: "Unexpected", tla: "---- MODULE Unexpected ----\n====\n")
      ],
      provenance: compiled.provenance
    )

    #expect(throws: TLAModuleBundleIntegrityError.undeclaredModule(
      module: "Unexpected",
      root: "Root"
    )) {
      try bundle.validateDeclaredClosure()
    }
  }

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
      Algorithm("ConfiguredZSequences", scoped: { scope in
        let rotatedState: SharedVariable<ZeroBasedSequence<Int>> = scope.sharedVar(
          "rotated",
          initial: rotated
        )
        Do(TestControlLabel.keep) { Assign(rotatedState, to: rotatedState.expr) }
      })
    }
    let compilation = try configured.compile()
    let initial = try firstCompiledState(in: compilation)
    #expect(try renderedValue(named: "rotated", in: initial, compilation: compilation) == .function([
      .int(0): .int(1), .int(1): .int(2), .int(2): .int(3)
    ]))

    let corpus = Var<ZeroBasedSequence<Int>>("corpus", .init())
    let consumer = TLASpec("UsesZSequences") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2))
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
    let importedModule = try #require(bundle.imports.first)
    #expect(importedModule.tla.contains("Rotation("))
    #expect(importedModule.tla.contains("VARIABLES") == false)
    #expect(importedModule.tla.contains("Spec ==") == false)
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
      Variable(corpus, in: ZSequences.sequences(over: SetExpr<Int>.literal(0, 1)))
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
    #expect(bundle.imports.first?.tla.contains("Twice(") == true)
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
    let importedModule = try #require(bundle.imports.first)
    #expect(importedModule.tla.contains("Twice(value) =="))

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
    #expect(try consumer.compile().renderedTLAModuleBundle().tla.contains("Math\u{21}CountDown"))
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
    let importedModule = try #require(bundle.imports.first)
    #expect(importedModule.tla.contains("CONSTANTS Base"))
    #expect(importedModule.tla.contains("ASSUME Base") == false)
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
