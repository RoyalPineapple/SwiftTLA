---- MODULE RenderedIntAssignmentTerms ----
EXTENDS PhysicalIntAssignmentRhsRule

\* Values come from the emitted pure TLA terms, before their guards are applied.
RenderedRhsTerms(plan, before, completed, starts, terms) ==
    /\ plan.count \in Nat \ {0}
    /\ starts[plan.count] = 1
    /\ \A index \in 1..plan.count :
        /\ terms[index] \in Int
        /\ starts[index] \in 1..index
        /\ CASE plan.kinds[index] = "literal" ->
                   /\ starts[index] = index
                   /\ terms[index] = plan.literals[index]
                [] plan.kinds[index] = "read" ->
                   /\ starts[index] = index
                   /\ terms[index] = PhysicalRhsBindings(plan, before, completed)[index]
                [] plan.kinds[index] = "add" ->
                   LET lhs == plan.left[index]
                       rhs == plan.right[index]
                   IN /\ lhs \in 1..(index - 1)
                      /\ rhs = index - 1
                      /\ starts[index] = starts[lhs]
                      /\ starts[rhs] = lhs + 1
                      /\ terms[index] = terms[lhs] + terms[rhs]
                [] OTHER -> FALSE

RenderedRhsLeavesAreTyped(plan, terms) ==
    \A node \in 1..plan.count : plan.kinds[node] # "add" => InRange(terms[node])

TermsInRange(terms, start, end) == \A node \in start..end : InRange(terms[node])

FirstOutOfRangeTerm(terms, start, end, node) ==
    /\ node \in start..end
    /\ TermsInRange(terms, start, node - 1)
    /\ ~InRange(terms[node])

RenderedTermOverflow(plan, terms, node) ==
    GeneratedOverflow(terms[plan.left[node]], terms[plan.right[node]])

THEOREM PhysicalTreeTermsDetermineTheFirstReachedSubexpression ==
    ASSUME NEW plan, NEW before, NEW completed, NEW starts, NEW terms, NEW history,
           RenderedRhsTerms(plan, before, completed, starts, terms), RenderedRhsLeavesAreTyped(plan, terms),
           PhysicalAssignmentRhsHistory(plan, before, completed, history)
    PROVE /\ (TermsInRange(terms, 1, plan.count) => history[plan.count] = Success(terms[plan.count]))
          /\ \A bad \in 1..plan.count : FirstOutOfRangeTerm(terms, 1, plan.count, bad) =>
                 /\ plan.kinds[bad] = "add"
                 /\ history[plan.count] = RenderedTermOverflow(plan, terms, bad)
PROOF
<1>. DEFINE meaning(index) ==
        index > 0 =>
          /\ (TermsInRange(terms, starts[index], index) => history[index] = Success(terms[index]))
          /\ \A bad \in starts[index]..index :
                FirstOutOfRangeTerm(terms, starts[index], index, bad) =>
                  /\ plan.kinds[bad] = "add"
                  /\ history[index] = RenderedTermOverflow(plan, terms, bad)
<1>count. plan.count \in Nat \ {0}
    BY ONLY RenderedRhsTerms(plan, before, completed, starts, terms) DEF RenderedRhsTerms
