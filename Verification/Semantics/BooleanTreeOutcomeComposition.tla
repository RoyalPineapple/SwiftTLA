---------------- MODULE BooleanTreeOutcomeComposition ----------------
EXTENDS TLAPS, NaturalsInduction, LazyExpressionFailureRule

Outcomes == [defined : BOOLEAN, value : BOOLEAN, firstFailure : STRING]
Records == [kind : {"leaf", "and", "or"}, left : Nat, right : Nat,
            outcome : Outcomes]

ValidPostorder(nodes, count) ==
    \A index \in 1..count :
        /\ nodes[index].kind \in {"leaf", "and", "or"}
        /\ (nodes[index].kind # "leaf" =>
            /\ nodes[index].left \in 1..(index - 1)
            /\ nodes[index].right \in 1..(index - 1))

SourceNode(nodes, source, index) ==
    IF nodes[index].kind = "leaf" THEN nodes[index].outcome
    ELSE LET left == source[nodes[index].left]
             right == source[nodes[index].right]
         IN IF nodes[index].kind = "and"
            THEN SourceAndChildOutcome(left.defined, left.value,
                     left.firstFailure, right.defined, right.value,
                     right.firstFailure)
            ELSE SourceOrChildOutcome(left.defined, left.value,
                     left.firstFailure, right.defined, right.value,
                     right.firstFailure)

RenderedNode(nodes, rendered, index) ==
    IF nodes[index].kind = "leaf" THEN nodes[index].outcome
    ELSE LET left == rendered[nodes[index].left]
             right == rendered[nodes[index].right]
         IN IF nodes[index].kind = "and"
            THEN RenderedAndChildOutcome(left.defined, left.value,
                     left.firstFailure, right.defined, right.value,
                     right.firstFailure)
            ELSE RenderedOrChildOutcome(left.defined, left.value,
                     left.firstFailure, right.defined, right.value,
                     right.firstFailure)

SourceHistory(nodes, source, count) ==
    \A index \in 1..count : source[index] = SourceNode(nodes, source, index)
RenderedHistory(nodes, rendered, count) ==
    \A index \in 1..count : rendered[index] = RenderedNode(nodes, rendered, index)

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
        <2>1. nodes[index + 1].kind \in {"leaf", "and", "or"}
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
            <3>3. SourceNode(nodes, source, index + 1) =
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
                <4>. QED BY <2>1, <2>3, <4>1, <4>2, SMT
            <3>4. source[index + 1] = SourceNode(nodes, source, index + 1)
                /\ rendered[index + 1] = RenderedNode(nodes, rendered, index + 1)
                BY SMT DEF SourceHistory, RenderedHistory
            <3>. QED BY <3>3, <3>4
        <2>. QED BY <2>1, <2>2, <2>3, SMT
    <1>3. \A index \in Nat : P(index)
        BY <1>1, <1>2, NatInduction
    <1>4. QED BY <1>3, SMT DEF P

=====================================================================
