-------------------- MODULE FrameActionRule --------------------
EXTENDS TLAPS

CONSTANTS Vars, Values, ActionLabels
States == [Vars -> Values]
LabeledEdges == States \X ActionLabels \X States

ApplyDelta(s, keys, delta) ==
    [key \in Vars |-> IF key \in keys THEN delta[key] ELSE s[key]]

RenderedDelta(s, t, keys, delta) ==
    /\ \A key \in keys : t[key] = delta[key]
    /\ \A key \in Vars \ keys : t[key] = s[key]

THEOREM CompleteDeltaUpdate ==
    \A keys \in SUBSET Vars :
        \A s, t \in States :
            \A delta \in [keys -> Values] :
                (t = ApplyDelta(s, keys, delta)) <=> RenderedDelta(s, t, keys, delta)
    BY SMT DEF ApplyDelta, RenderedDelta, States

SourceFramedDelta(s, t, frame, keys, delta) ==
    /\ t[frame] = s[frame]
    /\ \A key \in keys : t[key] = delta[key]
    /\ \A key \in Vars \ keys : t[key] = s[key]

CompiledFramedDelta(s, t, frame, keys, delta) ==
    /\ (frame \in keys => delta[frame] = s[frame])
    /\ t = ApplyDelta(s, keys, delta)

RenderedFramedDelta(s, t, frame, keys, delta) ==
    /\ t[frame] = s[frame]
    /\ RenderedDelta(s, t, keys, delta)

THEOREM UnchangedConjunctionPreservesCompleteState ==
    ASSUME NEW frame \in Vars,
           NEW keys \in SUBSET Vars,
           NEW s \in States,
           NEW t \in States,
           NEW delta \in [keys -> Values]
    PROVE /\ (SourceFramedDelta(s, t, frame, keys, delta)
                <=> CompiledFramedDelta(s, t, frame, keys, delta))
          /\ (CompiledFramedDelta(s, t, frame, keys, delta)
                <=> RenderedFramedDelta(s, t, frame, keys, delta))
    PROOF
    <1>1. SourceFramedDelta(s, t, frame, keys, delta)
            <=> RenderedFramedDelta(s, t, frame, keys, delta)
        BY SMT DEF SourceFramedDelta, RenderedFramedDelta, RenderedDelta
    <1>2. CompiledFramedDelta(s, t, frame, keys, delta)
            <=> SourceFramedDelta(s, t, frame, keys, delta)
        BY CompleteDeltaUpdate, SMT
            DEF CompiledFramedDelta, SourceFramedDelta, RenderedDelta, States
    <1>. QED BY <1>1, <1>2, SMT

\* These general relations and lemmas were moved from SingleAssignment.
\* Only the complete-state observation is shared between the three rules.
FrameObservation(prior, label, successors, none) ==
    [source |-> prior, action |-> label, successors |-> successors,
     selectedFailure |-> none, disabled |-> successors = {}]

SourceFrameObservation(s, label, frame, keys, delta, none) ==
    FrameObservation(s, label,
        {t \in States : SourceFramedDelta(s, t, frame, keys, delta)}, none)
CompiledFrameObservation(s, label, frame, keys, delta, none) ==
    FrameObservation(s, label,
        {t \in States : CompiledFramedDelta(s, t, frame, keys, delta)}, none)
TLAFrameObservation(s, label, frame, keys, delta, none) ==
    FrameObservation(s, label,
        {t \in States : RenderedFramedDelta(s, t, frame, keys, delta)}, none)

THEOREM FrameRulePreservesCompleteLabeledOutcomes ==
    ASSUME NEW s \in States, NEW label \in ActionLabels,
           NEW frame \in Vars, NEW keys \in SUBSET Vars,
           NEW delta \in [keys -> Values], NEW none
    PROVE /\ SourceFrameObservation(s, label, frame, keys, delta, none) =
                 CompiledFrameObservation(s, label, frame, keys, delta, none)
          /\ CompiledFrameObservation(s, label, frame, keys, delta, none) =
                 TLAFrameObservation(s, label, frame, keys, delta, none)
    PROOF
    <1>1. \A t \in States :
              /\ (SourceFramedDelta(s, t, frame, keys, delta)
                    <=> CompiledFramedDelta(s, t, frame, keys, delta))
              /\ (CompiledFramedDelta(s, t, frame, keys, delta)
                    <=> RenderedFramedDelta(s, t, frame, keys, delta))
        BY UnchangedConjunctionPreservesCompleteState, SMT
    <1>. QED BY <1>1, SMT
        DEF SourceFrameObservation, CompiledFrameObservation, TLAFrameObservation,
            FrameObservation

THEOREM ConflictingFramesDisableRatherThanFail ==
    ASSUME NEW s \in States, NEW label \in ActionLabels,
           NEW frame \in Vars, NEW keys \in SUBSET Vars,
           NEW delta \in [keys -> Values],
           frame \in keys, delta[frame] # s[frame], NEW none
    PROVE LET observed == CompiledFrameObservation(s, label, frame, keys, delta, none)
          IN /\ observed.successors = {}
             /\ observed.selectedFailure = none
             /\ observed.disabled
    BY SMT DEF CompiledFrameObservation, FrameObservation, CompiledFramedDelta

THEOREM OmittingAConflictingFrameChangesTheRelation ==
    ASSUME NEW s \in States, NEW t \in States,
           NEW frame \in Vars, NEW keys \in SUBSET Vars,
           NEW delta \in [keys -> Values],
           frame \in keys, delta[frame] # s[frame],
           RenderedDelta(s, t, keys, delta)
    PROVE ~RenderedFramedDelta(s, t, frame, keys, delta)
    BY SMT DEF RenderedFramedDelta, RenderedDelta

=============================================================================