<1>zero. meaning(0) BY SMT DEF meaning
<1>step. ASSUME NEW index \in 1..plan.count, \A earlier \in 0..(index - 1) : meaning(earlier)
         PROVE meaning(index)
    <2>. DEFINE lhs == plan.left[index]
                rhs == plan.right[index]
                start == starts[index]
                operandsFit == InRange(terms[lhs]) /\ InRange(terms[rhs])
    <2>node. history[index] =
        GeneratedNode(index, plan.kinds, plan.literals, PhysicalRhsReadIndices(plan),
           plan.left, plan.right, PhysicalRhsBindings(plan, before, completed), history)
        BY (index \in 1..plan.count), PhysicalAssignmentRhsHistory(plan, before, completed, history), SMT
            DEF PhysicalAssignmentRhsHistory, GeneratedExpressionHistory
    <2>leaf. CASE plan.kinds[index] # "add"
        <3>facts. /\ plan.kinds[index] \in {"literal", "read"}
                  /\ start = index /\ InRange(terms[index])
                  /\ terms[index] = (IF plan.kinds[index] = "literal"
                                      THEN plan.literals[index]
                                      ELSE PhysicalRhsBindings(plan, before, completed)[index])
            BY <2>leaf, (index \in 1..plan.count), SMT DEF RenderedRhsTerms, RenderedRhsLeavesAreTyped, start
        <3>. QED BY <3>facts, <2>node, SMT
            DEF meaning, GeneratedNode, PhysicalRhsReadIndices, FirstOutOfRangeTerm
    <2>add. CASE plan.kinds[index] = "add"
        <3>parts. /\ lhs \in 1..(index - 1) /\ rhs = index - 1
                  /\ start = starts[lhs] /\ starts[rhs] = lhs + 1
                  /\ starts[lhs] \in 1..lhs /\ starts[rhs] \in 1..rhs
                  /\ terms[lhs] \in Int /\ terms[rhs] \in Int
                  /\ terms[index] = terms[lhs] + terms[rhs]
            BY <2>add, (index \in 1..plan.count), SMT DEF RenderedRhsTerms, lhs, rhs, start
        <3>children. /\ meaning(lhs) /\ meaning(rhs)
                     /\ history[index] = GeneratedCombine(history[lhs], history[rhs])
            BY <2>add, <2>node, <3>parts, (\A earlier \in 0..(index - 1) : meaning(earlier)), SMT
                DEF GeneratedNode, lhs, rhs
        <3>fits. TermsInRange(terms, start, index) => history[index] = Success(terms[index])
            BY <3>parts, <3>children, GeneratedAddGuardMatchesSource, SMT
                DEF meaning, start, TermsInRange, operandsFit, GeneratedCombine, GeneratedAdd, Success
        <3>fails. \A bad \in start..index : FirstOutOfRangeTerm(terms, start, index, bad) =>
                    /\ plan.kinds[bad] = "add"
                    /\ history[index] = RenderedTermOverflow(plan, terms, bad)
            <4>. SUFFICES ASSUME NEW bad \in start..index, FirstOutOfRangeTerm(terms, start, index, bad)
                PROVE /\ plan.kinds[bad] = "add" /\ history[index] = RenderedTermOverflow(plan, terms, bad)
                OBVIOUS
            <4>left. CASE bad <= lhs
                BY <4>left, <3>parts, <3>children, FirstOutOfRangeTerm(terms, start, index, bad), SMT
                    DEF FirstOutOfRangeTerm, meaning, RenderedTermOverflow, GeneratedCombine, GeneratedOverflow
            <4>right. CASE lhs < bad /\ bad <= rhs
                BY <4>right, <3>parts, <3>children, FirstOutOfRangeTerm(terms, start, index, bad), SMT
                    DEF FirstOutOfRangeTerm, TermsInRange, meaning, RenderedTermOverflow,
                        GeneratedCombine, GeneratedOverflow, Success
            <4>root. CASE bad = index
                BY <4>root, <3>parts, <3>children, <2>add, FirstOutOfRangeTerm(terms, start, index, bad),
                    GeneratedAddGuardMatchesSource, SMT DEF FirstOutOfRangeTerm, TermsInRange, meaning,
                    RenderedTermOverflow, GeneratedCombine, GeneratedAdd, Success
            <4>partition. bad <= lhs \/ (lhs < bad /\ bad <= rhs) \/ bad = index
                <5>index. index \in Nat
                    BY ONLY <1>count, (index \in 1..plan.count), SMT
                <5>rhs. rhs = index - 1
                    BY ONLY <3>parts
                <5>lhs. lhs \in Int
                    BY ONLY <5>index, <3>parts, SMT
                <5>start. start \in Int
                    BY ONLY <5>lhs, <3>parts, SMT
                <5>bad. bad \in Int /\ bad <= index
                    BY ONLY <5>start, <5>index, (bad \in start..index), SMT
                <5>. QED BY ONLY <5>index, <5>rhs, <5>lhs, <5>bad, SMT
            <4>. QED BY ONLY <4>left, <4>right, <4>root, <4>partition, PTL
        <3>. QED BY <3>fits, <3>fails, SMT DEF meaning, start
    <2>. QED BY <2>leaf, <2>add, SMT
