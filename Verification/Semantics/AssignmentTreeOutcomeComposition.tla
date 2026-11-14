-------------------- MODULE AssignmentTreeOutcomeComposition --------------------
EXTENDS FramedActionTreeComposition, AssignmentActionRule

AssignmentLeaves == [target: Vars, source: ValueOutcomes, generated: ValueOutcomes]
SourceAssignmentSemantics(leaf) ==
    [pending \in PendingUpdates |-> SourceAssignment(pending, leaf.target, leaf.source)]
GeneratedAssignmentSemantics(leaf) ==
    [pending \in PendingUpdates |-> GeneratedAssignment(pending, leaf.target, leaf.generated)]

THEOREM AssignmentLeavesDischargeTheirAgreementAndShapePremises ==
    ASSUME NEW leaf \in AssignmentLeaves, ChildValuesAgree(leaf.source, leaf.generated)
    PROVE /\ SourceAssignmentSemantics(leaf) \in Tree!ActionSemantics
          /\ GeneratedAssignmentSemantics(leaf) \in Tree!ActionSemantics
          /\ SourceAssignmentSemantics(leaf) = GeneratedAssignmentSemantics(leaf)
          /\ \A pending \in PendingUpdates :
                 SourceAssignmentSemantics(leaf)[pending] \in Tree!SingleCandidateLeft
    BY AssignmentRuleComposes, SMT
        DEF SourceAssignmentSemantics, GeneratedAssignmentSemantics, AssignmentLeaves,
            Tree!ActionSemantics, Tree!SingleCandidateLeft, Outcomes!SingleCandidateLeft,
            Tree!OrderedOutcome, Outcomes!OrderedOutcome

AssignmentsMatchNodes(nodes, assigned, leaves) ==
    \A index \in assigned :
        /\ nodes[index].kind = "leaf"
        /\ nodes[index].sourceLeaf = SourceAssignmentSemantics(leaves[index])
        /\ nodes[index].generatedLeaf = GeneratedAssignmentSemantics(leaves[index])
        /\ ChildValuesAgree(leaves[index].source, leaves[index].generated)

RemainingAssignmentPremises(nodes, source, count, frames, assigned) ==
    \A index \in 1..count :
        /\ (nodes[index].kind = "leaf" /\ index \notin frames \cup assigned =>
                nodes[index].sourceLeaf = nodes[index].generatedLeaf)
        /\ (nodes[index].kind \in {"ifElse", "guard"} =>
                nodes[index].sourceCondition = nodes[index].generatedCondition)
        /\ (nodes[index].kind = "and" /\ nodes[index].left \notin frames \cup assigned /\
                nodes[nodes[index].left].kind # "guard" =>
                \A pending \in PendingUpdates :
                    source[nodes[index].left][pending] \in Tree!SingleCandidateLeft)

THEOREM AssignmentsDischargeRemainingFrameTreePremises ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> Tree!ActionNodes],
           Tree!ValidActionPostorder(nodes, count), NEW frames \in SUBSET (1..count),
           NEW assigned \in SUBSET (1..count), NEW leaves \in [assigned -> AssignmentLeaves],
           AssignmentsMatchNodes(nodes, assigned, leaves),
           NEW source \in [1..count -> Tree!ActionSemantics],
           Tree!SourceActionHistory(nodes, source, count),
           RemainingAssignmentPremises(nodes, source, count, frames, assigned)
    PROVE RemainingChildPremises(nodes, source, count, frames)
    PROOF
    <1>1. \A index \in assigned :
              nodes[index].sourceLeaf = nodes[index].generatedLeaf
        BY AssignmentLeavesDischargeTheirAgreementAndShapePremises, SMT
            DEF AssignmentsMatchNodes
    <1>2. \A index \in 1..count :
              nodes[index].kind = "and" /\ nodes[index].left \in assigned =>
                  \A pending \in PendingUpdates :
                      source[nodes[index].left][pending] \in Tree!SingleCandidateLeft
        BY AssignmentLeavesDischargeTheirAgreementAndShapePremises, SMT
            DEF AssignmentsMatchNodes, Tree!SourceActionHistory, Tree!SourceActionNode
    <1>. QED BY <1>1, <1>2, SMT DEF RemainingChildPremises, RemainingAssignmentPremises

THEOREM FiniteAssignmentAndFrameTreesPreserveCompleteLabeledOutcomes ==
    ASSUME NEW count \in Nat, NEW nodes \in [1..count -> Tree!ActionNodes],
           Tree!ValidActionPostorder(nodes, count),
           NEW prior \in States, NEW frames \in SUBSET (1..count),
           NEW targets \in [frames -> Vars],
           \A index \in frames :
               /\ nodes[index].kind = "leaf"
               /\ nodes[index].sourceLeaf = SourceFrameSemantics(prior, targets[index])
               /\ nodes[index].generatedLeaf = GeneratedFrameSemantics(prior, targets[index]),
           NEW assigned \in SUBSET (1..count), NEW leaves \in [assigned -> AssignmentLeaves],
           AssignmentsMatchNodes(nodes, assigned, leaves),
           NEW source \in [1..count -> Tree!ActionSemantics],
           NEW generated \in [1..count -> Tree!ActionSemantics],
           Tree!SourceActionHistory(nodes, source, count),
           Tree!GeneratedActionHistory(nodes, generated, count),
           RemainingAssignmentPremises(nodes, source, count, frames, assigned),
           NEW label \in ActionLabels
    PROVE /\ source = generated
          /\ \A index \in 1..count : \A pending \in PendingUpdates :
                 Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                     source[index][pending]) =
                 Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                     generated[index][pending])
    PROOF
    <1>1. RemainingChildPremises(nodes, source, count, frames)
        BY AssignmentsDischargeRemainingFrameTreePremises
    <1>. QED BY <1>1, FiniteFramedTreesPreserveCompleteLabeledOutcomes

=============================================================================
