---- MODULE CheckedViewInvariantMachine ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES slot

replace == (LET __atomic_0 == 0 IN (TRUE /\ slot' = __atomic_0))
zero == (LET __atomic_0 == [id |-> 0, limit |-> 2] IN (TRUE /\ slot' = __atomic_0))

WithinLimit == (IF (((LET _checkedValue == slot IN CASE (DOMAIN _checkedValue = {"id", "limit"} /\ _checkedValue \in [id: Int, limit: Int]) -> _checkedValue)).id = 1) THEN ((slot).limit = 2) ELSE FALSE)
ShortCircuit == (IF (slot = 0) THEN TRUE ELSE (((LET _checkedValue == slot IN CASE (DOMAIN _checkedValue = {"id", "limit"} /\ _checkedValue \in [id: Int, limit: Int]) -> _checkedValue)).limit = 2))
EarlierFailure == (IF ((LET __CheckedViewInvariantMachine_dividend0 == 5 IN (LET __CheckedViewInvariantMachine_divisor1 == ((LET _checkedValue == slot IN CASE (DOMAIN _checkedValue = {"id", "limit"} /\ _checkedValue \in [id: Int, limit: Int]) -> _checkedValue)).id IN (IF __CheckedViewInvariantMachine_divisor1 < 0 THEN (-__CheckedViewInvariantMachine_dividend0) \div (-__CheckedViewInvariantMachine_divisor1) ELSE __CheckedViewInvariantMachine_dividend0 \div __CheckedViewInvariantMachine_divisor1))) = 5) THEN (((LET _checkedValue == slot IN CASE (DOMAIN _checkedValue = {"id", "limit"} /\ _checkedValue \in [id: Int, limit: Int]) -> _checkedValue)).limit = 2) ELSE FALSE)

Init == slot = [id |-> 1, limit |-> 2]

Next ==
  \/ replace
  \/ zero

Spec ==
  /\ Init
  /\ [][Next]_slot

====
