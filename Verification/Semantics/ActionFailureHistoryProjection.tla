-------------------- MODULE ActionFailureHistoryProjection --------------------
EXTENDS TLAPS

\* Membership forgets position. The input sequence still retains every occurrence.
ActionFailureEventSet(history) == {history[index] : index \in DOMAIN history}

THEOREM ActionFailureEventSetHasExactMembership ==
    ASSUME NEW history, NEW event
    PROVE (event \in ActionFailureEventSet(history))
          <=> (\E index \in DOMAIN history : history[index] = event)
    BY SMT DEF ActionFailureEventSet

====
