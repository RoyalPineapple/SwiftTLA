---- MODULE Boulanger ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, num, flag, unchecked, max, nxt, previous

vars == <<pc, num, flag, unchecked, max, nxt, previous>>

MutualExclusion == \A __binder_Boulanger_123_21 \in {1, 2} : \A __binder_Boulanger_124_25 \in {1, 2} : (IF (__binder_Boulanger_123_21 = __binder_Boulanger_124_25) THEN TRUE ELSE (~((pc[__binder_Boulanger_123_21] = "cs") /\ (pc[__binder_Boulanger_124_25] = "cs"))))
LocalTypeOK == \A _process \in {1, 2} : ((max[_process] >= 0) /\ (previous[_process] >= -1))

StateConstraint == \A __binder_Boulanger_121_33 \in {1, 2} : (num[__binder_Boulanger_121_33] < 3)

Init ==
  /\ pc = [__pcal_initial_process \in {1, 2} |-> CASE (__pcal_initial_process \in {1, 2}) -> "ncs"]
  /\ num = [_typedFunctionEntry \in {1, 2} |-> CASE (_typedFunctionEntry = 1) -> 0 [] (_typedFunctionEntry = 2) -> 0]
  /\ flag = [_typedFunctionEntry \in {1, 2} |-> CASE (_typedFunctionEntry = 1) -> FALSE [] (_typedFunctionEntry = 2) -> FALSE]
  /\ unchecked = [__pcal_initial_process \in {1, 2} |-> {}]
  /\ max = [__pcal_initial_process \in {1, 2} |-> 0]
  /\ nxt = [__pcal_initial_process \in {1, 2} |-> 1]
  /\ previous = [__pcal_initial_process \in {1, 2} |-> -1]

