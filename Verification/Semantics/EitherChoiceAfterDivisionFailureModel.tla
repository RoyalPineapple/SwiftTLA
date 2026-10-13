---- MODULE EitherChoiceAfterDivisionFailureModel ----
EXTENDS Integers, FiniteSets, Sequences

VARIABLES divisor, result

vars == <<divisor, result>>

pick == ((IF (IF divisor # 0 THEN (IF (IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)) THEN TRUE ELSE FALSE) ELSE FALSE) THEN (LET __atomic_0 == (LET __EitherChoiceAfterDivisionFailureModel_dividend0 == 1 IN (LET __EitherChoiceAfterDivisionFailureModel_divisor1 == divisor IN (IF __EitherChoiceAfterDivisionFailureModel_divisor1 < 0 THEN (-__EitherChoiceAfterDivisionFailureModel_dividend0) \div (-__EitherChoiceAfterDivisionFailureModel_divisor1) ELSE __EitherChoiceAfterDivisionFailureModel_dividend0 \div __EitherChoiceAfterDivisionFailureModel_divisor1))) IN ((TRUE /\ result' = __atomic_0) /\ UNCHANGED divisor)) ELSE FALSE) \/ (IF (\E __binder_SpecParser_491_0 \in {1} : FALSE) THEN (LET __atomic_1 == (LET __EitherChoiceAfterDivisionFailureModel_choiceCandidates0 == {__binder_SpecParser_491_0 \in {1} : FALSE} IN (CHOOSE __binder_SpecParser_491_0 \in __EitherChoiceAfterDivisionFailureModel_choiceCandidates0 : (\A __EitherChoiceAfterDivisionFailureModel_choiceOther1 \in __EitherChoiceAfterDivisionFailureModel_choiceCandidates0 : __binder_SpecParser_491_0 <= __EitherChoiceAfterDivisionFailureModel_choiceOther1))) IN ((TRUE /\ result' = __atomic_1) /\ UNCHANGED divisor)) ELSE FALSE))
__SwiftTLAChoiceFailure0 == (IF (~(divisor # 0) \/ (IF divisor # 0 THEN ~((IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808))) ELSE FALSE)) THEN FALSE ELSE ~((\E __binder_SpecParser_491_0 \in {1} : FALSE)))
__SwiftTLADivisionByZeroFailure0 == ~(divisor # 0)
__SwiftTLADivisionByZeroDivisor0 == divisor
__SwiftTLAOverflowFailure0 == (IF divisor # 0 THEN ~((IF divisor # -1 THEN TRUE ELSE 1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808))) ELSE FALSE)
__SwiftTLAOverflowOperands0 == <<1, divisor>>
__SwiftTLAOverflowOperation0 == "division"
__SwiftTLAEvaluationOK == ~(__SwiftTLAChoiceFailure0) /\ ~(__SwiftTLADivisionByZeroFailure0) /\ ~(__SwiftTLAOverflowFailure0)

Init ==
  /\ divisor \in 0..1
  /\ result = 0

Next == pick

Spec ==
  /\ Init
  /\ [][Next]_<<divisor, result>>

====
