-------------------- MODULE ActionTreeOutcomeComposition --------------------
EXTENDS ConditionalActionRule, AlternativeActionRule,
        BranchwiseConjunctionRule, GuardActionRule, IndexedHistoryRules, ActionFailureHistoryProjection

ActionSemantics == [UpdateValues -> OrderedOutcome]
ActionNodes == [kind: {"leaf", "guard", "ifElse", "and", "or"}, left: Nat, right: Nat,
    sourceCondition: ConditionOutcome, generatedCondition: ConditionOutcome,
    sourceLeaf: ActionSemantics, generatedLeaf: ActionSemantics]

ValidActionPostorder(nodes, count) ==
    \A index \in 1..count :
        nodes[index].kind \notin {"leaf", "guard"} =>
            /\ nodes[index].left \in 1..(index - 1)
            /\ nodes[index].right \in 1..(index - 1)

SourceActionNode(nodes, history, index) ==
    [pending \in UpdateValues |->
        IF nodes[index].kind = "leaf" THEN nodes[index].sourceLeaf[pending]
        ELSE IF nodes[index].kind = "guard"
             THEN SourceGuard(nodes[index].sourceCondition, pending)
        ELSE LET left == history[nodes[index].left]
                 right == history[nodes[index].right]
             IN IF nodes[index].kind = "ifElse"
                THEN SourceIfElse(nodes[index].sourceCondition, left[pending], right[pending])
                ELSE IF nodes[index].kind = "or" THEN SourceOr(left[pending], right[pending])
                ELSE SourceAnd(left[pending], right)]

