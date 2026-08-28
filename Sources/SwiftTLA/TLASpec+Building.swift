extension TLASpec {
  public init(
    _ name: String,
    @SpecBuilder _ builder: () -> [SpecComponent]
  ) {
    self.init(name, components: builder())
  }

  public init(
    _ name: String,
    @SpecBuilder scoped builder: (SpecificationScope) -> [SpecComponent]
  ) {
    let scope = SpecificationScope()
    let body = builder(scope)
    let components = scope.declarations + body
    self.init(name, components: components)
  }

  private init(_ name: String, components: [SpecComponent]) {
    var variables: [NamedVar] = []
    var actions: [NamedAction] = []
    var invariants: [NamedInvariant] = []
    var temporalProperties: [NamedTemporal] = []
    var fairness: [FairnessCondition] = []
    var constants: [ConstantDecl] = []
    var formalParameters: [FormalModuleParameter] = []
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
            name: v.name, initialization: v.initialization, collectionType: v.collectionType,
            generatedSwiftType: v.generatedSwiftType, origin: .source))
      } else if let s = comp as? SymmetricCollectionDecl {
        variables.append(s.variable)
        symmetricCollections.append(s)
      } else if let a = comp as? ActionDecl {
        actions.append(NamedAction(
          name: a.name,
          body: a.body,
          bindings: a.bindings,
          controlOwner: nil
        ))
      } else if let algorithm = comp as? Algorithm {
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
    self.sourceAlgorithms = sourceAlgorithms
    self.algorithmPhase = sourceAlgorithms.isEmpty ? .lowered : .source
  }
}

