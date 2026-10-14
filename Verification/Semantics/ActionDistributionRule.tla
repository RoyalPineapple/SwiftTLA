-------------------- MODULE ActionDistributionRule --------------------
EXTENDS TLAPS

CONSTANTS Deltas, CompatiblePairs, Merge, States, Apply, Source, Action

Conjoin(left, right) ==
    {Merge[pair] : pair \in (left \X right) \cap CompatiblePairs}

Edges(updates) ==
    {<<Source, Action, Apply[delta]>> : delta \in updates}

THEOREM AlternativeDistributionPreservesCompleteUpdates ==
    ASSUME NEW first \in SUBSET Deltas,
           NEW second \in SUBSET Deltas,
           NEW right \in SUBSET Deltas,
           CompatiblePairs \in SUBSET (Deltas \X Deltas),
           Merge \in [Deltas \X Deltas -> Deltas]
    PROVE Conjoin(first \cup second, right) =
          Conjoin(first, right) \cup Conjoin(second, right)
    BY SMT DEF Conjoin

THEOREM AlternativeDistributionPreservesLabeledEdges ==
    ASSUME NEW first \in SUBSET Deltas,
           NEW second \in SUBSET Deltas,
           NEW right \in SUBSET Deltas,
           CompatiblePairs \in SUBSET (Deltas \X Deltas),
           Merge \in [Deltas \X Deltas -> Deltas],
           Apply \in [Deltas -> States]
    PROVE Edges(Conjoin(first \cup second, right)) =
          Edges(Conjoin(first, right) \cup Conjoin(second, right))
    BY AlternativeDistributionPreservesCompleteUpdates, SMT DEF Edges

THEOREM DroppingAUniqueAlternativeChangesTheGraph ==
    ASSUME NEW first \in SUBSET Deltas,
           NEW second \in SUBSET Deltas,
           NEW right \in SUBSET Deltas,
           CompatiblePairs \in SUBSET (Deltas \X Deltas),
           Merge \in [Deltas \X Deltas -> Deltas],
           NEW distinct \in Conjoin(second, right),
           distinct \notin Conjoin(first, right)
    PROVE Conjoin(first \cup second, right) # Conjoin(first, right)
    BY AlternativeDistributionPreservesCompleteUpdates, SMT

=============================================================================
