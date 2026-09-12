import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct ReachableGraphContractTests {
  @Test("HourClock canonical model has its declared reachable graph")
  func hourClockCanonicalGraph() throws {
    let fixture = Example.hourClock
    let graph = try ModelChecker(
      compilation: fixture.spec.compile(),
      configuration: try .init(maximumStateLimit: fixture.maximumStateLimit, symmetryReduction: .disabled)
    ).exploreGraph()
    #expect(graph.states.count == fixture.expectedDistinct)
  }

  @Test("DieHard canonical model has its declared reachable graph")
  func dieHardCanonicalGraph() throws {
    let fixture = Example.dieHardTypeOK
    let graph = try ModelChecker(
      compilation: fixture.spec.compile(),
      configuration: try .init(maximumStateLimit: fixture.maximumStateLimit, symmetryReduction: .disabled)
    ).exploreGraph()
    #expect(graph.states.count == fixture.expectedDistinct)
  }

  @Test("Allocator = 4 states")
  func allocator4() throws {
    let a = Var<Int>("available")
    let b = Var<Int>("allocated")
    let spec = TLASpec("allocator") {
      Variable(a, 3)
      Variable(b, 0)
      Action("Allocate") { a.becomes(a - 1).when(a > 0) && b.becomes(b + 1) }
      Action("Deallocate") { a.becomes(a + 1).when(b > 0) && b.becomes(b - 1) }
      Invariant("ResourceCount") { a + b == 3 }
    }
    #expect(try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph().states.count == 4)
    let checkOutcome = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check()
    #expect({ if case .ok = checkOutcome { true } else { false } }())
  }

  @Test("CoffeeCan MaxBeanCount=5 = 20 states (parity catalog)")
  func coffeeCanMax5() throws {
    let count = try ModelChecker(compilation: try Example.coffeeCanMax5.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 500, symmetryReduction: .disabled))
      .exploreGraph().states.count
    #expect(count == 20)
  }

  @Test("Chameneos has every typed initial creature-color assignment")
  func chameneosInitialStates() throws {
    let compilation = try Example.chameneosM4N4.spec.compile()
    let states = try CompiledRuntime(compilation: compilation).initialStates()
    #expect(states.count == 81)
    #expect(throws: GeneratedMachineError.ambiguousInitialState) { try ChameneosModel.makeMachine() }
    let native = try ChameneosModel.makeMachine(.init(chameneoses: [
      .one: .init(first: .blue, second: 0), .two: .init(first: .red, second: 0),
      .three: .init(first: .yellow, second: 0), .four: .init(first: .blue, second: 0)
    ], meetingPlace: 0, numMeetings: 0))
    #expect(try native.violatedInvariants().isEmpty)
    #expect(try native.enabledActions().count == 4)
  }

  @Test("Moving cat CatEvenBoxes = 48 states (parity catalog)")
  func movingCatEven() throws {
    let count = try ModelChecker(compilation: try Example.catEvenBoxes.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 500, symmetryReduction: .disabled))
      .exploreGraph().states.count
    #expect(count == 48)
  }

  @Test("Deadlock detected with DeadlockCheck()")
  func deadlock() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("Test") {
      Variable(x, 0)
      Action("once") { x.becomes(1).when(x == 0) }
      DeadlockCheck()
    }
    let r = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check()
    if case .deadlocked(let state) = r {
      let token = try #require(TLAStateProjection.Token(validating: "x"))
      #expect(state.value(for: token) == .int(1))
    } else {
      #expect(Bool(false))
    }
  }

  @Test("Majority Boyer-Moore shape explores")
  func majority() throws {
    let cand = Var<Int>("cand")
    let cnt = Var<Int>("cnt")
    let i = Var<Int>("i")
    let spec = TLASpec("Majority") {
      Variable(cand, 0)
      Variable(cnt, 0)
      Variable(i, 1)
      Invariant("TypeOK") {
        i >= 1 && i <= 4 && cand >= 0 && cand <= 3 && cnt >= 0 && cnt <= 3
      }
      Action("Next") {
        (i <= 3) && i.becomes(i + 1)
          && (cnt == 0 && cand.becomes(i) && cnt.becomes(1)
            || cnt != 0 && cand == i && cnt.becomes(cnt + 1)
            || cnt != 0 && cand != i && cnt.becomes(cnt - 1))
      }
    }
    let count = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph().states.count
    #expect(count >= 1)
    let checkOutcome = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check()
    #expect({ if case .ok = checkOutcome { true } else { false } }())
  }

  @Test("Multi-choose is Cartesian product")
  func multiChooseProduct() throws {
    let action = ActionExpr.existsAction("first", .setLiteral([.int(1), .int(2)]),
      .existsAction("second", .setLiteral([.int(10), .int(20)]),
        .and(.assign(.named("x"), .variable("first")), .assign(.named("y"), .variable("second")))))
    let (compilation, states) = try compiledSuccessors(
      for: action,
      from: [("x", .int(0)), ("y", .int(0))]
    )
    #expect(states.count == 4)
    let pairs = try Set(states.map {
      "\(try compiledStateValue(named: "x", in: $0, compilation: compilation))-\(try compiledStateValue(named: "y", in: $0, compilation: compilation))"
    })
    #expect(pairs == Set(["1-10", "1-20", "2-10", "2-20"]))
  }
}
