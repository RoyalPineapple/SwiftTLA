---- MODULE AtomicSchedulerAllocator ----
EXTENDS OrderedIntExpressionRule, AtomicAllocatorText

\* A Swift name equal to "__atomic_\(i)" is represented by its literal prefix and
\* canonical nonnegative decimal index. Normal Swift String/Set operations and
\* the lexical binding of this selected local closure have reviewed interpretations.
AtomicName(i) == <<AtomicPrefix,i>>
AllocatorState(s) == s = [next |-> s.next,used |-> s.used] /\ s.next \in 0..SwiftIntMax
AtomicAvailable(s,i) == i \in s.next..(SwiftIntMax-1) /\ AtomicName(i) \notin s.used
AtomicRoom(s,n,r) ==
    /\ DOMAIN r = 1..n
    /\ \A j \in 1..n : AtomicAvailable(s,r[j])
    /\ \A i,j \in 1..n : i < j => r[i] < r[j]
AtomicAllocatorCanServe(s,n) ==
    AllocatorState(s) /\ n \in Nat /\ \E r : AtomicRoom(s,n,r)

AtomicTrial(s) ==
    LET name == AtomicName(s.next)
        next == [next |-> s.next + AtomicIncrement, used |-> s.used \cup {name}]
    IN IF RecognizedAllocatorBody /\ s.next \in 0..(SwiftIntMax-1)
       THEN [inserted |-> name \notin s.used, name |-> name, after |-> next]
       ELSE [inserted |-> FALSE, name |-> <<>>, after |-> s]

AtomicLeastFree(s,i) == AtomicAvailable(s,i) /\ \A j \in 0..(i-1) : ~AtomicAvailable(s,j)
AtomicFirstFree(s) == CHOOSE i \in Nat : AtomicLeastFree(s,i)
AtomicBindingAllocation(s) == AtomicTrial([next |-> AtomicFirstFree(s), used |-> s.used])

\* Every unsuccessful Set.insert keeps its old set. The counter still advances.
\* The successful iteration returns the candidate after advancing the counter.
AtomicAllocatorReturns(s,k,h,out) ==
    /\ k \in Nat /\ DOMAIN h = 0..k /\ h[0] = s
    /\ \A j \in 0..(k-1) :
           /\ h[j].next \in 0..(SwiftIntMax-1) /\ ~AtomicTrial(h[j]).inserted
           /\ h[j+1] = AtomicTrial(h[j]).after
    /\ h[k].next \in 0..(SwiftIntMax-1) /\ AtomicTrial(h[k]).inserted /\ out = AtomicTrial(h[k])

THEOREM FailedInsertionAdvancesTheOrdinalOnly ==
    ASSUME NEW ordinal \in 0..(SwiftIntMax-1), NEW used, AtomicName(ordinal) \in used
    PROVE LET step == AtomicTrial([next |-> ordinal, used |-> used])
          IN ~step.inserted /\ step.after = [next |-> ordinal+1,used |-> used]
PROOF
<1>. DEFINE state == [next |-> ordinal,used |-> used]
<1>same. used \cup {AtomicName(ordinal)} = used
    BY ONLY AtomicName(ordinal) \in used, SMT
<1>unit. AtomicIncrement = 1 BY ONLY ActualAtomicAllocatorTokens, PTL
<1>fields. /\ state.next = ordinal /\ state.used = used BY IsaM("simp") DEF state
<1>execute. AtomicTrial(state) =
       [inserted |-> FALSE,name |-> AtomicName(ordinal),after |-> [next |-> ordinal+1,used |-> used]]
    BY ONLY <1>same,<1>unit,<1>fields,ActualAtomicAllocatorBody,(ordinal \in 0..(SwiftIntMax-1)),
       AtomicName(ordinal) \in used, IsaM("simp"), SMT DEF AtomicTrial
<1>. QED BY ONLY <1>execute, IsaM("simp"), SMT DEF state

THEOREM ActualAllocatorLoopFindsTheFirstUnusedOrdinal ==
    ASSUME NEW s, NEW n \in Nat \ {0}, AtomicAllocatorCanServe(s,n)
    PROVE /\ AtomicLeastFree(s,AtomicFirstFree(s))
          /\ \E k,h : AtomicAllocatorReturns(s,k,h,AtomicBindingAllocation(s))
PROOF
<1>r. PICK r : AtomicRoom(s,n,r)
    BY ONLY AtomicAllocatorCanServe(s,n) DEF AtomicAllocatorCanServe
<1>entry. /\ s.next \in Nat /\ s = [next |-> s.next,used |-> s.used]
          /\ 1 \in 1..n /\ r[1] \in Nat /\ AtomicAvailable(s,r[1])
    BY ONLY <1>r, AtomicAllocatorCanServe(s,n), (n \in Nat \ {0}), IntegerDomain, SMT
        DEF AtomicAllocatorCanServe, AllocatorState, AtomicRoom, AtomicAvailable
