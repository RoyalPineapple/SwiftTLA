---------------- MODULE BooleanExpressionComposition ----------------
EXTENDS BooleanExpressionConstructorRules, IndexedHistoryRules

CONSTANT Contexts

ExpressionSemantics == [Contexts -> ExpressionOutcomes]
ExpressionNodes == [kind: {"leaf", "not", "and", "or", "if"},
    left: Nat, right: Nat, third: Nat,
    sourceLeaf: ExpressionSemantics, nativeLeaf: ExpressionSemantics,
    tlaLeaf: ExpressionSemantics]

ValidExpressionPostorder(nodes, count) ==
    \A index \in 1..count :
        /\ (nodes[index].kind # "leaf" => nodes[index].left \in 1..(index - 1))
        /\ (nodes[index].kind \in {"and", "or", "if"} => nodes[index].right \in 1..(index - 1))
        /\ (nodes[index].kind = "if" => nodes[index].third \in 1..(index - 1))

SourceExpressionNode(nodes, history, index) ==
    [context \in Contexts |->
        IF nodes[index].kind = "leaf" THEN nodes[index].sourceLeaf[context]
        ELSE LET left == history[nodes[index].left][context]
             IN IF nodes[index].kind = "not" THEN SourceNot(left)
                ELSE LET right == history[nodes[index].right][context]
                     IN IF nodes[index].kind = "and" THEN SourceAnd(left, right)
                        ELSE IF nodes[index].kind = "or" THEN SourceOr(left, right)
                        ELSE SourceIf(left, right, history[nodes[index].third][context])]

NativeExpressionNode(nodes, history, index) ==
    [context \in Contexts |->
        IF nodes[index].kind = "leaf" THEN nodes[index].nativeLeaf[context]
        ELSE LET left == history[nodes[index].left][context]
             IN IF nodes[index].kind = "not" THEN NativeNot(left)
                ELSE LET right == history[nodes[index].right][context]
                     IN IF nodes[index].kind = "and" THEN NativeAnd(left, right)
                        ELSE IF nodes[index].kind = "or" THEN NativeOr(left, right)
                        ELSE NativeIf(left, right, history[nodes[index].third][context])]

TLAExpressionNode(nodes, history, index) ==
    [context \in Contexts |->
        IF nodes[index].kind = "leaf" THEN nodes[index].tlaLeaf[context]
        ELSE LET left == history[nodes[index].left][context]
             IN IF nodes[index].kind = "not" THEN TLANot(left)
                ELSE LET right == history[nodes[index].right][context]
                     IN IF nodes[index].kind = "and" THEN TLAAnd(left, right)
                        ELSE IF nodes[index].kind = "or" THEN TLAOr(left, right)
                        ELSE TLAIf(left, right, history[nodes[index].third][context])]

SourceSteps(nodes, count) ==
    [index \in 1..count |-> [prefix \in [1..(index - 1) -> ExpressionSemantics] |->
        SourceExpressionNode(nodes, prefix, index)]]
NativeSteps(nodes, count) ==
    [index \in 1..count |-> [prefix \in [1..(index - 1) -> ExpressionSemantics] |->
        NativeExpressionNode(nodes, prefix, index)]]
TLASteps(nodes, count) ==
    [index \in 1..count |-> [prefix \in [1..(index - 1) -> ExpressionSemantics] |->
        TLAExpressionNode(nodes, prefix, index)]]

LeafAgreement(nodes, count) ==
    \A index \in 1..count : nodes[index].kind = "leaf" =>
        /\ nodes[index].sourceLeaf = nodes[index].nativeLeaf
        /\ nodes[index].nativeLeaf = nodes[index].tlaLeaf

THEOREM ExpressionNodeOutcomesAreClosed ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> ExpressionNodes],
           ValidExpressionPostorder(nodes, count), NEW index \in 1..count,
           NEW history \in [1..(index - 1) -> ExpressionSemantics]
    PROVE /\ SourceExpressionNode(nodes, history, index) \in ExpressionSemantics
          /\ NativeExpressionNode(nodes, history, index) \in ExpressionSemantics
          /\ TLAExpressionNode(nodes, history, index) \in ExpressionSemantics
    PROOF
    <1>1. nodes[index] \in ExpressionNodes
        BY SMT
    <1>2. nodes[index].kind # "leaf" => history[nodes[index].left] \in ExpressionSemantics
        BY SMT DEF ValidExpressionPostorder
    <1>3. nodes[index].kind \in {"and", "or", "if"} => history[nodes[index].right] \in ExpressionSemantics
        BY SMT DEF ValidExpressionPostorder
    <1>4. nodes[index].kind = "if" => history[nodes[index].third] \in ExpressionSemantics
        BY SMT DEF ValidExpressionPostorder
    <1>5. \A context \in Contexts :
              /\ SourceExpressionNode(nodes, history, index)[context] \in ExpressionOutcomes
              /\ NativeExpressionNode(nodes, history, index)[context] \in ExpressionOutcomes
              /\ TLAExpressionNode(nodes, history, index)[context] \in ExpressionOutcomes
        <2>. SUFFICES ASSUME NEW context \in Contexts
                     PROVE /\ SourceExpressionNode(nodes, history, index)[context] \in ExpressionOutcomes
                           /\ NativeExpressionNode(nodes, history, index)[context] \in ExpressionOutcomes
                           /\ TLAExpressionNode(nodes, history, index)[context] \in ExpressionOutcomes
            BY SMT
        <2>1. CASE nodes[index].kind = "leaf"
            BY <1>1, <2>1, SMT DEF ExpressionNodes, ExpressionSemantics,
                SourceExpressionNode, NativeExpressionNode, TLAExpressionNode
        <2>2. CASE nodes[index].kind = "not"
            BY <1>2, <2>2, NegationRetainsTheSelectedPayload, SMT
                DEF ExpressionSemantics, SourceExpressionNode, NativeExpressionNode, TLAExpressionNode
        <2>3. CASE nodes[index].kind = "and"
            BY <1>2, <1>3, <2>3, ConjunctionRetainsTheSelectedPayload, SMT
                DEF ExpressionSemantics, SourceExpressionNode, NativeExpressionNode, TLAExpressionNode
        <2>4. CASE nodes[index].kind = "or"
            BY <1>2, <1>3, <2>4, DisjunctionRetainsTheSelectedPayload, SMT
                DEF ExpressionSemantics, SourceExpressionNode, NativeExpressionNode, TLAExpressionNode
        <2>5. CASE nodes[index].kind = "if"
            BY <1>2, <1>3, <1>4, <2>5, ConditionalRetainsTheSelectedPayload, SMT
                DEF ExpressionSemantics, SourceExpressionNode, NativeExpressionNode, TLAExpressionNode
        <2>. QED BY <1>1, <2>1, <2>2, <2>3, <2>4, <2>5, SMT DEF ExpressionNodes
    <1>. QED BY <1>5, SMT
        DEF ExpressionSemantics, SourceExpressionNode, NativeExpressionNode, TLAExpressionNode

