---------------- MODULE BooleanExpressionConstructorRules ----------------
EXTENDS TLAPS

CONSTANTS FailureValues, NoFailure
ASSUME NoFailure \notin FailureValues

ActionOutcomes == INSTANCE ActionOutcomeInterface WITH UpdateValues <- BOOLEAN

\* FailureValues can contain complete site/kind/operand records, not just names.
ExpressionOutcomes ==
    {outcome \in [defined: BOOLEAN, value: BOOLEAN,
                  firstFailure: FailureValues \cup {NoFailure}] :
        /\ (outcome.defined <=> outcome.firstFailure = NoFailure)
        /\ (~outcome.defined => ~outcome.value)}
Success(value) == [defined |-> TRUE, value |-> value, firstFailure |-> NoFailure]

SourceNot(child) ==
    IF ~child.defined THEN child ELSE Success(~child.value)
NativeNot(child) ==
    IF child.firstFailure = NoFailure THEN Success(~child.value) ELSE child
TLANot(child) ==
    [defined |-> child.defined,
     value |-> IF child.defined THEN ~child.value ELSE FALSE,
     firstFailure |-> child.firstFailure]

SourceAnd(left, right) ==
    IF ~left.defined THEN left
    ELSE IF ~left.value THEN Success(FALSE) ELSE right
NativeAnd(left, right) ==
    IF left.firstFailure # NoFailure THEN left
    ELSE IF left.value THEN right ELSE Success(FALSE)
TLAAnd(left, right) ==
    LET defined == left.defined /\ (IF left.value THEN right.defined ELSE TRUE)
    IN [defined |-> defined,
        value |-> IF defined THEN (IF left.value THEN right.value ELSE FALSE) ELSE FALSE,
        firstFailure |-> IF ~left.defined THEN left.firstFailure
                         ELSE IF left.value THEN right.firstFailure ELSE NoFailure]

SourceOr(left, right) ==
    IF ~left.defined THEN left
    ELSE IF left.value THEN Success(TRUE) ELSE right
NativeOr(left, right) ==
    IF left.firstFailure # NoFailure THEN left
    ELSE IF left.value THEN Success(TRUE) ELSE right
TLAOr(left, right) ==
    LET defined == left.defined /\ (IF left.value THEN TRUE ELSE right.defined)
    IN [defined |-> defined,
        value |-> IF defined THEN (IF left.value THEN TRUE ELSE right.value) ELSE FALSE,
        firstFailure |-> IF ~left.defined THEN left.firstFailure
                         ELSE IF left.value THEN NoFailure ELSE right.firstFailure]

SourceIf(condition, yes, no) ==
    IF ~condition.defined THEN condition
    ELSE IF condition.value THEN yes ELSE no
NativeIf(condition, yes, no) ==
    IF condition.firstFailure # NoFailure THEN condition
    ELSE IF condition.value THEN yes ELSE no
TLAIf(condition, yes, no) ==
    LET defined == condition.defined /\
                   (IF condition.value THEN yes.defined ELSE no.defined)
    IN [defined |-> defined,
        value |-> IF defined THEN (IF condition.value THEN yes.value ELSE no.value) ELSE FALSE,
        firstFailure |-> IF ~condition.defined THEN condition.firstFailure
                         ELSE IF condition.value THEN yes.firstFailure ELSE no.firstFailure]

THEOREM NegationRetainsTheSelectedPayload ==
    ASSUME NEW child \in ExpressionOutcomes
    PROVE /\ SourceNot(child) = NativeNot(child)
          /\ NativeNot(child) = TLANot(child)
          /\ SourceNot(child) \in ExpressionOutcomes
    BY SMT DEF SourceNot, NativeNot, TLANot, Success, ExpressionOutcomes

THEOREM ConjunctionRetainsTheSelectedPayload ==
    ASSUME NEW left \in ExpressionOutcomes, NEW right \in ExpressionOutcomes
    PROVE /\ SourceAnd(left, right) = NativeAnd(left, right)
          /\ NativeAnd(left, right) = TLAAnd(left, right)
          /\ SourceAnd(left, right) \in ExpressionOutcomes
    BY SMT DEF SourceAnd, NativeAnd, TLAAnd, Success, ExpressionOutcomes

THEOREM DisjunctionRetainsTheSelectedPayload ==
    ASSUME NEW left \in ExpressionOutcomes, NEW right \in ExpressionOutcomes
    PROVE /\ SourceOr(left, right) = NativeOr(left, right)
          /\ NativeOr(left, right) = TLAOr(left, right)
          /\ SourceOr(left, right) \in ExpressionOutcomes
    BY SMT DEF SourceOr, NativeOr, TLAOr, Success, ExpressionOutcomes

THEOREM ConditionalRetainsTheSelectedPayload ==
    ASSUME NEW condition \in ExpressionOutcomes,
           NEW yes \in ExpressionOutcomes, NEW no \in ExpressionOutcomes
    PROVE /\ SourceIf(condition, yes, no) = NativeIf(condition, yes, no)
          /\ NativeIf(condition, yes, no) = TLAIf(condition, yes, no)
          /\ SourceIf(condition, yes, no) \in ExpressionOutcomes
    BY SMT DEF SourceIf, NativeIf, TLAIf, ExpressionOutcomes

ConditionProjection(outcome) ==
    [enabled |-> outcome.value, failure |-> outcome.firstFailure]

THEOREM ProjectionRetainsTheEntireFailure ==
    ASSUME NEW outcome \in ExpressionOutcomes
    PROVE /\ ConditionProjection(outcome) \in ActionOutcomes!ConditionOutcome
          /\ ConditionProjection(outcome).failure = outcome.firstFailure
          /\ (~outcome.defined => ~ConditionProjection(outcome).enabled)
    BY SMT DEF ConditionProjection, ExpressionOutcomes, ActionOutcomes!ConditionOutcome

THEOREM UnselectedFailureDoesNotEscape ==
    ASSUME NEW failure \in FailureValues
    PROVE LET failed == [defined |-> FALSE, value |-> FALSE, firstFailure |-> failure]
          IN /\ TLAAnd(Success(FALSE), failed) = Success(FALSE)
             /\ TLAOr(Success(TRUE), failed) = Success(TRUE)
             /\ TLAIf(Success(TRUE), Success(FALSE), failed) = Success(FALSE)
             /\ TLAIf(Success(FALSE), failed, Success(TRUE)) = Success(TRUE)
    BY SMT DEF TLAAnd, TLAOr, TLAIf, Success

THEOREM ChangingTheSelectedFailureChangesTheOutcome ==
    ASSUME NEW first \in FailureValues, NEW second \in FailureValues, first # second
    PROVE LET left == [defined |-> FALSE, value |-> FALSE, firstFailure |-> first]
              right == [defined |-> FALSE, value |-> FALSE, firstFailure |-> second]
          IN /\ TLAAnd(left, right) = left
             /\ TLAAnd(left, right) # right
             /\ ConditionProjection(left) # ConditionProjection(right)
    BY SMT DEF TLAAnd, ConditionProjection

=============================================================================
