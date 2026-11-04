---------------- MODULE FiniteSetMembershipRule ----------------
EXTENDS TLAPS, Integers, FiniteSetTheorems, IndexedHistoryRules

SourceMember(members, candidate) ==
    \E selected \in members : selected = candidate
CompiledMember(members, candidate) == candidate \in members
RenderedMember(members, candidate) == candidate \in members

SourceOutcome(members, candidate) ==
    [defined |-> TRUE, value |-> SourceMember(members, candidate),
     firstFailure |-> "none"]
RenderedOutcome(members, candidate) ==
    [defined |-> TRUE, value |-> RenderedMember(members, candidate),
     firstFailure |-> "none"]

THEOREM SourceMembershipEqualsCompiled ==
    ASSUME NEW members, NEW candidate
    PROVE SourceMember(members, candidate)
        = CompiledMember(members, candidate)
    BY SMT DEF SourceMember, CompiledMember

THEOREM CompiledMembershipEqualsRendered ==
    ASSUME NEW members, NEW candidate
    PROVE CompiledMember(members, candidate)
        = RenderedMember(members, candidate)
    BY SMT DEF CompiledMember, RenderedMember

THEOREM MembershipHasCompleteTotalOutcome ==
    ASSUME NEW members, NEW candidate
    PROVE SourceOutcome(members, candidate)
        = RenderedOutcome(members, candidate)
    PROOF
    <1>1. SourceMember(members, candidate)
        = RenderedMember(members, candidate)
        BY SourceMembershipEqualsCompiled, CompiledMembershipEqualsRendered
    <1> QED BY <1>1, SMT DEF SourceOutcome, RenderedOutcome

SourceGuard(enabled, members, candidate) ==
    enabled /\ SourceMember(members, candidate)
RenderedGuard(enabled, members, candidate) ==
    IF enabled THEN RenderedMember(members, candidate) ELSE FALSE

THEOREM MembershipComposesWithShortCircuitGuard ==
    ASSUME NEW enabled \in BOOLEAN, NEW members, NEW candidate
    PROVE SourceGuard(enabled, members, candidate)
        <=> RenderedGuard(enabled, members, candidate)
    BY MembershipHasCompleteTotalOutcome, SMT
        DEF SourceGuard, RenderedGuard, SourceMember, RenderedMember

\* Membership evaluates the set before the candidate. A failed set prevents
\* candidate evaluation; either failure prevents a labeled successor.
SourceFallibleGuard(setDefined, candidateDefined, members, candidate) ==
    setDefined /\ candidateDefined /\ SourceMember(members, candidate)
RenderedFallibleGuard(setDefined, candidateDefined, members, candidate) ==
    IF setDefined THEN
        IF candidateDefined THEN RenderedMember(members, candidate)
        ELSE FALSE
    ELSE FALSE
SourceFallibleFirstFailure(setDefined, candidateDefined) ==
    IF ~setDefined THEN "set"
    ELSE IF ~candidateDefined THEN "candidate" ELSE "none"
RenderedFallibleFirstFailure(setDefined, candidateDefined) ==
    IF ~setDefined THEN "set"
    ELSE IF setDefined /\ ~candidateDefined THEN "candidate" ELSE "none"
SourceFallibleEdges(setDefined, candidateDefined, members, candidate,
                    state, label, target) ==
    IF SourceFallibleGuard(setDefined, candidateDefined, members, candidate)
    THEN {<<state, label, target>>} ELSE {}
RenderedFallibleEdges(setDefined, candidateDefined, members, candidate,
                      state, label, target) ==
    IF RenderedFallibleGuard(setDefined, candidateDefined, members, candidate)
    THEN {<<state, label, target>>} ELSE {}
SourceFallibleOutcome(setDefined, candidateDefined, members, candidate,
                      state, label, target) ==
    [edges |-> SourceFallibleEdges(setDefined, candidateDefined, members,
                                  candidate, state, label, target),
     firstFailure |-> SourceFallibleFirstFailure(setDefined, candidateDefined)]
RenderedFallibleOutcome(setDefined, candidateDefined, members, candidate,
                        state, label, target) ==
    [edges |-> RenderedFallibleEdges(setDefined, candidateDefined, members,
                                    candidate, state, label, target),
     firstFailure |-> RenderedFallibleFirstFailure(setDefined, candidateDefined)]

THEOREM FallibleMembershipPreservesLabeledOutcome ==
    ASSUME NEW setDefined \in BOOLEAN,
           NEW candidateDefined \in BOOLEAN,
           NEW domain, NEW members, NEW candidate,
           setDefined => members \in SUBSET domain,
           candidateDefined => candidate \in domain,
           NEW state, NEW label, NEW target
    PROVE SourceFallibleOutcome(setDefined, candidateDefined, members,
              candidate, state, label, target)
          = RenderedFallibleOutcome(setDefined, candidateDefined, members,
              candidate, state, label, target)
    BY SMT DEF SourceFallibleOutcome, RenderedFallibleOutcome,
        SourceFallibleEdges, RenderedFallibleEdges,
        SourceFallibleGuard, RenderedFallibleGuard,
        SourceFallibleFirstFailure, RenderedFallibleFirstFailure,
        SourceMember, RenderedMember

WrongFirstFailure(setDefined, candidateDefined) ==
    IF ~candidateDefined THEN "candidate"
    ELSE IF ~setDefined THEN "set" ELSE "none"

