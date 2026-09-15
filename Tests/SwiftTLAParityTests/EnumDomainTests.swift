import Foundation
@testable import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized) struct EnumDomainTests { @Test("Int-backed enum Var model-checks correctly")
  func intEnumVar() throws {
    let mode = Var<Mode>("mode")
    let spec = TLASpec("IntEnum") {
      Variable(mode, Mode.idle)
      Action("toggle") {
        (mode == Mode.idle) && mode.becomes(Mode.active)
          || (mode == Mode.active) && mode.becomes(Mode.idle)
      }
    }
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph()
    #expect(graph.states.count == 2)
  }

  @Test("Int-backed initialized enum variable model-checks correctly")
  func intEnumInitializedVar() throws {
    let mode = Var("mode", Mode.idle)
    let spec = TLASpec("IntEnumSV") {
      Variable(mode)
      Action("toggle") {
        (mode == Mode.idle) && mode.becomes(Mode.active)
          || (mode == Mode.active) && mode.becomes(Mode.idle)
      }
    }
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph()
    #expect(graph.states.count == 2)
  }

  @Test("String-backed enum Var model-checks correctly")
  func stringEnumVar() throws {
    let state = Var<Status>("state")
    let spec = TLASpec("StringEnum") {
      Variable(state, Status.on)
      Action("toggle") {
        (state == Status.on) && state.becomes(Status.off)
          || (state == Status.off) && state.becomes(Status.on)
      }
    }
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph()
    #expect(graph.states.count == 2)
  }

  @Test("String-backed initialized enum variable model-checks correctly")
  func stringEnumInitializedVar() throws {
    let state = Var("state", Status.on)
    let spec = TLASpec("StringEnumSV") {
      Variable(state)
      Action("toggle") {
        (state == Status.on) && state.becomes(Status.off)
          || (state == Status.off) && state.becomes(Status.on)
      }
    }
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph()
    #expect(graph.states.count == 2)
  }

  @Test("Int-backed enum TLA+ output uses raw values")
  func intEnumTLAOutput() throws {
    let mode = Var<Mode>("mode")
    let spec = TLASpec("IntEnum") {
      Variable(mode, Mode.idle)
      Action("toggle") {
        (mode == Mode.idle) && mode.becomes(Mode.active)
          || (mode == Mode.active) && mode.becomes(Mode.idle)
      }
    }
    let tla = try spec.compile().render().tlaBundle.tla
    #expect(tla.contains("mode = 0"))
    #expect(tla.contains("toggle =="))
  }

  @Test("String-backed enum TLA+ output uses raw string values")
  func stringEnumTLAOutput() throws {
    let state = Var<Status>("state")
    let spec = TLASpec("StringEnum") {
      Variable(state, Status.on)
      Action("toggle") {
        (state == Status.on) && state.becomes(Status.off)
          || (state == Status.off) && state.becomes(Status.on)
      }
    }
    let tla = try spec.compile().render().tlaBundle.tla
    #expect(tla.contains("state = \"on\""))
    #expect(tla.contains("toggle =="))
  }

  @Test("Enum values work in invariant expressions")
  func enumInInvariant() throws {
    let mode = Var<Mode>("mode")
    let spec = TLASpec("IntEnumInv") {
      Variable(mode, Mode.idle)
      Action("toggle") {
        (mode == Mode.idle) && mode.becomes(Mode.active)
          || (mode == Mode.active) && mode.becomes(Mode.idle)
      }
      Invariant("TypeOK") { (mode == Mode.idle) || (mode == Mode.active) }
    }
    let checkOutcome = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).check()
    if case .ok(let count) = checkOutcome {
      #expect(count == 2)
    } else {
      #expect(Bool(false), "Invariant should hold")
    }
  }

  @Test("Enum-backed spec produces valid TLA+ bundle")
  func enumBundle() throws {
    let mode = Var<Mode>("mode")
    let spec = TLASpec("IntEnumBundle") {
      Variable(mode, Mode.idle)
      Action("toggle") {
        (mode == Mode.idle) && mode.becomes(Mode.active)
          || (mode == Mode.active) && mode.becomes(Mode.idle)
      }
      Invariant("TypeOK") { (mode == Mode.idle) || (mode == Mode.active) }
    }
    let bundle = try spec.compile().render().tlaBundle
    #expect(bundle.tla.contains("MODULE"))
    #expect(bundle.tla.contains("VARIABLES mode"))
    #expect(bundle.cfg.contains("INVARIANT TypeOK"))
  }

  @Test("Multi-state Int-backed enum explores all values")
  func multiStateIntEnum() throws {
    let phase = Var<Mode>("phase")
    let spec = TLASpec("MultiEnum") {
      Variable(phase, Mode.idle)
      Action("activate") { phase.becomes(Mode.active).when(phase == Mode.idle) }
      Action("deactivate") { phase.becomes(Mode.idle).when(phase == Mode.active) }
    }
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph()
    let values = try Set(graph.states.values.compactMap { try value("phase", in: $0) })
    #expect(values == Set([TLAValue.int(0), TLAValue.int(1)]))
  }

  @Test("Enum vars work with stays expression")
  func enumStays() throws {
    let phase = Var<Mode>("phase")
    let spec = TLASpec("EnumStays") {
      Variable(phase, Mode.idle)
      Action("noop") {
        (phase == Mode.idle) && phase.stays
      }
    }
    let tla = try spec.compile().render().tlaBundle.tla
    #expect(tla.contains("UNCHANGED phase"))
  }

  @Test("Enum var initial state is first case raw value")
  func enumInitialState() throws {
    let mode = Var<Mode>("mode")
    let spec = TLASpec("EnumInit") {
      Variable(mode, Mode.idle)
    }
    let compilation = try spec.compile()
    let states = try CompiledRuntime(compilation: compilation).initialStates()
    let state = try #require(states.first)
    let projection = try state.projection(using: compilation.layout)
    let modeToken = try #require(TLAStateProjection.Token(validating: "mode"))
    #expect(states.count == 1)
    #expect(projection.value(for: modeToken) == .int(0))
  }
}
