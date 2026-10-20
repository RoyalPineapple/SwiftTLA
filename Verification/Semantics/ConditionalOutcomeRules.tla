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

SourceWhenStep(defined, condition, continuation) ==
    defined /\ condition /\ continuation
CompiledWhenStep(defined, condition, continuation) ==
    (IF defined THEN condition ELSE FALSE) /\ continuation
RenderedWhenStep(defined, condition, continuation) ==
    DefinedConditional(defined, condition, continuation, FALSE)
SourceWhenFirstFailure(defined, condition, continuationFails) ==
    IF ~defined THEN "condition"
    ELSE IF condition /\ continuationFails THEN "continuation" ELSE "none"
RenderedWhenFirstFailure(defined, condition, continuationFails) ==
    LET failure == RenderedFirstFailure(defined, condition, continuationFails, FALSE)
    IN IF failure = "yes" THEN "continuation" ELSE failure

THEOREM WhenPreservesStepAndFirstFailure ==
    ASSUME NEW defined \in BOOLEAN, NEW condition \in BOOLEAN,
           NEW continuation \in BOOLEAN, NEW continuationFails \in BOOLEAN,
           NEW label, NEW actionLabel
    PROVE /\ (label = actionLabel /\ SourceWhenStep(defined, condition, continuation)
                <=> label = actionLabel /\ CompiledWhenStep(defined, condition, continuation))
          /\ (CompiledWhenStep(defined, condition, continuation)
                <=> RenderedWhenStep(defined, condition, continuation))
          /\ SourceWhenFirstFailure(defined, condition, continuationFails)
                = RenderedWhenFirstFailure(defined, condition, continuationFails)
    BY DefinedConditionalPreservesStepAndFirstFailure, SMT
        DEF SourceWhenStep, CompiledWhenStep, RenderedWhenStep,
        SourceWhenFirstFailure, RenderedWhenFirstFailure,
        DefinedGuardedBranches, DefinedConditional,
        RenderedFirstFailure, RenderedConditionFailure,
        RenderedYesFailure, RenderedNoFailure

WrongEagerContinuationFailure(defined, continuationFails) ==
    IF ~defined THEN "condition"
    ELSE IF continuationFails THEN "continuation" ELSE "none"

THEOREM DisabledWhenSuppressesContinuationFailure ==
    SourceWhenFirstFailure(TRUE, FALSE, TRUE)
        = RenderedWhenFirstFailure(TRUE, FALSE, TRUE)
        /\ SourceWhenFirstFailure(TRUE, FALSE, TRUE)
            # WrongEagerContinuationFailure(TRUE, TRUE)
    BY WhenPreservesStepAndFirstFailure, SMT
        DEF SourceWhenFirstFailure, WrongEagerContinuationFailure

=====================================================================
