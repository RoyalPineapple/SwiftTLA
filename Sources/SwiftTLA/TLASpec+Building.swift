extension TLASpec {
  public init(
    _ name: String, parserTree: ParsedSpecModel? = nil,
    @SpecBuilder _ builder: () -> [SpecComponent]
  ) {
    let components = builder()
    var variables: [NamedVar] = []
    var actions: [NamedAction] = []
    var invariants: [NamedInvariant] = []
    var temporalProperties: [NamedTemporal] = []
    var fairness: [FairnessCondition] = []
    var constants: [String: TLAValue] = [:]
    var definitions: [String] = []
    var theorems: [String] = []
    var assumes: StateExpr?
    var extendsMods = "Integers"
    var deadlockFlag = false
    var constraint: StateExpr?
    var recursiveDefs: [String] = []
    var recursiveFuncs: [RecursiveFunc] = []
    var useSpecs: [TLASpec] = []
    var runtimeFuncCollector: [String: @Sendable ([TLAValue]) -> TLAValue] = [:]
    var runtimeFuncBodiesCollector: [String] = []
    var symmetrySets: [SymmetrySet] = []
    var symmetryGroups: [SymmetryVariableGroup] = []
    var symmetricCollections: [SymmetricCollectionDecl] = []
    var operators: [String: OpDecl] = [:]

    // Pass 1: collect operators
    for comp in components {
      if let op = comp as? OpDecl { operators[op.name] = op }
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
        do {
          let lowered = try algorithm.lower()
          variables += lowered.variables
          actions += lowered.actions
          invariants += lowered.invariants
          fairness += lowered.fairness
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
      } else if let d = comp as? DefinitionDecl {
        if let name = d.name, let body = d.body {
          definitions.append("\(name) == \(body)")
        } else {
          definitions.append(d.tlaText)
        }
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
      } else if let r = comp as? RecursiveDecl {
        recursiveDefs.append(r.tlaText)
      } else if let rf = comp as? RecursiveFuncDecl {
        recursiveFuncs.append(rf.funcDef)
      } else if let u = comp as? UseDecl {
        useSpecs.append(u.spec)
      } else if let rtf = comp as? RuntimeFuncDecl {
        runtimeFuncCollector[rtf.name] = rtf.implementation
        runtimeFuncBodiesCollector.append(rtf.tlaBody)
        runtimeFuncBodies.append(rtf.tlaBody)
      } else if let s = comp as? SymmetryVariableGroupDecl {
        symmetryGroups.append(SymmetryVariableGroup(s.names))
      } else if let s = comp as? SymmetrySetDecl {
        symmetrySets.append(SymmetrySet(variableName: s.variableName, values: s.values))
      } else if comp is OpDecl {
        // collected in pass 1
      } else if let u = comp as? UseSpecDecl {
        if let spec = SpecRegistry.lookup(u.name) {
          variables += spec.variables
          invariants += spec.invariants
        }
      } else if let u = comp as? OpUse {
        if let op = operators[u.op] {
          let body: ActionExpr
          let name: String
          if let val = u.value {
            body = substituteActionVar(op.params[0], with: val, in: op.body)
            name = "\(u.op)_\(val)"
          } else {
            body = renameVar(op.params[0], to: u.varName, in: op.body)
            name = "\(u.op)_\(u.varName)"
          }
          actions.append(NamedAction(name: name, body: body))
        }
      }
    }

    // Apply Use(spec) — compose used specs into this one
    for used in useSpecs {
      variables += used.variables
      actions += used.actions
      invariants += used.invariants
      constants.merge(used.constants) { $1 }
      definitions += used.definitions
      recursiveDefs += used.recursiveDefs
      recursiveFuncs += used.recursiveFuncs
      if let c = used.constraint { constraint = constraint.map { .and($0, c) } ?? c }
      if let a = used.assume { assumes = assumes.map { .and($0, a) } ?? a }
      symmetrySets += used.symmetrySets
      symmetricCollections += used.symmetricCollections
    }

    if let tree = parserTree {
      let built = ParsedSpecModel(
        variables: variables.map { ($0.name, $0.initial) },
        actions: actions.map { ($0.name, $0.body, $0.bindings) },
        invariants: invariants.map { ($0.name, $0.body) }
      )
      guard _tlaAlphaEquivalent(built, tree) else {
        fatalError(
          "SpecParser tree mismatch for '\(name)'. " +
            _tlaFidelityDiagnostic(tree, built)
        )
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
    self.actions = actions
    self.invariants = invariants
    self.temporalProperties = temporalProperties
    self.fairness = fairness
    self.assume = assumes
    self.checkDeadlock = deadlockFlag
    self.definitions = definitions
    self.theorems = theorems
    self.extendsModules = extendsMods
    self.constraint = constraint
    self.recursiveDefs = recursiveDefs
    self.recursiveFuncs = recursiveFuncs
    self.runtimeFuncs = runtimeFuncCollector
    self.runtimeFuncBodies = runtimeFuncBodiesCollector
    self.symmetrySets = symmetrySets
    self.symmetryGroups = symmetryGroups
    self.symmetricCollections = symmetricCollections
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
    symmetrySets: spec.symmetrySets,
    symmetryGroups: spec.symmetryGroups,
    symmetricCollections: spec.symmetricCollections
  )
  resolved.runtimeFuncs = spec.runtimeFuncs
  resolved.runtimeFuncBodies = spec.runtimeFuncBodies
  return resolved
}

private func substituteActionVar(_ name: String, with value: TLAValue, in expr: ActionExpr)
  -> ActionExpr {
  substituteVar(name, with: value, in: expr)
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
  case .tupleLiteral(let elems):
    return .tupleLiteral(elems.map { substituteInState($0, constants: constants) })
  case .tupleAccess(let a, let i):
    return .tupleAccess(substituteInState(a, constants: constants), i)
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
