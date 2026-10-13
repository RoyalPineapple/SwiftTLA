---- MODULE MixedCandidateDivisionFailureModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES result

pick == (\E __atomic_0 \in 0..1: (IF (IF __atomic_0 # 0 THEN (IF (IF __atomic_0 # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)) THEN TRUE ELSE FALSE) ELSE FALSE) THEN (LET __atomic_1 == (LET __MixedCandidateDivisionFailureModel_dividend0 == 1 IN (LET __MixedCandidateDivisionFailureModel_divisor1 == __atomic_0 IN (IF __MixedCandidateDivisionFailureModel_divisor1 < 0 THEN (-__MixedCandidateDivisionFailureModel_dividend0) \div (-__MixedCandidateDivisionFailureModel_divisor1) ELSE __MixedCandidateDivisionFailureModel_dividend0 \div __MixedCandidateDivisionFailureModel_divisor1))) IN (TRUE /\ result' = __atomic_1)) ELSE FALSE))
__SwiftTLADivisionByZeroFailure0 == ~({__atomic_0 \in 0..1: ~(__atomic_0 # 0)} = {})
__SwiftTLADivisionByZeroDivisor0 == {__atomic_0: __atomic_0 \in {__atomic_0 \in 0..1: ~(__atomic_0 # 0)}}
__SwiftTLAOverflowFailure0 == ~({__atomic_0 \in 0..1: (IF __atomic_0 # 0 THEN ~((IF __atomic_0 # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808))) ELSE FALSE)} = {})
__SwiftTLAOverflowOperands0 == {<<1, __atomic_0>>: __atomic_0 \in {__atomic_0 \in 0..1: (IF __atomic_0 # 0 THEN ~((IF __atomic_0 # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808))) ELSE FALSE)}}
__SwiftTLAOverflowOperation0 == "division"
__SwiftTLAEvaluationOK == ~(__SwiftTLADivisionByZeroFailure0) /\ ~(__SwiftTLAOverflowFailure0)

Init == result = 0

Next == pick

Spec ==
  /\ Init
  /\ [][Next]_result

====
