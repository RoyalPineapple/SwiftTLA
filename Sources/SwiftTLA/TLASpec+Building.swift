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
    var constants: [String: TLAValue] = [:]
    var formalParameters: [FormalModuleParameter] = []
    var definitions: [DirectModuleDefinition] = []
    var authoredPlusCalDeclarations: [AuthoredPlusCalDeclaration] = []
    var theorems: [String] = []
    var assumes: StateExpr?
    var extendsMods = "Integers"
    var deadlockFlag = false
    var constraint: StateExpr?
    let recursiveDefs: [String] = []
    var recursiveFuncs: [RecursiveFunc] = []
    var formalOperatorDefinitions: [FormalOperatorDefinition] = []
    let imports = components.compactMap { $0 as? ImportDecl }
    let importedModules = imports.map(\.module)
    let importConfigurations = imports.compactMap(\.configuration)
    let moduleInstances = components.compactMap { $0 as? FormalModuleInstance }
    var runtimeFuncCollector: [String: @Sendable ([TLAValue]) -> TLAValue] = [:]
    var runtimeFuncBodiesCollector: [String] = []
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
        // Retain source-level evidence directly from the builder model; do
        // not lower a second time merely to form a fidelity token.
        algorithmFidelityTokens.append(AlgorithmFidelityToken(model: algorithm.model))
        sourceAlgorithms.append(algorithm)
        do {
          let lowered = try algorithm.lower(
            formalOperatorDefinitions: formalOperatorDefinitions
          )
          variables += lowered.variables
          actions += lowered.actions
          invariants += lowered.invariants
          temporalProperties += lowered.temporalProperties
          fairness += lowered.fairness
          formalOperatorDefinitions += algorithm.model.formalOperatorDefinitions
          for definition in algorithm.model.formalOperatorDefinitions {
            let text = FormalOperatorDecl(definition).tlaText
            definitions.append(.init(
              name: definition.name, text: text, dependencies: definition.plusCalDependencies
            ))
            authoredPlusCalDeclarations.append(AuthoredPlusCalDeclaration(
              name: definition.name, text: text,
              phase: definition.plusCalPhase,
              dependencies: definition.plusCalDependencies
            ))
          }
          if let loweredConstraint = lowered.constraint {
            constraint = constraint.map { .and($0, loweredConstraint) } ?? loweredConstraint
          }
        } catch {
          preconditionFailure("Invalid algorithm '\(algorithm.model.name)': \(error)")
        }
      } else if let i = comp as? InvDecl {
        invariants.append(NamedInvariant(name: i.name, body: i.body))
      } else if let t = comp as? TemporalDecl {
        temporalProperties.append(NamedTemporal(name: t.name, expr: t.expr))
      } else if let f = comp as? FairnessDecl {
        fairness.append(f.condition)
      } else if let c = comp as? ConstantDecl {
        constants[c.name] = c.value
      } else if let parameter = comp as? FormalParameterDecl {
        formalParameters.append(parameter.parameter)
      } else if let d = comp as? DefinitionDecl {
        let text: String
        if let name = d.name, let body = d.body {
          text = "\(name) == \(body)"
        } else {
          text = d.tlaText
        }
        definitions.append(.init(name: d.name, text: text, dependencies: d.plusCalDependencies))
        authoredPlusCalDeclarations.append(AuthoredPlusCalDeclaration(
          name: d.name, text: text, phase: d.plusCalPhase, dependencies: d.plusCalDependencies
        ))
      } else if let definition = comp as? FormalOperatorDecl {
        definitions.append(.init(
          name: definition.definition.name,
          text: definition.tlaText,
          dependencies: definition.definition.plusCalDependencies
        ))
        authoredPlusCalDeclarations.append(AuthoredPlusCalDeclaration(
          name: definition.definition.name, text: definition.tlaText,
          phase: definition.definition.plusCalPhase,
          dependencies: definition.definition.plusCalDependencies
        ))
      } else if let th = comp as? TheoremDecl {
        if !th.tlaText.isEmpty {
          theorems.append(th.tlaText)
        } else if let name = th.name, let body = th.temporalBody {
          theorems.append("\(name) == Spec => \(body)")
        } else if let name = th.name, let body = th.stateBody {
          theorems.append("\(name) == Spec => [](\(body))")
        }
      } else if let a = comp as? AssumeDecl {
        assumes = assumes.map { .and($0, a.expr) } ?? a.expr
      } else if let e = comp as? ExtendsDecl {
        extendsMods = e.modules
      } else if comp is DeadlockDecl {
        deadlockFlag = true
      } else if let c = comp as? ConstraintDecl {
        constraint = constraint.map { .and($0, c.body) } ?? c.body
      } else if let rf = comp as? RecursiveFuncDecl {
        recursiveFuncs.append(rf.funcDef)
      } else if let rtf = comp as? RuntimeFuncDecl {
        runtimeFuncCollector[rtf.name] = rtf.implementation
        runtimeFuncBodiesCollector.append(rtf.tlaBody)
        runtimeFuncBodies.append(rtf.tlaBody)
      } else if let s = comp as? SymmetrySetDecl {
        symmetrySets.append(SymmetrySet(variableName: s.variableName, values: s.values))
      }
    }

    // Auto-UNCHANGED: push into OR branches so TLC sees complete assignments
    let vn = variables.map(\.name)
    actions = actions.map { a in
      NamedAction(name: a.name, body: completeAction(a.body, allVars: vn), bindings: a.bindings)
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
    self.definitions = definitions
    self.authoredPlusCalDeclarations = authoredPlusCalDeclarations
    self.theorems = theorems
    self.extendsModules = extendsMods
    self.constraint = constraint
    self.recursiveDefs = recursiveDefs
    self.recursiveFuncs = recursiveFuncs
    self.formalOperatorDefinitions = formalOperatorDefinitions
    self.imports = importedModules
    self.importConfigurations = importConfigurations
    self.moduleInstances = moduleInstances
    self.runtimeFuncs = runtimeFuncCollector
    self.runtimeFuncBodies = runtimeFuncBodiesCollector
    self.symmetrySets = symmetrySets
    self.symmetricCollections = symmetricCollections
    self.algorithmFidelityTokens = algorithmFidelityTokens
    self.sourceAlgorithms = sourceAlgorithms
  }
}

