import SwiftTLA

package struct ModelCheckResults: Equatable, Encodable, Sendable {
  package let properties: [String: PropertyResult]
  /// Nil means neither the model nor the validation configuration requested deadlock checking.
  package let deadlock: PropertyResult?

  package init(properties: [String: PropertyResult], deadlock: PropertyResult?) {
    self.properties = properties
    self.deadlock = deadlock
  }

  package var allSatisfied: Bool {
    properties.values.allSatisfy(\.isSatisfied) && (deadlock == nil || deadlock == .satisfied)
  }
}

package struct NativeModelRun: Sendable {
  package let rendered: RenderedSpecification
  package let graph: GraphRun
  package let checks: ModelCheckResults
  package let reachabilityTargets: [String: Set<CanonicalStateKey>]

  package init(rendered: RenderedSpecification, graph: GraphRun, checks: ModelCheckResults,
    reachabilityTargets: [String: Set<CanonicalStateKey>] = [:]) throws {
    guard Set(checks.properties.keys) == rendered.checkNames,
          Set(reachabilityTargets.keys) == rendered.reachabilityNames,
          (!rendered.checksDeadlock || checks.deadlock != nil) else {
      throw EvidenceFormatError.invalidField(record: rendered.tlaBundle.root.name, field: "native check coverage")
    }
    for (name, result) in checks.properties {
      if let targets = reachabilityTargets[name] {
        guard graph.isComparable, targets.isSubset(of: Set(graph.graph.states.keys)) else {
          throw EvidenceFormatError.invalidField(record: name, field: "reachability graph")
        }
        switch result {
        case .reached(let trace):
          try Self.validateReachabilityWitness(trace, name: name, targets: targets, graph: graph.graph)
        case .unreachable where targets.isEmpty: break
        case .unavailable: break
        default: throw EvidenceFormatError.invalidField(record: name, field: "reachability outcome")
        }
      } else {
        switch result {
        case .violated(let trace): try trace.validate(in: graph.graph)
        case .satisfied, .unavailable: break
        case .reached, .unreachable:
          throw EvidenceFormatError.invalidField(record: name, field: "unexpected reachability outcome")
        }
      }
    }
    if case .reached? = checks.deadlock { throw EvidenceFormatError.invalidField(record: "deadlock", field: "reachability outcome") }
    if case .unreachable? = checks.deadlock { throw EvidenceFormatError.invalidField(record: "deadlock", field: "reachability outcome") }
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
    self.reachabilityTargets = reachabilityTargets
  }

  package func validateReachabilityWitness(_ trace: GraphTrace, for name: String) throws {
    guard let targets = reachabilityTargets[name] else {
      throw EvidenceFormatError.invalidField(record: name, field: "undeclared reachability property")
    }
    try Self.validateReachabilityWitness(trace, name: name, targets: targets, graph: graph.graph)
  }

  private static func validateReachabilityWitness(_ trace: GraphTrace, name: String,
    targets: Set<CanonicalStateKey>, graph: CanonicalGraph) throws {
    try trace.validate(in: graph)
    guard trace.cycleStartIndex == nil, let final = trace.steps.last, targets.contains(final.state) else {
      throw EvidenceFormatError.invalidField(record: name, field: "reachability witness endpoint")
    }
  }

  package init<Machine: StateMachine>(
    _ native: ReachabilityGraph<Machine>,
    rendered: RenderedSpecification, checkingDeadlock: Bool = false, for finiteGraphCase: FiniteGraphCase? = nil
  ) throws {
    guard native.safetyViolations.keys.allSatisfy({ native.transitions.index(forKey: $0) != nil }),
          native.reachabilityTargets.values.allSatisfy({ targets in
            targets.allSatisfy { native.transitions.index(forKey: $0) != nil }
          }) else {
      throw EvidenceFormatError.invalidField(record: rendered.tlaBundle.root.name,
        field: "constraint-boundary counterexamples require evidence beyond the constrained graph")
    }
    let temporalNames = rendered.temporalNames
    let invariantNames = rendered.invariantNames
    let refinementNames = rendered.refinementNames
    let propertyNames = Machine.formalPropertyNames
    func propertyName(_ property: Machine.Property) throws -> String {
      guard let name = propertyNames[property] else {
        throw EvidenceFormatError.invalidField(record: rendered.tlaBundle.root.name, field: "undeclared native property")
      }
      return name
    }
    guard Set(propertyNames.keys) == Set(Machine.Property.allCases),
          Set(propertyNames.values).count == propertyNames.count,
          Set(try native.checking.properties.map(propertyName)) == rendered.checkNames,
          native.checking.checkDeadlock == rendered.checksDeadlock,
          native.behavior == rendered.behavior,
          temporalNames == Set(try native.temporalResults.keys.map(propertyName)),
          rendered.reachabilityNames == Set(try native.reachabilityResults.keys.map(propertyName)),
          Set(try native.refinementFailures.keys.map(propertyName)).isSubset(of: refinementNames) else {
      throw EvidenceFormatError.invalidField(record: rendered.tlaBundle.root.name, field: "native property declarations")
    }
    let renderedNames = Dictionary(uniqueKeysWithValues: (finiteGraphCase?.renderedActions ?? rendered.actions).map {
      ($0.sourceInvocationName, $0.renderedName)
    })
    func actionName(_ action: Machine.Action) throws -> String {
      let invocation = try native.formalCall(for: action).description
      return renderedNames[invocation] ?? invocation
    }
    let projectedStates = try NativeCanonicalStates(native)
    func stateKey(_ snapshot: Machine.Snapshot) throws -> CanonicalStateKey {
      try projectedStates.key(for: snapshot)
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
    var deadlock: PropertyResult? = native.checking.checkDeadlock || checkingDeadlock ? .satisfied : nil
    var paths: [Machine.Snapshot: GraphTrace] = [:]
    func trace(to snapshot: Machine.Snapshot) throws -> GraphTrace {
      if let cached = paths[snapshot] { return cached }
      let result = try path(native.trace(to: snapshot))
      paths[snapshot] = result
      return result
    }
    let reachabilityTargets = try Dictionary(uniqueKeysWithValues: native.reachabilityTargets.map {
      (try propertyName($0.key), try Set($0.value.map(stateKey)))
    })
    for (property, result) in native.reachabilityResults {
      let name = try propertyName(property)
      switch result {
      case .reached(let snapshot): properties[name] = .reached(try trace(to: snapshot))
      case .unreachable: properties[name] = .unreachable
      }
    }
    let failures = try native.safetyViolations.sorted { try stateKey($0.key) < stateKey($1.key) }
    for (snapshot, violations) in failures {
      for violation in violations {
        switch violation {
        case .invariant(let property):
          let name = try propertyName(property)
          guard invariantNames.contains(name) else {
            throw EvidenceFormatError.invalidField(record: name, field: "undeclared native invariant")
          }
          if properties[name] == .satisfied { properties[name] = .violated(try trace(to: snapshot)) }
        case .deadlock:
          guard native.checking.checkDeadlock else {
            throw EvidenceFormatError.invalidField(record: rendered.tlaBundle.root.name, field: "unexpected deadlock check")
          }
          if deadlock == .satisfied { deadlock = .violated(try trace(to: snapshot)) }
        }
      }
    }
    if checkingDeadlock && !native.checking.checkDeadlock {
      if let first = try native.deadlockedStates.min(by: { try stateKey($0) < stateKey($1) }) {
        deadlock = .violated(try trace(to: first))
      }
    }
    for (property, failure) in native.refinementFailures {
      let name = try propertyName(property)
      let witness: GraphTrace
      switch failure {
      case .initialState(let snapshot): witness = try trace(to: snapshot)
      case .transition(let source, let action, let target):
        witness = try path(native.trace(to: source) + [(action, target)])
      case .fairness(_, let cycle): witness = try lasso(cycle)
      }
      properties[name] = .violated(witness)
    }
    for (property, analysis) in native.temporalResults {
      let name = try propertyName(property)
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
    let canonical = try CanonicalGraph(native, projectedStates: projectedStates,
      renderedActionNames: renderedNames)
    let graph = try GraphRun(isComplete: true, graph: canonical,
      observableActions: canonical.observedActions, outcome: .noViolation)
    try self.init(rendered: rendered, graph: graph, checks: .init(properties: properties, deadlock: deadlock),
      reachabilityTargets: reachabilityTargets)
  }
}
