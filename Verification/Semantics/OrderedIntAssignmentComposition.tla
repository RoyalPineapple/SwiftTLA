-------------------- MODULE OrderedIntAssignmentComposition --------------------
EXTENDS AssignmentTreeOutcomeComposition, Integers

CONSTANTS IntKeys, SwiftIntMin, SwiftIntMax
Expressions == INSTANCE OrderedIntExpressionRule WITH Keys <- IntKeys
Membership == INSTANCE FiniteSetMembershipRule

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
    <1>1. 0 \in SwiftIntMin..SwiftIntMax
        BY SMT DEF IntDomains
    <1>2. 0 \in Values
        BY <1>1, SMT DEF IntDomains
    <1>. QED BY <1>2, SMT
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

\* A query's Boolean value and full child payload feed the existing action rule.

THEOREM RangeDomainMeaningAgreesWithOrderedIntSource ==
    ASSUME NEW lower \in Int, NEW upper \in Int
    PROVE Membership!SourceRangeDomain(Membership!QueryValue(lower), Membership!QueryValue(upper)).value
              = Expressions!SourceIntRangeMembers(lower, upper)
    BY SMT DEF Membership!SourceRangeDomain, Membership!QueryValue, Expressions!SourceIntRangeMembers


QueryChildOutcome(result) ==
    [defined |-> result.defined, value |-> result.value,
     failure |-> IF result.defined THEN NoFailure ELSE result.firstFailure]

THEOREM QueryResultSuppliesATypedAssignmentChild ==
    ASSUME NEW failures, failures \in SUBSET FailureValues,
           NoFailure \notin failures, BOOLEAN \subseteq Values,
           NEW result \in Membership!QueryResultOutcomes(failures)
    PROVE QueryChildOutcome(result) \in ValueOutcomes
    BY SMT DEF QueryChildOutcome, ValueOutcomes, Membership!QueryResultOutcomes

THEOREM RangeQueriesSupplyCompleteLabeledAssignmentOutcomes ==
    ASSUME NEW failures, failures \in SUBSET FailureValues,
           NoFailure \notin failures, BOOLEAN \subseteq Values,
           NEW prior \in States, NEW target \in Vars, NEW label \in ActionLabels,
           NEW sourceLower \in Membership!IntOperandOutcomes(failures),
           NEW sourceUpper \in Membership!IntOperandOutcomes(failures),
           NEW sourceCandidate \in Membership!IntOperandOutcomes(failures),
           NEW nativeLower \in Membership!IntOperandOutcomes(failures),
           NEW nativeUpper \in Membership!IntOperandOutcomes(failures),
           NEW nativeCandidate \in Membership!IntOperandOutcomes(failures),
           Membership!OperandOutcomesAgree(sourceLower, nativeLower),
           Membership!OperandOutcomesAgree(sourceUpper, nativeUpper),
           Membership!OperandOutcomesAgree(sourceCandidate, nativeCandidate)
    PROVE LET source == Membership!SourceDomainQuery(
                            Membership!SourceRangeDomain(sourceLower, sourceUpper), sourceCandidate)
              native == Membership!NativeDomainQuery(
                            Membership!NativeRangeDomain(nativeLower, nativeUpper), nativeCandidate)
              leaf == [target |-> target, source |-> QueryChildOutcome(source),
                       generated |-> QueryChildOutcome(native)]
          IN /\ leaf \in AssignmentLeaves
             /\ ChildValuesAgree(leaf.source, leaf.generated)
             /\ SourceAssignmentSemantics(leaf) = GeneratedAssignmentSemantics(leaf)
             /\ \A pending \in PendingUpdates :
                    SourceAssignmentObservation(prior, label, pending, target, leaf.source)
                        = Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                            GeneratedAssignment(pending, target, leaf.generated))
    PROOF
    <1>. DEFINE source == Membership!SourceDomainQuery(
                            Membership!SourceRangeDomain(sourceLower, sourceUpper), sourceCandidate)
                native == Membership!NativeDomainQuery(
                            Membership!NativeRangeDomain(nativeLower, nativeUpper), nativeCandidate)
                leaf == [target |-> target, source |-> QueryChildOutcome(source),
                         generated |-> QueryChildOutcome(native)]
    <1>1. /\ source \in Membership!QueryResultOutcomes(failures)
          /\ native \in Membership!QueryResultOutcomes(failures)
          /\ source = native
        BY Membership!RangeQueriesComposeCompleteValueAndFailurePayload
            DEF source, native
    <1>2. leaf \in AssignmentLeaves /\ ChildValuesAgree(leaf.source, leaf.generated)
        BY <1>1, QueryResultSuppliesATypedAssignmentChild, SMT
            DEF leaf, AssignmentLeaves, ChildValuesAgree, QueryChildOutcome,
                Membership!QueryResultOutcomes, ValueOutcomes
    <1>3. SourceAssignmentSemantics(leaf) = GeneratedAssignmentSemantics(leaf)
        BY <1>2, AssignmentLeavesDischargeTheirAgreementAndShapePremises
    <1>4. \A pending \in PendingUpdates :
              SourceAssignmentObservation(prior, label, pending, target, leaf.source)
                  = Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                      GeneratedAssignment(pending, target, leaf.generated))
        BY <1>2, AssignmentPreservesCompleteLabeledOutcomes, SMT DEF leaf, AssignmentLeaves
    <1>. QED BY <1>2, <1>3, <1>4, SMT DEF leaf, source, native

