-------------------- MODULE InitializationOutcomeRules --------------------
EXTENDS TLAPS

CONSTANTS Keys, Values, FailureValues, NoFailure, NoInitialSite
ASSUME InitialSentinels ==
    /\ NoFailure \notin FailureValues
    /\ NoInitialSite \notin Keys

InitializerOutcomes ==
    {outcome \in [candidates: SUBSET Values,
                  firstFailure: FailureValues \cup {NoFailure}] :
        outcome.firstFailure # NoFailure => outcome.candidates = {}}

SourceFixed(value) == [candidates |-> {value}, firstFailure |-> NoFailure]
GeneratedFixed(value) ==
    [candidates |-> {candidate \in Values : candidate = value},
     firstFailure |-> NoFailure]
SourceDomain(members) == [candidates |-> members, firstFailure |-> NoFailure]
GeneratedDomain(members) ==
    [candidates |-> Values \cap members, firstFailure |-> NoFailure]
SourceFailed(failure) == [candidates |-> {}, firstFailure |-> failure]
GeneratedFailed(failure) ==
    [candidates |-> {candidate \in Values : FALSE}, firstFailure |-> failure]

THEOREM FixedInitializerRetainsItsOnlyCandidate ==
    ASSUME NEW value \in Values
    PROVE /\ SourceFixed(value) = GeneratedFixed(value)
          /\ SourceFixed(value) \in InitializerOutcomes
    BY SMT DEF SourceFixed, GeneratedFixed, InitializerOutcomes

THEOREM DomainInitializerRetainsEveryCandidate ==
    ASSUME NEW members \in SUBSET Values
    PROVE /\ SourceDomain(members) = GeneratedDomain(members)
          /\ SourceDomain(members) \in InitializerOutcomes
    BY SMT DEF SourceDomain, GeneratedDomain, InitializerOutcomes

THEOREM FailedInitializerRetainsItsCompletePayload ==
    ASSUME NEW failure \in FailureValues
    PROVE /\ SourceFailed(failure) = GeneratedFailed(failure)
          /\ SourceFailed(failure) \in InitializerOutcomes
    BY SMT DEF SourceFailed, GeneratedFailed, InitializerOutcomes

SourceExtension(prior, key, value, next) ==
    /\ key \notin DOMAIN prior
    /\ DOMAIN next = (DOMAIN prior) \cup {key}
    /\ next[key] = value
    /\ \A name \in DOMAIN prior : next[name] = prior[name]

GeneratedExtension(prior, key, value) ==
    [name \in (DOMAIN prior) \cup {key} |->
        IF name = key THEN value ELSE prior[name]]

THEOREM GeneratedExtensionIsTyped ==
    ASSUME NEW bound \in SUBSET Keys, NEW prior \in [bound -> Values],
           NEW key \in Keys \ bound, NEW value \in Values
    PROVE GeneratedExtension(prior, key, value) \in [bound \cup {key} -> Values]
    BY SMT DEF GeneratedExtension

THEOREM ExtensionRetainsAllPriorBindings ==
    ASSUME NEW bound \in SUBSET Keys, NEW prior \in [bound -> Values],
           NEW key \in Keys \ bound, NEW value \in Values,
           NEW next \in [bound \cup {key} -> Values]
    PROVE SourceExtension(prior, key, value, next)
        <=> next = GeneratedExtension(prior, key, value)
    BY SMT DEF SourceExtension, GeneratedExtension

SourceInitialStates(prior, key, outcome) ==
    {next \in [(DOMAIN prior) \cup {key} -> Values] :
        \E value \in outcome.candidates : SourceExtension(prior, key, value, next)}
GeneratedInitialStates(prior, key, outcome) ==
    {GeneratedExtension(prior, key, value) : value \in outcome.candidates}

SourceInitialFailures(prior, key, outcome) ==
    IF outcome.firstFailure = NoFailure THEN {}
    ELSE {[before |-> prior, site |-> key, payload |-> outcome.firstFailure]}
GeneratedInitialFailures(prior, key, outcome) ==
    {event \in {[before |-> prior, site |-> key, payload |-> outcome.firstFailure]} :
        outcome.firstFailure # NoFailure}

SourceInitialLeaf(prior, key, outcome) ==
    [states |-> SourceInitialStates(prior, key, outcome),
     failures |-> SourceInitialFailures(prior, key, outcome)]
GeneratedInitialLeaf(prior, key, outcome) ==
    [states |-> GeneratedInitialStates(prior, key, outcome),
     failures |-> GeneratedInitialFailures(prior, key, outcome)]

THEOREM InitializerLeafRetainsCompleteStatesAndFailures ==
    ASSUME NEW bound \in SUBSET Keys, NEW prior \in [bound -> Values],
           NEW key \in Keys \ bound, NEW outcome \in InitializerOutcomes
    PROVE SourceInitialLeaf(prior, key, outcome)
        = GeneratedInitialLeaf(prior, key, outcome)
    PROOF
    <1>1. \A value \in outcome.candidates :
              GeneratedExtension(prior, key, value) \in [bound \cup {key} -> Values]
        BY GeneratedExtensionIsTyped, SMT DEF InitializerOutcomes
    <1>2. GeneratedInitialStates(prior, key, outcome)
            \subseteq [bound \cup {key} -> Values]
        BY <1>1, SMT DEF GeneratedInitialStates
    <1>3. \A next \in [bound \cup {key} -> Values] :
              next \in SourceInitialStates(prior, key, outcome)
                <=> next \in GeneratedInitialStates(prior, key, outcome)
        BY ExtensionRetainsAllPriorBindings, SMT
            DEF SourceInitialStates, GeneratedInitialStates, InitializerOutcomes
    <1>4. SourceInitialStates(prior, key, outcome)
            = GeneratedInitialStates(prior, key, outcome)
        BY <1>2, <1>3, SMT DEF SourceInitialStates
    <1>5. SourceInitialFailures(prior, key, outcome)
            = GeneratedInitialFailures(prior, key, outcome)
        BY SMT DEF SourceInitialFailures, GeneratedInitialFailures
    <1>. QED BY <1>4, <1>5 DEF SourceInitialLeaf, GeneratedInitialLeaf

THEOREM EmptySuccessfulDomainIsNotAFailedDomain ==
    ASSUME NEW failure \in FailureValues
    PROVE /\ SourceDomain({}).candidates = SourceFailed(failure).candidates
          /\ SourceDomain({}) # SourceFailed(failure)
    BY InitialSentinels, SMT
        DEF InitialSentinels, SourceDomain, SourceFailed

THEOREM DroppingAValidSiblingChangesTheInitialStates ==
    ASSUME NEW bound \in SUBSET Keys, NEW prior \in [bound -> Values],
           NEW key \in Keys \ bound, NEW first \in Values, NEW second \in Values,
           first # second
    PROVE GeneratedInitialStates(prior, key, SourceDomain({first, second}))
        # GeneratedInitialStates(prior, key, SourceDomain({first}))
    BY SMT DEF GeneratedInitialStates, GeneratedExtension, SourceDomain

EmptyFirstFailure == [payload |-> NoFailure, site |-> NoInitialSite]
SourceStoreFirst(stored, event) ==
    IF stored.payload = NoFailure
    THEN [payload |-> event.payload, site |-> event.site]
    ELSE stored
GeneratedStoreFirst(stored, event) ==
    IF stored.payload # NoFailure THEN stored
    ELSE [payload |-> event.payload, site |-> event.site]

THEOREM FirstFailureStoragePreservesItsSiteAndPayload ==
    ASSUME NEW stored, NEW event
    PROVE SourceStoreFirst(stored, event) = GeneratedStoreFirst(stored, event)
    BY SMT DEF SourceStoreFirst, GeneratedStoreFirst

THEOREM EqualFirstFailureDoesNotProveCompleteFailures ==
    ASSUME NEW first, NEW second,
           first.payload \in FailureValues, first # second
    PROVE /\ GeneratedStoreFirst(GeneratedStoreFirst(EmptyFirstFailure, first), second)
                = GeneratedStoreFirst(EmptyFirstFailure, first)
          /\ {first, second} # {first}
    BY InitialSentinels, SMT
        DEF InitialSentinels, GeneratedStoreFirst, EmptyFirstFailure

\* A domain remains mathematical; the declared variable type constrains states.
TypedInitializerOutcome(allowed, outcome) ==
    [candidates |-> allowed \cap outcome.candidates,
     firstFailure |-> outcome.firstFailure]

SourceTypedInitialLeaf(prior, key, allowed, outcome) ==
    [states |-> {next \in SourceInitialStates(prior, key, outcome) : next[key] \in allowed},
     failures |-> SourceInitialFailures(prior, key, outcome)]
GeneratedTypedInitialLeaf(prior, key, allowed, outcome) ==
    GeneratedInitialLeaf(prior, key, TypedInitializerOutcome(allowed, outcome))

THEOREM TypedInitializerRetainsCompleteStatesAndFailures ==
    ASSUME NEW bound \in SUBSET Keys, NEW prior \in [bound -> Values],
           NEW key \in Keys \ bound, NEW allowed \in SUBSET Values,
           NEW universe,
           NEW outcome \in [candidates: SUBSET universe,
                             firstFailure: FailureValues \cup {NoFailure}],
           outcome.firstFailure # NoFailure => outcome.candidates = {}
    PROVE SourceTypedInitialLeaf(prior, key, allowed, outcome)
        = GeneratedTypedInitialLeaf(prior, key, allowed, outcome)
    PROOF
    <1>1. TypedInitializerOutcome(allowed, outcome) \in InitializerOutcomes
        BY SMT DEF TypedInitializerOutcome, InitializerOutcomes
    <1>2. SourceTypedInitialLeaf(prior, key, allowed, outcome)
        = SourceInitialLeaf(prior, key, TypedInitializerOutcome(allowed, outcome))
        BY SMT DEF SourceTypedInitialLeaf, SourceInitialLeaf, SourceInitialStates,
            SourceInitialFailures, SourceExtension, TypedInitializerOutcome
    <1>3. SourceInitialLeaf(prior, key, TypedInitializerOutcome(allowed, outcome))
        = GeneratedInitialLeaf(prior, key, TypedInitializerOutcome(allowed, outcome))
        BY <1>1, InitializerLeafRetainsCompleteStatesAndFailures
    <1>. QED BY <1>2, <1>3 DEF GeneratedTypedInitialLeaf

THEOREM OmittingTheDeclaredTypeChangesCompleteInitialStates ==
    ASSUME NEW bound \in SUBSET Keys, NEW prior \in [bound -> Values],
           NEW key \in Keys \ bound, NEW allowed \in SUBSET Values,
           NEW universe,
           NEW outcome \in [candidates: SUBSET universe,
                             firstFailure: FailureValues \cup {NoFailure}],
           outcome.firstFailure = NoFailure,
           NEW outside \in outcome.candidates \ allowed
    PROVE GeneratedInitialLeaf(prior, key, outcome).states
        # SourceTypedInitialLeaf(prior, key, allowed, outcome).states
    PROOF
    <1>1. GeneratedExtension(prior, key, outside)
        \in GeneratedInitialLeaf(prior, key, outcome).states
        BY SMT DEF GeneratedInitialLeaf, GeneratedInitialStates
    <1>2. GeneratedExtension(prior, key, outside)
        \notin SourceTypedInitialLeaf(prior, key, allowed, outcome).states
        BY SMT DEF SourceTypedInitialLeaf, GeneratedExtension
    <1>. QED BY <1>1, <1>2, SMT

=============================================================================
