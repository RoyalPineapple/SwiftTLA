@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct ReachableGraphContractTests {
  @Test("DieHard canonical model has its declared reachable graph")
  func dieHardCanonicalGraph() throws {
    let graph = try ReachabilityGraph(initialMachines: DieHardModel.initialMachines(), maximumStates: 100)
    #expect(graph.transitions.count == 16)
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

  @Test("Chameneos configured machine retains initial choices and upstream checks")
  func chameneosConfiguredInitialStatesAndChecks() throws {
    let scenario = try #require(ChameneosModel.validationScenarios().first)
    let configuration = scenario.configuration
    let rendered = try scenario.render()
    #expect(rendered.checkNames == ["TypeOK", "SumMet"])
    #expect(!rendered.checksDeadlock)
    #expect(rendered.tlaBundle.cfg.contains("N = 4"))
    #expect(rendered.tlaBundle.cfg.contains("M = 4"))
    #expect(rendered.tlaBundle.cfg.contains("Faded = Faded"))
    #expect(rendered.tlaBundle.cfg.contains("MeetingPlaceEmpty = MeetingPlaceEmpty"))
    #expect(try scenario.initialMachines().count == 81)
    #expect(throws: GeneratedMachineError.ambiguousInitialState) {
      try ChameneosModel.makeMachine(configuration: configuration)
    }
    let native = try ChameneosModel.makeMachine(.init(chameneoses: [
      1: .init(first: .first(.blue), second: 0), 2: .init(first: .first(.red), second: 0),
      3: .init(first: .first(.yellow), second: 0), 4: .init(first: .first(.blue), second: 0)
    ], meetingPlace: .second(.empty), numMeetings: 0), configuration: configuration)
    #expect(try native.violatedInvariants().isEmpty)
    #expect(try native.enabledActions().count == 1)
    #expect(try native.successors().count == 4)
  }

  @Test("Chameneos native checking exhausts its configured state space")
  func chameneosNativeChecking() throws {
    let scenario = try #require(ChameneosModel.validationScenarios().first)
    let summary = try MachineValidator.run(
      initialMachines: scenario.initialMachines(), maximumStates: 50_000,
      checking: scenario.checking, stopOnViolation: false
    ) { _ in }
    if case .exhausted = summary.completion {} else { Issue.record("Exploration did not finish") }
    #expect(summary.initialStates == 81)
    #expect(summary.states == 34_534)
    #expect(summary.initialStates + summary.edges == 104_697)
    #expect(summary.violatedInvariants.isEmpty)
  }

  @Test("Moving cat CatEvenBoxes = 48 states (parity catalog)")
  func movingCatEven() throws {
    let count = try ModelChecker(compilation: try Example.catEvenBoxes.spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 500, symmetryReduction: .disabled))
      .exploreGraph().states.count
    #expect(count == 48)
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