THEOREM ReversingFallibleOperandsIsRejected ==
    SourceFallibleFirstFailure(FALSE, FALSE)
        # WrongFirstFailure(FALSE, FALSE)
    BY SMT DEF SourceFallibleFirstFailure, WrongFirstFailure

WrongMember(members, candidate) == candidate \in {2}

THEOREM ChangedMemberHasCounterexample ==
    SourceMember({1}, 1) /\ ~WrongMember({1}, 1)
    BY SMT DEF SourceMember, WrongMember

\* These rules preserve full child payloads; query values do not enumerate sets.
QueryValue(value) == [defined |-> TRUE, value |-> value, firstFailure |-> "none"]
QueryFailure(payload) == [defined |-> FALSE, value |-> FALSE, firstFailure |-> payload]
IntOperandOutcomes(failures) ==
    [defined: {TRUE}, value: Int, firstFailure: {"none"}] \cup
    [defined: {FALSE}, value: {0}, firstFailure: failures]
SourceDomainOutcomes(failures) ==
    [defined: {TRUE}, value: SUBSET Int, firstFailure: {"none"}] \cup
    [defined: {FALSE}, value: {FALSE}, firstFailure: failures]
NativeDomainOutcomes(failures) ==
    [defined: {TRUE}, value: [Int -> BOOLEAN], firstFailure: {"none"}] \cup
    [defined: {FALSE}, value: {FALSE}, firstFailure: failures]
QueryResultOutcomes(failures) ==
    [defined: {TRUE}, value: BOOLEAN, firstFailure: {"none"}] \cup
    [defined: {FALSE}, value: {FALSE}, firstFailure: failures]

DomainOutcomesAgree(source, native) ==
    /\ source.defined = native.defined
    /\ IF source.defined
       THEN \A member \in Int : SourceMember(source.value, member) = native.value[member]
       ELSE source.firstFailure = native.firstFailure
OperandOutcomesAgree(source, native) ==
    /\ source.defined = native.defined
    /\ IF source.defined THEN source.value = native.value
       ELSE source.firstFailure = native.firstFailure

SourceIntegerDomain == QueryValue(Int)
NativeIntegerDomain == QueryValue([member \in Int |-> TRUE])

THEOREM IntegerDomainPreservesEveryMemberAndHasNoFailure ==
    ASSUME NEW failures
    PROVE /\ SourceIntegerDomain \in SourceDomainOutcomes(failures)
          /\ NativeIntegerDomain \in NativeDomainOutcomes(failures)
          /\ DomainOutcomesAgree(SourceIntegerDomain, NativeIntegerDomain)
          /\ SourceIntegerDomain.defined /\ NativeIntegerDomain.defined
    BY SMT DEF SourceIntegerDomain, NativeIntegerDomain, QueryValue,
        SourceDomainOutcomes, NativeDomainOutcomes, DomainOutcomesAgree, SourceMember

SourceRangeDomain(lower, upper) ==
    IF ~lower.defined THEN QueryFailure(lower.firstFailure)
    ELSE IF ~upper.defined THEN QueryFailure(upper.firstFailure)
    ELSE QueryValue({member \in Int : lower.value <= member /\ member <= upper.value})
NativeRangeDomain(lower, upper) ==
    IF lower.defined /\ upper.defined
    THEN QueryValue([member \in Int |-> lower.value <= member /\ member <= upper.value])
    ELSE QueryFailure(IF ~lower.defined THEN lower.firstFailure ELSE upper.firstFailure)

THEOREM RangeDomainsPreserveAllMembersAndSelectedPayload ==
    ASSUME NEW failures, NEW sourceLower \in IntOperandOutcomes(failures),
           NEW sourceUpper \in IntOperandOutcomes(failures),
           NEW nativeLower \in IntOperandOutcomes(failures),
           NEW nativeUpper \in IntOperandOutcomes(failures),
           OperandOutcomesAgree(sourceLower, nativeLower),
           OperandOutcomesAgree(sourceUpper, nativeUpper)
    PROVE /\ SourceRangeDomain(sourceLower, sourceUpper) \in SourceDomainOutcomes(failures)
          /\ NativeRangeDomain(nativeLower, nativeUpper) \in NativeDomainOutcomes(failures)
          /\ DomainOutcomesAgree(SourceRangeDomain(sourceLower, sourceUpper),
                                  NativeRangeDomain(nativeLower, nativeUpper))
    BY SMT DEF SourceRangeDomain, NativeRangeDomain, DomainOutcomesAgree,
        OperandOutcomesAgree, SourceMember, QueryValue, QueryFailure,
        IntOperandOutcomes, SourceDomainOutcomes, NativeDomainOutcomes

SourceUnionDomain(left, right) ==
    IF left.defined /\ right.defined THEN QueryValue(left.value \cup right.value)
    ELSE QueryFailure(IF ~left.defined THEN left.firstFailure ELSE right.firstFailure)
NativeUnionDomain(left, right) ==
    IF ~left.defined THEN QueryFailure(left.firstFailure)
    ELSE IF ~right.defined THEN QueryFailure(right.firstFailure)
    ELSE QueryValue([member \in Int |-> left.value[member] \/ right.value[member]])

