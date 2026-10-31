-------------------- MODULE ConditionalActionRule --------------------
EXTENDS ActionOutcomeInterface

SourceIfElse(condition, yes, no) ==
    IF condition.failure # NoFailure
    THEN [updates |-> <<>>, failure |-> condition.failure]
    ELSE IF condition.enabled THEN yes ELSE no

GeneratedIfElse(condition, yes, no) ==
    [updates |-> IF condition.failure # NoFailure THEN <<>>
                 ELSE IF condition.enabled THEN yes.updates ELSE no.updates,
     failure |-> IF condition.failure # NoFailure THEN condition.failure
                 ELSE IF condition.enabled THEN yes.failure ELSE no.failure]

THEOREM ConditionalRuleComposes ==
    ASSUME NEW sourceCondition \in ConditionOutcome,
           NEW generatedCondition \in ConditionOutcome,
           NEW sourceYes \in OrderedOutcome, NEW sourceNo \in OrderedOutcome,
           NEW generatedYes \in OrderedOutcome, NEW generatedNo \in OrderedOutcome,
           sourceCondition = generatedCondition,
           sourceYes = generatedYes, sourceNo = generatedNo
    PROVE SourceIfElse(sourceCondition, sourceYes, sourceNo) =
              GeneratedIfElse(generatedCondition, generatedYes, generatedNo)
    BY SMT DEF SourceIfElse, GeneratedIfElse, OrderedOutcome

THEOREM ConditionalOutcomeIsClosed ==
    ASSUME NEW condition \in ConditionOutcome,
           NEW yes \in OrderedOutcome, NEW no \in OrderedOutcome
    PROVE SourceIfElse(condition, yes, no) \in OrderedOutcome
    BY SMT DEF SourceIfElse, ConditionOutcome, OrderedOutcome

THEOREM GeneratedConditionalOutcomeIsClosed ==
    ASSUME NEW condition \in ConditionOutcome,
           NEW yes \in OrderedOutcome, NEW no \in OrderedOutcome
    PROVE GeneratedIfElse(condition, yes, no) \in OrderedOutcome
    BY ConditionalOutcomeIsClosed, ConditionalRuleComposes, SMT

THEOREM SelectingTheWrongBranchChangesTheOutcome ==
    ASSUME NEW condition \in ConditionOutcome,
           condition.failure = NoFailure,
           NEW yes \in OrderedOutcome, NEW no \in OrderedOutcome,
           yes # no
    PROVE SourceIfElse(condition, yes, no) # GeneratedIfElse(condition, no, yes)
    BY SMT DEF SourceIfElse, GeneratedIfElse, OrderedOutcome

=============================================================================
