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
