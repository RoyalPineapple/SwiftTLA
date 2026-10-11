--------------------- MODULE RankedChoiceProof ---------------------
EXTENDS TLAPS, Integers, Sequences

Members(order) == {order[index] : index \in 1..Len(order)}
Matches(order, predicate) ==
    {member \in Members(order) : predicate[member]}
FirstIndices(order, predicate) ==
    {index \in 1..Len(order) :
        predicate[order[index]]
        /\ \A earlier \in 1..(index - 1) : ~predicate[order[earlier]]}
IncreasingRanks(order, rank) ==
    \A earlier, later \in 1..Len(order) :
        earlier < later => rank[order[earlier]] < rank[order[later]]
RankedChoice(order, rank, predicate) ==
    LET candidates == Matches(order, predicate)
    IN CHOOSE member \in candidates :
        \A other \in candidates : rank[member] <= rank[other]

THEOREM FirstMatchIsUniqueRankMinimum ==
    ASSUME NEW Values,
           NEW order \in Seq(Values),
           NEW rank \in [Members(order) -> Int],
           NEW predicate \in [Members(order) -> BOOLEAN],
           IncreasingRanks(order, rank),
           NEW first \in FirstIndices(order, predicate)
    PROVE /\ order[first] \in Matches(order, predicate)
          /\ \A other \in Matches(order, predicate) :
                 rank[order[first]] <= rank[other]
          /\ \A member \in Matches(order, predicate) :
                 (\A other \in Matches(order, predicate) :
                     rank[member] <= rank[other])
                 => member = order[first]
    BY SMT DEF Members, Matches, FirstIndices, IncreasingRanks

THEOREM RankedChoiceMatchesFirst ==
    ASSUME NEW Values,
           NEW order \in Seq(Values),
           NEW rank \in [Members(order) -> Int],
           NEW predicate \in [Members(order) -> BOOLEAN],
           IncreasingRanks(order, rank),
           NEW first \in FirstIndices(order, predicate)
    PROVE RankedChoice(order, rank, predicate) = order[first]
    BY FirstMatchIsUniqueRankMinimum, SMT
        DEF RankedChoice, Matches

THEOREM NoMatchIsEmptyCandidateSet ==
    ASSUME NEW Values,
           NEW order \in Seq(Values),
           NEW predicate \in [Members(order) -> BOOLEAN]
    PROVE (\A index \in 1..Len(order) : ~predicate[order[index]])
        <=> (Matches(order, predicate) = {})
    BY SMT DEF Matches, Members

SourceEdges(order, predicate, state, label, update) ==
    {<<state, label, update[order[index]]>> :
        index \in FirstIndices(order, predicate)}
RenderedEdges(order, rank, predicate, state, label, update) ==
    IF Matches(order, predicate) = {} THEN {}
    ELSE {<<state, label, update[RankedChoice(order, rank, predicate)]>>}
SourceFailures(order, predicate, state, label) ==
    IF \A index \in 1..Len(order) : ~predicate[order[index]]
    THEN {<<state, label, "noSatisfyingChoice">>} ELSE {}
RenderedFailures(order, predicate, state, label) ==
    IF Matches(order, predicate) = {}
    THEN {<<state, label, "noSatisfyingChoice">>} ELSE {}

THEOREM RankedChoicePreservesCompleteEdgesAndFailures ==
    ASSUME NEW Values,
           NEW States,
           NEW order \in Seq(Values),
           NEW rank \in [Members(order) -> Int],
           NEW predicate \in [Members(order) -> BOOLEAN],
           NEW update \in [Members(order) -> States],
           NEW state \in States,
           NEW label,
           IncreasingRanks(order, rank),
           Matches(order, predicate) = {}
               \/ FirstIndices(order, predicate) # {}
    PROVE /\ SourceEdges(order, predicate, state, label, update)
                 = RenderedEdges(order, rank, predicate, state, label, update)
          /\ SourceFailures(order, predicate, state, label)
                 = RenderedFailures(order, predicate, state, label)
    BY RankedChoiceMatchesFirst, NoMatchIsEmptyCandidateSet, SMT
        DEF SourceEdges, RenderedEdges, SourceFailures, RenderedFailures,
            FirstIndices, Matches

=====================================================================
