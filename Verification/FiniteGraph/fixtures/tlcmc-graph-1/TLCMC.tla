---- MODULE TLCMC ----
EXTENDS Integers, Sequences, FiniteSets

VARIABLES pc, frontier, closed, currentState, successors, initialIndex, counterexample, predecessorEdges, levels

vars == <<pc, frontier, closed, currentState, successors, initialIndex, counterexample, predecessorEdges, levels>>

TypeOK == (closed \subseteq {1, 2, 3, 4})
BFSLevel == (initialIndex >= 1)
__pcal_assert_0 == (IF (~((pc = "checkInitialStates") /\ TRUE)) THEN TRUE ELSE (closed = {1, 2}))
__pcal_assert_1 == (IF (~(((pc = "trace") /\ TRUE) /\ (TRUE /\ (Head(counterexample) \in {1, 2})))) THEN TRUE ELSE (Len(counterexample) > 0))

Init ==
  /\ pc = "scanInitialStates"
  /\ frontier \in {<<1, 2>>, <<2, 1>>}
  /\ closed = {}
  /\ currentState = "null"
  /\ successors = {}
  /\ initialIndex = 1
  /\ counterexample = <<>>
  /\ predecessorEdges = <<>>
  /\ levels = [__tla_fn_0 \in {} |-> TRUE]

