---------------- MODULE CheckingSelectionComposition ----------------
EXTENDS CheckingSelectionRule

CheckingPath(states, labels, initials, edges, path) ==
    /\ path \in Seq(states)
    /\ Len(path) > 0
    /\ path[1] \in initials
    /\ \A index \in 1..(Len(path) - 1) :
        \E label \in labels : <<path[index], label, path[index + 1]>> \in edges

SourceCheckingReachable(states, labels, initials, edges) ==
    {state \in states : \E path \in Seq(states) :
        CheckingPath(states, labels, initials, edges, path) /\ path[Len(path)] = state}

CheckingDeadlocks(reachable, labels, edges) ==
    {state \in reachable :
        ~(\E label \in labels, target \in reachable : <<state, label, target>> \in edges)}

ReachableCheckingFailures(reachable, failures) ==
    {failure \in failures : failure[1] \in reachable}

SourceCheckingObservation(states, labels, initials, edges, invariants, reachability,
    claims, initialFailures, actionFailures, checkDeadlock) ==
    LET reached == SourceCheckingReachable(states, labels, initials, edges)
        failures == ReachableCheckingFailures(reached, actionFailures)
        noDeadlock == \A state \in reached :
            \E label \in labels, target \in reached : <<state, label, target>> \in edges
    IN [initials |-> initials, edges |-> edges,
        initialFailures |-> initialFailures, actionFailures |-> failures,
        invariants |-> [property \in invariants |-> IF initials = {} THEN "unavailable"
            ELSE \A state \in reached : claims[property][state]],
        reachability |-> [property \in reachability |-> IF initials = {} THEN "unavailable"
            ELSE \E state \in reached : claims[property][state]],
        deadlock |-> IF ~checkDeadlock THEN "disabled"
                    ELSE IF initials = {} THEN "unavailable" ELSE noDeadlock,
        decision |-> IF initialFailures # {} \/ failures # {} THEN "evaluationFailure"
                    ELSE IF initials = {} THEN "noInitialStates"
                    ELSE IF checkDeadlock /\ ~noDeadlock THEN "deadlock" ELSE "complete"]

