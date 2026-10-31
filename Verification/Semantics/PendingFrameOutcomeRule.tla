-------------------- MODULE PendingFrameOutcomeRule --------------------
EXTENDS FrameActionRule, Sequences

CONSTANTS FailureValues, NoFailure

PendingUpdates == UNION {[keys -> Values] : keys \in SUBSET Vars}
Outcomes == INSTANCE ActionOutcomeInterface WITH UpdateValues <- PendingUpdates

Materialize(prior) ==
    [pending \in PendingUpdates |-> ApplyDelta(prior, DOMAIN pending, pending)]

\* The source retains every existing constraint and adds the prior-state frame.
SourcePendingFrame(prior, pending, frame) ==
    IF frame \in DOMAIN pending /\ pending[frame] # prior[frame]
    THEN Outcomes!EmptyOrdered
    ELSE [updates |-> <<[key \in DOMAIN pending \cup {frame} |->
                IF key \in DOMAIN pending THEN pending[key] ELSE prior[frame]]>>,
          failure |-> NoFailure]

\* Generated merging tests compatibility, then writes the incoming frame slot.
GeneratedPendingFrame(prior, pending, frame) ==
    IF frame \notin DOMAIN pending \/ pending[frame] = prior[frame]
    THEN [updates |-> <<[key \in DOMAIN pending \cup {frame} |->
                IF key = frame THEN prior[frame] ELSE pending[key]]>>,
          failure |-> NoFailure]
    ELSE Outcomes!EmptyOrdered

THEOREM PendingUpdatesHaveTypedDomains ==
    \A pending \in PendingUpdates :
        /\ DOMAIN pending \in SUBSET Vars
        /\ pending \in [DOMAIN pending -> Values]
    BY SMT DEF PendingUpdates

THEOREM PendingFrameRuleComposes ==
    ASSUME NEW prior \in States, NEW pending \in PendingUpdates,
           NEW frame \in Vars
    PROVE /\ SourcePendingFrame(prior, pending, frame) =
                 GeneratedPendingFrame(prior, pending, frame)
          /\ SourcePendingFrame(prior, pending, frame) \in Outcomes!SingleCandidateLeft
    PROOF
    <1>1. DOMAIN pending \in SUBSET Vars /\ pending \in [DOMAIN pending -> Values]
        BY PendingUpdatesHaveTypedDomains, SMT
    <1>2. [key \in DOMAIN pending \cup {frame} |->
                IF key \in DOMAIN pending THEN pending[key] ELSE prior[frame]] \in PendingUpdates
        BY <1>1, SMT DEF PendingUpdates, States
    <1>3. (frame \notin DOMAIN pending \/ pending[frame] = prior[frame]) =>
              [key \in DOMAIN pending \cup {frame} |->
                  IF key \in DOMAIN pending THEN pending[key] ELSE prior[frame]] =
              [key \in DOMAIN pending \cup {frame} |->
                  IF key = frame THEN prior[frame] ELSE pending[key]]
        BY SMT
    <1>. QED BY <1>2, <1>3, SMT
        DEF SourcePendingFrame, GeneratedPendingFrame, Outcomes!EmptyOrdered,
            Outcomes!SingleCandidateLeft, Outcomes!OrderedOutcome

THEOREM MaterializationIsComplete ==
    ASSUME NEW prior \in States
    PROVE Materialize(prior) \in [PendingUpdates -> States]
    BY PendingUpdatesHaveTypedDomains, SMT DEF Materialize, ApplyDelta, States

THEOREM PendingFramesPreserveCompleteLabeledOutcomes ==
    ASSUME NEW prior \in States, NEW pending \in PendingUpdates,
           NEW frame \in Vars, NEW label \in ActionLabels
    PROVE /\ Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                 SourcePendingFrame(prior, pending, frame)) =
                 SourceFrameObservation(prior, label, frame, DOMAIN pending, pending, NoFailure)
          /\ Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                 GeneratedPendingFrame(prior, pending, frame)) =
                 TLAFrameObservation(prior, label, frame, DOMAIN pending, pending, NoFailure)
    PROOF
    <1>1. DOMAIN pending \in SUBSET Vars /\ pending \in [DOMAIN pending -> Values]
        BY PendingUpdatesHaveTypedDomains, SMT
    <1>2. SourcePendingFrame(prior, pending, frame) = GeneratedPendingFrame(prior, pending, frame)
        BY PendingFrameRuleComposes
    <1>3. SourceFrameObservation(prior, label, frame, DOMAIN pending, pending, NoFailure) =
              TLAFrameObservation(prior, label, frame, DOMAIN pending, pending, NoFailure)
        BY <1>1, FrameRulePreservesCompleteLabeledOutcomes, SMT
    <1>4. Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
              SourcePendingFrame(prior, pending, frame)) =
              SourceFrameObservation(prior, label, frame, DOMAIN pending, pending, NoFailure)
        BY <1>1, CompleteDeltaUpdate, SMT
            DEF SourcePendingFrame, Materialize, PendingUpdates, ApplyDelta, States,
                SourceFrameObservation, FrameObservation, SourceFramedDelta,
                RenderedDelta, Outcomes!CompleteLabeledOutcome, Outcomes!EmptyOrdered
    <1>. QED BY <1>2, <1>3, <1>4, SMT

THEOREM ForgettingAFrameLosesTheLaterWriteConstraint ==
    ASSUME NEW prior \in States, NEW pending \in PendingUpdates,
           NEW frame \in Vars, frame \notin DOMAIN pending,
           NEW incoming \in Values, incoming # prior[frame]
    PROVE LET recorded == SourcePendingFrame(prior, pending, frame).updates[1]
          IN /\ SourcePendingFrame(prior, pending, frame) #
                    [updates |-> <<pending>>, failure |-> NoFailure]
             /\ frame \in DOMAIN recorded /\ recorded[frame] # incoming
             /\ frame \notin DOMAIN pending
    BY SMT DEF SourcePendingFrame

THEOREM AcceptingAConflictingFrameChangesTheOutcome ==
    ASSUME NEW prior \in States, NEW pending \in PendingUpdates,
           NEW frame \in DOMAIN pending, pending[frame] # prior[frame]
    PROVE SourcePendingFrame(prior, pending, frame) #
              [updates |-> <<pending>>, failure |-> NoFailure]
    BY SMT DEF SourcePendingFrame, Outcomes!EmptyOrdered

=============================================================================
