import Foundation
import SwiftParser
import SwiftSyntax
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
    let mc = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100))
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
    let mc = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100))
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
    let mc = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100))
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
// MARK: - Round-trip: parse(swiftSource(expr)) == expr for every StateExpr case
extension StateExpr {
  fileprivate var normalized: StateExpr {
    switch self {
    case .setFilter(let s, _, let p): return .setFilter(s.normalized, "x", p.normalized)
    case .setMap(let e, _, let s): return .setMap(e.normalized, "x", s.normalized)
    case .forAll(let s, _, let p): return .forAll(s.normalized, "x", p.normalized)
    case .exists(let s, _, let p): return .exists(s.normalized, "x", p.normalized)
    case .choose(let s, _, let p): return .choose(s.normalized, "x", p.normalized)
    case .functionLiteral(let d, _, let b): return .functionLiteral(d.normalized, "x", b.normalized)
    case .add(let a, let b): return .add(a.normalized, b.normalized)
    case .subtract(let a, let b): return .subtract(a.normalized, b.normalized)
    case .multiply(let a, let b): return .multiply(a.normalized, b.normalized)
    case .divide(let a, let b): return .divide(a.normalized, b.normalized)
    case .modulo(let a, let b): return .modulo(a.normalized, b.normalized)
    case .integerDivide(let a, let b): return .integerDivide(a.normalized, b.normalized)
    case .negate(let a): return .negate(a.normalized)
    case .equal(let a, let b): return .equal(a.normalized, b.normalized)
    case .notEqual(let a, let b): return .notEqual(a.normalized, b.normalized)
    case .lessThan(let a, let b): return .lessThan(a.normalized, b.normalized)
    case .lessOrEqual(let a, let b): return .lessOrEqual(a.normalized, b.normalized)
    case .greaterThan(let a, let b): return .greaterThan(a.normalized, b.normalized)
    case .greaterOrEqual(let a, let b): return .greaterOrEqual(a.normalized, b.normalized)
    case .and(let a, let b): return .and(a.normalized, b.normalized)
    case .or(let a, let b): return .or(a.normalized, b.normalized)
    case .not(let a): return .not(a.normalized)
    case .ifThenElse(let c, let t, let e):
      return .ifThenElse(c.normalized, t.normalized, e.normalized)
    case .in(let a, let b): return .in(a.normalized, b.normalized)
    case .setLiteral(let es): return .setLiteral(es.map(\.normalized))
    case .subset(let a, let b): return .subset(a.normalized, b.normalized)
    case .union(let a, let b): return .union(a.normalized, b.normalized)
    case .intersection(let a, let b): return .intersection(a.normalized, b.normalized)
    case .setDifference(let a, let b): return .setDifference(a.normalized, b.normalized)
    case .cardinality(let a): return .cardinality(a.normalized)
    case .powerSet(let a): return .powerSet(a.normalized)
    case .unionAll(let a): return .unionAll(a.normalized)
    case .domain(let a): return .domain(a.normalized)
    case .functionApply(let f, let a): return .functionApply(f.normalized, a.normalized)
    case .except(let f, let k, let v): return .except(f.normalized, k.normalized, v.normalized)
    case .tupleLiteral(let es): return .tupleLiteral(es.map(\.normalized))
    case .tupleAccess(let t, let i): return .tupleAccess(t.normalized, i)
    case .tupleLength(let t): return .tupleLength(t.normalized)
    case .tupleHead(let t): return .tupleHead(t.normalized)
    case .tupleTail(let t): return .tupleTail(t.normalized)
    case .tupleAppend(let t, let e): return .tupleAppend(t.normalized, e.normalized)
    case .tupleConcatenate(let a, let b): return .tupleConcatenate(a.normalized, b.normalized)
    case .recordLiteral(let record):
      return .recordLiteral(.init(record.fields.map { .init(name: $0.name, value: $0.value.normalized) }))
    case .recordAccess(let r, let f): return .recordAccess(r.normalized, f)
    case .caseExpr(let pairs, let fallback):
      return .caseExpr(pairs.map(\.normalized), fallback?.normalized)
    default: return self
    }
  }
}
@Suite(.serialized) struct StateExprRoundTripTests {
  private static func parseExpression(_ source: String) throws -> ExprSyntax {
    let statement = try #require(SwiftParser.Parser.parse(source: source).statements.first)
    return try #require(statement.item.as(ExprSyntax.self))
  }

