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

WrongEagerTrueFailure(conditionDefined, yesDefined) ==
    IF ~conditionDefined THEN "condition"
    ELSE IF ~yesDefined THEN "yes" ELSE "none"

THEOREM EagerUnselectedBranchIsRejected ==
    /\ RenderedFirstSiteFailure(TRUE, FALSE, FALSE, TRUE) = "none"
    /\ WrongEagerTrueFailure(TRUE, FALSE) = "yes"
    BY SMT DEF RenderedFirstSiteFailure,
        SelectedTrueGuard, SelectedFalseGuard, WrongEagerTrueFailure

======================================================================
