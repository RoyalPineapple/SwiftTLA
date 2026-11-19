---------------- MODULE CompilerInputScopeRules ----------------
EXTENDS TLAPS, Integers, Sequences, CompilerInputBytes

\* Source grammar for the observed canonical SIL lexical fragment, not full SIL adequacy.
SILPlainAt(first, last) ==
    \A i \in first..(last - 1): CompilerInputByte[i] \in 0..255 \ {34, 35, 47, 92, 123, 125}
SILCommentAt(first, last) ==
    /\ last >= first + 3
    /\ CompilerInputByte[first] = 47 /\ CompilerInputByte[first + 1] = 47
    /\ CompilerInputByte[last - 1] = 10
    /\ \A i \in (first + 2)..(last - 2): CompilerInputByte[i] \in 0..255 \ {10, 13}
SILQuotedAt(first, last) ==
    /\ last >= first + 2
    /\ CompilerInputByte[first] = 34 /\ CompilerInputByte[last - 1] = 34
    /\ CompilerInputByte[last] # 34
    /\ \A i \in (first + 1)..(last - 2): CompilerInputByte[i] \in 0..255 \ {10, 13, 34, 92}
SILStructuralUnitAt(first, last, kind) ==
    /\ first \in Nat /\ last \in Nat /\ first < last /\ last < CompilerInputSize
    /\ CASE kind = "plain" -> SILPlainAt(first, last)
         [] kind = "comment" -> SILCommentAt(first, last)
         [] kind = "quoted" -> SILQuotedAt(first, last)
         [] kind = "hash" -> /\ last = first + 1 /\ CompilerInputByte[first] = 35
                             /\ CompilerInputByte[last] \notin {34, 35}
         [] kind = "open" -> last = first + 1 /\ CompilerInputByte[first] = 123
         [] kind = "close" -> last = first + 1 /\ CompilerInputByte[first] = 125
         [] OTHER -> FALSE


SILScopeStackStep(first, kind, before, after) ==
    CASE kind = "open" -> after = Append(before, first)
      [] kind = "close" -> /\ Len(before) > 0
                           /\ after = SubSeq(before, 1, Len(before) - 1)
      [] OTHER -> after = before

SILScopeTrace(cuts, kinds, stacks, count) ==
    /\ cuts \in [0..count -> Nat]
    /\ kinds \in [1..count -> {"plain", "comment", "quoted", "hash", "open", "close"}]
    /\ stacks \in [0..count -> Seq(Nat)]
    /\ \A j \in 1..count:
        /\ SILStructuralUnitAt(cuts[j - 1], cuts[j], kinds[j])
        /\ SILScopeStackStep(cuts[j - 1], kinds[j], stacks[j - 1], stacks[j])

SILScopeRange(first, last, before, after) ==
    \E count \in Nat: \E cuts, kinds, stacks:
        /\ SILScopeTrace(cuts, kinds, stacks, count)
        /\ cuts[0] = first /\ cuts[count] = last
        /\ stacks[0] = before /\ stacks[count] = after

THEOREM CheckedStructuralUnitSuppliesScopeRange ==
    ASSUME NEW first \in Nat, NEW last \in Nat,
           NEW kind \in {"plain", "comment", "quoted", "hash", "open", "close"},
           NEW before \in Seq(Nat), NEW after \in Seq(Nat),
           SILStructuralUnitAt(first, last, kind),
           SILScopeStackStep(first, kind, before, after)
    PROVE SILScopeRange(first, last, before, after)
    PROOF
    <1>. DEFINE cuts == [i \in 0..1 |-> IF i = 0 THEN first ELSE last]
                kinds == [i \in 1..1 |-> kind]
                stacks == [i \in 0..1 |-> IF i = 0 THEN before ELSE after]
    <1>trace. SILScopeTrace(cuts, kinds, stacks, 1)
        BY SMT DEF SILScopeTrace, cuts, kinds, stacks
    <1>. QED BY <1>trace, SMT DEF SILScopeRange, cuts, kinds, stacks

