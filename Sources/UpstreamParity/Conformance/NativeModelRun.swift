import SwiftTLA

package struct ModelCheckResults: Equatable, Encodable, Sendable {
  package let properties: [String: PropertyResult]
  /// Nil means deadlock checking was not requested by the model.
  package let deadlock: PropertyResult?

  package init(properties: [String: PropertyResult], deadlock: PropertyResult?) {
    self.properties = properties
    self.deadlock = deadlock
  }

  package var allSatisfied: Bool {
    properties.values.allSatisfy { $0 == .satisfied } && (deadlock == nil || deadlock == .satisfied)
  }
}

package struct NativeModelRun: Sendable {
  package let rendered: RenderedSpecification
  package let graph: GraphRun
  package let checks: ModelCheckResults

  package init(rendered: RenderedSpecification, graph: GraphRun, checks: ModelCheckResults) throws {
    guard Set(checks.properties.keys) == rendered.checkNames,
          (checks.deadlock != nil) == rendered.checksDeadlock else {
      throw EvidenceFormatError.invalidField(record: rendered.tlaBundle.root.name, field: "native check coverage")
    }
    for result in checks.properties.values {
      if case .violated(let trace) = result { try trace.validate(in: graph.graph) }
    }
    if case .violated(let trace)? = checks.deadlock {
      try trace.validate(in: graph.graph)
      guard trace.cycleStartIndex == nil, let final = trace.steps.last,
            !graph.graph.edges.contains(where: { $0.source == final.state }) else {
        throw EvidenceFormatError.invalidField(record: rendered.tlaBundle.root.name, field: "deadlock counterexample")
      }
    }
    self.rendered = rendered
    self.graph = graph
    self.checks = checks
  }

  package init<Machine: StateMachine>(
    _ native: ReachabilityGraph<Machine>, description: CompilationDescription,
    rendered: RenderedSpecification, for finiteGraphCase: FiniteGraphCase? = nil
  ) throws {
    let temporalNames = Set(description.temporalProperties)
    let invariantNames = Set(description.invariants)
    let refinementNames = Set(description.refinements)
    guard temporalNames == Set(native.temporalResults.keys),
          Set(native.refinementFailures.keys).isSubset(of: refinementNames) else {
      throw EvidenceFormatError.invalidField(record: description.name, field: "native property declarations")
    }
    let renderedNames = Dictionary(uniqueKeysWithValues: (finiteGraphCase?.renderedActions ?? rendered.actions).map {
      ($0.sourceInvocationName, $0.renderedName)
    })
    func actionName(_ action: Machine.Action) throws -> String {
      let invocation = try native.formalCall(for: action).description
      return renderedNames[invocation] ?? invocation
    }
    let states = try Dictionary(uniqueKeysWithValues: native.transitions.keys.map {
      ($0, try CanonicalState(native.formalProjection(of: $0)))
    })
    func stateKey(_ snapshot: Machine.Snapshot) throws -> CanonicalStateKey {
      guard let state = states[snapshot] else { throw CanonicalGraphError.missingNativeSnapshot }
      return state.key
    }
    func path(_ steps: [(action: Machine.Action?, state: Machine.Snapshot)]) throws -> GraphTrace {
      GraphTrace(id: "native-path", steps: try steps.map {
        GraphTraceStep(state: try stateKey($0.state), action: try $0.action.map(actionName))
      })
    }
    func lasso(_ witness: FairLassoWitness<Machine.Snapshot, Machine.Action?>) throws -> GraphTrace {
      try GraphTrace(id: "native-lasso", witness: witness, stateKey: stateKey, actionName: actionName)
    }
    var properties = Dictionary(uniqueKeysWithValues:
      (invariantNames.union(refinementNames)).map { ($0, PropertyResult.satisfied) })
    var deadlock: PropertyResult? = Machine.checksDeadlock ? .satisfied : nil
    var paths: [Machine.Snapshot: GraphTrace] = [:]
    func trace(to snapshot: Machine.Snapshot) throws -> GraphTrace {
      if let cached = paths[snapshot] { return cached }
      let result = try path(native.trace(to: snapshot))
      paths[snapshot] = result
      return result
    }
    let failures = try native.safetyViolations.sorted { try stateKey($0.key) < stateKey($1.key) }
    for (snapshot, violations) in failures {
      for violation in violations {
        switch violation {
        case .invariant(let name):
          guard invariantNames.contains(name) else {
            throw EvidenceFormatError.invalidField(record: name, field: "undeclared native invariant")
          }
          if properties[name] == .satisfied { properties[name] = .violated(try trace(to: snapshot)) }
        case .deadlock:
          guard Machine.checksDeadlock else {
            throw EvidenceFormatError.invalidField(record: description.name, field: "unexpected deadlock check")
          }
          if deadlock == .satisfied { deadlock = .violated(try trace(to: snapshot)) }
        }
      }
    }
    for (name, failure) in native.refinementFailures {
      let witness: GraphTrace
      switch failure {
      case .initialState(let snapshot): witness = try trace(to: snapshot)
      case .transition(let source, let action, let target):
        witness = try path(native.trace(to: source) + [(action, target)])
      case .fairness(_, let cycle): witness = try lasso(cycle)
      }
      properties[name] = .violated(witness)
    }
    for (name, analysis) in native.temporalResults {
      switch analysis.status {
      case .satisfied: properties[name] = .satisfied
      case .unavailable: properties[name] = .unavailable
      case .violated:
        guard let witness = analysis.witness else {
          throw EvidenceFormatError.invalidField(record: name, field: "missing native temporal witness")
        }
        properties[name] = .violated(try lasso(witness))
      }
    }
    let canonical = try CanonicalGraph(native, states: states, renderedActionNames: renderedNames)
    let graph = try GraphRun(isComplete: true, graph: canonical,
      observableActions: Set(canonical.edges.map(\.action)), outcome: .noViolation)
    try self.init(rendered: rendered, graph: graph, checks: .init(properties: properties, deadlock: deadlock))
  }
}