THEOREM EveryFiniteExpressionTreeHasIndependentHistories ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> ExpressionNodes],
           ValidExpressionPostorder(nodes, count)
    PROVE /\ \E source \in [1..count -> ExpressionSemantics] :
                 IndexedHistory(SourceSteps(nodes, count), source, count)
          /\ \E native \in [1..count -> ExpressionSemantics] :
                 IndexedHistory(NativeSteps(nodes, count), native, count)
          /\ \E tla \in [1..count -> ExpressionSemantics] :
                 IndexedHistory(TLASteps(nodes, count), tla, count)
    PROOF
    <1>. DEFINE sourceStep == [index \in 1..count |->
                    [prefix \in [1..(index - 1) -> ExpressionSemantics] |->
                        SourceExpressionNode(nodes, prefix, index)]]
                nativeStep == [index \in 1..count |->
                    [prefix \in [1..(index - 1) -> ExpressionSemantics] |->
                        NativeExpressionNode(nodes, prefix, index)]]
                tlaStep == [index \in 1..count |->
                    [prefix \in [1..(index - 1) -> ExpressionSemantics] |->
                        TLAExpressionNode(nodes, prefix, index)]]
    <1>1. \A index \in 1..count :
              sourceStep[index] \in [[1..(index - 1) -> ExpressionSemantics] -> ExpressionSemantics]
        BY ExpressionNodeOutcomesAreClosed, SMT DEF sourceStep
    <1>2. \A index \in 1..count :
              nativeStep[index] \in [[1..(index - 1) -> ExpressionSemantics] -> ExpressionSemantics]
        BY ExpressionNodeOutcomesAreClosed, SMT DEF nativeStep
    <1>3. \A index \in 1..count :
              tlaStep[index] \in [[1..(index - 1) -> ExpressionSemantics] -> ExpressionSemantics]
        BY ExpressionNodeOutcomesAreClosed, SMT DEF tlaStep
    <1>4. PICK source \in [1..count -> ExpressionSemantics] :
              IndexedHistory(sourceStep, source, count)
        BY <1>1, FiniteIndexedHistoryExists, SMT DEF IndexedHistory
    <1>5. PICK native \in [1..count -> ExpressionSemantics] :
              IndexedHistory(nativeStep, native, count)
        BY <1>2, FiniteIndexedHistoryExists, SMT DEF IndexedHistory
    <1>6. PICK tla \in [1..count -> ExpressionSemantics] :
              IndexedHistory(tlaStep, tla, count)
        BY <1>3, FiniteIndexedHistoryExists, SMT DEF IndexedHistory
    <1>7. /\ sourceStep = SourceSteps(nodes, count)
          /\ nativeStep = NativeSteps(nodes, count)
          /\ tlaStep = TLASteps(nodes, count)
        BY SMT DEF sourceStep, nativeStep, tlaStep, SourceSteps, NativeSteps, TLASteps
    <1>. QED BY <1>4, <1>5, <1>6, <1>7, SMT

