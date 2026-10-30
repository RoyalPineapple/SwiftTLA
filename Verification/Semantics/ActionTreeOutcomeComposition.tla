-------------------- MODULE ActionTreeOutcomeComposition --------------------
EXTENDS ConditionalActionRule, AlternativeActionRule,
        BranchwiseConjunctionRule, IndexedHistoryRules

ActionSemantics == [UpdateValues -> OrderedOutcome]
ActionNodes == [kind: {"leaf", "ifElse", "and", "or"}, left: Nat, right: Nat,
    sourceCondition: ConditionOutcome, generatedCondition: ConditionOutcome,
    sourceLeaf: ActionSemantics, generatedLeaf: ActionSemantics]

ValidActionPostorder(nodes, count) ==
    \A index \in 1..count :
        nodes[index].kind # "leaf" =>
            /\ nodes[index].left \in 1..(index - 1)
            /\ nodes[index].right \in 1..(index - 1)

SourceActionNode(nodes, history, index) ==
    [pending \in UpdateValues |->
        IF nodes[index].kind = "leaf" THEN nodes[index].sourceLeaf[pending]
        ELSE LET left == history[nodes[index].left]
                 right == history[nodes[index].right]
             IN IF nodes[index].kind = "ifElse"
                THEN SourceIfElse(nodes[index].sourceCondition, left[pending], right[pending])
                ELSE IF nodes[index].kind = "or" THEN SourceOr(left[pending], right[pending])
                ELSE SourceAnd(left[pending], right)]

GeneratedActionNode(nodes, history, index) ==
    [pending \in UpdateValues |->
        IF nodes[index].kind = "leaf" THEN nodes[index].generatedLeaf[pending]
        ELSE LET left == history[nodes[index].left]
                 right == history[nodes[index].right]
             IN IF nodes[index].kind = "ifElse"
                THEN GeneratedIfElse(nodes[index].generatedCondition, left[pending], right[pending])
                ELSE IF nodes[index].kind = "or" THEN CombineOrdered(left[pending], right[pending])
                ELSE ContinueBranch(left[pending], right)]

SourceActionHistory(nodes, history, count) ==
    \A index \in 1..count :
        history[index] = SourceActionNode(nodes, HistoryPrefix(history, index - 1), index)
GeneratedActionHistory(nodes, history, count) ==
    \A index \in 1..count :
        history[index] = GeneratedActionNode(nodes, HistoryPrefix(history, index - 1), index)

ActionChildPremises(nodes, source, count) ==
    \A index \in 1..count :
        /\ (nodes[index].kind = "leaf" =>
                nodes[index].sourceLeaf = nodes[index].generatedLeaf)
        /\ (nodes[index].kind = "ifElse" =>
                nodes[index].sourceCondition = nodes[index].generatedCondition)
        /\ (nodes[index].kind = "and" =>
                \A pending \in UpdateValues :
                    source[nodes[index].left][pending] \in SingleCandidateLeft)

THEOREM ActionNodeOutcomesAreClosed ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> ActionNodes],
           ValidActionPostorder(nodes, count), NEW index \in 1..count,
           NEW history \in [1..(index - 1) -> ActionSemantics]
    PROVE /\ SourceActionNode(nodes, history, index) \in ActionSemantics
          /\ GeneratedActionNode(nodes, history, index) \in ActionSemantics
    PROOF
    <1>1. nodes[index] \in ActionNodes
        BY SMT
    <1>2. nodes[index].kind # "leaf" =>
              /\ history[nodes[index].left] \in ActionSemantics
              /\ history[nodes[index].right] \in ActionSemantics
        BY SMT DEF ValidActionPostorder
    <1>3. \A pending \in UpdateValues :
              /\ SourceActionNode(nodes, history, index)[pending] \in OrderedOutcome
              /\ GeneratedActionNode(nodes, history, index)[pending] \in OrderedOutcome
        <2>. SUFFICES ASSUME NEW pending \in UpdateValues
                     PROVE /\ SourceActionNode(nodes, history, index)[pending] \in OrderedOutcome
                           /\ GeneratedActionNode(nodes, history, index)[pending] \in OrderedOutcome
            BY SMT
        <2>1. CASE nodes[index].kind = "leaf"
            BY <1>1, <2>1, SMT
                DEF SourceActionNode, GeneratedActionNode, ActionNodes, ActionSemantics
        <2>2. CASE nodes[index].kind = "ifElse"
            BY <1>1, <1>2, <2>2, ConditionalOutcomeIsClosed,
                GeneratedConditionalOutcomeIsClosed, SMT
                DEF SourceActionNode, GeneratedActionNode, ActionNodes, ActionSemantics
        <2>3. CASE nodes[index].kind = "or"
            BY <1>2, <2>3, AlternativeOutcomeIsClosed, OrderedCompositionIsClosed, SMT
                DEF SourceActionNode, GeneratedActionNode, ActionSemantics
        <2>4. CASE nodes[index].kind = "and"
            BY <1>2, <2>4, ConjunctionOutcomeIsClosed, GeneratedConjunctionOutcomeIsClosed, SMT
                DEF SourceActionNode, GeneratedActionNode, ActionSemantics
        <2>. QED BY <1>1, <2>1, <2>2, <2>3, <2>4, SMT DEF ActionNodes
    <1>. QED BY <1>3, SMT DEF ActionSemantics, SourceActionNode, GeneratedActionNode

