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

SourceConditionalTrueBranchOutcome(conditionDefined, condition,
                                   conditionFailure, noDefined, noValue,
                                   noFailure) ==
    IF ~conditionDefined THEN [defined |-> FALSE, value |-> FALSE,
                               firstFailure |-> conditionFailure]
    ELSE IF condition THEN [defined |-> TRUE, value |-> TRUE,
                            firstFailure |-> "none"]
    ELSE IF ~noDefined THEN [defined |-> FALSE, value |-> FALSE,
                             firstFailure |-> noFailure]
    ELSE [defined |-> TRUE, value |-> noValue,
          firstFailure |-> "none"]

SourceConditionalChildOutcome(conditionDefined, condition,
                              conditionFailure, yesDefined, yesValue,
                              yesFailure, noDefined, noValue, noFailure) ==
    IF ~conditionDefined THEN [defined |-> FALSE, value |-> FALSE,
                               firstFailure |-> conditionFailure]
    ELSE IF condition THEN
        IF ~yesDefined THEN [defined |-> FALSE, value |-> FALSE,
                             firstFailure |-> yesFailure]
        ELSE [defined |-> TRUE, value |-> yesValue,
              firstFailure |-> "none"]
    ELSE IF ~noDefined THEN [defined |-> FALSE, value |-> FALSE,
                             firstFailure |-> noFailure]
    ELSE [defined |-> TRUE, value |-> noValue,
          firstFailure |-> "none"]

RenderedConditionalChildOutcome(conditionDefined, condition,
                                conditionFailure, yesDefined, yesValue,
                                yesFailure, noDefined, noValue, noFailure) ==
    LET defined == conditionDefined /\
                   (IF condition THEN yesDefined ELSE noDefined)
    IN [defined |-> defined,
        value |-> IF defined
                 THEN (IF condition THEN yesValue ELSE noValue)
                 ELSE FALSE,
        firstFailure |-> IF ~conditionDefined THEN conditionFailure
                        ELSE IF condition /\ ~yesDefined THEN yesFailure
                        ELSE IF ~condition /\ ~noDefined THEN noFailure
                        ELSE "none"]

THEOREM ConditionalPropagatesSelectedChildOutcome ==
    ASSUME NEW conditionDefined \in BOOLEAN, NEW condition \in BOOLEAN,
           NEW conditionFailure, NEW yesDefined \in BOOLEAN,
           NEW yesValue \in BOOLEAN, NEW yesFailure,
           NEW noDefined \in BOOLEAN, NEW noValue \in BOOLEAN,
           NEW noFailure
    PROVE SourceConditionalChildOutcome(conditionDefined, condition,
              conditionFailure, yesDefined, yesValue, yesFailure,
              noDefined, noValue, noFailure)
        = RenderedConditionalChildOutcome(conditionDefined, condition,
              conditionFailure, yesDefined, yesValue, yesFailure,
              noDefined, noValue, noFailure)
    BY SMT DEF SourceConditionalChildOutcome,
        RenderedConditionalChildOutcome

THEOREM ConditionalSkipsUnselectedChildFailure ==
    /\ SourceConditionalChildOutcome(TRUE, TRUE, "none", TRUE, TRUE,
         "none", FALSE, FALSE, "unselected-no").firstFailure = "none"
    /\ SourceConditionalChildOutcome(TRUE, FALSE, "none", FALSE, FALSE,
         "unselected-yes", TRUE, FALSE, "none").firstFailure = "none"
    BY SMT DEF SourceConditionalChildOutcome

THEOREM ConditionalTrueBranchIsShortCircuitOr ==
    ASSUME NEW conditionDefined \in BOOLEAN, NEW condition \in BOOLEAN,
           NEW conditionFailure, NEW noDefined \in BOOLEAN,
           NEW noValue \in BOOLEAN, NEW noFailure
    PROVE SourceConditionalTrueBranchOutcome(conditionDefined, condition,
              conditionFailure, noDefined, noValue, noFailure)
        = SourceOrChildOutcome(conditionDefined, condition,
              conditionFailure, noDefined, noValue, noFailure)
    BY SMT DEF SourceConditionalTrueBranchOutcome, SourceOrChildOutcome

WrongEagerConditionalElseFailure(noDefined) ==
    IF ~noDefined THEN "else" ELSE "none"

THEOREM EagerConditionalElseWouldInventFailure ==
    SourceConditionalTrueBranchOutcome(TRUE, TRUE, "none", FALSE,
        FALSE, "else").firstFailure
        # WrongEagerConditionalElseFailure(FALSE)
    BY SMT DEF SourceConditionalTrueBranchOutcome,
        WrongEagerConditionalElseFailure

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
