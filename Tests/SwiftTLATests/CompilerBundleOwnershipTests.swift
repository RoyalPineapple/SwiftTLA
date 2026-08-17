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