<1>. HIDE DEF meaning
<1>all. \A index \in 0..plan.count : meaning(index)
    BY <1>count, <1>zero, <1>step, FiniteIndexedPrefixProperty, Isa
<1>. QED BY <1>count, <1>all, SMT DEF meaning, RenderedRhsTerms

RenderedRhsGuards(plan, terms, guards) ==
    \A node \in 1..plan.count :
        guards[node] =
            IF plan.kinds[node] = "add"
            THEN GeneratedAddDefined(terms[plan.left[node]], terms[plan.right[node]])
            ELSE TRUE

EveryRenderedGuardPasses(guards, end) == \A node \in 1..end : guards[node]

THEOREM RenderedGuardPrefixesSelectExactlyTheFirstOutOfRangeTerm ==
    ASSUME NEW plan, NEW before, NEW completed, NEW starts, NEW terms, NEW guards,
           RenderedRhsTerms(plan, before, completed, starts, terms), RenderedRhsLeavesAreTyped(plan, terms),
           RenderedRhsGuards(plan, terms, guards)
    PROVE \A index \in 0..plan.count :
                EveryRenderedGuardPasses(guards, index) <=> TermsInRange(terms, 1, index)
PROOF
<1>. DEFINE holds(index) == EveryRenderedGuardPasses(guards, index) <=> TermsInRange(terms, 1, index)
<1>count. plan.count \in Nat
    BY SMT DEF RenderedRhsTerms
<1>zero. holds(0)
    BY SMT DEF holds, EveryRenderedGuardPasses, TermsInRange
<1>next. ASSUME NEW index \in 1..plan.count, \A earlier \in 0..(index - 1) : holds(earlier)
         PROVE holds(index)
    <2>prior. holds(index - 1)
        BY (index \in 1..plan.count), (\A earlier \in 0..(index - 1) : holds(earlier)), SMT
    <2>node. TermsInRange(terms, 1, index - 1) => (guards[index] <=> InRange(terms[index]))
        <3>. SUFFICES ASSUME TermsInRange(terms, 1, index - 1)
                     PROVE guards[index] <=> InRange(terms[index])
            OBVIOUS
        <3>add. CASE plan.kinds[index] = "add"
            <4>. DEFINE lhs == plan.left[index]
                        rhs == plan.right[index]
            <4>operands. /\ lhs \in 1..(index - 1) /\ rhs \in 1..(index - 1)
                         /\ terms[index] = terms[lhs] + terms[rhs]
                         /\ terms[lhs] \in Int /\ terms[rhs] \in Int
                BY <3>add, (index \in 1..plan.count), SMT DEF lhs, rhs, RenderedRhsTerms
            <4>range. InRange(terms[lhs]) /\ InRange(terms[rhs])
                BY <4>operands, TermsInRange(terms, 1, index - 1), SMT DEF TermsInRange
            <4>. QED BY <3>add, <4>operands, <4>range, (index \in 1..plan.count),
                GeneratedAddGuardMatchesSource, SMT DEF lhs, rhs, RenderedRhsGuards
        <3>leaf. CASE plan.kinds[index] # "add"
            BY <3>leaf, (index \in 1..plan.count), SMT DEF RenderedRhsTerms, RenderedRhsLeavesAreTyped, RenderedRhsGuards
        <3>. QED BY <3>add, <3>leaf, SMT
    <2>. QED BY <2>prior, <2>node, (index \in 1..plan.count), SMT
        DEF holds, EveryRenderedGuardPasses, TermsInRange