THEOREM EagerUnionDomainsComposeAllMembersAndSelectedPayload ==
    ASSUME NEW failures,
           NEW sourceLeft \in SourceDomainOutcomes(failures),
           NEW sourceRight \in SourceDomainOutcomes(failures),
           NEW nativeLeft \in NativeDomainOutcomes(failures),
           NEW nativeRight \in NativeDomainOutcomes(failures),
           DomainOutcomesAgree(sourceLeft, nativeLeft),
           DomainOutcomesAgree(sourceRight, nativeRight)
    PROVE /\ SourceUnionDomain(sourceLeft, sourceRight) \in SourceDomainOutcomes(failures)
          /\ NativeUnionDomain(nativeLeft, nativeRight) \in NativeDomainOutcomes(failures)
          /\ DomainOutcomesAgree(SourceUnionDomain(sourceLeft, sourceRight),
                                  NativeUnionDomain(nativeLeft, nativeRight))
    BY SMT DEF SourceUnionDomain, NativeUnionDomain, DomainOutcomesAgree,
        SourceMember, SourceDomainOutcomes, NativeDomainOutcomes, QueryValue, QueryFailure

SourceDomainQuery(domain, candidate) ==
    IF domain.defined /\ candidate.defined
    THEN QueryValue(SourceMember(domain.value, candidate.value))
    ELSE QueryFailure(IF ~domain.defined THEN domain.firstFailure ELSE candidate.firstFailure)
NativeDomainQuery(domain, candidate) ==
    IF ~domain.defined THEN QueryFailure(domain.firstFailure)
    ELSE IF ~candidate.defined THEN QueryFailure(candidate.firstFailure)
    ELSE QueryValue(domain.value[candidate.value])

THEOREM EmptyIntegerPredicateChangesTheQueryOutcome ==
    SourceDomainQuery(SourceIntegerDomain, QueryValue(0))
        # NativeDomainQuery(QueryValue([member \in Int |-> FALSE]), QueryValue(0))
    BY SMT DEF SourceDomainQuery, NativeDomainQuery, SourceIntegerDomain,
        QueryValue, SourceMember

THEOREM DomainMembershipComposesCompleteValueAndFailurePayload ==
    ASSUME NEW failures, NEW sourceDomain \in SourceDomainOutcomes(failures),
           NEW nativeDomain \in NativeDomainOutcomes(failures),
           NEW sourceCandidate \in IntOperandOutcomes(failures),
           NEW nativeCandidate \in IntOperandOutcomes(failures),
           DomainOutcomesAgree(sourceDomain, nativeDomain),
           OperandOutcomesAgree(sourceCandidate, nativeCandidate)
    PROVE /\ SourceDomainQuery(sourceDomain, sourceCandidate) \in QueryResultOutcomes(failures)
          /\ NativeDomainQuery(nativeDomain, nativeCandidate) \in QueryResultOutcomes(failures)
          /\ SourceDomainQuery(sourceDomain, sourceCandidate)
                = NativeDomainQuery(nativeDomain, nativeCandidate)
    BY SMT DEF SourceDomainQuery, NativeDomainQuery, DomainOutcomesAgree,
        OperandOutcomesAgree, SourceDomainOutcomes, NativeDomainOutcomes,
        IntOperandOutcomes, QueryResultOutcomes, QueryValue, QueryFailure, SourceMember

THEOREM RangeQueriesComposeCompleteValueAndFailurePayload ==
    ASSUME NEW failures,
           NEW sourceLower \in IntOperandOutcomes(failures),
           NEW sourceUpper \in IntOperandOutcomes(failures),
           NEW sourceCandidate \in IntOperandOutcomes(failures),
           NEW nativeLower \in IntOperandOutcomes(failures),
           NEW nativeUpper \in IntOperandOutcomes(failures),
           NEW nativeCandidate \in IntOperandOutcomes(failures),
           OperandOutcomesAgree(sourceLower, nativeLower),
           OperandOutcomesAgree(sourceUpper, nativeUpper),
           OperandOutcomesAgree(sourceCandidate, nativeCandidate)
    PROVE /\ SourceDomainQuery(SourceRangeDomain(sourceLower, sourceUpper), sourceCandidate)
                \in QueryResultOutcomes(failures)
          /\ NativeDomainQuery(NativeRangeDomain(nativeLower, nativeUpper), nativeCandidate)
                \in QueryResultOutcomes(failures)
          /\ SourceDomainQuery(SourceRangeDomain(sourceLower, sourceUpper), sourceCandidate)
                = NativeDomainQuery(NativeRangeDomain(nativeLower, nativeUpper), nativeCandidate)
    PROOF
    <1>1. /\ SourceRangeDomain(sourceLower, sourceUpper) \in SourceDomainOutcomes(failures)
          /\ NativeRangeDomain(nativeLower, nativeUpper) \in NativeDomainOutcomes(failures)
          /\ DomainOutcomesAgree(SourceRangeDomain(sourceLower, sourceUpper),
                                  NativeRangeDomain(nativeLower, nativeUpper))
        BY RangeDomainsPreserveAllMembersAndSelectedPayload
    <1>. QED BY <1>1, DomainMembershipComposesCompleteValueAndFailurePayload

THEOREM IgnoringAnEagerUnionDomainFailureChangesItsOutcome ==
    ASSUME NEW failures, NEW failed \in SourceDomainOutcomes(failures), ~failed.defined
    PROVE SourceDomainQuery(SourceUnionDomain(
                  SourceRangeDomain(QueryValue(0), QueryValue(1)), failed), QueryValue(0))
              # QueryValue(TRUE)
    BY SMT DEF SourceDomainQuery, SourceUnionDomain, SourceRangeDomain, QueryValue, QueryFailure

THEOREM MovingCandidateBeforeDomainChangesTheSelectedPayload ==
    ASSUME NEW domainFailure, NEW candidateFailure, domainFailure # candidateFailure
    PROVE SourceDomainQuery(QueryFailure(domainFailure), QueryFailure(candidateFailure))
              # QueryFailure(candidateFailure)
    BY SMT DEF SourceDomainQuery, QueryFailure