extension TLASpec {
  /// Renders the sole Algorithm authored in this builder as a PlusCal module.
  /// Direct TLA+ specifications and multi-algorithm source are not silently
  /// split into ad-hoc exports; callers must use a source model with one
  /// compiler-owned root module.
  func renderAuthoredPlusCalModule() throws -> String {
    guard sourceAlgorithms.count == 1, let algorithm = sourceAlgorithms.first else {
      throw AlgorithmPlusCalRenderDiagnostic(
        failedConcept: "authored PlusCal module root",
        path: "TLASpec.sourceAlgorithms",
        expected: "exactly one authored Algorithm",
        actual: "\(sourceAlgorithms.count) authored Algorithms",
        nextSafeAction: "Compile one canonical Algorithm model per exported module."
      )
    }
    let renderer = AlgorithmPlusCalRenderer(model: algorithm.model)
    let sourceProperties = try renderer.sourcePropertyDefinitions()
    let sourcePropertyNames = sourceProperties.map(\.name)
    let loweredPropertyNames = invariants.map(\.name) + temporalProperties.map(\.name)
    guard Set(sourcePropertyNames).count == sourcePropertyNames.count,
          Set(loweredPropertyNames).count == loweredPropertyNames.count,
          Set(sourcePropertyNames).union(renderer.translatorOwnedPropertyNames()) == Set(loweredPropertyNames)
    else {
        throw AlgorithmPlusCalRenderDiagnostic(
          failedConcept: "authored PlusCal property export",
          path: "TLASpec.properties",
          expected: "one retained Algorithm source property for every lowered property",
          actual: "source properties \(sourcePropertyNames); lowered properties \(loweredPropertyNames)",
          nextSafeAction: "Declare properties inside Algorithm, or add a source-level renderer for the top-level declaration before exporting PlusCal."
        )
    }
    let declarationSections = try authoredPlusCalDeclarationSections()
    let module = AuthoredPlusCalModule(
      name: name.replacingOccurrences(of: " ", with: ""),
      extendsModules: authoredPlusCalExtends,
      constants: authoredPlusCalPrelude,
      definitionsBeforeInstances: declarationSections.prelude,
      instances: [],
      definitionsAfterInstances: [],
      algorithm: algorithm.model,
      defineDeclarations: declarationSections.define,
      postTranslationDeclarations: sourceProperties.map(\.definition)
        + authoredPlusCalSymmetry
    )
    return try AlgorithmPlusCalRenderer(model: algorithm.model).render(module)
  }

  private var authoredPlusCalExtends: [String] {
    let requested = extendsModules.split(separator: ",").map {
      $0.trimmingCharacters(in: .whitespaces)
    }
    let symmetryModule = symmetrySets.isEmpty ? [] : ["TLC"]
    return (requested + ["Naturals", "Integers", "Sequences", "FiniteSets"] + symmetryModule + imports.map(\.name))
      .reduce(into: [String]()) { modules, module in
        if !modules.contains(module) { modules.append(module) }
      }
  }