scanInitialStates == (((((((pc = "scanInitialStates") /\ (initialIndex <= Len(frontier))) /\ (TRUE /\ currentState' = frontier[initialIndex])) /\ ((closed' = (closed \cup {frontier[initialIndex]}) /\ levels' = [__binder_StateExpr_354_22 \in (DOMAIN levels \cup {frontier[initialIndex]}) |-> (IF (__binder_StateExpr_354_22 = frontier[initialIndex]) THEN 0 ELSE levels[__binder_StateExpr_354_22])]) /\ (initialIndex' = (initialIndex + 1) /\ (frontier[initialIndex] \in {4})))) /\ (((TRUE /\ counterexample' = <<frontier[initialIndex]>>) /\ (pc' = "trace" /\ UNCHANGED frontier)) /\ (UNCHANGED successors /\ UNCHANGED predecessorEdges))) \/ (((((pc = "scanInitialStates") /\ (initialIndex <= Len(frontier))) /\ (TRUE /\ currentState' = frontier[initialIndex])) /\ ((closed' = (closed \cup {frontier[initialIndex]}) /\ levels' = [__binder_StateExpr_354_22 \in (DOMAIN levels \cup {frontier[initialIndex]}) |-> (IF (__binder_StateExpr_354_22 = frontier[initialIndex]) THEN 0 ELSE levels[__binder_StateExpr_354_22])]) /\ (initialIndex' = (initialIndex + 1) /\ (~(frontier[initialIndex] \in {4}))))) /\ (((TRUE /\ pc' = "scanInitialStates") /\ (UNCHANGED frontier /\ UNCHANGED successors)) /\ (UNCHANGED counterexample /\ UNCHANGED predecessorEdges)))) \/ (((((pc = "scanInitialStates") /\ (~(initialIndex <= Len(frontier)))) /\ (pc' = "checkInitialStates" /\ UNCHANGED frontier)) /\ ((UNCHANGED closed /\ UNCHANGED currentState) /\ (UNCHANGED successors /\ UNCHANGED initialIndex))) /\ ((UNCHANGED counterexample /\ UNCHANGED predecessorEdges) /\ UNCHANGED levels)))
checkInitialStates == (((((pc = "checkInitialStates") /\ TRUE) /\ (TRUE /\ pc' = "dequeue")) /\ ((UNCHANGED frontier /\ UNCHANGED closed) /\ (UNCHANGED currentState /\ UNCHANGED successors))) /\ ((UNCHANGED initialIndex /\ UNCHANGED counterexample) /\ (UNCHANGED predecessorEdges /\ UNCHANGED levels)))
dequeue == (((((((pc = "dequeue") /\ TRUE) /\ ((Len(frontier) = 0) /\ TRUE)) /\ ((pc' = "Done" /\ UNCHANGED frontier) /\ (UNCHANGED closed /\ UNCHANGED currentState))) /\ (((UNCHANGED successors /\ UNCHANGED initialIndex) /\ (UNCHANGED counterexample /\ UNCHANGED predecessorEdges)) /\ UNCHANGED levels)) \/ (((((pc = "dequeue") /\ TRUE) /\ ((~(Len(frontier) = 0)) /\ TRUE)) /\ ((currentState' = frontier[1] /\ frontier' = (SubSeq(frontier, 1, (1 - 1)) \o SubSeq(frontier, (1 + 1), Len(frontier)))) /\ (successors' = (([_typedFunctionEntry \in {1, 2, 3, 4} |-> CASE (_typedFunctionEntry = 1) -> {2} [] (_typedFunctionEntry = 2) -> {1, 3} [] (_typedFunctionEntry = 3) -> {4} [] (_typedFunctionEntry = 4) -> {3}][frontier[1]] \ {frontier[1]}) \ closed) /\ (Cardinality(([_typedFunctionEntry \in {1, 2, 3, 4} |-> CASE (_typedFunctionEntry = 1) -> {2} [] (_typedFunctionEntry = 2) -> {1, 3} [] (_typedFunctionEntry = 3) -> {4} [] (_typedFunctionEntry = 4) -> {3}][frontier[1]] \ {frontier[1]})) = 0)))) /\ (((TRUE /\ counterexample' = <<frontier[1]>>) /\ (pc' = "trace" /\ UNCHANGED closed)) /\ ((UNCHANGED initialIndex /\ UNCHANGED predecessorEdges) /\ UNCHANGED levels)))) \/ (((((pc = "dequeue") /\ TRUE) /\ ((~(Len(frontier) = 0)) /\ TRUE)) /\ ((currentState' = frontier[1] /\ frontier' = (SubSeq(frontier, 1, (1 - 1)) \o SubSeq(frontier, (1 + 1), Len(frontier)))) /\ (successors' = (([_typedFunctionEntry \in {1, 2, 3, 4} |-> CASE (_typedFunctionEntry = 1) -> {2} [] (_typedFunctionEntry = 2) -> {1, 3} [] (_typedFunctionEntry = 3) -> {4} [] (_typedFunctionEntry = 4) -> {3}][frontier[1]] \ {frontier[1]}) \ closed) /\ (~(Cardinality(([_typedFunctionEntry \in {1, 2, 3, 4} |-> CASE (_typedFunctionEntry = 1) -> {2} [] (_typedFunctionEntry = 2) -> {1, 3} [] (_typedFunctionEntry = 3) -> {4} [] (_typedFunctionEntry = 4) -> {3}][frontier[1]] \ {frontier[1]})) = 0))))) /\ (((TRUE /\ pc' = "exploreSuccessors") /\ (UNCHANGED closed /\ UNCHANGED initialIndex)) /\ ((UNCHANGED counterexample /\ UNCHANGED predecessorEdges) /\ UNCHANGED levels))))
exploreSuccessors == (((((((pc = "exploreSuccessors") /\ TRUE) /\ ((Cardinality(successors) = 0) /\ TRUE)) /\ ((pc' = "dequeue" /\ UNCHANGED frontier) /\ (UNCHANGED closed /\ UNCHANGED currentState))) /\ (((UNCHANGED successors /\ UNCHANGED initialIndex) /\ (UNCHANGED counterexample /\ UNCHANGED predecessorEdges)) /\ UNCHANGED levels)) \/ ((((pc = "exploreSuccessors") /\ TRUE) /\ ((~(Cardinality(successors) = 0)) /\ TRUE)) /\ ((\E __binder_TLCMC_109_25 \in successors: ((((TRUE /\ successors' = (successors \ {__binder_TLCMC_109_25})) /\ (closed' = (closed \cup {__binder_TLCMC_109_25}) /\ frontier' = Append(frontier, __binder_TLCMC_109_25))) /\ ((predecessorEdges' = Append(predecessorEdges, <<currentState, __binder_TLCMC_109_25>>) /\ levels' = [__binder_StateExpr_354_22 \in (DOMAIN levels \cup {__binder_TLCMC_109_25}) |-> (IF (__binder_StateExpr_354_22 = __binder_TLCMC_109_25) THEN (levels[currentState] + 1) ELSE levels[__binder_StateExpr_354_22])]) /\ ((__binder_TLCMC_109_25 \in {4}) /\ TRUE))) /\ (counterexample' = <<currentState, __binder_TLCMC_109_25>> /\ pc' = "trace")) /\ UNCHANGED currentState) /\ UNCHANGED initialIndex))) \/ ((((pc = "exploreSuccessors") /\ TRUE) /\ ((~(Cardinality(successors) = 0)) /\ TRUE)) /\ ((\E __binder_TLCMC_109_25 \in successors: ((((TRUE /\ successors' = (successors \ {__binder_TLCMC_109_25})) /\ (closed' = (closed \cup {__binder_TLCMC_109_25}) /\ frontier' = Append(frontier, __binder_TLCMC_109_25))) /\ ((predecessorEdges' = Append(predecessorEdges, <<currentState, __binder_TLCMC_109_25>>) /\ levels' = [__binder_StateExpr_354_22 \in (DOMAIN levels \cup {__binder_TLCMC_109_25}) |-> (IF (__binder_StateExpr_354_22 = __binder_TLCMC_109_25) THEN (levels[currentState] + 1) ELSE levels[__binder_StateExpr_354_22])]) /\ ((~(__binder_TLCMC_109_25 \in {4})) /\ TRUE))) /\ pc' = "exploreSuccessors") /\ UNCHANGED currentState) /\ (UNCHANGED initialIndex /\ UNCHANGED counterexample))))
trace == (((((((pc = "trace") /\ TRUE) /\ (TRUE /\ (Head(counterexample) \in {1, 2}))) /\ ((TRUE /\ TRUE) /\ (pc' = "Done" /\ UNCHANGED frontier))) /\ (((UNCHANGED closed /\ UNCHANGED currentState) /\ (UNCHANGED successors /\ UNCHANGED initialIndex)) /\ ((UNCHANGED counterexample /\ UNCHANGED predecessorEdges) /\ UNCHANGED levels))) \/ (((((pc = "trace") /\ TRUE) /\ (TRUE /\ (~(Head(counterexample) \in {1, 2})))) /\ ((TRUE /\ counterexample' = (<<SelectSeq(predecessorEdges, LAMBDA __binder_TypedValues_1017_38: (__binder_TypedValues_1017_38[2] = counterexample[1]))[1][1]>> \o counterexample)) /\ (pc' = "trace" /\ UNCHANGED frontier))) /\ (((UNCHANGED closed /\ UNCHANGED currentState) /\ (UNCHANGED successors /\ UNCHANGED initialIndex)) /\ (UNCHANGED predecessorEdges /\ UNCHANGED levels)))) \/ (((((pc = "trace") /\ (~TRUE)) /\ (pc' = "Done" /\ UNCHANGED frontier)) /\ ((UNCHANGED closed /\ UNCHANGED currentState) /\ (UNCHANGED successors /\ UNCHANGED initialIndex))) /\ ((UNCHANGED counterexample /\ UNCHANGED predecessorEdges) /\ UNCHANGED levels)))
Terminating == (((((pc = "Done") /\ UNCHANGED pc) /\ (UNCHANGED frontier /\ UNCHANGED closed)) /\ ((UNCHANGED currentState /\ UNCHANGED successors) /\ (UNCHANGED initialIndex /\ UNCHANGED counterexample))) /\ ((UNCHANGED predecessorEdges /\ UNCHANGED levels) /\ UNCHANGED pc))

Next ==
  \/ scanInitialStates
  \/ checkInitialStates
  \/ dequeue
  \/ exploreSuccessors
  \/ trace
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, frontier, closed, currentState, successors, initialIndex, counterexample, predecessorEdges, levels>>
  /\ WF_<<pc, frontier, closed, currentState, successors, initialIndex, counterexample, predecessorEdges, levels>>(Next)

====
