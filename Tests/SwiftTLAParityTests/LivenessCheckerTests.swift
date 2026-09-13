import os
@testable import SwiftTLA
import Testing

@Suite(.serialized)
struct LivenessCheckerTests {
  @Test("deep transition graphs do not consume the call stack")
  func deepTransitionGraph() throws {
    let count = 20_000
    let states = Set(0...count)
    let transitions = Dictionary(uniqueKeysWithValues: (0...count).map { state in
      (state, [GraphEdge(source: state, action: 0, target: state == count ? 1 : state + 1)])
    })
    let checker = LivenessChecker<Int, Int, Int>(states: states, transitions: transitions,
      fairness: [], matches: { $0 == $1 }, actionOrder: { $0 < $1 }, stateOrder: { $0 < $1 })
    let result = try checker.analyze(.always { _ in true }, initialStates: [0], renderScope: { _ in "step" })
    #expect(result.status == .satisfied)
    #expect(result.witness == nil)
    #expect(Set(result.fairComponents) == [Set([0]), Set(1...count)])
  }

  @Test("impossible counterexamples retain fairness diagnostics without searching cycles")
  func skipsImpossibleCounterexampleSearch() throws {
    let matchCount = OSAllocatedUnfairLock(initialState: 0)
    let checker = LivenessChecker<Int, Int, Int>(states: [0, 1], transitions: [
      0: [.init(source: 0, action: 1, target: 1)],
      1: [.init(source: 1, action: 1, target: 0)]
    ], fairness: [(scope: 1, isStrong: false)], matches: { action, scope in
      matchCount.withLock { $0 += 1 }
      return action == scope
    }, actionOrder: { $0 < $1 }, stateOrder: { $0 < $1 })
    let properties: [TemporalCondition<@Sendable (Int) throws -> Bool>] = [
      .always { _ in true },
      .eventuallyAlways { _ in true },
      .leadsTo({ _ in false }, { _ in false })
    ]
    for property in properties {
      matchCount.withLock { $0 = 0 }
      let result = try checker.analyze(property, initialStates: [0], renderScope: { _ in "step" })
      #expect(result.status == .satisfied)
      #expect(result.witness == nil)
      #expect(result.fairComponents == [Set([0, 1])])
      #expect(result.enabledActions == ["step": [0: true, 1: true]])
      // One match establishes that the component is fair; no cycle search is needed.
      #expect(matchCount.withLock { $0 } == 1)
    }
  }

  @Test("fairness enabledness is computed once across property checks")
  func sharesFairnessEnabledness() throws {
    let first = "first"
    let second = "second"
    let matchCount = OSAllocatedUnfairLock(initialState: 0)
    let checker = LivenessChecker<String, Int, Int>(states: [first, second], transitions: [
      first: [GraphEdge(source: first, action: 1, target: second)],
      second: [GraphEdge(source: second, action: 1, target: first)]
    ], fairness: [(scope: 1, isStrong: false)], matches: { action, scope in
      matchCount.withLock { $0 += 1 }
      return action == scope
    }, actionOrder: { $0 < $1 }, stateOrder: { $0 < $1 })
    #expect(matchCount.withLock { $0 } == 2)
    for _ in 0..<2 {
      let result = try checker.analyze(.eventually { _ in true },
        initialStates: [first], renderScope: { _ in "step" })
      #expect(result.status == .satisfied)
    }
    #expect(matchCount.withLock { $0 } == 2)
  }

