---- MODULE CheckingSelectionCompilerBinding ----
EXTENDS CheckingSelectionComposition, ActionFailureHistoryProjection, SequenceTheorems_proofs

\* The compiler enumerates the concatenated invariant, reachability and
\* temporal registrations. Array offsets are zero-based property identities.
CatalogOrdinal(catalog, property) ==
    (CHOOSE index \in 1..Len(catalog) : catalog[index] = property) - 1

CatalogAllocation(catalog) ==
    [property \in CatalogMembers(catalog) |-> CatalogOrdinal(catalog, property)]

CatalogReferences(catalog, present, handles) ==
    [property \in CatalogMembers(catalog) |->
        IF present[property] THEN handles[property] ELSE NoPropertyHandle]

THEOREM OrderedRegistrationConstructsTheCatalogAndAllocation ==
    ASSUME NEW declarations, NEW catalog \in Seq(declarations), NEW present, NEW handles
    PROVE LET registered == CatalogMembers(catalog)
              allocation == CatalogAllocation(catalog)
              references == CatalogReferences(catalog, present, handles)
          IN /\ allocation \in [registered -> 0..(Len(catalog) - 1)]
             /\ FaithfulPropertyCatalog(catalog, registered, present, handles, references, allocation)
    PROOF
    <1>. DEFINE registered == CatalogMembers(catalog)
                allocation == CatalogAllocation(catalog)
                references == CatalogReferences(catalog, present, handles)
    <1>ordinals. \A property \in registered :
        \E index \in 1..Len(catalog) :
            catalog[index] = property /\ allocation[property] = index - 1
        <2>. TAKE property \in registered
        <2>covered. \E index \in 1..Len(catalog) : catalog[index] = property
            BY ONLY (property \in registered), SMT DEF registered, CatalogMembers
        <2>. QED BY ONLY (property \in registered), <2>covered, SMT DEF allocation, CatalogAllocation, CatalogOrdinal
    <1>typed. allocation \in [registered -> 0..(Len(catalog) - 1)]
        BY ONLY <1>ordinals, SMT DEF allocation, CatalogAllocation
    <1>distinct. \A left, right \in registered : allocation[left] = allocation[right] => left = right
        BY ONLY <1>ordinals, SMT
    <1>. QED BY ONLY <1>typed, <1>distinct, SMT
        DEF FaithfulPropertyCatalog, registered, references, CatalogReferences

CheckingSignature(invariants, reachability, deadlock) ==
    [invariants |-> invariants, reachability |-> reachability, deadlock |-> deadlock]

THEOREM ConstructorSelectionSuppliesTheCheckingSignature ==
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
           NEW enabled \in BOOLEAN, SourceDeadlockSelection(default, overrides, enabled)
    PROVE CheckingSignature(SourcePropertySelection(declarations, present, handles, only, selected) \cap invariants,
              SourcePropertySelection(declarations, present, handles, only, selected) \cap reachability, enabled)
          = CheckingSignature(
              {property \in declarations : allocation[property] \in
                  LoweredPropertySelection(catalog, references, allocation, only, selected)} \cap invariants,
              {property \in declarations : allocation[property] \in
                  LoweredPropertySelection(catalog, references, allocation, only, selected)} \cap reachability,
              LoweredDeadlockSelection(default, overrides))
    PROOF
    <1>inputs. /\ {property \in declarations : allocation[property] \in
                         LoweredPropertySelection(catalog, references, allocation, only, selected)}
                   = SourcePropertySelection(declarations, present, handles, only, selected)
                /\ enabled = LoweredDeadlockSelection(default, overrides)
        BY SelectionConstructorsComposeTheCheckingInputs
    <1>. QED BY <1>inputs, SMT

THEOREM ReachableCheckingFailureMembershipIsAnOrderedOccurrence ==
    ASSUME NEW history, NEW reached, NEW occurrence
    PROVE (occurrence \in ReachableCheckingFailures(reached, ActionFailureEventSet(history)))
          <=> (occurrence[1] \in reached /\
                  \E index \in DOMAIN history : history[index] = occurrence)
    BY ActionFailureEventSetHasExactMembership, SMT DEF ReachableCheckingFailures

