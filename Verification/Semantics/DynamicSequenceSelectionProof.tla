---------------- MODULE DynamicSequenceSelectionProof ----------------
EXTENDS TLAPS, DynamicSequenceSelection

Members == {<<1>>, <<1, 0>>, <<2>>}
Rank(value) ==
    CASE value = <<1>> -> 0
      [] value = <<1, 0>> -> 1
      [] value = <<2>> -> 2
LexLE(left, right) ==
    \/ left = right
    \/ (\E index \in 1..Len(left) :
          IF index <= Len(right)
          THEN ((\A prefix \in 1..(index - 1) : left[prefix] = right[prefix])
                /\ left[index] < right[index])
          ELSE FALSE)
    \/ (IF Len(left) < Len(right)
        THEN (\A prefix \in 1..Len(left) : left[prefix] = right[prefix])
        ELSE FALSE)
SourceFirst(values) ==
    CHOOSE member \in values :
        \A other \in values : Rank(member) <= Rank(other)
SourceInit == pc = "select" /\ candidates = Members /\ selected = <<2>>
SourceSelect ==
    pc = "select" /\ candidates # {} /\
    selected' = SourceFirst(candidates) /\ pc' = "Done" /\
    UNCHANGED candidates
SourceTerminating == pc = "Done" /\ UNCHANGED <<pc, candidates, selected>>
SourceFailure == pc = "select" /\ candidates = {}
SourceLabeled(label) ==
    \/ label = "select" /\ SourceSelect
    \/ label = "Terminating" /\ SourceTerminating
EmittedLabeled(label) ==
    \/ label = "select" /\ select
    \/ label = "Terminating" /\ Terminating

THEOREM SequenceOrderMatchesRank ==
    \A left, right \in Members :
        LexLE(left, right) <=> Rank(left) <= Rank(right)
    BY SMT DEF Members, LexLE, Rank

THEOREM CandidateMinimumPredicatesAgree ==
    ASSUME candidates \subseteq Members
    PROVE \A member \in candidates :
        (\A other \in candidates : LexLE(member, other))
          <=> (\A other \in candidates : Rank(member) <= Rank(other))
    BY SequenceOrderMatchesRank, SMT

THEOREM RankMinimumExistsUnique ==
    ASSUME candidates \subseteq Members, candidates # {}
    PROVE \E member \in candidates :
        /\ (\A other \in candidates : Rank(member) <= Rank(other))
        /\ (\A another \in candidates :
              (\A other \in candidates : Rank(another) <= Rank(other))
                => another = member)
    BY SMT DEF Members, Rank

THEOREM CanonicalChoiceAgrees ==
    ASSUME candidates \subseteq Members, candidates # {}
    PROVE (CHOOSE member \in candidates :
              \A other \in candidates : LexLE(member, other))
          = SourceFirst(candidates)
    BY CandidateMinimumPredicatesAgree, RankMinimumExistsUnique,
        SMT DEF SourceFirst

THEOREM InitialStatesAgree ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit, Members

THEOREM EmittedInitialChoiceUsesMinimum ==
    ASSUME candidates = Members
    PROVE select <=>
        (pc = "select" /\ selected' = <<1>> /\
         pc' = "Done" /\ UNCHANGED candidates)
    BY SMT DEF select, Members

THEOREM SourceInitialChoiceUsesMinimum ==
    SourceFirst(Members) = <<1>>
    BY SMT DEF SourceFirst, Members, Rank

THEOREM EmittedSelectPreservesSourceStep ==
    ASSUME candidates = Members
    PROVE select <=> SourceSelect
    BY EmittedInitialChoiceUsesMinimum,
        SourceInitialChoiceUsesMinimum, SMT
        DEF SourceSelect, Members

THEOREM CompleteLabeledRelationAgrees ==
    ASSUME candidates = Members, NEW label
    PROVE /\ (select <=> SourceSelect)
          /\ (Terminating <=> SourceTerminating)
          /\ (EmittedLabeled(label) <=> SourceLabeled(label))
          /\ (Next <=> (SourceSelect \/ SourceTerminating))
    BY EmittedSelectPreservesSourceStep, SMT
        DEF Terminating, SourceTerminating, EmittedLabeled,
            SourceLabeled, Next

THEOREM SelectedFailureAndCheckingInvariantAgree ==
    /\ (__SwiftTLAChoiceFailure0 <=> SourceFailure)
    /\ (__SwiftTLAAnyEvaluationFailure0 <=> SourceFailure)
    /\ (__SwiftTLAEvaluationOK <=> ~SourceFailure)
    BY SMT DEF __SwiftTLAChoiceFailure0, __SwiftTLAAnyEvaluationFailure0,
        __SwiftTLAEvaluationOK,
        SourceFailure

THEOREM CandidateUniverseIsReachableInvariant ==
    /\ (Init => candidates = Members)
    /\ ((candidates = Members /\ Next) => candidates' = Members)
    BY SMT DEF Init, Next, select, Terminating, Members

WrongLast ==
    pc = "select" /\ selected' = <<2>> /\ pc' = "Done" /\
    UNCHANGED candidates

THEOREM ReversedOrderChangesSelectedEdge ==
    ASSUME SourceInit
    PROVE /\ ENABLED WrongLast
          /\ ~(WrongLast /\ select)
    BY CompleteLabeledRelationAgrees, ExpandENABLED, SMT
        DEF SourceInit, WrongLast, SourceSelect, SourceFirst,
            Members, Rank, select

======================================================================
