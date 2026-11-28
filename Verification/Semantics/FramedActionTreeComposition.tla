-------------------- MODULE FramedActionTreeComposition --------------------
EXTENDS PendingFrameOutcomeRule, Naturals

Tree == INSTANCE ActionTreeOutcomeComposition WITH UpdateValues <- PendingUpdates

SourceFrameSemantics(prior, frame) ==
    [pending \in PendingUpdates |-> SourcePendingFrame(prior, pending, frame)]
GeneratedFrameSemantics(prior, frame) ==
    [pending \in PendingUpdates |-> GeneratedPendingFrame(prior, pending, frame)]

THEOREM FrameLeavesDischargeTheirAgreementAndShapePremises ==
    ASSUME NEW prior \in States, NEW frame \in Vars
    PROVE /\ SourceFrameSemantics(prior, frame) \in Tree!ActionSemantics
          /\ GeneratedFrameSemantics(prior, frame) \in Tree!ActionSemantics
          /\ SourceFrameSemantics(prior, frame) = GeneratedFrameSemantics(prior, frame)
          /\ \A pending \in PendingUpdates :
                 SourceFrameSemantics(prior, frame)[pending] \in Tree!SingleCandidateLeft
    BY PendingFrameRuleComposes, SMT
        DEF SourceFrameSemantics, GeneratedFrameSemantics, Tree!ActionSemantics,
            Tree!SingleCandidateLeft, Outcomes!SingleCandidateLeft,
            Tree!OrderedOutcome, Outcomes!OrderedOutcome

\* Frame and guard leaves discharge their own premises; all others stay visible.
RemainingChildPremises(nodes, source, count, frames) ==
    \A index \in 1..count :
        /\ (nodes[index].kind = "leaf" /\ index \notin frames =>
                nodes[index].sourceLeaf = nodes[index].generatedLeaf)
        /\ (nodes[index].kind \in {"ifElse", "guard"} =>
                nodes[index].sourceCondition = nodes[index].generatedCondition)
        /\ (nodes[index].kind = "and" /\ nodes[index].left \notin frames /\
                nodes[nodes[index].left].kind # "guard" =>
                \A pending \in PendingUpdates :
                    source[nodes[index].left][pending] \in Tree!SingleCandidateLeft)

THEOREM FramesDischargeFiniteTreeChildPremises ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> Tree!ActionNodes],
           Tree!ValidActionPostorder(nodes, count),
           NEW prior \in States, NEW frames \in SUBSET (1..count),
           NEW targets \in [frames -> Vars],
           \A index \in frames :
               /\ nodes[index].kind = "leaf"
               /\ nodes[index].sourceLeaf = SourceFrameSemantics(prior, targets[index])
               /\ nodes[index].generatedLeaf = GeneratedFrameSemantics(prior, targets[index]),
           NEW source \in [1..count -> Tree!ActionSemantics],
           Tree!SourceActionHistory(nodes, source, count),
           RemainingChildPremises(nodes, source, count, frames)
    PROVE Tree!ActionChildPremises(nodes, source, count)
    PROOF
    <1>1. \A index \in frames :
              nodes[index].sourceLeaf = nodes[index].generatedLeaf
        BY FrameLeavesDischargeTheirAgreementAndShapePremises, SMT
    <1>2. \A index \in 1..count :
              nodes[index].kind = "and" =>
                  \A pending \in PendingUpdates :
                      source[nodes[index].left][pending] \in Tree!SingleCandidateLeft
        <2>. SUFFICES ASSUME NEW index \in 1..count, nodes[index].kind = "and"
                     PROVE \A pending \in PendingUpdates :
                               source[nodes[index].left][pending] \in Tree!SingleCandidateLeft
            BY SMT
        <2>1. CASE nodes[index].left \in frames
            BY <2>1, FrameLeavesDischargeTheirAgreementAndShapePremises, SMT
                DEF Tree!SourceActionHistory, Tree!SourceActionNode, SourceFrameSemantics
        <2>2. CASE nodes[nodes[index].left].kind = "guard"
            BY <2>2, Tree!GuardChildrenDischargeTheConjunctionShapePremise
        <2>3. CASE nodes[index].left \notin frames /\
                       nodes[nodes[index].left].kind # "guard"
            BY <2>3, SMT DEF RemainingChildPremises
        <2>. QED BY <2>1, <2>2, <2>3, SMT
    <1>. QED BY <1>1, <1>2, SMT DEF Tree!ActionChildPremises, RemainingChildPremises

THEOREM FiniteFramedTreesPreserveCompleteLabeledOutcomes ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> Tree!ActionNodes],
           Tree!ValidActionPostorder(nodes, count),
           NEW prior \in States, NEW frames \in SUBSET (1..count),
           NEW targets \in [frames -> Vars],
           \A index \in frames :
               /\ nodes[index].kind = "leaf"
               /\ nodes[index].sourceLeaf = SourceFrameSemantics(prior, targets[index])
               /\ nodes[index].generatedLeaf = GeneratedFrameSemantics(prior, targets[index]),
           NEW source \in [1..count -> Tree!ActionSemantics],
           NEW generated \in [1..count -> Tree!ActionSemantics],
           Tree!SourceActionHistory(nodes, source, count),
           Tree!GeneratedActionHistory(nodes, generated, count),
           RemainingChildPremises(nodes, source, count, frames),
           NEW label \in ActionLabels
    PROVE /\ source = generated
          /\ \A index \in 1..count : \A pending \in PendingUpdates :
                 Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                     source[index][pending]) =
                 Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                     generated[index][pending])
    PROOF
    <1>1. Tree!ActionChildPremises(nodes, source, count)
        BY FramesDischargeFiniteTreeChildPremises
    <1>2. Materialize(prior) \in [PendingUpdates -> States]
        BY MaterializationIsComplete
    <1>. QED BY <1>1, <1>2, Tree!FiniteActionTreesPreserveCompleteLabeledOutcomes, SMT
        DEF States, Outcomes!CompleteLabeledOutcome, Tree!CompleteLabeledOutcome

=============================================================================
