---- MODULE BranchwiseConjunctionFailureOrderModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES divisor, modulus, selected, result

vars == <<divisor, modulus, selected, result>>

pick == ((LET __atomic_0 == 0 IN (IF (IF divisor # 0 THEN (IF (IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)) THEN TRUE ELSE FALSE) ELSE FALSE) THEN (LET __atomic_1 == (LET __BranchwiseConjunctionFailureOrderModel_dividend0 == 1 IN (LET __BranchwiseConjunctionFailureOrderModel_divisor1 == divisor IN (IF __BranchwiseConjunctionFailureOrderModel_divisor1 < 0 THEN (-__BranchwiseConjunctionFailureOrderModel_dividend0) \div (-__BranchwiseConjunctionFailureOrderModel_divisor1) ELSE __BranchwiseConjunctionFailureOrderModel_dividend0 \div __BranchwiseConjunctionFailureOrderModel_divisor1))) IN (((TRUE /\ result' = __atomic_1) /\ (selected' = __atomic_0 /\ UNCHANGED divisor)) /\ UNCHANGED modulus)) ELSE FALSE)) \/ (IF (IF modulus # 0 THEN (IF modulus > 0 THEN TRUE ELSE FALSE) ELSE FALSE) THEN (LET __atomic_2 == (1 % modulus) IN (IF (IF divisor # 0 THEN (IF (IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)) THEN TRUE ELSE FALSE) ELSE FALSE) THEN (LET __atomic_3 == (LET __BranchwiseConjunctionFailureOrderModel_dividend0 == 1 IN (LET __BranchwiseConjunctionFailureOrderModel_divisor1 == divisor IN (IF __BranchwiseConjunctionFailureOrderModel_divisor1 < 0 THEN (-__BranchwiseConjunctionFailureOrderModel_dividend0) \div (-__BranchwiseConjunctionFailureOrderModel_divisor1) ELSE __BranchwiseConjunctionFailureOrderModel_dividend0 \div __BranchwiseConjunctionFailureOrderModel_divisor1))) IN (((TRUE /\ result' = __atomic_3) /\ (selected' = __atomic_2 /\ UNCHANGED divisor)) /\ UNCHANGED modulus)) ELSE FALSE)) ELSE FALSE))
__SwiftTLADivisionByZeroFailure0 == (LET __atomic_0 == 0 IN ~(divisor # 0))
__SwiftTLADivisionByZeroDivisor0 == (LET __atomic_0 == 0 IN divisor)
__SwiftTLAOverflowFailure0 == (LET __atomic_0 == 0 IN (IF divisor # 0 THEN ~((IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808))) ELSE FALSE))
__SwiftTLAOverflowOperands0 == (LET __atomic_0 == 0 IN <<1, divisor>>)
__SwiftTLAOverflowOperation0 == "division"
__SwiftTLADivisionByZeroFailure0_1 == (IF (LET __atomic_0 == 0 IN ~((IF divisor # 0 THEN (IF (IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)) THEN TRUE ELSE FALSE) ELSE FALSE))) THEN FALSE ELSE ~(modulus # 0))
__SwiftTLADivisionByZeroDivisor0_1 == modulus
__SwiftTLANegativeModuloDivisorFailure0 == (IF (LET __atomic_0 == 0 IN ~((IF divisor # 0 THEN (IF (IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)) THEN TRUE ELSE FALSE) ELSE FALSE))) THEN FALSE ELSE (IF modulus # 0 THEN ~(modulus > 0) ELSE FALSE))
__SwiftTLANegativeModuloDivisorValue0 == modulus
__SwiftTLADivisionByZeroFailure0_2 == (IF (LET __atomic_0 == 0 IN ~((IF divisor # 0 THEN (IF (IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)) THEN TRUE ELSE FALSE) ELSE FALSE))) THEN FALSE ELSE (IF (IF modulus # 0 THEN (IF modulus > 0 THEN TRUE ELSE FALSE) ELSE FALSE) THEN (LET __atomic_2 == (1 % modulus) IN ~(divisor # 0)) ELSE FALSE))
__SwiftTLADivisionByZeroDivisor0_2 == (LET __atomic_2 == (1 % modulus) IN divisor)
__SwiftTLAOverflowFailure0_1 == (IF (LET __atomic_0 == 0 IN ~((IF divisor # 0 THEN (IF (IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)) THEN TRUE ELSE FALSE) ELSE FALSE))) THEN FALSE ELSE (IF (IF modulus # 0 THEN (IF modulus > 0 THEN TRUE ELSE FALSE) ELSE FALSE) THEN (LET __atomic_2 == (1 % modulus) IN (IF divisor # 0 THEN ~((IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808))) ELSE FALSE)) ELSE FALSE))
__SwiftTLAOverflowOperands0_1 == (LET __atomic_2 == (1 % modulus) IN <<1, divisor>>)
__SwiftTLAOverflowOperation0_1 == "division"
__SwiftTLAAnyEvaluationFailure0 == (IF (LET __atomic_0 == 0 IN ~((IF divisor # 0 THEN (IF (IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)) THEN TRUE ELSE FALSE) ELSE FALSE))) THEN TRUE ELSE (~((IF modulus # 0 THEN (IF modulus > 0 THEN TRUE ELSE FALSE) ELSE FALSE)) \/ (IF (IF modulus # 0 THEN (IF modulus > 0 THEN TRUE ELSE FALSE) ELSE FALSE) THEN (LET __atomic_2 == (1 % modulus) IN ~((IF divisor # 0 THEN (IF (IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)) THEN TRUE ELSE FALSE) ELSE FALSE))) ELSE FALSE)))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)

Init ==
  /\ divisor \in 0..1
  /\ modulus \in {-1, 0, 1, 2}
  /\ selected = -1
  /\ result = 0

Next == pick

Spec ==
  /\ Init
  /\ [][Next]_<<divisor, modulus, selected, result>>

====
