---- MODULE DependentDivisionInitialModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES pc, divisor, quotient

vars == <<pc, divisor, quotient>>

stay == (((pc = "stay")) = TRUE /\ (LET __atomic_0 == quotient IN ((TRUE /\ quotient' = __atomic_0) /\ (pc' = "Done" /\ UNCHANGED divisor))))
Terminating == (((((pc = "Done")) = TRUE /\ UNCHANGED pc) /\ (UNCHANGED divisor /\ UNCHANGED quotient)) /\ UNCHANGED pc)

Init ==
  /\ pc = "stay"
  /\ divisor \in {0, 1}
  /\ (IF (IF divisor # 0 THEN (IF (IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)) THEN TRUE ELSE FALSE) ELSE FALSE) THEN quotient = (LET __DependentDivisionInitialModel_dividend0 == 1 IN (LET __DependentDivisionInitialModel_divisor1 == divisor IN (IF __DependentDivisionInitialModel_divisor1 < 0 THEN (-__DependentDivisionInitialModel_dividend0) \div (-__DependentDivisionInitialModel_divisor1) ELSE __DependentDivisionInitialModel_dividend0 \div __DependentDivisionInitialModel_divisor1))) ELSE FALSE)

__SwiftTLAInitialDivisionByZeroFailure2(__SwiftTLAInitialFailedOperands2) == (LET __SwiftTLAInitialValue0 == "stay" IN (\E __SwiftTLAInitialValue1 \in {0, 1}: (IF ~(__SwiftTLAInitialValue1 # 0) THEN __SwiftTLAInitialFailedOperands2 = __SwiftTLAInitialValue1 ELSE FALSE)))
__SwiftTLAInitialOverflowFailure2(__SwiftTLAInitialFailedOperands2_) == (LET __SwiftTLAInitialValue0 == "stay" IN (\E __SwiftTLAInitialValue1 \in {0, 1}: (IF (IF __SwiftTLAInitialValue1 # 0 THEN ~((IF __SwiftTLAInitialValue1 # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808))) ELSE FALSE) THEN __SwiftTLAInitialFailedOperands2_ = <<1, __SwiftTLAInitialValue1>> ELSE FALSE)))
__SwiftTLAInitialOverflowOperation2 == "division"
__SwiftTLAAnyInitialEvaluationFailure == ((LET __SwiftTLAInitialValue0 == "stay" IN (\E __SwiftTLAInitialValue1 \in {0, 1}: ~(__SwiftTLAInitialValue1 # 0)))) \/ ((LET __SwiftTLAInitialValue0 == "stay" IN (\E __SwiftTLAInitialValue1 \in {0, 1}: (IF __SwiftTLAInitialValue1 # 0 THEN ~((IF __SwiftTLAInitialValue1 # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808))) ELSE FALSE))))

Next ==
  \/ stay
  \/ Terminating

Spec ==
  /\ Init
  /\ [][Next]_<<pc, divisor, quotient>>

====
