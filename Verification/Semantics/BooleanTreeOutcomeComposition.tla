---------------- MODULE BooleanTreeOutcomeComposition ----------------
EXTENDS TLAPS, NaturalsInduction, LazyExpressionFailureRule

Outcomes == [defined : BOOLEAN, value : BOOLEAN, firstFailure : STRING]
DefaultOutcome == [defined |-> TRUE, value |-> FALSE,
                   firstFailure |-> "none"]
Records == [kind : {"leaf", "and", "or", "if"}, left : Nat, right : Nat,
            third : Nat,
            outcome : Outcomes]

ValidPostorder(nodes, count) ==
    \A index \in 1..count :
        /\ nodes[index].kind \in {"leaf", "and", "or", "if"}
        /\ (nodes[index].kind # "leaf" =>
            /\ nodes[index].left \in 1..(index - 1)
            /\ nodes[index].right \in 1..(index - 1))
        /\ (nodes[index].kind = "if" =>
            nodes[index].third \in 1..(index - 1))

SourceNode(nodes, source, index) ==
    IF nodes[index].kind = "leaf" THEN nodes[index].outcome
    ELSE LET left == source[nodes[index].left]
             right == source[nodes[index].right]
         IN IF nodes[index].kind = "and"
            THEN SourceAndChildOutcome(left.defined, left.value,
                     left.firstFailure, right.defined, right.value,
                     right.firstFailure)
            ELSE IF nodes[index].kind = "or"
                 THEN SourceOrChildOutcome(left.defined, left.value,
                          left.firstFailure, right.defined, right.value,
                          right.firstFailure)
                 ELSE LET third == source[nodes[index].third]
                      IN SourceConditionalChildOutcome(
                           left.defined, left.value, left.firstFailure,
                           right.defined, right.value, right.firstFailure,
                           third.defined, third.value, third.firstFailure)

RenderedNode(nodes, rendered, index) ==
    IF nodes[index].kind = "leaf" THEN nodes[index].outcome
    ELSE LET left == rendered[nodes[index].left]
             right == rendered[nodes[index].right]
         IN IF nodes[index].kind = "and"
            THEN RenderedAndChildOutcome(left.defined, left.value,
                     left.firstFailure, right.defined, right.value,
                     right.firstFailure)
            ELSE IF nodes[index].kind = "or"
                 THEN RenderedOrChildOutcome(left.defined, left.value,
                          left.firstFailure, right.defined, right.value,
                          right.firstFailure)
                 ELSE LET third == rendered[nodes[index].third]
                      IN RenderedConditionalChildOutcome(
                           left.defined, left.value, left.firstFailure,
                           right.defined, right.value, right.firstFailure,
                           third.defined, third.value, third.firstFailure)

SourceHistory(nodes, source, count) ==
    \A index \in 1..count : source[index] = SourceNode(nodes, source, index)
RenderedHistory(nodes, rendered, count) ==
    \A index \in 1..count : rendered[index] = RenderedNode(nodes, rendered, index)

PrefixNodes(nodes, count) ==
    [index \in 1..count |-> nodes[index]]
ExtendHistory(history, count, outcome) ==
    [index \in 1..(count + 1) |->
        IF index = count + 1 THEN outcome ELSE history[index]]

THEOREM SourceAndOutcomeIsComplete ==
    ASSUME NEW left \in Outcomes, NEW right \in Outcomes
    PROVE SourceAndChildOutcome(left.defined, left.value,
        left.firstFailure, right.defined, right.value,
        right.firstFailure) \in Outcomes
    BY SMT DEF SourceAndChildOutcome, Outcomes

THEOREM SourceOrOutcomeIsComplete ==
    ASSUME NEW left \in Outcomes, NEW right \in Outcomes
    PROVE SourceOrChildOutcome(left.defined, left.value,
        left.firstFailure, right.defined, right.value,
        right.firstFailure) \in Outcomes
    BY SMT DEF SourceOrChildOutcome, Outcomes

