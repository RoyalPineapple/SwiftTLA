import Foundation
@testable import SwiftTLA
import Testing
import UpstreamParity

struct SymmetryReductionTests {
  @Test("Direct symmetry produces the exact orbit graph")
  func directValueSymmetry() throws {
    let spec = TLASpec("SymTest") {
      let owner = Var<LeftNode>("owner")
      Variable(owner, in: LeftNode.allCases)
      Action("stay") { owner.stays }
      Symmetry("owner", Set(LeftNode.allCases))
    }
    let compilation = try spec.compile()
    let raw = try ModelChecker(
      compilation: compilation,
      configuration: FiniteExplorationConfiguration(
        maximumStateLimit: 100,
        symmetryReduction: .disabled)
    ).explore().graph
    let reduced = try ModelChecker(
      compilation: compilation,
      configuration: FiniteExplorationConfiguration(
      maximumStateLimit: 100,
      symmetryReduction: .enabled(maximumPermutationCount: 2))
    ).explore().graph

    #expect(raw.states.count == 2)
    #expect(raw.transitions.values.flatMap { $0 }.count == 2)
    #expect(reduced.states.count == 1)
    #expect(reduced.transitions.values.flatMap { $0 }.count == 1)
  }

  @Test("Independent direct symmetry domains produce the exact product orbit")
  func multipleSymmetrySets() throws {
    let spec = TLASpec("MultiSym") {
      let left = Var<LeftNode>("left")
      let right = Var<RightNode>("right")
      Variable(left, in: LeftNode.allCases)
      Variable(right, in: RightNode.allCases)
      Action("stay") { left.stays && right.stays }
      Symmetry("left", Set(LeftNode.allCases))
      Symmetry("right", Set(RightNode.allCases))
    }
    let compilation = try spec.compile()
    let raw = try ModelChecker(
      compilation: compilation,
      configuration: FiniteExplorationConfiguration(
        maximumStateLimit: 100,
        symmetryReduction: .disabled)
    ).explore().graph
    let reduced = try ModelChecker(
      compilation: compilation,
      configuration: FiniteExplorationConfiguration(
        maximumStateLimit: 100,
        symmetryReduction: .enabled(maximumPermutationCount: 4))
    ).explore().graph

    #expect(raw.states.count == 4)
    #expect(raw.transitions.values.flatMap { $0 }.count == 4)
    #expect(reduced.states.count == 1)
    #expect(reduced.transitions.values.flatMap { $0 }.count == 1)
  }

