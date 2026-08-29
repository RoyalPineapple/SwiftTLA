import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized)
struct LivenessCheckerTests {
  @Test("A twelve-state cycle forms one strongly connected component")
  func cycleFormsOneStronglyConnectedComponent() throws {
    let position = Var<Int>("position")
    let spec = TLASpec("TwelveStateCycle") {
      Variable(position, in: 1...12)
      Action("advance") {
        (position < 12 && position.becomes(position + 1))
          || (position == 12 && position.becomes(1))
      }
    }
    let compilation = try spec.compile()
    let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20, symmetryReduction: .disabled)).explore()
    let lc = LivenessChecker(compilation: compilation, graph: exploration.graph, states: exploration.compiledStates)
    let sccs = lc.computeSCCs()
    #expect(sccs.count == 1)
    #expect(sccs[0].count == 12)
  }

  @Test("Terminal SCC detection works")
  func terminalSCC() throws {
    let position = Var<Int>("position")
    let spec = TLASpec("TwelveStateCycle") {
      Variable(position, in: 1...12)
      Action("advance") {
        (position < 12 && position.becomes(position + 1))
          || (position == 12 && position.becomes(1))
      }
    }
    let compilation = try spec.compile()
    let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20, symmetryReduction: .disabled)).explore()
    let lc = LivenessChecker(compilation: compilation, graph: exploration.graph, states: exploration.compiledStates)
    let sccs = lc.computeSCCs()
    let terminals = lc.terminalSCCs(from: sccs)
    #expect(terminals.count == 1)
  }

  @Test("Eventually holds when the target belongs to a fair cycle")
  func eventuallySatisfied() throws {
    let position = Var<Int>("position")
    let spec = TLASpec("TwelveStateCycle") {
      Variable(position, in: 1...12)
      let advance = Action("advance") {
        (position < 12 && position.becomes(position + 1))
          || (position == 12 && position.becomes(1))
      }
      advance
      Eventually("reachesTwelve", position == 12)
      WeakFairness(advance)
    }
    let compilation = try spec.compile()
    let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20, symmetryReduction: .disabled)).explore()
    let results = try LivenessChecker(compilation: compilation, graph: exploration.graph, states: exploration.compiledStates)
      .analyze(initialStateIDs: exploration.initialStateIDs)
    #expect(results.map(\.status) == [.satisfied])
  }

  @Test("Eventually fails when the target is unreachable")
  func eventuallyViolated() throws {
    let position = Var<Int>("position")
    let spec = TLASpec("TwelveStateCycle") {
      Variable(position, in: 1...12)
      Action("advance") {
        (position < 12 && position.becomes(position + 1))
          || (position == 12 && position.becomes(1))
      }
      Eventually("reachesThirteen", position == 13)
    }
    let compilation = try spec.compile()
    let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 20, symmetryReduction: .disabled)).explore()
    let results = try LivenessChecker(compilation: compilation, graph: exploration.graph, states: exploration.compiledStates)
      .analyze(initialStateIDs: exploration.initialStateIDs)
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
    let initialStateIDs = exploration.initialStateIDs
    let weak = try #require(
      LivenessChecker(compilation: weakCompilation, graph: exploration.graph, states: exploration.compiledStates)
        .analyze(initialStateIDs: initialStateIDs).first
    )
    let strongCompilation = try strongSpec.compile()
    let strongExploration = try ModelChecker(
      compilation: strongCompilation,
      configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10, symmetryReduction: .disabled)
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
@Test("ChangRoberts compilation preserves and satisfies cand ~> won")
func changRobertsLiveness() throws {
  let spec = Example.changRobertsN3.spec
  let compilation = try spec.compile()
  let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 500, symmetryReduction: .disabled)).explore()
  let lc = LivenessChecker(compilation: compilation, graph: exploration.graph, states: exploration.compiledStates)
  #expect(compilation.description.temporalProperties == ["Liveness"])
  let result = try #require(lc.analyze(initialStateIDs: exploration.initialStateIDs).first)
  #expect(result.status == .satisfied)
}
