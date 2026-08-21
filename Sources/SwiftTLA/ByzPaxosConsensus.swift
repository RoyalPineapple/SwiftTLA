/// The typed abstract consensus model used by VoteProof's refinement.
public enum ByzPaxosConsensus {
  public static let Value = FormalModuleParameter("Value")
  public static let chosen = Var<SetExpr<TLAValue>>("chosen", SetExpr())

  public static let module = TLASpec("Consensus") {
    Value
    Variable(chosen)
    Action("Next") {
      .and(
        .guard_(chosen.stateExpr == SetExpr<TLAValue>()),
        .existsAction(
          "candidate",
          from: Value.stateExpr,
          .assign(chosen.name, .singleton(.variable("candidate")))
        )
      )
    }
    Eventually("Success", .notEqual(chosen.stateExpr, SetExpr<TLAValue>().stateExpr))
    RequireCapability(.temporalFairnessSpecification)
    RequireCapability(.temporalEquivalence)
  }
}
