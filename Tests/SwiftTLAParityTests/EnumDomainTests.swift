@testable import SwiftTLA
import Testing

struct EnumDomainTests {
  @Test("Int-backed enum TLA+ output uses raw values")
  func intEnumTLAOutput() throws {
    let mode = Var<IntEnumToggleModel.Mode>("mode")
    let spec = TLASpec("IntEnum") {
      Variable(mode, IntEnumToggleModel.Mode.idle)
      Action("toggle") {
        (mode == IntEnumToggleModel.Mode.idle) && mode.becomes(IntEnumToggleModel.Mode.active)
          || (mode == IntEnumToggleModel.Mode.active) && mode.becomes(IntEnumToggleModel.Mode.idle)
      }
    }
    let tla = try spec.compile().render().tlaBundle.tla
    #expect(tla.contains("mode = 0"))
    #expect(tla.contains("toggle =="))
  }

  @Test("String-backed enum TLA+ output uses raw string values")
  func stringEnumTLAOutput() throws {
    let state = Var<StringEnumToggleModel.Status>("state")
    let spec = TLASpec("StringEnum") {
      Variable(state, StringEnumToggleModel.Status.on)
      Action("toggle") {
        (state == StringEnumToggleModel.Status.on) && state.becomes(StringEnumToggleModel.Status.off)
          || (state == StringEnumToggleModel.Status.off) && state.becomes(StringEnumToggleModel.Status.on)
      }
    }
    let tla = try spec.compile().render().tlaBundle.tla
    #expect(tla.contains("state = \"on\""))
    #expect(tla.contains("toggle =="))
  }

  @Test("Enum-backed spec produces valid TLA+ bundle")
  func enumBundle() throws {
    let mode = Var<IntEnumToggleModel.Mode>("mode")
    let spec = TLASpec("IntEnumBundle") {
      Variable(mode, IntEnumToggleModel.Mode.idle)
      Action("toggle") {
        (mode == IntEnumToggleModel.Mode.idle) && mode.becomes(IntEnumToggleModel.Mode.active)
          || (mode == IntEnumToggleModel.Mode.active) && mode.becomes(IntEnumToggleModel.Mode.idle)
      }
      Invariant("TypeOK") { (mode == IntEnumToggleModel.Mode.idle) || (mode == IntEnumToggleModel.Mode.active) }
    }
    let bundle = try spec.compile().render().tlaBundle
    #expect(bundle.tla.contains("MODULE"))
    #expect(bundle.tla.contains("VARIABLES mode"))
    #expect(bundle.cfg.contains("INVARIANT TypeOK"))
  }

  @Test("Enum vars work with stays expression")
  func enumStays() throws {
    let phase = Var<IntEnumToggleModel.Mode>("phase")
    let spec = TLASpec("EnumStays") {
      Variable(phase, IntEnumToggleModel.Mode.idle)
      Action("noop") {
        (phase == IntEnumToggleModel.Mode.idle) && phase.stays
      }
    }
    let tla = try spec.compile().render().tlaBundle.tla
    #expect(tla.contains("UNCHANGED phase"))
  }

  @Test("integer-backed enum states retain typed toggles and raw TLA values")
  func checksIntegerEnumMachine() throws {
    let initialMachines = try IntEnumToggleModel.initialMachines()
    #expect(initialMachines.count == 1)
    let initial = try #require(initialMachines.first)
    #expect(initial.state.mode == .idle)
    let mode = try #require(TLAStateProjection.Token(validating: "mode"))
    #expect(try initial.formalProjection(of: initial.snapshot).value(for: mode) == .int(0))
    let graph = try ReachabilityGraph(initialMachines: [initial], maximumStates: 2)
    #expect(Set(graph.transitions.keys.map(\.state.mode)) == [.idle, .active])
    #expect(graph.transitions[initial.snapshot]?.first?.target.state.mode == .active)
    let active = try #require(graph.transitions.keys.first { $0.state.mode == .active })
    #expect(graph.transitions[active]?.first?.target.state.mode == .idle)
    #expect(graph.transitions.values.flatMap { $0 }.map(\.action) == [.toggle, .toggle])
    #expect(graph.safetyViolations.isEmpty)
    #expect(try IntEnumToggleModel.render().tlaBundle.tla.contains("mode = 0"))
  }

  @Test("string-backed enum states retain typed toggles and raw TLA values")
  func checksStringEnumMachine() throws {
    let initial = try #require(StringEnumToggleModel.initialMachines().first)
    #expect(initial.state.status == .on)
    let graph = try ReachabilityGraph(initialMachines: [initial], maximumStates: 2)
    #expect(Set(graph.transitions.keys.map(\.state.status)) == [.on, .off])
    #expect(graph.transitions[initial.snapshot]?.first?.target.state.status == .off)
    let off = try #require(graph.transitions.keys.first { $0.state.status == .off })
    #expect(graph.transitions[off]?.first?.target.state.status == .on)
    #expect(graph.transitions.values.flatMap { $0 }.map(\.action) == [.toggle, .toggle])
    #expect(graph.safetyViolations.isEmpty)
    #expect(try StringEnumToggleModel.render().tlaBundle.tla.contains("status = \"on\""))
  }
}