THEOREM SourceConditionalOutcomeIsComplete ==
    ASSUME NEW condition \in Outcomes, NEW yes \in Outcomes,
           NEW no \in Outcomes
    PROVE SourceConditionalChildOutcome(condition.defined,
        condition.value, condition.firstFailure, yes.defined, yes.value,
        yes.firstFailure, no.defined, no.value, no.firstFailure) \in Outcomes
    BY SMT DEF SourceConditionalChildOutcome, Outcomes

THEOREM SourceNodeHasCompleteOutcome ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> Records],
           ValidPostorder(nodes, count), NEW index \in 1..count,
           NEW history \in [1..count -> Outcomes]
    PROVE SourceNode(nodes, history, index) \in Outcomes
    PROOF
    <1>1. ASSUME nodes[index].kind = "leaf"
          PROVE SourceNode(nodes, history, index) \in Outcomes
        <2>1. nodes[index] \in Records
            BY SMT
        <2>2. nodes[index].outcome \in Outcomes
            BY <2>1, SMT DEF Records
        <2>. QED BY <1>1, <2>2, SMT DEF SourceNode
    <1>2. ASSUME nodes[index].kind # "leaf"
          PROVE SourceNode(nodes, history, index) \in Outcomes
        <2>1. nodes[index].left \in 1..count
            /\ nodes[index].right \in 1..count
            BY <1>2, SMT DEF ValidPostorder
        <2>2. history[nodes[index].left] \in Outcomes
            /\ history[nodes[index].right] \in Outcomes
            BY <2>1, SMT
        <2>3. nodes[index].kind = "if" =>
                 history[nodes[index].third] \in Outcomes
            BY SMT DEF ValidPostorder
        <2>4. ASSUME nodes[index].kind = "and"
              PROVE SourceNode(nodes, history, index) \in Outcomes
            BY <2>2, <2>4, SourceAndOutcomeIsComplete,
                SMT DEF SourceNode
        <2>5. ASSUME nodes[index].kind = "or"
              PROVE SourceNode(nodes, history, index) \in Outcomes
            BY <2>2, <2>5, SourceOrOutcomeIsComplete,
                SMT DEF SourceNode
        <2>6. ASSUME nodes[index].kind = "if"
              PROVE SourceNode(nodes, history, index) \in Outcomes
            BY <2>2, <2>3, <2>6,
                SourceConditionalOutcomeIsComplete, SMT DEF SourceNode
        <2>. QED BY <1>2, <2>4, <2>5, <2>6,
            SMT DEF ValidPostorder
    <1>. QED BY <1>1, <1>2, SMT

