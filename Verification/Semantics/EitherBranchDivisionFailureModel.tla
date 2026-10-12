---- MODULE EitherBranchDivisionFailureModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES divisor, result

vars == <<divisor, result>>

pick == ((IF (IF divisor # 0 THEN (IF (IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)) THEN TRUE ELSE FALSE) ELSE FALSE) THEN (LET __atomic_0 == (LET __EitherBranchDivisionFailureModel_dividend0 == 1 IN (LET __EitherBranchDivisionFailureModel_divisor1 == divisor IN (IF __EitherBranchDivisionFailureModel_divisor1 < 0 THEN (-__EitherBranchDivisionFailureModel_dividend0) \div (-__EitherBranchDivisionFailureModel_divisor1) ELSE __EitherBranchDivisionFailureModel_dividend0 \div __EitherBranchDivisionFailureModel_divisor1))) IN ((TRUE /\ result' = __atomic_0) /\ UNCHANGED divisor)) ELSE FALSE) \/ (LET __atomic_1 == 1 IN ((TRUE /\ result' = __atomic_1) /\ UNCHANGED divisor)))
__SwiftTLADivisionByZeroFailure0 == ~(divisor # 0)
__SwiftTLADivisionByZeroDivisor0 == divisor
__SwiftTLAOverflowFailure0 == (IF divisor # 0 THEN ~((IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808))) ELSE FALSE)
__SwiftTLAOverflowOperands0 == <<1, divisor>>
__SwiftTLAOverflowOperation0 == "division"
__SwiftTLAEvaluationOK == ~(__SwiftTLADivisionByZeroFailure0) /\ ~(__SwiftTLAOverflowFailure0)

Init ==
  /\ divisor = 0
  /\ result = 0

Next == pick

Spec ==
  /\ Init
  /\ [][Next]_<<divisor, result>>

====
