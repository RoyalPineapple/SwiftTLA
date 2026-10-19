-------------------- MODULE LazyExpressionFailureRule --------------------
EXTENDS TLAPS, ConditionalOutcomeRules

SelectedTrueGuard(condition, defined) ==
    IF condition THEN defined ELSE TRUE
SelectedFalseGuard(condition, defined) ==
    IF condition THEN TRUE ELSE defined

RenderedFirstSiteFailure(conditionDefined, condition, yesDefined, noDefined) ==
    IF ~conditionDefined THEN "condition"
    ELSE IF ~SelectedTrueGuard(condition, yesDefined) THEN "yes"
    ELSE IF ~SelectedFalseGuard(condition, noDefined) THEN "no"
    ELSE "none"

THEOREM LazyBranchFailureOrderPreserved ==
    ASSUME NEW conditionDefined \in BOOLEAN, NEW condition \in BOOLEAN,
           NEW yesDefined \in BOOLEAN, NEW noDefined \in BOOLEAN
    PROVE SourceFirstFailure(conditionDefined, condition,
              ~yesDefined, ~noDefined)
          = RenderedFirstSiteFailure(conditionDefined, condition,
              yesDefined, noDefined)
    BY SMT DEF SourceFirstFailure, RenderedFirstSiteFailure,
        SelectedTrueGuard, SelectedFalseGuard

THEOREM ShortCircuitAndPreservesRightFailure ==
    ASSUME NEW leftDefined \in BOOLEAN, NEW left \in BOOLEAN,
           NEW rightDefined \in BOOLEAN
    PROVE SourceFirstFailure(leftDefined, left, ~rightDefined, FALSE)
          = RenderedFirstSiteFailure(leftDefined, left, rightDefined, TRUE)
    BY LazyBranchFailureOrderPreserved, SMT

THEOREM ShortCircuitOrPreservesRightFailure ==
    ASSUME NEW leftDefined \in BOOLEAN, NEW left \in BOOLEAN,
           NEW rightDefined \in BOOLEAN
    PROVE SourceFirstFailure(leftDefined, left, FALSE, ~rightDefined)
          = RenderedFirstSiteFailure(leftDefined, left, TRUE, rightDefined)
    BY LazyBranchFailureOrderPreserved, SMT

SourceAndOutcome(leftDefined, left, rightDefined, right) ==
    IF ~leftDefined THEN [defined |-> FALSE, value |-> FALSE,
                          firstFailure |-> "condition"]
    ELSE IF ~left THEN [defined |-> TRUE, value |-> FALSE,
                        firstFailure |-> "none"]
    ELSE IF ~rightDefined THEN [defined |-> FALSE, value |-> FALSE,
                                firstFailure |-> "yes"]
    ELSE [defined |-> TRUE, value |-> right,
          firstFailure |-> "none"]
RenderedAndOutcome(leftDefined, left, rightDefined, right) ==
    LET defined == leftDefined /\ (IF left THEN rightDefined ELSE TRUE)
    IN [defined |-> defined,
        value |-> IF defined THEN (IF left THEN right ELSE FALSE) ELSE FALSE,
        firstFailure |-> RenderedFirstSiteFailure(
            leftDefined, left, rightDefined, TRUE)]

SourceOrOutcome(leftDefined, left, rightDefined, right) ==
    IF ~leftDefined THEN [defined |-> FALSE, value |-> FALSE,
                          firstFailure |-> "condition"]
    ELSE IF left THEN [defined |-> TRUE, value |-> TRUE,
                       firstFailure |-> "none"]
    ELSE IF ~rightDefined THEN [defined |-> FALSE, value |-> FALSE,
                                firstFailure |-> "no"]
    ELSE [defined |-> TRUE, value |-> right,
          firstFailure |-> "none"]
RenderedOrOutcome(leftDefined, left, rightDefined, right) ==
    LET defined == leftDefined /\ (IF left THEN TRUE ELSE rightDefined)
    IN [defined |-> defined,
        value |-> IF defined THEN (IF left THEN TRUE ELSE right) ELSE FALSE,
        firstFailure |-> RenderedFirstSiteFailure(
            leftDefined, left, TRUE, rightDefined)]

THEOREM ShortCircuitAndPreservesCompleteOutcome ==
    ASSUME NEW leftDefined \in BOOLEAN, NEW left \in BOOLEAN,
           NEW rightDefined \in BOOLEAN, NEW right \in BOOLEAN
    PROVE SourceAndOutcome(leftDefined, left, rightDefined, right)
        = RenderedAndOutcome(leftDefined, left, rightDefined, right)
    BY SMT DEF SourceAndOutcome, RenderedAndOutcome,
        RenderedFirstSiteFailure, SelectedTrueGuard, SelectedFalseGuard