THEOREM RangeDomainConstructorsHaveTypedOutcomes ==
    ASSUME NEW failures,
           NEW sourceLower \in IntOperandOutcomes(failures),
           NEW sourceUpper \in IntOperandOutcomes(failures),
           NEW nativeLower \in IntOperandOutcomes(failures),
           NEW nativeUpper \in IntOperandOutcomes(failures)
    PROVE /\ SourceRangeDomain(sourceLower, sourceUpper) \in SourceDomainOutcomes(failures)
          /\ NativeRangeDomain(nativeLower, nativeUpper) \in NativeDomainOutcomes(failures)
    BY SMT DEF SourceRangeDomain, NativeRangeDomain, QueryValue, QueryFailure,
        IntOperandOutcomes, SourceDomainOutcomes, NativeDomainOutcomes

THEOREM UnionDomainConstructorsHaveTypedOutcomes ==
    ASSUME NEW failures,
           NEW sourceLeft \in SourceDomainOutcomes(failures),
           NEW sourceRight \in SourceDomainOutcomes(failures),
           NEW nativeLeft \in NativeDomainOutcomes(failures),
           NEW nativeRight \in NativeDomainOutcomes(failures)
    PROVE /\ SourceUnionDomain(sourceLeft, sourceRight) \in SourceDomainOutcomes(failures)
          /\ NativeUnionDomain(nativeLeft, nativeRight) \in NativeDomainOutcomes(failures)
    BY SMT DEF SourceUnionDomain, NativeUnionDomain, SourceDomainOutcomes,
        NativeDomainOutcomes, QueryValue, QueryFailure

DomainNodes(failures) ==
    [kind: {"leaf", "range", "union", "integerSet"}, left: Nat, right: Nat,
     sourceLeaf: SourceDomainOutcomes(failures), nativeLeaf: NativeDomainOutcomes(failures),
     sourceLower: IntOperandOutcomes(failures), sourceUpper: IntOperandOutcomes(failures),
     nativeLower: IntOperandOutcomes(failures), nativeUpper: IntOperandOutcomes(failures)]
ValidDomainPostorder(nodes, count) ==
    \A index \in 1..count : nodes[index].kind = "union" =>
        /\ nodes[index].left \in 1..(index - 1)
        /\ nodes[index].right \in 1..(index - 1)
DomainLeafAgreement(nodes, count) ==
    \A index \in 1..count :
        /\ (nodes[index].kind = "leaf" =>
                DomainOutcomesAgree(nodes[index].sourceLeaf, nodes[index].nativeLeaf))
        /\ (nodes[index].kind = "range" =>
                /\ OperandOutcomesAgree(nodes[index].sourceLower, nodes[index].nativeLower)
                /\ OperandOutcomesAgree(nodes[index].sourceUpper, nodes[index].nativeUpper))

SourceDomainNode(nodes, history, index) ==
    IF nodes[index].kind = "leaf" THEN nodes[index].sourceLeaf
    ELSE IF nodes[index].kind = "integerSet" THEN SourceIntegerDomain
    ELSE IF nodes[index].kind = "range"
         THEN SourceRangeDomain(nodes[index].sourceLower, nodes[index].sourceUpper)
         ELSE SourceUnionDomain(history[nodes[index].left], history[nodes[index].right])
NativeDomainNode(nodes, history, index) ==
    IF nodes[index].kind = "leaf" THEN nodes[index].nativeLeaf
    ELSE IF nodes[index].kind = "integerSet" THEN NativeIntegerDomain
    ELSE IF nodes[index].kind = "range"
         THEN NativeRangeDomain(nodes[index].nativeLower, nodes[index].nativeUpper)
         ELSE NativeUnionDomain(history[nodes[index].left], history[nodes[index].right])
SourceDomainSteps(failures, nodes, count) ==
    [index \in 1..count |-> [prefix \in [1..(index - 1) -> SourceDomainOutcomes(failures)] |->
        SourceDomainNode(nodes, prefix, index)]]
NativeDomainSteps(failures, nodes, count) ==
    [index \in 1..count |-> [prefix \in [1..(index - 1) -> NativeDomainOutcomes(failures)] |->
        NativeDomainNode(nodes, prefix, index)]]

THEOREM DomainNodeOutcomesAreClosed ==
    ASSUME NEW failures, NEW count \in Nat, NEW nodes \in [1..count -> DomainNodes(failures)],
           ValidDomainPostorder(nodes, count),
           NEW index \in 1..count,
           NEW source \in [1..(index - 1) -> SourceDomainOutcomes(failures)],
           NEW native \in [1..(index - 1) -> NativeDomainOutcomes(failures)]
    PROVE /\ SourceDomainNode(nodes, source, index) \in SourceDomainOutcomes(failures)
          /\ NativeDomainNode(nodes, native, index) \in NativeDomainOutcomes(failures)
    PROOF
    <1>1. nodes[index] \in DomainNodes(failures) BY SMT
    <1>2. CASE nodes[index].kind = "leaf"
        BY <1>1, <1>2, SMT DEF DomainNodes, SourceDomainNode, NativeDomainNode
    <1>3. CASE nodes[index].kind = "range"
        BY <1>1, <1>3, RangeDomainConstructorsHaveTypedOutcomes, SMT
            DEF DomainNodes, SourceDomainNode, NativeDomainNode
    <1>4. CASE nodes[index].kind = "union"
        <2>1. /\ source[nodes[index].left] \in SourceDomainOutcomes(failures)
              /\ source[nodes[index].right] \in SourceDomainOutcomes(failures)
              /\ native[nodes[index].left] \in NativeDomainOutcomes(failures)
              /\ native[nodes[index].right] \in NativeDomainOutcomes(failures)
            BY <1>4, SMT DEF ValidDomainPostorder
        <2>2. /\ SourceUnionDomain(source[nodes[index].left], source[nodes[index].right])
                    \in SourceDomainOutcomes(failures)
              /\ NativeUnionDomain(native[nodes[index].left], native[nodes[index].right])
                    \in NativeDomainOutcomes(failures)
            BY <2>1, UnionDomainConstructorsHaveTypedOutcomes, SMT
        <2>. QED BY <1>1, <1>4, <2>2, SMT
            DEF SourceDomainNode, NativeDomainNode
    <1>5. CASE nodes[index].kind = "integerSet"
        BY <1>5, IntegerDomainPreservesEveryMemberAndHasNoFailure, SMT
            DEF SourceDomainNode, NativeDomainNode
    <1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, SMT DEF DomainNodes

