import os
@testable import SwiftTLA
import Testing

@Suite(.serialized)
struct LivenessCheckerTests {
  @Test("fairness ignores changes outside its projection, including conditional properties", arguments: [false, true])
  func projectedEnabledness(_ strong: Bool) throws {
    let transitions: [Int: [GraphEdge<Int, Int>]] = [
      0: [.init(source: 0, action: 1, target: 1)],
      1: [.init(source: 1, action: 1, target: 0)]
    ]
    let checker = LivenessChecker<Int, Int, Int>(states: [0, 1], transitions: transitions,
      fairness: [(scope: 1, isStrong: strong)], matches: { $0 == $1 },
      changes: { before, after, _ in before / 2 != after / 2 },
      actionOrder: { $0 < $1 }, stateOrder: { $0 < $1 })
    let eventually: TemporalCondition<@Sendable (Int, Int) throws -> Bool> = .eventually { state, _ in state == 1 }
    for property in [eventually, .conditional({ _, _ in true }, then: eventually, else: .always { _, _ in true })] {
      let result = try checker.analyze(property, initialStates: [0], renderScope: { _ in "projected" })
      #expect(result.status == .violated)
      #expect(result.enabledActions == ["projected": [0: false, 1: false]])
      let witness = try #require(result.witness)
      #expect(witness.cycle == [0, 0])
      #expect(witness.cycleActions == [nil])
    }
    let wholeState = LivenessChecker<Int, Int, Int>(states: [0, 1], transitions: transitions,
      fairness: [(scope: 1, isStrong: strong)], matches: { $0 == $1 },
      actionOrder: { $0 < $1 }, stateOrder: { $0 < $1 })
    #expect(try wholeState.analyze(eventually, initialStates: [0], renderScope: { _ in "whole" }).status == .satisfied)
  }

  @Test("projection-stuttering edges cannot discharge an enabled fairness obligation", arguments: [false, true])
  func projectedProgress(_ strong: Bool) throws {
    let checker = LivenessChecker<Int, Int, Int>(states: [0, 1, 2], transitions: [
      0: [.init(source: 0, action: 1, target: 1), .init(source: 0, action: 1, target: 2)],
      1: [.init(source: 1, action: 1, target: 0), .init(source: 1, action: 1, target: 2)],
      2: []
    ], fairness: [(scope: 1, isStrong: strong)], matches: { $0 == $1 },
      changes: { before, after, _ in before / 2 != after / 2 },
      actionOrder: { $0 < $1 }, stateOrder: { $0 < $1 })
    let result = try checker.analyze(.eventually { state, _ in state == 2 },
      initialStates: [0], renderScope: { _ in "projected" })
    #expect(result.status == .satisfied)
    #expect(result.witness == nil)
    #expect(result.enabledActions == ["projected": [0: true, 1: true, 2: false]])
    #expect(result.rejectedComponents.contains([0, 1]))
  }

  @Test("deep transition graphs do not consume the call stack")
  func deepTransitionGraph() throws {
    let count = 20_000
    let states = Set(0...count)
    let transitions = Dictionary(uniqueKeysWithValues: (0...count).map { state in
      (state, [GraphEdge(source: state, action: 0, target: state == count ? 1 : state + 1)])
    })
    let checker = LivenessChecker<Int, Int, Int>(states: states, transitions: transitions,
      fairness: [], matches: { $0 == $1 }, actionOrder: { $0 < $1 }, stateOrder: { $0 < $1 })
    let result = try checker.analyze(.always { _, _ in true }, initialStates: [0], renderScope: { _ in "step" })
    #expect(result.status == .satisfied)
    #expect(result.witness == nil)
    #expect(Set(result.fairComponents) == [Set([0]), Set(1...count)])
  }

  @Test("impossible counterexamples retain only relevant fairness diagnostics")
  func skipsImpossibleCounterexampleSearch() throws {
    let checker = LivenessChecker<Int, Int, Int>(states: [0, 1], transitions: [
      0: [.init(source: 0, action: 1, target: 1)],
      1: [.init(source: 1, action: 1, target: 0)]
    ], fairness: [(scope: 1, isStrong: false)], matches: { $0 == $1 },
      actionOrder: { $0 < $1 }, stateOrder: { $0 < $1 })
    let cases: [(property: TemporalCondition<@Sendable (Int, Int) throws -> Bool>, fairComponents: [Set<Int>])] = [
      (.always { _, _ in true }, [Set([0, 1])]),
      (.eventuallyAlways { _, _ in true }, [Set([0, 1])]),
      (.leadsTo({ _, _ in false }, { _, _ in false }), [])
    ]
    for (property, fairComponents) in cases {
      let result = try checker.analyze(property, initialStates: [0], renderScope: { _ in "step" })
      #expect(result.status == .satisfied)
      #expect(result.witness == nil)
      #expect(result.fairComponents == fairComponents)
      #expect(result.enabledActions == ["step": [0: true, 1: true]])
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
      let result = try checker.analyze(.eventually { _, _ in true },
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

  @Test("a fair cycle reaches its member but not an absent target")
  func eventualTargetsInFairCycle() throws {
    let states = Set(1...12)
    let transitions = Dictionary(uniqueKeysWithValues: states.map { state in
      (state, [GraphEdge(source: state, action: 0, target: state == 12 ? 1 : state + 1)])
    })
    let checker = LivenessChecker<Int, Int, Int>(states: states, transitions: transitions,
      fairness: [(scope: 0, isStrong: false)], matches: { $0 == $1 },
      actionOrder: { $0 < $1 }, stateOrder: { $0 < $1 })
    #expect(try checker.analyze(.eventually { state, _ in state == 12 },
      initialStates: [1], renderScope: { _ in "advance" }).status == .satisfied)
    #expect(try checker.analyze(.eventually { state, _ in state == 13 },
      initialStates: [1], renderScope: { _ in "advance" }).status == .violated)
  }

  @Test("WF satisfied, SF violated: A exits SCC, B+C cycle within")
  func wfSfDifferential() throws {
    let transitions: [Int: [GraphEdge<Int, String>]] = [
      0: [.init(source: 0, action: "A", target: 2), .init(source: 0, action: "B", target: 1)],
      1: [.init(source: 1, action: "C", target: 0)],
      2: []
    ]
    func analyze(strong: Bool) throws -> TemporalAnalysis<Int, String?> {
      let checker = LivenessChecker<Int, String, String>(states: [0, 1, 2], transitions: transitions,
        fairness: [(scope: "A", isStrong: strong)], matches: { $0 == $1 },
        actionOrder: { $0 < $1 }, stateOrder: { $0 < $1 })
      return try checker.analyze(.alwaysEventually { state, _ in state == 3 },
        initialStates: [0], renderScope: { $0 })
    }
    #expect(try analyze(strong: false).fairComponents.contains([0, 1]))
    #expect(try analyze(strong: true).rejectedComponents.contains([0, 1]))
  }
}
