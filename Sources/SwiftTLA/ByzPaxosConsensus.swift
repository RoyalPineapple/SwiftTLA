/// Source-faithful formal dependency for the upstream byzpaxos `Consensus`
/// module.
///
/// `VoteProof` instantiates this module with its same-named `Value` constant
/// and `chosen` refinement mapping, so both symbols remain formal parameters.
public enum ByzPaxosConsensus {
  public static let module = TLASpec("Consensus") {
    Extends("Naturals, FiniteSets, FiniteSetTheorems, TLAPS")
    Parameter("Value")
    Parameter("chosen", kind: .variable)

    Definition("vars == chosen")
    Definition("Init == chosen = {}")
    Definition("""
      Next == /\\ chosen = {}
              /\\ \\E v \\in Value:
                   chosen' = {v}
      """)
    Definition("Spec == Init /\\ [][Next]_vars")
    Definition("LiveSpec == Spec /\\ WF_vars(Next)")
    Definition("Success == <>(chosen # {})")
    Definition("LiveSpecEquals == LiveSpec <=> Spec /\\ ([]<><<Next>>_vars \\/ []<>(chosen # {}))")
  }
}