THEOREM EveryFiniteDomainTreeHasIndependentHistories ==
    ASSUME NEW failures, NEW count \in Nat, NEW nodes \in [1..count -> DomainNodes(failures)],
           ValidDomainPostorder(nodes, count)
    PROVE /\ \E source \in [1..count -> SourceDomainOutcomes(failures)] :
                  IndexedHistory(SourceDomainSteps(failures, nodes, count), source, count)
          /\ \E native \in [1..count -> NativeDomainOutcomes(failures)] :
                  IndexedHistory(NativeDomainSteps(failures, nodes, count), native, count)
    PROOF
    <1>. DEFINE sourceStep == [index \in 1..count |->
                    [prefix \in [1..(index - 1) -> SourceDomainOutcomes(failures)] |->
                        SourceDomainNode(nodes, prefix, index)]]
                nativeStep == [index \in 1..count |->
                    [prefix \in [1..(index - 1) -> NativeDomainOutcomes(failures)] |->
                        NativeDomainNode(nodes, prefix, index)]]
    <1>1. \A index \in 1..count : sourceStep[index] \in
              [[1..(index - 1) -> SourceDomainOutcomes(failures)] -> SourceDomainOutcomes(failures)]
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                            NEW prefix \in [1..(index - 1) -> SourceDomainOutcomes(failures)]
                     PROVE SourceDomainNode(nodes, prefix, index) \in SourceDomainOutcomes(failures)
            BY SMT DEF sourceStep
        <2>. DEFINE other == [child \in 1..(index - 1) |-> nodes[index].nativeLeaf]
        <2>1. other \in [1..(index - 1) -> NativeDomainOutcomes(failures)]
            BY SMT DEF other, DomainNodes
        <2>. QED BY <2>1, DomainNodeOutcomesAreClosed
    <1>2. \A index \in 1..count : nativeStep[index] \in
              [[1..(index - 1) -> NativeDomainOutcomes(failures)] -> NativeDomainOutcomes(failures)]
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                            NEW prefix \in [1..(index - 1) -> NativeDomainOutcomes(failures)]
                     PROVE NativeDomainNode(nodes, prefix, index) \in NativeDomainOutcomes(failures)
            BY SMT DEF nativeStep
        <2>. DEFINE other == [child \in 1..(index - 1) |-> nodes[index].sourceLeaf]
        <2>1. other \in [1..(index - 1) -> SourceDomainOutcomes(failures)]
            BY SMT DEF other, DomainNodes
        <2>. QED BY <2>1, DomainNodeOutcomesAreClosed
    <1>3. PICK source \in [1..count -> SourceDomainOutcomes(failures)] :
              IndexedHistory(sourceStep, source, count)
        BY <1>1, FiniteIndexedHistoryExists
    <1>4. PICK native \in [1..count -> NativeDomainOutcomes(failures)] :
              IndexedHistory(nativeStep, native, count)
        BY <1>2, FiniteIndexedHistoryExists
    <1>5. /\ sourceStep = SourceDomainSteps(failures, nodes, count)
          /\ nativeStep = NativeDomainSteps(failures, nodes, count)
        BY SMT DEF sourceStep, nativeStep, SourceDomainSteps, NativeDomainSteps
    <1>. QED BY <1>3, <1>4, <1>5, SMT

THEOREM DomainNodeRulesPreserveRepresentation ==
    ASSUME NEW failures, NEW count \in Nat, NEW nodes \in [1..count -> DomainNodes(failures)],
           ValidDomainPostorder(nodes, count), DomainLeafAgreement(nodes, count),
           NEW index \in 1..count,
           NEW source \in [1..(index - 1) -> SourceDomainOutcomes(failures)],
           NEW native \in [1..(index - 1) -> NativeDomainOutcomes(failures)],
           \A child \in 1..(index - 1) : DomainOutcomesAgree(source[child], native[child])
    PROVE DomainOutcomesAgree(SourceDomainNode(nodes, source, index),
                              NativeDomainNode(nodes, native, index))
    PROOF
    <1>1. nodes[index] \in DomainNodes(failures) BY SMT
    <1>2. CASE nodes[index].kind = "leaf"
        BY <1>2, SMT DEF DomainLeafAgreement, SourceDomainNode, NativeDomainNode
    <1>3. CASE nodes[index].kind = "range"
        BY <1>1, <1>3, RangeDomainsPreserveAllMembersAndSelectedPayload, SMT
            DEF DomainNodes, DomainLeafAgreement, SourceDomainNode, NativeDomainNode
    <1>4. CASE nodes[index].kind = "union"
        <2>1. /\ nodes[index].left \in 1..(index - 1)
              /\ nodes[index].right \in 1..(index - 1)
            BY <1>4, SMT DEF ValidDomainPostorder
        <2>2. /\ DomainOutcomesAgree(source[nodes[index].left], native[nodes[index].left])
              /\ DomainOutcomesAgree(source[nodes[index].right], native[nodes[index].right])
            BY <2>1, SMT
        <2>. QED BY <1>4, <2>1, <2>2, EagerUnionDomainsComposeAllMembersAndSelectedPayload, SMT
            DEF SourceDomainNode, NativeDomainNode
    <1>5. CASE nodes[index].kind = "integerSet"
        BY <1>5, IntegerDomainPreservesEveryMemberAndHasNoFailure, SMT
            DEF SourceDomainNode, NativeDomainNode
    <1>. QED BY <1>1, <1>2, <1>3, <1>4, <1>5, SMT DEF DomainNodes

