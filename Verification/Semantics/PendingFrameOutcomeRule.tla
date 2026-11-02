-------------------- MODULE PendingFrameOutcomeRule --------------------
EXTENDS PendingWriteOutcomeRule

\* The source retains every existing constraint and adds the prior-state frame.
SourcePendingFrame(prior, pending, frame) ==
    SourcePendingWrite(pending, frame, prior[frame])

\* Generated merging tests compatibility, then writes the incoming frame slot.
GeneratedPendingFrame(prior, pending, frame) ==
    GeneratedPendingWrite(pending, frame, prior[frame])

THEOREM PendingFrameRuleComposes ==
    ASSUME NEW prior \in States, NEW pending \in PendingUpdates,
           NEW frame \in Vars
    PROVE /\ SourcePendingFrame(prior, pending, frame) =
                 GeneratedPendingFrame(prior, pending, frame)
          /\ SourcePendingFrame(prior, pending, frame) \in Outcomes!SingleCandidateLeft
    BY PendingWriteRuleComposes, SMT DEF SourcePendingFrame, GeneratedPendingFrame, States

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
            DEF SourcePendingFrame, SourcePendingWrite, Materialize, PendingUpdates, ApplyDelta, States,
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
    BY SMT DEF SourcePendingFrame, SourcePendingWrite

THEOREM AcceptingAConflictingFrameChangesTheOutcome ==
    ASSUME NEW prior \in States, NEW pending \in PendingUpdates,
           NEW frame \in DOMAIN pending, pending[frame] # prior[frame]
    PROVE SourcePendingFrame(prior, pending, frame) #
              [updates |-> <<pending>>, failure |-> NoFailure]
    BY SMT DEF SourcePendingFrame, SourcePendingWrite, Outcomes!EmptyOrdered

=============================================================================