THEOREM EqualChildrenDischargeTheParentRule ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> ExpressionNodes],
           ValidExpressionPostorder(nodes, count), LeafAgreement(nodes, count),
           NEW index \in 1..count,
           NEW history \in [1..(index - 1) -> ExpressionSemantics]
    PROVE /\ SourceExpressionNode(nodes, history, index) = NativeExpressionNode(nodes, history, index)
          /\ SourceExpressionNode(nodes, history, index) = TLAExpressionNode(nodes, history, index)
    PROOF
    <1>1. nodes[index] \in ExpressionNodes
        BY SMT
    <1>2. nodes[index].kind # "leaf" => history[nodes[index].left] \in ExpressionSemantics
        BY SMT DEF ValidExpressionPostorder
    <1>3. nodes[index].kind \in {"and", "or", "if"} => history[nodes[index].right] \in ExpressionSemantics
        BY SMT DEF ValidExpressionPostorder
    <1>4. nodes[index].kind = "if" => history[nodes[index].third] \in ExpressionSemantics
        BY SMT DEF ValidExpressionPostorder
    <1>5. \A context \in Contexts :
              /\ SourceExpressionNode(nodes, history, index)[context] = NativeExpressionNode(nodes, history, index)[context]
              /\ SourceExpressionNode(nodes, history, index)[context] = TLAExpressionNode(nodes, history, index)[context]
        <2>. SUFFICES ASSUME NEW context \in Contexts
                     PROVE /\ SourceExpressionNode(nodes, history, index)[context] = NativeExpressionNode(nodes, history, index)[context]
                           /\ SourceExpressionNode(nodes, history, index)[context] = TLAExpressionNode(nodes, history, index)[context]
            BY SMT
        <2>1. CASE nodes[index].kind = "leaf"
            BY <2>1, SMT DEF LeafAgreement, SourceExpressionNode, NativeExpressionNode, TLAExpressionNode
        <2>2. CASE nodes[index].kind = "not"
            BY <1>2, <2>2, NegationRetainsTheSelectedPayload, SMT
                DEF ExpressionSemantics, SourceExpressionNode, NativeExpressionNode, TLAExpressionNode
        <2>3. CASE nodes[index].kind = "and"
            BY <1>2, <1>3, <2>3, ConjunctionRetainsTheSelectedPayload, SMT
                DEF ExpressionSemantics, SourceExpressionNode, NativeExpressionNode, TLAExpressionNode
        <2>4. CASE nodes[index].kind = "or"
            BY <1>2, <1>3, <2>4, DisjunctionRetainsTheSelectedPayload, SMT
                DEF ExpressionSemantics, SourceExpressionNode, NativeExpressionNode, TLAExpressionNode
        <2>5. CASE nodes[index].kind = "if"
            BY <1>2, <1>3, <1>4, <2>5, ConditionalRetainsTheSelectedPayload, SMT
                DEF ExpressionSemantics, SourceExpressionNode, NativeExpressionNode, TLAExpressionNode
        <2>. QED BY <1>1, <2>1, <2>2, <2>3, <2>4, <2>5, SMT DEF ExpressionNodes
    <1>. QED BY <1>5, SMT DEF SourceExpressionNode, NativeExpressionNode, TLAExpressionNode