<1>leastExists. \E i \in Nat : AtomicLeastFree(s,i)
    BY ONLY <1>entry, SmallestNatural DEF AtomicLeastFree
<1>. DEFINE f == AtomicFirstFree(s)
            k == f - s.next
            h == [j \in 0..k |-> [next |-> s.next+j, used |-> s.used]]
<1>least. AtomicLeastFree(s,f)
    BY ONLY <1>leastExists, SMT DEF AtomicFirstFree,f
<1>bounds. /\ f \in s.next..(SwiftIntMax-1) /\ AtomicName(f) \notin s.used
           /\ k \in Nat /\ s.next+k = f
    BY ONLY <1>least, <1>entry, SMT DEF AtomicLeastFree,AtomicAvailable,k
<1>initial. /\ DOMAIN h = 0..k /\ h[0] = s /\ h[k] = [next |-> f,used |-> s.used]
    BY ONLY <1>bounds,<1>entry,SMT DEF h
<1>loop. \A j \in 0..(k-1) :
           /\ h[j].next \in 0..(SwiftIntMax-1) /\ ~AtomicTrial(h[j]).inserted
           /\ h[j+1] = AtomicTrial(h[j]).after
    <2>. SUFFICES ASSUME NEW j \in 0..(k-1) PROVE
           /\ h[j].next \in 0..(SwiftIntMax-1) /\ ~AtomicTrial(h[j]).inserted
           /\ h[j+1] = AtomicTrial(h[j]).after
        OBVIOUS
    <2>numbers. /\ j \in Nat /\ k \in Nat /\ f \in Nat /\ s.next \in Nat /\ SwiftIntMax \in Int
                 /\ 0 <= j /\ j < k /\ f = s.next + k /\ f < SwiftIntMax
        BY ONLY <1>bounds, <1>entry, (j \in 0..(k-1)), IntegerDomain, SMT
    <2>indices. /\ j \in 0..k /\ j+1 \in 0..k /\ s.next+j \in s.next..(f-1)
                /\ s.next+j \in 0..(SwiftIntMax-1)
        BY ONLY <2>numbers, SMT
    <2>used. AtomicName(s.next+j) \in s.used
        BY ONLY <1>least, <1>entry, <1>bounds, <2>indices, SMT DEF AtomicLeastFree,AtomicAvailable
    <2>at. /\ h[j] = [next |-> s.next+j, used |-> s.used]
            /\ h[j+1] = [next |-> (s.next+j)+1, used |-> s.used]
        BY ONLY <2>indices,<2>numbers, SMT DEF h
    <2>trial. LET step == AtomicTrial([next |-> s.next+j, used |-> s.used])
              IN ~step.inserted /\ step.after = [next |-> (s.next+j)+1,used |-> s.used]
        BY ONLY <2>used, <2>indices, FailedInsertionAdvancesTheOrdinalOnly, Isa
    <2>. QED BY ONLY <2>at,<2>trial,<2>indices, SMT
<1>last. /\ AtomicTrial(h[k]).inserted /\ h[k].next \in 0..(SwiftIntMax-1)
          /\ AtomicTrial(h[k]) = AtomicBindingAllocation(s)
    BY ONLY <1>initial,<1>bounds,<1>entry, ActualAtomicAllocatorBody, SMT DEF AtomicTrial,AtomicBindingAllocation,f
<1>returns. AtomicAllocatorReturns(s,k,h,AtomicBindingAllocation(s))
    BY ONLY <1>bounds,<1>initial,<1>loop,<1>last, SMT DEF AtomicAllocatorReturns
<1>. QED BY ONLY <1>least,<1>returns DEF f

THEOREM SuccessfulInsertionReturnsItsCandidateAndUpdatedState ==
    ASSUME NEW ordinal \in 0..(SwiftIntMax-1), NEW used, AtomicName(ordinal) \notin used
    PROVE AtomicTrial([next |-> ordinal,used |-> used]) =
          [inserted |-> TRUE, name |-> AtomicName(ordinal),
           after |-> [next |-> ordinal+1,used |-> used \cup {AtomicName(ordinal)}]]
PROOF
<1>. DEFINE state == [next |-> ordinal,used |-> used]
<1>unit. AtomicIncrement = 1 BY ONLY ActualAtomicAllocatorTokens, PTL
<1>fields. /\ state.next = ordinal /\ state.used = used BY IsaM("simp") DEF state
<1>. QED BY ONLY <1>unit,<1>fields,ActualAtomicAllocatorBody,(ordinal \in 0..(SwiftIntMax-1)),
        AtomicName(ordinal) \notin used, IsaM("simp"), SMT DEF AtomicTrial,state

THEOREM ActualAllocatorReturnsAFreshBinderForTheShorterSuffix ==
    ASSUME NEW state, NEW count \in Nat \ {0}, AtomicAllocatorCanServe(state,count)
    PROVE LET out == AtomicBindingAllocation(state)
          IN /\ \E k,h : AtomicAllocatorReturns(state,k,h,out)
             /\ out.name \notin state.used
             /\ out.after.used = state.used \cup {out.name}
             /\ out.after.next > state.next
             /\ AtomicAllocatorCanServe(out.after,count-1)
