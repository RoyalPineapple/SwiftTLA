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

    let snapshot = ModuleCall<Bool>(
      "CC", "SnapshotIsolation", Expr<Function<TestKey, TestValue>>(initial),
      Expr<SetExpr<TupleExpr<Int>>>(.setLiteral([]))
    )
    #expect(try snapshot.raw.evaluate(
      in: [:],
      recursiveFuncs: try consumer.compile().formalModuleClosure.resolvedRecursiveFuncs,
      formalOperatorDefinitions: try consumer.compile().formalModuleClosure.resolvedFormalOperatorDefinitions
    ) == .bool(true))
    #expect(try consumer.compile().renderedTLAModuleBundle().imports.map(\.name) == ["Folds", "Functions", "Util", "ClientCentric"])
    #expect(try consumer.compile().renderedTLAModuleBundle().tla.contains("CC == INSTANCE ClientCentric WITH Keys <- {\"k\"}, Values <- {\"none\"}"))
  }

  @Test("a selected injective function can concatenate as a TLA sequence")
  func chosenFunctionRemainsSequenceCompatible() throws {
    let selected = StateExpr.choose(
      .functionSet(.integerRange(.int(1), .int(2)), .setLiteral([.int(1), .int(2)])),
      "f",
      .operatorApplication(.reference("IsInjective", arity: 1), [.value(.variable("f"))])
    )
    let expression = StateExpr.tupleConcatenate(.tupleLiteral([]), selected)
    let result = try expression.evaluate(
      in: [:], formalOperatorDefinitions: try FunctionsModule.module.compile().formalModuleClosure.resolvedFormalOperatorDefinitions
    )
    guard case .tuple(let values) = result else {
      Issue.record("An injective function choice must be consumable as a formal sequence.")
      return
    }
    #expect(Set(values) == [.int(1), .int(2)])
  }

  private enum TestKey: String, FiniteDomainKey {
    case key = "k"
    static let formalDomain: [Self] = [.key]
    static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.clientCentric.key")
  }

  private enum TestValue: String, FiniteDomainKey {
    case none
    static let formalDomain: [Self] = [.none]
    static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.clientCentric.value")
  }
}