ncs(_process) == (((((pc[_process] = "ncs") /\ TRUE) /\ (TRUE /\ pc' = [pc EXCEPT ![_process] = "e1"])) /\ ((UNCHANGED num /\ UNCHANGED flag) /\ (UNCHANGED unchecked /\ UNCHANGED max))) /\ (UNCHANGED nxt /\ UNCHANGED previous))
ncs__0 == ncs(1)
ncs__1 == ncs(2)
e1(_process) == ((((((pc[_process] = "e1") /\ TRUE) /\ (TRUE /\ flag' = [flag EXCEPT ![_process] = (IF (flag[_process] = TRUE) THEN FALSE ELSE TRUE)])) /\ ((pc' = [pc EXCEPT ![_process] = "e1"] /\ UNCHANGED num) /\ (UNCHANGED unchecked /\ UNCHANGED max))) /\ (UNCHANGED nxt /\ UNCHANGED previous)) \/ (((((pc[_process] = "e1") /\ TRUE) /\ (TRUE /\ flag' = [flag EXCEPT ![_process] = TRUE])) /\ ((unchecked' = [unchecked EXCEPT ![_process] = ({1, 2} \ {_process})] /\ max' = [max EXCEPT ![_process] = 0]) /\ (pc' = [pc EXCEPT ![_process] = "e2"] /\ UNCHANGED num))) /\ (UNCHANGED nxt /\ UNCHANGED previous)))
e1__0 == e1(1)
e1__1 == e1(2)
e2(_process) == (((((((pc[_process] = "e2") /\ (~(Cardinality(unchecked[_process]) = 0))) /\ (TRUE /\ \E __binder_Boulanger_54_25 \in unchecked[_process]: (((TRUE /\ unchecked' = [unchecked EXCEPT ![_process] = (unchecked[_process] \ {__binder_Boulanger_54_25})]) /\ ((num[__binder_Boulanger_54_25] > max[_process]) /\ TRUE)) /\ max' = [max EXCEPT ![_process] = num[__binder_Boulanger_54_25]]))) /\ ((pc' = [pc EXCEPT ![_process] = "e2"] /\ UNCHANGED num) /\ (UNCHANGED flag /\ UNCHANGED nxt))) /\ UNCHANGED previous) \/ (((((pc[_process] = "e2") /\ (~(Cardinality(unchecked[_process]) = 0))) /\ (TRUE /\ \E __binder_Boulanger_54_25 \in unchecked[_process]: ((TRUE /\ unchecked' = [unchecked EXCEPT ![_process] = (unchecked[_process] \ {__binder_Boulanger_54_25})]) /\ ((~(num[__binder_Boulanger_54_25] > max[_process])) /\ TRUE)))) /\ ((pc' = [pc EXCEPT ![_process] = "e2"] /\ UNCHANGED num) /\ (UNCHANGED flag /\ UNCHANGED max))) /\ (UNCHANGED nxt /\ UNCHANGED previous))) \/ (((((pc[_process] = "e2") /\ (~(~(Cardinality(unchecked[_process]) = 0)))) /\ (pc' = [pc EXCEPT ![_process] = "e3"] /\ UNCHANGED num)) /\ ((UNCHANGED flag /\ UNCHANGED unchecked) /\ (UNCHANGED max /\ UNCHANGED nxt))) /\ UNCHANGED previous))
e2__0 == e2(1)
e2__1 == e2(2)
e3(_process) == ((((((pc[_process] = "e3") /\ TRUE) /\ (TRUE /\ \E __binder_Boulanger_62_29 \in {0, 1, 2, 3}: ((TRUE /\ num' = [num EXCEPT ![_process] = __binder_Boulanger_62_29]) /\ pc' = [pc EXCEPT ![_process] = "e3"]))) /\ ((UNCHANGED flag /\ UNCHANGED unchecked) /\ (UNCHANGED max /\ UNCHANGED nxt))) /\ UNCHANGED previous) \/ (((((pc[_process] = "e3") /\ TRUE) /\ (TRUE /\ num' = [num EXCEPT ![_process] = (max[_process] + 1)])) /\ ((pc' = [pc EXCEPT ![_process] = "e4"] /\ UNCHANGED flag) /\ (UNCHANGED unchecked /\ UNCHANGED max))) /\ (UNCHANGED nxt /\ UNCHANGED previous)))
e3__0 == e3(1)
e3__1 == e3(2)
e4(_process) == ((((((pc[_process] = "e4") /\ TRUE) /\ (TRUE /\ flag' = [flag EXCEPT ![_process] = (IF (flag[_process] = TRUE) THEN FALSE ELSE TRUE)])) /\ ((pc' = [pc EXCEPT ![_process] = "e4"] /\ UNCHANGED num) /\ (UNCHANGED unchecked /\ UNCHANGED max))) /\ (UNCHANGED nxt /\ UNCHANGED previous)) \/ (((((pc[_process] = "e4") /\ TRUE) /\ (TRUE /\ flag' = [flag EXCEPT ![_process] = FALSE])) /\ ((unchecked' = [unchecked EXCEPT ![_process] = (IF (num[_process] = 1) THEN (IF (_process = 1) THEN {} ELSE (IF (_process = 2) THEN {1} ELSE {})) ELSE ({1, 2} \ {_process}))] /\ pc' = [pc EXCEPT ![_process] = "w1"]) /\ (UNCHANGED num /\ UNCHANGED max))) /\ (UNCHANGED nxt /\ UNCHANGED previous)))
e4__0 == e4(1)
e4__1 == e4(2)
w1(_process) == ((((((pc[_process] = "w1") /\ TRUE) /\ ((~(Cardinality(unchecked[_process]) = 0)) /\ TRUE)) /\ ((\E __binder_Boulanger_83_29 \in unchecked[_process]: (((TRUE /\ nxt' = [nxt EXCEPT ![_process] = __binder_Boulanger_83_29]) /\ ((~flag[__binder_Boulanger_83_29]) /\ previous' = [previous EXCEPT ![_process] = -1])) /\ pc' = [pc EXCEPT ![_process] = "w2"]) /\ UNCHANGED num) /\ (UNCHANGED flag /\ UNCHANGED unchecked))) /\ UNCHANGED max) \/ (((((pc[_process] = "w1") /\ TRUE) /\ ((~(~(Cardinality(unchecked[_process]) = 0))) /\ TRUE)) /\ ((pc' = [pc EXCEPT ![_process] = "cs"] /\ UNCHANGED num) /\ (UNCHANGED flag /\ UNCHANGED unchecked))) /\ ((UNCHANGED max /\ UNCHANGED nxt) /\ UNCHANGED previous)))
w1__0 == w1(1)
w1__1 == w1(2)
w2(_process) == (((((((pc[_process] = "w2") /\ TRUE) /\ ((IF (IF (IF (num[nxt[_process]] = 0) THEN TRUE ELSE (num[_process] < num[nxt[_process]])) THEN TRUE ELSE ((num[_process] = num[nxt[_process]]) /\ (_process \in (IF (nxt[_process] = 1) THEN {} ELSE (IF (nxt[_process] = 2) THEN {1} ELSE {}))))) THEN TRUE ELSE ((previous[_process] /= -1) /\ (num[nxt[_process]] /= previous[_process]))) /\ TRUE)) /\ ((LET __binder_Boulanger_94_29 == (unchecked[_process] \ {nxt[_process]}) IN (((TRUE /\ unchecked' = [unchecked EXCEPT ![_process] = __binder_Boulanger_94_29]) /\ ((Cardinality(__binder_Boulanger_94_29) = 0) /\ TRUE)) /\ pc' = [pc EXCEPT ![_process] = "cs"]) /\ UNCHANGED num) /\ (UNCHANGED flag /\ UNCHANGED max))) /\ (UNCHANGED nxt /\ UNCHANGED previous)) \/ (((((pc[_process] = "w2") /\ TRUE) /\ ((IF (IF (IF (num[nxt[_process]] = 0) THEN TRUE ELSE (num[_process] < num[nxt[_process]])) THEN TRUE ELSE ((num[_process] = num[nxt[_process]]) /\ (_process \in (IF (nxt[_process] = 1) THEN {} ELSE (IF (nxt[_process] = 2) THEN {1} ELSE {}))))) THEN TRUE ELSE ((previous[_process] /= -1) /\ (num[nxt[_process]] /= previous[_process]))) /\ TRUE)) /\ ((LET __binder_Boulanger_94_29 == (unchecked[_process] \ {nxt[_process]}) IN (((TRUE /\ unchecked' = [unchecked EXCEPT ![_process] = __binder_Boulanger_94_29]) /\ ((~(Cardinality(__binder_Boulanger_94_29) = 0)) /\ TRUE)) /\ pc' = [pc EXCEPT ![_process] = "w1"]) /\ UNCHANGED num) /\ (UNCHANGED flag /\ UNCHANGED max))) /\ (UNCHANGED nxt /\ UNCHANGED previous))) \/ (((((pc[_process] = "w2") /\ TRUE) /\ ((~(IF (IF (IF (num[nxt[_process]] = 0) THEN TRUE ELSE (num[_process] < num[nxt[_process]])) THEN TRUE ELSE ((num[_process] = num[nxt[_process]]) /\ (_process \in (IF (nxt[_process] = 1) THEN {} ELSE (IF (nxt[_process] = 2) THEN {1} ELSE {}))))) THEN TRUE ELSE ((previous[_process] /= -1) /\ (num[nxt[_process]] /= previous[_process])))) /\ TRUE)) /\ ((previous' = [previous EXCEPT ![_process] = num[nxt[_process]]] /\ pc' = [pc EXCEPT ![_process] = "w2"]) /\ (UNCHANGED num /\ UNCHANGED flag))) /\ ((UNCHANGED unchecked /\ UNCHANGED max) /\ UNCHANGED nxt)))
w2__0 == w2(1)
w2__1 == w2(2)
cs(_process) == (((((pc[_process] = "cs") /\ TRUE) /\ (TRUE /\ pc' = [pc EXCEPT ![_process] = "exit"])) /\ ((UNCHANGED num /\ UNCHANGED flag) /\ (UNCHANGED unchecked /\ UNCHANGED max))) /\ (UNCHANGED nxt /\ UNCHANGED previous))
cs__0 == cs(1)
cs__1 == cs(2)
exit(_process) == ((((((pc[_process] = "exit") /\ TRUE) /\ (TRUE /\ \E __binder_Boulanger_108_29 \in {0, 1, 2, 3}: ((TRUE /\ num' = [num EXCEPT ![_process] = __binder_Boulanger_108_29]) /\ pc' = [pc EXCEPT ![_process] = "exit"]))) /\ ((UNCHANGED flag /\ UNCHANGED unchecked) /\ (UNCHANGED max /\ UNCHANGED nxt))) /\ UNCHANGED previous) \/ (((((pc[_process] = "exit") /\ TRUE) /\ (TRUE /\ num' = [num EXCEPT ![_process] = 0])) /\ ((pc' = [pc EXCEPT ![_process] = "ncs"] /\ UNCHANGED flag) /\ (UNCHANGED unchecked /\ UNCHANGED max))) /\ (UNCHANGED nxt /\ UNCHANGED previous)))
exit__0 == exit(1)
exit__1 == exit(2)
Terminating == (((((TRUE /\ \A _process \in {1, 2} : (pc[_process] = "Done")) /\ UNCHANGED pc) /\ (UNCHANGED num /\ UNCHANGED flag)) /\ ((UNCHANGED unchecked /\ UNCHANGED max) /\ (UNCHANGED nxt /\ UNCHANGED previous))) /\ UNCHANGED pc)

Next ==
  \/ ncs__0
  \/ ncs__1
  \/ e1__0
  \/ e1__1
  \/ e2__0
  \/ e2__1
  \/ e3__0
  \/ e3__1
  \/ e4__0
  \/ e4__1
  \/ w1__0
  \/ w1__1
  \/ w2__0
  \/ w2__1
  \/ cs__0
  \/ cs__1
  \/ exit__0
  \/ exit__1
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, num, flag, unchecked, max, nxt, previous>>
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(ncs__0)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(ncs__1)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(e1__0)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(e1__1)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(e2__0)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(e2__1)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(e3__0)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(e3__1)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(e4__0)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(e4__1)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(w1__0)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(w1__1)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(w2__0)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(w2__1)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(cs__0)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(cs__1)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(exit__0)
  /\ WF_<<pc, num, flag, unchecked, max, nxt, previous>>(exit__1)

====