THEOREM FiniteDomainHistoriesPreserveRepresentation ==
    ASSUME NEW failures, NEW count \in Nat, NEW nodes \in [1..count -> DomainNodes(failures)],
           ValidDomainPostorder(nodes, count), DomainLeafAgreement(nodes, count),
           NEW source \in [1..count -> SourceDomainOutcomes(failures)],
           NEW native \in [1..count -> NativeDomainOutcomes(failures)],
           IndexedHistory(SourceDomainSteps(failures, nodes, count), source, count),
           IndexedHistory(NativeDomainSteps(failures, nodes, count), native, count)
    PROVE \A index \in 1..count : DomainOutcomesAgree(source[index], native[index])
    PROOF
    <1>. DEFINE P(index) == IF index = 0 THEN TRUE ELSE DomainOutcomesAgree(source[index], native[index])
    <1>1. P(0) BY SMT DEF P
    <1>2. ASSUME NEW index \in 1..count,
                \A child \in 0..(index - 1) : P(child)
          PROVE P(index)
        <2>1. \A child \in 1..(index - 1) : DomainOutcomesAgree(source[child], native[child])
            BY (\A child \in 0..(index - 1) : P(child)), SMT DEF P
        <2>2. /\ HistoryPrefix(source, index - 1) \in [1..(index - 1) -> SourceDomainOutcomes(failures)]
              /\ HistoryPrefix(native, index - 1) \in [1..(index - 1) -> NativeDomainOutcomes(failures)]
            BY SMT DEF HistoryPrefix
        <2>3. DomainOutcomesAgree(
                  SourceDomainNode(nodes, HistoryPrefix(source, index - 1), index),
                  NativeDomainNode(nodes, HistoryPrefix(native, index - 1), index))
            BY <2>1, <2>2, DomainNodeRulesPreserveRepresentation, SMT DEF HistoryPrefix
        <2>4. /\ source[index] = SourceDomainNode(nodes, HistoryPrefix(source, index - 1), index)
              /\ native[index] = NativeDomainNode(nodes, HistoryPrefix(native, index - 1), index)
            BY <2>2, SMT DEF IndexedHistory, SourceDomainSteps, NativeDomainSteps
        <2>. QED BY <2>3, <2>4, SMT DEF P
    <1>3. HIDE DEF P
    <1>4. \A index \in 0..count : P(index)
        BY <1>1, <1>2, FiniteIndexedPrefixProperty
    <1>. QED BY <1>4, SMT DEF P

THEOREM EveryFiniteDomainTreePreservesItsRootQuery ==
    ASSUME NEW failures, NEW count \in Nat \ {0}, NEW nodes \in [1..count -> DomainNodes(failures)],
           ValidDomainPostorder(nodes, count), DomainLeafAgreement(nodes, count)
    PROVE \E source \in [1..count -> SourceDomainOutcomes(failures)],
              native \in [1..count -> NativeDomainOutcomes(failures)] :
              /\ IndexedHistory(SourceDomainSteps(failures, nodes, count), source, count)
              /\ IndexedHistory(NativeDomainSteps(failures, nodes, count), native, count)
              /\ \A sourceCandidate, nativeCandidate \in IntOperandOutcomes(failures) :
                     OperandOutcomesAgree(sourceCandidate, nativeCandidate) =>
                         /\ SourceDomainQuery(source[count], sourceCandidate) \in QueryResultOutcomes(failures)
                         /\ NativeDomainQuery(native[count], nativeCandidate) \in QueryResultOutcomes(failures)
                         /\ SourceDomainQuery(source[count], sourceCandidate)
                                = NativeDomainQuery(native[count], nativeCandidate)
    PROOF
    <1>1. PICK source \in [1..count -> SourceDomainOutcomes(failures)] :
              IndexedHistory(SourceDomainSteps(failures, nodes, count), source, count)
        BY EveryFiniteDomainTreeHasIndependentHistories
    <1>2. PICK native \in [1..count -> NativeDomainOutcomes(failures)] :
              IndexedHistory(NativeDomainSteps(failures, nodes, count), native, count)
        BY EveryFiniteDomainTreeHasIndependentHistories
    <1>3. DomainOutcomesAgree(source[count], native[count])
        BY <1>1, <1>2, FiniteDomainHistoriesPreserveRepresentation, SMT
    <1>4. \A sourceCandidate, nativeCandidate \in IntOperandOutcomes(failures) :
              OperandOutcomesAgree(sourceCandidate, nativeCandidate) =>
                  /\ SourceDomainQuery(source[count], sourceCandidate) \in QueryResultOutcomes(failures)
                  /\ NativeDomainQuery(native[count], nativeCandidate) \in QueryResultOutcomes(failures)
                  /\ SourceDomainQuery(source[count], sourceCandidate)
                        = NativeDomainQuery(native[count], nativeCandidate)
        BY <1>3, DomainMembershipComposesCompleteValueAndFailurePayload, SMT
    <1>. QED BY <1>1, <1>2, <1>4, SMT


