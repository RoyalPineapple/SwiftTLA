@testable import SwiftTLAPlugin
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
    #spec("WF_ImportedFormalModuleGeneratedModel") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: 2))
      let importedFormalModuleGeneratedModel = Algorithm(label: "ImportedFormalModuleGeneratedModel", scoped: { scope in
        let value = scope.sharedVar(_name: "value", initial: 0)
        Do(Step.keep) { Assign(value, to: value.expr) }
      })
      importedFormalModuleGeneratedModel
    }
  }
}

@TLAModel
private struct InstancedFormalModuleGeneratedModel {
  enum Step: String, CaseIterable { case keep }

  static var spec: TLASpec {
    #spec("InstancedFormalModuleGeneratedModel") {
      Instance("Folding", of: Folds.module)
      let instancedFormalModuleGeneratedModel = Algorithm(label: "InstancedFormalModuleGeneratedModel", scoped: { scope in
        let value = scope.sharedVar(_name: "value", initial: 0)
        Do(Step.keep) { Assign(value, to: value.expr) }
      })
      instancedFormalModuleGeneratedModel
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
    let compiled = try TLASpec("Root") {}.compile().render().tlaBundle
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

  @Test("#spec compilation preserves source identity and legal module-file names", arguments: [
    ("ImportedFormalModuleGeneratedModel", "ImportedFormalModuleGeneratedModel"),
    ("WF_Import", "_WF_Import_1"), ("SF_Import", "_SF_Import"), ("_1", "v_1"), ("Sequences", "Sequences_1")
  ])
  func compiledSpecRetainsImportedModule(name: String, expected: String) throws {
    if name == "ImportedFormalModuleGeneratedModel" {
      #expect(try ImportedFormalModuleGeneratedModel.spec.compile().description.name == "WF_ImportedFormalModuleGeneratedModel")
      let generated = try ImportedFormalModuleGeneratedModel.render()
      #expect(generated.tlaBundle.root.name == "_WF_ImportedFormalModuleGeneratedModel")
      #expect(generated.tlaBundle.root.tla.hasPrefix("---- MODULE _WF_ImportedFormalModuleGeneratedModel ----\n"))
    }
    var source = ImportedFormalModuleGeneratedModel.spec
    source.name = name
    if name == "WF_Import" { source.imports.append(TLASpec("_WF_Import") {}) }
    let compilation = try source.compile()
    #expect(compilation.description.name == name)
    let rendered = try compilation.render()
    let imports = name == "WF_Import" ? ["ZSequences", "_WF_Import"] : ["ZSequences"]
    for bundle in [rendered.tlaBundle, try rendered.plusCalBundle()] {
      #expect(bundle.root.name == expected)
      #expect(bundle.root.tla.hasPrefix("---- MODULE \(expected) ----\n"))
      #expect(bundle.imports.map(\.name) == imports)
      #expect(try #require(bundle.root.cfg).contains("CONSTANT Nat <- [ZSequences]ZSequencesNat"))
      let extendsLine = try #require(bundle.root.tla.split(whereSeparator: \.isNewline).first { $0.hasPrefix("EXTENDS ") })
      let modules = extendsLine.dropFirst("EXTENDS ".count).split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
      #expect(modules.contains("Sequences"))
      if name == "Sequences" { #expect(!modules.contains(expected)) }
      try bundle.validateDeclaredClosure()
    }
    let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
    #expect(program.moduleName == name)
    let module = try program.renderModule()
    #expect(module.renderedModuleSource.hasPrefix("---- MODULE \(expected) ----\n"))
    #expect(try #require(try program.renderAuthoredPlusCal(declarations: module))
      .hasPrefix("---- MODULE \(expected) ----\n"))
  }

  @Test("the parser records imports for builder fidelity")
  func parserRetainsImportedModule() throws {
    let source = "{ Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: 2)) }"
    let closure = try parseClosure(source)
    let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)
    let built = TLASpec("Imported") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: 2))
    }
    let parserTree = canonicalTestSpec(
      variables: [], actions: [], invariants: [], imports: parsed.imports,
      importConfigurations: parsed.importConfigurations
    )
    let builtTree = canonicalTestSpec(
      variables: [], actions: [], invariants: [], imports: built.imports,
      importConfigurations: built.importConfigurations
    )

    #expect(try parserTree.compile().identity == builtTree.compile().identity)
  }

  @Test("the parser retains formal module parameters for builder fidelity")
  func parserRetainsFormalModuleParameters() throws {
    let source = "{ Parameter(\"Base\") }"
    let closure = try parseClosure(source)
    let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)
    let built = TLASpec("Parameterized") {
      Parameter("Base")
    }
    let parserTree = canonicalTestSpec(
      variables: [], actions: [], invariants: [], formalParameters: parsed.formalParameters
    )
    let builtTree = canonicalTestSpec(
      variables: [], actions: [], invariants: [], formalParameters: built.formalParameters
    )

    #expect(parsed.diagnostics.isEmpty)
    #expect(try parserTree.compile().identity == builtTree.compile().identity)
  }

  @Test("#spec compilation preserves a named module instance")
  func compiledSpecRetainsNamedModuleInstance() throws {
    let bundle = try InstancedFormalModuleGeneratedModel.spec.compile().render().tlaBundle

    #expect(bundle.imports.map(\.name) == ["Folds"])
    #expect(bundle.root.tla.contains("Folding == INSTANCE Folds"))
    for (name, expected) in [("Folding", "Folding"), ("TRUE", "TRUE_1"), ("FALSE", "FALSE_1"),
                             ("BOOLEAN", "BOOLEAN_1"), ("STRING", "STRING_1"),
                             ("WF_Folding", "_WF_Folding"), ("_1", "v_1")] {
      let parsed = SpecParser.parseSpecClosure(named: "NamedInstance",
        try parseClosure("{ Instance(\"\(name)\", of: Folds.module) }"))
      #expect(parsed.diagnostics.isEmpty)
      #expect(parsed.moduleInstances.map(\.name) == [name])
      var source = InstancedFormalModuleGeneratedModel.spec
      source.moduleInstances = parsed.moduleInstances
      let compilation = try source.compile()
      #expect(compilation.layout.moduleInstances.map(\.namespace) == [name])
      let rendered = try compilation.render()
      for bundle in [rendered.tlaBundle, try rendered.plusCalBundle()] {
        #expect(bundle.root.tla.contains("\(expected) == INSTANCE Folds"))
      }
    }
  }

  @Test("the parser preserves qualified ZSequences calls")
  func parserRetainsQualifiedModuleCalls() throws {
    let source = "ZSequences.rotation(of: corpus, leftBy: 1)"
    let expression = try parseExpression(source)
    let parsed = SpecParser.decodeStateExpr(expression)

    #expect(parsed == .recursiveCall("Rotation", [.variable("corpus"), .int(1)]))
  }

  @Test("typed lexicographic predicates preserve empty, prefix, and element ordering")
  func typedLexicographicPredicates() throws {
    let consumer = TLASpec("TypedLexicographicPredicates") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: 3))
    }
    let functions = try FormalModuleClosure.resolve(root: consumer).linkedOperators.recursiveFunctions
    let cases: [([Int], [Int], Bool)] = [
      ([], [], true), ([], [0], true), ([0], [], false),
      ([0], [0, 1], true), ([0, 1], [0], false),
      ([1, 1, 1], [1, 1, 1], true),
      ([-1, 2], [0, -2], true), ([0, 2], [0, 1], false)
    ]
    for (left, right, expected) in cases {
      let predicate: Expr<Bool> = ZSequences.lexicographicallyPrecedesOrEquals(
        ZSequences.zeroBased(from: left.expr), ZSequences.zeroBased(from: right.expr))
      #expect(try compiledValue(predicate.stateExpr, recursiveFunctions: functions) == .bool(expected))
    }
  }

  @Test("ZSequences keeps the upstream operators in its own importable module")
  func zeroBasedSequenceModuleIsExecutable() throws {
    let sequence = ZeroBasedSequence<Int>.literal(3, 1, 2)
    let rotated = ZSequences.rotation(of: sequence, leftBy: Expr(.int(1)))
    let configured = TLASpec("ConfiguredZSequences") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: 2))
      Algorithm("ConfiguredZSequences", scoped: { scope in
        let rotatedState: SharedVariable<ZeroBasedSequence<Int>> = scope.sharedVar(_name: "rotated",
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
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: 2))
      Variable(corpus, ZeroBasedSequence<Int>())
      Invariant("RotationOrdering") {
        ZSequences.lexicographicallyPrecedesOrEquals(
          ZSequences.rotation(of: Expr(corpus.stateExpr), leftBy: Expr(.int(0))),
          ZSequences.rotation(of: Expr(corpus.stateExpr), leftBy: Expr(.int(0)))
        )
      }
    }

    #expect(try consumer.compile().render().tlaBundle.tla.contains("EXTENDS Integers, FiniteSets, Sequences, ZSequences"))
    let bundle = try consumer.compile().render().tlaBundle
    #expect(bundle.imports.map { $0.name } == ["ZSequences"])
    let importedModule = try #require(bundle.imports.first)
    #expect(importedModule.tla.contains("Rotation("))
    #expect(importedModule.tla.contains("VARIABLES") == false)
    #expect(importedModule.tla.contains("Spec ==") == false)
    let exploration = try ModelChecker(compilation: consumer.compile(), configuration: .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).explore()
    #expect(exploration.isComplete)
    #expect(exploration.safetyViolations.map { $0.diagnostic?.kind } == [.deadlock])
  }

  @Test("an imported module keeps its source boundary while receiving a typed TLC replacement")
  func importedModuleUsesScopedFiniteReplacement() throws {
    let consumer = TLASpec("BoundedZSequences") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: 2))
    }

    #expect(try consumer.compile().render().tlaBundle.tla.contains("ZSequencesNat == 0..2"))
    #expect(try consumer.compile().render().tlaBundle.cfg.contains("CONSTANT Nat <- [ZSequences]ZSequencesNat"))
    let bundle = try consumer.compile().render().tlaBundle
    #expect(bundle.imports.map(\.name) == ["ZSequences"])
    #expect(!bundle.root.tla.contains("ZSeq(elements) =="))

    let domain: Expr<Set<ZeroBasedSequence<Int>>> = ZSequences.sequences(over: Set<Int>([0, 1]))
    let sequences = try compiledValue(
      domain.stateExpr,
      recursiveFunctions: try FormalModuleClosure.resolve(root: consumer)
        .linkedOperators.recursiveFunctions
    )
    guard case .set(let values) = sequences else {
      Issue.record("The bounded ZSeq value was not a set.")
      return
    }
    #expect(values.count == 7)
    #expect(try #require(Set<ZeroBasedSequence<Int>>(formalValue: sequences)).count == 7)

    let sequence = ZeroBasedSequence<Int>.literal(0, 1)
    let indices: Expr<Set<Int>> = ZSequences.indices(of: sequence)
    let rotations: Expr<Set<ZSequences.Rotation<Int>>> = ZSequences.rotations(of: sequence)
    let functions = try FormalModuleClosure.resolve(root: consumer).linkedOperators.recursiveFunctions
    let indexValues = try compiledValue(indices.stateExpr, recursiveFunctions: functions)
    #expect(Set<Int>(formalValue: indexValues) == [0, 1])
    let rotationValues = try compiledValue(rotations.stateExpr, recursiveFunctions: functions)
    let projectedRotations = try #require(Set<ZSequences.Rotation<Int>>(formalValue: rotationValues))
    #expect(projectedRotations.count == 2)
    #expect(Set(projectedRotations.map(\.shift)) == [0, 1])
    for rotation in projectedRotations {
      #expect(rotation.seq.element(at: 0) == rotation.shift)
      #expect(rotation.seq.element(at: 1) == 1 - rotation.shift)
    }

    let corpus = Var<ZeroBasedSequence<Int>>("corpus", .init())
    let initialized = TLASpec("InitializedZSequences") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: 2))
      Variable(corpus, in: ZSequences.sequences(over: Set<Int>([0, 1])))
    }
    let compilation = try initialized.compile()
    #expect(try CompiledRuntime(compilation: compilation).initialStates().count == 7)

    let member = Var<Int>("member", 0)
    let ordinarySet = TLASpec("OrdinarySetDomain") {
      Variable(member, in: Set([0, 1]))
    }
    #expect(try CompiledRuntime(compilation: ordinarySet.compile()).initialStates().count == 2)
  }

  @Test("an import retains source identity while allocating legal file and dependency names", arguments: [
    ("FormalArithmetic", "FormalArithmetic"), ("WF_Arithmetic", "_WF_Arithmetic"),
    ("SF_Arithmetic", "_SF_Arithmetic"), ("_1", "v_1"), ("Sequences", "Sequences_1")
  ])
  func importedOperatorIsBundledAndExecutable(name: String, expected: String) throws {
    let arithmetic = TLASpec(name) {
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

    let compilation = try consumer.compile()
    #expect(compilation.description.imports.map(\.name) == [name])
    let bundle = try compilation.render().tlaBundle
    #expect(bundle.tla.contains("EXTENDS Integers, FiniteSets, Sequences, \(expected)"))
    #expect(!bundle.tla.contains("Twice(value) =="))
    #expect(bundle.imports.map(\.name) == [expected])
    #expect(try #require(bundle.imports.first).tla.hasPrefix("---- MODULE \(expected) ----\n"))
    #expect(bundle.imports.first?.tla.contains("Twice(") == true)
    try bundle.validateDeclaredClosure()
    let exploration = try ModelChecker(compilation: consumer.compile(), configuration: .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).explore()
    #expect(exploration.isComplete)
    #expect(exploration.safetyViolations.map { $0.diagnostic?.kind } == [.deadlock])
  }

  @Test("a named instance retains source identity and a distinct emitted namespace", arguments: [
    ("Math", "Math"), ("Init", "Init_1"), ("Next", "Next_1"), ("Spec", "Spec_1"), ("vars", "vars_1"),
    ("Len", "Len_1"), ("TRUE", "TRUE_1"), ("FALSE", "FALSE_1"), ("BOOLEAN", "BOOLEAN_1"), ("STRING", "STRING_1"),
    ("WF_Math", "_WF_Math"), ("SF_Math", "_SF_Math"), ("_1", "v_1")
  ])
  func namedModuleInstanceIsBundled(name: String, expected: String) throws {
    let arithmetic = TLASpec("InstanceArithmetic") {
      DefineRecursive("Twice", params: ["value"]) {
        StateExpr.variable("value") * 2
      }
    }
    let value = Var<Int>("value", 1)
    let consumer = TLASpec("UsesInstanceArithmetic") {
      let math = Instance(name, of: arithmetic)
      math
      Variable(value, 1)
      Action("Stay") { value.stateExpr == 1 }
      Invariant("ValueIsTwoTimesOne") { math.call("Twice", value.stateExpr) == 2 }
    }

    let compilation = try consumer.compile()
    #expect(compilation.layout.moduleInstances.map(\.namespace) == [name])
    let operation = try #require(compilation.bindings.sourceOperators["\(name)!Twice"])
    #expect(compilation.bindings.operatorName(operation) == "\(expected)!Twice")
    let bundle = try compilation.render().tlaBundle
    #expect(bundle.tla.contains("\(expected) == INSTANCE InstanceArithmetic"))
    #expect(bundle.tla.contains("ValueIsTwoTimesOne == (\(expected)!Twice(value) = 2)"), "Rendered module: \(bundle.tla)")
    #expect(!bundle.tla.contains("EXTENDS Integers, FiniteSets, Sequences, InstanceArithmetic"))
    #expect(bundle.imports.map(\.name) == ["InstanceArithmetic"])
    let importedModule = try #require(bundle.imports.first)
    #expect(importedModule.tla.contains("Twice(value) =="))

    let outcome = try ModelChecker(compilation: try consumer.compile(), configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).check()
    guard case .ok = outcome else {
      Issue.record("The checker did not resolve the qualified module operator.")
      return
    }
  }

  @Test("an instance keeps recursive calls and allocated exports inside its namespace", arguments: [
    ("CountDown", "Math", "Local", "Math"), ("Len", "Math", "Local", "Math"), ("Spec", "Math", "Local", "Math"),
    ("CountDown", "TRUE", "TRUE_1", "TRUE_2"), ("CountDown", "WF_Math", "_WF_Math", "_WF_Math_1")
  ])
  func namedModuleInstanceKeepsRecursiveCallsQualified(name: String, namespace: String, occupied: String, expected: String) throws {
    let counting = TLASpec("InstanceCounting") {
      DefineRecursive(name, params: ["number"]) {
        let number = StateExpr.variable("number")
        return .ifThenElse(
          .equal(number, .int(0)),
          .int(0),
          .add(.int(1), .recursiveCall(name, [.subtract(number, .int(1))]))
        )
      }
    }
    let value = Var<Int>("value", 3)
    let consumer = TLASpec("UsesInstanceCounting") {
      let math = Instance(namespace, of: counting)
      math
      Variable(value, 3)
      Action("Stay") { value.stateExpr == 3 }
      Invariant("CountsDown") {
        StateExpr.letIn([LocalOperator(occupied, parameters: [], body: .int(99))],
          .and(math.call(name, value.stateExpr) == 3,
            .equal(.operatorApplication(.reference(occupied, arity: 0), []), .int(99))))
      }
    }

    let resolved = try FormalModuleClosure.resolve(root: consumer)
      .linkedOperators.recursiveFunctions
    #expect(resolved.map(\.name) == ["\(namespace)!\(name)"])
    let compilation = try consumer.compile()
    #expect(compilation.layout.moduleInstances.map(\.namespace) == [namespace])
    let operation = try #require(compilation.bindings.sourceOperators["\(namespace)!\(name)"])
    let formalName = try #require(compilation.bindings.operatorName(operation))
    #expect(formalName.hasPrefix("\(expected)!"))
    let exportedName = try #require(formalName.split(separator: "!").last)
    #expect(!["Len", "Spec"].contains(String(exportedName)))
    let bundle = try compilation.render().tlaBundle
    #expect(bundle.root.tla.contains("\(formalName)("))
    #expect(try #require(bundle.imports.first).tla.contains("RECURSIVE \(exportedName)("))
    let outcome = try ModelChecker(compilation: try consumer.compile(), configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).check()
    guard case .ok = outcome else {
      Issue.record("The checker did not resolve recursive instance calls.")
      return
    }
  }

  @Test("imported function parameters do not capture caller variables")
  func moduleArgumentsAvoidFunctionParameters() throws {
    let arithmetic = TLASpec("CaptureArithmetic") {
      Parameter("Base", kind: .variable)
      DefineRecursive("AddBase", params: ["number"]) {
        StateExpr.add(.variable("number"), .variable("Base"))
      }
    }
    let value = Var<Int>("number", 10)
    let consumer = TLASpec("CallerFunctionScope") {
      let math = Instance("Math", of: arithmetic, with: [ModuleArgument("Base", value: value.stateExpr)])
      math
      Variable(value, 10)
      Action("Stay") { value.stays }
      Invariant("CallerAndParameterAreDistinct") { math.call("AddBase", StateExpr.value(.int(1))) == 11 }
    }
    let compilation = try consumer.compile()
    let outcome = try ModelChecker(compilation: compilation,
      configuration: try .init(maximumStateLimit: 10, symmetryReduction: .disabled)).check()
    guard case .ok = outcome else {
      Issue.record("The function parameter captured the caller variable: \(outcome)")
      return
    }
  }

  @Test("module arguments preserve references to the caller's parameter names")
  func moduleArgumentsAreSimultaneous() throws {
    let arithmetic = TLASpec("ArgumentArithmetic") {
      Parameter("First", kind: .variable)
      Parameter("Second", kind: .variable)
      DefineRecursive("Difference", params: []) {
        StateExpr.subtract(.variable("First"), .variable("Second"))
      }
    }
    let value = Var<Int>("Second", 10)
    let consumer = TLASpec("CallerArgumentScope") {
      let math = Instance("Math", of: arithmetic, with: [
        ModuleArgument("First", value: value.stateExpr), ModuleArgument("Second", value: 7)
      ])
      math
      Variable(value, 10)
      Action("Stay") { value.stays }
      Invariant("DifferenceIsThree") { math.call("Difference") == 3 }
    }
    let compilation = try consumer.compile()
    let outcome = try ModelChecker(compilation: compilation,
      configuration: try .init(maximumStateLimit: 10, symmetryReduction: .disabled)).check()
    guard case .ok = outcome else {
      Issue.record("Module argument substitution changed a caller reference: \(outcome)")
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

    #expect(try consumer.compile().render().tlaBundle.tla.contains("Math == INSTANCE ParameterizedArithmetic WITH Base <- 2"))
    let bundle = try consumer.compile().render().tlaBundle
    let importedModule = try #require(bundle.imports.first)
    #expect(importedModule.tla.contains("CONSTANTS Base"))
    #expect(importedModule.tla.contains("ASSUME Base") == false)
    let outcome = try ModelChecker(compilation: try consumer.compile(), configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).check()
    guard case .ok = outcome else {
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

    #expect(try consumer.compile().render().tlaBundle.tla.contains("Math == INSTANCE VariableParameterizedArithmetic WITH Base <- value"))
    #expect(try consumer.compile().render().tlaBundle.imports[0].tla.contains("VARIABLES Base"))
    let outcome = try ModelChecker(compilation: try consumer.compile(), configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).check()
    guard case .ok = outcome else {
      Issue.record("The checker did not substitute the state parameter.")
      return
    }
  }

}
