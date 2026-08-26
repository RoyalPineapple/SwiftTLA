/// The typed abstract consensus model used by VoteProof's refinement.
public enum ByzPaxosConsensus {
  public static let valueParameter = FormalModuleParameter("Value")

  public static func chosen<Value: TLAValueType>(for _: Value.Type) -> Var<SetExpr<Value>> {
    Var("chosen", SetExpr())
  }

  public static func module<Value: TLAValueType>(for type: Value.Type) -> TLASpec {
    let chosen = chosen(for: type)
    return sourceModule(chosenDeclaration: Variable(chosen))
  }

  static func parsedModule(choiceTypeName: String) -> TLASpec {
    sourceModule(
      chosenDeclaration: VarDecl(
        "chosen",
        .set([]),
        generatedSwiftType: "SetExpr<\(choiceTypeName)>"
      )
    )
  }

  private static func sourceModule(chosenDeclaration: VarDecl) -> TLASpec {
    let chosen = StateExpr.variable(chosenDeclaration.name)
    return TLASpec("Consensus") {
      valueParameter
      chosenDeclaration
      Action("Next") {
        .and(
          .guard_(chosen == StateExpr.setLiteral([])),
          ActionExpr.exists("candidate", from: valueParameter) { candidate in
            .assign(.named(chosenDeclaration.name), .setLiteral([candidate]))
          }
        )
      }
      Eventually("Success", .notEqual(chosen, .setLiteral([])))
    }
  }
}