THEOREM EveryFiniteBooleanTreeHasSourceHistory ==
    \A count \in Nat : \A nodes \in [1..count -> Records] :
        ValidPostorder(nodes, count) =>
            \E history \in [1..count -> Outcomes] :
                SourceHistory(nodes, history, count)
    PROOF
    <1>. DEFINE P(count) ==
        \A nodes \in [1..count -> Records] :
            ValidPostorder(nodes, count) =>
                \E history \in [1..count -> Outcomes] :
                    SourceHistory(nodes, history, count)
    <1>1. P(0)
        <2>. DEFINE empty == [index \in 1..0 |-> DefaultOutcome]
        <2>1. empty \in [1..0 -> Outcomes]
            BY SMT DEF empty, DefaultOutcome, Outcomes
        <2>2. \A nodes \in [1..0 -> Records] :
                  SourceHistory(nodes, empty, 0)
            BY SMT DEF SourceHistory
        <2>. QED BY <2>1, <2>2, SMT DEF P, ValidPostorder, SourceHistory
    <1>2. ASSUME NEW count \in Nat, P(count)
          PROVE P(count + 1)
        <2>. SUFFICES ASSUME NEW nodes \in [1..(count + 1) -> Records],
                             ValidPostorder(nodes, count + 1)
                     PROVE \E history \in [1..(count + 1) -> Outcomes] :
                         SourceHistory(nodes, history, count + 1)
            BY SMT DEF P
        <2>. DEFINE prefix == PrefixNodes(nodes, count)
        <2>1. prefix \in [1..count -> Records]
            BY SMT DEF prefix, PrefixNodes
        <2>2. ValidPostorder(prefix, count)
            BY SMT DEF prefix, PrefixNodes, ValidPostorder
        <2>3. PICK prior \in [1..count -> Outcomes] :
                 SourceHistory(prefix, prior, count)
            BY P(count), <2>1, <2>2, SMT DEF P
        <2>. DEFINE next == SourceNode(nodes, prior, count + 1)
        <2>4. next \in Outcomes
            <3>1. nodes[count + 1] \in Records
                BY SMT
            <3>2. ASSUME nodes[count + 1].kind = "leaf"
                  PROVE next \in Outcomes
                BY <3>1, <3>2, SMT DEF next, SourceNode, Records
            <3>3. ASSUME nodes[count + 1].kind # "leaf"
                  PROVE next \in Outcomes
                <4>1. nodes[count + 1].left \in 1..count
                    /\ nodes[count + 1].right \in 1..count
                    BY <3>3, SMT DEF ValidPostorder
                <4>2. prior[nodes[count + 1].left] \in Outcomes
                    /\ prior[nodes[count + 1].right] \in Outcomes
                    BY <4>1, SMT
                <4>3. nodes[count + 1].kind = "if" =>
                         prior[nodes[count + 1].third] \in Outcomes
                    BY SMT DEF ValidPostorder
                <4>4. ASSUME nodes[count + 1].kind = "and"
                      PROVE next \in Outcomes
                    BY <4>2, <4>4, SourceAndOutcomeIsComplete,
                        SMT DEF next, SourceNode
                <4>5. ASSUME nodes[count + 1].kind = "or"
                      PROVE next \in Outcomes
                    BY <4>2, <4>5, SourceOrOutcomeIsComplete,
                        SMT DEF next, SourceNode
                <4>6. ASSUME nodes[count + 1].kind = "if"
                      PROVE next \in Outcomes
                    BY <4>2, <4>3, <4>6,
                        SourceConditionalOutcomeIsComplete,
                        SMT DEF next, SourceNode
                <4>. QED BY <3>3, <4>4, <4>5, <4>6,
                    SMT DEF ValidPostorder
            <3>. QED BY <3>1, <3>2, <3>3, SMT DEF Records
        <2>. DEFINE extended == ExtendHistory(prior, count, next)
        <2>5. extended \in [1..(count + 1) -> Outcomes]
            BY <2>3, <2>4, SMT DEF extended, ExtendHistory
        <2>6. SourceHistory(nodes, extended, count + 1)
            BY <2>3, SMT
                DEF SourceHistory, SourceNode, ValidPostorder,
                    prefix, PrefixNodes, extended, ExtendHistory,
                    SourceAndChildOutcome, SourceOrChildOutcome,
                    SourceConditionalChildOutcome
        <2>. QED BY <2>5, <2>6, SMT
    <1>3. \A count \in Nat : P(count)
        BY <1>1, <1>2, NatInduction
    <1>4. QED BY <1>3 DEF P