THEOREM EveryFiniteActionTreeHasIndependentHistories ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> ActionNodes],
           ValidActionPostorder(nodes, count)
    PROVE /\ \E source \in [1..count -> ActionSemantics] : SourceActionHistory(nodes, source, count)
          /\ \E generated \in [1..count -> ActionSemantics] : GeneratedActionHistory(nodes, generated, count)
    PROOF
    <1>. DEFINE sourceStep == [index \in 1..count |->
                    [prefix \in [1..(index - 1) -> ActionSemantics] |->
                        SourceActionNode(nodes, prefix, index)]]
                generatedStep == [index \in 1..count |->
                    [prefix \in [1..(index - 1) -> ActionSemantics] |->
                        GeneratedActionNode(nodes, prefix, index)]]
    <1>1. \A index \in 1..count :
              /\ sourceStep[index] \in [[1..(index - 1) -> ActionSemantics] -> ActionSemantics]
              /\ generatedStep[index] \in [[1..(index - 1) -> ActionSemantics] -> ActionSemantics]
        BY ActionNodeOutcomesAreClosed, SMT DEF sourceStep, generatedStep
    <1>2. \E source \in [1..count -> ActionSemantics] : IndexedHistory(sourceStep, source, count)
        BY <1>1, FiniteIndexedHistoryExists, SMT DEF IndexedHistory, sourceStep, generatedStep
    <1>3. \E generated \in [1..count -> ActionSemantics] : IndexedHistory(generatedStep, generated, count)
        BY <1>1, FiniteIndexedHistoryExists, SMT DEF IndexedHistory, sourceStep, generatedStep
    <1>. QED BY <1>2, <1>3, SMT
        DEF IndexedHistory, SourceActionHistory, GeneratedActionHistory,
            sourceStep, generatedStep, HistoryPrefix

THEOREM ActionNodeRuleComposes ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> ActionNodes],
           ValidActionPostorder(nodes, count), NEW index \in 1..count,
           NEW source \in [1..count -> ActionSemantics],
           NEW generated \in [1..count -> ActionSemantics],
           ActionChildPremises(nodes, source, count),
           \A child \in 1..(index - 1) : source[child] = generated[child]
    PROVE SourceActionNode(nodes, HistoryPrefix(source, index - 1), index) =
              GeneratedActionNode(nodes, HistoryPrefix(generated, index - 1), index)
    PROOF
    <1>1. nodes[index] \in ActionNodes
        BY SMT
    <1>2. nodes[index].kind # "leaf" =>
              /\ source[nodes[index].left] = generated[nodes[index].left]
              /\ source[nodes[index].right] = generated[nodes[index].right]
              /\ source[nodes[index].left] \in ActionSemantics
              /\ source[nodes[index].right] \in ActionSemantics
        BY SMT DEF ValidActionPostorder
    <1>3. \A pending \in UpdateValues :
              SourceActionNode(nodes, HistoryPrefix(source, index - 1), index)[pending] =
                  GeneratedActionNode(nodes, HistoryPrefix(generated, index - 1), index)[pending]
        <2>. SUFFICES ASSUME NEW pending \in UpdateValues
                     PROVE SourceActionNode(nodes, HistoryPrefix(source, index - 1), index)[pending] =
                               GeneratedActionNode(nodes, HistoryPrefix(generated, index - 1), index)[pending]
            BY SMT
        <2>1. CASE nodes[index].kind = "leaf"
            BY <2>1, SMT DEF SourceActionNode, GeneratedActionNode, ActionChildPremises
        <2>2. CASE nodes[index].kind = "ifElse"
            BY <1>1, <1>2, <2>2, ConditionalRuleComposes, SMT
                DEF SourceActionNode, GeneratedActionNode, HistoryPrefix,
                    ActionChildPremises, ActionNodes, ActionSemantics, ValidActionPostorder
        <2>3. CASE nodes[index].kind = "or"
            BY <1>2, <2>3, AlternativeRuleComposes, SMT
                DEF SourceActionNode, GeneratedActionNode, HistoryPrefix,
                    ActionSemantics, ValidActionPostorder
        <2>4. CASE nodes[index].kind = "and"
            BY <1>2, <2>4, BranchwiseConjunctionRuleComposes, SMT
                DEF SourceActionNode, GeneratedActionNode, HistoryPrefix,
                    ActionChildPremises, ActionSemantics, ValidActionPostorder
        <2>. QED BY <1>1, <2>1, <2>2, <2>3, <2>4, SMT DEF ActionNodes
    <1>. QED BY <1>3, SMT DEF SourceActionNode, GeneratedActionNode

THEOREM FiniteActionTreesPreserveCompleteLabeledOutcomes ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> ActionNodes],
           ValidActionPostorder(nodes, count),
           NEW source \in [1..count -> ActionSemantics],
           NEW generated \in [1..count -> ActionSemantics],
           SourceActionHistory(nodes, source, count),
           GeneratedActionHistory(nodes, generated, count),
           ActionChildPremises(nodes, source, count),
           NEW fields, NEW values, NEW prior \in [fields -> values], NEW label,
           NEW finish \in [UpdateValues -> [fields -> values]]
    PROVE /\ source = generated
          /\ \A index \in 1..count : \A pending \in UpdateValues :
                 CompleteLabeledOutcome(prior, label, finish, NoFailure, source[index][pending]) =
                     CompleteLabeledOutcome(prior, label, finish, NoFailure, generated[index][pending])
    PROOF
    <1>1. \A index \in 1..count :
              ((\A child \in 1..(index - 1) : source[child] = generated[child])
               => source[index] = generated[index])
        BY ActionNodeRuleComposes, SMT DEF SourceActionHistory, GeneratedActionHistory
    <1>2. source = generated
        BY <1>1, FiniteIndexedHistoriesAgree
    <1>. QED BY <1>2, SMT

=============================================================================
