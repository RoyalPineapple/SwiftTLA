extension TLASpec {
  public init(
    _ name: String,
    @SpecBuilder _ builder: () -> [SpecComponent]
  ) {
    let components = builder()
    var variables: [NamedVar] = []
    var actions: [NamedAction] = []
    var invariants: [NamedInvariant] = []
    var temporalProperties: [NamedTemporal] = []
    var fairness: [FairnessCondition] = []
    var constants: [ConstantDecl] = []
    var formalParameters: [FormalModuleParameter] = []
    var theorems: [TheoremDecl] = []
    var assumes: StateExpr?
    var extendsMods: [StandardModule] = [.integers]
    var deadlockFlag = false
    var constraint: StateExpr?
    var recursiveFuncs: [RecursiveFunc] = []
    var formalOperatorDefinitions: [FormalOperatorDefinition] = []
    let imports = components.compactMap { $0 as? ImportDecl }
    let importedModules = imports.map(\.module)
    let importConfigurations = imports.compactMap(\.configuration)
    let moduleInstances = components.compactMap { $0 as? FormalModuleInstance }
    let refinements = components.compactMap { $0 as? RefinementDecl }
    var symmetrySets: [SymmetrySet] = []
    var symmetricCollections: [SymmetricCollectionDecl] = []
    var algorithmFidelityTokens: [AlgorithmFidelityToken] = []
    var sourceAlgorithms: [Algorithm] = []
    // Collect the definitions needed to materialize closed Algorithm initial values.
    for comp in components {
      if let definition = comp as? FormalOperatorDecl {
        formalOperatorDefinitions.append(definition.definition)
      }
    }

    for comp in components {
      if let v = comp as? VarDecl {
        variables.append(
          NamedVar(
            name: v.name, initial: v.initial, initialSet: v.initialSet, initExpr: v.initExpr,
            lazySet: v.lazySet, collectionType: v.collectionType))
      } else if let s = comp as? SymmetricCollectionDecl {
        variables.append(
          NamedVar(
            name: s.variable.name, initial: s.variable.initial, initialSet: s.variable.initialSet,
            initExpr: s.variable.initExpr, lazySet: s.variable.lazySet,
            collectionType: s.variable.collectionType))
        symmetricCollections.append(s)
      } else if let a = comp as? ActionDecl {
        actions.append(NamedAction(name: a.name, body: a.body, bindings: a.bindings))
      } else if let algorithm = comp as? Algorithm {
        algorithmFidelityTokens.append(AlgorithmFidelityToken(model: algorithm.model))
        sourceAlgorithms.append(algorithm)
      } else if let i = comp as? InvDecl {
        invariants.append(NamedInvariant(name: i.name, body: i.body))
      } else if let t = comp as? TemporalDecl {
        temporalProperties.append(NamedTemporal(name: t.name, expr: t.expr))
      } else if let f = comp as? FairnessDecl {
        fairness.append(f.condition)
      } else if let c = comp as? ConstantDecl {
        constants.append(c)
      } else if let parameter = comp as? FormalModuleParameter {
        formalParameters.append(parameter)
      } else if let th = comp as? TheoremDecl {
        theorems.append(th)
      } else if let a = comp as? AssumeDecl {
        assumes = assumes.map { .and($0, a.expr) } ?? a.expr
      } else if let e = comp as? ExtendsDecl {
        extendsMods.append(contentsOf: e.modules)
      } else if comp is DeadlockDecl {
        deadlockFlag = true
      } else if let c = comp as? ConstraintDecl {
        constraint = constraint.map { .and($0, c.body) } ?? c.body
      } else if let rf = comp as? RecursiveFuncDecl {
        recursiveFuncs.append(rf.funcDef)
      } else if let s = comp as? SymmetrySetDecl {
        symmetrySets.append(SymmetrySet(variableName: s.variableName, values: s.values))
      }
    }

    self.name = name
    self.variables = variables
    self.constants = constants
    self.formalParameters = formalParameters
    self.actions = actions
    self.invariants = invariants
    self.temporalProperties = temporalProperties
    self.fairness = fairness
    self.assume = assumes
    self.checkDeadlock = deadlockFlag
    self.theorems = theorems
    self.extendsModules = canonicalStandardModules(extendsMods)
    self.constraint = constraint
    self.recursiveFuncs = recursiveFuncs
    self.formalOperatorDefinitions = formalOperatorDefinitions
    self.imports = importedModules
    self.importConfigurations = importConfigurations
    self.moduleInstances = moduleInstances
    self.refinements = refinements
    self.symmetrySets = symmetrySets
    self.symmetricCollections = symmetricCollections
    self.algorithmFidelityTokens = algorithmFidelityTokens
    self.sourceAlgorithms = sourceAlgorithms
    self.algorithmPhase = sourceAlgorithms.isEmpty ? .lowered : .source
  }
}