<1>. HIDE DEF holds
<1>all. \A index \in 0..plan.count : holds(index)
    BY <1>count, <1>zero, <1>next, FiniteIndexedPrefixProperty, Isa
<1>. QED BY <1>all DEF holds

FirstRejectedRenderedGuard(guards, count, node) ==
    /\ node \in 1..count
    /\ EveryRenderedGuardPasses(guards, node - 1)
    /\ ~guards[node]

THEOREM RenderedReachedRhsHasCertifiedObservation ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW ordinal \in 1..Len(rows),
           NEW physical, PhysicalAssignmentReadsMatchRoutes(rows, ordinal, physical),
           NEW before \in AssignmentBindings, NEW completed \in Seq(AssignmentIntValues),
           Len(completed) = ordinal - 1, NEW terms, NEW starts, NEW guards,
           RenderedRhsTerms(physical, before, completed, starts, terms),
           RenderedRhsGuards(physical, terms, guards)
    PROVE LET result == SourceAssignmentRHS(rows[ordinal], CompletedAssignmentBindings(before, rows, completed))
          IN /\ (EveryRenderedGuardPasses(guards, physical.count) => result = Success(terms[physical.count]))
             /\ \A node \in 1..physical.count : FirstRejectedRenderedGuard(guards, physical.count, node) =>
                   /\ physical.kinds[node] = "add"
                   /\ result = RenderedTermOverflow(physical, terms, node)
PROOF
<1>. DEFINE row == rows[ordinal]
            bindings == CompletedAssignmentBindings(before, rows, completed)
            plan == AssignmentRhsPlan(row)
            outcome == SourceAssignmentRHS(row, bindings)
<1>types. /\ AssignmentRhsCertificate(row) /\ bindings \in AssignmentBindings
          /\ physical.count = plan.count /\ physical.count \in Nat \ {0}
    BY SupportedAssignmentList(rows), (ordinal \in 1..Len(rows)), (Len(completed) = ordinal - 1),
        (before \in AssignmentBindings), (completed \in Seq(AssignmentIntValues)),
        AssignmentPrefixMaterializationIsTyped, SMT DEF SupportedAssignmentList, row, bindings, plan,
            PhysicalAssignmentReadsMatchRoutes, PhysicalAssignmentOperandsMatch, RenderedRhsTerms
<1>expression. /\ PartialExpressionPlan(plan.count, plan.kinds, plan.literals, plan.reads,
                              plan.left, plan.right, Keys, bindings)
                /\ \E replay : GeneratedAssignmentRhsHistory(row, bindings, replay)
    BY <1>types, LiteralReadAddCertificateSuppliesExpressionParent, SMT
        DEF AssignmentRhsPlan, AssignmentRhsCertificate, GeneratedAssignmentRhsHistory,
            AssignmentBindings, AssignmentIntValues, plan