\* Equality is a query, not an enumeration of the interval.
SourceDomainRangeEquality(members, lower, upper) == members = lower..upper
GeneratedDomainRangeEquality(members, lower, upper) ==
    IF members = {} THEN lower > upper
    ELSE /\ lower + (Cardinality(members) - 1) = upper
         /\ \A member \in members : lower <= member /\ member <= upper

THEOREM DomainRangeEqualityPreservesEveryFiniteIntegerDomain ==
    ASSUME NEW members \in SUBSET Int, IsFiniteSet(members),
           NEW lower \in Int, NEW upper \in Int
    PROVE SourceDomainRangeEquality(members, lower, upper)
        = GeneratedDomainRangeEquality(members, lower, upper)
    PROOF
    <1>1. /\ IsFiniteSet(lower..upper)
          /\ Cardinality(lower..upper) = IF lower > upper THEN 0 ELSE upper - lower + 1
        BY FS_Interval
    <1>2. Cardinality(members) \in Nat BY FS_CardinalityType
    <1>3. Cardinality(members) = 0 <=> members = {}
        BY FS_EmptySet
    <1>4. CASE lower > upper
        <2>1. lower..upper = {} BY <1>1, <1>4, FS_EmptySet, SMT
        <2>. QED BY <1>2, <1>3, <1>4, <2>1, SMT
            DEF SourceDomainRangeEquality, GeneratedDomainRangeEquality
    <1>5. CASE lower <= upper
        <2>1. ASSUME members = lower..upper
              PROVE GeneratedDomainRangeEquality(members, lower, upper)
            BY <2>1, <1>1, <1>2, <1>3, <1>5, SMT DEF GeneratedDomainRangeEquality
        <2>2. ASSUME GeneratedDomainRangeEquality(members, lower, upper)
              PROVE members = lower..upper
            <3>1. /\ members \in SUBSET (lower..upper)
                  /\ Cardinality(members) = Cardinality(lower..upper)
                BY <2>2, <1>1, <1>2, <1>3, <1>5, SMT DEF GeneratedDomainRangeEquality
            <3>. QED BY <1>1, <3>1, FS_Subset, SMT
        <2>. QED BY <2>1, <2>2, SMT DEF SourceDomainRangeEquality, GeneratedDomainRangeEquality
    <1>. QED BY <1>4, <1>5, SMT

GeneratedBoundedDomainRangeEquality(members, lower, upper, minimum, maximum) ==
    IF members = {} THEN lower > upper
    ELSE /\ GeneratedDomainRangeEquality(members, lower, upper)
         /\ lower + (Cardinality(members) - 1) \in minimum..maximum

THEOREM InternalEndpointOverflowCannotChangeEquality ==
    ASSUME NEW members \in SUBSET Int, IsFiniteSet(members),
           NEW minimum \in Int, NEW maximum \in Int, minimum <= maximum,
           NEW lower \in Int, NEW upper \in minimum..maximum
    PROVE GeneratedBoundedDomainRangeEquality(members, lower, upper, minimum, maximum)
        = SourceDomainRangeEquality(members, lower, upper)
    PROOF
    <1>1. GeneratedDomainRangeEquality(members, lower, upper)
            = SourceDomainRangeEquality(members, lower, upper)
        BY DomainRangeEqualityPreservesEveryFiniteIntegerDomain, SMT
    <1>. QED BY <1>1, SMT
        DEF GeneratedBoundedDomainRangeEquality, GeneratedDomainRangeEquality

FiniteDomainOperands(failures) ==
    {outcome \in SourceDomainOutcomes(failures) :
        outcome.defined => IsFiniteSet(outcome.value)}

SourceDomainRangeEqualityOutcome(domain, lower, upper, domainFirst) ==
    IF domainFirst /\ ~domain.defined THEN QueryFailure(domain.firstFailure)
    ELSE IF ~lower.defined THEN QueryFailure(lower.firstFailure)
    ELSE IF ~upper.defined THEN QueryFailure(upper.firstFailure)
    ELSE IF ~domain.defined THEN QueryFailure(domain.firstFailure)
    ELSE QueryValue(SourceDomainRangeEquality(domain.value, lower.value, upper.value))
GeneratedDomainRangeEqualityOutcome(domain, lower, upper, domainFirst, minimum, maximum) ==
    IF domain.defined /\ lower.defined /\ upper.defined
    THEN QueryValue(GeneratedBoundedDomainRangeEquality(
        domain.value, lower.value, upper.value, minimum, maximum))
    ELSE QueryFailure(IF domainFirst /\ ~domain.defined THEN domain.firstFailure
                      ELSE IF ~lower.defined THEN lower.firstFailure
                      ELSE IF ~upper.defined THEN upper.firstFailure
                      ELSE domain.firstFailure)

