--------------- MODULE ConditionalChoiceConditionFailureProof ---------------
EXTENDS TLAPS, ConditionalChoiceConditionFailure, ConditionalOutcomeRules

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
    /\ (__SwiftTLAAnyEvaluationFailure0 <=> SourceFailure)
    /\ (__SwiftTLAEvaluationOK <=> ~SourceFailure)
    BY EmptyChoiceHasNoMatch, SMT
        DEF __SwiftTLAChoiceFailure0, __SwiftTLAAnyEvaluationFailure0,
            __SwiftTLAEvaluationOK,
            SourceFailure

THEOREM EmittedConditionFailureInstantiatesDefinedRule ==
    ASSUME pc = "select"
    PROVE /\ (select <=> DefinedConditional(HasMatch, TRUE, SourceThen, SourceElse))
          /\ (__SwiftTLAChoiceFailure0 <=> RenderedConditionFailure(HasMatch))
    BY EmptyChoiceHasNoMatch, CompleteLabeledRelationAgrees,
        SelectedFailureAndCheckingInvariantAgree, SMT
        DEF DefinedConditional, RenderedConditionFailure, SourceFailure,
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