PROOF
<1>. DEFINE f == AtomicFirstFree(state)
            out == AtomicBindingAllocation(state)
<1>loop. /\ AtomicLeastFree(state,f) /\ \E k,h : AtomicAllocatorReturns(state,k,h,out)
    BY ONLY (count \in Nat \ {0}), AtomicAllocatorCanServe(state,count),
            ActualAllocatorLoopFindsTheFirstUnusedOrdinal DEF f,out
<1>first. /\ f \in state.next..(SwiftIntMax-1) /\ AtomicName(f) \notin state.used /\ state.next \in Nat
    BY ONLY <1>loop, AtomicAllocatorCanServe(state,count), IntegerDomain, SMT
       DEF AtomicLeastFree,AtomicAvailable,AtomicAllocatorCanServe,AllocatorState
<1>numeric. /\ f \in 0..(SwiftIntMax-1) /\ f \in Nat /\ state.next <= f /\ SwiftIntMax \in Int
    BY ONLY <1>first, IntegerDomain, SMT
<1>trial. out = [inserted |-> TRUE,name |-> AtomicName(f),
                  after |-> [next |-> f+1,used |-> state.used \cup {AtomicName(f)}]]
    BY ONLY <1>first,<1>numeric,SuccessfulInsertionReturnsItsCandidateAndUpdatedState,Isa
       DEF out,f,AtomicBindingAllocation
<1>identities. /\ out.name = AtomicName(f)
                 /\ out.after = [next |-> f+1,used |-> state.used \cup {AtomicName(f)}]
    BY ONLY <1>trial, IsaM("simp"), SMT
<1>advance. /\ f+1 \in 0..SwiftIntMax /\ f+1 > state.next
    BY ONLY <1>first,<1>numeric,IntegerDomain,SMT
<1>out. /\ out.name = AtomicName(f) /\ out.after = [next |-> f+1,used |-> state.used \cup {AtomicName(f)}]
        /\ out.after.next > state.next /\ AllocatorState(out.after)
    BY ONLY <1>identities,<1>advance, IsaM("simp"), SMT DEF AllocatorState
<1>reserve. PICK reserve : AtomicRoom(state,count,reserve)
    BY ONLY AtomicAllocatorCanServe(state,count) DEF AtomicAllocatorCanServe
<1>lower. f <= reserve[1]
    BY ONLY <1>reserve,<1>first,<1>loop,(count \in Nat \ {0}), SMT DEF AtomicRoom,AtomicLeastFree,AtomicAvailable
<1>. DEFINE suffix == [i \in 1..(count-1) |-> reserve[i+1]]
<1>available. \A j \in 1..(count-1) : AtomicAvailable(out.after,suffix[j])
    <2>. SUFFICES ASSUME NEW j \in 1..(count-1) PROVE AtomicAvailable(out.after,suffix[j]) OBVIOUS
    <2>index. /\ 1 \in 1..count /\ j+1 \in 1..count /\ 1 < j+1
        BY ONLY (j \in 1..(count-1)), (count \in Nat \ {0}), SMT
    <2>members. /\ AtomicAvailable(state,reserve[1]) /\ AtomicAvailable(state,reserve[j+1])
                /\ reserve[1] < reserve[j+1]
        BY ONLY <2>index,<1>reserve, SMT DEF AtomicRoom
    <2>integers. /\ reserve[1] \in Int /\ reserve[j+1] \in Int
        BY ONLY <2>members,<1>first,IntegerDomain, SMT DEF AtomicAvailable
    <2>later. f < reserve[j+1]
        BY ONLY <2>members,<2>integers,<1>lower,<1>numeric, SMT
    <2>different. AtomicName(reserve[j+1]) # AtomicName(f)
        BY ONLY <2>later,<2>integers,<1>numeric, SMT DEF AtomicName
    <2>bounds. reserve[j+1] \in (f+1)..(SwiftIntMax-1)
        BY ONLY <2>members,<2>later,<2>integers,<1>numeric,IntegerDomain, SMT DEF AtomicAvailable
    <2>absent. AtomicName(reserve[j+1]) \notin state.used \cup {AtomicName(f)}
        BY ONLY <2>different,<2>members, SMT DEF AtomicAvailable
    <2>. QED BY ONLY (j \in 1..(count-1)),<2>bounds,<2>absent,<1>out,SMT DEF suffix,AtomicAvailable
<1>suffix. AtomicRoom(out.after,count-1,suffix)
    BY ONLY <1>reserve, <1>available, (count \in Nat \ {0}), SMT DEF AtomicRoom,suffix
<1>cap. AtomicAllocatorCanServe(out.after,count-1)
    BY ONLY <1>out, <1>suffix, (count \in Nat \ {0}), SMT DEF AtomicAllocatorCanServe
<1>. QED BY ONLY <1>loop,<1>first,<1>out,<1>cap, SMT DEF out
====
