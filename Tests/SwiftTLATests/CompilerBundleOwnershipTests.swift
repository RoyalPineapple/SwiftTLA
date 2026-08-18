import Testing
@testable import SwiftTLA

@Suite("Compiler formal module closure")
struct CompilerBundleOwnershipTests {
  @Test("a closure owns each dependency once in dependency-first order")
  func validClosureHasDeterministicOwnership() throws {
    let dependency = TLASpec(name: "Dependency", variables: [], actions: [], invariants: [])
    let support = TLASpec(
      name: "Support", variables: [], actions: [], invariants: [], imports: [dependency]
    )
    let unrelated = TLASpec(name: "Unrelated", variables: [], actions: [], invariants: [])
    let root = TLASpec(name: "Root", variables: [], actions: [], invariants: [], imports: [support])

    let closure = try FormalModuleClosure.resolve(root: root)

    #expect(closure.entries.map(\.module.name) == ["Dependency", "Support", "Root"])
    #expect(closure.entries.map(\.owningRoot) == ["Root", "Root", "Root"])
    #expect(closure.entries.map(\.structuralPath) == [
      ["Root", "Support", "Dependency"], ["Root", "Support"], ["Root"]
    ])
    #expect(!closure.entries.contains { $0.module.name == unrelated.name })
  }

  @Test("closure retains import configuration and instance argument edges")
  func closureRetainsEdgePayloads() throws {
    let library = TLASpec(name: "Library", variables: [], formalParameters: [.init("Base")], actions: [], invariants: [])
    let root = TLASpec("Root") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2))
      Instance("Library", of: library, with: [ModuleArgument("Base", value: 1)])
    }
    let closure = try root.compile().formalModuleClosure

    #expect(closure.edges.contains { if case .importModule(let configuration) = $0.kind { configuration == ZSequences.boundedNaturalNumbers(0...2) } else { false } })
    #expect(closure.edges.contains { if case .namedInstance("Library", let arguments) = $0.kind { arguments == [ModuleArgument("Base", value: 1)] } else { false } })
  }

  @Test("same-name modules with different sources block compilation")
  func conflictingModuleSourcesBlockCompilation() throws {
    let first = TLASpec(
      name: "Shared", variables: [NamedVar(name: "left", initial: .int(0))], actions: [], invariants: []
    )
    let second = TLASpec(
      name: "Shared", variables: [NamedVar(name: "right", initial: .int(0))], actions: [], invariants: []
    )
    let root = TLASpec(name: "Root", variables: [], actions: [], invariants: [], imports: [first, second])

    try expectLinkDiagnostic(.conflictingFormalModuleSource, from: root)
  }

  @Test("the same canonical module imported twice is a duplicate import")
  func duplicateCanonicalImportBlocksCompilation() throws {
    let shared = TLASpec(name: "Shared", variables: [], actions: [], invariants: [])
    let root = TLASpec(
      name: "Root", variables: [], actions: [], invariants: [], imports: [shared, shared]
    )

    try expectLinkDiagnostic(.duplicateFormalModuleImport, from: root)
  }

  @Test("configured replacements reach imported formal operators")
  func configuredReplacementReachesFormalOperatorDefinitions() throws {
    let library = TLASpec(
      name: "Library", variables: [], actions: [], invariants: [],
      formalOperatorDefinitions: [
        .init(name: "ConfiguredValue", parameters: [], body: .variable("Base"))
      ]
    )
    let root = TLASpec(
      name: "Root", variables: [], actions: [], invariants: [], imports: [library],
      importConfigurations: [
        .init(moduleName: "Library", replacements: [
          .init(operatorName: "Base", definitionName: "BaseValue", expression: .int(7))
        ])
      ]
    )

    let definitions = try root.compile().formalModuleClosure.resolvedFormalOperatorDefinitions
    let value = try StateExpr.operatorApplication(
      .reference("ConfiguredValue", arity: 0), []
    ).evaluate(in: [:], formalOperatorDefinitions: definitions)

    #expect(value == .int(7))
  }

  @Test("duplicate namespaces, bindings, and missing targets produce link diagnostics")
  func conflictingBindingsBlockCompilation() throws {
    let library = TLASpec(
      name: "Library", variables: [], formalParameters: [.init("Base", kind: .constant)],
      actions: [], invariants: []
    )
    let duplicateNamespaces = TLASpec(
      name: "Root", variables: [], actions: [], invariants: [],
      moduleInstances: [Instance("Library", of: library), Instance("Library", of: library)]
    )
    let missingConfigurationTarget = TLASpec(
      name: "ConfiguredRoot", variables: [], actions: [], invariants: [],
      importConfigurations: [.init(moduleName: "Library", replacements: [])]
    )
    let duplicateBindings = TLASpec(
      name: "BoundRoot", variables: [], actions: [], invariants: [],
      moduleInstances: [Instance("Library", of: library, with: [
        ModuleArgument("Base", value: 1), ModuleArgument("Base", value: 2)
      ])]
    )

    try expectLinkDiagnostic(.duplicateFormalModuleInstanceNamespace, from: duplicateNamespaces)
    try expectLinkDiagnostic(.missingFormalModuleConfigurationTarget, from: missingConfigurationTarget)
    try expectLinkDiagnostic(.duplicateFormalModuleArgument, from: duplicateBindings)
  }

  @Test("ambiguous symbols exported by imports block compilation")
  func duplicateImportedSymbolsBlockCompilation() throws {
    let left = TLASpec("Left") {
      DefineRecursive("Shared", params: []) { 1 }
    }
    let right = TLASpec("Right") {
      DefineRecursive("Shared", params: []) { 2 }
    }
    let root = TLASpec(
      name: "Root", variables: [], actions: [], invariants: [], imports: [left, right]
    )

    try expectLinkDiagnostic(.duplicateFormalModuleSymbol, from: root)
  }

  @Test("an imported instance namespace cannot collide through a transitive import")
  func transitiveInstanceNamespaceCollisionBlocksCompilation() throws {
    let base = TLASpec("Base") {
      DefineRecursive("Value", params: []) { 1 }
    }
    let transitivelyNamespaced = TLASpec("TransitivelyNamespaced") {
      Instance("Shared", of: base)
    }
    let root = TLASpec("Root") {
      Import(transitivelyNamespaced)
      Instance("Shared", of: base)
    }

    try expectLinkDiagnostic(.duplicateFormalModuleSymbol, from: root)
  }

  @Test("invalid parameters and unresolved configuration replacements block compilation")
  func invalidParametersAndReplacementsBlockCompilation() throws {
    let invalidParameter = TLASpec(name: "Invalid", variables: [], formalParameters: [.init("")], actions: [], invariants: [])
    let invalidReplacement = TLASpec("Root") {
      Import(ZSequences.module, configuring: .init(moduleName: "ZSequences", replacements: [
        .init(operatorName: "Missing", definitionName: "MissingValue", expression: .int(0))
      ]))
    }

    try expectLinkDiagnostic(.invalidFormalModuleParameter, from: invalidParameter)
    try expectLinkDiagnostic(.unresolvedFormalModuleReplacement, from: invalidReplacement)
  }

  @Test("replacement targets are structural free module symbols, not binders")
  func replacementTargetExcludesBoundNames() throws {
    let library = TLASpec(
      name: "Library", variables: [], actions: [], invariants: [],
      recursiveFuncs: [
        .init(
          name: "UsesOnlyLocal",
          params: [],
          body: .forAll(.setLiteral([.int(1)]), "Local", .equal(.variable("Local"), .int(1)))
        )
      ]
    )
    let root = TLASpec(
      name: "Root", variables: [], actions: [], invariants: [], imports: [library],
      importConfigurations: [
        .init(moduleName: "Library", replacements: [
          .init(operatorName: "Local", definitionName: "LocalValue", expression: .int(1))
        ])
      ]
    )

    try expectLinkDiagnostic(.unresolvedFormalModuleReplacement, from: root)
  }

  @Test("public execution entry points compile before they link")
  func executionEntryPointsRejectInvalidModuleClosure() {
    let invalid = TLASpec(
      name: "Root", variables: [], actions: [], invariants: [],
      importConfigurations: [.init(moduleName: "Missing", replacements: [])]
    )

    #expect(throws: CompilationDiagnostic.self) { try computeInitialStates(invalid) }
    #expect(throws: CompilationDiagnostic.self) { try TransitionRelation(spec: invalid) }
    #expect(throws: CompilationDiagnostic.self) { try ModelChecker(spec: invalid) }
    #expect(throws: CompilationDiagnostic.self) { try SpecRuntime(spec: invalid) }
  }

  private func expectLinkDiagnostic(
    _ code: CompilationDiagnostic.Code,
    from spec: TLASpec
  ) throws {
    do {
      _ = try spec.compile()
      Issue.record("Expected a blocking formal-module diagnostic.")
    } catch let diagnostic as CompilationDiagnostic {
      #expect(diagnostic.code == code)
      #expect(diagnostic.stage == .linking)
    }
  }
}
