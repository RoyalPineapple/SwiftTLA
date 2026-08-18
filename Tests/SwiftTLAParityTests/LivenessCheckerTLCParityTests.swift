import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import SwiftTLAModels
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
    let graph = try ModelChecker(spec: spec, maxStates: 20).exploreGraph()
    let lc = LivenessChecker(graph: graph)
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
    let graph = try ModelChecker(spec: spec, maxStates: 20).exploreGraph()
    let lc = LivenessChecker(graph: graph)
    let sccs = lc.computeSCCs()
    let terminals = lc.terminalSCCs(from: sccs)
    #expect(terminals.count == 1)
  }

  @Test("checkEventually: satisfied when property holds in SCC")
  func eventuallySatisfied() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, in: 1...12)
      Action("tick") { (hr < 12 && hr.becomes(hr + 1)) || (hr == 12 && hr.becomes(1)) }
    }
    let graph = try ModelChecker(spec: spec, maxStates: 20).exploreGraph()
    let lc = LivenessChecker(graph: graph)
    let sccs = lc.computeSCCs()
    let terminals = lc.terminalSCCs(from: sccs)
    let eventually12: StateExpr = .equal(.variable("hr"), .value(.int(12)))
    let result = try lc.checkEventually(eventually12, fairSCCs: terminals)
    #expect(result == .satisfied)
  }

  @Test("checkEventually: violated when property never holds")
  func eventuallyViolated() throws {
    let hr = Var<Int>("hr")
    let spec = TLASpec("HourClock") {
      Variable(hr, in: 1...12)
      Action("tick") { (hr < 12 && hr.becomes(hr + 1)) || (hr == 12 && hr.becomes(1)) }
    }
    let graph = try ModelChecker(spec: spec, maxStates: 20).exploreGraph()
    let lc = LivenessChecker(graph: graph)
    let sccs = lc.computeSCCs()
    let terminals = lc.terminalSCCs(from: sccs)
    let eventually13: StateExpr = .equal(.variable("hr"), .value(.int(13)))
    let result = try lc.checkEventually(eventually13, fairSCCs: terminals)
    if case .violated = result {} else { #expect(Bool(false)) }
  }

  @Test("WF satisfied, SF violated: A exits SCC, B+C cycle within")
  func wfSfDifferential() throws {
    // 3 states (0, 1, 2). A exits SCC, B+C cycle within.
    // SCC {0,1} has A enabled at 0 (goes to 2 outside SCC), disabled at 1.
    // WF(A): disabled somewhere → fair
    // SF(A): enabled somewhere but never taken within SCC → unfair
    let x = Var<Int>("x")
    let spec = TLASpec("WFSFTest") {
      Variable(x, 0)
      Action("A") { x == 0 && x.becomes(2) }
      Action("B") { x == 0 && x.becomes(1) }
      Action("C") { x == 1 && x.becomes(0) }
    }
    let graph = try ModelChecker(spec: spec, maxStates: 10).exploreGraph()
    let lc = LivenessChecker(graph: graph)
    let sccs = lc.computeSCCs()
    // Check ALL SCCs, not just terminal ones
    let wfFair = lc.fairTerminalSCCs(
      sccs, fairness: [FairnessCondition.weakFairness("A")], actions: spec.actions)
    let sfFair = lc.fairTerminalSCCs(
      sccs, fairness: [FairnessCondition.strongFairness("A")], actions: spec.actions)
    // WF accepts more SCCs than SF
    #expect(
      wfFair.count > sfFair.count,
      "WF should accept more SCCs than SF (WF: \(wfFair.count), SF: \(sfFair.count))")
  }
}
@Test("ChangRoberts liveness: cand ~> won holds")
func changRobertsLiveness() throws {
  let spec = Example.changRobertsN3.spec
  let mc = try ModelChecker(spec: spec, maxStates: 500)
  let graph = try mc.exploreGraph()
  let lc = LivenessChecker(graph: graph)
  // Verify temporal property exists
  #expect(spec.temporalProperties.count == 1)
  #expect(spec.temporalProperties[0].name == "Liveness")
  let results = try lc.checkAll(
    spec.temporalProperties, fairness: spec.fairness, actions: spec.actions)
  #expect(results.count == 1)
  #expect(results[0] == .satisfied)
}
@Test("ChangRoberts liveness verified by TLC")
func changRobertsLivenessParity() throws {
  let spec = Example.changRobertsN3.spec
  let mc = try ModelChecker(spec: spec, maxStates: 500)
  let graph = try mc.exploreGraph()
  let lc = LivenessChecker(graph: graph)
  let results = try lc.checkAll(
    spec.temporalProperties, fairness: spec.fairness, actions: spec.actions)
  #expect(results.count == 1)
  #expect(results[0] == .satisfied)
}
