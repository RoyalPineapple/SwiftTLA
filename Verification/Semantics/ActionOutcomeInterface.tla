-------------------- MODULE ActionOutcomeInterface --------------------
EXTENDS TLAPS, NaturalsInduction, SequenceTheorems_proofs

CONSTANTS UpdateValues, FailureValues, NoFailure

Outcome == [updates: SUBSET UpdateValues, failure: FailureValues \cup {NoFailure}]
OrderedOutcome == [updates: Seq(UpdateValues), failure: FailureValues \cup {NoFailure}]
EmptyOrdered == [updates |-> <<>>, failure |-> NoFailure]
ConditionOutcome == [enabled: BOOLEAN, failure: FailureValues \cup {NoFailure}]
SingleCandidateLeft ==
    {result \in OrderedOutcome :
        Len(result.updates) <= 1 /\
        (Len(result.updates) = 1 => result.failure = NoFailure)}

\* finish maps each pending update to the entire resulting state, including
\* hidden control state. The action includes every invocation argument.
CompleteLabeledOutcome(prior, action, finish, none, result) ==
    [source |-> prior,
     action |-> action,
     successors |-> {finish[result.updates[index]] :
                         index \in 1..Len(result.updates)},
     selectedFailure |-> result.failure,
     disabled |-> Len(result.updates) = 0 /\ result.failure = none]

THEOREM CompleteOutcomeRetainsStateIdentityAndDisabledness ==
    ASSUME NEW fields, NEW values,
           NEW prior \in [fields -> values], NEW label,
           NEW finish \in [UpdateValues -> [fields -> values]],
           NEW result \in OrderedOutcome
    PROVE LET observed == CompleteLabeledOutcome(prior, label, finish, NoFailure, result)
          IN /\ observed.source = prior /\ observed.action = label
             /\ observed.successors \in SUBSET [fields -> values]
             /\ observed.selectedFailure = result.failure
             /\ (observed.disabled <=>
                    observed.successors = {} /\ observed.selectedFailure = NoFailure)
    BY LenProperties, ElementOfSeq, SMT DEF CompleteLabeledOutcome, OrderedOutcome


\* The decoded enumerator supplies the handle order. Each switch case supplies
\* the successor visitor ordinal and formal call name. Leaf observations come
\* from the separately checked visitor bodies.
NativeDispatchOutcome(routes, outcomes, candidate) ==
    [handle |-> routes[candidate].handle,
     formal |-> routes[candidate].formal,
     outcome |-> outcomes[routes[candidate].visitor]]

NativeDispatchLabeled(routes, nativeBranches, formalLabels, authoredLabels, label) ==
    \E candidate \in DOMAIN routes : \E action \in DOMAIN formalLabels :
        LET observation == NativeDispatchOutcome(routes, nativeBranches, candidate)
        IN /\ observation.formal = formalLabels[action]
           /\ authoredLabels[action] = label
           /\ observation.outcome

CatalogLabeledBranches(branches, labels, label) ==
    \E action \in DOMAIN labels : labels[action] = label /\ branches[action]

THEOREM CatalogLabeledBranchesComposeTheFiniteUnion ==
    ASSUME NEW branches, NEW labels, DOMAIN branches = DOMAIN labels
    PROVE (\E action \in DOMAIN branches : branches[action])
          <=> (\E label : CatalogLabeledBranches(branches, labels, label))
    BY ONLY (DOMAIN branches = DOMAIN labels), SMT DEF CatalogLabeledBranches

\* The emitted flat disjunction visits its action operands by position.
ActionCatalogPrefix(values, width) ==
    \E slot \in 1..width : values[slot]

THEOREM EmptyActionCatalogPrefix ==
    ASSUME NEW values
    PROVE ~ActionCatalogPrefix(values, 0)
    BY ONLY SMT DEF ActionCatalogPrefix

THEOREM ActionCatalogPrefixAddsOneDisjunct ==
    ASSUME NEW values, NEW width \in Nat
    PROVE ActionCatalogPrefix(values, width + 1) <=>
        (ActionCatalogPrefix(values, width) \/ values[width + 1])
PROOF
<1>positions. 1..(width + 1) = (1..width) \cup {width + 1}
    BY ONLY (width \in Nat), SMT
<1>. QED BY ONLY <1>positions, SMT DEF ActionCatalogPrefix

FollowingSequentialEntry(entries, slot, done) ==
    IF slot + 1 \in DOMAIN entries THEN entries[slot + 1] ELSE done

