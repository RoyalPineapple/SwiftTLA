-------------------- MODULE OrderedIntAssignmentComposition --------------------
EXTENDS AssignmentTreeOutcomeComposition, Integers

CONSTANTS IntKeys, SwiftIntMin, SwiftIntMax
Expressions == INSTANCE OrderedIntExpressionRule WITH Keys <- IntKeys

IntDomains ==
    /\ SwiftIntMin \in Int /\ SwiftIntMax \in Int
    /\ SwiftIntMin <= -2000000000 /\ 2000000000 <= SwiftIntMax
    /\ IntKeys \in SUBSET Vars
    /\ SwiftIntMin..SwiftIntMax \subseteq Values
    /\ Expressions!ArithmeticFailures \subseteq FailureValues
    /\ NoFailure \notin Expressions!ArithmeticFailures

IntProjection(prior) == [key \in IntKeys |-> prior[key]]

SourceChildOutcome(result) ==
    [defined |-> result.ok, value |-> result.value,
     failure |-> IF result.ok THEN NoFailure ELSE result.failure]
GeneratedChildOutcome(result) ==
    IF result.ok THEN [defined |-> TRUE, value |-> result.value, failure |-> NoFailure]
    ELSE [defined |-> FALSE, value |-> 0, failure |-> result.failure]

THEOREM IntChildOutcomesAreTyped ==
    ASSUME IntDomains, NEW result \in Expressions!ExpressionOutcomes
    PROVE /\ SourceChildOutcome(result) \in ValueOutcomes
          /\ GeneratedChildOutcome(result) \in ValueOutcomes
    PROOF
    <1>1. 0 \in Values
        BY SMT DEF IntDomains
    <1>. QED BY <1>1, SMT
        DEF SourceChildOutcome, GeneratedChildOutcome, ValueOutcomes, IntDomains,
            Expressions!ExpressionOutcomes

THEOREM IntChildAgreementFollowsFromExpressionAgreement ==
    ASSUME IntDomains, NEW source \in Expressions!ExpressionOutcomes,
           NEW generated \in Expressions!ExpressionOutcomes, source = generated
    PROVE ChildValuesAgree(SourceChildOutcome(source), GeneratedChildOutcome(generated))
    BY SMT DEF SourceChildOutcome, GeneratedChildOutcome, ChildValuesAgree,
        Expressions!ExpressionOutcomes

THEOREM OrderedIntExpressionsSupplyCompleteAssignmentLeaves ==
    ASSUME IntDomains, NEW prior \in States, NEW target \in IntKeys, NEW label \in ActionLabels,
           NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           Expressions!ExpressionPlan(count, kinds, literals, reads, left, right, IntProjection(prior))
    PROVE \E source, generated :
              /\ Expressions!SourceExpressionHistory(count, kinds, literals, reads, left, right,
                     IntProjection(prior), source)
              /\ Expressions!GeneratedExpressionHistory(count, kinds, literals, reads, left, right,
                     IntProjection(prior), generated)
              /\ LET leaf == [target |-> target, source |-> SourceChildOutcome(source[count]),
                              generated |-> GeneratedChildOutcome(generated[count])]
                 IN /\ leaf \in AssignmentLeaves
                    /\ ChildValuesAgree(leaf.source, leaf.generated)
                    /\ SourceAssignmentSemantics(leaf) = GeneratedAssignmentSemantics(leaf)
                    /\ \A pending \in PendingUpdates :
                           SourceAssignmentObservation(prior, label, pending, target, leaf.source) =
                               Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                                   GeneratedAssignment(pending, target, leaf.generated))
    PROOF
    <1>1. PICK source, generated :
              /\ Expressions!SourceExpressionHistory(count, kinds, literals, reads, left, right,
                     IntProjection(prior), source)
              /\ Expressions!GeneratedExpressionHistory(count, kinds, literals, reads, left, right,
                     IntProjection(prior), generated)
              /\ \A index \in 0..count : Expressions!OutcomeAgrees(source, generated, index)
        BY Expressions!EveryOrderedIntExpressionPreservesOutcome, SMT DEF IntDomains
    <1>2. source[count] \in Expressions!ExpressionOutcomes /\
              generated[count] \in Expressions!ExpressionOutcomes /\ source[count] = generated[count]
        BY <1>1, Expressions!ExpressionHistoriesHaveTypedOutcomes, SMT
            DEF Expressions!ExpressionPlan, Expressions!OutcomeAgrees, IntDomains
    <1>. DEFINE leaf == [target |-> target, source |-> SourceChildOutcome(source[count]),
                        generated |-> GeneratedChildOutcome(generated[count])]
    <1>3. leaf \in AssignmentLeaves /\ ChildValuesAgree(leaf.source, leaf.generated)
        BY <1>2, IntChildOutcomesAreTyped, IntChildAgreementFollowsFromExpressionAgreement, SMT
            DEF leaf, AssignmentLeaves, IntDomains
    <1>4. SourceAssignmentSemantics(leaf) = GeneratedAssignmentSemantics(leaf)
        BY <1>3, AssignmentLeavesDischargeTheirAgreementAndShapePremises, SMT
    <1>5. \A pending \in PendingUpdates :
              SourceAssignmentObservation(prior, label, pending, target, leaf.source) =
                  Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                      GeneratedAssignment(pending, target, leaf.generated))
        BY <1>3, AssignmentPreservesCompleteLabeledOutcomes, SMT DEF leaf, AssignmentLeaves
    <1>. QED BY <1>1, <1>3, <1>4, <1>5, SMT DEF leaf

THEOREM DroppingAnOverflowBreaksTheChildPremise ==
    ASSUME IntDomains, NEW result \in Expressions!ExpressionOutcomes, ~result.ok
    PROVE ~ChildValuesAgree(SourceChildOutcome(result),
                [defined |-> FALSE, value |-> 0, failure |-> NoFailure])
    BY SMT DEF ChildValuesAgree, SourceChildOutcome, IntDomains, Expressions!ExpressionOutcomes

THEOREM ReversingOverflowOperandsBreaksTheChildPremise ==
    ASSUME IntDomains, NEW left \in SwiftIntMin..SwiftIntMax,
           NEW right \in SwiftIntMin..SwiftIntMax, left # right,
           ~Expressions!InRange(left + right)
    PROVE ~ChildValuesAgree(SourceChildOutcome(Expressions!SourceAdd(left, right)),
                [defined |-> FALSE, value |-> 0,
                 failure |-> <<"integerOverflow", "addition", <<right, left>>>>])
    BY SMT DEF ChildValuesAgree, SourceChildOutcome, Expressions!SourceAdd,
        Expressions!SourceOverflow

=============================================================================
