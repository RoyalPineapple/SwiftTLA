import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct ImportedFormalModuleGeneratedModel {
  static var spec: TLASpec {
    #spec("ImportedFormalModuleGeneratedModel") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2))
      Algorithm("ImportedFormalModuleGeneratedModel") {
        let value = SharedVar(initial: 0)
        Do("keep") { Assign(value, to: value.expr) }
      }
    }
  }
}

@TLAModel
private struct InstancedFormalModuleGeneratedModel {
  static var spec: TLASpec {
    #spec("InstancedFormalModuleGeneratedModel") {
      Instance("Sequences", of: ZSequences.module)
      Algorithm("InstancedFormalModuleGeneratedModel") {
        let value = SharedVar(initial: 0)
        Do("keep") { Assign(value, to: value.expr) }
      }
    }
  }
}

@Suite("TLA+ module bundles")
struct TLAModuleBundleTests {
  @Test("a bundle rejects an unresolved nonstandard import before tools run")
  func rejectsMissingLinkDependency() {
    let bundle = TLAModuleBundle(root: .init(
      name: "Consumer",
      tla: "---- MODULE Consumer ----\nEXTENDS Integers, MissingModule\n====\n"
    ))

    #expect(throws: TLAModuleBundleLinkError.missingModule(
      module: "MissingModule", importedBy: "Consumer", line: 2
    )) {
      try bundle.validateLink()
    }
  }

  @Test("a bundle checks every module on an EXTENDS line")
  func rejectsLaterMissingExtendDependency() {
    let bundle = TLAModuleBundle(
      root: .init(
        name: "Consumer",
        tla: "---- MODULE Consumer ----\nEXTENDS Integers, Present, MissingModule\n====\n"
      ),
      imports: [
        .init(name: "Present", tla: "---- MODULE Present ----\n====\n")
      ]
    )

    #expect(throws: TLAModuleBundleLinkError.missingModule(
      module: "MissingModule", importedBy: "Consumer", line: 2
    )) {
      try bundle.validateLink()
    }
  }

  @Test("a bundle accepts transitive source dependencies when all are present")
  func acceptsCompleteLinkDependencyClosure() throws {
    let bundle = TLAModuleBundle(
      root: .init(name: "Consumer", tla: "---- MODULE Consumer ----\nC == INSTANCE Support\n====\n"),
      imports: [
        .init(name: "Support", tla: "---- MODULE Support ----\nEXTENDS Dependency\n====\n"),
        .init(name: "Dependency", tla: "---- MODULE Dependency ----\nEXTENDS Integers\n====\n")
      ]
    )

    try bundle.validateLink()
  }

  @Test("a bundle rejects cyclic nonstandard module dependencies")
  func rejectsCyclicLinkDependency() {
    let bundle = TLAModuleBundle(
      root: .init(name: "Root", tla: "---- MODULE Root ----\nEXTENDS Support\n====\n"),
      imports: [
        .init(name: "Support", tla: "---- MODULE Support ----\nEXTENDS Root\n====\n")
      ]
    )

    #expect(throws: TLAModuleBundleLinkError.cyclicModule(
      module: "Root", path: ["Root", "Support", "Root"]
    )) {
      try bundle.validateLink()
    }
  }

  @Test("a generated model preserves its imported module")
  func generatedModelRetainsImportedModule() {
    ImportedFormalModuleGeneratedModel._checkParserTree()
    #expect(ImportedFormalModuleGeneratedModel.spec.imports.map { $0.name } == ["ZSequences"])
    #expect(ImportedFormalModuleGeneratedModel.spec.importConfigurations == [
      ZSequences.boundedNaturalNumbers(0...2)
    ])
  }

  @Test("the parser records imports for builder fidelity")
  func parserRetainsImportedModule() {
    let source = "{ Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2)) }"
    let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
    let parsed = SpecParser.parseSpecClosure(closure)
    let runtime = TLASpec("Imported") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2))
    }
    let parserTree = canonicalTestSpec(
      variables: [], actions: [], invariants: [], imports: parsed.imports,
      importConfigurations: parsed.importConfigurations
    )
    let runtimeTree = canonicalTestSpec(
      variables: [], actions: [], invariants: [], imports: runtime.imports.map(\.name),
      importConfigurations: runtime.importConfigurations
    )

    #expect(_tlaAlphaEquivalent(parserTree, runtimeTree))
  }

  @Test("the parser retains formal module parameters for builder fidelity")
  func parserRetainsFormalModuleParameters() {
    let source = "{ Parameter(\"Base\") }"
    let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
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
    #expect(_tlaAlphaEquivalent(parserTree, runtimeTree))
  }

  @Test("a generated model preserves a named module instance")
  func generatedModelRetainsNamedModuleInstance() {
    InstancedFormalModuleGeneratedModel._checkParserTree()
    #expect(InstancedFormalModuleGeneratedModel.spec.moduleInstances.map(\.name) == ["Sequences"])
    #expect(InstancedFormalModuleGeneratedModel.spec.moduleInstances.map { $0.module.name } == ["ZSequences"])
  }

  @Test("the parser preserves qualified ZSequences calls")
  func parserRetainsQualifiedModuleCalls() {
    let source = "ZSequences.rotation(of: corpus, leftBy: 1)"
    let expression = Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!
    let parsed = SpecParser.decodeStateExpr(expression)

    #expect(parsed == .recursiveCall("Rotation", [.variable("corpus"), .int(1)]))
  }

  @Test("ZSequences keeps the upstream operators in its own importable module")
  func zeroBasedSequenceModuleIsExecutable() throws {
    let sequence = ZeroBasedSequence<Int>.literal(3, 1, 2)
    let rotated = ZSequences.rotation(of: sequence, leftBy: Expr(.int(1)))
    let result = try rotated.raw.evaluate(
      in: [:], recursiveFuncs: ZSequences.module.resolvedRecursiveFuncs
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

    #expect(consumer.tlaModule.contains("EXTENDS Integers, FiniteSets, Sequences, ZSequences"))
    #expect(consumer.tlaBundle.imports.map { $0.name } == ["ZSequences"])
    #expect(consumer.tlaBundle.imports[0].tla.contains("Rotation(sequence, shift) =="))
    #expect(!consumer.tlaBundle.imports[0].tla.contains("VARIABLES"))
    #expect(!consumer.tlaBundle.imports[0].tla.contains("Spec =="))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try consumer.tlaBundle.write(to: directory)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("UsesZSequences.tla").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ZSequences.tla").path))
    let check = try ModelChecker(spec: consumer).check()
    guard case .ok = check.underlyingOutcome else {
      Issue.record("The imported ZSequences operators did not evaluate successfully.")
      return
    }
  }

  @Test("an imported module keeps its source boundary while receiving a typed TLC replacement")
  func importedModuleUsesScopedFiniteReplacement() throws {
    let consumer = TLASpec("BoundedZSequences") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2))
    }

    #expect(consumer.tlaModule.contains("ZSequencesNat == 0..2"))
    #expect(consumer.tlaCfg.contains("CONSTANT Nat <- [ZSequences]ZSequencesNat"))
    #expect(consumer.tlaBundle.imports.map(\.name) == ["ZSequences"])
    #expect(!consumer.tlaBundle.root.tla.contains("ZSeq(elements) =="))

    let sequences = try StateExpr.recursiveCall("ZSeq", [
      .setLiteral([.int(0), .int(1)])
    ]).evaluate(in: [:], recursiveFuncs: consumer.resolvedRecursiveFuncs)
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
    #expect(computeInitialStates(initialized).count == 7)
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

    #expect(consumer.tlaModule.contains("EXTENDS Integers, FiniteSets, Sequences, FormalArithmetic"))
    #expect(!consumer.tlaModule.contains("Twice(value) =="))
    #expect(consumer.tlaBundle.imports.map { $0.name } == ["FormalArithmetic"])
    #expect(consumer.tlaBundle.imports.first?.tla.contains("Twice(value) ==") == true)
    let check = try ModelChecker(spec: consumer).check()
    guard case .ok = check.underlyingOutcome else {
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

    #expect(consumer.tlaModule.contains("Math == INSTANCE InstanceArithmetic"))
    #expect(consumer.tlaModule.contains("ValueIsTwoTimesOne == (Math!Twice(value) = 2)"))
    #expect(!consumer.tlaModule.contains("EXTENDS Integers, FiniteSets, Sequences, InstanceArithmetic"))
    #expect(consumer.tlaBundle.imports.map(\.name) == ["InstanceArithmetic"])
    #expect(consumer.tlaBundle.imports[0].tla.contains("Twice(value) =="))

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try consumer.tlaBundle.write(to: directory)
    #expect(FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("InstanceArithmetic.tla").path
    ))
    let result = try ModelChecker(spec: consumer).check()
    guard case .ok = result.underlyingOutcome else {
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

    #expect(consumer.resolvedRecursiveFuncs.map(\.name) == ["Math!CountDown"])
    #expect(consumer.resolvedRecursiveFuncs[0].body.description.contains("Math!CountDown"))
    let result = try ModelChecker(spec: consumer).check()
    guard case .ok = result.underlyingOutcome else {
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

    #expect(consumer.tlaModule.contains("Math == INSTANCE ParameterizedArithmetic WITH Base <- 2"))
    #expect(consumer.tlaBundle.imports[0].tla.contains("CONSTANTS Base"))
    #expect(!consumer.tlaBundle.imports[0].tla.contains("ASSUME Base"))
    let result = try ModelChecker(spec: consumer).check()
    guard case .ok = result.underlyingOutcome else {
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

    #expect(consumer.tlaModule.contains("Math == INSTANCE VariableParameterizedArithmetic WITH Base <- value"))
    #expect(consumer.tlaBundle.imports[0].tla.contains("VARIABLES Base"))
    let result = try ModelChecker(spec: consumer).check()
    guard case .ok = result.underlyingOutcome else {
      Issue.record("The checker did not substitute the state parameter.")
      return
    }
  }

}
