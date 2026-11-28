---------------- MODULE SequenceExpressionComposition ----------------
EXTENDS SequenceExpressionConstructorRules, IndexedHistoryRules

CONSTANT Contexts
SequenceSemantics == [Contexts -> SequenceOutcomes]
ElementSemantics == [Contexts -> ElementOutcomes]
SequenceNodes == [kind: {"leaf", "append", "concat"}, left: Nat, right: Nat,
    sourceLeaf: SequenceSemantics, generatedLeaf: SequenceSemantics,
    sourceElement: ElementSemantics, generatedElement: ElementSemantics]

ValidPostorder(nodes, count) ==
    \A index \in 1..count :
        /\ (nodes[index].kind # "leaf" => nodes[index].left \in 1..(index - 1))
        /\ (nodes[index].kind = "concat" => nodes[index].right \in 1..(index - 1))
LeafAgreement(nodes, count) ==
    \A index \in 1..count :
        /\ (nodes[index].kind = "leaf" => nodes[index].sourceLeaf = nodes[index].generatedLeaf)
        /\ (nodes[index].kind = "append" => nodes[index].sourceElement = nodes[index].generatedElement)

SourceNode(nodes, history, index) ==
    [context \in Contexts |->
        IF nodes[index].kind = "leaf" THEN nodes[index].sourceLeaf[context]
        ELSE IF nodes[index].kind = "append"
             THEN SourceAppend(history[nodes[index].left][context], nodes[index].sourceElement[context])
             ELSE SourceConcat(history[nodes[index].left][context], history[nodes[index].right][context])]
GeneratedNode(nodes, history, index) ==
    [context \in Contexts |->
        IF nodes[index].kind = "leaf" THEN nodes[index].generatedLeaf[context]
        ELSE IF nodes[index].kind = "append"
             THEN GeneratedAppend(history[nodes[index].left][context], nodes[index].generatedElement[context])
             ELSE GeneratedConcat(history[nodes[index].left][context], history[nodes[index].right][context])]
SourceSteps(nodes, count) ==
    [index \in 1..count |-> [prefix \in [1..(index - 1) -> SequenceSemantics] |->
        SourceNode(nodes, prefix, index)]]
GeneratedSteps(nodes, count) ==
    [index \in 1..count |-> [prefix \in [1..(index - 1) -> SequenceSemantics] |->
        GeneratedNode(nodes, prefix, index)]]

THEOREM SequenceNodeOutcomesAreClosed ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> SequenceNodes],
           ValidPostorder(nodes, count), NEW index \in 1..count,
           NEW history \in [1..(index - 1) -> SequenceSemantics]
    PROVE /\ SourceNode(nodes, history, index) \in SequenceSemantics
          /\ GeneratedNode(nodes, history, index) \in SequenceSemantics
    PROOF
    <1>1. nodes[index] \in SequenceNodes BY SMT
    <1>2. nodes[index].kind # "leaf" => history[nodes[index].left] \in SequenceSemantics
        BY SMT DEF ValidPostorder
    <1>3. nodes[index].kind = "concat" => history[nodes[index].right] \in SequenceSemantics
        BY SMT DEF ValidPostorder
    <1>4. \A context \in Contexts :
              /\ SourceNode(nodes, history, index)[context] \in SequenceOutcomes
              /\ GeneratedNode(nodes, history, index)[context] \in SequenceOutcomes
        <2>. SUFFICES ASSUME NEW context \in Contexts
                     PROVE /\ SourceNode(nodes, history, index)[context] \in SequenceOutcomes
                           /\ GeneratedNode(nodes, history, index)[context] \in SequenceOutcomes
            BY SMT
        <2>1. CASE nodes[index].kind = "leaf"
            BY <1>1, <2>1, SMT DEF SequenceNodes, SequenceSemantics, SourceNode, GeneratedNode
        <2>2. CASE nodes[index].kind = "append"
            BY <1>1, <1>2, <2>2, AppendRetainsValueAndFirstFailure, SMT
                DEF SequenceNodes, SequenceSemantics, ElementSemantics, SourceNode, GeneratedNode
        <2>3. CASE nodes[index].kind = "concat"
            BY <1>2, <1>3, <2>3, ConcatenationRetainsValueAndFirstFailure, SMT
                DEF SequenceSemantics, SourceNode, GeneratedNode
        <2>. QED BY <1>1, <2>1, <2>2, <2>3, SMT DEF SequenceNodes
    <1>. QED BY <1>4, SMT DEF SequenceSemantics, SourceNode, GeneratedNode