THEOREM ExhaustiveSelectedCheckingWithOrderedActionFailures ==
    ASSUME NEW states, NEW labels, NEW properties, NEW failureRecords,
           NEW sourceInitials \in SUBSET states, NEW generatedInitials \in SUBSET states,
           NEW sourceEdges \in SUBSET (states \X labels \X states),
           NEW generatedEdges \in SUBSET (states \X labels \X states),
           NEW sourceSelection, NEW generatedSelection, sourceSelection = generatedSelection,
           sourceSelection.invariants \subseteq properties,
           sourceSelection.reachability \subseteq properties,
           sourceSelection.deadlock \in BOOLEAN,
           NEW sourceClaims \in [properties -> [states -> BOOLEAN]],
           NEW generatedClaims \in [properties -> [states -> BOOLEAN]],
           NEW sourceInitialFailures \in SUBSET failureRecords,
           NEW generatedInitialFailures \in SUBSET failureRecords,
           NEW sourceHistory \in Seq(states \X labels \X failureRecords),
           NEW generatedHistory \in Seq(states \X labels \X failureRecords),
           DOMAIN sourceHistory = DOMAIN generatedHistory,
           \A index \in DOMAIN sourceHistory : sourceHistory[index] = generatedHistory[index],
           NEW reached \in SUBSET states,
           sourceInitials = generatedInitials, sourceEdges = generatedEdges,
           sourceInitialFailures = generatedInitialFailures,
           \A property \in sourceSelection.invariants \cup sourceSelection.reachability,
               state \in states : sourceClaims[property][state] = generatedClaims[property][state],
           reached = SourceCheckingReachable(states, labels, generatedInitials, generatedEdges)
    PROVE LET source == SourceCheckingObservation(states, labels, sourceInitials, sourceEdges,
                         sourceSelection.invariants, sourceSelection.reachability, sourceClaims,
                         sourceInitialFailures, ActionFailureEventSet(sourceHistory), sourceSelection.deadlock)
              generated == GeneratedCheckingObservation(labels, generatedInitials, generatedEdges, reached,
                              generatedSelection.invariants, generatedSelection.reachability, generatedClaims,
                              generatedInitialFailures, ActionFailureEventSet(generatedHistory), generatedSelection.deadlock)
          IN /\ source = generated
             /\ sourceHistory = generatedHistory
             /\ \A occurrence \in states \X labels \X failureRecords :
                    (occurrence \in generated.actionFailures) <=>
                        (occurrence[1] \in reached /\
                            \E index \in DOMAIN generatedHistory : generatedHistory[index] = occurrence)
    PROOF
    <1>. DEFINE failures == states \X labels \X failureRecords
                source == SourceCheckingObservation(states, labels, sourceInitials, sourceEdges,
                             sourceSelection.invariants, sourceSelection.reachability, sourceClaims,
                             sourceInitialFailures, ActionFailureEventSet(sourceHistory), sourceSelection.deadlock)
                generated == GeneratedCheckingObservation(labels, generatedInitials, generatedEdges, reached,
                                  generatedSelection.invariants, generatedSelection.reachability, generatedClaims,
                                  generatedInitialFailures, ActionFailureEventSet(generatedHistory), generatedSelection.deadlock)
    <1>domains. /\ DOMAIN sourceHistory = 1..Len(sourceHistory)
                 /\ DOMAIN generatedHistory = 1..Len(generatedHistory)
                 /\ sourceHistory \in [1..Len(sourceHistory) -> failures]
        BY ONLY (sourceHistory \in Seq(states \X labels \X failureRecords)),
            (generatedHistory \in Seq(states \X labels \X failureRecords)), LenProperties, SMT DEF failures
    <1>order. sourceHistory = generatedHistory
        BY <1>domains, SMT
    <1>range. ActionFailureEventSet(sourceHistory) \in SUBSET failures
        BY ONLY <1>domains, SMT DEF ActionFailureEventSet
    <1>sets. /\ ActionFailureEventSet(generatedHistory) \in SUBSET failures
              /\ ActionFailureEventSet(sourceHistory) = ActionFailureEventSet(generatedHistory)
        BY <1>order, <1>range
    <1>observation. source = generated
        BY <1>range, <1>sets, ExhaustiveSelectedCheckingObservationsCompose, SMT DEF source, generated
    <1>membership. \A occurrence \in failures :
            (occurrence \in generated.actionFailures) <=>
                (occurrence[1] \in reached /\
                    \E index \in DOMAIN generatedHistory : generatedHistory[index] = occurrence)
        BY ReachableCheckingFailureMembershipIsAnOrderedOccurrence, SMT
            DEF generated, GeneratedCheckingObservation
    <1>. QED BY <1>order, <1>observation, <1>membership DEF failures, source, generated

====