THEOREM CheckedScopeRangesCompose ==
    ASSUME NEW first, NEW middle, NEW last,
           NEW before, NEW between, NEW after,
           SILScopeRange(first, middle, before, between),
           SILScopeRange(middle, last, between, after)
    PROVE SILScopeRange(first, last, before, after)
    PROOF
    <1>left. PICK m, lc, lk, ls: m \in Nat
        /\ SILScopeTrace(lc, lk, ls, m)
        /\ lc[0] = first /\ lc[m] = middle
        /\ ls[0] = before /\ ls[m] = between
        BY DEF SILScopeRange
    <1>right. PICK n, rc, rk, rs: n \in Nat
        /\ SILScopeTrace(rc, rk, rs, n)
        /\ rc[0] = middle /\ rc[n] = last
        /\ rs[0] = between /\ rs[n] = after
        BY DEF SILScopeRange
    <1>. DEFINE cuts == [i \in 0..(m + n) |-> IF i <= m THEN lc[i] ELSE rc[i - m]]
                kinds == [i \in 1..(m + n) |-> IF i <= m THEN lk[i] ELSE rk[i - m]]
                stacks == [i \in 0..(m + n) |-> IF i <= m THEN ls[i] ELSE rs[i - m]]
    <1>types. /\ cuts \in [0..(m + n) -> Nat]
                /\ kinds \in [1..(m + n) -> {"plain", "comment", "quoted", "hash", "open", "close"}]
                /\ stacks \in [0..(m + n) -> Seq(Nat)]
        BY ONLY <1>left, <1>right, SMT DEF cuts, kinds, stacks, SILScopeTrace
    <1>edges. /\ cuts[0] = first /\ cuts[m + n] = last
                /\ stacks[0] = before /\ stacks[m + n] = after
        BY ONLY <1>left, <1>right, SMT DEF cuts, stacks
    <1>steps. ASSUME NEW j \in 1..(m + n)
              PROVE /\ SILStructuralUnitAt(cuts[j - 1], cuts[j], kinds[j])
                    /\ SILScopeStackStep(cuts[j - 1], kinds[j], stacks[j - 1], stacks[j])
        PROOF
        <2>left. CASE j <= m
            BY ONLY <2>left, <1>left, <1>right, SMT DEF cuts, kinds, stacks, SILScopeTrace
        <2>right. CASE j > m
            <3>boundary. /\ cuts[j - 1] = rc[j - m - 1]
                           /\ stacks[j - 1] = rs[j - m - 1]
                BY ONLY <2>right, <1>left, <1>right, SMT DEF cuts, stacks
            <3>. QED BY ONLY <2>right, <1>left, <1>right, <3>boundary, SMT DEF cuts, kinds, stacks, SILScopeTrace
        <2>. QED BY ONLY <1>left, <1>right, <2>left, <2>right, SMT
    <1>trace. SILScopeTrace(cuts, kinds, stacks, m + n)
        BY <1>types, <1>steps DEF SILScopeTrace
    <1>. QED BY ONLY <1>trace, <1>edges, <1>left, <1>right, SMT DEF SILScopeRange


SILInputInterval(first, last, allowed) ==
    \A i \in first..last: CompilerInputByte[i] \in allowed

SILInputPageRange(base, first, last, page, allowed) ==
    /\ base \in Nat /\ first \in base..(base + 15) /\ last \in first..(base + 15)
    /\ \A j \in 1..16: CompilerInputByte[base + j - 1] = page[j]
    /\ \A j \in (first - base + 1)..(last - base + 1): page[j] \in allowed

THEOREM LoadedPageSuppliesInputInterval ==
    ASSUME NEW base, NEW first, NEW last, NEW page, NEW allowed,
           SILInputPageRange(base, first, last, page, allowed)
    PROVE SILInputInterval(first, last, allowed)
    PROOF
    <1>at. ASSUME NEW i \in first..last
           PROVE CompilerInputByte[i] \in allowed
        PROOF
        <2>index. /\ i - base + 1 \in 1..16
                   /\ i - base + 1 \in (first - base + 1)..(last - base + 1)
            BY ONLY SILInputPageRange(base, first, last, page, allowed), SMT DEF SILInputPageRange
        <2>read. CompilerInputByte[i] = page[i - base + 1]
            BY ONLY SILInputPageRange(base, first, last, page, allowed), <2>index, SMT DEF SILInputPageRange
        <2>. QED BY ONLY SILInputPageRange(base, first, last, page, allowed), <2>index, <2>read, SMT DEF SILInputPageRange
    <1>. QED BY <1>at DEF SILInputInterval

=============================================================================