THEOREM FiniteDomainQueriesSupplyCompleteLabeledAssignmentLeaves ==
    ASSUME NEW failures, failures \in SUBSET FailureValues,
           NoFailure \notin failures, BOOLEAN \subseteq Values,
           NEW prior \in States, NEW target \in Vars, NEW label \in ActionLabels,
           NEW count \in Nat \ {0}, NEW nodes \in [1..count -> Membership!DomainNodes(failures)],
           Membership!ValidDomainPostorder(nodes, count), Membership!DomainLeafAgreement(nodes, count)
    PROVE \E source \in [1..count -> Membership!SourceDomainOutcomes(failures)],
              native \in [1..count -> Membership!NativeDomainOutcomes(failures)] :
              /\ Membership!IndexedHistory(Membership!SourceDomainSteps(failures, nodes, count), source, count)
              /\ Membership!IndexedHistory(Membership!NativeDomainSteps(failures, nodes, count), native, count)
              /\ \A sourceCandidate, nativeCandidate \in Membership!IntOperandOutcomes(failures) :
                     Membership!OperandOutcomesAgree(sourceCandidate, nativeCandidate) =>
                         LET sourceResult == Membership!SourceDomainQuery(source[count], sourceCandidate)
                             nativeResult == Membership!NativeDomainQuery(native[count], nativeCandidate)
                             leaf == [target |-> target, source |-> QueryChildOutcome(sourceResult),
                                      generated |-> QueryChildOutcome(nativeResult)]
                         IN /\ leaf \in AssignmentLeaves
                            /\ ChildValuesAgree(leaf.source, leaf.generated)
                            /\ SourceAssignmentSemantics(leaf) = GeneratedAssignmentSemantics(leaf)
                            /\ \A pending \in PendingUpdates :
                                   SourceAssignmentObservation(prior, label, pending, target, leaf.source)
                                       = Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                                           GeneratedAssignment(pending, target, leaf.generated))
    PROOF
    <1>1. PICK source \in [1..count -> Membership!SourceDomainOutcomes(failures)],
               native \in [1..count -> Membership!NativeDomainOutcomes(failures)] :
               /\ Membership!IndexedHistory(Membership!SourceDomainSteps(failures, nodes, count), source, count)
               /\ Membership!IndexedHistory(Membership!NativeDomainSteps(failures, nodes, count), native, count)
               /\ \A sourceCandidate, nativeCandidate \in Membership!IntOperandOutcomes(failures) :
                      Membership!OperandOutcomesAgree(sourceCandidate, nativeCandidate) =>
                          /\ Membership!SourceDomainQuery(source[count], sourceCandidate)
                                \in Membership!QueryResultOutcomes(failures)
                          /\ Membership!NativeDomainQuery(native[count], nativeCandidate)
                                \in Membership!QueryResultOutcomes(failures)
                          /\ Membership!SourceDomainQuery(source[count], sourceCandidate)
                                = Membership!NativeDomainQuery(native[count], nativeCandidate)
        BY Membership!EveryFiniteDomainTreePreservesItsRootQuery
    <1>2. \A sourceCandidate, nativeCandidate \in Membership!IntOperandOutcomes(failures) :
              Membership!OperandOutcomesAgree(sourceCandidate, nativeCandidate) =>
                  LET sourceResult == Membership!SourceDomainQuery(source[count], sourceCandidate)
                      nativeResult == Membership!NativeDomainQuery(native[count], nativeCandidate)
                      leaf == [target |-> target, source |-> QueryChildOutcome(sourceResult),
                               generated |-> QueryChildOutcome(nativeResult)]
                  IN /\ leaf \in AssignmentLeaves
                     /\ ChildValuesAgree(leaf.source, leaf.generated)
                     /\ SourceAssignmentSemantics(leaf) = GeneratedAssignmentSemantics(leaf)
                     /\ \A pending \in PendingUpdates :
                            SourceAssignmentObservation(prior, label, pending, target, leaf.source)
                                = Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                                    GeneratedAssignment(pending, target, leaf.generated))
        <2>. SUFFICES ASSUME NEW sourceCandidate \in Membership!IntOperandOutcomes(failures),
                            NEW nativeCandidate \in Membership!IntOperandOutcomes(failures),
                            Membership!OperandOutcomesAgree(sourceCandidate, nativeCandidate)
                     PROVE LET sourceResult == Membership!SourceDomainQuery(source[count], sourceCandidate)
                               nativeResult == Membership!NativeDomainQuery(native[count], nativeCandidate)
                               leaf == [target |-> target, source |-> QueryChildOutcome(sourceResult),
                                        generated |-> QueryChildOutcome(nativeResult)]
                           IN /\ leaf \in AssignmentLeaves
                              /\ ChildValuesAgree(leaf.source, leaf.generated)
                              /\ SourceAssignmentSemantics(leaf) = GeneratedAssignmentSemantics(leaf)
                              /\ \A pending \in PendingUpdates :
                                     SourceAssignmentObservation(prior, label, pending, target, leaf.source)
                                         = Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                                             GeneratedAssignment(pending, target, leaf.generated))
            BY SMT
        <2>. DEFINE sourceResult == Membership!SourceDomainQuery(source[count], sourceCandidate)
                    nativeResult == Membership!NativeDomainQuery(native[count], nativeCandidate)
                    leaf == [target |-> target, source |-> QueryChildOutcome(sourceResult),
                             generated |-> QueryChildOutcome(nativeResult)]
        <2>1. /\ sourceResult \in Membership!QueryResultOutcomes(failures)
              /\ nativeResult \in Membership!QueryResultOutcomes(failures)
              /\ sourceResult = nativeResult
            BY <1>1, SMT DEF sourceResult, nativeResult
        <2>2. leaf \in AssignmentLeaves /\ ChildValuesAgree(leaf.source, leaf.generated)
            BY <2>1, QueryResultSuppliesATypedAssignmentChild, SMT
                DEF leaf, AssignmentLeaves, ChildValuesAgree, QueryChildOutcome,
                    Membership!QueryResultOutcomes, ValueOutcomes
        <2>3. SourceAssignmentSemantics(leaf) = GeneratedAssignmentSemantics(leaf)
            BY <2>2, AssignmentLeavesDischargeTheirAgreementAndShapePremises
        <2>4. \A pending \in PendingUpdates :
                  SourceAssignmentObservation(prior, label, pending, target, leaf.source)
                      = Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                          GeneratedAssignment(pending, target, leaf.generated))
            BY <2>2, AssignmentPreservesCompleteLabeledOutcomes, SMT DEF leaf, AssignmentLeaves
        <2>. QED BY <2>2, <2>3, <2>4, SMT DEF sourceResult, nativeResult, leaf
    <1>. QED BY <1>1, <1>2, SMT


