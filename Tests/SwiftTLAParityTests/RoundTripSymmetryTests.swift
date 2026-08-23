import Foundation
@testable import SwiftTLA
import Testing
import UpstreamParity

struct SymmetryReductionTests {
  @Test("Symmetry with direct-value variable reduces state count")
  func directValueSymmetry() throws {
    let spec = TLASpec("SymTest") {
      let x = Var<Int>("x")
      Variable(x, in: [1, 2, 3])
      Action("inc") { x < 3 && x.becomes(x + 1) }
      Invariant("TypeOK") { x >= 1 && x <= 3 }
      Symmetry("x", [1, 2, 3] as Set<Int>)
    }
    let mc = ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100))
    let result = try mc.check()
    guard case .ok(let count) = result else {
      #expect(Bool(false))
      return
    }
    #expect(count < 3)
  }

  @Test("Symmetry chains multiple sets")
  func multipleSymmetrySets() throws {
    let spec = TLASpec("MultiSym") {
      let x = Var<Int>("x")
      let y = Var<Int>("y")
      Variable(x, in: [1, 2])
      Variable(y, in: [10, 20])
      Action("bump") {
        (x == 1 && x.becomes(2) && y.stays)
          || (y == 10 && y.becomes(20) && x.stays)
      }
      Invariant("TypeOK") { x >= 1 && x <= 2 && y >= 10 && y <= 20 }
      Symmetry("x", [1, 2] as Set<Int>)
      Symmetry("y", [10, 20] as Set<Int>)
    }
    let mc = ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100))
    let result = try mc.check()
    guard case .ok = result else {
      #expect(Bool(false))
      return
    }
  }

  @Test("Empty symmetry sets are no-op")
  func emptySymmetryNoOp() throws {
    let spec = TLASpec("NoSym") {
      let x = Var<Int>("x")
      Variable(x, in: 1...3)
      Action("inc") { x < 3 && x.becomes(x + 1) }
      Invariant("TypeOK") { x >= 1 && x <= 3 }
    }
    let mc = ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100))
    let result = try mc.check()
    guard case .ok(let count) = result else {
      #expect(Bool(false))
      return
    }
    #expect(count == 3)
  }

  @Test("TLA+ symmetry operator and config directive are emitted")
  func symmetryTLAOutput() throws {
    let spec = TLASpec("SymOut") {
      let x = Var<Int>("x")
      Variable(x, in: [1, 2, 3])
      Invariant("TypeOK") { x >= 1 }
      Symmetry("x", [1, 2, 3] as Set<Int>)
    }
    let tla = try spec.compile().renderedTLAModuleBundle().tla
    #expect(tla.contains("EXTENDS Integers, FiniteSets, Sequences, TLC"))
    #expect(tla.contains("Symmx == Permutations({1, 2, 3})"))
    #expect(tla.contains("Symmx"))
    #expect(try spec.compile().renderedTLAModuleBundle().cfg.contains("SYMMETRY Symmx"))
  }
}
// MARK: - Initialized-variable parity
@Suite(.serialized) struct InitializedVariableParityTests { @Test("initialized and explicitly declared variables produce the same StateGraph")
  func initializedVarVsExplicitVariable() throws {
    let x = Var<Int>("x")
    let spec1 = TLASpec("Test") {
      Variable(x, 0)
      Action("inc") { x.becomes(x + 1).when(x < 5) }
      Invariant("ok") { x >= 0 && x <= 5 }
    }
    let sv = Var("x", 0)
    let spec2 = TLASpec("Test") {
      Variable(sv)
      Action("inc") { sv.becomes(sv + 1).when(sv < 5) }
      Invariant("ok") { sv >= 0 && sv <= 5 }
    }
    let graph1 = try ModelChecker(compilation: try spec1.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph()
    let graph2 = try ModelChecker(compilation: try spec2.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph()
    #expect(graph1.states.count == graph2.states.count)
    #expect(graph1.states.count == 6)
    let result1 = try ModelChecker(compilation: try spec1.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).check()
    let result2 = try ModelChecker(compilation: try spec2.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).check()
    if case .ok(let c1) = result1, case .ok(let c2) = result2 {
      #expect(c1 == c2)
    } else {
      #expect(Bool(false), "Invariants should hold in both specs")
    }
  }
}
// MARK: - Enum domain type tests
enum Mode: Int, TLAValueType, StateExprConvertible {
  case idle = 0
  case active = 1

  static var defaultValue: Self { .idle }
}
enum Status: String, TLAValueType, StateExprConvertible {
  case on, off

  static var defaultValue: Self { .on }
}
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
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph()
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
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph()
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
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph()
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
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph()
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
    let tla = try spec.compile().renderedTLAModuleBundle().tla
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
    let tla = try spec.compile().renderedTLAModuleBundle().tla
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
    let result = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).check()
    if case .ok(let count) = result {
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
    let bundle = try spec.compile().renderedTLAModuleBundle()
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
    let graph = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).exploreGraph()
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
    let tla = try spec.compile().renderedTLAModuleBundle().tla
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
// MARK: - Var-as-SpecComponent: builder collects Var directly
@Suite(.serialized) struct VarSpecComponentTests { @Test("Var(name, value) + Variable(ref) registers spec variable")
  func varAsSpecComponent() throws {
    let spec = TLASpec("VarTest") {
      let x = Var("x", 0)
      Variable(x)
      Action("inc") { x.becomes(x + 1).when(x < 3) }
    }
    #expect(spec.variables.count == 1)
    #expect(spec.variables[0].name == "x")
    #expect(spec.variables[0].initial == .int(0))
    #expect(try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10)).exploreGraph().states.count == 4)
  }
}
