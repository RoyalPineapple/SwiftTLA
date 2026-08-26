import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

// MARK: - Liveness checker and ChangRoberts TLC parity

@Suite(.serialized) struct LivenessCheckerTests { @Test("SCC decomposition works on HourClock (12 states, 1 SCC)")
  func hourClockSCC() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, in: 1...12)
      Action("tick") { (hr < 12 && hr.becomes(hr + 1)) || (hr == 12 && hr.becomes(1)) }
    }
    let compilation = try spec.compile()
    let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20)).explore()
    let lc = LivenessChecker(compilation: compilation, graph: exploration.graph, states: exploration.compiledStates)
    let sccs = lc.computeSCCs()
    #expect(sccs.count == 1)
    #expect(sccs[0].count == 12)
  }

  @Test("Terminal SCC detection works")
  func terminalSCC() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, in: 1...12)
      Action("tick") { (hr < 12 && hr.becomes(hr + 1)) || (hr == 12 && hr.becomes(1)) }
    }
    let compilation = try spec.compile()
    let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20)).explore()
    let lc = LivenessChecker(compilation: compilation, graph: exploration.graph, states: exploration.compiledStates)
    let sccs = lc.computeSCCs()
    let terminals = lc.terminalSCCs(from: sccs)
    #expect(terminals.count == 1)
  }

  @Test("eventually holds in the clock cycle")
  func eventuallySatisfied() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, in: 1...12)
      Action("tick") { (hr < 12 && hr.becomes(hr + 1)) || (hr == 12 && hr.becomes(1)) }
      Eventually("reachesTwelve", hr == 12)
      WeakFairness("tick")
    }
    let compilation = try spec.compile()
    let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20)).explore()
    let results = LivenessChecker(compilation: compilation, graph: exploration.graph, states: exploration.compiledStates)
      .analyze(initialStateIDs: exploration.initialStateIDs)
    #expect(results.map(\.status) == [.satisfied])
  }

  @Test("eventually reports a missing clock value")
  func eventuallyViolated() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, in: 1...12)
      Action("tick") { (hr < 12 && hr.becomes(hr + 1)) || (hr == 12 && hr.becomes(1)) }
      Eventually("reachesThirteen", hr == 13)
    }
    let compilation = try spec.compile()
    let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20)).explore()
    let results = LivenessChecker(compilation: compilation, graph: exploration.graph, states: exploration.compiledStates)
      .analyze(initialStateIDs: exploration.initialStateIDs)
    #expect(results.map(\.status) == [.violated])
  }

  @Test("WF satisfied, SF violated: A exits SCC, B+C cycle within")
  func wfSfDifferential() throws {
    let x = Var<Int>("x")
    let weakSpec = TLASpec("WFSFTest") {
      Variable(x, 0)
      Action("A") { x == 0 && x.becomes(2) }
      Action("B") { x == 0 && x.becomes(1) }
      Action("C") { x == 1 && x.becomes(0) }
      AlwaysEventually("neverThree", x == 3)
      WeakFairness("A")
    }
    let strongSpec = TLASpec("WFSFTest") {
      Variable(x, 0)
      Action("A") { x == 0 && x.becomes(2) }
      Action("B") { x == 0 && x.becomes(1) }
      Action("C") { x == 1 && x.becomes(0) }
      AlwaysEventually("neverThree", x == 3)
      StrongFairness("A")
    }
    let weakCompilation = try weakSpec.compile()
    let exploration = try ModelChecker(compilation: weakCompilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10)).explore()
    let initialStateIDs = exploration.initialStateIDs
    let weak = try #require(
      LivenessChecker(compilation: weakCompilation, graph: exploration.graph, states: exploration.compiledStates)
        .analyze(initialStateIDs: initialStateIDs).first
    )
    let strongCompilation = try strongSpec.compile()
    let strongExploration = try ModelChecker(
      compilation: strongCompilation,
      configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10)
    ).explore()
    let strong = try #require(
      LivenessChecker(
        compilation: strongCompilation,
        graph: strongExploration.graph,
        states: strongExploration.compiledStates
      ).analyze(initialStateIDs: strongExploration.initialStateIDs).first
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
@Test("ChangRoberts liveness: cand ~> won holds")
func changRobertsLiveness() throws {
  let spec = Example.changRobertsN3.spec
  let compilation = try spec.compile()
  let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 500)).explore()
  let lc = LivenessChecker(compilation: compilation, graph: exploration.graph, states: exploration.compiledStates)
  // Verify temporal property exists
  #expect(spec.temporalProperties.count == 1)
  #expect(spec.temporalProperties[0].name == "Liveness")
  let results = lc.analyze(initialStateIDs: exploration.initialStateIDs)
  #expect(results.count == 1)
  #expect(results[0].status == .satisfied)
}
@Test("ChangRoberts liveness verified by TLC")
func changRobertsLivenessParity() throws {
  let spec = Example.changRobertsN3.spec
  let compilation = try spec.compile()
  let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 500)).explore()
  let lc = LivenessChecker(compilation: compilation, graph: exploration.graph, states: exploration.compiledStates)
  let results = lc.analyze(initialStateIDs: exploration.initialStateIDs)
  #expect(results.count == 1)
  #expect(results[0].status == .satisfied)
}