  private var authoredPlusCalPrelude: [String] {
    var lines: [String] = []
    let constantNames = (constants.keys + formalParameters.filter { $0.kind == .constant }.map(\.name)).sorted()
    if !constantNames.isEmpty {
      lines.append("CONSTANTS \(constantNames.joined(separator: ", "))")
    }
    return lines
  }

  private func authoredPlusCalDeclarationSections() throws -> AuthoredPlusCalDeclarationSections {
    let instances = moduleInstances.map { instance in
      let arguments = instance.arguments.map { "\($0.parameter) <- \($0.value)" }.joined(separator: ", ")
      let withClause = arguments.isEmpty ? "" : " WITH \(arguments)"
      return AuthoredPlusCalDeclaration(
        name: instance.name,
        text: "\(instance.name) == INSTANCE \(instance.module.name)\(withClause)",
        phase: instance.plusCalPhase,
        dependencies: instance.plusCalDependencies
      )
    }
    return try AuthoredPlusCalDeclarationSections(authoredPlusCalDeclarations + instances)
  }

  private var authoredPlusCalSymmetry: [String] {
    symmetrySets.map { symmetry in
      let values = symmetry.values.sorted { $0.description < $1.description }
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

public func substituteConstants(_ spec: TLASpec) -> TLASpec {
  let constants = spec.constants
  let vars = spec.variables.map { v in
    NamedVar(
      name: v.name,
      initial: substituteInValue(v.initial, constants: constants),
      initialSet: v.initialSet.map { substituteInState($0, constants: constants) },
      initExpr: v.initExpr.map { substituteInState($0, constants: constants) },
      lazySet: v.lazySet.map { substituteInState($0, constants: constants) },
      collectionType: v.collectionType
    )
  }
  let acts = spec.actions.map { a in
    NamedAction(
      name: a.name, body: substituteInAction(a.body, constants: constants), bindings: a.bindings)
  }
  let invs = spec.invariants.map { i in
    NamedInvariant(name: i.name, body: substituteInState(i.body, constants: constants))
  }
  var resolved = TLASpec(
    name: spec.name,
    variables: vars,
    constants: [:],
    formalParameters: spec.formalParameters,
    actions: acts,
    invariants: invs,
    temporalProperties: spec.temporalProperties.map { t in
      NamedTemporal(name: t.name, expr: substituteInTemporal(t.expr, constants: constants))
    },
    fairness: spec.fairness,
    assume: spec.assume.map { substituteInState($0, constants: constants) },
    checkDeadlock: spec.checkDeadlock,
    definitions: spec.definitions,
    theorems: spec.theorems,
    extendsModules: spec.extendsModules,
    constraint: spec.constraint.map { substituteInState($0, constants: constants) },
    recursiveDefs: spec.recursiveDefs,
    recursiveFuncs: spec.recursiveFuncs,
    formalOperatorDefinitions: spec.formalOperatorDefinitions,
    imports: spec.imports,
    importConfigurations: spec.importConfigurations,
    moduleInstances: spec.moduleInstances,
    symmetrySets: spec.symmetrySets,
    symmetricCollections: spec.symmetricCollections,
    algorithmFidelityTokens: spec.algorithmFidelityTokens,
    sourceAlgorithms: spec.sourceAlgorithms
  )
  resolved.runtimeFuncs = spec.runtimeFuncs
  resolved.runtimeFuncBodies = spec.runtimeFuncBodies
  return resolved
}

private func substituteInValue(_ value: TLAValue, constants: [String: TLAValue]) -> TLAValue {
  if case .constant(let name) = value, let replacement = constants[name] {
    return replacement
  }
  return value
}

private func substituteInState(_ expr: StateExpr, constants: [String: TLAValue]) -> StateExpr {
  switch expr {
  case .value(let v): return .value(substituteInValue(v, constants: constants))
  case .variable: return expr
  case .add(let a, let b):
    return .add(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .subtract(let a, let b):
    return .subtract(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .multiply(let a, let b):
    return .multiply(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .divide(let a, let b):
    return .divide(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .modulo(let a, let b):
    return .modulo(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .negate(let a): return .negate(substituteInState(a, constants: constants))
  case .integerDivide(let a, let b):
    return .integerDivide(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .equal(let a, let b):
    return .equal(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .notEqual(let a, let b):
    return .notEqual(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .lessThan(let a, let b):
    return .lessThan(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .lessOrEqual(let a, let b):
    return .lessOrEqual(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .greaterThan(let a, let b):
    return .greaterThan(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .greaterOrEqual(let a, let b):
    return .greaterOrEqual(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .and(let a, let b):
    return .and(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .or(let a, let b):
    return .or(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .not(let a): return .not(substituteInState(a, constants: constants))
  case .ifThenElse(let c, let t, let f):
    return .ifThenElse(
      substituteInState(c, constants: constants), substituteInState(t, constants: constants),
      substituteInState(f, constants: constants))
  case .setLiteral(let elems):
    return .setLiteral(elems.map { substituteInState($0, constants: constants) })
  case .in(let a, let b):
    return .in(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .subset(let a, let b):
    return .subset(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .union(let a, let b):
    return .union(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .intersection(let a, let b):
    return .intersection(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .setDifference(let a, let b):
    return .setDifference(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .cardinality(let a): return .cardinality(substituteInState(a, constants: constants))
  case .setFilter(let a, let qv, let b):
    return .setFilter(
      substituteInState(a, constants: constants), qv, substituteInState(b, constants: constants))
  case .setMap(let a, let qv, let b):
    return .setMap(
      substituteInState(a, constants: constants), qv, substituteInState(b, constants: constants))
  case .powerSet(let a): return .powerSet(substituteInState(a, constants: constants))
  case .unionAll(let a): return .unionAll(substituteInState(a, constants: constants))
  case .integerRange(let lower, let upper):
    return .integerRange(substituteInState(lower, constants: constants), substituteInState(upper, constants: constants))
  case .tupleLiteral(let elems):
    return .tupleLiteral(elems.map { substituteInState($0, constants: constants) })
  case .tupleAccess(let a, let i):
    return .tupleAccess(substituteInState(a, constants: constants), i)
  case .tupleDynamicAccess(let tuple, let index):
    return .tupleDynamicAccess(substituteInState(tuple, constants: constants), substituteInState(index, constants: constants))
  case .tupleLength(let a): return .tupleLength(substituteInState(a, constants: constants))
  case .tupleAppend(let a, let b):
    return .tupleAppend(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .tupleHead(let t): return .tupleHead(substituteInState(t, constants: constants))
  case .tupleTail(let t): return .tupleTail(substituteInState(t, constants: constants))
  case .tupleConcatenate(let a, let b):
    return .tupleConcatenate(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .recordLiteral(let fields):
    return .recordLiteral(fields.mapValues { substituteInState($0, constants: constants) })
  case .recordAccess(let a, let f):
    return .recordAccess(substituteInState(a, constants: constants), f)
  case .domain(let a): return .domain(substituteInState(a, constants: constants))
  case .functionLiteral(let a, let qv, let b):
    return .functionLiteral(
      substituteInState(a, constants: constants), qv, substituteInState(b, constants: constants))
  case .functionApply(let a, let b):
    return .functionApply(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  case .except(let a, let b, let c):
    return .except(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants),
      substituteInState(c, constants: constants))
  case .caseExpr(let pairs, let other):
    return .caseExpr(
      pairs.map { substituteInState($0, constants: constants) },
      other.map { substituteInState($0, constants: constants) })
  case .forAll(let a, let qv, let b):
    return .forAll(
      substituteInState(a, constants: constants), qv, substituteInState(b, constants: constants))
  case .exists(let a, let qv, let b):
    return .exists(
      substituteInState(a, constants: constants), qv, substituteInState(b, constants: constants))
  case .choose(let a, let qv, let b):
    return .choose(
      substituteInState(a, constants: constants), qv, substituteInState(b, constants: constants))
  case .enabledAction: return expr
  case .sequenceFromSet(let s): return .sequenceFromSet(substituteInState(s, constants: constants))
  case .functionSet(let d, let r):
    return .functionSet(
      substituteInState(d, constants: constants), substituteInState(r, constants: constants))
  case .setSum(let f, let s):
    return .setSum(
      substituteInState(f, constants: constants), substituteInState(s, constants: constants))
  case .recursiveCall(let n, let a):
    return .recursiveCall(n, a.map { substituteInState($0, constants: constants) })
  case .letValue(let name, let value, let body):
    let bodyConstants = constants.filter { $0.key != name }
    return .letValue(
      name,
      substituteInState(value, constants: constants),
      substituteInState(body, constants: bodyConstants)
    )
  case .foldFunction(let operation, let initial, let sequence):
    let bodyConstants = constants.filter { !operation.parameters.contains($0.key) }
    return .foldFunction(
      FormalLambda(
        parameters: operation.parameters,
        body: substituteInState(operation.body, constants: bodyConstants)
      ),
      initial: substituteInState(initial, constants: constants),
      sequence: substituteInState(sequence, constants: constants)
    )
  case .operatorApplication(let operation, let arguments):
    let substitutedOperator: FormalOperator
    switch operation {
    case .lambda(let lambda):
      let bodyConstants = constants.filter { !lambda.parameters.contains($0.key) }
      substitutedOperator = .lambda(
        FormalLambda(
          parameters: lambda.parameters,
          body: substituteInState(lambda.body, constants: bodyConstants)
        )
      )
    case .reference:
      substitutedOperator = operation
    }
    return .operatorApplication(
      substitutedOperator,
      arguments.map { argument in
        switch argument {
        case .value(let expression):
          FormalCallArgument.value(substituteInState(expression, constants: constants))
        case .operator(.reference(let name, let arity)):
          FormalCallArgument.operator(.reference(name, arity: arity))
        case .operator(.lambda(let lambda)):
          FormalCallArgument.operator(.lambda(FormalLambda(
            parameters: lambda.parameters,
            body: substituteInState(lambda.body, constants: constants)
          )))
        }
      }
    )
  case .letIn(let operators, let body):
    return .letIn(
      operators.map { operation in
        let bodyConstants = constants.filter { !operation.parameters.contains($0.key) }
        return LocalOperator(
          operation.name,
          parameters: operation.parameters,
          domain: operation.domain.map { substituteInState($0, constants: constants) },
          body: substituteInState(operation.body, constants: bodyConstants)
        )
      },
      substituteInState(body, constants: constants)
    )
  }
}

private func substituteInAction(_ expr: ActionExpr, constants: [String: TLAValue]) -> ActionExpr {
  switch expr {
  case .assign(let v, let e): return .assign(v, substituteInState(e, constants: constants))
  case .unchanged: return expr
  case .guard_(let e): return .guard_(substituteInState(e, constants: constants))
  case .chooseAction(let v, let s):
    return .chooseAction(v, substituteInState(s, constants: constants))
  case .and(let a, let b):
    return .and(
      substituteInAction(a, constants: constants), substituteInAction(b, constants: constants))
  case .or(let a, let b):
    return .or(
      substituteInAction(a, constants: constants), substituteInAction(b, constants: constants))
  case .ifElse(let c, let t, let e):
    return .ifElse(
      substituteInState(c, constants: constants), substituteInAction(t, constants: constants),
      substituteInAction(e, constants: constants))
  case .define(let v, let exp, let body):
    return .define(
      v, substituteInState(exp, constants: constants),
      substituteInAction(body, constants: constants))
  case .existsAction(let v, let s, let b):
    return .existsAction(
      v, substituteInState(s, constants: constants), substituteInAction(b, constants: constants))
  }
}

public func assignedVars(_ e: ActionExpr) -> Set<String> {
  switch e {
  case .assign(let v, _), .chooseAction(let v, _): return [v]
  case .unchanged, .guard_: return []
  case .and(let a, let b): return assignedVars(a).union(assignedVars(b))
  case .or(let a, let b): return assignedVars(a).union(assignedVars(b))
  case .ifElse(_, let t, let e): return assignedVars(t).union(assignedVars(e))
  case .define(_, _, let b): return assignedVars(b)
  case .existsAction(_, _, let b): return assignedVars(b)
  }
}

public func explicitUnchanged(_ e: ActionExpr) -> Set<String> {
  switch e {
  case .unchanged(let v): return [v]
  case .and(let a, let b): return explicitUnchanged(a).union(explicitUnchanged(b))
  case .or(let a, let b): return explicitUnchanged(a).intersection(explicitUnchanged(b))
  case .ifElse: return []
  case .define: return []
  case .existsAction: return []
  default: return []
  }
}

/// Joint nondeterministic init: two variables from a constrained cross-product.
private func substituteInTemporal(_ expr: TemporalExpr, constants: [String: TLAValue])
  -> TemporalExpr {
  switch expr {
  case .always(let s): return .always(substituteInState(s, constants: constants))
  case .eventually(let s): return .eventually(substituteInState(s, constants: constants))
  case .alwaysEventually(let s):
    return .alwaysEventually(substituteInState(s, constants: constants))
  case .eventuallyAlways(let s):
    return .eventuallyAlways(substituteInState(s, constants: constants))
  case .leadsTo(let a, let b):
    return .leadsTo(
      substituteInState(a, constants: constants), substituteInState(b, constants: constants))
  }
}
