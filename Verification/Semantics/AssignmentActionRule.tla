-------------------- MODULE AssignmentActionRule --------------------
EXTENDS PendingWriteOutcomeRule

ValueOutcomes == {result \in [defined: BOOLEAN, value: Values,
                             failure: FailureValues \cup {NoFailure}] :
                    ~result.defined => result.failure # NoFailure}

ChildValuesAgree(source, generated) ==
    /\ source.defined = generated.defined
    /\ (source.defined => source.value = generated.value)
    /\ (~source.defined => source.failure = generated.failure)

SourceAssignment(pending, target, child) ==
    IF ~child.defined THEN [updates |-> <<>>, failure |-> child.failure]
    ELSE SourcePendingWrite(pending, target, child.value)

GeneratedAssignment(pending, target, child) ==
    IF child.defined THEN GeneratedPendingWrite(pending, target, child.value)
    ELSE [updates |-> <<>>, failure |-> child.failure]

THEOREM AssignmentRuleComposes ==
    ASSUME NEW pending \in PendingUpdates, NEW target \in Vars,
           NEW source \in ValueOutcomes, NEW generated \in ValueOutcomes,
           ChildValuesAgree(source, generated)
    PROVE /\ SourceAssignment(pending, target, source) =
                 GeneratedAssignment(pending, target, generated)
          /\ SourceAssignment(pending, target, source) \in Outcomes!SingleCandidateLeft
    BY PendingWriteRuleComposes, SMT
        DEF SourceAssignment, GeneratedAssignment, ChildValuesAgree, ValueOutcomes,
            Outcomes!SingleCandidateLeft, Outcomes!OrderedOutcome

\* A relational assignment constrains its target and every inherited write.
SourceAssignedDelta(prior, next, pending, target, value) ==
    /\ next[target] = value
    /\ \A key \in DOMAIN pending : next[key] = pending[key]
    /\ \A key \in Vars \ (DOMAIN pending \cup {target}) : next[key] = prior[key]

SourceAssignmentObservation(prior, label, pending, target, child) ==
    LET successors == IF child.defined
                      THEN {next \in States :
                                SourceAssignedDelta(prior, next, pending, target, child.value)}
                      ELSE {}
        failure == IF child.defined THEN NoFailure ELSE child.failure
    IN [source |-> prior, action |-> label, successors |-> successors,
        selectedFailure |-> failure, disabled |-> successors = {} /\ failure = NoFailure]

THEOREM AssignmentPreservesCompleteLabeledOutcomes ==
    ASSUME NEW prior \in States, NEW label \in ActionLabels,
           NEW pending \in PendingUpdates, NEW target \in Vars,
           NEW source \in ValueOutcomes, NEW generated \in ValueOutcomes,
           ChildValuesAgree(source, generated)
    PROVE SourceAssignmentObservation(prior, label, pending, target, source) =
              Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                  GeneratedAssignment(pending, target, generated))
    PROOF
    <1>1. DOMAIN pending \in SUBSET Vars /\ pending \in [DOMAIN pending -> Values]
        BY PendingUpdatesHaveTypedDomains, SMT
    <1>2. SourceAssignment(pending, target, source) =
              GeneratedAssignment(pending, target, generated)
        BY AssignmentRuleComposes
    <1>3. SourceAssignmentObservation(prior, label, pending, target, source) =
              Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                  SourceAssignment(pending, target, source))
        <2>1. CASE ~source.defined
            BY <2>1, SMT
                DEF SourceAssignmentObservation, SourceAssignment, ValueOutcomes,
                    Outcomes!CompleteLabeledOutcome
        <2>2. CASE source.defined /\ target \in DOMAIN pending /\ pending[target] # source.value
            BY <2>2, SMT
                DEF SourceAssignmentObservation, SourceAssignedDelta, SourceAssignment,
                    SourcePendingWrite, Outcomes!EmptyOrdered, Outcomes!CompleteLabeledOutcome
        <2>3. CASE source.defined /\ (target \notin DOMAIN pending \/ pending[target] = source.value)
            <3>. DEFINE written == [key \in DOMAIN pending \cup {target} |->
                            IF key \in DOMAIN pending THEN pending[key] ELSE source.value]
            <3>1. written \in PendingUpdates
                BY <1>1, SMT DEF written, PendingUpdates, ValueOutcomes
            <3>2. \A next \in States :
                      SourceAssignedDelta(prior, next, pending, target, source.value)
                          <=> next = Materialize(prior)[written]
                BY <1>1, <2>3, <3>1, SMT
                    DEF SourceAssignedDelta, Materialize, written, ApplyDelta, States
            <3>3. Materialize(prior)[written] \in States
                BY <3>1, MaterializationIsComplete, SMT
            <3>. QED BY <2>3, <3>1, <3>2, <3>3, SMT
                DEF SourceAssignmentObservation, SourceAssignment, SourcePendingWrite,
                    written, Outcomes!CompleteLabeledOutcome
        <2>. QED BY <2>1, <2>2, <2>3, SMT DEF ValueOutcomes
    <1>. QED BY <1>2, <1>3, SMT

THEOREM FailurePrecedesAConflictingWrite ==
    ASSUME NEW pending \in PendingUpdates, NEW target \in DOMAIN pending,
           NEW child \in ValueOutcomes, ~child.defined,
           pending[target] # child.value
    PROVE /\ SourceAssignment(pending, target, child).updates = <<>>
          /\ SourceAssignment(pending, target, child).failure = child.failure
          /\ SourceAssignment(pending, target, child) #
                 GeneratedPendingWrite(pending, target, child.value)
    BY SMT DEF SourceAssignment, GeneratedPendingWrite, Outcomes!EmptyOrdered, ValueOutcomes

THEOREM LosingAChildFailureChangesTheOutcome ==
    ASSUME NEW pending \in PendingUpdates, NEW target \in Vars,
           NEW child \in ValueOutcomes, ~child.defined
    PROVE SourceAssignment(pending, target, child) # Outcomes!EmptyOrdered
    BY SMT DEF SourceAssignment, Outcomes!EmptyOrdered, ValueOutcomes

=============================================================================
