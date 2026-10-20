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

WrongMember(members, candidate) == candidate \in {2}

THEOREM ChangedMemberHasCounterexample ==
    SourceMember({1}, 1) /\ ~WrongMember({1}, 1)
    BY SMT DEF SourceMember, WrongMember

===============================================================
