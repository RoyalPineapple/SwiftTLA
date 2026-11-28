---- MODULE SelectedInitialInvariantFailureModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, divisor, quotient

vars == <<pc, divisor, quotient>>

stay == (((pc = "stay")) = TRUE /\ (LET __atomic_0 == quotient IN ((TRUE /\ quotient' = __atomic_0) /\ (pc' = "Done" /\ UNCHANGED divisor))))
Terminating == (((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED divisor /\ UNCHANGED quotient)) /\ UNCHANGED pc)

Allowed == (quotient = (LET __SelectedInitialInvariantFailureModel_dividend0 == 1 IN (LET __SelectedInitialInvariantFailureModel_divisor1 == divisor IN (IF __SelectedInitialInvariantFailureModel_divisor1 < 0 THEN (-__SelectedInitialInvariantFailureModel_dividend0) \div (-__SelectedInitialInvariantFailureModel_divisor1) ELSE __SelectedInitialInvariantFailureModel_dividend0 \div __SelectedInitialInvariantFailureModel_divisor1))))

Init ==
  /\ pc \in {"stay"}
  /\ divisor \in {0, 1}
  /\ quotient = 1
  /\ (IF (divisor >= (-2 * 1000000000 - 147483648) /\ divisor <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE divisor \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))
  /\ (IF (quotient >= (-2 * 1000000000 - 147483648) /\ quotient <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE quotient \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807))
  /\ (IF (IF divisor # 0 THEN (IF (IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)) THEN TRUE ELSE FALSE) ELSE FALSE) THEN Allowed ELSE FALSE)

__SwiftTLASelectedInitialDivisionByZeroFailure(__SwiftTLASelectedInitialFailedOperands) == (\E __SwiftTLAInitialValue0_ \in {"stay"}: (\E __SwiftTLAInitialValue1_ \in {0, 1}: (IF (IF (__SwiftTLAInitialValue1_ >= (-2 * 1000000000 - 147483648) /\ __SwiftTLAInitialValue1_ <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE __SwiftTLAInitialValue1_ \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807)) THEN (LET __SwiftTLAInitialValue2 == 1 IN (IF (IF (__SwiftTLAInitialValue2 >= (-2 * 1000000000 - 147483648) /\ __SwiftTLAInitialValue2 <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE __SwiftTLAInitialValue2 \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807)) THEN (IF ~(__SwiftTLAInitialValue1_ # 0) THEN __SwiftTLASelectedInitialFailedOperands = __SwiftTLAInitialValue1_ ELSE FALSE) ELSE FALSE)) ELSE FALSE)))
__SwiftTLASelectedInitialOverflowFailure(__SwiftTLASelectedInitialFailedOperands_) == (\E __SwiftTLAInitialValue0_ \in {"stay"}: (\E __SwiftTLAInitialValue1_ \in {0, 1}: (IF (IF (__SwiftTLAInitialValue1_ >= (-2 * 1000000000 - 147483648) /\ __SwiftTLAInitialValue1_ <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE __SwiftTLAInitialValue1_ \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807)) THEN (LET __SwiftTLAInitialValue2 == 1 IN (IF (IF (__SwiftTLAInitialValue2 >= (-2 * 1000000000 - 147483648) /\ __SwiftTLAInitialValue2 <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE __SwiftTLAInitialValue2 \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807)) THEN (IF (IF __SwiftTLAInitialValue1_ # 0 THEN ~((IF __SwiftTLAInitialValue1_ # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808))) ELSE FALSE) THEN __SwiftTLASelectedInitialFailedOperands_ = <<1, __SwiftTLAInitialValue1_>> ELSE FALSE) ELSE FALSE)) ELSE FALSE)))
__SwiftTLASelectedInitialOverflowOperation == "division"
__SwiftTLAAnyInitialEvaluationFailure == ((\E __SwiftTLAInitialValue0_ \in {"stay"}: (\E __SwiftTLAInitialValue1_ \in {0, 1}: (IF (IF (__SwiftTLAInitialValue1_ >= (-2 * 1000000000 - 147483648) /\ __SwiftTLAInitialValue1_ <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE __SwiftTLAInitialValue1_ \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807)) THEN (LET __SwiftTLAInitialValue2 == 1 IN (IF (IF (__SwiftTLAInitialValue2 >= (-2 * 1000000000 - 147483648) /\ __SwiftTLAInitialValue2 <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE __SwiftTLAInitialValue2 \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807)) THEN ~(__SwiftTLAInitialValue1_ # 0) ELSE FALSE)) ELSE FALSE)))) \/ ((\E __SwiftTLAInitialValue0_ \in {"stay"}: (\E __SwiftTLAInitialValue1_ \in {0, 1}: (IF (IF (__SwiftTLAInitialValue1_ >= (-2 * 1000000000 - 147483648) /\ __SwiftTLAInitialValue1_ <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE __SwiftTLAInitialValue1_ \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807)) THEN (LET __SwiftTLAInitialValue2 == 1 IN (IF (IF (__SwiftTLAInitialValue2 >= (-2 * 1000000000 - 147483648) /\ __SwiftTLAInitialValue2 <= (2 * 1000000000 + 147483647)) THEN TRUE ELSE __SwiftTLAInitialValue2 \in ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)..((9 * 1000000000 + 223372036) * 1000000000 + 854775807)) THEN (IF __SwiftTLAInitialValue1_ # 0 THEN ~((IF __SwiftTLAInitialValue1_ # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808))) ELSE FALSE) ELSE FALSE)) ELSE FALSE))))

Next ==
  \/ stay
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, divisor, quotient>>

====
