---- MODULE SchedulerCallStack ----
EXTENDS NaturalsInduction, TLAPS

CallChain(seed,lo,hi,step(_,_)) ==
    LET chain[i \in lo..hi] == IF i=lo THEN seed ELSE step(chain[i-1],i)
    IN chain

THEOREM PointwiseCallsDetermineChain ==
    ASSUME NEW lo \in Nat, NEW hi \in Nat, lo <= hi,
           NEW seed, NEW step(_,_), NEW seen,
           DOMAIN seen = lo..hi, seen[lo] = seed,
           \A i \in (lo+1)..hi : seen[i] = step(seen[i-1],i)
    PROVE \A i \in lo..hi : CallChain(seed,lo,hi,step)[i] = seen[i]
PROOF
<1>. DEFINE actual == CallChain(seed,lo,hi,step)
<1>definition. FiniteNatInductiveDefHypothesis(actual,seed,step,lo,hi)
    BY ONLY DEF actual,CallChain,FiniteNatInductiveDefHypothesis
<1>source. FiniteNatInductiveDefConclusion(actual,seed,step,lo,hi)
    BY ONLY <1>definition,(lo \in Nat),(hi \in Nat),FiniteNatInductiveDef,IsaM("blast")
<1>pointwise. \A i \in lo..hi :
    seen[i] = IF i=lo THEN seed ELSE step(seen[i-1],i)
    BY ONLY (lo \in Nat),(hi \in Nat),(seen[lo]=seed),
            (\A i \in (lo+1)..hi : seen[i] = step(seen[i-1],i)), SMT
<1>. DEFINE expected == [i \in lo..hi |-> seen[i]]
<1>ext. expected = [i \in lo..hi |-> IF i=lo THEN seed ELSE step(expected[i-1],i)]
    <2>. SUFFICES \A i \in lo..hi : seen[i] = IF i=lo THEN seed ELSE step(expected[i-1],i)
        BY IsaM("auto") DEF expected
    <2>. TAKE i \in lo..hi
    <2>base. CASE i=lo BY ONLY <2>base,(seen[lo]=seed),IsaM("simp")
    <2>rest. CASE i#lo
        <3>index. i-1 \in lo..hi BY ONLY (i \in lo..hi),<2>rest,(lo \in Nat),(hi \in Nat),SMT
        <3>lookup. expected[i-1]=seen[i-1] BY ONLY <3>index,IsaM("simp") DEF expected
        <3>. QED BY ONLY <1>pointwise,(i \in lo..hi),<3>lookup,SMT
    <2>. QED BY ONLY <2>base,<2>rest
<1>same. FiniteNatInductiveDefConclusion(expected,seed,step,lo,hi)
    BY ONLY <1>ext DEF FiniteNatInductiveDefConclusion
<1>eq. actual=expected BY ONLY <1>source,<1>same,(lo \in Nat),(hi \in Nat),FiniteNatInductiveUnique,Zenon,SMT,IsaM("metis")
<1>. QED BY ONLY <1>eq,IsaM("simp") DEF actual,expected
====
