-------------------- MODULE ActionOutcomeInterface --------------------
EXTENDS TLAPS, NaturalsInduction, SequenceTheorems_proofs

CONSTANTS UpdateValues, FailureValues, NoFailure

Outcome == [updates: SUBSET UpdateValues, failure: FailureValues \cup {NoFailure}]
OrderedOutcome == [updates: Seq(UpdateValues), failure: FailureValues \cup {NoFailure}]
EmptyOrdered == [updates |-> <<>>, failure |-> NoFailure]
ConditionOutcome == [enabled: BOOLEAN, failure: FailureValues \cup {NoFailure}]
SingleCandidateLeft ==
    {result \in OrderedOutcome :
        Len(result.updates) <= 1 /\
        (Len(result.updates) = 1 => result.failure = NoFailure)}

\* finish maps each pending update to the entire resulting state, including
\* hidden control state. The action includes every invocation argument.
CompleteLabeledOutcome(prior, action, finish, none, result) ==
    [source |-> prior,
     action |-> action,
     successors |-> {finish[result.updates[index]] :
                         index \in 1..Len(result.updates)},
     selectedFailure |-> result.failure,
     disabled |-> Len(result.updates) = 0 /\ result.failure = none]

THEOREM CompleteOutcomeRetainsStateIdentityAndDisabledness ==
    ASSUME NEW fields, NEW values,
           NEW prior \in [fields -> values], NEW label,
           NEW finish \in [UpdateValues -> [fields -> values]],
           NEW result \in OrderedOutcome
    PROVE LET observed == CompleteLabeledOutcome(prior, label, finish, NoFailure, result)
          IN /\ observed.source = prior /\ observed.action = label
             /\ observed.successors \in SUBSET [fields -> values]
             /\ observed.selectedFailure = result.failure
             /\ (observed.disabled <=>
                    observed.successors = {} /\ observed.selectedFailure = NoFailure)
    BY LenProperties, ElementOfSeq, SMT DEF CompleteLabeledOutcome, OrderedOutcome

=============================================================================
