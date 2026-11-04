---- MODULE MissingFunctionKey ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES table, key, result

vars == <<table, key, result>>

read == (IF (IF (key \in DOMAIN (table)) THEN TRUE ELSE FALSE) THEN (LET __atomic_0 == table[key] IN ((TRUE /\ result' = __atomic_0) /\ (UNCHANGED table /\ UNCHANGED key))) ELSE FALSE)
__SwiftTLAFunctionArgumentOutsideDomainFailure0 == ~((key \in DOMAIN (table)))
__SwiftTLAAnyEvaluationFailure0 == ~((IF (key \in DOMAIN (table)) THEN TRUE ELSE FALSE))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ table = (LET __binder_key0 == 0 IN (LET __binder_value0 == 42 IN CASE (Cardinality({__binder_key0}) = 1) -> [__binder_selected \in {__binder_key0} |-> CASE (__binder_selected = __binder_key0) -> __binder_value0]))
  /\ key = 1
  /\ result = 0
  /\ (IF (key >= (-2 * 1000000000 - 147483648) /\ key <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE key \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))
  /\ (IF (result >= (-2 * 1000000000 - 147483648) /\ result <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE result \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))

Next == read

Spec ==
  /\ Init
  /\ [][Next]_<<table, key, result>>

====
