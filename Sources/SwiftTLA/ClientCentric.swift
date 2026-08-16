/// Executable formal port of the upstream KeyValueStore `ClientCentric` module.
///
/// `ClientCentric` is a real parameterized TLA+ module.  It deliberately keeps
/// its isolation definitions in the formal AST so a consumer can both emit an
/// `INSTANCE` for TLC and evaluate the same bounded invariant in SwiftTLA.
public enum ClientCentric {
  private static func call(_ name: String, _ values: StateExpr...) -> StateExpr {
    .operatorApplication(.reference(name, arity: values.count), values.map(FormalCallArgument.value))
  }

  private static func op(_ name: String, arity: Int) -> FormalOperator {
    .reference(name, arity: arity)
  }

  public static let module = TLASpec("ClientCentric") {
    Extends("Naturals, TLC")
    Parameter("Keys", kind: .variable)
    Parameter("Values", kind: .variable)
    Import(KeyValueStoreUtil.module)

    // These are source-level type aliases. They are not evaluated by the
    // isolation predicate, but retaining them makes the module source match
    // the published ClientCentric interface.
    Definition("State == [Keys -> Values]")
    Definition("Operation == [op: {\"read\", \"write\"}, key: Keys, value: Values]")
    Definition("Transaction == Seq(Operation)")
    Definition("TimeStamp == Nat")
    Definition("TransactionTimes == [t \\in Transaction |-> [start: TimeStamp, commit: TimeStamp]]")
    Definition("ExecutionElem == [parentState: State, transaction: Transaction]")
    Definition("Execution == Seq(ExecutionElem)")
    Definition("TypeOKT(transactions) == transactions \\subseteq Transaction")
    Definition("TypeOK(transactions, execution) == /\\ TypeOKT(transactions) /\\ execution \\in Execution")

    FormalDefinition("r", parameters: [.value("k"), .value("v")], body: .recordLiteral([
      "op": .value(.string("read")), "key": .variable("k"), "value": .variable("v")
    ]))
    FormalDefinition("w", parameters: [.value("k"), .value("v")], body: .recordLiteral([
      "op": .value(.string("write")), "key": .variable("k"), "value": .variable("v")
    ]))
    FormalDefinition("executionStates", parameters: [.value("execution")], body: .functionLiteral(
      .integerRange(.int(1), .tupleLength(.variable("execution"))), "i",
      .recordAccess(.tupleDynamicAccess(.variable("execution"), .variable("i")), "parentState")
    ))
    FormalDefinition("executionTransactions", parameters: [.value("execution")], body: .setMap(
      .recordAccess(.variable("ep"), "transaction"), "ep",
      call("SeqToSet", .variable("execution"))
    ))
    FormalDefinition("parentState", parameters: [.value("execution"), .value("transaction")], body: .letValue(
      "ind",
      .choose(
        .integerRange(.int(1), .tupleLength(.variable("execution"))), "i",
        .equal(
          .recordAccess(.tupleDynamicAccess(.variable("execution"), .variable("i")), "transaction"),
          .variable("transaction")
        )
      ),
      .recordAccess(.tupleDynamicAccess(.variable("execution"), .variable("ind")), "parentState")
    ))
    FormalDefinition("earlierInTransaction", parameters: [.value("transaction"), .value("op1"), .value("op2")], body: .lessThan(
      call("Index", .variable("transaction"), .variable("op1")),
      call("Index", .variable("transaction"), .variable("op2"))
    ))
    FormalDefinition("beforeOrEqualInExecution", parameters: [.value("execution"), .value("state1"), .value("state2")], body: .letValue(
      "states", call("executionStates", .variable("execution")),
      .lessOrEqual(
        call("Index", .variable("states"), .variable("state1")),
        call("Index", .variable("states"), .variable("state2"))
      )
    ))
    FormalDefinition("ReadStates", parameters: [.value("execution"), .value("operation"), .value("transaction")], body: .letValue(
      "Se", call("SeqToSet", call("executionStates", .variable("execution"))),
      .letValue(
        "sp", call("parentState", .variable("execution"), .variable("transaction")),
        .setFilter(.variable("Se"), "s", .and(
          call("beforeOrEqualInExecution", .variable("execution"), .variable("s"), .variable("sp")),
          .or(
            .equal(
              .functionApply(.variable("s"), .recordAccess(.variable("operation"), "key")),
              .recordAccess(.variable("operation"), "value")
            ),
            .or(
              .exists(call("SeqToSet", .variable("transaction")), "write", .and(
                .and(
                  .equal(.recordAccess(.variable("write"), "op"), .value(.string("write"))),
                  .equal(
                    .recordAccess(.variable("write"), "key"),
                    .recordAccess(.variable("operation"), "key")
                  )
                ),
                .and(
                  .equal(
                    .recordAccess(.variable("write"), "value"),
                    .recordAccess(.variable("operation"), "value")
                  ),
                  call("earlierInTransaction", .variable("transaction"), .variable("write"), .variable("operation"))
                )
              )),
              .equal(.recordAccess(.variable("operation"), "op"), .value(.string("write")))
            )
          )
        ))
      )
    ))
    FormalDefinition("Preread", parameters: [.value("execution"), .value("transaction")], body: .forAll(
      call("SeqToSet", .variable("transaction")), "operation",
      .notEqual(
        call("ReadStates", .variable("execution"), .variable("operation"), .variable("transaction")),
        .setLiteral([])
      )
    ))
    FormalDefinition("PrereadAll", parameters: [.value("execution"), .value("transactions")], body: .forAll(
      .variable("transactions"), "transaction",
      call("Preread", .variable("execution"), .variable("transaction"))
    ))
    FormalDefinition("Complete", parameters: [.value("execution"), .value("transaction"), .value("state")], body: .letValue(
      "setOfAllReadStatesOfOperation",
      .setMap(
        call("ReadStates", .variable("execution"), .variable("operation"), .variable("transaction")),
        "operation", call("SeqToSet", .variable("transaction"))
      ),
      .letValue(
        "readStatesForEmptyTransaction",
        .setFilter(
          call("SeqToSet", call("executionStates", .variable("execution"))), "s",
          call(
            "beforeOrEqualInExecution", .variable("execution"), .variable("s"),
            call("parentState", .variable("execution"), .variable("transaction"))
          )
        ),
        .in(
          .variable("state"),
          call("INTERSECTION", .union(.variable("setOfAllReadStatesOfOperation"), .setLiteral([.variable("readStatesForEmptyTransaction")])))
        )
      )
    ))
    FormalDefinition("WriteSet", parameters: [.value("transaction")], body: .letValue(
      "writes",
      .setFilter(
        call("SeqToSet", .variable("transaction")), "operation",
        .equal(.recordAccess(.variable("operation"), "op"), .value(.string("write")))
      ),
      .setMap(.recordAccess(.variable("operation"), "key"), "operation", .variable("writes"))
    ))
    FormalDefinition("NoConf", parameters: [.value("execution"), .value("transaction"), .value("state")], body: .letValue(
      "Sp", call("parentState", .variable("execution"), .variable("transaction")),
      .letValue(
        "delta",
        .setFilter(.domain(.variable("Sp")), "key", .notEqual(
          .functionApply(.variable("Sp"), .variable("key")),
          .functionApply(.variable("state"), .variable("key"))
        )),
        .equal(
          .intersection(.variable("delta"), call("WriteSet", .variable("transaction"))),
          .setLiteral([])
        )
      )
    ))
    FormalDefinition("ComesStrictBefore", parameters: [.value("t1"), .value("t2"), .value("timestamps")], body: .lessThan(
      .recordAccess(.functionApply(.variable("timestamps"), .variable("t1")), "commit"),
      .recordAccess(.functionApply(.variable("timestamps"), .variable("t2")), "start")
    ))
    FormalDefinition("effects", parameters: [.value("state"), .value("transaction")], body: .operatorApplication(
      op("ReduceSeq", arity: 3), [
        .operator(.lambda(FormalLambda(parameters: ["o", "newState"], body: .ifThenElse(
          .equal(.recordAccess(.variable("o"), "op"), .value(.string("write"))),
          .except(
            .variable("newState"), .recordAccess(.variable("o"), "key"),
            .recordAccess(.variable("o"), "value")
          ),
          .variable("newState")
        )))),
        .value(.variable("transaction")), .value(.variable("state"))
      ]
    ))
    FormalDefinition("executions", parameters: [.value("initialState"), .value("transactions")], body: .letValue(
      "orderings", call("PermSeqs", .variable("transactions")),
      .letValue(
        "accummulator", .recordLiteral([
          "execution": .tupleLiteral([]), "nextState": .variable("initialState")
        ]),
        .setMap(
          .letValue(
            "executionAcc",
            .operatorApplication(
              op("ReduceSeq", arity: 3), [
                .operator(.lambda(FormalLambda(parameters: ["t", "acc"], body: .recordLiteral([
                "execution": .tupleAppend(
                  .recordAccess(.variable("acc"), "execution"),
                  .recordLiteral([
                    "parentState": .recordAccess(.variable("acc"), "nextState"),
                    "transaction": .variable("t")
                  ])
                ),
                "nextState": call("effects", .recordAccess(.variable("acc"), "nextState"), .variable("t"))
                ])))),
                .value(.variable("ordering")), .value(.variable("accummulator"))
              ]
            ),
            .recordAccess(.variable("executionAcc"), "execution")
          ),
          "ordering", .variable("orderings")
        )
      )
    ))
    FormalDefinition("executionSatisfiesCT", parameters: [
      .value("execution"), .operator("commitTest", arity: 2)
    ], body: .letValue(
      "transactions", call("executionTransactions", .variable("execution")),
      .forAll(
        .variable("transactions"), "transaction",
        .operatorApplication(op("commitTest", arity: 2), [
          .value(.variable("transaction")), .value(.variable("execution"))
        ])
      )
    ))
    FormalDefinition("satisfyIsolationLevel", parameters: [
      .value("initialState"), .value("transactions"), .operator("commitTest", arity: 2)
    ], body: .exists(
      call("executions", .variable("initialState"), .variable("transactions")), "execution",
      .forAll(
        .variable("transactions"), "transaction",
        .operatorApplication(op("commitTest", arity: 2), [
          .value(.variable("transaction")), .value(.variable("execution"))
        ])
      )
    ))
    FormalDefinition("CT_SER", parameters: [.value("transaction"), .value("execution")], body: call(
      "Complete", .variable("execution"), .variable("transaction"),
      call("parentState", .variable("execution"), .variable("transaction"))
    ))
    FormalDefinition("Serializability", parameters: [.value("initialState"), .value("transactions")], body: .operatorApplication(
      op("satisfyIsolationLevel", arity: 3), [
        .value(.variable("initialState")), .value(.variable("transactions")), .operator(op("CT_SER", arity: 2))
      ]
    ))
    FormalDefinition("CT_SI", parameters: [.value("transaction"), .value("execution")], body: .exists(
      call("SeqToSet", call("executionStates", .variable("execution"))), "state",
      .and(
        call("Complete", .variable("execution"), .variable("transaction"), .variable("state")),
        call("NoConf", .variable("execution"), .variable("transaction"), .variable("state"))
      )
    ))
    FormalDefinition("SnapshotIsolation", parameters: [.value("initialState"), .value("transactions")], body: .operatorApplication(
      op("satisfyIsolationLevel", arity: 3), [
        .value(.variable("initialState")), .value(.variable("transactions")), .operator(op("CT_SI", arity: 2))
      ]
    ))
    FormalDefinition("CT_SSER", parameters: [.value("timestamps"), .value("transaction"), .value("execution")], body: .letValue(
      "Sp", call("parentState", .variable("execution"), .variable("transaction")),
      .and(
        call("Complete", .variable("execution"), .variable("transaction"), .variable("Sp")),
        .forAll(call("executionTransactions", .variable("execution")), "otherTransaction", .or(
          .not(call("ComesStrictBefore", .variable("otherTransaction"), .variable("transaction"), .variable("timestamps"))),
          call("beforeOrEqualInExecution", .variable("execution"),
               call("parentState", .variable("execution"), .variable("otherTransaction")), .variable("Sp"))
        ))
      )
    ))
    FormalDefinition("StrictSerializability", parameters: [.value("initialState"), .value("transactions"), .value("timestamps")], body: .exists(
      call("executions", .variable("initialState"), .variable("transactions")), "execution",
      .forAll(.variable("transactions"), "transaction", call(
        "CT_SSER", .variable("timestamps"), .variable("transaction"), .variable("execution")
      ))
    ))
    FormalDefinition("CT_RC", parameters: [.value("transaction"), .value("execution")], body: call(
      "Preread", .variable("execution"), .variable("transaction")
    ))
    FormalDefinition("ReadCommitted", parameters: [.value("initialState"), .value("transactions")], body: .operatorApplication(
      op("satisfyIsolationLevel", arity: 3), [
        .value(.variable("initialState")), .value(.variable("transactions")), .operator(op("CT_RC", arity: 2))
      ]
    ))
    FormalDefinition("CT_RU", parameters: [.value("transaction"), .value("execution")], body: .value(.bool(true)))
    FormalDefinition("ReadUncommitted", parameters: [.value("initialState"), .value("transactions")], body: .operatorApplication(
      op("satisfyIsolationLevel", arity: 3), [
        .value(.variable("initialState")), .value(.variable("transactions")), .operator(op("CT_RU", arity: 2))
      ]
    ))
    // TLC's Print is intentionally source-only: diagnostics are not state
    // semantics and are outside the executable formal evaluator boundary.
    // It follows the formal definitions it names because TLA+ declarations
    // are resolved in source order.
    Definition("SerializabilityDebug(initialState, transactions) == ~ Serializability(initialState, transactions) => Print(<<\"Executions not Serializable:\", executions(initialState, transactions)>>, FALSE)")
  }
}