GeneratedCheckingObservation(labels, initials, edges, reached, invariants, reachability,
    claims, initialFailures, actionFailures, checkDeadlock) ==
    LET failures == ReachableCheckingFailures(reached, actionFailures)
        deadlocks == CheckingDeadlocks(reached, labels, edges)
    IN [initials |-> initials, edges |-> edges,
        initialFailures |-> initialFailures, actionFailures |-> failures,
        invariants |-> [property \in invariants |-> IF initials = {} THEN "unavailable"
            ELSE {state \in reached : ~claims[property][state]} = {}],
        reachability |-> [property \in reachability |-> IF initials = {} THEN "unavailable"
            ELSE {state \in reached : claims[property][state]} # {}],
        deadlock |-> IF ~checkDeadlock THEN "disabled"
                    ELSE IF initials = {} THEN "unavailable" ELSE deadlocks = {},
        decision |-> IF initialFailures = {} /\ failures = {}
                    THEN IF initials = {} THEN "noInitialStates"
                         ELSE IF ~checkDeadlock \/ deadlocks = {} THEN "complete" ELSE "deadlock"
                    ELSE "evaluationFailure"]

THEOREM EmptyInitializationHasNoReachableState ==
    ASSUME NEW states, NEW labels, NEW edges
    PROVE SourceCheckingReachable(states, labels, {}, edges) = {}
    BY SMT DEF SourceCheckingReachable, CheckingPath

THEOREM EmptyInitialCheckingOutcomesRemainUnavailable ==
    ASSUME NEW states, NEW labels, NEW edges,
           NEW invariants, NEW reachability, NEW claims,
           NEW initialFailures, NEW actionFailures, NEW checkDeadlock \in BOOLEAN
    PROVE LET observation == SourceCheckingObservation(states, labels, {}, edges,
                  invariants, reachability, claims, initialFailures, actionFailures, checkDeadlock)
          IN /\ observation.invariants = [property \in invariants |-> "unavailable"]
             /\ observation.reachability = [property \in reachability |-> "unavailable"]
             /\ observation.deadlock = IF checkDeadlock THEN "unavailable" ELSE "disabled"
             /\ observation.actionFailures = {}
             /\ observation.decision = IF initialFailures = {} THEN "noInitialStates"
                                       ELSE "evaluationFailure"
    PROOF
    <1>1. SourceCheckingReachable(states, labels, {}, edges) = {}
        BY EmptyInitializationHasNoReachableState
    <1>. QED BY <1>1, SMT DEF SourceCheckingObservation, ReachableCheckingFailures

THEOREM ExhaustiveSelectedCheckingObservationsCompose ==
    ASSUME NEW states, NEW labels, NEW properties, NEW failureRecords,
           NEW sourceInitials \in SUBSET states, NEW generatedInitials \in SUBSET states,
           NEW sourceEdges \in SUBSET (states \X labels \X states),
           NEW generatedEdges \in SUBSET (states \X labels \X states),
           NEW sourceInvariants \in SUBSET properties, NEW generatedInvariants \in SUBSET properties,
           NEW sourceReachability \in SUBSET properties, NEW generatedReachability \in SUBSET properties,
           NEW sourceClaims \in [properties -> [states -> BOOLEAN]],
           NEW generatedClaims \in [properties -> [states -> BOOLEAN]],
           NEW sourceInitialFailures \in SUBSET failureRecords,
           NEW generatedInitialFailures \in SUBSET failureRecords,
           NEW sourceActionFailures \in SUBSET (states \X labels \X failureRecords),
           NEW generatedActionFailures \in SUBSET (states \X labels \X failureRecords),
           NEW sourceDeadlock \in BOOLEAN, NEW generatedDeadlock \in BOOLEAN,
           NEW generatedReachable \in SUBSET states,
           sourceInitials = generatedInitials, sourceEdges = generatedEdges,
           sourceInvariants = generatedInvariants, sourceReachability = generatedReachability,
           sourceInitialFailures = generatedInitialFailures,
           sourceActionFailures = generatedActionFailures, sourceDeadlock = generatedDeadlock,
           \A property \in sourceInvariants \cup sourceReachability, state \in states :
               sourceClaims[property][state] = generatedClaims[property][state],
           generatedReachable = SourceCheckingReachable(states, labels, generatedInitials, generatedEdges)
    PROVE SourceCheckingObservation(states, labels, sourceInitials, sourceEdges,
              sourceInvariants, sourceReachability, sourceClaims,
              sourceInitialFailures, sourceActionFailures, sourceDeadlock)
          = GeneratedCheckingObservation(labels, generatedInitials, generatedEdges, generatedReachable,
              generatedInvariants, generatedReachability, generatedClaims,
              generatedInitialFailures, generatedActionFailures, generatedDeadlock)
    PROOF
    <1>1. generatedReachable = SourceCheckingReachable(states, labels, sourceInitials, sourceEdges)
        BY SMT
    <1>2. \A property \in sourceInvariants \cup sourceReachability, state \in generatedReachable :
        sourceClaims[property][state] = generatedClaims[property][state]
        BY SMT
    <1>3. [property \in sourceInvariants |-> \A state \in generatedReachable : sourceClaims[property][state]]
        = [property \in generatedInvariants |->
            {state \in generatedReachable : ~generatedClaims[property][state]} = {}]
        BY <1>2, SMT
    <1>4. [property \in sourceReachability |-> \E state \in generatedReachable : sourceClaims[property][state]]
        = [property \in generatedReachability |->
            {state \in generatedReachable : generatedClaims[property][state]} # {}]
        BY <1>2, SMT
    <1>5. (\A state \in generatedReachable :
        \E label \in labels, target \in generatedReachable : <<state, label, target>> \in sourceEdges)
        <=> CheckingDeadlocks(generatedReachable, labels, generatedEdges) = {}
        BY SMT DEF CheckingDeadlocks
    <1>. QED BY <1>1, <1>3, <1>4, <1>5, SMT
        DEF SourceCheckingObservation, GeneratedCheckingObservation

THEOREM DisabledDeadlockDoesNotHideEvaluationFailure ==
    ASSUME NEW states, NEW labels, NEW initials, NEW edges,
           NEW invariants, NEW reachability, NEW claims,
           NEW initialFailures, NEW actionFailures,
           initialFailures # {}
    PROVE SourceCheckingObservation(states, labels, initials, edges, invariants, reachability,
              claims, initialFailures, actionFailures, FALSE).decision = "evaluationFailure"
    BY SMT DEF SourceCheckingObservation

THEOREM SelectionConstructorsComposeWithAnObservation ==
    ASSUME NEW declarations, NEW handleValues, NEW compiledIDs,
           NoPropertyHandle \notin handleValues,
           NEW catalog \in Seq(declarations),
           NEW present \in [declarations -> BOOLEAN],
           NEW handles \in [declarations -> (handleValues \cup {NoPropertyHandle})],
           NEW references \in [declarations -> (handleValues \cup {NoPropertyHandle})],
           NEW allocation \in [declarations -> compiledIDs],
           FaithfulPropertyCatalog(catalog, declarations, present, handles, references, allocation),
           NEW only \in BOOLEAN, NEW selected \in SUBSET handleValues,
           NEW invariants \in SUBSET declarations, NEW reachability \in SUBSET declarations,
           NEW default \in BOOLEAN, NEW overrides \in Seq(BOOLEAN), Len(overrides) <= 1,
           NEW enabled \in BOOLEAN, SourceDeadlockSelection(default, overrides, enabled),
           NEW observation(_, _, _)
    PROVE observation(
              SourcePropertySelection(declarations, present, handles, only, selected) \cap invariants,
              SourcePropertySelection(declarations, present, handles, only, selected) \cap reachability,
              enabled)
          = observation(
              {property \in declarations : allocation[property] \in
                  LoweredPropertySelection(catalog, references, allocation, only, selected)} \cap invariants,
              {property \in declarations : allocation[property] \in
                  LoweredPropertySelection(catalog, references, allocation, only, selected)} \cap reachability,
              LoweredDeadlockSelection(default, overrides))
    PROOF
    <1>1. \A property \in declarations :
        allocation[property] \in LoweredPropertySelection(catalog, references, allocation, only, selected)
        <=> property \in SourcePropertySelection(declarations, present, handles, only, selected)
        BY CatalogSelectionPreservesIdentity
    <1>2. {property \in declarations : allocation[property] \in
              LoweredPropertySelection(catalog, references, allocation, only, selected)}
          = SourcePropertySelection(declarations, present, handles, only, selected)
        BY <1>1, SMT DEF SourcePropertySelection
    <1>3. enabled = LoweredDeadlockSelection(default, overrides)
        BY DeadlockOverridePreservesTheUniqueSourceChoice
    <1>. QED BY <1>2, <1>3, SMT
=============================================================================