THEOREM ShortCircuitOrPreservesCompleteOutcome ==
    ASSUME NEW leftDefined \in BOOLEAN, NEW left \in BOOLEAN,
           NEW rightDefined \in BOOLEAN, NEW right \in BOOLEAN
    PROVE SourceOrOutcome(leftDefined, left, rightDefined, right)
        = RenderedOrOutcome(leftDefined, left, rightDefined, right)
    BY SMT DEF SourceOrOutcome, RenderedOrOutcome,
        RenderedFirstSiteFailure, SelectedTrueGuard, SelectedFalseGuard

SourceAndChildOutcome(leftDefined, left, leftFailure,
                      rightDefined, right, rightFailure) ==
    IF ~leftDefined THEN [defined |-> FALSE, value |-> FALSE,
                          firstFailure |-> leftFailure]
    ELSE IF ~left THEN [defined |-> TRUE, value |-> FALSE,
                        firstFailure |-> "none"]
    ELSE IF ~rightDefined THEN [defined |-> FALSE, value |-> FALSE,
                                firstFailure |-> rightFailure]
    ELSE [defined |-> TRUE, value |-> right,
          firstFailure |-> "none"]
RenderedAndChildOutcome(leftDefined, left, leftFailure,
                        rightDefined, right, rightFailure) ==
    LET defined == leftDefined /\ (IF left THEN rightDefined ELSE TRUE)
    IN [defined |-> defined,
        value |-> IF defined THEN (IF left THEN right ELSE FALSE) ELSE FALSE,
        firstFailure |-> IF ~leftDefined THEN leftFailure
                        ELSE IF left /\ ~rightDefined THEN rightFailure
                        ELSE "none"]

SourceOrChildOutcome(leftDefined, left, leftFailure,
                     rightDefined, right, rightFailure) ==
    IF ~leftDefined THEN [defined |-> FALSE, value |-> FALSE,
                          firstFailure |-> leftFailure]
    ELSE IF left THEN [defined |-> TRUE, value |-> TRUE,
                       firstFailure |-> "none"]
    ELSE IF ~rightDefined THEN [defined |-> FALSE, value |-> FALSE,
                                firstFailure |-> rightFailure]
    ELSE [defined |-> TRUE, value |-> right,
          firstFailure |-> "none"]
RenderedOrChildOutcome(leftDefined, left, leftFailure,
                       rightDefined, right, rightFailure) ==
    LET defined == leftDefined /\ (IF left THEN TRUE ELSE rightDefined)
    IN [defined |-> defined,
        value |-> IF defined THEN (IF left THEN TRUE ELSE right) ELSE FALSE,
        firstFailure |-> IF ~leftDefined THEN leftFailure
                        ELSE IF ~left /\ ~rightDefined THEN rightFailure
                        ELSE "none"]

THEOREM ShortCircuitAndPropagatesChildOutcome ==
    ASSUME NEW leftDefined \in BOOLEAN, NEW left \in BOOLEAN,
           NEW leftFailure, NEW rightDefined \in BOOLEAN,
           NEW right \in BOOLEAN, NEW rightFailure
    PROVE SourceAndChildOutcome(leftDefined, left, leftFailure,
              rightDefined, right, rightFailure)
        = RenderedAndChildOutcome(leftDefined, left, leftFailure,
              rightDefined, right, rightFailure)
    BY SMT DEF SourceAndChildOutcome, RenderedAndChildOutcome

THEOREM ShortCircuitOrPropagatesChildOutcome ==
    ASSUME NEW leftDefined \in BOOLEAN, NEW left \in BOOLEAN,
           NEW leftFailure, NEW rightDefined \in BOOLEAN,
           NEW right \in BOOLEAN, NEW rightFailure
    PROVE SourceOrChildOutcome(leftDefined, left, leftFailure,
              rightDefined, right, rightFailure)
        = RenderedOrChildOutcome(leftDefined, left, leftFailure,
              rightDefined, right, rightFailure)
    BY SMT DEF SourceOrChildOutcome, RenderedOrChildOutcome

THEOREM NestedFailureIsRetainedButSkippedFailureIsNot ==
    /\ SourceAndChildOutcome(FALSE, TRUE, "inner", FALSE, TRUE, "right").firstFailure
           = "inner"
    /\ SourceAndChildOutcome(TRUE, FALSE, "left", FALSE, TRUE, "right").firstFailure
           = "none"
    /\ SourceOrChildOutcome(TRUE, TRUE, "left", FALSE, FALSE, "right").firstFailure
           = "none"
    BY SMT DEF SourceAndChildOutcome, SourceOrChildOutcome

WrongEagerTrueFailure(conditionDefined, yesDefined) ==
    IF ~conditionDefined THEN "condition"
    ELSE IF ~yesDefined THEN "yes" ELSE "none"

THEOREM EagerUnselectedBranchIsRejected ==
    /\ RenderedFirstSiteFailure(TRUE, FALSE, FALSE, TRUE) = "none"
    /\ WrongEagerTrueFailure(TRUE, FALSE) = "yes"
    BY SMT DEF RenderedFirstSiteFailure,
        SelectedTrueGuard, SelectedFalseGuard, WrongEagerTrueFailure

======================================================================