THEOREM SameChildHistoryPreservesEachNode ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> Records],
           ValidPostorder(nodes, count), NEW index \in 1..count,
           NEW history \in [1..count -> Outcomes]
    PROVE SourceNode(nodes, history, index) =
          RenderedNode(nodes, history, index)
    PROOF
    <1>1. ASSUME nodes[index].kind = "leaf"
          PROVE SourceNode(nodes, history, index) =
                RenderedNode(nodes, history, index)
        BY <1>1, SMT DEF SourceNode, RenderedNode
    <1>2. ASSUME nodes[index].kind = "and"
          PROVE SourceNode(nodes, history, index) =
                RenderedNode(nodes, history, index)
        <2>1. nodes[index].left \in 1..count
            /\ nodes[index].right \in 1..count
            BY <1>2, SMT DEF ValidPostorder
        <2>2. history[nodes[index].left] \in Outcomes
            /\ history[nodes[index].right] \in Outcomes
            BY <2>1, SMT
        <2>3. LET left == history[nodes[index].left]
                 right == history[nodes[index].right]
              IN SourceAndChildOutcome(left.defined, left.value,
                   left.firstFailure, right.defined, right.value,
                   right.firstFailure)
                 = RenderedAndChildOutcome(left.defined, left.value,
                   left.firstFailure, right.defined, right.value,
                   right.firstFailure)
            BY <2>2, ShortCircuitAndPropagatesChildOutcome, SMT DEF Outcomes
        <2>. QED BY <1>2, <2>3, SMT DEF SourceNode, RenderedNode
    <1>3. ASSUME nodes[index].kind = "or"
          PROVE SourceNode(nodes, history, index) =
                RenderedNode(nodes, history, index)
        <2>1. nodes[index].left \in 1..count
            /\ nodes[index].right \in 1..count
            BY <1>3, SMT DEF ValidPostorder
        <2>2. history[nodes[index].left] \in Outcomes
            /\ history[nodes[index].right] \in Outcomes
            BY <2>1, SMT
        <2>3. LET left == history[nodes[index].left]
                 right == history[nodes[index].right]
              IN SourceOrChildOutcome(left.defined, left.value,
                   left.firstFailure, right.defined, right.value,
                   right.firstFailure)
                 = RenderedOrChildOutcome(left.defined, left.value,
                   left.firstFailure, right.defined, right.value,
                   right.firstFailure)
            BY <2>2, ShortCircuitOrPropagatesChildOutcome, SMT DEF Outcomes
        <2>. QED BY <1>3, <2>3, SMT DEF SourceNode, RenderedNode
    <1>4. ASSUME nodes[index].kind = "if"
          PROVE SourceNode(nodes, history, index) =
                RenderedNode(nodes, history, index)
        <2>1. nodes[index].left \in 1..count
            /\ nodes[index].right \in 1..count
            /\ nodes[index].third \in 1..count
            BY <1>4, SMT DEF ValidPostorder
        <2>2. history[nodes[index].left] \in Outcomes
            /\ history[nodes[index].right] \in Outcomes
            /\ history[nodes[index].third] \in Outcomes
            BY <2>1, SMT
        <2>3. LET condition == history[nodes[index].left]
                 yes == history[nodes[index].right]
                 no == history[nodes[index].third]
              IN SourceConditionalChildOutcome(condition.defined,
                   condition.value, condition.firstFailure,
                   yes.defined, yes.value, yes.firstFailure,
                   no.defined, no.value, no.firstFailure)
                 = RenderedConditionalChildOutcome(condition.defined,
                   condition.value, condition.firstFailure,
                   yes.defined, yes.value, yes.firstFailure,
                   no.defined, no.value, no.firstFailure)
            BY <2>2, ConditionalPropagatesSelectedChildOutcome,
                SMT DEF Outcomes
        <2>. QED BY <1>4, <2>3, SMT DEF SourceNode, RenderedNode
    <1>. QED BY <1>1, <1>2, <1>3, <1>4, SMT DEF ValidPostorder

THEOREM EveryFiniteBooleanTreeHasOneSharedHistory ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> Records],
           ValidPostorder(nodes, count)
    PROVE \E history \in [1..count -> Outcomes] :
        SourceHistory(nodes, history, count)
        /\ RenderedHistory(nodes, history, count)
    PROOF
    <1>1. PICK history \in [1..count -> Outcomes] :
             SourceHistory(nodes, history, count)
        BY EveryFiniteBooleanTreeHasSourceHistory, SMT
    <1>2. RenderedHistory(nodes, history, count)
        BY <1>1, SameChildHistoryPreservesEachNode, SMT
            DEF SourceHistory, RenderedHistory
    <1>. QED BY <1>1, <1>2, SMT

