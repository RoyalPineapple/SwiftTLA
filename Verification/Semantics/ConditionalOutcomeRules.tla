-------------------- MODULE ConditionalOutcomeRules --------------------
EXTENDS TLAPS

DefinedConditional(defined, condition, yes, no) ==
    IF defined THEN (IF condition THEN yes ELSE no) ELSE FALSE
DefinedGuardedBranches(defined, condition, yes, no) ==
    ((IF defined THEN condition ELSE FALSE) /\ yes)
    \/ ((IF defined THEN ~condition ELSE FALSE) /\ no)
SourceConditionalStep(defined, condition, yes, no) ==
    defined /\ ((condition /\ yes) \/ (~condition /\ no))
SourceFirstFailure(defined, condition, yesFails, noFails) ==
    IF ~defined THEN "condition"
    ELSE IF condition THEN (IF yesFails THEN "yes" ELSE "none")
    ELSE IF noFails THEN "no" ELSE "none"
RenderedConditionFailure(defined) == ~defined
RenderedYesFailure(defined, condition, yesFails) ==
    IF defined THEN (IF condition THEN yesFails ELSE FALSE) ELSE FALSE
RenderedNoFailure(defined, condition, noFails) ==
    IF defined THEN (IF condition THEN FALSE ELSE noFails) ELSE FALSE
RenderedFirstFailure(defined, condition, yesFails, noFails) ==
    IF RenderedConditionFailure(defined) THEN "condition"
    ELSE IF RenderedYesFailure(defined, condition, yesFails) THEN "yes"
    ELSE IF RenderedNoFailure(defined, condition, noFails) THEN "no"
    ELSE "none"

THEOREM DefinedConditionalPreservesStepAndFirstFailure ==
    ASSUME NEW defined \in BOOLEAN, NEW condition \in BOOLEAN,
           NEW yes \in BOOLEAN, NEW no \in BOOLEAN,
           NEW yesFails \in BOOLEAN, NEW noFails \in BOOLEAN,
           NEW label, NEW actionLabel
    PROVE /\ (label = actionLabel /\ SourceConditionalStep(defined, condition, yes, no)
                <=> label = actionLabel /\ DefinedGuardedBranches(defined, condition, yes, no))
          /\ (DefinedGuardedBranches(defined, condition, yes, no)
                <=> DefinedConditional(defined, condition, yes, no))
          /\ SourceFirstFailure(defined, condition, yesFails, noFails)
                = RenderedFirstFailure(defined, condition, yesFails, noFails)
    BY SMT DEF SourceConditionalStep, DefinedGuardedBranches,
        DefinedConditional,
        SourceFirstFailure, RenderedFirstFailure,
        RenderedConditionFailure, RenderedYesFailure, RenderedNoFailure

WrongUnselectedFailure(defined, yesFails, noFails) ==
    IF ~defined THEN "condition"
    ELSE IF yesFails THEN "yes" ELSE IF noFails THEN "no" ELSE "none"

THEOREM UnselectedBranchFailureWouldBeWrong ==
    SourceFirstFailure(TRUE, TRUE, FALSE, TRUE)
        = RenderedFirstFailure(TRUE, TRUE, FALSE, TRUE)
        /\ SourceFirstFailure(TRUE, TRUE, FALSE, TRUE)
            # WrongUnselectedFailure(TRUE, FALSE, TRUE)
    BY SMT DEF SourceFirstFailure, RenderedFirstFailure,
        RenderedConditionFailure, RenderedYesFailure, RenderedNoFailure,
        WrongUnselectedFailure

=====================================================================