THEOREM FollowingSequentialEntryUsesTheRegisteredOrder ==
    ASSUME NEW entries, NEW count \in Nat, DOMAIN entries = 1..count,
           NEW slot \in DOMAIN entries, NEW done
    PROVE FollowingSequentialEntry(entries, slot, done) =
          IF slot < count THEN entries[slot + 1] ELSE done
    BY ONLY (count \in Nat), (DOMAIN entries = 1..count), (slot \in DOMAIN entries), SMT
        DEF FollowingSequentialEntry

NativeDispatchBindsTheActionCatalog(routes, formalLabels) ==
    /\ \A first, second \in DOMAIN routes : routes[first].handle = routes[second].handle => first = second
    /\ \A first, second \in DOMAIN formalLabels : formalLabels[first] = formalLabels[second] => first = second
    /\ \A candidate \in DOMAIN routes :
           LET visitor == routes[candidate].visitor
           IN /\ visitor \in DOMAIN formalLabels
              /\ routes[candidate].formal = formalLabels[visitor]
    /\ \A visitor \in DOMAIN formalLabels : \E candidate \in DOMAIN routes : routes[candidate].visitor = visitor

THEOREM CertifiedNativeDispatchUsesTheLabeledCatalog ==
    ASSUME NEW routes, NEW formalLabels, NativeDispatchBindsTheActionCatalog(routes, formalLabels),
           NEW authoredLabels, DOMAIN authoredLabels = DOMAIN formalLabels,
           NEW nativeBranches, NEW sourceBranches,
           \A action \in DOMAIN formalLabels : nativeBranches[action] <=> sourceBranches[action]
    PROVE \A label : NativeDispatchLabeled(routes, nativeBranches, formalLabels, authoredLabels, label)
                     <=> CatalogLabeledBranches(sourceBranches, authoredLabels, label)
PROOF
<1>. TAKE label
<1>forward.
    ASSUME NativeDispatchLabeled(routes, nativeBranches, formalLabels, authoredLabels, label)
    PROVE CatalogLabeledBranches(sourceBranches, authoredLabels, label)
    <2>candidate. PICK candidate \in DOMAIN routes :
        \E action \in DOMAIN formalLabels :
            /\ NativeDispatchOutcome(routes, nativeBranches, candidate).formal = formalLabels[action]
            /\ authoredLabels[action] = label
            /\ NativeDispatchOutcome(routes, nativeBranches, candidate).outcome
        BY ONLY NativeDispatchLabeled(routes, nativeBranches, formalLabels, authoredLabels, label)
            DEF NativeDispatchLabeled
    <2>row. PICK action \in DOMAIN formalLabels :
        /\ NativeDispatchOutcome(routes, nativeBranches, candidate).formal = formalLabels[action]
        /\ authoredLabels[action] = label
        /\ NativeDispatchOutcome(routes, nativeBranches, candidate).outcome
        BY ONLY <2>candidate
    <2>identity. routes[candidate].visitor = action
        BY ONLY <2>row, (candidate \in DOMAIN routes), (action \in DOMAIN formalLabels),
            NativeDispatchBindsTheActionCatalog(routes, formalLabels), SMT
            DEF NativeDispatchBindsTheActionCatalog, NativeDispatchOutcome
    <2>. QED BY ONLY <2>row, <2>identity, (action \in DOMAIN formalLabels),
        (DOMAIN authoredLabels = DOMAIN formalLabels),
        (\A action \in DOMAIN formalLabels : nativeBranches[action] <=> sourceBranches[action]), SMT
        DEF NativeDispatchOutcome, CatalogLabeledBranches
<1>backward.
    ASSUME CatalogLabeledBranches(sourceBranches, authoredLabels, label)
    PROVE NativeDispatchLabeled(routes, nativeBranches, formalLabels, authoredLabels, label)
    <2>action. PICK action \in DOMAIN formalLabels : authoredLabels[action] = label /\ sourceBranches[action]
        BY ONLY CatalogLabeledBranches(sourceBranches, authoredLabels, label),
            (DOMAIN authoredLabels = DOMAIN formalLabels), SMT DEF CatalogLabeledBranches
    <2>candidate. PICK candidate \in DOMAIN routes : routes[candidate].visitor = action
        BY ONLY (action \in DOMAIN formalLabels), NativeDispatchBindsTheActionCatalog(routes, formalLabels), SMT
            DEF NativeDispatchBindsTheActionCatalog
    <2>. QED BY ONLY <2>action, <2>candidate, (candidate \in DOMAIN routes), (action \in DOMAIN formalLabels),
        NativeDispatchBindsTheActionCatalog(routes, formalLabels),
        (\A action \in DOMAIN formalLabels : nativeBranches[action] <=> sourceBranches[action]), SMT
        DEF NativeDispatchBindsTheActionCatalog, NativeDispatchOutcome, NativeDispatchLabeled
<1>. QED BY ONLY <1>forward, <1>backward, SMT

=============================================================================