THEOREM FiniteBooleanTreePreservesCompleteOutcomes ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> Records],
           ValidPostorder(nodes, count),
           NEW source \in [1..count -> Outcomes],
           NEW rendered \in [1..count -> Outcomes],
           SourceHistory(nodes, source, count), RenderedHistory(nodes, rendered, count)
    PROVE \A index \in 1..count : source[index] = rendered[index]
    PROOF
    <1>. DEFINE P(index) ==
        \A prior \in 1..count :
            prior <= index => source[prior] = rendered[prior]
    <1>1. P(0)
        BY SMT DEF P
    <1>2. ASSUME NEW index \in Nat, P(index)
          PROVE P(index + 1)
        <2>. SUFFICES ASSUME index + 1 \in 1..count
                     PROVE source[index + 1] = rendered[index + 1]
            BY P(index), SMT DEF P
        <2>1. nodes[index + 1].kind \in {"leaf", "and", "or", "if"}
            BY SMT DEF ValidPostorder
        <2>2. ASSUME nodes[index + 1].kind = "leaf"
              PROVE source[index + 1] = rendered[index + 1]
            BY <2>2, SMT DEF SourceHistory, RenderedHistory,
                SourceNode, RenderedNode
        <2>3. ASSUME nodes[index + 1].kind # "leaf"
              PROVE source[index + 1] = rendered[index + 1]
            <3>1. nodes[index + 1].left \in 1..index
                /\ nodes[index + 1].right \in 1..index
                BY <2>3, SMT DEF ValidPostorder
            <3>2. source[nodes[index + 1].left] =
                    rendered[nodes[index + 1].left]
                /\ source[nodes[index + 1].right] =
                    rendered[nodes[index + 1].right]
                BY <3>1, P(index), SMT DEF P
            <3>3. nodes[index + 1].kind = "if" =>
                     /\ nodes[index + 1].third \in 1..index
                     /\ source[nodes[index + 1].third] =
                          rendered[nodes[index + 1].third]
                BY P(index), SMT DEF P, ValidPostorder
            <3>4. SourceNode(nodes, source, index + 1) =
                    RenderedNode(nodes, rendered, index + 1)
                <4>1. ASSUME nodes[index + 1].kind = "and"
                      PROVE SourceNode(nodes, source, index + 1) =
                            RenderedNode(nodes, rendered, index + 1)
                    BY <2>3, <3>2, <4>1, SMT
                        DEF SourceNode, RenderedNode, Outcomes,
                            SourceAndChildOutcome, RenderedAndChildOutcome
                <4>2. ASSUME nodes[index + 1].kind = "or"
                      PROVE SourceNode(nodes, source, index + 1) =
                            RenderedNode(nodes, rendered, index + 1)
                    BY <2>3, <3>2, <4>2, SMT
                        DEF SourceNode, RenderedNode, Outcomes,
                            SourceOrChildOutcome, RenderedOrChildOutcome
                <4>3. ASSUME nodes[index + 1].kind = "if"
                      PROVE SourceNode(nodes, source, index + 1) =
                            RenderedNode(nodes, rendered, index + 1)
                    BY <2>3, <3>2, <3>3, <4>3, SMT
                        DEF SourceNode, RenderedNode, Outcomes,
                            SourceConditionalChildOutcome,
                            RenderedConditionalChildOutcome
                <4>. QED BY <2>1, <2>3, <4>1, <4>2, <4>3, SMT
            <3>5. source[index + 1] = SourceNode(nodes, source, index + 1)
                /\ rendered[index + 1] = RenderedNode(nodes, rendered, index + 1)
                BY SMT DEF SourceHistory, RenderedHistory
            <3>. QED BY <3>4, <3>5
        <2>. QED BY <2>1, <2>2, <2>3, SMT
    <1>3. \A index \in Nat : P(index)
        BY <1>1, <1>2, NatInduction
    <1>4. QED BY <1>3, SMT DEF P

THEOREM FiniteBooleanTreeHasExactlyOneCompleteHistory ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> Records],
           ValidPostorder(nodes, count),
           NEW first \in [1..count -> Outcomes],
           NEW second \in [1..count -> Outcomes],
           SourceHistory(nodes, first, count),
           SourceHistory(nodes, second, count)
    PROVE first = second
    PROOF
    <1>1. RenderedHistory(nodes, second, count)
        BY SameChildHistoryPreservesEachNode, SMT
            DEF SourceHistory, RenderedHistory
    <1>2. \A index \in 1..count : first[index] = second[index]
        BY <1>1, FiniteBooleanTreePreservesCompleteOutcomes
    <1>. QED BY <1>2, SMT

=====================================================================