  @Test(
    "Round-trip: parse(swiftSource(expr)) == expr for all parseable StateExpr cases",
    arguments: [
      ("value int", StateExpr.value(.int(42))),
      ("value bool", StateExpr.value(.bool(true))),
      ("value string", StateExpr.value(.string("hi"))),
      ("variable", StateExpr.variable("x")),
      ("add", StateExpr.add(.int(1), .int(2))),
      ("subtract", StateExpr.subtract(.int(5), .int(3))),
      ("multiply", StateExpr.multiply(.int(2), .int(3))),
      ("divide", StateExpr.divide(.int(6), .int(2))),
      ("modulo", StateExpr.modulo(.int(7), .int(3))),
      ("negate", StateExpr.negate(.int(1))),
      ("integerDivide", StateExpr.integerDivide(.int(4), .int(2))),
      ("equal", StateExpr.equal(.int(1), .int(1))),
      ("notEqual", StateExpr.notEqual(.int(1), .int(2))),
      ("lessThan", StateExpr.lessThan(.int(1), .int(2))),
      ("lessOrEqual", StateExpr.lessOrEqual(.int(1), .int(2))),
      ("greaterThan", StateExpr.greaterThan(.int(2), .int(1))),
      ("greaterOrEqual", StateExpr.greaterOrEqual(.int(2), .int(1))),
      ("and", StateExpr.and(.bool(true), .bool(false))),
      ("or", StateExpr.or(.bool(true), .bool(false))),
      ("not", StateExpr.not(.bool(true))),
      ("ifThenElse", StateExpr.ifThenElse(.bool(true), .int(1), .int(2))),
      ("in", StateExpr.in(.int(1), .setLiteral([.int(1), .int(2)]))),
      ("setLiteral", StateExpr.setLiteral([.int(1), .int(2)])),
      ("subset", StateExpr.subset(.setLiteral([.int(1)]), .setLiteral([.int(1), .int(2)]))),
      ("union", StateExpr.union(.setLiteral([.int(1)]), .setLiteral([.int(2)]))),
      ("intersection", StateExpr.intersection(.setLiteral([.int(1)]), .setLiteral([.int(1)]))),
      (
        "setDifference",
        StateExpr.setDifference(.setLiteral([.int(1), .int(2)]), .setLiteral([.int(2)]))
      ),
      ("cardinality", StateExpr.cardinality(.setLiteral([.int(1)]))),
      ("powerSet", StateExpr.powerSet(.setLiteral([.int(1)]))),
      ("unionAll", StateExpr.unionAll(.setLiteral([.setLiteral([.int(1)])]))),
      ("domain", StateExpr.domain(StateExpr.record(["k": .int(1)]))),
      ("functionApply", StateExpr.functionApply(.variable("f"), .int(1))),
      ("except", StateExpr.except(.variable("f"), .int(1), .int(2))),
      ("tupleLiteral", StateExpr.tupleLiteral([.int(1), .int(2)])),
      ("tupleAccess", StateExpr.tupleAccess(.tupleLiteral([.int(10)]), 1)),
      ("tupleLength", StateExpr.tupleLength(.tupleLiteral([.int(1)]))),
      ("tupleHead", StateExpr.tupleHead(.tupleLiteral([.int(1)]))),
      ("tupleTail", StateExpr.tupleTail(.tupleLiteral([.int(1)]))),
      ("tupleAppend", StateExpr.tupleAppend(.tupleLiteral([.int(1)]), .int(2))),
      (
        "tupleConcatenate",
        StateExpr.tupleConcatenate(.tupleLiteral([.int(1)]), .tupleLiteral([.int(2)]))
      ),
      ("recordLiteral", StateExpr.record(["k": .int(1)])),
      ("recordAccess", StateExpr.recordAccess(StateExpr.record(["k": .int(1)]), "k")),
      (
        "setFilter",
        StateExpr.setFilter(.setLiteral([.int(1)]), "x0", .equal(.variable("x0"), .int(1)))
      ),
      (
        "setMap",
        StateExpr.setMap(.add(.variable("x0"), .int(1)), "x0", .setLiteral([.int(1)]))
      ),
      (
        "forAll",
        StateExpr.forAll(.setLiteral([.int(1)]), "x0", .equal(.variable("x0"), .int(1)))
      ),
      (
        "exists",
        StateExpr.exists(.setLiteral([.int(1)]), "x0", .equal(.variable("x0"), .int(1)))
      ),
      (
        "choose",
        StateExpr.choose(.setLiteral([.int(1)]), "x0", .equal(.variable("x0"), .int(1)))
      ),
      (
        "functionLiteral",
        StateExpr.functionLiteral(.setLiteral([.int(1)]), "x0", .add(.variable("x0"), .int(1)))
      ),
      ("caseExpr", StateExpr.caseExpr([.bool(true), .int(1), .bool(false), .int(2)], .int(0))),
      ("enabledAction", StateExpr.enabledAction("Tick"))
    ] as [(String, StateExpr)])
  func roundTrip(_ name: String, _ expr: StateExpr) throws {
    let source = expr.swiftSource
    #expect(!source.isEmpty, "\(name): swiftSource is empty")
    #expect(!source.contains("\\in"), "\(name): swiftSource contains TLA+ syntax: \(source)")
    #expect(!source.contains("<<"), "\(name): swiftSource contains TLA+ tuple syntax: \(source)")
    let parsed = SpecParser.decodeStateExpr(try Self.parseExpression(source))
    let parsedNormalized = parsed?.normalized
    #expect(
      parsedNormalized == expr.normalized,
      "\(name): round-trip failed.\n  source: \(source)\n  parsed: \(String(describing: parsed))\n  expected: \(expr)"
    )
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
