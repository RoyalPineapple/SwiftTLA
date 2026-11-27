---------------- MODULE CheckedViewInvariantRule ----------------
EXTENDS TLAPS

\* A successful view preserves its operand. When a read or a view fails,
\* propagate the complete event (including site, payload and before-bindings).
CheckedRead(input, conforms(_), onMismatch) ==
    IF input.ok
    THEN IF conforms(input.value) THEN input ELSE onMismatch
    ELSE input

ContinueWithView(first, continueOn, lhs(_), rhs(_), nextRead) ==
    IF first.ok THEN
        LET l == lhs(first.value) IN
        IF l.ok THEN
            IF l.value = continueOn
            THEN IF nextRead.ok THEN rhs(nextRead.value) ELSE nextRead
            ELSE l
        ELSE l
    ELSE first

THEOREM RepeatedCheckedReadHasTheSameCompleteOutcome ==
    ASSUME NEW input, NEW conforms(_), NEW mismatch, NEW laterMismatch, NEW continueOn,
           NEW lhs(_), NEW rhs(_),
           input.ok \in BOOLEAN, mismatch.ok = FALSE,
           input.ok => conforms(input.value) \in BOOLEAN
    PROVE LET first == CheckedRead(input, conforms, mismatch) IN
              ContinueWithView(first, continueOn, lhs, rhs, CheckedRead(input, conforms, laterMismatch)) =
              ContinueWithView(first, continueOn, lhs, rhs, input)
    BY SMT DEF CheckedRead, ContinueWithView

\* The invariant consumer maps whole outcomes over reached states. It can
\* retain failure events even when no Boolean verdict exists for that state.
THEOREM SelectedInvariantRetainsAllCheckedReadOutcomes ==
    ASSUME NEW reached, NEW input(_), NEW conforms(_), NEW mismatch(_), NEW laterMismatch(_),
           NEW continueOn, NEW lhs(_, _), NEW rhs(_, _),
           \A s \in reached : /\ input(s).ok \in BOOLEAN
                              /\ mismatch(s).ok = FALSE
                              /\ (input(s).ok => conforms(input(s).value) \in BOOLEAN)
    PROVE LET Result(s, reuse) ==
                LET first == CheckedRead(input(s), conforms, mismatch(s))
                    left(v) == lhs(s, v)
                    right(v) == rhs(s, v)
                IN ContinueWithView(first, continueOn, left, right,
                                    IF reuse THEN input(s) ELSE CheckedRead(input(s), conforms, laterMismatch(s)))
          IN [s \in reached |-> Result(s, FALSE)] = [s \in reached |-> Result(s, TRUE)]
    PROOF
    <1>1. ASSUME NEW s \in reached
          PROVE LET first == CheckedRead(input(s), conforms, mismatch(s))
                    left(v) == lhs(s, v)
                    right(v) == rhs(s, v)
                IN ContinueWithView(first, continueOn, left, right, CheckedRead(input(s), conforms, laterMismatch(s))) =
                   ContinueWithView(first, continueOn, left, right, input(s))
          BY RepeatedCheckedReadHasTheSameCompleteOutcome
    <1>. QED BY <1>1, SMT
=====================================================================
