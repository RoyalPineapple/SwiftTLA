---- MODULE CanonicalUnicodeStringSelection ----
\* SwiftTLA formal strings: utf8-v1
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, selected

vars == <<pc, selected>>

select == (((pc = "select")) = TRUE /\ (IF (\E __SELECT_MEMBER__ \in {"__SwiftTLA_UTF8_V1__C3A9", "z"} : TRUE) THEN (LET __atomic_0 == (LET __CanonicalUnicodeStringSelection_choiceCandidates0 == {__SELECT_MEMBER__ \in {"__SwiftTLA_UTF8_V1__C3A9", "z"} : TRUE} IN (CHOOSE __SELECT_MEMBER__ \in __CanonicalUnicodeStringSelection_choiceCandidates0 : (\A __CanonicalUnicodeStringSelection_choiceOther1 \in __CanonicalUnicodeStringSelection_choiceCandidates0 : (CASE __SELECT_MEMBER__ = "z" -> 0 [] __SELECT_MEMBER__ = "__SwiftTLA_UTF8_V1__C3A9" -> 1) <= (CASE __CanonicalUnicodeStringSelection_choiceOther1 = "z" -> 0 [] __CanonicalUnicodeStringSelection_choiceOther1 = "__SwiftTLA_UTF8_V1__C3A9" -> 1)))) IN ((TRUE /\ selected' = __atomic_0) /\ pc' = "Done")) ELSE FALSE))
__SwiftTLAChoiceFailure0 == (((pc = "select")) = TRUE /\ ~((\E __SELECT_MEMBER__ \in {"__SwiftTLA_UTF8_V1__C3A9", "z"} : TRUE)))
__SwiftTLAAnyEvaluationFailure0 == (IF (pc = "select") THEN ~((\E __SELECT_MEMBER__ \in {"__SwiftTLA_UTF8_V1__C3A9", "z"} : TRUE)) ELSE FALSE)
Terminating == ((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED selected /\ UNCHANGED pc))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ pc = "select"
  /\ selected = "__SwiftTLA_UTF8_V1__C3A9"

Next ==
  \/ select
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, selected>>

====
