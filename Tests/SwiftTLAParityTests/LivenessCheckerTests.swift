import Foundation
import os
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized)
struct LivenessCheckerTests {
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

  @Test("SCC decomposition finds one twelve-state cycle")
  func singleCycleSCC() throws {
    let compilation = try Example.hourClock.spec.compile()
    let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20, symmetryReduction: .disabled)).explore()
    let lc = compilation.livenessChecker(graph: exploration.graph)
    let sccs = lc.computeSCCs()
    #expect(sccs.count == 1)
    #expect(sccs[0].count == 12)
  }

  @Test("Terminal SCC detection works")
  func terminalSCC() throws {
    let compilation = try Example.hourClock.spec.compile()
    let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20, symmetryReduction: .disabled)).explore()
    let lc = compilation.livenessChecker(graph: exploration.graph)
    let sccs = lc.computeSCCs()
    let terminals = lc.terminalSCCs(from: sccs)
    #expect(terminals.count == 1)
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