<1>leaves. RenderedRhsLeavesAreTyped(physical, terms)
    <2>. SUFFICES ASSUME NEW node \in 1..physical.count, physical.kinds[node] # "add"
        PROVE InRange(terms[node])
        BY SMT DEF RenderedRhsLeavesAreTyped
    <2>same. /\ physical.kinds[node] = plan.kinds[node]
              /\ (plan.kinds[node] = "literal" => physical.literals[node] = plan.literals[node])
              /\ (plan.kinds[node] = "read" =>
                    /\ plan.reads[node] \in Keys
                    /\ physical.reads[node] = DirectCopyRoutes(Keys, rows)[ordinal - 1][plan.reads[node]])
        BY <1>types, (node \in 1..physical.count), SMT DEF PhysicalAssignmentReadsMatchRoutes,
            PhysicalAssignmentOperandsMatch, row, plan
    <2>literal. CASE physical.kinds[node] = "literal"
        BY <2>literal, <2>same, <1>types, <1>expression, (node \in 1..physical.count), SMT
            DEF PartialExpressionPlan, ExpressionPlan, InRange, RenderedRhsTerms
    <2>read. CASE physical.kinds[node] = "read"
        <3>bound. terms[node] = bindings[plan.reads[node]]
            BY <2>read, <2>same, (node \in 1..physical.count), (Len(completed) = ordinal - 1), SMT
                DEF RenderedRhsTerms, PhysicalRhsBindings, bindings, CompletedAssignmentBindings, CopyMaterializedState
        <3>. QED BY <2>same, <2>read, <3>bound, <1>types, SMT DEF AssignmentBindings, AssignmentIntValues, InRange
    <2>. QED BY <2>literal, <2>read, (physical.kinds[node] # "add"), (node \in 1..physical.count), SMT
        DEF RenderedRhsTerms
<1>chosen. PICK replay : PhysicalAssignmentRhsHistory(physical, before, completed, replay)
    BY <1>types, <1>expression, (ordinal \in 1..Len(rows)), (Len(completed) = ordinal - 1),
        PhysicalAssignmentHistoryMatchesTheCertifiedRhs, SMT DEF row, bindings
<1>meaning. replay[physical.count] = outcome
    BY <1>chosen, (ordinal \in 1..Len(rows)), (Len(completed) = ordinal - 1),
        PhysicalAssignmentRhsHasCertifiedOutcome, SMT DEF row, bindings, outcome
<1>ranges. \A node \in 0..physical.count :
                   EveryRenderedGuardPasses(guards, node) <=> TermsInRange(terms, 1, node)
    BY <1>leaves, RenderedGuardPrefixesSelectExactlyTheFirstOutOfRangeTerm
<1>fails. \A node \in 1..physical.count : FirstRejectedRenderedGuard(guards, physical.count, node) =>
                FirstOutOfRangeTerm(terms, 1, physical.count, node)
    BY <1>ranges, <1>types, SMT DEF FirstRejectedRenderedGuard, EveryRenderedGuardPasses, FirstOutOfRangeTerm, TermsInRange
<1>tree. /\ (TermsInRange(terms, 1, physical.count) => replay[physical.count] = Success(terms[physical.count]))
         /\ \A node \in 1..physical.count : FirstOutOfRangeTerm(terms, 1, physical.count, node) =>
                 /\ physical.kinds[node] = "add"
                 /\ replay[physical.count] = RenderedTermOverflow(physical, terms, node)
    BY ONLY <1>chosen, <1>leaves, RenderedRhsTerms(physical, before, completed, starts, terms),
        PhysicalTreeTermsDetermineTheFirstReachedSubexpression, SMT
<1>success. EveryRenderedGuardPasses(guards, physical.count) => outcome = Success(terms[physical.count])
    BY ONLY <1>types, <1>ranges, <1>tree, <1>meaning, SMT
<1>failure. \A node \in 1..physical.count : FirstRejectedRenderedGuard(guards, physical.count, node) =>
                /\ physical.kinds[node] = "add"
                /\ outcome = RenderedTermOverflow(physical, terms, node)
    <2>. SUFFICES ASSUME NEW node \in 1..physical.count,
                         FirstRejectedRenderedGuard(guards, physical.count, node)
                 PROVE /\ physical.kinds[node] = "add"
                       /\ outcome = RenderedTermOverflow(physical, terms, node)
        OBVIOUS
    <2>bad. FirstOutOfRangeTerm(terms, 1, physical.count, node)
        BY ONLY (node \in 1..physical.count), FirstRejectedRenderedGuard(guards, physical.count, node),
            <1>fails, SMT
    <2>observed. /\ physical.kinds[node] = "add"
                 /\ replay[physical.count] = RenderedTermOverflow(physical, terms, node)
        BY ONLY (node \in 1..physical.count), <2>bad, <1>tree, SMT
    <2>. QED BY ONLY <2>observed, <1>meaning, SMT
<1>. QED BY ONLY <1>success, <1>failure DEF outcome, row, bindings

====
