---- MODULE EitherDistinctFailuresModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES divisor, modulus, result

vars == <<divisor, modulus, result>>

pick == ((IF (IF divisor # 0 THEN (IF (IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)) THEN TRUE ELSE FALSE) ELSE FALSE) THEN (LET __atomic_0 == (LET __EitherDistinctFailuresModel_dividend0 == 1 IN (LET __EitherDistinctFailuresModel_divisor1 == divisor IN (IF __EitherDistinctFailuresModel_divisor1 < 0 THEN (-__EitherDistinctFailuresModel_dividend0) \div (-__EitherDistinctFailuresModel_divisor1) ELSE __EitherDistinctFailuresModel_dividend0 \div __EitherDistinctFailuresModel_divisor1))) IN ((TRUE /\ result' = __atomic_0) /\ (UNCHANGED divisor /\ UNCHANGED modulus))) ELSE FALSE) \/ (IF (IF modulus # 0 THEN (IF modulus > 0 THEN TRUE ELSE FALSE) ELSE FALSE) THEN (LET __atomic_1 == (1 % modulus) IN ((TRUE /\ result' = __atomic_1) /\ (UNCHANGED divisor /\ UNCHANGED modulus))) ELSE FALSE))
__SwiftTLADivisionByZeroFailure0 == ~(divisor # 0)
__SwiftTLADivisionByZeroDivisor0 == divisor
__SwiftTLAOverflowFailure0 == (IF divisor # 0 THEN ~((IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808))) ELSE FALSE)
__SwiftTLAOverflowOperands0 == <<1, divisor>>
__SwiftTLAOverflowOperation0 == "division"
__SwiftTLADivisionByZeroFailure0_1 == (IF (~(divisor # 0) \/ (IF divisor # 0 THEN ~((IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808))) ELSE FALSE)) THEN FALSE ELSE ~(modulus # 0))
__SwiftTLADivisionByZeroDivisor0_1 == modulus
__SwiftTLANegativeModuloDivisorFailure0 == (IF (~(divisor # 0) \/ (IF divisor # 0 THEN ~((IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808))) ELSE FALSE)) THEN FALSE ELSE (IF modulus # 0 THEN ~(modulus > 0) ELSE FALSE))
__SwiftTLANegativeModuloDivisorValue0 == modulus
__SwiftTLAEvaluationOK == ~(__SwiftTLADivisionByZeroFailure0) /\ ~(__SwiftTLAOverflowFailure0) /\ ~(__SwiftTLADivisionByZeroFailure0_1) /\ ~(__SwiftTLANegativeModuloDivisorFailure0)

Init ==
  /\ divisor = 0
  /\ modulus = -1
  /\ result = 0

Next == pick

Spec ==
  /\ Init
  /\ [][Next]_<<divisor, modulus, result>>

====
