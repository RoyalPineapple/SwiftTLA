-------------------- MODULE GuardActionRule --------------------
EXTENDS ActionOutcomeInterface

SourceGuard(condition, pending) ==
    IF condition.failure # NoFailure
    THEN [updates |-> <<>>, failure |-> condition.failure]
    ELSE IF condition.enabled
         THEN [updates |-> <<pending>>, failure |-> NoFailure]
         ELSE EmptyOrdered

GeneratedGuard(condition, pending) ==
    [updates |-> IF condition.failure = NoFailure /\ condition.enabled
                 THEN <<pending>> ELSE <<>>,
     failure |-> condition.failure]

THEOREM GuardRuleComposes ==
    ASSUME NEW sourceCondition \in ConditionOutcome,
           NEW generatedCondition \in ConditionOutcome,
           NEW pending \in UpdateValues,
           sourceCondition = generatedCondition
    PROVE SourceGuard(sourceCondition, pending) =
              GeneratedGuard(generatedCondition, pending)
    BY SMT DEF SourceGuard, GeneratedGuard, EmptyOrdered, ConditionOutcome

THEOREM GuardOutcomeIsASingleCandidate ==
    ASSUME NEW condition \in ConditionOutcome, NEW pending \in UpdateValues
    PROVE /\ SourceGuard(condition, pending) \in SingleCandidateLeft
          /\ GeneratedGuard(condition, pending) \in SingleCandidateLeft
    BY GuardRuleComposes, SMT DEF SourceGuard, EmptyOrdered,
        SingleCandidateLeft, OrderedOutcome, ConditionOutcome

THEOREM AFailingGuardIsNotDisabled ==
    ASSUME NEW condition \in ConditionOutcome, condition.failure # NoFailure,
           NEW pending \in UpdateValues, NEW fields, NEW values,
           NEW prior \in [fields -> values], NEW label,
           NEW finish \in [UpdateValues -> [fields -> values]]
    PROVE LET observed == CompleteLabeledOutcome(prior, label, finish, NoFailure,
                  SourceGuard(condition, pending))
          IN /\ observed.successors = {}
             /\ observed.selectedFailure = condition.failure
             /\ ~observed.disabled
    BY SMT DEF SourceGuard, CompleteLabeledOutcome

THEOREM ChangingGuardFailurePayloadChangesTheOutcome ==
    ASSUME NEW sourceCondition \in ConditionOutcome,
           NEW wrongCondition \in ConditionOutcome,
           sourceCondition.failure # NoFailure,
           sourceCondition.failure # wrongCondition.failure,
           NEW pending \in UpdateValues
    PROVE SourceGuard(sourceCondition, pending) # GeneratedGuard(wrongCondition, pending)
    BY SMT DEF SourceGuard, GeneratedGuard

=============================================================================