extension TLASpec {
  func loweredSourceModel() throws -> TLASpec {
    guard algorithmPhase == .source else { return self }
    var variables = variables
    var actions = actions
    var invariants = invariants
    var temporalProperties = temporalProperties
    var fairness = fairness
    var constraint = constraint
    var formalOperatorDefinitions = formalOperatorDefinitions

    for algorithm in sourceAlgorithms {
      try algorithm.requireValid()
      let lowered = try AlgorithmLowerer.lower(
        algorithm.model,
        formalOperatorDefinitions: formalOperatorDefinitions
      )
      variables += lowered.variables
      actions += lowered.actions
      invariants += lowered.invariants
      temporalProperties += lowered.temporalProperties
      fairness += lowered.fairness
      formalOperatorDefinitions += algorithm.model.formalOperatorDefinitions
      if let loweredConstraint = lowered.constraint {
        constraint = constraint.map { .and($0, loweredConstraint) } ?? loweredConstraint
      }
    }

    let variableNames = variables.map(\.name)
    actions = actions.map { action in
      NamedAction(
        name: action.name,
        body: ActionNormalization.complete(action.body, variables: variableNames),
        bindings: action.bindings
      )
    }

    var lowered = TLASpec(
      name: name,
      variables: variables,
      constants: constants,
      formalParameters: formalParameters,
      actions: actions,
      invariants: invariants,
      temporalProperties: temporalProperties,
      fairness: fairness,
      assume: assume,
      checkDeadlock: checkDeadlock,
      theorems: theorems,
      extendsModules: extendsModules,
      constraint: constraint,
      recursiveFuncs: recursiveFuncs,
      formalOperatorDefinitions: formalOperatorDefinitions,
      imports: imports,
      importConfigurations: importConfigurations,
      moduleInstances: moduleInstances,
      refinements: refinements,
      symmetrySets: symmetrySets,
      symmetricCollections: symmetricCollections,
      algorithmFidelityTokens: algorithmFidelityTokens,
      sourceAlgorithms: sourceAlgorithms
    )
    lowered.algorithmPhase = .lowered
    return lowered
  }