  @Test("refinement cycle filtering preserves concrete fairness and unrestricted prefixes", arguments: [false, true])
  func refinementFairnessCycle(_ strongConcreteFairness: Bool) throws {
    let checker = LivenessChecker<String, String, String>(states: ["start", "on", "off", "exit"], transitions: [
      "start": [.init(source: "start", action: "enter", target: "on")],
      "on": [.init(source: "on", action: "leave", target: "exit"),
             .init(source: "on", action: "toggle", target: "off")],
      "off": [.init(source: "off", action: "toggle", target: "on")],
      "exit": []
    ], fairness: [(scope: "leave", isStrong: strongConcreteFairness)], matches: { $0 == $1 },
      actionOrder: { $0 < $1 }, stateOrder: { $0 < $1 })
    for strongAbstractFairness in [false, true] {
      let witness = checker.fairnessViolation(initialStates: ["start"],
        isStrong: strongAbstractFairness, enabledStates: ["on"],
        takesAction: { $0 == "start" || $1 == "exit" })
      if strongAbstractFairness && !strongConcreteFairness {
        let trace = try #require(witness)
        #expect(trace.prefix.first == "start")
        #expect(Set(trace.cycle) == ["on", "off"])
      } else {
        #expect(witness == nil)
      }
    }
  }

  @Test("Eventually holds when the target belongs to a fair cycle")
  func eventuallySatisfied() throws {
    let position = Var<Int>("position")
    let spec = TLASpec("FairCycle") {
      Variable(position, in: 1...12)
      let advance = Action("advance") {
        (position < 12 && position.becomes(position + 1)) ||
          (position == 12 && position.becomes(1))
      }
      advance
      Eventually("reachesTwelve", position == 12)
      WeakFairness(advance)
    }
    let compilation = try spec.compile()
    let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20, symmetryReduction: .disabled)).explore()
    let results = try exploration.analyzeTemporalProperties(in: compilation)
    #expect(results.map(\.status) == [.satisfied])
  }

  @Test("Eventually fails when the target is unreachable")
  func eventuallyViolated() throws {
    let position = Var<Int>("position")
    let spec = TLASpec("CycleWithUnreachableProperty") {
      Variable(position, in: 1...12)
      Action("advance") {
        (position < 12 && position.becomes(position + 1)) ||
          (position == 12 && position.becomes(1))
      }
      Eventually("reachesThirteen", position == 13)
    }
    let compilation = try spec.compile()
    let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20, symmetryReduction: .disabled)).explore()
    let results = try exploration.analyzeTemporalProperties(in: compilation)
    #expect(results.map(\.status) == [.violated])
  }

  @Test("WF satisfied, SF violated: A exits SCC, B+C cycle within")
  func wfSfDifferential() throws {
    let x = Var<Int>("x")
    let weakSpec = TLASpec("WFSFTest") {
      Variable(x, 0)
      let a = Action("A") { x == 0 && x.becomes(2) }
      a
      Action("B") { x == 0 && x.becomes(1) }
      Action("C") { x == 1 && x.becomes(0) }
      AlwaysEventually("neverThree", x == 3)
      WeakFairness(a)
    }
    let strongSpec = TLASpec("WFSFTest") {
      Variable(x, 0)
      let a = Action("A") { x == 0 && x.becomes(2) }
      a
      Action("B") { x == 0 && x.becomes(1) }
      Action("C") { x == 1 && x.becomes(0) }
      AlwaysEventually("neverThree", x == 3)
      StrongFairness(a)
    }
    let weakCompilation = try weakSpec.compile()
    let exploration = try ModelChecker(compilation: weakCompilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10, symmetryReduction: .disabled)).explore()
    let weak = try #require(
      exploration.analyzeTemporalProperties(in: weakCompilation).first
    )
    let strongCompilation = try strongSpec.compile()
    let strongExploration = try ModelChecker(
      compilation: strongCompilation,
      configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10, symmetryReduction: .disabled)
    ).explore()
    let strong = try #require(
      strongExploration.analyzeTemporalProperties(in: strongCompilation).first
    )
    let xToken = try #require(TLAStateProjection.Token(validating: "x"))
    let cycle = Set(exploration.graph.states.compactMap { id, projection in
      let value = projection.value(for: xToken)
      return value == .int(0) || value == .int(1) ? id : nil
    })
    #expect(weak.fairComponents.contains(cycle))
    #expect(strong.rejectedComponents.contains(cycle))
  }
}
