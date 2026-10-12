--------------- MODULE ConditionalChoiceConditionFailureProof ---------------
EXTENDS TLAPS, ConditionalChoiceConditionFailure

HasMatch == \E member \in {TRUE} : FALSE
SourceInit == pc = "select" /\ selected = 0
SourceThen == selected' = 1 /\ pc' = "Done"
SourceElse == selected' = 2 /\ pc' = "Done"
SourceSelect ==
    pc = "select" /\
    (\E member \in {TRUE} : FALSE /\ (IF member THEN SourceThen ELSE SourceElse))
SourceTerminating == pc = "Done" /\ UNCHANGED <<pc, selected>>
SourceFailure == pc = "select" /\ ~HasMatch
SourceLabeled(label) ==
    \/ label = "select" /\ SourceSelect
    \/ label = "Terminating" /\ SourceTerminating
EmittedLabeled(label) ==
    \/ label = "select" /\ select
    \/ label = "Terminating" /\ Terminating

Conditional(defined, condition, yes, no) ==
    IF defined THEN (IF condition THEN yes ELSE no) ELSE FALSE
GuardedBranches(defined, condition, yes, no) ==
    ((IF defined THEN condition ELSE FALSE) /\ yes)
    \/ ((IF defined THEN ~condition ELSE FALSE) /\ no)

THEOREM ConditionalLoweringLaw ==
    ASSUME NEW defined \in BOOLEAN, NEW condition \in BOOLEAN,
           NEW yes \in BOOLEAN, NEW no \in BOOLEAN
    PROVE Conditional(defined, condition, yes, no)
          <=> GuardedBranches(defined, condition, yes, no)
    BY SMT DEF Conditional, GuardedBranches

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
           NEW label
    PROVE /\ (label = "select" /\ SourceConditionalStep(defined, condition, yes, no)
                <=> label = "select" /\ Conditional(defined, condition, yes, no))
          /\ SourceFirstFailure(defined, condition, yesFails, noFails)
                = RenderedFirstFailure(defined, condition, yesFails, noFails)
    BY ConditionalLoweringLaw, SMT
        DEF SourceConditionalStep, SourceFirstFailure,
            RenderedFirstFailure, RenderedConditionFailure,
            RenderedYesFailure, RenderedNoFailure,
            Conditional, GuardedBranches

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

THEOREM EmptyChoiceHasNoMatch ==
    ~HasMatch
    BY SMT DEF HasMatch

THEOREM InitialStatesAgree ==
    Init <=> SourceInit
    BY SMT DEF Init, SourceInit

THEOREM CompleteLabeledRelationAgrees ==
    ASSUME NEW label
    PROVE /\ (select <=> SourceSelect)
          /\ (Terminating <=> SourceTerminating)
          /\ (EmittedLabeled(label) <=> SourceLabeled(label))
          /\ (Next <=> (SourceSelect \/ SourceTerminating))
    BY EmptyChoiceHasNoMatch, SMT
        DEF select, SourceSelect, Terminating, SourceTerminating,
            SourceThen, SourceElse, EmittedLabeled, SourceLabeled, Next

THEOREM SelectedFailureAndCheckingInvariantAgree ==
    /\ (__SwiftTLAChoiceFailure0 <=> SourceFailure)
    /\ (__SwiftTLAEvaluationOK <=> ~SourceFailure)
    BY EmptyChoiceHasNoMatch, SMT
        DEF __SwiftTLAChoiceFailure0, __SwiftTLAEvaluationOK,
            SourceFailure

THEOREM EmittedConditionFailureInstantiatesDefinedRule ==
    ASSUME pc = "select"
    PROVE /\ (select <=> Conditional(HasMatch, TRUE, SourceThen, SourceElse))
          /\ (__SwiftTLAChoiceFailure0 <=> RenderedConditionFailure(HasMatch))
    BY EmptyChoiceHasNoMatch, CompleteLabeledRelationAgrees,
        SelectedFailureAndCheckingInvariantAgree, SMT
        DEF Conditional, RenderedConditionFailure, SourceFailure,
            SourceSelect

THEOREM InitialFailureHasNoTransition ==
    ASSUME SourceInit
    PROVE /\ SourceFailure
          /\ ~ENABLED Next
    BY CompleteLabeledRelationAgrees,
        SelectedFailureAndCheckingInvariantAgree,
        ExpandENABLED, SMT
        DEF SourceInit, SourceSelect, SourceTerminating, SourceFailure,
            SourceThen, SourceElse, HasMatch, Next, select, Terminating

WrongFalseBranch == pc = "select" /\ selected' = 2 /\ pc' = "Done"

THEOREM UnguardedFalseBranchIsRejected ==
    ASSUME SourceInit
    PROVE /\ ENABLED WrongFalseBranch
          /\ ~ENABLED select
    BY CompleteLabeledRelationAgrees, ExpandENABLED, SMT
        DEF SourceInit, WrongFalseBranch, SourceSelect, SourceThen,
            SourceElse, select

======================================================================
