---- MODULE FiniteAssignmentTraceQuantifiedInduction ----
EXTENDS FiniteAssignmentTraceInduction

TraceInputSequences(shapes) ==
    \A entry : TraceReady(entry, shapes) => entry.values \in Seq(shapes)

TraceInputHeads(shapes) ==
    \A entry : TraceReady(entry, shapes) /\ entry.values # <<>> =>
         \E context : HeadTracePostcondition(entry, shapes, context)

TraceOutputFor(shapes) ==
    \A entry :
        TraceReady(entry, shapes) =>
            \E trace : FiniteScheduleReturns(entry, trace)
                       /\ TraceSupportedAssignmentList(trace.rows)
                       /\ TracePreservesOccurrences(entry, trace.rows)
                       /\ TraceStatesAreReady(trace, shapes)
                       /\ Len(trace.rows) = Len(entry.values)

THEOREM TheFiniteReturnFollowsFromTheHeadAndSequenceInputs ==
    \A shapes : TraceInputSequences(shapes) /\ TraceInputHeads(shapes) => TraceOutputFor(shapes)
PROOF
<1>. TAKE shapes
<1>. SUFFICES ASSUME TraceInputSequences(shapes), TraceInputHeads(shapes)
              PROVE TraceOutputFor(shapes)
    OBVIOUS
<1>sequences. \A entry : TraceReady(entry, shapes) => entry.values \in Seq(shapes)
    BY ONLY TraceInputSequences(shapes) DEF TraceInputSequences
<1>heads. \A entry : TraceReady(entry, shapes) /\ entry.values # <<>> =>
         \E context : HeadTracePostcondition(entry, shapes, context)
    BY ONLY TraceInputHeads(shapes) DEF TraceInputHeads
<1>. QED BY ONLY <1>sequences, <1>heads, HeadAndTailConstructTheFiniteReturn, SMT DEF TraceOutputFor
====