  @Test("Empty symmetry sets are no-op")
  func emptySymmetryNoOp() throws {
    let spec = TLASpec("NoSym") {
      let x = Var<Int>("x")
      Variable(x, in: 1...3)
      Action("inc") { x < 3 && x.becomes(x + 1) }
      Invariant("TypeOK") { x >= 1 && x <= 3 }
    }
    let mc = ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100, symmetryReduction: .disabled))
    let checkOutcome = try mc.check()
    guard case .ok(let count) = checkOutcome else {
      #expect(Bool(false))
      return
    }
    #expect(count == 3)
  }

  @Test("Symmetry reduction requires a declared symmetry domain")
  func reductionRequiresSymmetry() throws {
    let x = Var<Int>("x")
    let spec = TLASpec("NoSymmetry") {
      Variable(x, 0)
      Action("stay") { x.stays }
    }
    let configuration = try FiniteExplorationConfiguration(
      maximumStateLimit: 10,
      symmetryReduction: .enabled(maximumPermutationCount: 1))

    #expect(throws: FiniteExplorationConfigurationError.symmetryReductionWithoutDeclarations) {
      try ModelChecker(compilation: try spec.compile(), configuration: configuration).explore()
    }
  }

  @Test("TLA+ symmetry operator and config directive are emitted")
  func symmetryTLAOutput() throws {
    let spec = TLASpec("SymOut") {
      let x = Var<Int>("x")
      Variable(x, in: [1, 2, 3])
      Invariant("TypeOK") { x >= 1 }
      Symmetry("x", [1, 2, 3] as Set<Int>)
    }
    let tla = try spec.compile().render().tlaBundle.tla
    #expect(tla.contains("EXTENDS Integers, FiniteSets, Sequences, TLC"))
    #expect(tla.contains("Symmx == Permutations({1, 2, 3})"))
    #expect(tla.contains("Symmx"))
    #expect(try spec.compile().render().tlaBundle.cfg.contains("SYMMETRY Symmx"))
  }

  @Test("Direct symmetry names and domains are validated during compilation")
  func invalidDirectSymmetryFailsCompilation() {
    let invalidName = TLASpec("InvalidSymmetryName") {
      Symmetry("not-a-name", [1] as Set<Int>)
    }
    let emptyDomain = TLASpec("EmptySymmetryDomain") {
      Symmetry("empty", Set<Int>())
    }

    assertInvalidSymmetry(invalidName, path: "symmetrySets[0].name")
    assertInvalidSymmetry(emptyDomain, path: "symmetrySets[0].values")
  }

  @Test("Direct symmetry rendered names cannot collide with declarations")
  func directSymmetryRenderedNameCollisionFailsCompilation() {
    let collision = TLASpec("SymmetryCollision") {
      FormalDefinition("Symmowner", parameters: [], body: .value(.bool(true)))
      Symmetry("owner", [1, 2] as Set<Int>)
    }

    assertInvalidSymmetry(collision, path: "symmetrySets[0].renderedName")
  }

  @Test("Direct symmetry domains must be disjoint")
  func overlappingDirectSymmetryFailsCompilation() {
    let overlap = TLASpec("OverlappingSymmetry") {
      Symmetry("left", [1, 2] as Set<Int>)
      Symmetry("right", [2, 3] as Set<Int>)
    }

    assertInvalidSymmetry(overlap, path: "symmetrySets[1].values")
  }

  @Test("Formal value ordering distinguishes same-sized composite values")
  func formalValueOrderingIsStructural() throws {
    let tupleOne = TLAValue.tuple([.int(1)])
    let tupleTwo = TLAValue.tuple([.int(2)])
    let setOne = TLAValue.set([.int(1)])
    let setTwo = TLAValue.set([.int(2)])
    let recordOne = TLAValue.record(["value": .int(1)])
    let recordTwo = TLAValue.record(["value": .int(2)])
    let functionOne = TLAValue.function([.int(0): .int(1)])
    let functionTwo = TLAValue.function([.int(0): .int(2)])

    #expect(Set([tupleTwo, tupleOne]).sorted() == [tupleOne, tupleTwo])
    #expect(Set([setTwo, setOne]).sorted() == [setOne, setTwo])
    #expect(Set([recordTwo, recordOne]).sorted() == [recordOne, recordTwo])
    #expect(Set([functionTwo, functionOne]).sorted() == [functionOne, functionTwo])

    let compilation = try TLASpec(
      name: "AtomicSymmetryCompositePayload",
      variables: [.init(name: "payload", initialization: .value(.tuple([tupleTwo, tupleOne])), origin: .compiler)],
      actions: [], invariants: [],
      symmetrySets: [.init(variableName: "value", values: [.int(2), .int(1)])]
    ).compile()
    let rendered = try compilation.render().tlaBundle.tla
    #expect(rendered.contains("Symmvalue == Permutations({1, 2})"))
    let plan = try SymmetryPlan(compilation: compilation, reduction: .enabled(maximumPermutationCount: 2))
    let initial = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
    let canonical = try plan.canonicalState(initial)
    #expect(try canonical.value(for: compilation.layout.variables[0].id)
      == .tuple([.init(formal: tupleOne), .init(formal: tupleTwo)]))
  }

  private func assertInvalidSymmetry(_ spec: TLASpec, path: String) {
    do {
      _ = try spec.compile()
      Issue.record("Expected direct symmetry compilation to fail")
    } catch let diagnostic as CompilationDiagnostic {
      #expect(diagnostic.code == .invalidSymmetryDeclaration)
      #expect(diagnostic.stage == .validation)
      #expect(diagnostic.path == path)
    } catch {
      Issue.record("Expected CompilationDiagnostic, got \(error)")
    }
  }
}