THEOREM EveryFiniteSequenceTreeHasIndependentHistories ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> SequenceNodes], ValidPostorder(nodes, count)
    PROVE /\ \E source \in [1..count -> SequenceSemantics] :
                 IndexedHistory(SourceSteps(nodes, count), source, count)
          /\ \E generated \in [1..count -> SequenceSemantics] :
                 IndexedHistory(GeneratedSteps(nodes, count), generated, count)
    PROOF
    <1>. DEFINE sourceStep == [index \in 1..count |->
                    [prefix \in [1..(index - 1) -> SequenceSemantics] |-> SourceNode(nodes, prefix, index)]]
                generatedStep == [index \in 1..count |->
                    [prefix \in [1..(index - 1) -> SequenceSemantics] |-> GeneratedNode(nodes, prefix, index)]]
    <1>1. \A index \in 1..count :
              sourceStep[index] \in [[1..(index - 1) -> SequenceSemantics] -> SequenceSemantics]
        BY SequenceNodeOutcomesAreClosed, SMT DEF sourceStep
    <1>2. \A index \in 1..count :
              generatedStep[index] \in [[1..(index - 1) -> SequenceSemantics] -> SequenceSemantics]
        BY SequenceNodeOutcomesAreClosed, SMT DEF generatedStep
    <1>3. PICK source \in [1..count -> SequenceSemantics] : IndexedHistory(sourceStep, source, count)
        BY <1>1, FiniteIndexedHistoryExists, SMT DEF IndexedHistory
    <1>4. PICK generated \in [1..count -> SequenceSemantics] : IndexedHistory(generatedStep, generated, count)
        BY <1>2, FiniteIndexedHistoryExists, SMT DEF IndexedHistory
    <1>5. sourceStep = SourceSteps(nodes, count) /\ generatedStep = GeneratedSteps(nodes, count)
        BY SMT DEF sourceStep, generatedStep, SourceSteps, GeneratedSteps
    <1>. QED BY <1>3, <1>4, <1>5, SMT

THEOREM EqualChildrenDischargeTheSequenceParent ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> SequenceNodes],
           ValidPostorder(nodes, count), LeafAgreement(nodes, count), NEW index \in 1..count,
           NEW history \in [1..(index - 1) -> SequenceSemantics]
    PROVE SourceNode(nodes, history, index) = GeneratedNode(nodes, history, index)
    PROOF
    <1>1. nodes[index] \in SequenceNodes BY SMT
    <1>2. nodes[index].kind # "leaf" => history[nodes[index].left] \in SequenceSemantics
        BY SMT DEF ValidPostorder
    <1>3. nodes[index].kind = "concat" => history[nodes[index].right] \in SequenceSemantics
        BY SMT DEF ValidPostorder
    <1>4. \A context \in Contexts :
              SourceNode(nodes, history, index)[context] = GeneratedNode(nodes, history, index)[context]
        <2>. SUFFICES ASSUME NEW context \in Contexts
                     PROVE SourceNode(nodes, history, index)[context] = GeneratedNode(nodes, history, index)[context]
            BY SMT
        <2>1. CASE nodes[index].kind = "leaf"
            BY <2>1, SMT DEF LeafAgreement, SourceNode, GeneratedNode
        <2>2. CASE nodes[index].kind = "append"
            BY <1>1, <1>2, <2>2, AppendRetainsValueAndFirstFailure, SMT
                DEF LeafAgreement, SequenceNodes, SequenceSemantics, ElementSemantics,
                    SourceNode, GeneratedNode
        <2>3. CASE nodes[index].kind = "concat"
            BY <1>2, <1>3, <2>3, ConcatenationRetainsValueAndFirstFailure, SMT
                DEF SequenceSemantics, SourceNode, GeneratedNode
        <2>. QED BY <1>1, <2>1, <2>2, <2>3, SMT DEF SequenceNodes
    <1>. QED BY <1>4, SMT DEF SourceNode, GeneratedNode

THEOREM FiniteSequenceTreesRetainValuesAndSelectedFailures ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> SequenceNodes],
           ValidPostorder(nodes, count), LeafAgreement(nodes, count),
           NEW source \in [1..count -> SequenceSemantics],
           NEW generated \in [1..count -> SequenceSemantics],
           IndexedHistory(SourceSteps(nodes, count), source, count),
           IndexedHistory(GeneratedSteps(nodes, count), generated, count)
    PROVE /\ source = generated
          /\ \A index \in 1..count : \A context \in Contexts :
                 /\ source[index][context].value = generated[index][context].value
                 /\ source[index][context].firstFailure = generated[index][context].firstFailure
    PROOF
    <1>1. \A index \in 1..count :
              (\A child \in 1..(index - 1) : source[child] = generated[child])
              => source[index] = generated[index]
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A child \in 1..(index - 1) : source[child] = generated[child]
                     PROVE source[index] = generated[index]
            BY SMT
        <2>1. HistoryPrefix(source, index - 1) = HistoryPrefix(generated, index - 1)
            BY SMT DEF HistoryPrefix
        <2>2. HistoryPrefix(source, index - 1) \in [1..(index - 1) -> SequenceSemantics]
            BY SMT DEF HistoryPrefix
        <2>. QED BY <2>1, <2>2, EqualChildrenDischargeTheSequenceParent, SMT
            DEF IndexedHistory, SourceSteps, GeneratedSteps
    <1>2. source = generated BY <1>1, FiniteIndexedHistoriesAgree, SMT
    <1>. QED BY <1>2, SMT

=============================================================================
