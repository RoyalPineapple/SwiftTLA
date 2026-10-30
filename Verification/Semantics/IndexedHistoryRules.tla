-------------------- MODULE IndexedHistoryRules --------------------
EXTENDS TLAPS, NaturalsInduction

HistoryPrefix(history, count) == [index \in 1..count |-> history[index]]
HistoryAppend(history, count, value) ==
    [index \in 1..(count + 1) |-> IF index = count + 1 THEN value ELSE history[index]]
IndexedHistory(steps, history, count) ==
    \A index \in 1..count :
        history[index] = steps[index][HistoryPrefix(history, index - 1)]

THEOREM FiniteIndexedHistoryExists ==
    ASSUME NEW count \in Nat, NEW results, NEW steps,
           \A index \in 1..count : steps[index] \in [[1..(index - 1) -> results] -> results]
    PROVE \E history \in [1..count -> results] : IndexedHistory(steps, history, count)
    PROOF
    <1>. DEFINE P(length) == length <= count =>
        \E history \in [1..length -> results] : IndexedHistory(steps, history, length)
    <1>1. P(0)
        <2>. DEFINE empty == [index \in 1..0 |-> index]
        <2>1. empty \in [1..0 -> results] /\ IndexedHistory(steps, empty, 0)
            BY SMT DEF empty, IndexedHistory
        <2>. QED BY <2>1, SMT DEF P
    <1>2. ASSUME NEW length \in Nat, P(length)
          PROVE P(length + 1)
        <2>. SUFFICES ASSUME length + 1 <= count
                     PROVE \E history \in [1..(length + 1) -> results] :
                         IndexedHistory(steps, history, length + 1)
            BY SMT DEF P
        <2>1. PICK prior \in [1..length -> results] : IndexedHistory(steps, prior, length)
            BY P(length), SMT DEF P
        <2>. DEFINE next == steps[length + 1][prior]
                    extended == HistoryAppend(prior, length, next)
        <2>2. next \in results /\ extended \in [1..(length + 1) -> results]
            BY <2>1, SMT DEF next, extended, HistoryAppend
        <2>3. \A index \in 1..length : extended[index] = prior[index]
            BY SMT DEF extended, HistoryAppend
        <2>4. \A index \in 1..length :
                  HistoryPrefix(extended, index - 1) = HistoryPrefix(prior, index - 1)
            BY <2>3, SMT DEF HistoryPrefix
        <2>5. HistoryPrefix(extended, length) = prior
            BY <2>1, <2>3, SMT DEF HistoryPrefix
        <2>6. IndexedHistory(steps, extended, length + 1)
            BY <2>1, <2>3, <2>4, <2>5, SMT
                DEF IndexedHistory, extended, HistoryAppend, next
        <2>. QED BY <2>2, <2>6, SMT
    <1>3. \A length \in Nat : P(length)
        BY <1>1, <1>2, NatInduction
    <1>. QED BY <1>3, SMT DEF P

THEOREM FiniteIndexedHistoriesAgree ==
    ASSUME NEW count \in Nat, NEW results,
           NEW source \in [1..count -> results],
           NEW generated \in [1..count -> results],
           \A index \in 1..count :
               ((\A child \in 1..(index - 1) : source[child] = generated[child])
                => source[index] = generated[index])
    PROVE source = generated
    PROOF
    <1>. DEFINE P(length) ==
        \A index \in 1..count : index <= length => source[index] = generated[index]
    <1>1. P(0) BY SMT DEF P
    <1>2. ASSUME NEW length \in Nat, P(length)
          PROVE P(length + 1)
        <2>. SUFFICES ASSUME length + 1 \in 1..count
                     PROVE source[length + 1] = generated[length + 1]
            BY P(length), SMT DEF P
        <2>1. \A child \in 1..length : source[child] = generated[child]
            BY P(length), SMT DEF P
        <2>. QED BY <2>1, SMT
    <1>3. \A length \in Nat : P(length)
        BY <1>1, <1>2, NatInduction
    <1>. QED BY <1>3, SMT DEF P

=============================================================================