THEOREM DomainRangeEqualityComposesValuesAndOrderedFailures ==
    ASSUME NEW failures, NEW sourceDomain \in FiniteDomainOperands(failures),
           NEW nativeDomain \in FiniteDomainOperands(failures),
           NEW sourceLower \in IntOperandOutcomes(failures), NEW sourceUpper \in IntOperandOutcomes(failures),
           NEW nativeLower \in IntOperandOutcomes(failures), NEW nativeUpper \in IntOperandOutcomes(failures),
           OperandOutcomesAgree(sourceDomain, nativeDomain),
           OperandOutcomesAgree(sourceLower, nativeLower), OperandOutcomesAgree(sourceUpper, nativeUpper),
           NEW domainFirst \in BOOLEAN, NEW minimum \in Int, NEW maximum \in Int, minimum <= maximum,
           nativeLower.defined => nativeLower.value \in minimum..maximum,
           nativeUpper.defined => nativeUpper.value \in minimum..maximum
    PROVE /\ SourceDomainRangeEqualityOutcome(sourceDomain, sourceLower, sourceUpper, domainFirst)
                \in QueryResultOutcomes(failures)
          /\ GeneratedDomainRangeEqualityOutcome(nativeDomain, nativeLower, nativeUpper,
                    domainFirst, minimum, maximum) \in QueryResultOutcomes(failures)
          /\ SourceDomainRangeEqualityOutcome(sourceDomain, sourceLower, sourceUpper, domainFirst)
                = GeneratedDomainRangeEqualityOutcome(nativeDomain, nativeLower, nativeUpper,
                    domainFirst, minimum, maximum)
    PROOF
    <1>1. CASE sourceDomain.defined /\ sourceLower.defined /\ sourceUpper.defined
        <2>1. /\ nativeDomain.defined /\ nativeLower.defined /\ nativeUpper.defined
              /\ nativeDomain.value \in SUBSET Int /\ IsFiniteSet(nativeDomain.value)
              /\ sourceDomain.value = nativeDomain.value
              /\ sourceLower.value = nativeLower.value /\ sourceUpper.value = nativeUpper.value
              /\ nativeLower.value \in Int /\ nativeUpper.value \in minimum..maximum
            BY <1>1, SMT DEF OperandOutcomesAgree, FiniteDomainOperands,
                SourceDomainOutcomes, IntOperandOutcomes
        <2>2. GeneratedBoundedDomainRangeEquality(nativeDomain.value, nativeLower.value,
                        nativeUpper.value, minimum, maximum)
                = SourceDomainRangeEquality(sourceDomain.value, sourceLower.value, sourceUpper.value)
            BY <2>1, InternalEndpointOverflowCannotChangeEquality, SMT
        <2>. QED BY <1>1, <2>1, <2>2, SMT
            DEF SourceDomainRangeEqualityOutcome, GeneratedDomainRangeEqualityOutcome,
                QueryValue, QueryResultOutcomes, SourceDomainRangeEquality
    <1>2. CASE ~(sourceDomain.defined /\ sourceLower.defined /\ sourceUpper.defined)
        BY <1>2, SMT DEF SourceDomainRangeEqualityOutcome, GeneratedDomainRangeEqualityOutcome,
            OperandOutcomesAgree, FiniteDomainOperands, SourceDomainOutcomes,
            IntOperandOutcomes, QueryFailure, QueryResultOutcomes
    <1>. QED BY <1>1, <1>2, SMT

THEOREM EnumerationCapabilityIsNotASemanticEqualityFailure ==
    ASSUME NEW payload, NEW lower \in Int, NEW upper \in Int, NEW domainFirst \in BOOLEAN
    PROVE SourceDomainRangeEqualityOutcome(QueryValue({}), QueryValue(lower), QueryValue(upper), domainFirst)
        # QueryFailure(payload)
    BY SMT DEF SourceDomainRangeEqualityOutcome, QueryValue, QueryFailure

THEOREM RemovingKeyCoverageCanChangeEquality ==
    ASSUME NEW members \in SUBSET Int, IsFiniteSet(members), members # {},
           NEW lower \in Int, NEW upper \in Int, lower <= upper,
           lower + (Cardinality(members) - 1) = upper,
           \E member \in members : member < lower \/ upper < member
    PROVE /\ ~SourceDomainRangeEquality(members, lower, upper)
          /\ ~GeneratedDomainRangeEquality(members, lower, upper)
    BY SMT DEF SourceDomainRangeEquality, GeneratedDomainRangeEquality

THEOREM RemovingEndpointCountCanChangeEquality ==
    ASSUME NEW members \in SUBSET Int, IsFiniteSet(members), members # {},
           NEW lower \in Int, NEW upper \in Int, lower <= upper,
           \A member \in members : lower <= member /\ member <= upper,
           NEW omitted \in lower..upper, omitted \notin members
    PROVE /\ ~SourceDomainRangeEquality(members, lower, upper)
          /\ (\A member \in members : lower <= member /\ member <= upper)
    BY SMT DEF SourceDomainRangeEquality

THEOREM SwappingEqualityOperandsChangesTheSelectedFailure ==
    ASSUME NEW domainFailure, NEW boundFailure, domainFailure # boundFailure
    PROVE SourceDomainRangeEqualityOutcome(QueryFailure(domainFailure),
              [defined |-> FALSE, value |-> 0, firstFailure |-> boundFailure], QueryValue(0), TRUE)
        # SourceDomainRangeEqualityOutcome(QueryFailure(domainFailure),
              [defined |-> FALSE, value |-> 0, firstFailure |-> boundFailure], QueryValue(0), FALSE)
    BY SMT DEF SourceDomainRangeEqualityOutcome, QueryValue, QueryFailure


===============================================================
