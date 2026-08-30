import Testing
@testable import SwiftTLA

@Suite("ClientCentric formal module")
struct ClientCentricModuleTests {
  @Test("an instance resolves namespaced executable operators")
  func instanceResolvesSnapshotIsolation() throws {
    let keys = SetExpr<TestKey>(.key)
    let values = SetExpr<TestValue>(.none)
    let initial = StateExpr.functionLiteral(keys.stateExpr, "key", .value(.string("none")))
    let snapshot = ModuleCall(
      as: Bool.self,
      "CC", "SnapshotIsolation", Expr<Function<TestKey, TestValue>>(initial),
      Expr<SetExpr<TupleExpr<Int>>>(.setLiteral([]))
    )
    let consumer = TLASpec("ClientCentricConsumer") {
      Import(KeyValueStoreUtil.module)
      Instance("CC", of: ClientCentric.module, with: [
        ModuleArgument("Keys", value: keys),
        ModuleArgument("Values", value: values)
      ])
      Invariant("SnapshotIsolation") { snapshot.raw }
    }

    let compilation = try consumer.compile()
    let runtime = CompiledRuntime(compilation: compilation)
    let state = try #require(try runtime.initialStates().first)
    let invariant = try #require(compilation.semantics.invariants.first)
    #expect(try runtime.invariantHolds(invariant, in: state))
    #expect(compilation.renderedTLAModuleBundle().imports.map(\.name) == ["Folds", "Functions", "Util", "ClientCentric"])
    #expect(compilation.renderedTLAModuleBundle().tla.contains("CC == INSTANCE ClientCentric WITH Keys <- {\"k\"}, Values <- {\"none\"}"))
  }

  @Test("a selected injective function can concatenate as a TLA sequence")
  func chosenFunctionConcatenatesAsSequence() throws {
    let selected = StateExpr.choose(
      .functionSet(.integerRange(.int(1), .int(2)), .setLiteral([.int(1), .int(2)])),
      "f",
      .operatorApplication(.reference("IsInjective", arity: 1), [.value(.variable("f"))])
    )
    let expression = StateExpr.tupleConcatenate(.tupleLiteral([]), selected)
    let value = try compiledValue(
      expression,
      formalOperators: try FormalModuleClosure.resolve(root: FunctionsModule.module)
        .linkedOperators.formalOperatorDefinitions
    )
    guard case .tuple(let values) = value else {
      Issue.record("An injective function choice must be consumable as a formal sequence.")
      return
    }
    #expect(Set(values) == [.int(1), .int(2)])
  }

  private enum TestKey: String, FiniteTLAValueDomain {
    case key = "k"
    static var defaultValue: Self { .key }
    static let finiteValues: [Self] = [.key]
  }

  private enum TestValue: String, FiniteTLAValueDomain {
    case none
    static var defaultValue: Self { .none }
    static let finiteValues: [Self] = [.none]
  }
}