GeneratedActionNode(nodes, history, index) ==
    [pending \in UpdateValues |->
        IF nodes[index].kind = "leaf" THEN nodes[index].generatedLeaf[pending]
        ELSE IF nodes[index].kind = "guard"
             THEN GeneratedGuard(nodes[index].generatedCondition, pending)
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
        /\ (nodes[index].kind \in {"ifElse", "guard"} =>
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
    <1>2. nodes[index].kind \notin {"leaf", "guard"} =>
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
        <2>5. CASE nodes[index].kind = "guard"
            BY <1>1, <2>5, GuardOutcomeIsASingleCandidate, SMT
                DEF SourceActionNode, GeneratedActionNode, ActionNodes,
                    SingleCandidateLeft, ActionSemantics
        <2>. QED BY <1>1, <2>1, <2>2, <2>3, <2>4, <2>5, SMT DEF ActionNodes
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
    <1>4. \E source \in [1..count -> ActionSemantics] : SourceActionHistory(nodes, source, count)
        <2>1. PICK source \in [1..count -> ActionSemantics] : IndexedHistory(sourceStep, source, count)
            BY <1>2
        <2>2. \A index \in 1..count :
                  HistoryPrefix(source, index - 1) \in [1..(index - 1) -> ActionSemantics]
            BY <2>1, SMT DEF HistoryPrefix
        <2>3. SourceActionHistory(nodes, source, count)
            BY <2>1, <2>2, SMT DEF IndexedHistory, SourceActionHistory, sourceStep
        <2>. QED BY <2>1, <2>3, SMT
    <1>5. \E generated \in [1..count -> ActionSemantics] : GeneratedActionHistory(nodes, generated, count)
        <2>1. PICK generated \in [1..count -> ActionSemantics] : IndexedHistory(generatedStep, generated, count)
            BY <1>3
        <2>2. \A index \in 1..count :
                  HistoryPrefix(generated, index - 1) \in [1..(index - 1) -> ActionSemantics]
            BY <2>1, SMT DEF HistoryPrefix
        <2>3. GeneratedActionHistory(nodes, generated, count)
            BY <2>1, <2>2, SMT DEF IndexedHistory, GeneratedActionHistory, generatedStep
        <2>. QED BY <2>1, <2>3, SMT
    <1>. QED BY <1>4, <1>5

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
    <1>2. nodes[index].kind \notin {"leaf", "guard"} =>
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
        <2>5. CASE nodes[index].kind = "guard"
            BY <1>1, <2>5, GuardRuleComposes, SMT
                DEF SourceActionNode, GeneratedActionNode, ActionChildPremises,
                    ActionNodes
        <2>. QED BY <1>1, <2>1, <2>2, <2>3, <2>4, <2>5, SMT DEF ActionNodes
    <1>. QED BY <1>3, SMT DEF SourceActionNode, GeneratedActionNode

\* FailureValues may identify structured occurrences, including the caught
\* reason and the lexical values retained before that occurrence. Sequences
\* preserve equal-payload occurrences at distinct positions.
ActionAlternativeFailureHistory(left, right) == left \o right
ActionHistoryFirstFailure(history) == IF Len(history) = 0 THEN NoFailure ELSE history[1]

THEOREM ActionAlternativeHistoryRetainsEveryOccurrenceAndItsFirstFailure ==
    ASSUME NEW left \in Seq(FailureValues), NEW right \in Seq(FailureValues),
           NoFailure \notin FailureValues
    PROVE LET history == ActionAlternativeFailureHistory(left, right)
              head(events) == ActionHistoryFirstFailure(events)
          IN /\ history \in Seq(FailureValues)
             /\ Len(history) = Len(left) + Len(right)
             /\ \A index \in 1..Len(left) : history[index] = left[index]
             /\ \A index \in 1..Len(right) : history[Len(left) + index] = right[index]
             /\ ActionFailureEventSet(history) = ActionFailureEventSet(left) \cup ActionFailureEventSet(right)
             /\ head(history) = IF head(left) = NoFailure THEN head(right) ELSE head(left)
    PROOF
    <1>. DEFINE history == ActionAlternativeFailureHistory(left, right)
                head(events) == ActionHistoryFirstFailure(events)
    <1>shape.
        /\ history \in Seq(FailureValues)
        /\ Len(history) = Len(left) + Len(right)
        /\ \A index \in 1..Len(left) : history[index] = left[index]
        /\ \A index \in 1..Len(right) : history[Len(left) + index] = right[index]
        BY ONLY (left \in Seq(FailureValues)), (right \in Seq(FailureValues)), ConcatProperties, SMT
            DEF history, ActionAlternativeFailureHistory
    <1>selection. head(history) = IF head(left) = NoFailure THEN head(right) ELSE head(left)
        <2>empty. CASE Len(left) = 0
            BY ONLY <2>empty, <1>shape, (right \in Seq(FailureValues)), LenProperties, SMT DEF head, ActionHistoryFirstFailure
        <2>nonempty. CASE Len(left) # 0
            BY ONLY <2>nonempty, <1>shape, (left \in Seq(FailureValues)),
                (NoFailure \notin FailureValues), LenProperties, ElementOfSeq, SMT DEF head, ActionHistoryFirstFailure
        <2>. QED BY ONLY <2>empty, <2>nonempty, SMT
    <1>events. ActionFailureEventSet(history) = ActionFailureEventSet(left) \cup ActionFailureEventSet(right)
        <2>domains. /\ DOMAIN history = 1..(Len(left) + Len(right))
                     /\ DOMAIN left = 1..Len(left)
                     /\ DOMAIN right = 1..Len(right)
            BY ONLY <1>shape, (left \in Seq(FailureValues)), (right \in Seq(FailureValues)), LenProperties, SMT
        <2>forward. \A index \in DOMAIN history :
            history[index] \in ActionFailureEventSet(left) \cup ActionFailureEventSet(right)
            <3>. TAKE index \in DOMAIN history
            <3>left. CASE index <= Len(left)
                BY ONLY (index \in DOMAIN history), <3>left, <2>domains, <1>shape, SMT DEF ActionFailureEventSet
            <3>right. CASE index > Len(left)
                <4>position. index - Len(left) \in DOMAIN right
                    BY ONLY (index \in DOMAIN history), <3>right, <2>domains, SMT
                <4>event. history[index] = right[index - Len(left)]
                    BY ONLY <4>position, <2>domains, <1>shape, SMT
                <4>. QED BY ONLY <4>position, <4>event, SMT DEF ActionFailureEventSet
            <3>integer. index \in Int
                BY ONLY (index \in DOMAIN history), <2>domains, SMT
            <3>length. Len(left) \in Nat
                BY ONLY (left \in Seq(FailureValues)), LenProperties, SMT
            <3>order. index <= Len(left) \/ index > Len(left)
                BY ONLY <3>integer, <3>length, SMT
            <3>branches.
                /\ (index <= Len(left) =>
                    history[index] \in ActionFailureEventSet(left) \cup ActionFailureEventSet(right))
                /\ (index > Len(left) =>
                    history[index] \in ActionFailureEventSet(left) \cup ActionFailureEventSet(right))
                BY ONLY <3>left, <3>right, Isa
            <3>. QED BY ONLY <3>order, <3>branches, PTL
        <2>backward. /\ \A index \in DOMAIN left : left[index] \in ActionFailureEventSet(history)
                     /\ \A index \in DOMAIN right : right[index] \in ActionFailureEventSet(history)
            BY ONLY <2>domains, <1>shape, SMT DEF ActionFailureEventSet
        <2>. QED BY ONLY <2>forward, <2>backward, SetExtensionality, SMT DEF ActionFailureEventSet
    <1>. QED BY ONLY <1>shape, <1>selection, <1>events

\* Independent source and emitted child histories refine an alternative
\* node only when they agree occurrence by occurrence. Old selected clients
\* retain their original result and need no child history premises.
FullAlternativeNodeOutcome(prior, label, finish, selected, left, right) ==
    [outcome |-> CompleteLabeledOutcome(prior, label, finish, NoFailure, selected),
     failures |-> ActionAlternativeFailureHistory(left, right)]

AlternativeNodeHistoryRefinement(nodes, source, generated, count, prior, label, finish) ==
    \A index \in 1..count : \A pending \in UpdateValues :
        \A left, right, nativeLeft, nativeRight \in Seq(FailureValues) :
            (/\ nodes[index].kind = "or"
             /\ NoFailure \notin FailureValues
             /\ left = nativeLeft /\ right = nativeRight
             /\ source[nodes[index].left][pending].failure = ActionHistoryFirstFailure(left)
             /\ source[nodes[index].right][pending].failure = ActionHistoryFirstFailure(right))
            => LET authored == FullAlternativeNodeOutcome(prior, label, finish, source[index][pending], left, right)
                   physical == FullAlternativeNodeOutcome(prior, label, finish,
                                   generated[index][pending], nativeLeft, nativeRight)
               IN /\ physical = authored
                  /\ Len(physical.failures) = Len(left) + Len(right)
                  /\ \A visit \in 1..Len(left) : physical.failures[visit] = left[visit]
                  /\ \A visit \in 1..Len(right) : physical.failures[Len(left) + visit] = right[visit]
                  /\ ActionFailureEventSet(physical.failures) =
                         ActionFailureEventSet(left) \cup ActionFailureEventSet(right)
                  /\ physical.outcome.selectedFailure = ActionHistoryFirstFailure(physical.failures)

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
          /\ AlternativeNodeHistoryRefinement(nodes, source, generated, count, prior, label, finish)
    PROOF
    <1>1. \A index \in 1..count :
              ((\A child \in 1..(index - 1) : source[child] = generated[child])
               => source[index] = generated[index])
        BY ActionNodeRuleComposes, SMT DEF SourceActionHistory, GeneratedActionHistory
    <1>2. source = generated
        BY <1>1, FiniteIndexedHistoriesAgree
    <1>full. AlternativeNodeHistoryRefinement(nodes, source, generated, count, prior, label, finish)
        <2>. SUFFICES \A index \in 1..count : \A pending \in UpdateValues :
                            \A left, right, nativeLeft, nativeRight \in Seq(FailureValues) :
                              (/\ nodes[index].kind = "or"
                               /\ NoFailure \notin FailureValues
                               /\ left = nativeLeft /\ right = nativeRight
                               /\ source[nodes[index].left][pending].failure = ActionHistoryFirstFailure(left)
                               /\ source[nodes[index].right][pending].failure = ActionHistoryFirstFailure(right))
                              => LET authored == FullAlternativeNodeOutcome(prior, label, finish, source[index][pending], left, right)
                                     physical == FullAlternativeNodeOutcome(prior, label, finish,
                                                     generated[index][pending], nativeLeft, nativeRight)
                                 IN /\ physical = authored
                                    /\ Len(physical.failures) = Len(left) + Len(right)
                                    /\ \A visit \in 1..Len(left) : physical.failures[visit] = left[visit]
                                    /\ \A visit \in 1..Len(right) : physical.failures[Len(left) + visit] = right[visit]
                                    /\ ActionFailureEventSet(physical.failures) =
                                           ActionFailureEventSet(left) \cup ActionFailureEventSet(right)
                                    /\ physical.outcome.selectedFailure = ActionHistoryFirstFailure(physical.failures)
            BY DEF AlternativeNodeHistoryRefinement
        <2>. TAKE index \in 1..count
        <2>. TAKE pending \in UpdateValues
        <2>. TAKE left, right, nativeLeft, nativeRight \in Seq(FailureValues)
        <2>. DEFINE authored == FullAlternativeNodeOutcome(prior, label, finish, source[index][pending], left, right)
                    physical == FullAlternativeNodeOutcome(prior, label, finish,
                                    generated[index][pending], nativeLeft, nativeRight)
        <2>. SUFFICES ASSUME nodes[index].kind = "or", NoFailure \notin FailureValues,
                             left = nativeLeft, right = nativeRight,
                             source[nodes[index].left][pending].failure = ActionHistoryFirstFailure(left),
                             source[nodes[index].right][pending].failure = ActionHistoryFirstFailure(right)
                     PROVE /\ physical = authored
                           /\ Len(physical.failures) = Len(left) + Len(right)
                           /\ \A visit \in 1..Len(left) : physical.failures[visit] = left[visit]
                           /\ \A visit \in 1..Len(right) : physical.failures[Len(left) + visit] = right[visit]
                           /\ ActionFailureEventSet(physical.failures) =
                                  ActionFailureEventSet(left) \cup ActionFailureEventSet(right)
                           /\ physical.outcome.selectedFailure = ActionHistoryFirstFailure(physical.failures)
            OBVIOUS
        <2>visited. source[index][pending] =
            SourceOr(source[nodes[index].left][pending], source[nodes[index].right][pending])
            BY ONLY SourceActionHistory(nodes, source, count), ValidActionPostorder(nodes, count),
                (nodes[index].kind = "or"), (index \in 1..count), (pending \in UpdateValues), SMT
                DEF SourceActionHistory, SourceActionNode, ValidActionPostorder, HistoryPrefix
        <2>arrays. /\ physical = authored
                   /\ physical.failures = ActionAlternativeFailureHistory(left, right)
            BY ONLY <1>2, (left = nativeLeft), (right = nativeRight), SMT
                DEF physical, authored, FullAlternativeNodeOutcome
        <2>append. LET failures == ActionAlternativeFailureHistory(left, right)
                   IN /\ failures \in Seq(FailureValues)
                      /\ Len(failures) = Len(left) + Len(right)
                      /\ \A visit \in 1..Len(left) : failures[visit] = left[visit]
                      /\ \A visit \in 1..Len(right) : failures[Len(left) + visit] = right[visit]
                      /\ ActionFailureEventSet(failures) =
                           ActionFailureEventSet(left) \cup ActionFailureEventSet(right)
                      /\ ActionHistoryFirstFailure(failures) =
                           IF ActionHistoryFirstFailure(left) = NoFailure
                           THEN ActionHistoryFirstFailure(right) ELSE ActionHistoryFirstFailure(left)
            BY ONLY (left \in Seq(FailureValues)), (right \in Seq(FailureValues)),
                (NoFailure \notin FailureValues), ActionAlternativeHistoryRetainsEveryOccurrenceAndItsFirstFailure, Isa
        <2>selected. physical.outcome.selectedFailure = ActionHistoryFirstFailure(physical.failures)
            BY ONLY (source[nodes[index].left][pending].failure = ActionHistoryFirstFailure(left)),
                (source[nodes[index].right][pending].failure = ActionHistoryFirstFailure(right)),
                <2>visited, <2>arrays, <2>append, SMT
                DEF physical, authored, FullAlternativeNodeOutcome, CompleteLabeledOutcome, SourceOr
        <2>. QED BY ONLY <2>arrays, <2>append, <2>selected, SMT
    <1>. QED BY ONLY <1>2, <1>full, SMT

THEOREM GuardChildrenDischargeTheConjunctionShapePremise ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> ActionNodes],
           ValidActionPostorder(nodes, count),
           NEW source \in [1..count -> ActionSemantics],
           SourceActionHistory(nodes, source, count), NEW index \in 1..count,
           nodes[index].kind = "and",
           nodes[nodes[index].left].kind = "guard"
    PROVE \A pending \in UpdateValues :
              source[nodes[index].left][pending] \in SingleCandidateLeft
    BY GuardOutcomeIsASingleCandidate, SMT
        DEF SourceActionHistory, SourceActionNode, ValidActionPostorder, ActionNodes

=============================================================================