  func authoredPlusCalModule(
    semantics: CompiledSemantics,
    formalRenderer: CompiledTLARenderer,
    renderedRefinements: [String]
  ) throws -> AuthoredPlusCalModule? {
    guard sourceAlgorithms.count == 1, let algorithm = sourceAlgorithms.first else {
      return nil
    }
    let plusCalAlgorithm = algorithm.model.plusCalProjection()
    let declarationSections = try authoredPlusCalDeclarationSections(
      semantics: semantics,
      formalRenderer: formalRenderer
    )
    let declarationPlan = AuthoredPlusCalModule(
      name: name,
      extendsModules: authoredPlusCalExtends,
      constants: authoredPlusCalPrelude,
      definitionsBeforeInstances: declarationSections.prelude,
      instances: moduleInstances,
      instanceArguments: Dictionary(uniqueKeysWithValues: moduleInstances.map { ($0.name, instanceArguments(for: $0)) }),
      definitionsAfterInstances: [],
      algorithm: plusCalAlgorithm,
      defineDeclarations: declarationSections.define,
      postTranslationDeclarations: [],
      refinements: renderedRefinements
    )
    let renderer = AlgorithmPlusCalRenderer(module: declarationPlan)
    let sourceProperties = try renderer.sourcePropertyDefinitions()
    let sourcePropertyNames = sourceProperties.map(\.name)
    let topLevelProperties = try invariants
      .filter { sourcePropertyNames.contains($0.name) == false }
      .map { invariant -> (name: String, definition: String) in
        guard let compiled = semantics.invariants.first(where: { $0.name == invariant.name }) else {
          throw CompilationDiagnostic(
            code: .compilationIdentityMismatch,
            stage: .rendering,
            path: "authoredPlusCal.invariants.\(invariant.name)",
            expected: "a compiled invariant",
            actual: "no compiled invariant",
            nextSafeAction: "Compile the model again from its current source."
          )
        }
        return (name: invariant.name, definition: "\(invariant.name) == \(try formalRenderer.state(compiled.body))")
      }
    let topLevelPropertyNames = topLevelProperties.map(\.name)
    let loweredPropertyNames = invariants.map(\.name) + temporalProperties.map(\.name)
    guard Set(sourcePropertyNames).count == sourcePropertyNames.count,
          Set(topLevelPropertyNames).count == topLevelPropertyNames.count,
          Set(loweredPropertyNames).count == loweredPropertyNames.count,
          Set(sourcePropertyNames + topLevelPropertyNames)
            .union(renderer.translatorOwnedPropertyNames()) == Set(loweredPropertyNames)
    else {
        throw AlgorithmPlusCalRenderDiagnostic(
          failedConcept: "authored PlusCal property export",
          path: "TLASpec.properties",
          expected: "one rendered typed property for every lowered property",
          actual: "Algorithm properties \(sourcePropertyNames); top-level typed properties \(topLevelPropertyNames); lowered properties \(loweredPropertyNames)",
          nextSafeAction: "Give each property a unique name and use a supported typed property expression."
        )
    }
    let module = AuthoredPlusCalModule(
      name: name,
      extendsModules: authoredPlusCalExtends,
      constants: authoredPlusCalPrelude,
      definitionsBeforeInstances: declarationSections.prelude,
      instances: moduleInstances,
      instanceArguments: Dictionary(uniqueKeysWithValues: moduleInstances.map { ($0.name, instanceArguments(for: $0)) }),
      definitionsAfterInstances: [],
      algorithm: plusCalAlgorithm,
      defineDeclarations: declarationSections.define,
      postTranslationDeclarations: (sourceProperties + topLevelProperties).map(\.definition)
        + authoredPlusCalSymmetry,
      refinements: renderedRefinements
    )
    return module
  }

  private var authoredPlusCalExtends: [String] {
    let requested = extendsModules.map(\.rawValue)
    let standard = [StandardModule.naturals, .integers, .sequences, .finiteSets].map(\.rawValue)
    let symmetry = symmetrySets.isEmpty ? [] : [StandardModule.tlc.rawValue]
    let imported = imports.map(\.name)
    let candidates = requested + standard + symmetry + imported
    var modules: [String] = []
    for module in candidates where !modules.contains(module) {
      modules.append(module)
    }
    return modules
  }

  private var authoredPlusCalPrelude: [String] {
    var lines: [String] = []
    let constantNames = (constants.map(\.name) + formalParameters.filter { $0.kind == .constant }.map(\.name)).sorted()
    if !constantNames.isEmpty {
      lines.append("CONSTANTS \(constantNames.joined(separator: ", "))")
    }
    return lines
  }