THEOREM FiniteBooleanExpressionsRetainValuesAndCompleteFailures ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> ExpressionNodes],
           ValidExpressionPostorder(nodes, count), LeafAgreement(nodes, count),
           NEW source \in [1..count -> ExpressionSemantics],
           NEW native \in [1..count -> ExpressionSemantics],
           NEW tla \in [1..count -> ExpressionSemantics],
           IndexedHistory(SourceSteps(nodes, count), source, count),
           IndexedHistory(NativeSteps(nodes, count), native, count),
           IndexedHistory(TLASteps(nodes, count), tla, count)
    PROVE /\ source = native /\ source = tla
          /\ \A index \in 1..count : \A context \in Contexts :
                 /\ ConditionProjection(source[index][context]) = ConditionProjection(native[index][context])
                 /\ ConditionProjection(source[index][context]) = ConditionProjection(tla[index][context])
    PROOF
    <1>1. \A index \in 1..count :
              (\A child \in 1..(index - 1) : source[child] = native[child]) => source[index] = native[index]
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A child \in 1..(index - 1) : source[child] = native[child]
                     PROVE source[index] = native[index]
            BY SMT
        <2>1. HistoryPrefix(source, index - 1) = HistoryPrefix(native, index - 1)
            BY SMT DEF HistoryPrefix
        <2>2. HistoryPrefix(source, index - 1) \in [1..(index - 1) -> ExpressionSemantics]
            BY SMT DEF HistoryPrefix
        <2>. QED BY <2>1, <2>2, EqualChildrenDischargeTheParentRule, SMT
            DEF IndexedHistory, SourceSteps, NativeSteps
    <1>2. \A index \in 1..count :
              (\A child \in 1..(index - 1) : source[child] = tla[child]) => source[index] = tla[index]
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A child \in 1..(index - 1) : source[child] = tla[child]
                     PROVE source[index] = tla[index]
            BY SMT
        <2>1. HistoryPrefix(source, index - 1) = HistoryPrefix(tla, index - 1)
            BY SMT DEF HistoryPrefix
        <2>2. HistoryPrefix(source, index - 1) \in [1..(index - 1) -> ExpressionSemantics]
            BY SMT DEF HistoryPrefix
        <2>. QED BY <2>1, <2>2, EqualChildrenDischargeTheParentRule, SMT
            DEF IndexedHistory, SourceSteps, TLASteps
    <1>3. source = native /\ source = tla
        BY <1>1, <1>2, FiniteIndexedHistoriesAgree, SMT
    <1>. QED BY <1>3, SMT

=============================================================================
