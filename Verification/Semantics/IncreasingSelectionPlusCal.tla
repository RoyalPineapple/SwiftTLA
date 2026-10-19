---- MODULE IncreasingSelectionPlusCal ----
EXTENDS Integers, Naturals, Sequences, FiniteSets

(*--algorithm increasingSelection {
variables
  position = 0;
{
  advance: while (TRUE) {
    when (\E __binder_SpecParser_383_0 \in {1, 2, 3} : (__binder_SpecParser_383_0 > position));
    with (__atomic_0 = (LET __IncreasingSelection_choiceCandidates0 == {__binder_SpecParser_383_0 \in {1, 2, 3} : (__binder_SpecParser_383_0 > position)} IN (CHOOSE __binder_SpecParser_383_0 \in __IncreasingSelection_choiceCandidates0 : (\A __IncreasingSelection_choiceOther1 \in __IncreasingSelection_choiceCandidates0 : __binder_SpecParser_383_0 <= __IncreasingSelection_choiceOther1)))) {
      position := __atomic_0;
    };
  };
}
} *)
__SwiftTLAChoiceFailure0 == ~((\E __binder_SpecParser_383_0 \in {1, 2, 3} : (__binder_SpecParser_383_0 > position)))
__SwiftTLAAnyEvaluationFailure0 == ~((\E __binder_SpecParser_383_0 \in {1, 2, 3} : (__binder_SpecParser_383_0 > position)))
__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)
====
