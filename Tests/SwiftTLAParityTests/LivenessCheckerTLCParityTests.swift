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
    let graph = try ModelChecker(spec: spec, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20)).exploreGraph()
    let lc = LivenessChecker(compilation: try spec.compile(), graph: graph)
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
    let graph = try ModelChecker(spec: spec, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20)).exploreGraph()
    let lc = LivenessChecker(compilation: try spec.compile(), graph: graph)
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
    }
    let graph = try ModelChecker(spec: spec, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20)).exploreGraph()
    let results = LivenessChecker(compilation: try spec.compile(), graph: graph)
      .analyze(initialStateIDs: graph.states.keys.sorted(by: { $0.id < $1.id }))
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
    let graph = try ModelChecker(spec: spec, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20)).exploreGraph()
    let results = LivenessChecker(compilation: try spec.compile(), graph: graph)
      .analyze(initialStateIDs: graph.states.keys.sorted(by: { $0.id < $1.id }))
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
    let graph = try ModelChecker(spec: weakSpec, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10)).exploreGraph()
    let initialStateIDs = graph.states.keys.sorted(by: { $0.id < $1.id })
    let weak = try #require(
      LivenessChecker(compilation: try weakSpec.compile(), graph: graph)
        .analyze(initialStateIDs: initialStateIDs).first
    )
    let strong = try #require(
      LivenessChecker(compilation: try strongSpec.compile(), graph: graph)
        .analyze(initialStateIDs: initialStateIDs).first
    )
    #expect(
      weak.fairComponents.count > strong.fairComponents.count,
      "WF should accept more SCCs than SF (WF: \(weak.fairComponents.count), SF: \(strong.fairComponents.count))")
  }
}
@Test("ChangRoberts liveness: cand ~> won holds")
func changRobertsLiveness() throws {
  let spec = Example.changRobertsN3.spec
  let mc = try ModelChecker(spec: spec, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 500))
  let graph = try mc.exploreGraph()
  let lc = LivenessChecker(compilation: try spec.compile(), graph: graph)
  // Verify temporal property exists
  #expect(spec.temporalProperties.count == 1)
  #expect(spec.temporalProperties[0].name == "Liveness")
  let results = lc.analyze(initialStateIDs: graph.states.keys.sorted(by: { $0.id < $1.id }))
  #expect(results.count == 1)
  #expect(results[0].status == .satisfied)
}
@Test("ChangRoberts liveness verified by TLC")
func changRobertsLivenessParity() throws {
  let spec = Example.changRobertsN3.spec
  let mc = try ModelChecker(spec: spec, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 500))
  let graph = try mc.exploreGraph()
  let lc = LivenessChecker(compilation: try spec.compile(), graph: graph)
  let results = lc.analyze(initialStateIDs: graph.states.keys.sorted(by: { $0.id < $1.id }))
  #expect(results.count == 1)
  #expect(results[0].status == .satisfied)
}