  private func authoredPlusCalDeclarationSections(
    semantics: CompiledSemantics,
    formalRenderer: CompiledTLARenderer
  ) throws -> AuthoredPlusCalDeclarationSections {
    guard formalOperatorDefinitions.count <= semantics.formalOperatorDefinitions.count else {
      throw CompilationDiagnostic(
        code: .compilationIdentityMismatch,
        stage: .rendering,
        path: "authoredPlusCal.definitions",
        expected: "compiled definitions aligned with this source model",
        actual: "\(semantics.formalOperatorDefinitions.count) compiled definitions for \(formalOperatorDefinitions.count) declared definitions",
        nextSafeAction: "Compile the model again from its current source."
      )
    }
    let definitions = try formalOperatorDefinitions.enumerated().map { index, definition in
      AuthoredPlusCalDeclaration(
        name: definition.name,
        text: try formalRenderer.formalDefinition(semantics.formalOperatorDefinitions[index]),
        phase: definition.plusCalPhase,
        dependencies: definition.plusCalDependencies
      )
    }
    let instances = moduleInstances.map { instance in
      let arguments = instanceArguments(for: instance).map { "\($0.parameter) <- \($0.value)" }.joined(separator: ", ")
      let withClause = arguments.isEmpty ? "" : " WITH \(arguments)"
      return AuthoredPlusCalDeclaration(
        name: instance.name,
        text: "\(instance.name) == INSTANCE \(instance.module.name)\(withClause)",
        phase: instance.plusCalPhase,
        dependencies: instance.plusCalDependencies
      )
    }
    return try AuthoredPlusCalDeclarationSections(definitions + instances)
  }

  private var authoredPlusCalSymmetry: [String] {
    symmetrySets.map { symmetry in
      let values = symmetry.values.sorted()
        .map(\.description)
        .joined(separator: ", ")
      return "Symm\(symmetry.variableName) == Permutations({\(values)})"
    }
  }
}

struct AuthoredPlusCalDeclarationSections {
  let prelude: [String]
  let define: [String]

  init(_ declarations: [AuthoredPlusCalDeclaration]) throws {
    var emitted: Set<String> = []
    func order(_ phase: AuthoredPlusCalDeclarationPhase) throws -> [String] {
      var pending = declarations.filter { $0.phase == phase }
      var result: [String] = []
      let declared = Set(declarations.compactMap(\.name))
      if let unresolved = pending.first(where: { $0.dependencies.contains(where: { !declared.contains($0) }) }) {
        throw AlgorithmPlusCalRenderDiagnostic(failedConcept: "authored PlusCal declaration dependency", path: unresolved.name ?? "unnamed", expected: "a declared dependency", actual: unresolved.dependencies.joined(separator: ", "), nextSafeAction: "Declare the dependency or remove its placement edge.")
      }
      while let index = pending.firstIndex(where: { declaration in
        declaration.dependencies.allSatisfy(emitted.contains)
      }) {
        let declaration = pending.remove(at: index)
        result.append(declaration.text)
        if let name = declaration.name { emitted.insert(name) }
      }
      if !pending.isEmpty {
        throw AlgorithmPlusCalRenderDiagnostic(failedConcept: "authored PlusCal declaration dependency", path: pending.compactMap(\.name).joined(separator: ","), expected: "an acyclic declaration dependency graph", actual: "cyclic dependencies", nextSafeAction: "Break the declaration cycle or move the declarations to one legal phase.")
      }
      return result
    }
    prelude = try order(.prelude)
    define = try order(.define)
  }
}

package func assignedVars(_ e: ActionExpr) -> Set<ActionTarget> {
  switch e {
  case .assign(let target, _), .chooseAction(let target, _): return [target]
  case .unchanged, .guard_: return []
  case .and(let a, let b): return assignedVars(a).union(assignedVars(b))
  case .or(let a, let b): return assignedVars(a).union(assignedVars(b))
  case .ifElse(_, let t, let e): return assignedVars(t).union(assignedVars(e))
  case .define(_, _, let b): return assignedVars(b)
  case .existsAction(_, _, let b): return assignedVars(b)
  }
}

package func explicitUnchanged(_ e: ActionExpr) -> Set<ActionTarget> {
  switch e {
  case .unchanged(let target): return [target]
  case .and(let a, let b): return explicitUnchanged(a).union(explicitUnchanged(b))
  case .or(let a, let b): return explicitUnchanged(a).intersection(explicitUnchanged(b))
  case .ifElse: return []
  case .define: return []
  case .existsAction: return []
  default: return []
  }
}
