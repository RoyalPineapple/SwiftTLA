---------------- MODULE FiniteSetMembershipRule ----------------
EXTENDS TLAPS

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

===============================================================