extension TLASpec {
  func loweredSourceModel() throws -> TLASpec {
    try validateCapabilityAdmission()
    var variables = variables
    var actions = actions
    var invariants = invariants
    var temporalProperties = temporalProperties
    var fairness = fairness
    var constraint = constraint
    var formalOperatorDefinitions = formalOperatorDefinitions

    if algorithmPhase == .source {
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
    }

    actions = actions.map { action in
      let body: ActionExpr
      if case .existsAction(let binder, let domain, let memberBody) = action.body {
        body = .existsAction(
          binder,
          domain,
          ActionNormalization.complete(memberBody, variables: variables)
        )
      } else {
        body = ActionNormalization.complete(action.body, variables: variables)
      }
      return NamedAction(
        name: action.name,
        body: body,
        bindings: action.bindings,
        controlOwner: action.controlOwner
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
      sourceAlgorithms: sourceAlgorithms
    )
    lowered.algorithmPhase = .lowered
    return lowered
  }

  private func validateCapabilityAdmission() throws {
    for algorithm in sourceAlgorithms {
      try AlgorithmCapabilityValidator.validate(algorithm.model)
    }
    for refinement in refinements {
      switch refinement.operator {
      case .spec:
        continue
      case .liveSpec:
        throw refinementCapabilityDiagnostic(.temporalRefinementLiveSpec, refinement: refinement)
      case .liveSpecEquals:
        throw refinementCapabilityDiagnostic(.temporalRefinementLiveSpecEquals, refinement: refinement)
      }
    }
  }

  private func refinementCapabilityDiagnostic(
    _ construct: DeclaredLanguageConstruct,
    refinement: RefinementDecl
  ) -> LanguageCapabilityDiagnostic {
    let capability = LanguageCapabilityLedger.capability(for: construct)
    return .init(
      code: .unsupportedConstruct,
      construct: .declared(construct: construct, authoredName: construct.rawValue),
      operation: .compilation,
      source: refinement.name,
      sourcePath: ["refinements", refinement.name, "operator"],
      sourceSpan: .init(location: .unavailable, utf8Length: refinement.name.utf8.count),
      expected: capability.boundary,
      actual: "\(construct.rawValue) target",
      nextSafeAction: capability.nextSafeAction
    )
  }

  func authoredPlusCalModule(
    semantics: CompiledSemantics,
    layout: CompiledLayout,
    bindings: CompiledBindingTable,
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
    let propertyPlan = try authoredPlusCalProperties(in: plusCalAlgorithm)
    let sourceProperties = propertyPlan.properties
    let invariantsByID = Dictionary(uniqueKeysWithValues: semantics.invariants.map { ($0.id, $0) })
    let temporalPropertiesByID = Dictionary(uniqueKeysWithValues: semantics.temporalProperties.map { ($0.id, $0) })
    func propertyMissing(_ id: PropertyID) -> CompilationDiagnostic {
      .init(code: .compilationIdentityMismatch, stage: .rendering, path: "authoredPlusCal.properties", expected: "a compiled property for identity \(id.ordinal)", actual: "no compiled property", nextSafeAction: "Compile the model again from its current source.")
    }
    func propertyID(_ property: AuthoredPlusCalProperty) throws -> PropertyID {
      let path = property.bindingPath
      guard case .property(let id) = bindings.references[path] else {
        throw CompilationDiagnostic(code: .compilationIdentityMismatch, stage: .rendering, path: path, expected: "a bound property identity", actual: "no property identity", nextSafeAction: "Compile the model again from its current source.")
      }
      return id
    }
    let sourcePropertyIDs = try Set(sourceProperties.map(propertyID))
    let renderedSourceProperties = try sourceProperties.map { property -> (name: String, definition: String) in
      let id = try propertyID(property)
      switch property {
      case .invariant(let name):
        guard let invariant = invariantsByID[id] else { throw propertyMissing(id) }
        return (name, "\(name) == \(try formalRenderer.state(invariant.body))")
      case .temporal(let name):
        guard let temporal = temporalPropertiesByID[id] else { throw propertyMissing(id) }
        return (name, "\(name) == \(try formalRenderer.temporal(temporal.expression))")
      }
    }
    let topLevelProperties = try layout.stateProperties
      .filter { !sourcePropertyIDs.contains($0.id) }
      .map { property -> (name: String, definition: String) in
        guard let invariant = invariantsByID[property.id] else { throw propertyMissing(property.id) }
        return (property.declaration.name, "\(property.declaration.name) == \(try formalRenderer.state(invariant.body))")
      }
    let topLevelPropertyNames = topLevelProperties.map(\.name)
    let sourcePropertyNames = sourceProperties.map(\.name)
    let loweredPropertyNames = invariants.map(\.name) + temporalProperties.map(\.name)
    guard Set(sourcePropertyNames).count == sourcePropertyNames.count,
          Set(topLevelPropertyNames).count == topLevelPropertyNames.count,
          Set(loweredPropertyNames).count == loweredPropertyNames.count,
          Set(sourcePropertyNames + topLevelPropertyNames)
            .union(propertyPlan.translatorOwnedNames) == Set(loweredPropertyNames)
    else {
        throw AlgorithmPlusCalRenderDiagnostic(
          failedConcept: "authored PlusCal property export",
          path: "TLASpec.properties",
          expected: "one rendered typed property for every lowered property",
          actual: "Algorithm properties \(sourcePropertyNames); top-level typed properties \(topLevelPropertyNames); lowered properties \(loweredPropertyNames)",
          nextSafeAction: "Give each property a unique name and use a supported typed property expression."
        )
    }
    let constraint = try semantics.constraint.map { "StateConstraint == \(try formalRenderer.state($0))" }
    let renderedProperties = (renderedSourceProperties + topLevelProperties).map(\.definition)
    let postTranslationDeclarations = declarationSections.postTranslation
      + (constraint.map { [$0] } ?? [])
      + renderedProperties
      + authoredPlusCalSymmetry
    let module = AuthoredPlusCalModule(
      name: name,
      extendsModules: authoredPlusCalExtends,
      constants: authoredPlusCalPrelude,
      preludeDeclarations: declarationSections.prelude,
      algorithm: plusCalAlgorithm,
      defineDeclarations: declarationSections.define,
      postTranslationDeclarations: postTranslationDeclarations,
      refinements: renderedRefinements
    )
    return module
  }

  private func authoredPlusCalProperties(
    in algorithm: AlgorithmModel
  ) throws -> (properties: [AuthoredPlusCalProperty], translatorOwnedNames: Set<String>) {
    func isTranslatorTermination(_ temporal: NamedTemporal) -> Bool {
      guard temporal.name == "Termination", algorithm.processes.count == 1,
            case .eventually(let expression) = temporal.expr,
            case .forAll(let domain, let binding, let predicate) = expression,
            domain == .setLiteral(algorithm.processes[0].domain.map(StateExpr.value))
      else { return false }
      switch predicate {
      case .equal(.functionApply(.programCounter, .variable(let process)), .controlLocation(let location)),
           .equal(.controlLocation(let location), .functionApply(.programCounter, .variable(let process))):
        return location.sourceName == CompilerControlSymbol.done.rawValue && process == binding
      default:
        return false
      }
    }

    func collect(
      _ components: [AlgorithmComponentModel],
      path: String
    ) throws -> (properties: [AuthoredPlusCalProperty], translatorOwnedNames: Set<String>) {
      var properties: [AuthoredPlusCalProperty] = []
      var translatorOwnedNames: Set<String> = []
      for (index, component) in components.enumerated() {
        let componentPath = "\(path)[\(index)]"
        switch component {
        case .invariant(let invariant):
          properties.append(.invariant(invariant.name))
        case .temporal(let temporal):
          if isTranslatorTermination(temporal) {
            translatorOwnedNames.insert(temporal.name)
          } else if temporal.name == "Termination" {
            throw CompilationDiagnostic(
              code: .duplicateRenderedModuleDefinition,
              stage: .rendering,
              path: componentPath,
              expected: "the translator's standard Termination predicate for this process family",
              actual: "a distinct property named Termination",
              nextSafeAction: "Give the property a distinct name, or declare the standard process termination property."
            )
          } else {
            properties.append(.temporal(temporal.name))
          }
        case .process(let process):
          let nested = try collect(process.components, path: "\(componentPath).components")
          properties += nested.properties
          translatorOwnedNames.formUnion(nested.translatorOwnedNames)
        case .shared, .procedure, .formalOperator, .stateConstraint, .unsupported, .local, .step:
          continue
        }
      }
      return (properties, translatorOwnedNames)
    }

    return try collect(algorithm.components, path: "components")
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

private enum AuthoredPlusCalProperty {
  case invariant(String)
  case temporal(String)

  var name: String {
    switch self {
    case .invariant(let name), .temporal(let name): name
    }
  }

  var bindingPath: String {
    switch self {
    case .invariant(let name): "invariants.\(name).declaration"
    case .temporal(let name): "temporalProperties.\(name).declaration"
    }
  }
}

struct AuthoredPlusCalDeclarationSections {
  let prelude: [String]
  let define: [String]
  let postTranslation: [String]

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
    postTranslation = try order(.postTranslation)
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