THEOREM DomainEqualityQueriesSupplyCompleteLabeledAssignmentOutcomes ==
    ASSUME IntDomains, NEW domainFirst \in BOOLEAN, NEW failures, failures \in SUBSET FailureValues,
           NoFailure \notin failures, BOOLEAN \subseteq Values,
           NEW prior \in States, NEW target \in Vars, NEW label \in ActionLabels,
           NEW sourceLower \in Membership!IntOperandOutcomes(failures),
           NEW sourceUpper \in Membership!IntOperandOutcomes(failures),
           NEW sourceDomain \in Membership!FiniteDomainOperands(failures),
           NEW nativeLower \in Membership!IntOperandOutcomes(failures),
           NEW nativeUpper \in Membership!IntOperandOutcomes(failures),
           NEW nativeDomain \in Membership!FiniteDomainOperands(failures),
           Membership!OperandOutcomesAgree(sourceLower, nativeLower),
           Membership!OperandOutcomesAgree(sourceUpper, nativeUpper),
           Membership!OperandOutcomesAgree(sourceDomain, nativeDomain),
           nativeLower.defined => nativeLower.value \in SwiftIntMin..SwiftIntMax,
           nativeUpper.defined => nativeUpper.value \in SwiftIntMin..SwiftIntMax
    PROVE LET source == Membership!SourceDomainRangeEqualityOutcome(
                            sourceDomain, sourceLower, sourceUpper, domainFirst)
              native == Membership!GeneratedDomainRangeEqualityOutcome(
                            nativeDomain, nativeLower, nativeUpper, domainFirst, SwiftIntMin, SwiftIntMax)
              leaf == [target |-> target, source |-> QueryChildOutcome(source),
                       generated |-> QueryChildOutcome(native)]
          IN /\ leaf \in AssignmentLeaves
             /\ ChildValuesAgree(leaf.source, leaf.generated)
             /\ SourceAssignmentSemantics(leaf) = GeneratedAssignmentSemantics(leaf)
             /\ \A pending \in PendingUpdates :
                    SourceAssignmentObservation(prior, label, pending, target, leaf.source)
                        = Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                            GeneratedAssignment(pending, target, leaf.generated))
    PROOF
    <1>. DEFINE source == Membership!SourceDomainRangeEqualityOutcome(
                            sourceDomain, sourceLower, sourceUpper, domainFirst)
                native == Membership!GeneratedDomainRangeEqualityOutcome(
                            nativeDomain, nativeLower, nativeUpper, domainFirst, SwiftIntMin, SwiftIntMax)
                leaf == [target |-> target, source |-> QueryChildOutcome(source),
                         generated |-> QueryChildOutcome(native)]
    <1>1. /\ source \in Membership!QueryResultOutcomes(failures)
          /\ native \in Membership!QueryResultOutcomes(failures)
          /\ source = native
        BY Membership!DomainRangeEqualityComposesValuesAndOrderedFailures, SMT
            DEF source, native, IntDomains
    <1>2. leaf \in AssignmentLeaves /\ ChildValuesAgree(leaf.source, leaf.generated)
        BY <1>1, QueryResultSuppliesATypedAssignmentChild, SMT
            DEF leaf, AssignmentLeaves, ChildValuesAgree, QueryChildOutcome,
                Membership!QueryResultOutcomes, ValueOutcomes
    <1>3. SourceAssignmentSemantics(leaf) = GeneratedAssignmentSemantics(leaf)
        BY <1>2, AssignmentLeavesDischargeTheirAgreementAndShapePremises
    <1>4. \A pending \in PendingUpdates :
              SourceAssignmentObservation(prior, label, pending, target, leaf.source)
                  = Outcomes!CompleteLabeledOutcome(prior, label, Materialize(prior), NoFailure,
                      GeneratedAssignment(pending, target, leaf.generated))
        BY <1>2, AssignmentPreservesCompleteLabeledOutcomes, SMT DEF leaf, AssignmentLeaves
    <1>. QED BY <1>2, <1>3, <1>4, SMT DEF leaf, source, native


=============================================================================
