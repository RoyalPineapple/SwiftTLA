-------------------- MODULE PendingWriteOutcomeRule --------------------
EXTENDS FrameActionRule, Sequences

CONSTANTS FailureValues, NoFailure

PendingUpdates == UNION {[keys -> Values] : keys \in SUBSET Vars}
Outcomes == INSTANCE ActionOutcomeInterface WITH UpdateValues <- PendingUpdates

Materialize(prior) ==
    [pending \in PendingUpdates |-> ApplyDelta(prior, DOMAIN pending, pending)]

SourcePendingWrite(pending, target, value) ==
    IF target \in DOMAIN pending /\ pending[target] # value
    THEN Outcomes!EmptyOrdered
    ELSE [updates |-> <<[key \in DOMAIN pending \cup {target} |->
                IF key \in DOMAIN pending THEN pending[key] ELSE value]>>,
          failure |-> NoFailure]

GeneratedPendingWrite(pending, target, value) ==
    IF target \notin DOMAIN pending \/ pending[target] = value
    THEN [updates |-> <<[key \in DOMAIN pending \cup {target} |->
                IF key = target THEN value ELSE pending[key]]>>,
          failure |-> NoFailure]
    ELSE Outcomes!EmptyOrdered

THEOREM PendingUpdatesHaveTypedDomains ==
    \A pending \in PendingUpdates :
        /\ DOMAIN pending \in SUBSET Vars
        /\ pending \in [DOMAIN pending -> Values]
    BY SMT DEF PendingUpdates

THEOREM PendingWriteRuleComposes ==
    ASSUME NEW pending \in PendingUpdates, NEW target \in Vars, NEW value \in Values
    PROVE /\ SourcePendingWrite(pending, target, value) =
                 GeneratedPendingWrite(pending, target, value)
          /\ SourcePendingWrite(pending, target, value) \in Outcomes!SingleCandidateLeft
    PROOF
    <1>1. DOMAIN pending \in SUBSET Vars /\ pending \in [DOMAIN pending -> Values]
        BY PendingUpdatesHaveTypedDomains, SMT
    <1>2. [key \in DOMAIN pending \cup {target} |->
                IF key \in DOMAIN pending THEN pending[key] ELSE value] \in PendingUpdates
        BY <1>1, SMT DEF PendingUpdates
    <1>3. (target \notin DOMAIN pending \/ pending[target] = value) =>
              [key \in DOMAIN pending \cup {target} |->
                  IF key \in DOMAIN pending THEN pending[key] ELSE value] =
              [key \in DOMAIN pending \cup {target} |->
                  IF key = target THEN value ELSE pending[key]]
        BY SMT
    <1>. QED BY <1>2, <1>3, SMT
        DEF SourcePendingWrite, GeneratedPendingWrite, Outcomes!EmptyOrdered,
            Outcomes!SingleCandidateLeft, Outcomes!OrderedOutcome

THEOREM MaterializationIsComplete ==
    ASSUME NEW prior \in States
    PROVE Materialize(prior) \in [PendingUpdates -> States]
    BY PendingUpdatesHaveTypedDomains, SMT DEF Materialize, ApplyDelta, States

THEOREM ConflictingWritesDisableWithoutFailure ==
    ASSUME NEW pending \in PendingUpdates, NEW target \in DOMAIN pending,
           NEW value \in Values, pending[target] # value
    PROVE /\ GeneratedPendingWrite(pending, target, value).updates = <<>>
          /\ GeneratedPendingWrite(pending, target, value).failure = NoFailure
    BY SMT DEF GeneratedPendingWrite, Outcomes!EmptyOrdered

=============================================================================
