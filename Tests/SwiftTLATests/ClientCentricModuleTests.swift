import Testing
@testable import SwiftTLA

@Suite("ClientCentric formal module")
struct ClientCentricModuleTests {
  @Test("an instance qualifies executable formal operators without copying imports")
  func instanceResolvesSnapshotIsolation() throws {
    let keys = StateExpr.setLiteral([.value(.string("k"))])
    let values = StateExpr.setLiteral([.value(.string("none"))])
    let initial = StateExpr.functionLiteral(keys, "key", .value(.string("none")))
    let consumer = TLASpec("ClientCentricConsumer") {
      Import(KeyValueStoreUtil.module)
      Instance("CC", of: ClientCentric.module, with: [
        ModuleArgument("Keys", expression: keys),
        ModuleArgument("Values", expression: values)
      ])
    }

    let snapshot = ModuleCall(
      as: Bool.self,
      "CC", "SnapshotIsolation", Expr<Function<TestKey, TestValue>>(initial),
      Expr<SetExpr<TupleExpr<Int>>>(.setLiteral([]))
    )
    let closure = try FormalModuleClosure.resolve(root: consumer)
    #expect(try compiledValue(
      snapshot.raw,
      recursiveFunctions: closure.linkedOperators.recursiveFunctions,
      formalOperators: closure.linkedOperators.formalOperatorDefinitions
    ) == .bool(true))
    #expect(try consumer.compile().renderedTLAModuleBundle().imports.map(\.name) == ["Folds", "Functions", "Util", "ClientCentric"])
    #expect(try consumer.compile().renderedTLAModuleBundle().tla.contains("CC == INSTANCE ClientCentric WITH Keys <- {\"k\"}, Values <- {\"none\"}"))
  }

  @Test("a selected injective function can concatenate as a TLA sequence")
  func chosenFunctionConcatenatesAsSequence() throws {
    let selected = StateExpr.choose(
      .functionSet(.integerRange(.int(1), .int(2)), .setLiteral([.int(1), .int(2)])),
      "f",
      .operatorApplication(.reference("IsInjective", arity: 1), [.value(.variable("f"))])
    )
    let expression = StateExpr.tupleConcatenate(.tupleLiteral([]), selected)
    let result = try compiledValue(
      expression,
      formalOperators: try FormalModuleClosure.resolve(root: FunctionsModule.module)
        .linkedOperators.formalOperatorDefinitions
    )
    guard case .tuple(let values) = result else {
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
