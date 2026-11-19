-------------------- MODULE OrderedIntExpressionRule --------------------
EXTENDS TLAPS, Integers, NaturalsInduction, IndexedHistoryRules

CONSTANTS Keys, SwiftIntMin, SwiftIntMax
ASSUME IntegerDomain ==
    /\ SwiftIntMin \in Int
    /\ SwiftIntMax \in Int
    /\ SwiftIntMin <= -2000000000
    /\ 2000000000 <= SwiftIntMax

InRange(value) == value \in Int /\ SwiftIntMin <= value /\ value <= SwiftIntMax
Success(value) == [ok |-> TRUE, value |-> value,
                   failure |-> <<"none", 0, 0>>]
SourceOverflow(left, right) == [ok |-> FALSE, value |-> 0,
    failure |-> <<"integerOverflow", "addition", <<left, right>>>>]
GeneratedOverflow(left, right) == [ok |-> FALSE, value |-> 0,
    failure |-> <<"integerOverflow", "addition", <<left, right>>>>]

ArithmeticFailures ==
    {"integerOverflow"} \X {"addition"} \X
        ((SwiftIntMin..SwiftIntMax) \X (SwiftIntMin..SwiftIntMax))
ExpressionOutcomes ==
    [ok: {TRUE}, value: SwiftIntMin..SwiftIntMax, failure: {<<"none", 0, 0>>}] \cup
    [ok: {FALSE}, value: {0}, failure: ArithmeticFailures]

SourceAdd(left, right) ==
    IF InRange(left + right) THEN Success(left + right)
    ELSE SourceOverflow(left, right)

SmallAddOperands(left, right) ==
    /\ -1000000000 <= left
    /\ left <= 1000000000
    /\ -1000000000 <= right
    /\ right <= 1000000000

GeneratedAddDefined(left, right) ==
    IF SmallAddOperands(left, right) THEN TRUE
    ELSE
    IF right > 0 THEN left <= SwiftIntMax - right
    ELSE IF right < 0 THEN left >= SwiftIntMin - right
    ELSE TRUE
GeneratedAdd(left, right) ==
    IF GeneratedAddDefined(left, right) THEN Success(left + right)
    ELSE GeneratedOverflow(left, right)

THEOREM GeneratedAddGuardMatchesSource ==
    ASSUME NEW left \in Int, NEW right \in Int,
           InRange(left), InRange(right)
    PROVE GeneratedAddDefined(left, right) <=> InRange(left + right)
    PROOF
    <1>0. USE IntegerDomain DEF IntegerDomain
    <1>0a. SmallAddOperands(left, right) => InRange(left + right)
        BY SMT DEF SmallAddOperands, InRange
    <1>1. right > 0 => left + right >= SwiftIntMin
        BY SMT DEF InRange
    <1>2. right < 0 => left + right <= SwiftIntMax
        BY SMT DEF InRange
    <1>3. right > 0 =>
            (left + right <= SwiftIntMax <=> left <= SwiftIntMax - right)
        BY SMT DEF InRange
    <1>4. right < 0 =>
            (left + right >= SwiftIntMin <=> left >= SwiftIntMin - right)
        BY SMT DEF InRange
    <1>5. right = 0 => InRange(left + right)
        BY SMT DEF InRange
    <1>. QED BY <1>0a, <1>1, <1>2, <1>3, <1>4, <1>5, SMT
        DEF GeneratedAddDefined, SmallAddOperands, InRange

THEOREM CheckedAdditionRule ==
    \A left, right \in Int :
        (InRange(left) /\ InRange(right)) =>
            SourceAdd(left, right) = GeneratedAdd(left, right)
    BY GeneratedAddGuardMatchesSource, SMT
        DEF SourceAdd, GeneratedAdd, GeneratedAddDefined,
        InRange, Success, SourceOverflow, GeneratedOverflow

ExpressionPlan(count, kinds, literals, reads, left, right, state) ==
    /\ count \in Nat \ {0}
    /\ kinds \in [1..count -> {"literal", "read", "add"}]
    /\ literals \in [1..count -> SwiftIntMin..SwiftIntMax]
    /\ reads \in [1..count -> Keys]
    /\ left \in [1..count -> 0..count]
    /\ right \in [1..count -> 0..count]
    /\ state \in [Keys -> SwiftIntMin..SwiftIntMax]
    /\ \A index \in 1..count : kinds[index] = "add" =>
        /\ left[index] \in 1..(index - 1)
        /\ right[index] \in 1..(index - 1)

SourceCombine(first, second) ==
    IF ~first.ok THEN first
    ELSE IF ~second.ok THEN second
    ELSE SourceAdd(first.value, second.value)
GeneratedCombine(first, second) ==
    IF ~first.ok THEN first
    ELSE IF ~second.ok THEN second
    ELSE GeneratedAdd(first.value, second.value)

THEOREM CombinedAdditionRule ==
    ASSUME NEW first, NEW second,
           first.ok => InRange(first.value),
           second.ok => InRange(second.value)
    PROVE /\ SourceCombine(first, second) = GeneratedCombine(first, second)
          /\ (SourceCombine(first, second).ok =>
              InRange(SourceCombine(first, second).value))
    PROOF
    <1>1. CASE ~first.ok
        BY <1>1, SMT DEF SourceCombine, GeneratedCombine
    <1>2. CASE first.ok /\ ~second.ok
        BY <1>2, SMT DEF SourceCombine, GeneratedCombine
    <1>3. CASE first.ok /\ second.ok
        <2>1. InRange(first.value) /\ InRange(second.value)
            BY <1>3, SMT
        <2>2. SourceAdd(first.value, second.value)
                = GeneratedAdd(first.value, second.value)
            BY <2>1, CheckedAdditionRule, SMT DEF InRange
        <2>3. SourceAdd(first.value, second.value).ok =>
                InRange(SourceAdd(first.value, second.value).value)
            BY SMT DEF SourceAdd, Success, SourceOverflow, InRange
        <2>. QED BY <1>3, <2>2, <2>3, SMT
            DEF SourceCombine, GeneratedCombine
    <1>. QED BY <1>1, <1>2, <1>3, SMT

SourceNode(index, kinds, literals, reads, left, right, state, history) ==
    IF kinds[index] = "literal" THEN Success(literals[index])
    ELSE IF kinds[index] = "read" THEN Success(state[reads[index]])
    ELSE SourceCombine(history[left[index]], history[right[index]])

GeneratedNode(index, kinds, literals, reads, left, right, state, history) ==
    IF kinds[index] = "literal" THEN Success(literals[index])
    ELSE IF kinds[index] = "read" THEN Success(state[reads[index]])
    ELSE GeneratedCombine(history[left[index]], history[right[index]])

THEOREM ExpressionNodeRule ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, NEW source, NEW generated,
           ExpressionPlan(count, kinds, literals, reads, left, right, state),
           NEW index \in 1..count,
           \A position \in 0..(index - 1) :
               /\ source[position] = generated[position]
               /\ (source[position].ok => InRange(source[position].value))
    PROVE /\ SourceNode(index, kinds, literals, reads, left, right,
                   state, source)
               = GeneratedNode(index, kinds, literals, reads, left, right,
                   state, generated)
          /\ (SourceNode(index, kinds, literals, reads, left, right,
                   state, source).ok =>
               InRange(SourceNode(index, kinds, literals, reads, left, right,
                   state, source).value))
    PROOF
    <1>1. kinds[index] \in {"literal", "read", "add"}
        BY SMT DEF ExpressionPlan
    <1>2. CASE kinds[index] = "literal"
        BY <1>2, SMT DEF SourceNode, GeneratedNode,
            ExpressionPlan, Success, InRange
    <1>3. CASE kinds[index] = "read"
        BY <1>3, SMT DEF SourceNode, GeneratedNode,
            ExpressionPlan, Success, InRange
    <1>4. CASE kinds[index] = "add"
        <2>1. left[index] \in 0..(index - 1)
              /\ right[index] \in 0..(index - 1)
            BY <1>4, SMT DEF ExpressionPlan
        <2>2. source[left[index]] = generated[left[index]]
              /\ source[right[index]] = generated[right[index]]
              /\ (source[left[index]].ok =>
                  InRange(source[left[index]].value))
              /\ (source[right[index]].ok =>
                  InRange(source[right[index]].value))
            BY <2>1, SMT
        <2>. QED BY <1>4, <2>2, CombinedAdditionRule, SMT
            DEF SourceNode, GeneratedNode
    <1>. QED BY <1>1, <1>2, <1>3, <1>4, SMT

SourceExpressionHistory(count, kinds, literals, reads, left, right,
                        state, history) ==
    /\ history[0] = Success(0)
    /\ \A index \in 1..count : history[index] =
        SourceNode(index, kinds, literals, reads, left, right, state, history)

GeneratedExpressionHistory(count, kinds, literals, reads, left, right,
                           state, history) ==
    /\ history[0] = Success(0)
    /\ \A index \in 1..count : history[index] =
        GeneratedNode(index, kinds, literals, reads, left, right, state, history)

OutcomeAgrees(source, generated, index) ==
    /\ source[index] = generated[index]
    /\ (source[index].ok => InRange(source[index].value))

THEOREM ExpressionHistoryPreservesValueAndFirstFailure ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, NEW source, NEW generated,
           ExpressionPlan(count, kinds, literals, reads, left, right, state),
           SourceExpressionHistory(count, kinds, literals, reads, left, right,
               state, source),
           GeneratedExpressionHistory(count, kinds, literals, reads, left, right,
               state, generated)
    PROVE \A index \in 0..count : OutcomeAgrees(source, generated, index)
    PROOF
    <1>. DEFINE agrees(index) == OutcomeAgrees(source, generated, index)
    <1>1. count \in Nat
        BY SMT DEF ExpressionPlan
    <1>2. OutcomeAgrees(source, generated, 0)
        BY IntegerDomain, SMT DEF OutcomeAgrees,
            SourceExpressionHistory, GeneratedExpressionHistory,
            Success, InRange, IntegerDomain
    <1>3. \A index \in 1..count :
            (\A prior \in 0..(index - 1) :
                OutcomeAgrees(source, generated, prior))
            => OutcomeAgrees(source, generated, index)
        PROOF
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A prior \in 0..(index - 1) :
                                 OutcomeAgrees(source, generated, prior)
                     PROVE OutcomeAgrees(source, generated, index)
            BY SMT
        <2>1. source[index] = SourceNode(index,
                kinds, literals, reads, left, right, state, source)
            BY SMT DEF SourceExpressionHistory
        <2>2. generated[index] = GeneratedNode(index,
                kinds, literals, reads, left, right, state, generated)
            BY SMT DEF GeneratedExpressionHistory
        <2>. QED BY <2>1, <2>2, ExpressionNodeRule, SMT
            DEF OutcomeAgrees
    <1>4. agrees(0) /\
              \A index \in 1..count :
                  ((\A child \in 0..(index - 1) : agrees(child)) => agrees(index))
        BY <1>2, <1>3 DEF agrees
    <1>5. \A index \in 0..count : agrees(index)
        BY <1>1, <1>4, FiniteIndexedPrefixProperty
    <1>. QED BY <1>5 DEF agrees

ExpressionNode(generated, index, kinds, literals, reads, left, right,
               state, history) ==
    IF generated
    THEN GeneratedNode(index, kinds, literals, reads, left, right, state,
        history)
    ELSE SourceNode(index, kinds, literals, reads, left, right, state,
        history)

THEOREM ExpressionNodeUsesOnlyEarlierResults ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, NEW before, NEW after, NEW generated \in BOOLEAN,
           ExpressionPlan(count, kinds, literals, reads, left, right, state),
           NEW index \in 1..count,
           \A prior \in 0..(index - 1) : before[prior] = after[prior]
    PROVE ExpressionNode(generated, index, kinds, literals, reads, left,
              right, state, before)
        = ExpressionNode(generated, index, kinds, literals, reads, left,
              right, state, after)
    PROOF
    <1>1. kinds[index] \in {"literal", "read", "add"}
        BY SMT DEF ExpressionPlan
    <1>2. CASE kinds[index] = "literal"
        BY <1>2, SMT DEF ExpressionNode, SourceNode, GeneratedNode
    <1>3. CASE kinds[index] = "read"
        BY <1>3, SMT DEF ExpressionNode, SourceNode, GeneratedNode
    <1>4. CASE kinds[index] = "add"
        <2>1. left[index] \in 0..(index - 1)
              /\ right[index] \in 0..(index - 1)
            BY <1>4, SMT DEF ExpressionPlan
        <2>2. before[left[index]] = after[left[index]]
              /\ before[right[index]] = after[right[index]]
            BY <2>1, SMT
        <2>. QED BY <1>4, <2>2, SMT
            DEF ExpressionNode, SourceNode, GeneratedNode
    <1>. QED BY <1>1, <1>2, <1>3, <1>4, SMT

ExpressionPrefix(generated, upto, kinds, literals, reads, left, right,
                 state, history) ==
    /\ history[0] = Success(0)
    /\ \A index \in 1..upto : history[index] =
        ExpressionNode(generated, index, kinds, literals, reads, left,
            right, state, history)

ExtendExpressionPrefix(history, upto, value) ==
    [index \in 0..upto |-> IF index = upto THEN value ELSE history[index]]

THEOREM PrefixIndexBounds ==
    ASSUME NEW count \in Nat, NEW upto \in 0..(count - 1)
    PROVE /\ upto + 1 \in 1..count
          /\ \A index \in 1..upto : index \in 1..count
    BY SMT

THEOREM ExpressionPrefixExtension ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, NEW history, NEW generated \in BOOLEAN,
           ExpressionPlan(count, kinds, literals, reads, left, right, state),
           NEW upto \in 0..(count - 1),
           ExpressionPrefix(generated, upto, kinds, literals, reads, left,
               right, state, history)
    PROVE ExpressionPrefix(generated, upto + 1, kinds, literals, reads, left,
        right, state,
        ExtendExpressionPrefix(history, upto + 1,
            ExpressionNode(generated, upto + 1, kinds, literals, reads,
                left, right, state, history)))
    PROOF
    <1>. DEFINE extended == ExtendExpressionPrefix(history, upto + 1,
            ExpressionNode(generated, upto + 1, kinds, literals, reads,
                left, right, state, history))
    <1>0. upto + 1 \in 1..count
        BY PrefixIndexBounds, SMT DEF ExpressionPlan
    <1>1. \A index \in 0..upto : extended[index] = history[index]
        BY SMT DEF extended, ExtendExpressionPrefix
    <1>2. extended[upto + 1] = ExpressionNode(generated, upto + 1,
            kinds, literals, reads, left, right, state, history)
        BY SMT DEF extended, ExtendExpressionPrefix
    <1>3. ExpressionNode(generated, upto + 1, kinds, literals, reads, left,
            right, state, history) = ExpressionNode(generated, upto + 1,
            kinds, literals, reads, left, right, state, extended)
        BY <1>0, <1>1, ExpressionNodeUsesOnlyEarlierResults, SMT
    <1>4. extended[0] = Success(0)
        BY <1>1, SMT DEF ExpressionPrefix
    <1>5. \A index \in 1..upto : extended[index] =
            ExpressionNode(generated, index, kinds, literals, reads,
                left, right, state, extended)
        PROOF
        <2>. SUFFICES ASSUME NEW index \in 1..upto
                     PROVE extended[index] = ExpressionNode(generated,
                         index, kinds, literals, reads, left, right,
                         state, extended)
            BY SMT
        <2>1. index \in 1..count
            BY PrefixIndexBounds, SMT DEF ExpressionPlan
        <2>2. \A prior \in 0..(index - 1) :
                history[prior] = extended[prior]
            BY <1>1, SMT
        <2>3. extended[index] = history[index]
            BY <1>1, SMT
        <2>4. history[index] = ExpressionNode(generated, index,
                kinds, literals, reads, left, right, state, history)
            BY SMT DEF ExpressionPrefix
        <2>. QED BY <2>1, <2>2, <2>3, <2>4,
            ExpressionNodeUsesOnlyEarlierResults, SMT
    <1>6. extended[upto + 1] = ExpressionNode(generated, upto + 1,
            kinds, literals, reads, left, right, state, extended)
        BY <1>2, <1>3
    <1>. QED BY <1>4, <1>5, <1>6, SMT
        DEF ExpressionPrefix, extended

THEOREM PrefixPredecessorBound ==
    ASSUME NEW count \in Nat, NEW upto \in Nat,
           upto + 1 \in 0..count
    PROVE /\ upto \in 0..(count - 1)
          /\ upto \in 0..count
    BY SMT

THEOREM ExpressionPrefixHistoryExists ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, NEW generated \in BOOLEAN,
           ExpressionPlan(count, kinds, literals, reads, left, right, state)
    PROVE \E history : ExpressionPrefix(generated, count, kinds, literals,
        reads, left, right, state, history)
    PROOF
    <1>. DEFINE P(upto) ==
        upto \in 0..count =>
            \E history : ExpressionPrefix(generated, upto, kinds, literals,
                reads, left, right, state, history)
    <1>1. P(0)
        <2>. DEFINE empty == [index \in 0..0 |-> Success(0)]
        <2>1. ExpressionPrefix(generated, 0, kinds, literals, reads, left,
                right, state, empty)
            BY SMT DEF ExpressionPrefix, empty
        <2>. QED BY <2>1, SMT DEF P
    <1>2. ASSUME NEW upto \in Nat, P(upto)
          PROVE P(upto + 1)
        <2>. SUFFICES ASSUME upto + 1 \in 0..count
                     PROVE \E history : ExpressionPrefix(generated,
                         upto + 1, kinds, literals, reads, left, right,
                         state, history)
            BY SMT DEF P
        <2>1. upto \in 0..(count - 1)
              /\ upto \in 0..count
            BY PrefixPredecessorBound, SMT DEF ExpressionPlan
        <2>2. PICK history : ExpressionPrefix(generated, upto, kinds,
                literals, reads, left, right, state, history)
            BY <2>1, P(upto), SMT DEF P
        <2>3. ExpressionPrefix(generated, upto + 1, kinds, literals,
                reads, left, right, state,
                ExtendExpressionPrefix(history, upto + 1,
                    ExpressionNode(generated, upto + 1, kinds, literals,
                        reads, left, right, state, history)))
            BY <2>1, <2>2, ExpressionPrefixExtension
        <2>. QED BY <2>3, SMT
    <1>3. HIDE DEF P
    <1>4. \A upto \in Nat : P(upto)
        BY <1>1, <1>2, NatInduction
    <1>5. count \in Nat
        BY SMT DEF ExpressionPlan
    <1>. QED BY <1>4, <1>5, SMT DEF P

THEOREM BothExpressionHistoriesExist ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state,
           ExpressionPlan(count, kinds, literals, reads, left, right, state)
    PROVE \E source, generated :
        /\ SourceExpressionHistory(count, kinds, literals, reads, left,
               right, state, source)
        /\ GeneratedExpressionHistory(count, kinds, literals, reads, left,
               right, state, generated)
    PROOF
    <1>1. PICK source : ExpressionPrefix(FALSE, count, kinds, literals,
            reads, left, right, state, source)
        BY ExpressionPrefixHistoryExists, SMT
    <1>2. PICK generated : ExpressionPrefix(TRUE, count, kinds, literals,
            reads, left, right, state, generated)
        BY ExpressionPrefixHistoryExists, SMT
    <1>3. SourceExpressionHistory(count, kinds, literals, reads, left,
            right, state, source)
        BY <1>1, SMT DEF ExpressionPrefix, ExpressionNode,
            SourceExpressionHistory
    <1>4. GeneratedExpressionHistory(count, kinds, literals, reads, left,
            right, state, generated)
        BY <1>2, SMT DEF ExpressionPrefix, ExpressionNode,
            GeneratedExpressionHistory
    <1>. QED BY <1>3, <1>4, SMT

THEOREM EveryOrderedIntExpressionPreservesOutcome ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state,
           ExpressionPlan(count, kinds, literals, reads, left, right, state)
    PROVE \E source, generated :
        /\ SourceExpressionHistory(count, kinds, literals, reads, left,
               right, state, source)
        /\ GeneratedExpressionHistory(count, kinds, literals, reads, left,
               right, state, generated)
        /\ \A index \in 0..count :
               OutcomeAgrees(source, generated, index)
    PROOF
    <1>1. PICK source, generated :
            /\ SourceExpressionHistory(count, kinds, literals, reads,
                   left, right, state, source)
            /\ GeneratedExpressionHistory(count, kinds, literals, reads,
                   left, right, state, generated)
        BY BothExpressionHistoriesExist
    <1>2. \A index \in 0..count :
            OutcomeAgrees(source, generated, index)
        BY <1>1, ExpressionHistoryPreservesValueAndFirstFailure
    <1>. QED BY <1>1, <1>2, SMT

SourceAssignmentEdges(state, root, label, outcome) ==
    IF outcome.ok THEN
        {<<state, label, [state EXCEPT ![root] = outcome.value]>>}
    ELSE {}

GeneratedAssignmentEdges(state, root, label, outcome) ==
    IF outcome.ok THEN
        {<<state, label,
           [key \in Keys |-> IF key = root THEN outcome.value ELSE state[key]]>>}
    ELSE {}

SourceAssignmentFailures(state, label, outcome) ==
    IF outcome.ok THEN {} ELSE {<<state, label, outcome.failure>>}

GeneratedAssignmentFailures(state, label, outcome) ==
    IF ~outcome.ok THEN {<<state, label, outcome.failure>>} ELSE {}

THEOREM AssignmentUpdateFormsAgree ==
    ASSUME NEW state \in [Keys -> SwiftIntMin..SwiftIntMax],
           NEW root \in Keys, NEW value
    PROVE [state EXCEPT ![root] = value]
        = [key \in Keys |-> IF key = root THEN value ELSE state[key]]
    BY SMT

THEOREM AdditionOutcomesAreTyped ==
    ASSUME NEW first \in ExpressionOutcomes, NEW second \in ExpressionOutcomes
    PROVE /\ SourceCombine(first, second) \in ExpressionOutcomes
          /\ GeneratedCombine(first, second) \in ExpressionOutcomes
    PROOF
    <1>1. first.ok \in BOOLEAN /\ second.ok \in BOOLEAN
        BY SMT DEF ExpressionOutcomes
    <1>2. SourceCombine(first, second) \in ExpressionOutcomes
        <2>1. CASE ~first.ok
            BY <2>1, SMT DEF SourceCombine
        <2>2. CASE first.ok /\ ~second.ok
            BY <2>2, SMT DEF SourceCombine
        <2>3. CASE first.ok /\ second.ok
            <3>1. first.value \in SwiftIntMin..SwiftIntMax /\ second.value \in SwiftIntMin..SwiftIntMax
                BY <2>3, SMT DEF ExpressionOutcomes
            <3>2. <<"integerOverflow", "addition", <<first.value, second.value>>>> \in ArithmeticFailures
                BY <3>1, SMT DEF ArithmeticFailures
            <3>3. SourceOverflow(first.value, second.value) \in ExpressionOutcomes
                BY <3>2, SMT DEF SourceOverflow, ExpressionOutcomes
            <3>4. InRange(first.value + second.value) =>
                      Success(first.value + second.value) \in ExpressionOutcomes
                BY SMT DEF InRange, Success, ExpressionOutcomes
            <3>. QED BY <2>3, <3>3, <3>4, SMT DEF SourceCombine, SourceAdd
        <2>. QED BY <1>1, <2>1, <2>2, <2>3, SMT
    <1>3. (first.ok => InRange(first.value)) /\ (second.ok => InRange(second.value))
        BY SMT DEF ExpressionOutcomes, InRange
    <1>. QED BY <1>2, <1>3, CombinedAdditionRule, SMT

THEOREM ExpressionNodeOutcomesAreTyped ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, NEW history,
           ExpressionPlan(count, kinds, literals, reads, left, right, state),
           NEW index \in 1..count,
           \A position \in 0..(index - 1) : history[position] \in ExpressionOutcomes
    PROVE /\ SourceNode(index, kinds, literals, reads, left, right, state, history) \in ExpressionOutcomes
          /\ GeneratedNode(index, kinds, literals, reads, left, right, state, history) \in ExpressionOutcomes
    PROOF
    <1>1. CASE kinds[index] = "literal"
        BY <1>1, SMT DEF SourceNode, GeneratedNode, ExpressionPlan, Success, ExpressionOutcomes
    <1>2. CASE kinds[index] = "read"
        BY <1>2, SMT DEF SourceNode, GeneratedNode, ExpressionPlan, Success, ExpressionOutcomes
    <1>3. CASE kinds[index] = "add"
        <2>1. history[left[index]] \in ExpressionOutcomes /\ history[right[index]] \in ExpressionOutcomes
            BY <1>3, SMT DEF ExpressionPlan
        <2>. QED BY <1>3, <2>1, AdditionOutcomesAreTyped, SMT DEF SourceNode, GeneratedNode
    <1>. QED BY <1>1, <1>2, <1>3, SMT DEF ExpressionPlan

THEOREM ExpressionHistoriesHaveTypedOutcomes ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, NEW source, NEW generated,
           ExpressionPlan(count, kinds, literals, reads, left, right, state),
           SourceExpressionHistory(count, kinds, literals, reads, left, right, state, source),
           GeneratedExpressionHistory(count, kinds, literals, reads, left, right, state, generated)
    PROVE \A index \in 0..count :
              source[index] \in ExpressionOutcomes /\ generated[index] \in ExpressionOutcomes
    PROOF
    <1>. DEFINE typed(index) == source[index] \in ExpressionOutcomes /\ generated[index] \in ExpressionOutcomes
    <1>1. typed(0)
        BY IntegerDomain, SMT
            DEF typed, SourceExpressionHistory, GeneratedExpressionHistory,
                Success, ExpressionOutcomes, IntegerDomain
    <1>2. \A index \in 1..count :
              ((\A child \in 0..(index - 1) : typed(child)) => typed(index))
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A child \in 0..(index - 1) : typed(child)
                     PROVE typed(index)
            BY SMT
        <2>1. \A child \in 0..(index - 1) : source[child] \in ExpressionOutcomes
            BY SMT DEF typed
        <2>2. \A child \in 0..(index - 1) : generated[child] \in ExpressionOutcomes
            BY SMT DEF typed
        <2>3. SourceNode(index, kinds, literals, reads, left, right, state, source) \in ExpressionOutcomes
            BY <2>1, ExpressionNodeOutcomesAreTyped
        <2>4. GeneratedNode(index, kinds, literals, reads, left, right, state, generated) \in ExpressionOutcomes
            BY <2>2, ExpressionNodeOutcomesAreTyped
        <2>. QED BY <2>3, <2>4, SMT DEF typed, SourceExpressionHistory, GeneratedExpressionHistory
    <1>3. count \in Nat
        BY SMT DEF ExpressionPlan
    <1>4. \A index \in 0..count : typed(index)
        BY <1>1, <1>2, <1>3, FiniteIndexedPrefixProperty
    <1>. QED BY <1>4 DEF typed

THEOREM OrderedIntExpressionPreservesAssignmentOutcome ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state,
           ExpressionPlan(count, kinds, literals, reads, left, right, state),
           NEW root \in Keys, NEW label
    PROVE \E source, generated :
        /\ SourceExpressionHistory(count, kinds, literals, reads, left,
               right, state, source)
        /\ GeneratedExpressionHistory(count, kinds, literals, reads, left,
               right, state, generated)
        /\ SourceAssignmentEdges(state, root, label, source[count])
             = GeneratedAssignmentEdges(state, root, label, generated[count])
        /\ SourceAssignmentFailures(state, label, source[count])
             = GeneratedAssignmentFailures(state, label, generated[count])
    PROOF
    <1>1. PICK source, generated :
            /\ SourceExpressionHistory(count, kinds, literals, reads,
                   left, right, state, source)
            /\ GeneratedExpressionHistory(count, kinds, literals, reads,
                   left, right, state, generated)
            /\ \A index \in 0..count :
                   OutcomeAgrees(source, generated, index)
        BY EveryOrderedIntExpressionPreservesOutcome
    <1>2. source[count] = generated[count]
        BY <1>1, SMT DEF ExpressionPlan, OutcomeAgrees
    <1>3. [state EXCEPT ![root] = source[count].value]
            = [key \in Keys |-> IF key = root THEN generated[count].value
                ELSE state[key]]
        BY <1>2, AssignmentUpdateFormsAgree, SMT DEF ExpressionPlan
    <1>. QED BY <1>1, <1>2, <1>3, SMT
        DEF SourceAssignmentEdges, GeneratedAssignmentEdges,
            SourceAssignmentFailures, GeneratedAssignmentFailures

ExpressionReadKeys(count, kinds, reads) ==
    {reads[index] : index \in {position \in 1..count : kinds[position] = "read"}}

ReadEffectNode(index, kinds, reads, left, right, history) ==
    IF kinds[index] = "literal" THEN {}
    ELSE IF kinds[index] = "read" THEN {reads[index]}
    ELSE history[left[index]] \cup history[right[index]]

ExpressionReadHistory(count, kinds, reads, left, right, effects) ==
    /\ effects \in [1..count -> SUBSET Keys]
    /\ \A index \in 1..count : effects[index] =
        ReadEffectNode(index, kinds, reads, left, right, effects)

THEOREM ExpressionReadHistoryExists ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state,
           ExpressionPlan(count, kinds, literals, reads, left, right, state)
    PROVE \E effects : ExpressionReadHistory(count, kinds, reads, left, right, effects)
    PROOF
    <1>. DEFINE steps == [index \in 1..count |->
        [history \in [1..(index - 1) -> SUBSET Keys] |->
            ReadEffectNode(index, kinds, reads, left, right, history)]]
    <1>1. \A index \in 1..count :
        steps[index] \in [[1..(index - 1) -> SUBSET Keys] -> SUBSET Keys]
        BY SMT DEF steps, ReadEffectNode, ExpressionPlan
    <1>2. count \in Nat BY SMT DEF ExpressionPlan
    <1>3. PICK effects \in [1..count -> SUBSET Keys] :
        IndexedHistory(steps, effects, count)
        BY <1>1, <1>2, FiniteIndexedHistoryExists
    <1>4. \A index \in 1..count :
        ReadEffectNode(index, kinds, reads, left, right,
            HistoryPrefix(effects, index - 1))
        = ReadEffectNode(index, kinds, reads, left, right, effects)
        BY SMT DEF ReadEffectNode, HistoryPrefix, ExpressionPlan
    <1>5. \A index \in 1..count :
        HistoryPrefix(effects, index - 1) \in [1..(index - 1) -> SUBSET Keys]
        BY <1>2, <1>3, SMT DEF HistoryPrefix
    <1>6. \A index \in 1..count : effects[index] =
        ReadEffectNode(index, kinds, reads, left, right, effects)
        BY <1>3, <1>4, <1>5, SMT DEF IndexedHistory, steps
    <1>7. ExpressionReadHistory(count, kinds, reads, left, right, effects)
        BY <1>3, <1>6 DEF ExpressionReadHistory
    <1>. QED BY <1>7, SMT

StackReadKeys(stack, height, effects) ==
    {key \in Keys : \E position \in 1..height : key \in effects[stack[position]]}

ExpressionIndexStack(count, kinds, left, right, heights, stacks) ==
    /\ heights \in [0..count -> Nat]
    /\ heights[0] = 0
    /\ \A index \in 0..count : stacks[index] \in [1..heights[index] -> 1..index]
    /\ \A index \in 1..count :
        IF kinds[index] = "add" THEN
            /\ heights[index - 1] >= 2
            /\ stacks[index - 1][heights[index - 1] - 1] = left[index]
            /\ stacks[index - 1][heights[index - 1]] = right[index]
            /\ heights[index] = heights[index - 1] - 1
            /\ stacks[index] = HistoryAppend(stacks[index - 1],
                heights[index - 1] - 2, index)
        ELSE
            /\ heights[index] = heights[index - 1] + 1
            /\ stacks[index] = HistoryAppend(stacks[index - 1],
                heights[index - 1], index)
    /\ heights[count] = 1

\* Storage typing does not assume that an addition points to earlier nodes.
ExpressionNodeStorage(count, kinds, literals, reads, left, right, state) ==
    /\ count \in Nat \ {0}
    /\ kinds \in [1..count -> {"literal", "read", "add"}]
    /\ literals \in [1..count -> SwiftIntMin..SwiftIntMax]
    /\ reads \in [1..count -> Keys]
    /\ left \in [1..count -> Int]
    /\ right \in [1..count -> Int]
    /\ \A index \in 1..count : kinds[index] # "add" =>
        /\ left[index] = 0
        /\ right[index] = 0
    /\ state \in [Keys -> SwiftIntMin..SwiftIntMax]

THEOREM PostorderAppendPreservesIndexBounds ==
    ASSUME NEW count \in Nat, NEW height \in Nat,
           NEW stack \in [1..height -> 1..count],
           NEW retained \in 0..height
    PROVE HistoryAppend(stack, retained, count + 1)
        \in [1..(retained + 1) -> 1..(count + 1)]
    BY SMT DEF HistoryAppend

RetainedIndexCount(kind, height) == IF kind = "add" THEN height - 2 ELSE height

\* These are the actual prefix removal and append operations, without an index-bound premise.
PostorderIndexOperations(count, kinds, left, right, heights, stacks) ==
    /\ count \in Nat \ {0}
    /\ heights \in [0..count -> Nat]
    /\ heights[0] = 0
    /\ stacks[0] = [position \in 1..0 |-> position]
    /\ \A index \in 1..count :
        LET before == heights[index - 1]
            retained == RetainedIndexCount(kinds[index], before)
        IN /\ retained \in 0..before
           /\ heights[index] = retained + 1
           /\ stacks[index] = HistoryAppend(stacks[index - 1], retained, index)
           /\ (kinds[index] = "add" =>
                   /\ left[index] = stacks[index - 1][before - 1]
                   /\ right[index] = stacks[index - 1][before])
    /\ heights[count] = 1

THEOREM PostorderIndexOperationsKeepEveryPrefixBounded ==
    ASSUME NEW count, NEW kinds, NEW left, NEW right, NEW heights, NEW stacks,
           PostorderIndexOperations(count, kinds, left, right, heights, stacks)
    PROVE \A index \in 0..count :
        stacks[index] \in [1..heights[index] -> 1..index]
    PROOF
    <1>. DEFINE bounded(index) == stacks[index] \in [1..heights[index] -> 1..index]
    <1>1. bounded(0)
        BY SMT DEF bounded, PostorderIndexOperations
    <1>2. \A index \in 1..count :
        ((\A prior \in 0..(index - 1) : bounded(prior)) => bounded(index))
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A prior \in 0..(index - 1) : bounded(prior)
                     PROVE bounded(index)
            BY SMT
        <2>. DEFINE before == heights[index - 1]
                    retained == RetainedIndexCount(kinds[index], before)
        <2>1. index - 1 \in Nat /\ before \in Nat
              /\ retained \in 0..before /\ bounded(index - 1)
            BY SMT DEF before, retained, PostorderIndexOperations
        <2>2. HistoryAppend(stacks[index - 1], retained, index)
                  \in [1..(retained + 1) -> 1..index]
            BY <2>1, PostorderAppendPreservesIndexBounds, SMT DEF bounded
        <2>. QED BY <2>2, SMT DEF bounded, before, retained, PostorderIndexOperations
    <1>3. count \in Nat BY SMT DEF PostorderIndexOperations
    <1>4. \A index \in 0..count : bounded(index)
        BY <1>1, <1>2, <1>3, FiniteIndexedPrefixProperty
    <1>. QED BY <1>4 DEF bounded

THEOREM PostorderIndexOperationsSupplyTheConstructionInvariant ==
    ASSUME NEW count, NEW kinds, NEW left, NEW right, NEW heights, NEW stacks,
           PostorderIndexOperations(count, kinds, left, right, heights, stacks)
    PROVE ExpressionIndexStack(count, kinds, left, right, heights, stacks)
    PROOF
    <1>1. \A index \in 0..count :
        stacks[index] \in [1..heights[index] -> 1..index]
        BY PostorderIndexOperationsKeepEveryPrefixBounded
    <1>2. \A index \in 1..count : kinds[index] = "add" =>
        /\ heights[index - 1] >= 2
        /\ heights[index] = heights[index - 1] - 1
        BY SMT DEF PostorderIndexOperations, RetainedIndexCount
    <1>. QED BY <1>1, <1>2, SMT
        DEF ExpressionIndexStack, PostorderIndexOperations, RetainedIndexCount

THEOREM PostorderConstructionSuppliesExpressionPlan ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, NEW heights, NEW stacks,
           ExpressionNodeStorage(count, kinds, literals, reads, left, right, state),
           ExpressionIndexStack(count, kinds, left, right, heights, stacks)
    PROVE ExpressionPlan(count, kinds, literals, reads, left, right, state)
    PROOF
    <1>1. \A index \in 1..count : kinds[index] = "add" =>
        /\ left[index] \in 1..(index - 1)
        /\ right[index] \in 1..(index - 1)
        <2>. SUFFICES ASSUME NEW index \in 1..count, kinds[index] = "add"
                     PROVE /\ left[index] \in 1..(index - 1)
                           /\ right[index] \in 1..(index - 1)
            BY SMT
        <2>1. index - 1 \in 0..count
            BY SMT DEF ExpressionNodeStorage
        <2>2. stacks[index - 1] \in [1..heights[index - 1] -> 1..(index - 1)]
              /\ heights[index - 1] \in Nat
              /\ heights[index - 1] >= 2
            BY <2>1, SMT DEF ExpressionIndexStack
        <2>3. left[index] = stacks[index - 1][heights[index - 1] - 1]
              /\ right[index] = stacks[index - 1][heights[index - 1]]
            BY SMT DEF ExpressionIndexStack
        <2>. QED BY <2>2, <2>3, SMT
    <1>2. \A index \in 1..count :
        /\ left[index] \in 0..count
        /\ right[index] \in 0..count
        BY <1>1, SMT DEF ExpressionNodeStorage
    <1>3. left \in [1..count -> 0..count]
          /\ right \in [1..count -> 0..count]
        BY <1>2, SMT DEF ExpressionNodeStorage
    <1>. QED BY <1>1, <1>3, SMT DEF ExpressionNodeStorage, ExpressionPlan

THEOREM CompletedPostorderConstructionSelectsTheLastNode ==
    ASSUME NEW count \in Nat \ {0}, NEW kinds, NEW left, NEW right,
           NEW heights, NEW stacks,
           ExpressionIndexStack(count, kinds, left, right, heights, stacks)
    PROVE stacks[count][1] = count
    PROOF
    <1>1. heights[count] = 1
        BY SMT DEF ExpressionIndexStack
    <1>2. CASE kinds[count] = "add"
        <2>1. heights[count - 1] = 2
              /\ stacks[count] = HistoryAppend(stacks[count - 1], 0, count)
            BY <1>1, <1>2, SMT DEF ExpressionIndexStack
        <2>. QED BY <2>1, SMT DEF HistoryAppend
    <1>3. CASE kinds[count] # "add"
        <2>1. heights[count - 1] = 0
              /\ stacks[count] = HistoryAppend(stacks[count - 1], 0, count)
            BY <1>1, <1>3, SMT DEF ExpressionIndexStack
        <2>. QED BY <2>1, SMT DEF HistoryAppend
    <1>. QED BY <1>2, <1>3, SMT

\* Ghost syntax prefixes specify pending-frame obligations; they do not evaluate expressions.
VisitPrefix(height, terms) == [height |-> height, terms |-> terms]
EmptyVisitPrefix == VisitPrefix(0, [position \in 1..0 |-> position])
PushVisitPrefix(prefix, node) ==
    VisitPrefix(prefix.height + 1, HistoryAppend(prefix.terms, prefix.height, node))
FoldVisitPrefix(prefix, node) ==
    VisitPrefix(prefix.height - 1, HistoryAppend(prefix.terms, prefix.height - 2, node))
WellFormedVisitPrefix(prefix) ==
    /\ prefix.height \in Nat
    /\ prefix.terms = [position \in 1..prefix.height |-> prefix.terms[position]]
VisitFrame(node, expanded, prefix) ==
    [node |-> node, expanded |-> expanded, prefix |-> prefix]
VisitFrameExit(frame) ==
    IF frame.expanded THEN FoldVisitPrefix(frame.prefix, frame.node)
    ELSE PushVisitPrefix(frame.prefix, frame.node)
WellFormedVisitFrame(frame, sourceLeft, sourceRight) ==
    /\ frame.expanded \in BOOLEAN
    /\ WellFormedVisitPrefix(frame.prefix)
    /\ (frame.expanded =>
        /\ frame.prefix.height >= 2
        /\ frame.prefix.terms[frame.prefix.height - 1] = sourceLeft[frame.node]
        /\ frame.prefix.terms[frame.prefix.height] = sourceRight[frame.node])

THEOREM PushingASyntaxRootPreservesItsPrefix ==
    ASSUME NEW prefix, NEW node, WellFormedVisitPrefix(prefix)
    PROVE WellFormedVisitPrefix(PushVisitPrefix(prefix, node))
    BY SMT DEF WellFormedVisitPrefix, PushVisitPrefix, VisitPrefix, HistoryAppend

THEOREM FoldingTwoCompletedChildrenRestoresTheParentPrefix ==
    ASSUME NEW prefix, NEW parent, NEW sourceLeft, NEW sourceRight,
           WellFormedVisitPrefix(prefix)
    PROVE FoldVisitPrefix(
        PushVisitPrefix(PushVisitPrefix(prefix, sourceLeft), sourceRight), parent)
        = PushVisitPrefix(prefix, parent)
    BY SMT DEF FoldVisitPrefix, PushVisitPrefix, VisitPrefix,
        WellFormedVisitPrefix, HistoryAppend

ExpandedVisitFrames(frame, sourceLeft, sourceRight) ==
    LET leftPrefix == PushVisitPrefix(frame.prefix, sourceLeft[frame.node])
        bothPrefix == PushVisitPrefix(leftPrefix, sourceRight[frame.node])
    IN [position \in 1..3 |->
        IF position = 1 THEN VisitFrame(frame.node, TRUE, bothPrefix)
        ELSE IF position = 2 THEN VisitFrame(sourceRight[frame.node], FALSE, leftPrefix)
        ELSE VisitFrame(sourceLeft[frame.node], FALSE, frame.prefix)]

THEOREM ExpandedFramesThreadLeftThenRightIntoTheParent ==
    ASSUME NEW frame, NEW sourceLeft, NEW sourceRight,
           WellFormedVisitFrame(frame, sourceLeft, sourceRight), ~frame.expanded
    PROVE LET frames == ExpandedVisitFrames(frame, sourceLeft, sourceRight)
          IN /\ \A position \in 1..3 :
                    WellFormedVisitFrame(frames[position], sourceLeft, sourceRight)
             /\ frames[3].prefix = frame.prefix
             /\ VisitFrameExit(frames[3]) = frames[2].prefix
             /\ VisitFrameExit(frames[2]) = frames[1].prefix
             /\ VisitFrameExit(frames[1]) = VisitFrameExit(frame)
    PROOF
    <1>1. WellFormedVisitPrefix(frame.prefix)
        BY SMT DEF WellFormedVisitFrame
    <1>2. WellFormedVisitPrefix(PushVisitPrefix(frame.prefix, sourceLeft[frame.node]))
        BY <1>1, PushingASyntaxRootPreservesItsPrefix
    <1>3. WellFormedVisitPrefix(PushVisitPrefix(
        PushVisitPrefix(frame.prefix, sourceLeft[frame.node]), sourceRight[frame.node]))
        BY <1>2, PushingASyntaxRootPreservesItsPrefix
    <1>4. FoldVisitPrefix(PushVisitPrefix(
        PushVisitPrefix(frame.prefix, sourceLeft[frame.node]), sourceRight[frame.node]), frame.node)
        = PushVisitPrefix(frame.prefix, frame.node)
        BY <1>1, FoldingTwoCompletedChildrenRestoresTheParentPrefix
    <1>. DEFINE frames == ExpandedVisitFrames(frame, sourceLeft, sourceRight)
                leftPrefix == PushVisitPrefix(frame.prefix, sourceLeft[frame.node])
                bothPrefix == PushVisitPrefix(leftPrefix, sourceRight[frame.node])
    <1>5. WellFormedVisitFrame(frames[1], sourceLeft, sourceRight)
        <2>1. frames[1] = VisitFrame(frame.node, TRUE, bothPrefix)
            BY SMT DEF frames, ExpandedVisitFrames, bothPrefix, leftPrefix
        <2>2. frame.prefix.height \in Nat
              /\ leftPrefix.height = frame.prefix.height + 1
              /\ bothPrefix.height = frame.prefix.height + 2
            BY <1>1, SMT
                DEF leftPrefix, bothPrefix, WellFormedVisitPrefix, PushVisitPrefix, VisitPrefix
        <2>3. leftPrefix.terms[leftPrefix.height] = sourceLeft[frame.node]
            BY <2>2, SMT DEF leftPrefix, PushVisitPrefix, VisitPrefix, HistoryAppend
        <2>4. bothPrefix.terms[bothPrefix.height - 1] = sourceLeft[frame.node]
              /\ bothPrefix.terms[bothPrefix.height] = sourceRight[frame.node]
            BY <2>2, <2>3, SMT DEF bothPrefix, PushVisitPrefix, VisitPrefix, HistoryAppend
        <2>5. WellFormedVisitPrefix(bothPrefix)
            BY <1>3 DEF bothPrefix, leftPrefix
        <2>. QED BY <2>1, <2>2, <2>4, <2>5, SMT DEF WellFormedVisitFrame, VisitFrame
    <1>6. WellFormedVisitFrame(frames[2], sourceLeft, sourceRight)
          /\ WellFormedVisitFrame(frames[3], sourceLeft, sourceRight)
        BY <1>1, <1>2, SMT
            DEF frames, ExpandedVisitFrames, WellFormedVisitFrame, VisitFrame
    <1>7. \A position \in 1..3 :
        WellFormedVisitFrame(frames[position], sourceLeft, sourceRight)
        BY <1>5, <1>6, SMT DEF frames, ExpandedVisitFrames
    <1>8. frames[3].prefix = frame.prefix
          /\ VisitFrameExit(frames[3]) = frames[2].prefix
          /\ VisitFrameExit(frames[2]) = frames[1].prefix
          /\ VisitFrameExit(frames[1]) = VisitFrameExit(frame)
        BY <1>4, SMT DEF frames, ExpandedVisitFrames, VisitFrame, VisitFrameExit
    <1>. QED BY <1>7, <1>8 DEF frames

PendingVisitContract(height, pending, current, goal, sourceLeft, sourceRight) ==
    /\ height \in Nat
    /\ \A position \in 1..height :
        WellFormedVisitFrame(pending[position], sourceLeft, sourceRight)
    /\ \A position \in 2..height :
        pending[position - 1].prefix = VisitFrameExit(pending[position])
    /\ IF height = 0 THEN current = goal
       ELSE /\ current = pending[height].prefix
            /\ goal = VisitFrameExit(pending[1])

ReplaceTopVisitFrame(pending, height, frames) ==
    [position \in 1..(height + 2) |->
        IF position < height THEN pending[position] ELSE frames[position - height + 1]]

THEOREM ExpandingAPendingParentPreservesTheVisitContract ==
    ASSUME NEW height, NEW pending, NEW current, NEW goal, NEW sourceLeft, NEW sourceRight,
           PendingVisitContract(height, pending, current, goal, sourceLeft, sourceRight),
           height > 0, ~pending[height].expanded
    PROVE PendingVisitContract(height + 2,
        ReplaceTopVisitFrame(pending, height,
            ExpandedVisitFrames(pending[height], sourceLeft, sourceRight)),
        current, goal, sourceLeft, sourceRight)
    PROOF
    <1>. DEFINE frames == ExpandedVisitFrames(pending[height], sourceLeft, sourceRight)
                next == ReplaceTopVisitFrame(pending, height, frames)
    <1>1. \A position \in 1..3 :
        WellFormedVisitFrame(frames[position], sourceLeft, sourceRight)
        BY ExpandedFramesThreadLeftThenRightIntoTheParent, SMT
            DEF frames, PendingVisitContract
    <1>2. frames[3].prefix = pending[height].prefix
          /\ VisitFrameExit(frames[3]) = frames[2].prefix
          /\ VisitFrameExit(frames[2]) = frames[1].prefix
          /\ VisitFrameExit(frames[1]) = VisitFrameExit(pending[height])
        BY ExpandedFramesThreadLeftThenRightIntoTheParent, SMT
            DEF frames, PendingVisitContract
    <1>3. \A position \in 1..(height + 2) :
        WellFormedVisitFrame(next[position], sourceLeft, sourceRight)
        BY <1>1, SMT DEF next, ReplaceTopVisitFrame, PendingVisitContract
    <1>4. \A position \in 2..(height + 2) :
        next[position - 1].prefix = VisitFrameExit(next[position])
        BY <1>2, SMT DEF next, ReplaceTopVisitFrame, PendingVisitContract
    <1>. QED BY <1>2, <1>3, <1>4, SMT
        DEF next, ReplaceTopVisitFrame, PendingVisitContract

THEOREM CompletingAPendingFramePreservesTheVisitContract ==
    ASSUME NEW height, NEW pending, NEW current, NEW goal, NEW sourceLeft, NEW sourceRight,
           PendingVisitContract(height, pending, current, goal, sourceLeft, sourceRight), height > 0
    PROVE PendingVisitContract(height - 1, HistoryPrefix(pending, height - 1),
        VisitFrameExit(pending[height]), goal, sourceLeft, sourceRight)
    BY SMT DEF PendingVisitContract, HistoryPrefix

THEOREM ASourceRootStartsItsOwnPendingVisitContract ==
    ASSUME NEW root, NEW sourceLeft, NEW sourceRight
    PROVE PendingVisitContract(1,
        [position \in 1..1 |-> VisitFrame(root, FALSE, EmptyVisitPrefix)],
        EmptyVisitPrefix, PushVisitPrefix(EmptyVisitPrefix, root), sourceLeft, sourceRight)
    BY SMT DEF PendingVisitContract, VisitFrame, VisitFrameExit,
        EmptyVisitPrefix, WellFormedVisitFrame, WellFormedVisitPrefix, VisitPrefix

PendingVisitStep(sourceKinds, sourceLeft, sourceRight,
                 height, pending, current, nextHeight, nextPending, nextCurrent) ==
    /\ height > 0
    /\ LET frame == pending[height]
       IN IF ~frame.expanded /\ sourceKinds[frame.node] = "add"
          THEN /\ nextHeight = height + 2
               /\ nextPending = ReplaceTopVisitFrame(pending, height,
                      ExpandedVisitFrames(frame, sourceLeft, sourceRight))
               /\ nextCurrent = current
          ELSE /\ (frame.expanded /\ sourceKinds[frame.node] = "add")
                      \/ (~frame.expanded /\ sourceKinds[frame.node] \in {"literal", "read"})
               /\ nextHeight = height - 1
               /\ nextPending = HistoryPrefix(pending, height - 1)
               /\ nextCurrent = VisitFrameExit(frame)

THEOREM APendingVisitStepPreservesTheContract ==
    ASSUME NEW sourceKinds, NEW sourceLeft, NEW sourceRight,
           NEW height, NEW pending, NEW current, NEW goal,
           NEW nextHeight, NEW nextPending, NEW nextCurrent,
           PendingVisitContract(height, pending, current, goal, sourceLeft, sourceRight),
           PendingVisitStep(sourceKinds, sourceLeft, sourceRight,
               height, pending, current, nextHeight, nextPending, nextCurrent)
    PROVE PendingVisitContract(nextHeight, nextPending, nextCurrent, goal, sourceLeft, sourceRight)
    PROOF
    <1>1. CASE ~pending[height].expanded /\ sourceKinds[pending[height].node] = "add"
        BY <1>1, ExpandingAPendingParentPreservesTheVisitContract, SMT DEF PendingVisitStep
    <1>2. CASE ~(~pending[height].expanded /\ sourceKinds[pending[height].node] = "add")
        BY <1>2, CompletingAPendingFramePreservesTheVisitContract, SMT DEF PendingVisitStep
    <1>. QED BY <1>1, <1>2, SMT

PendingVisitHistory(steps, root, sourceKinds, sourceLeft, sourceRight, heights, pendings, currents) ==
    /\ steps \in Nat
    /\ heights \in [0..steps -> Nat]
    /\ heights[0] = 1
    /\ pendings[0] = [position \in 1..1 |-> VisitFrame(root, FALSE, EmptyVisitPrefix)]
    /\ currents[0] = EmptyVisitPrefix
    /\ \A step \in 1..steps : PendingVisitStep(sourceKinds, sourceLeft, sourceRight,
        heights[step - 1], pendings[step - 1], currents[step - 1],
        heights[step], pendings[step], currents[step])

THEOREM PendingVisitHistoryPreservesTheSourceRootContext ==
    ASSUME NEW steps, NEW root, NEW sourceKinds, NEW sourceLeft, NEW sourceRight,
           NEW heights, NEW pendings, NEW currents,
           PendingVisitHistory(steps, root, sourceKinds, sourceLeft, sourceRight, heights, pendings, currents)
    PROVE \A step \in 0..steps : PendingVisitContract(heights[step], pendings[step], currents[step],
        PushVisitPrefix(EmptyVisitPrefix, root), sourceLeft, sourceRight)
    PROOF
    <1>. DEFINE holds(step) == PendingVisitContract(heights[step], pendings[step], currents[step],
        PushVisitPrefix(EmptyVisitPrefix, root), sourceLeft, sourceRight)
    <1>0. PendingVisitContract(1,
        [position \in 1..1 |-> VisitFrame(root, FALSE, EmptyVisitPrefix)],
        EmptyVisitPrefix, PushVisitPrefix(EmptyVisitPrefix, root), sourceLeft, sourceRight)
        BY ASourceRootStartsItsOwnPendingVisitContract
    <1>1. holds(0)
        BY <1>0, SMT DEF holds, PendingVisitHistory
    <1>2. \A step \in 1..steps :
        ((\A prior \in 0..(step - 1) : holds(prior)) => holds(step))
        <2>. SUFFICES ASSUME NEW step \in 1..steps,
                             \A prior \in 0..(step - 1) : holds(prior)
                     PROVE holds(step)
            BY SMT
        <2>1. holds(step - 1)
            BY SMT DEF PendingVisitHistory
        <2>2. PendingVisitStep(sourceKinds, sourceLeft, sourceRight,
            heights[step - 1], pendings[step - 1], currents[step - 1],
            heights[step], pendings[step], currents[step])
            BY SMT DEF PendingVisitHistory
        <2>. QED BY <2>1, <2>2, APendingVisitStepPreservesTheContract DEF holds
    <1>3. steps \in Nat BY SMT DEF PendingVisitHistory
    <1>4. \A step \in 0..steps : holds(step)
        BY <1>1, <1>2, <1>3, FiniteIndexedPrefixProperty
    <1>. QED BY <1>4 DEF holds

THEOREM SuccessfulPendingVisitReturnsOnlyItsSourceRoot ==
    ASSUME NEW steps, NEW root, NEW sourceKinds, NEW sourceLeft, NEW sourceRight,
           NEW heights, NEW pendings, NEW currents,
           PendingVisitHistory(steps, root, sourceKinds, sourceLeft, sourceRight, heights, pendings, currents),
           heights[steps] = 0
    PROVE /\ currents[steps] = PushVisitPrefix(EmptyVisitPrefix, root)
          /\ currents[steps].height = 1
          /\ currents[steps].terms[1] = root
    PROOF
    <1>1. \A step \in 0..steps : PendingVisitContract(heights[step], pendings[step], currents[step],
        PushVisitPrefix(EmptyVisitPrefix, root), sourceLeft, sourceRight)
        BY PendingVisitHistoryPreservesTheSourceRootContext
    <1>2. PendingVisitContract(heights[steps], pendings[steps], currents[steps],
        PushVisitPrefix(EmptyVisitPrefix, root), sourceLeft, sourceRight)
        BY <1>1, SMT DEF PendingVisitHistory
    <1>3. currents[steps] = PushVisitPrefix(EmptyVisitPrefix, root)
        BY <1>2, SMT DEF PendingVisitContract
    <1>. QED BY <1>3, SMT
        DEF PushVisitPrefix, EmptyVisitPrefix, VisitPrefix, HistoryAppend

\* Total record projections represent the associated fields of the existing three node cases.
EmptyNodeEmission ==
    LET empty == [position \in 1..0 |-> position]
    IN [count |-> 0, height |-> 0, indices |-> empty, nodes |-> empty, origins |-> empty]
AppendedVisitNode(view, frame, emitted) ==
    LET kind == view.kinds[frame.node]
    IN [kind |-> kind,
        payload |-> IF kind = "literal" THEN view.literals[frame.node]
                    ELSE IF kind = "read" THEN view.reads[frame.node] ELSE 0,
        left |-> IF kind = "add" THEN emitted.indices[emitted.height - 1] ELSE 0,
        right |-> IF kind = "add" THEN emitted.indices[emitted.height] ELSE 0]
AppendVisitNode(view, frame, emitted) ==
    LET retained == RetainedIndexCount(view.kinds[frame.node], emitted.height)
        index == emitted.count + 1
    IN [count |-> index, height |-> retained + 1,
        indices |-> HistoryAppend(emitted.indices, retained, index),
        nodes |-> HistoryAppend(emitted.nodes, emitted.count, AppendedVisitNode(view, frame, emitted)),
        origins |-> HistoryAppend(emitted.origins, emitted.count, frame.node)]

NodeEmissionArrays(emitted) ==
    /\ emitted.count \in Nat /\ emitted.height \in Nat
    /\ emitted.indices \in [1..emitted.height -> 1..emitted.count]
    /\ emitted.nodes = [index \in 1..emitted.count |-> emitted.nodes[index]]
    /\ emitted.origins = [index \in 1..emitted.count |-> emitted.origins[index]]
    /\ (emitted.height > 0 => emitted.indices[emitted.height] = emitted.count)
NodeRootsMatchVisitPrefix(emitted, current) ==
    /\ current.height = emitted.height
    /\ \A position \in 1..emitted.height :
        current.terms[position] = emitted.origins[emitted.indices[position]]
NodePayloadMatchesSource(view, emitted, index) ==
    LET node == emitted.nodes[index]
        origin == emitted.origins[index]
    IN /\ node.kind \in {"literal", "read", "add"}
       /\ node.kind = view.kinds[origin]
       /\ node.payload = IF node.kind = "literal" THEN view.literals[origin]
                         ELSE IF node.kind = "read" THEN view.reads[origin] ELSE 0
       /\ IF node.kind = "add"
          THEN /\ node.left \in 1..(index - 1) /\ node.right \in 1..(index - 1)
               /\ emitted.origins[node.left] = view.left[origin]
               /\ emitted.origins[node.right] = view.right[origin]
          ELSE /\ node.left = 0 /\ node.right = 0
AllNodePayloadsMatchSource(view, emitted) ==
    \A index \in 1..emitted.count : NodePayloadMatchesSource(view, emitted, index)

THEOREM AppendingACompletedFrameKeepsNodeArrays ==
    ASSUME NEW view, NEW frame, NEW emitted,
           NodeEmissionArrays(emitted), WellFormedVisitFrame(frame, view.left, view.right),
           frame.prefix.height = emitted.height,
           (frame.expanded /\ view.kinds[frame.node] = "add")
               \/ (~frame.expanded /\ view.kinds[frame.node] \in {"literal", "read"})
    PROVE NodeEmissionArrays(AppendVisitNode(view, frame, emitted))
    PROOF
    <1>. DEFINE retained == RetainedIndexCount(view.kinds[frame.node], emitted.height)
                next == AppendVisitNode(view, frame, emitted)
    <1>1. retained \in 0..emitted.height
        BY SMT DEF retained, RetainedIndexCount, WellFormedVisitFrame, NodeEmissionArrays
    <1>2. HistoryAppend(emitted.indices, retained, emitted.count + 1)
        \in [1..(retained + 1) -> 1..(emitted.count + 1)]
        BY <1>1, PostorderAppendPreservesIndexBounds, SMT DEF NodeEmissionArrays
    <1>. QED BY <1>1, <1>2, SMT
        DEF next, NodeEmissionArrays, AppendVisitNode, retained, HistoryAppend

THEOREM AppendingACompletedFrameKeepsTheSyntaxRootCoupling ==
    ASSUME NEW view, NEW frame, NEW emitted,
           NodeEmissionArrays(emitted), WellFormedVisitFrame(frame, view.left, view.right),
           NodeRootsMatchVisitPrefix(emitted, frame.prefix),
           (frame.expanded /\ view.kinds[frame.node] = "add")
               \/ (~frame.expanded /\ view.kinds[frame.node] \in {"literal", "read"})
    PROVE NodeRootsMatchVisitPrefix(AppendVisitNode(view, frame, emitted), VisitFrameExit(frame))
    PROOF
    <1>. DEFINE retained == RetainedIndexCount(view.kinds[frame.node], emitted.height)
    <1>1. retained \in 0..emitted.height
        BY SMT DEF retained, RetainedIndexCount, WellFormedVisitFrame,
            NodeRootsMatchVisitPrefix, NodeEmissionArrays
    <1>2. \A position \in 1..retained : emitted.indices[position] \in 1..emitted.count
        BY <1>1, SMT DEF NodeEmissionArrays
    <1>. QED BY <1>1, <1>2, SMT
        DEF NodeRootsMatchVisitPrefix, AppendVisitNode, VisitFrameExit,
            PushVisitPrefix, FoldVisitPrefix, VisitPrefix, HistoryAppend,
            retained, RetainedIndexCount, NodeEmissionArrays

THEOREM AppendingACompletedFramePreservesEveryOldNodePayload ==
    ASSUME NEW view, NEW frame, NEW emitted,
           NodeEmissionArrays(emitted), AllNodePayloadsMatchSource(view, emitted)
    PROVE \A index \in 1..emitted.count :
        NodePayloadMatchesSource(view, AppendVisitNode(view, frame, emitted), index)
    PROOF
    <1>. SUFFICES ASSUME NEW index \in 1..emitted.count
                 PROVE NodePayloadMatchesSource(view, AppendVisitNode(view, frame, emitted), index)
        BY SMT
    <1>1. NodePayloadMatchesSource(view, emitted, index)
        BY SMT DEF AllNodePayloadsMatchSource
    <1>2. emitted.nodes[index].kind = "add" =>
        /\ emitted.nodes[index].left \in 1..emitted.count
        /\ emitted.nodes[index].right \in 1..emitted.count
        BY <1>1, SMT DEF NodePayloadMatchesSource, NodeEmissionArrays
    <1>. QED BY <1>1, <1>2, SMT
        DEF NodePayloadMatchesSource, AppendVisitNode, HistoryAppend, NodeEmissionArrays

THEOREM AppendingACompletedFrameRetainsItsSourcePayload ==
    ASSUME NEW view, NEW frame, NEW emitted,
           NodeEmissionArrays(emitted), WellFormedVisitFrame(frame, view.left, view.right),
           NodeRootsMatchVisitPrefix(emitted, frame.prefix),
           (frame.expanded /\ view.kinds[frame.node] = "add")
               \/ (~frame.expanded /\ view.kinds[frame.node] \in {"literal", "read"})
    PROVE NodePayloadMatchesSource(view, AppendVisitNode(view, frame, emitted), emitted.count + 1)
    PROOF
    <1>1. CASE frame.expanded
        <2>1. view.kinds[frame.node] = "add" /\ emitted.height >= 2
            BY <1>1, SMT DEF WellFormedVisitFrame, NodeRootsMatchVisitPrefix
        <2>2. emitted.indices[emitted.height - 1] \in 1..emitted.count
              /\ emitted.indices[emitted.height] \in 1..emitted.count
            BY <2>1, SMT DEF NodeEmissionArrays
        <2>3. emitted.origins[emitted.indices[emitted.height - 1]] = view.left[frame.node]
              /\ emitted.origins[emitted.indices[emitted.height]] = view.right[frame.node]
            BY <1>1, <2>1, SMT DEF NodeRootsMatchVisitPrefix, WellFormedVisitFrame, NodeEmissionArrays
        <2>. QED BY <2>1, <2>2, <2>3, SMT
            DEF NodePayloadMatchesSource, AppendVisitNode, AppendedVisitNode, HistoryAppend, NodeEmissionArrays
    <1>2. CASE ~frame.expanded
        BY <1>2, SMT DEF NodePayloadMatchesSource, AppendVisitNode, AppendedVisitNode,
            HistoryAppend, NodeEmissionArrays
    <1>. QED BY <1>1, <1>2, SMT

NodeEmissionStep(view, frame, emitted, next) ==
    IF ~frame.expanded /\ view.kinds[frame.node] = "add"
    THEN next = emitted
    ELSE next = AppendVisitNode(view, frame, emitted)

THEOREM ASynchronizedVisitStepPreservesNodesAndSourcePayloads ==
    ASSUME NEW view, NEW height, NEW pending, NEW current, NEW goal,
           NEW nextHeight, NEW nextPending, NEW nextCurrent, NEW emitted, NEW next,
           PendingVisitContract(height, pending, current, goal, view.left, view.right),
           PendingVisitStep(view.kinds, view.left, view.right,
               height, pending, current, nextHeight, nextPending, nextCurrent),
           NodeEmissionArrays(emitted), NodeRootsMatchVisitPrefix(emitted, current),
           AllNodePayloadsMatchSource(view, emitted),
           NodeEmissionStep(view, pending[height], emitted, next)
    PROVE /\ NodeEmissionArrays(next)
          /\ NodeRootsMatchVisitPrefix(next, nextCurrent)
          /\ AllNodePayloadsMatchSource(view, next)
    PROOF
    <1>1. CASE ~pending[height].expanded /\ view.kinds[pending[height].node] = "add"
        BY <1>1, SMT DEF NodeEmissionStep, PendingVisitStep
    <1>2. CASE ~(~pending[height].expanded /\ view.kinds[pending[height].node] = "add")
        <2>. DEFINE frame == pending[height]
        <2>1. WellFormedVisitFrame(frame, view.left, view.right)
              /\ NodeRootsMatchVisitPrefix(emitted, frame.prefix)
              /\ ((frame.expanded /\ view.kinds[frame.node] = "add")
                  \/ (~frame.expanded /\ view.kinds[frame.node] \in {"literal", "read"}))
            BY <1>2, SMT DEF frame, PendingVisitContract, PendingVisitStep
        <2>2. next = AppendVisitNode(view, frame, emitted)
              /\ nextCurrent = VisitFrameExit(frame)
            BY <1>2, SMT DEF frame, NodeEmissionStep, PendingVisitStep
        <2>3. NodeEmissionArrays(next)
            BY <2>1, <2>2, AppendingACompletedFrameKeepsNodeArrays, SMT DEF NodeRootsMatchVisitPrefix
        <2>4. NodeRootsMatchVisitPrefix(next, nextCurrent)
            BY <2>1, <2>2, AppendingACompletedFrameKeepsTheSyntaxRootCoupling
        <2>5. \A index \in 1..emitted.count : NodePayloadMatchesSource(view, next, index)
            BY <2>2, AppendingACompletedFramePreservesEveryOldNodePayload
        <2>6. NodePayloadMatchesSource(view, next, emitted.count + 1)
            BY <2>1, <2>2, AppendingACompletedFrameRetainsItsSourcePayload
        <2>7. AllNodePayloadsMatchSource(view, next)
            BY <2>2, <2>5, <2>6, SMT DEF AllNodePayloadsMatchSource, AppendVisitNode, NodeEmissionArrays
        <2>. QED BY <2>3, <2>4, <2>7
    <1>. QED BY <1>1, <1>2, SMT

SynchronizedNodeHistory(steps, root, view, heights, pendings, currents, emissions) ==
    /\ PendingVisitHistory(steps, root, view.kinds, view.left, view.right, heights, pendings, currents)
    /\ emissions[0] = EmptyNodeEmission
    /\ \A step \in 1..steps : NodeEmissionStep(view,
        pendings[step - 1][heights[step - 1]], emissions[step - 1], emissions[step])

THEOREM SynchronizedNodeHistoryPreservesEverySourcePayload ==
    ASSUME NEW steps, NEW root, NEW view, NEW heights, NEW pendings, NEW currents, NEW emissions,
           SynchronizedNodeHistory(steps, root, view, heights, pendings, currents, emissions)
    PROVE \A step \in 0..steps :
        /\ NodeEmissionArrays(emissions[step])
        /\ NodeRootsMatchVisitPrefix(emissions[step], currents[step])
        /\ AllNodePayloadsMatchSource(view, emissions[step])
    PROOF
    <1>. DEFINE holds(step) ==
        /\ NodeEmissionArrays(emissions[step])
        /\ NodeRootsMatchVisitPrefix(emissions[step], currents[step])
        /\ AllNodePayloadsMatchSource(view, emissions[step])
    <1>1. \A step \in 0..steps : PendingVisitContract(heights[step], pendings[step], currents[step],
        PushVisitPrefix(EmptyVisitPrefix, root), view.left, view.right)
        BY PendingVisitHistoryPreservesTheSourceRootContext, SMT DEF SynchronizedNodeHistory
    <1>2. holds(0)
        BY SMT DEF holds, SynchronizedNodeHistory, PendingVisitHistory,
            EmptyNodeEmission, NodeEmissionArrays, NodeRootsMatchVisitPrefix,
            AllNodePayloadsMatchSource, EmptyVisitPrefix, VisitPrefix
    <1>3. \A step \in 1..steps :
        ((\A prior \in 0..(step - 1) : holds(prior)) => holds(step))
        <2>. SUFFICES ASSUME NEW step \in 1..steps,
                             \A prior \in 0..(step - 1) : holds(prior)
                     PROVE holds(step)
            BY SMT
        <2>1. holds(step - 1)
            BY SMT DEF SynchronizedNodeHistory, PendingVisitHistory
        <2>2. PendingVisitContract(heights[step - 1], pendings[step - 1], currents[step - 1],
            PushVisitPrefix(EmptyVisitPrefix, root), view.left, view.right)
            BY <1>1, SMT DEF SynchronizedNodeHistory, PendingVisitHistory
        <2>3. PendingVisitStep(view.kinds, view.left, view.right,
            heights[step - 1], pendings[step - 1], currents[step - 1],
            heights[step], pendings[step], currents[step])
            /\ NodeEmissionStep(view, pendings[step - 1][heights[step - 1]],
                emissions[step - 1], emissions[step])
            BY SMT DEF SynchronizedNodeHistory, PendingVisitHistory
        <2>. QED BY <2>1, <2>2, <2>3, ASynchronizedVisitStepPreservesNodesAndSourcePayloads DEF holds
    <1>4. steps \in Nat BY SMT DEF SynchronizedNodeHistory, PendingVisitHistory
    <1>5. \A step \in 0..steps : holds(step)
        BY <1>2, <1>3, <1>4, FiniteIndexedPrefixProperty
    <1>. QED BY <1>5 DEF holds

THEOREM SuccessfulSynchronizedVisitIdentifiesTheEmittedSourceRoot ==
    ASSUME NEW steps, NEW root, NEW view, NEW heights, NEW pendings, NEW currents, NEW emissions,
           SynchronizedNodeHistory(steps, root, view, heights, pendings, currents, emissions),
           heights[steps] = 0
    PROVE LET result == emissions[steps]
          IN /\ result.count \in Nat \ {0} /\ result.height = 1
             /\ result.indices[1] = result.count
             /\ result.origins[result.count] = root
             /\ AllNodePayloadsMatchSource(view, result)
    PROOF
    <1>1. currents[steps].height = 1 /\ currents[steps].terms[1] = root
        BY SuccessfulPendingVisitReturnsOnlyItsSourceRoot, SMT DEF SynchronizedNodeHistory
    <1>2. \A step \in 0..steps :
        /\ NodeEmissionArrays(emissions[step])
        /\ NodeRootsMatchVisitPrefix(emissions[step], currents[step])
        /\ AllNodePayloadsMatchSource(view, emissions[step])
        BY SynchronizedNodeHistoryPreservesEverySourcePayload
    <1>3. NodeEmissionArrays(emissions[steps])
          /\ NodeRootsMatchVisitPrefix(emissions[steps], currents[steps])
          /\ AllNodePayloadsMatchSource(view, emissions[steps])
        BY <1>2, SMT DEF SynchronizedNodeHistory, PendingVisitHistory
    <1>. QED BY <1>1, <1>3, SMT DEF NodeEmissionArrays, NodeRootsMatchVisitPrefix

TypedVisitedSourceInputs(view, emitted) ==
    \A index \in 1..emitted.count :
        LET origin == emitted.origins[index]
        IN /\ (view.kinds[origin] = "literal" => InRange(view.literals[origin]))
           /\ (view.kinds[origin] = "read" => view.reads[origin] \in Keys)

ExtractedNodePlan(emitted, fallbackRead) ==
    [count |-> emitted.count,
     kinds |-> [index \in 1..emitted.count |-> emitted.nodes[index].kind],
     literals |-> [index \in 1..emitted.count |->
         IF emitted.nodes[index].kind = "literal" THEN emitted.nodes[index].payload ELSE 0],
     reads |-> [index \in 1..emitted.count |->
         IF emitted.nodes[index].kind = "read" THEN emitted.nodes[index].payload ELSE fallbackRead],
     left |-> [index \in 1..emitted.count |-> emitted.nodes[index].left],
     right |-> [index \in 1..emitted.count |-> emitted.nodes[index].right]]

THEOREM SourceMatchedNodesSupplyTheTypedExpressionPlan ==
    ASSUME NEW view, NEW emitted, NEW fallbackRead \in Keys,
           NEW state \in [Keys -> SwiftIntMin..SwiftIntMax],
           NodeEmissionArrays(emitted), emitted.count > 0,
           AllNodePayloadsMatchSource(view, emitted), TypedVisitedSourceInputs(view, emitted)
    PROVE LET plan == ExtractedNodePlan(emitted, fallbackRead)
          IN ExpressionPlan(plan.count, plan.kinds, plan.literals, plan.reads, plan.left, plan.right, state)
    PROOF
    <1>. DEFINE plan == ExtractedNodePlan(emitted, fallbackRead)
    <1>0. USE IntegerDomain DEF IntegerDomain
    <1>1. \A index \in 1..emitted.count :
        /\ emitted.nodes[index].kind \in {"literal", "read", "add"}
        /\ plan.literals[index] \in SwiftIntMin..SwiftIntMax
        /\ plan.reads[index] \in Keys
        BY SMT DEF plan, ExtractedNodePlan, AllNodePayloadsMatchSource, NodePayloadMatchesSource,
            TypedVisitedSourceInputs, InRange, NodeEmissionArrays
    <1>2. \A index \in 1..emitted.count :
        /\ plan.left[index] \in 0..emitted.count
        /\ plan.right[index] \in 0..emitted.count
        /\ (plan.kinds[index] = "add" =>
               /\ plan.left[index] \in 1..(index - 1)
               /\ plan.right[index] \in 1..(index - 1))
        BY SMT DEF plan, ExtractedNodePlan, AllNodePayloadsMatchSource,
            NodePayloadMatchesSource, NodeEmissionArrays
    <1>. QED BY <1>1, <1>2, SMT
        DEF plan, ExtractedNodePlan, ExpressionPlan, NodeEmissionArrays

THEOREM SuccessfulSynchronizedVisitSuppliesItsExpressionPlan ==
    ASSUME NEW steps, NEW root, NEW view, NEW heights, NEW pendings, NEW currents, NEW emissions,
           SynchronizedNodeHistory(steps, root, view, heights, pendings, currents, emissions),
           heights[steps] = 0,
           TypedVisitedSourceInputs(view, emissions[steps]),
           NEW fallbackRead \in Keys, NEW state \in [Keys -> SwiftIntMin..SwiftIntMax]
    PROVE LET plan == ExtractedNodePlan(emissions[steps], fallbackRead)
          IN /\ ExpressionPlan(plan.count, plan.kinds, plan.literals, plan.reads, plan.left, plan.right, state)
             /\ emissions[steps].origins[plan.count] = root
             /\ AllNodePayloadsMatchSource(view, emissions[steps])
    PROOF
    <1>0. \A step \in 0..steps :
        /\ NodeEmissionArrays(emissions[step])
        /\ NodeRootsMatchVisitPrefix(emissions[step], currents[step])
        /\ AllNodePayloadsMatchSource(view, emissions[step])
        BY SynchronizedNodeHistoryPreservesEverySourcePayload
    <1>1. NodeEmissionArrays(emissions[steps])
          /\ AllNodePayloadsMatchSource(view, emissions[steps])
        BY <1>0, SMT DEF SynchronizedNodeHistory, PendingVisitHistory
    <1>2. emissions[steps].count > 0
          /\ emissions[steps].origins[emissions[steps].count] = root
        BY SuccessfulSynchronizedVisitIdentifiesTheEmittedSourceRoot, SMT
    <1>3. LET plan == ExtractedNodePlan(emissions[steps], fallbackRead)
          IN ExpressionPlan(plan.count, plan.kinds, plan.literals, plan.reads, plan.left, plan.right, state)
        BY <1>1, <1>2, SourceMatchedNodesSupplyTheTypedExpressionPlan
    <1>. QED BY <1>1, <1>2, <1>3 DEF ExtractedNodePlan

\* Source meaning is indexed by syntax nodes, before an emitted plan exists.
SourceSyntaxHistory(view, state, meaning) ==
    /\ DOMAIN meaning = DOMAIN view.kinds
    /\ \A node \in DOMAIN view.kinds : meaning[node] =
        IF view.kinds[node] = "literal" THEN Success(view.literals[node])
        ELSE IF view.kinds[node] = "read" THEN Success(state[view.reads[node]])
        ELSE SourceCombine(meaning[view.left[node]], meaning[view.right[node]])

EmittedSourceSyntaxHistory(emitted, meaning) ==
    [index \in 0..emitted.count |->
        IF index = 0 THEN Success(0) ELSE meaning[emitted.origins[index]]]

THEOREM MatchedPostorderNodesRetainIndependentSourceSyntaxMeaning ==
    ASSUME NEW view, NEW emitted, NEW state, NEW meaning,
           NodeEmissionArrays(emitted), emitted.count > 0,
           AllNodePayloadsMatchSource(view, emitted),
           {emitted.origins[index] : index \in 1..emitted.count} \subseteq DOMAIN view.kinds,
           SourceSyntaxHistory(view, state, meaning), NEW fallbackRead \in Keys
    PROVE LET plan == ExtractedNodePlan(emitted, fallbackRead)
              history == EmittedSourceSyntaxHistory(emitted, meaning)
          IN /\ SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
                    plan.reads, plan.left, plan.right, state, history)
             /\ history[plan.count] = meaning[emitted.origins[emitted.count]]
    PROOF
    <1>. DEFINE plan == ExtractedNodePlan(emitted, fallbackRead)
                history == EmittedSourceSyntaxHistory(emitted, meaning)
    <1>1. \A index \in 1..emitted.count :
        history[index] = SourceNode(index, plan.kinds, plan.literals,
            plan.reads, plan.left, plan.right, state, history)
        <2>. SUFFICES ASSUME NEW index \in 1..emitted.count
                     PROVE history[index] = SourceNode(index, plan.kinds, plan.literals,
                         plan.reads, plan.left, plan.right, state, history)
            BY SMT
        <2>1. emitted.origins[index] \in DOMAIN view.kinds
              /\ NodePayloadMatchesSource(view, emitted, index)
            BY SMT DEF AllNodePayloadsMatchSource
        <2>2. emitted.nodes[index].kind \in {"literal", "read", "add"}
            BY <2>1 DEF NodePayloadMatchesSource
        <2>3. CASE emitted.nodes[index].kind = "literal"
            BY <2>1, <2>3, SMT DEF history, plan, EmittedSourceSyntaxHistory,
                ExtractedNodePlan, SourceNode, SourceSyntaxHistory, NodePayloadMatchesSource
        <2>4. CASE emitted.nodes[index].kind = "read"
            BY <2>1, <2>4, SMT DEF history, plan, EmittedSourceSyntaxHistory,
                ExtractedNodePlan, SourceNode, SourceSyntaxHistory, NodePayloadMatchesSource
        <2>5. CASE emitted.nodes[index].kind = "add"
            <3>1. emitted.count \in Nat
                  /\ emitted.nodes[index].left \in 1..emitted.count
                  /\ emitted.nodes[index].right \in 1..emitted.count
                BY <2>1, <2>5, SMT DEF NodeEmissionArrays, NodePayloadMatchesSource
            <3>2. emitted.origins[emitted.nodes[index].left] = view.left[emitted.origins[index]]
                  /\ emitted.origins[emitted.nodes[index].right] = view.right[emitted.origins[index]]
                BY <2>1, <2>5, SMT DEF NodePayloadMatchesSource
            <3>3. history[emitted.nodes[index].left] = meaning[view.left[emitted.origins[index]]]
                  /\ history[emitted.nodes[index].right] = meaning[view.right[emitted.origins[index]]]
                BY <3>1, <3>2, SMT DEF history, EmittedSourceSyntaxHistory
            <3>4. meaning[emitted.origins[index]] = SourceCombine(
                meaning[view.left[emitted.origins[index]]], meaning[view.right[emitted.origins[index]]])
                BY <2>1, <2>5, SMT DEF SourceSyntaxHistory, NodePayloadMatchesSource
            <3>. QED BY <2>5, <3>1, <3>3, <3>4, SMT
                DEF history, plan, EmittedSourceSyntaxHistory, ExtractedNodePlan, SourceNode
        <2>. QED BY <2>2, <2>3, <2>4, <2>5, SMT
    <1>2. emitted.count \in Nat /\ 0 \in 0..emitted.count
          /\ emitted.count \in 0..emitted.count
        BY SMT DEF NodeEmissionArrays
    <1>3. history[0] = Success(0)
          /\ history[plan.count] = meaning[emitted.origins[emitted.count]]
        BY <1>2, SMT DEF history, plan, EmittedSourceSyntaxHistory, ExtractedNodePlan
    <1>4. SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
        plan.reads, plan.left, plan.right, state, history)
        BY <1>1, <1>3 DEF SourceExpressionHistory, plan, ExtractedNodePlan
    <1>. QED BY <1>3, <1>4 DEF history, plan

\* These project failures from a list; they do not evaluate syntax or emitted code.
EveryRootSucceeded(count, roots, meaning) ==
    \A position \in 1..count : meaning[roots[position]].ok
FirstRootFailureIs(count, roots, meaning, outcome) ==
    /\ ~outcome.ok
    /\ \E position \in 1..count :
        /\ meaning[roots[position]] = outcome
        /\ \A earlier \in 1..(position - 1) : meaning[roots[earlier]].ok

THEOREM AppendingARootRetainsTheFirstFailure ==
    ASSUME NEW count \in Nat, NEW roots, NEW meaning, NEW node
    PROVE /\ EveryRootSucceeded(count + 1, HistoryAppend(roots, count, node), meaning)
                 <=> (EveryRootSucceeded(count, roots, meaning) /\ meaning[node].ok)
          /\ \A outcome :
              FirstRootFailureIs(count + 1, HistoryAppend(roots, count, node), meaning, outcome)
              <=> (FirstRootFailureIs(count, roots, meaning, outcome)
                   \/ (EveryRootSucceeded(count, roots, meaning)
                       /\ ~meaning[node].ok /\ outcome = meaning[node]))
    PROOF
    <1>1. \A position \in 1..count : HistoryAppend(roots, count, node)[position] = roots[position]
        BY SMT DEF HistoryAppend
    <1>2. HistoryAppend(roots, count, node)[count + 1] = node
        BY SMT DEF HistoryAppend
    <1>. QED BY <1>1, <1>2, SMT DEF EveryRootSucceeded, FirstRootFailureIs

THEOREM FoldingOrderedChildrenRetainsTheFirstFailure ==
    ASSUME NEW height \in Nat, height >= 2, NEW roots, NEW meaning, NEW node,
           meaning[node] = SourceCombine(meaning[roots[height - 1]], meaning[roots[height]])
    PROVE /\ EveryRootSucceeded(height - 1, HistoryAppend(roots, height - 2, node), meaning)
                 <=> (EveryRootSucceeded(height, roots, meaning) /\ meaning[node].ok)
          /\ \A outcome :
              FirstRootFailureIs(height - 1, HistoryAppend(roots, height - 2, node), meaning, outcome)
              <=> (FirstRootFailureIs(height, roots, meaning, outcome)
                   \/ (EveryRootSucceeded(height, roots, meaning)
                       /\ ~meaning[node].ok /\ outcome = meaning[node]))
    PROOF
    <1>. DEFINE first == meaning[roots[height - 1]]
                second == meaning[roots[height]]
                folded == HistoryAppend(roots, height - 2, node)
    <1>1. \A position \in 1..(height - 2) : folded[position] = roots[position]
        BY SMT DEF folded, HistoryAppend
    <1>2. folded[height - 1] = node
        BY SMT DEF folded, HistoryAppend
    <1>3. /\ (meaning[node].ok => first.ok /\ second.ok)
          /\ (~first.ok => meaning[node] = first)
          /\ (first.ok /\ ~second.ok => meaning[node] = second)
        BY SMT DEF first, second, SourceCombine, SourceAdd, Success, SourceOverflow
    <1>4. EveryRootSucceeded(height - 1, folded, meaning)
              <=> (EveryRootSucceeded(height, roots, meaning) /\ meaning[node].ok)
        BY <1>1, <1>2, <1>3, SMT DEF EveryRootSucceeded, first, second
    <1>5. \A outcome : FirstRootFailureIs(height, roots, meaning, outcome)
              => FirstRootFailureIs(height - 1, folded, meaning, outcome)
        <2>. SUFFICES ASSUME NEW outcome, FirstRootFailureIs(height, roots, meaning, outcome)
                     PROVE FirstRootFailureIs(height - 1, folded, meaning, outcome)
            BY SMT
        <2>1. PICK position \in 1..height :
            meaning[roots[position]] = outcome
            /\ \A earlier \in 1..(position - 1) : meaning[roots[earlier]].ok
            BY SMT DEF FirstRootFailureIs
        <2>2. CASE position <= height - 2
            BY <2>1, <2>2, <1>1, SMT DEF FirstRootFailureIs
        <2>3. CASE position = height - 1
            BY <2>1, <2>3, <1>1, <1>2, <1>3, SMT DEF FirstRootFailureIs, first
        <2>4. CASE position = height
            BY <2>1, <2>4, <1>1, <1>2, <1>3, SMT DEF FirstRootFailureIs, first, second
        <2>. QED BY <2>1, <2>2, <2>3, <2>4, SMT
    <1>6. \A outcome :
        FirstRootFailureIs(height - 1, folded, meaning, outcome)
        => (FirstRootFailureIs(height, roots, meaning, outcome)
            \/ (EveryRootSucceeded(height, roots, meaning)
                /\ ~meaning[node].ok /\ outcome = meaning[node]))
        <2>. SUFFICES ASSUME NEW outcome,
                             FirstRootFailureIs(height - 1, folded, meaning, outcome)
                     PROVE FirstRootFailureIs(height, roots, meaning, outcome)
                         \/ (EveryRootSucceeded(height, roots, meaning)
                             /\ ~meaning[node].ok /\ outcome = meaning[node])
            BY SMT
        <2>1. PICK position \in 1..(height - 1) :
            meaning[folded[position]] = outcome
            /\ \A earlier \in 1..(position - 1) : meaning[folded[earlier]].ok
            BY SMT DEF FirstRootFailureIs
        <2>2. CASE position <= height - 2
            BY <2>1, <2>2, <1>1, SMT DEF FirstRootFailureIs
        <2>3. CASE position = height - 1 /\ ~first.ok
            BY <2>1, <2>3, <1>1, <1>2, <1>3, SMT DEF FirstRootFailureIs, first
        <2>4. CASE position = height - 1 /\ first.ok /\ ~second.ok
            BY <2>1, <2>4, <1>1, <1>2, <1>3, SMT DEF FirstRootFailureIs, first, second
        <2>5. CASE position = height - 1 /\ first.ok /\ second.ok
            BY <2>1, <2>5, <1>1, <1>2, SMT
                DEF FirstRootFailureIs, EveryRootSucceeded, first, second
        <2>. QED BY <2>1, <2>2, <2>3, <2>4, <2>5, SMT
    <1>7. \A outcome : (EveryRootSucceeded(height, roots, meaning)
            /\ ~meaning[node].ok /\ outcome = meaning[node])
        => FirstRootFailureIs(height - 1, folded, meaning, outcome)
        BY <1>1, <1>2, SMT DEF FirstRootFailureIs, EveryRootSucceeded
    <1>. QED BY <1>4, <1>5, <1>6, <1>7, SMT DEF folded

VisitFailureProjection(emitted, current, meaning) ==
    /\ (EveryRootSucceeded(emitted.count, emitted.origins, meaning)
         <=> EveryRootSucceeded(current.height, current.terms, meaning))
    /\ \A outcome : FirstRootFailureIs(emitted.count, emitted.origins, meaning, outcome)
         <=> FirstRootFailureIs(current.height, current.terms, meaning, outcome)

THEOREM CompletedSyntaxVisitIdentifiesTheFirstReachedFailure ==
    ASSUME NEW steps, NEW root, NEW view, NEW heights, NEW pendings, NEW currents, NEW emissions,
           NEW state, NEW meaning,
           SynchronizedNodeHistory(steps, root, view, heights, pendings, currents, emissions),
           heights[steps] = 0, SourceSyntaxHistory(view, state, meaning),
           \A step \in 1..steps : pendings[step - 1][heights[step - 1]].node \in DOMAIN view.kinds
    PROVE /\ (meaning[root].ok
              <=> EveryRootSucceeded(emissions[steps].count, emissions[steps].origins, meaning))
          /\ \A outcome : FirstRootFailureIs(emissions[steps].count,
                 emissions[steps].origins, meaning, outcome)
              <=> (~meaning[root].ok /\ outcome = meaning[root])
    PROOF
    <1>. DEFINE holds(step) == VisitFailureProjection(emissions[step], currents[step], meaning)
    <1>0. steps \in Nat
        BY SMT DEF SynchronizedNodeHistory, PendingVisitHistory
    <1>0a. \A step \in 0..steps :
        /\ NodeEmissionArrays(emissions[step])
        /\ NodeRootsMatchVisitPrefix(emissions[step], currents[step])
        /\ AllNodePayloadsMatchSource(view, emissions[step])
        BY SynchronizedNodeHistoryPreservesEverySourcePayload
    <1>1. \A step \in 0..steps : PendingVisitContract(heights[step], pendings[step], currents[step],
        PushVisitPrefix(EmptyVisitPrefix, root), view.left, view.right)
        BY PendingVisitHistoryPreservesTheSourceRootContext, SMT DEF SynchronizedNodeHistory
    <1>2. holds(0)
        BY SMT DEF holds, VisitFailureProjection, SynchronizedNodeHistory, PendingVisitHistory,
            EmptyNodeEmission, EmptyVisitPrefix, VisitPrefix, EveryRootSucceeded, FirstRootFailureIs
    <1>3. \A step \in 1..steps :
        ((\A prior \in 0..(step - 1) : holds(prior)) => holds(step))
        <2>. SUFFICES ASSUME NEW step \in 1..steps,
                             \A prior \in 0..(step - 1) : holds(prior)
                     PROVE holds(step)
            BY SMT
        <2>. DEFINE frame == pendings[step - 1][heights[step - 1]]
                    emitted == emissions[step - 1]
                    current == currents[step - 1]
                    next == emissions[step]
                    nextCurrent == currents[step]
        <2>0. step \in Nat /\ step - 1 \in 0..steps
              /\ step - 1 \in 0..(step - 1)
              /\ heights[step - 1] > 0
            BY <1>0, SMT DEF SynchronizedNodeHistory, PendingVisitHistory, PendingVisitStep
        <2>1. holds(step - 1) /\ frame.node \in DOMAIN view.kinds
              /\ PendingVisitContract(heights[step - 1], pendings[step - 1], current,
                     PushVisitPrefix(EmptyVisitPrefix, root), view.left, view.right)
              /\ PendingVisitStep(view.kinds, view.left, view.right, heights[step - 1],
                     pendings[step - 1], current, heights[step], pendings[step], nextCurrent)
              /\ NodeEmissionStep(view, frame, emitted, next)
            BY <1>1, <2>0, SMT DEF frame, emitted, current, next, nextCurrent,
                SynchronizedNodeHistory, PendingVisitHistory
        <2>1a. /\ NodeEmissionArrays(emitted)
               /\ NodeRootsMatchVisitPrefix(emitted, current)
               /\ emitted.count \in Nat /\ current.height \in Nat
               /\ frame.prefix = current
               /\ WellFormedVisitFrame(frame, view.left, view.right)
            BY <1>0a, <2>0, <2>1, SMT
                DEF emitted, current, frame, PendingVisitContract,
                    NodeEmissionArrays, NodeRootsMatchVisitPrefix
        <2>2. CASE ~frame.expanded /\ view.kinds[frame.node] = "add"
            BY <2>1, <2>2, SMT DEF holds, NodeEmissionStep, PendingVisitStep,
                frame, emitted, current, next, nextCurrent
        <2>3. CASE ~(~frame.expanded /\ view.kinds[frame.node] = "add")
            <3>1. /\ frame.prefix = current
                  /\ WellFormedVisitFrame(frame, view.left, view.right)
                  /\ next = AppendVisitNode(view, frame, emitted)
                  /\ nextCurrent = VisitFrameExit(frame)
                  /\ NodeEmissionArrays(emitted)
                  /\ NodeRootsMatchVisitPrefix(emitted, current)
                  /\ ((frame.expanded /\ view.kinds[frame.node] = "add")
                      \/ (~frame.expanded /\ view.kinds[frame.node] \in {"literal", "read"}))
                BY <2>0, <2>1, <2>1a, <2>3, SMT
                    DEF frame, emitted, current, next, nextCurrent,
                        PendingVisitContract, PendingVisitStep, NodeEmissionStep
            <3>2. /\ next.count = emitted.count + 1
                  /\ next.origins = HistoryAppend(emitted.origins, emitted.count, frame.node)
                BY <3>1 DEF AppendVisitNode
            <3>3. CASE ~frame.expanded
                <4>1. nextCurrent = PushVisitPrefix(current, frame.node) /\ meaning[frame.node].ok
                    BY <2>1, <3>1, <3>3, SMT
                        DEF VisitFrameExit, SourceSyntaxHistory, Success
                <4>. QED BY <2>1, <2>1a, <3>1, <3>2, <4>1, AppendingARootRetainsTheFirstFailure, SMT
                    DEF holds, VisitFailureProjection, PushVisitPrefix, VisitPrefix,
                        frame, emitted, current, next, nextCurrent
            <3>4. CASE frame.expanded
                <4>1. current.height \in Nat /\ current.height >= 2
                      /\ nextCurrent = FoldVisitPrefix(current, frame.node)
                      /\ meaning[frame.node] = SourceCombine(
                             meaning[current.terms[current.height - 1]],
                             meaning[current.terms[current.height]])
                    BY <2>1, <3>1, <3>4, SMT DEF WellFormedVisitFrame,
                        WellFormedVisitPrefix, VisitFrameExit, SourceSyntaxHistory
                <4>2a. \A position \in 1..emitted.count :
                    HistoryAppend(emitted.origins, emitted.count, frame.node)[position]
                        = emitted.origins[position]
                    BY <2>1a, SMT DEF HistoryAppend
                <4>2b. HistoryAppend(emitted.origins, emitted.count, frame.node)[emitted.count + 1]
                    = frame.node
                    BY <2>1a, SMT DEF HistoryAppend
                <4>2. /\ EveryRootSucceeded(emitted.count + 1,
                             HistoryAppend(emitted.origins, emitted.count, frame.node), meaning)
                          <=> (EveryRootSucceeded(emitted.count, emitted.origins, meaning)
                               /\ meaning[frame.node].ok)
                      /\ \A outcome : FirstRootFailureIs(emitted.count + 1,
                             HistoryAppend(emitted.origins, emitted.count, frame.node), meaning, outcome)
                          <=> (FirstRootFailureIs(emitted.count, emitted.origins, meaning, outcome)
                               \/ (EveryRootSucceeded(emitted.count, emitted.origins, meaning)
                                   /\ ~meaning[frame.node].ok /\ outcome = meaning[frame.node]))
                    BY <2>1a, <4>2a, <4>2b, AppendingARootRetainsTheFirstFailure, SMT
                        DEF EveryRootSucceeded, FirstRootFailureIs
                <4>3. /\ EveryRootSucceeded(nextCurrent.height, nextCurrent.terms, meaning)
                          <=> (EveryRootSucceeded(current.height, current.terms, meaning)
                               /\ meaning[frame.node].ok)
                      /\ \A outcome : FirstRootFailureIs(nextCurrent.height, nextCurrent.terms, meaning, outcome)
                          <=> (FirstRootFailureIs(current.height, current.terms, meaning, outcome)
                               \/ (EveryRootSucceeded(current.height, current.terms, meaning)
                                   /\ ~meaning[frame.node].ok /\ outcome = meaning[frame.node]))
                    BY <4>1, FoldingOrderedChildrenRetainsTheFirstFailure, SMT
                        DEF FoldVisitPrefix, VisitPrefix
                <4>. QED BY <2>1, <3>2, <4>2, <4>3, SMT
                    DEF holds, VisitFailureProjection, FoldVisitPrefix, VisitPrefix,
                        frame, emitted, current, next, nextCurrent
            <3>. QED BY <3>3, <3>4, SMT
        <2>. QED BY <2>2, <2>3, SMT
    <1>4. steps \in Nat BY SMT DEF SynchronizedNodeHistory, PendingVisitHistory
    <1>5. \A step \in 0..steps : holds(step)
        BY <1>2, <1>3, <1>4, FiniteIndexedPrefixProperty
    <1>6. currents[steps].height = 1 /\ currents[steps].terms[1] = root
        BY SuccessfulPendingVisitReturnsOnlyItsSourceRoot, SMT DEF SynchronizedNodeHistory
    <1>. QED BY <1>4, <1>5, <1>6, SMT
        DEF holds, VisitFailureProjection, EveryRootSucceeded, FirstRootFailureIs

\* This is the exact unique-name count guard used by the initializer checker.
LayoutNamesFS == INSTANCE FiniteSetTheorems
LayoutNameRange(ids, names) == {names[id] : id \in ids}
LayoutStateByName(ids, names, values) ==
    [name \in LayoutNameRange(ids, names) |->
        values[CHOOSE id \in ids : names[id] = name]]

THEOREM UniqueLayoutNamesPreserveEveryReadValue ==
    ASSUME NEW ids, LayoutNamesFS!IsFiniteSet(ids),
           NEW nameUniverse, NEW names \in [ids -> nameUniverse],
           LayoutNamesFS!Cardinality(LayoutNameRange(ids, names)) =
               LayoutNamesFS!Cardinality(ids),
           NEW readIDs \in SUBSET ids,
           NEW values \in [readIDs -> SwiftIntMin..SwiftIntMax]
    PROVE /\ \A first, second \in ids : names[first] = names[second] => first = second
          /\ LayoutStateByName(readIDs, names, values) \in
                 [LayoutNameRange(readIDs, names) -> SwiftIntMin..SwiftIntMax]
          /\ \A id \in readIDs : LayoutStateByName(readIDs, names, values)[names[id]] = values[id]
    PROOF
    <1>1. names \in LayoutNamesFS!Surjection(ids, LayoutNameRange(ids, names))
        BY SMT DEF LayoutNamesFS!Surjection, LayoutNameRange
    <1>2. names \in LayoutNamesFS!Injection(ids, LayoutNameRange(ids, names))
        BY <1>1, LayoutNamesFS!FS_SurjSameCardinalityImpliesInj
    <1>3. \A first, second \in ids : names[first] = names[second] => first = second
        BY <1>2, SMT DEF LayoutNamesFS!Injection, LayoutNamesFS!IsInjective
    <1>4. \A name \in LayoutNameRange(readIDs, names) :
          (CHOOSE id \in readIDs : names[id] = name) \in readIDs
        BY SMT DEF LayoutNameRange
    <1>5. \A id \in readIDs : (CHOOSE other \in readIDs : names[other] = names[id]) = id
        BY <1>3, SMT
    <1>6. LayoutStateByName(readIDs, names, values) \in
              [LayoutNameRange(readIDs, names) -> SwiftIntMin..SwiftIntMax]
        BY <1>4, SMT DEF LayoutStateByName, LayoutNameRange
    <1>7. \A id \in readIDs : LayoutStateByName(readIDs, names, values)[names[id]] = values[id]
        <2>1. TAKE id \in readIDs
        <2>2. names[id] \in LayoutNameRange(readIDs, names)
            BY SMT DEF LayoutNameRange
        <2>3. (CHOOSE other \in readIDs : names[other] = names[id]) = id
            BY <1>5
        <2>. QED BY <2>2, <2>3 DEF LayoutStateByName
    <1>. QED BY <1>3, <1>6, <1>7

THEOREM StackReadKeysAfterPush ==
    ASSUME NEW height \in Nat, NEW stack, NEW effects, NEW node,
           effects[node] \subseteq Keys
    PROVE StackReadKeys(HistoryAppend(stack, height, node), height + 1, effects)
        = StackReadKeys(stack, height, effects) \cup effects[node]
    PROOF
    <1>1. \A position \in 1..height :
        HistoryAppend(stack, height, node)[position] = stack[position]
        BY SMT DEF HistoryAppend
    <1>2. HistoryAppend(stack, height, node)[height + 1] = node
        BY SMT DEF HistoryAppend
    <1>3. \A key \in Keys :
        key \in StackReadKeys(HistoryAppend(stack, height, node), height + 1, effects)
        <=> key \in StackReadKeys(stack, height, effects) \cup effects[node]
        BY <1>1, <1>2, SMT DEF StackReadKeys
    <1>. QED BY <1>3, SMT DEF StackReadKeys

THEOREM StackReadKeysAfterFold ==
    ASSUME NEW height \in Nat, height >= 2, NEW stack, NEW effects, NEW node,
           effects[node] = effects[stack[height - 1]] \cup effects[stack[height]]
    PROVE StackReadKeys(HistoryAppend(stack, height - 2, node), height - 1, effects)
        = StackReadKeys(stack, height, effects)
    PROOF
    <1>1. \A position \in 1..(height - 2) :
        HistoryAppend(stack, height - 2, node)[position] = stack[position]
        BY SMT DEF HistoryAppend
    <1>2. HistoryAppend(stack, height - 2, node)[height - 1] = node
        BY SMT DEF HistoryAppend
    <1>3. \A key \in Keys :
        key \in StackReadKeys(HistoryAppend(stack, height - 2, node), height - 1, effects)
        <=> key \in StackReadKeys(stack, height, effects)
        BY <1>1, <1>2, SMT DEF StackReadKeys
    <1>. QED BY <1>3, SMT DEF StackReadKeys

THEOREM ReadKeysAtNextNode ==
    ASSUME NEW count \in Nat, NEW index \in 1..count,
           NEW kinds, NEW reads
    PROVE ExpressionReadKeys(index, kinds, reads) =
        ExpressionReadKeys(index - 1, kinds, reads) \cup
            IF kinds[index] = "read" THEN {reads[index]} ELSE {}
    BY SMT DEF ExpressionReadKeys

THEOREM ConstructedPlanPreservesAllReads ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, NEW effects, NEW heights, NEW stacks,
           ExpressionPlan(count, kinds, literals, reads, left, right, state),
           ExpressionReadHistory(count, kinds, reads, left, right, effects),
           ExpressionIndexStack(count, kinds, left, right, heights, stacks)
    PROVE effects[count] = ExpressionReadKeys(count, kinds, reads)
    PROOF
    <1>. DEFINE P(index) == StackReadKeys(stacks[index], heights[index], effects)
        = ExpressionReadKeys(index, kinds, reads)
    <1>1. P(0)
        BY SMT DEF P, StackReadKeys, ExpressionIndexStack, ExpressionReadKeys
    <1>2. \A index \in 1..count :
        ((\A prior \in 0..(index - 1) : P(prior)) => P(index))
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A prior \in 0..(index - 1) : P(prior)
                     PROVE P(index)
            BY SMT
        <2>1. P(index - 1) BY SMT DEF ExpressionPlan
        <2>2. count \in Nat /\ heights[index - 1] \in Nat
              /\ effects[index] \subseteq Keys
            BY SMT DEF ExpressionPlan, ExpressionIndexStack, ExpressionReadHistory
        <2>3. CASE kinds[index] = "add"
            <3>1. effects[index] = effects[stacks[index - 1][heights[index - 1] - 1]]
                    \cup effects[stacks[index - 1][heights[index - 1]]]
                BY <2>3, SMT DEF ExpressionReadHistory, ReadEffectNode, ExpressionIndexStack
            <3>2. StackReadKeys(stacks[index], heights[index], effects)
                    = StackReadKeys(stacks[index - 1], heights[index - 1], effects)
                BY <2>2, <2>3, <3>1, StackReadKeysAfterFold, SMT DEF ExpressionIndexStack
            <3>3. ExpressionReadKeys(index, kinds, reads) = ExpressionReadKeys(index - 1, kinds, reads)
                BY <2>3, SMT DEF ExpressionReadKeys
            <3>. QED BY <2>1, <3>2, <3>3, SMT DEF P
        <2>4. CASE kinds[index] # "add"
            <3>1. effects[index] = IF kinds[index] = "read" THEN {reads[index]} ELSE {}
                BY <2>4, SMT DEF ExpressionPlan, ExpressionReadHistory, ReadEffectNode
            <3>2. StackReadKeys(stacks[index], heights[index], effects)
                    = StackReadKeys(stacks[index - 1], heights[index - 1], effects) \cup effects[index]
                BY <2>2, <2>4, StackReadKeysAfterPush, SMT DEF ExpressionIndexStack
            <3>. QED BY <2>1, <3>1, <3>2, ReadKeysAtNextNode, SMT DEF P
        <2>. QED BY <2>3, <2>4, SMT
    <1>3. count \in Nat /\ count \in 1..count BY SMT DEF ExpressionPlan
    <1>4. \A index \in 0..count : P(index)
        BY <1>1, <1>2, <1>3, FiniteIndexedPrefixProperty
    <1>5. heights[count] = 1 /\ stacks[count][1] = count
        BY <1>3, SMT DEF ExpressionIndexStack, HistoryAppend
    <1>6. effects[count] \subseteq Keys
        BY <1>3, SMT DEF ExpressionReadHistory
    <1>7. StackReadKeys(stacks[count], heights[count], effects) = effects[count]
        BY <1>5, <1>6, SMT DEF StackReadKeys
    <1>. QED BY <1>3, <1>4, <1>7, SMT DEF P

ReadWalkStep(kinds, reads, left, right, height, stack, found,
             nextHeight, nextStack, nextFound) ==
    LET node == stack[height]
        rest == HistoryPrefix(stack, height - 1)
    IN IF kinds[node] = "add" THEN
        /\ nextHeight = height + 1
        /\ nextStack = HistoryAppend(HistoryAppend(rest, height - 1, left[node]), height, right[node])
        /\ nextFound = found
    ELSE
        /\ nextHeight = height - 1
        /\ nextStack = rest
        /\ nextFound = IF kinds[node] = "read" THEN found \cup {reads[node]} ELSE found

THEOREM ReadWalkStepPreservesReadEffects ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, NEW effects, NEW height \in Nat \ {0},
           NEW stack \in [1..height -> 1..count], NEW found,
           NEW nextHeight, NEW nextStack, NEW nextFound,
           ExpressionPlan(count, kinds, literals, reads, left, right, state),
           ExpressionReadHistory(count, kinds, reads, left, right, effects),
           ReadWalkStep(kinds, reads, left, right, height, stack, found,
               nextHeight, nextStack, nextFound)
    PROVE found \cup StackReadKeys(stack, height, effects)
        = nextFound \cup StackReadKeys(nextStack, nextHeight, effects)
    PROOF
    <1>. DEFINE node == stack[height]
                rest == HistoryPrefix(stack, height - 1)
    <1>1. node \in 1..count /\ height - 1 \in Nat /\ effects[node] \subseteq Keys
        BY SMT DEF node, ExpressionReadHistory
    <1>2. HistoryAppend(rest, height - 1, node) = stack
        BY SMT DEF rest, node, HistoryPrefix, HistoryAppend
    <1>3. StackReadKeys(stack, height, effects)
        = StackReadKeys(rest, height - 1, effects) \cup effects[node]
        BY <1>1, <1>2, StackReadKeysAfterPush, SMT
    <1>4. CASE kinds[node] = "add"
        <2>1. effects[left[node]] \subseteq Keys /\ effects[right[node]] \subseteq Keys
              /\ effects[node] = effects[left[node]] \cup effects[right[node]]
            BY <1>1, <1>4, SMT DEF ExpressionPlan, ExpressionReadHistory, ReadEffectNode
        <2>2. StackReadKeys(HistoryAppend(rest, height - 1, left[node]), height, effects)
            = StackReadKeys(rest, height - 1, effects) \cup effects[left[node]]
            BY <1>1, <2>1, StackReadKeysAfterPush, SMT
        <2>3. StackReadKeys(nextStack, nextHeight, effects)
            = StackReadKeys(rest, height - 1, effects) \cup effects[left[node]] \cup effects[right[node]]
            BY <1>4, <2>1, <2>2, StackReadKeysAfterPush, SMT DEF ReadWalkStep, node, rest
        <2>. QED BY <1>3, <1>4, <2>1, <2>3, SMT DEF ReadWalkStep, node
    <1>5. CASE kinds[node] # "add"
        <2>1. effects[node] = IF kinds[node] = "read" THEN {reads[node]} ELSE {}
            BY <1>1, <1>5, SMT DEF ExpressionPlan, ExpressionReadHistory, ReadEffectNode
        <2>. QED BY <1>3, <1>5, <2>1, SMT DEF ReadWalkStep, node, rest
    <1>. QED BY <1>4, <1>5, SMT

NodeWork(index, kinds, left, right, weights) ==
    IF kinds[index] = "add" THEN 1 + weights[left[index]] + weights[right[index]] ELSE 1
ExpressionWorkHistory(count, kinds, left, right, weights) ==
    /\ weights \in [1..count -> Nat \ {0}]
    /\ \A index \in 1..count : weights[index] = NodeWork(index, kinds, left, right, weights)

THEOREM ExpressionWorkHistoryExists ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, ExpressionPlan(count, kinds, literals, reads, left, right, state)
    PROVE \E weights : ExpressionWorkHistory(count, kinds, left, right, weights)
    PROOF
    <1>. DEFINE steps == [index \in 1..count |->
        [history \in [1..(index - 1) -> Nat \ {0}] |-> NodeWork(index, kinds, left, right, history)]]
    <1>1. \A index \in 1..count :
        steps[index] \in [[1..(index - 1) -> Nat \ {0}] -> Nat \ {0}]
        BY SMT DEF steps, NodeWork, ExpressionPlan
    <1>2. count \in Nat BY SMT DEF ExpressionPlan
    <1>3. PICK weights \in [1..count -> Nat \ {0}] : IndexedHistory(steps, weights, count)
        BY <1>1, <1>2, FiniteIndexedHistoryExists
    <1>4. \A index \in 1..count :
        HistoryPrefix(weights, index - 1) \in [1..(index - 1) -> Nat \ {0}]
        BY <1>2, <1>3, SMT DEF HistoryPrefix
    <1>4a. \A index \in 1..count :
        NodeWork(index, kinds, left, right, HistoryPrefix(weights, index - 1))
            = NodeWork(index, kinds, left, right, weights)
        BY SMT DEF HistoryPrefix, NodeWork, ExpressionPlan
    <1>5. \A index \in 1..count : weights[index] = NodeWork(index, kinds, left, right, weights)
        BY <1>3, <1>4, <1>4a, SMT DEF steps, IndexedHistory
    <1>6. ExpressionWorkHistory(count, kinds, left, right, weights)
        BY <1>3, <1>5 DEF ExpressionWorkHistory
    <1>. QED BY <1>6, SMT

StackWorkHistory(height, stack, weights, sums) ==
    /\ sums \in [0..height -> Nat]
    /\ sums[0] = 0
    /\ \A position \in 1..height :
        sums[position] = sums[position - 1] + weights[stack[position]]

THEOREM PositiveNodeWorkBoundsStackHeight ==
    ASSUME NEW count \in Nat, NEW height \in Nat,
           NEW stack \in [1..height -> 1..count],
           NEW weights \in [1..count -> Nat \ {0}], NEW sums,
           StackWorkHistory(height, stack, weights, sums)
    PROVE height <= sums[height]
    PROOF
    <1>. DEFINE P(position) == position <= sums[position]
    <1>1. P(0) BY SMT DEF P, StackWorkHistory
    <1>2. \A position \in 1..height :
        ((\A prior \in 0..(position - 1) : P(prior)) => P(position))
        <2>. SUFFICES ASSUME NEW position \in 1..height,
                             \A prior \in 0..(position - 1) : P(prior)
                     PROVE P(position)
            BY SMT
        <2>1. P(position - 1) BY SMT
        <2>2. weights[stack[position]] >= 1 BY SMT
        <2>. QED BY <2>1, <2>2, SMT DEF P, StackWorkHistory
    <1>3. HIDE DEF P
    <1>4. \A position \in 0..height : P(position)
        BY <1>1, <1>2, FiniteIndexedPrefixProperty
    <1>. QED BY <1>4, SMT DEF P

THEOREM ReadWalkHasAOneLessWorkSuccessor ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, NEW weights, NEW height \in Nat \ {0},
           NEW stack \in [1..height -> 1..count], NEW found \in SUBSET Keys, NEW sums,
           ExpressionPlan(count, kinds, literals, reads, left, right, state),
           ExpressionWorkHistory(count, kinds, left, right, weights),
           StackWorkHistory(height, stack, weights, sums)
    PROVE \E nextHeight, nextStack, nextFound, nextSums :
        /\ nextHeight \in Nat /\ nextFound \in SUBSET Keys
        /\ nextStack \in [1..nextHeight -> 1..count]
        /\ StackWorkHistory(nextHeight, nextStack, weights, nextSums)
        /\ nextSums[nextHeight] = sums[height] - 1
        /\ ReadWalkStep(kinds, reads, left, right, height, stack, found,
            nextHeight, nextStack, nextFound)
    PROOF
    <1>. DEFINE node == stack[height]
                rest == HistoryPrefix(stack, height - 1)
                nextHeight == IF kinds[node] = "add" THEN height + 1 ELSE height - 1
                nextStack == IF kinds[node] = "add"
                    THEN HistoryAppend(HistoryAppend(rest, height - 1, left[node]), height, right[node])
                    ELSE rest
                nextFound == IF kinds[node] = "read" THEN found \cup {reads[node]} ELSE found
                nextSums == [position \in 0..nextHeight |->
                    IF position < height THEN sums[position]
                    ELSE IF position = height THEN sums[height - 1] + weights[left[node]]
                    ELSE sums[height - 1] + weights[left[node]] + weights[right[node]]]
    <1>1. count \in Nat /\ node \in 1..count /\ height - 1 \in Nat
          /\ kinds[node] \in {"literal", "read", "add"}
          /\ weights \in [1..count -> Nat \ {0}]
          /\ sums \in [0..height -> Nat]
        BY SMT DEF node, ExpressionPlan, ExpressionWorkHistory, StackWorkHistory
    <1>2. CASE kinds[node] = "add"
        <2>1. left[node] \in 1..count /\ right[node] \in 1..count
              /\ weights[node] = 1 + weights[left[node]] + weights[right[node]]
            BY <1>1, <1>2, SMT DEF ExpressionPlan, ExpressionWorkHistory, NodeWork
        <2>2. nextHeight \in Nat /\ nextStack \in [1..nextHeight -> 1..count]
              /\ nextFound \in SUBSET Keys
            BY <1>1, <1>2, <2>1, SMT DEF nextHeight, nextStack, rest,
                nextFound, HistoryPrefix, HistoryAppend
        <2>3. nextSums \in [0..nextHeight -> Nat] /\ nextSums[0] = 0
            BY <1>1, <1>2, <2>1, SMT DEF nextSums, nextHeight, StackWorkHistory
        <2>4. \A position \in 1..nextHeight :
            nextSums[position] = nextSums[position - 1] + weights[nextStack[position]]
            BY <1>1, <1>2, <2>1, SMT DEF nextSums, nextHeight, nextStack, rest,
                StackWorkHistory, HistoryPrefix, HistoryAppend
        <2>5. nextSums[nextHeight] = sums[height] - 1
            BY <1>1, <1>2, <2>1, SMT DEF nextSums, nextHeight, StackWorkHistory, node
        <2>6. ReadWalkStep(kinds, reads, left, right, height, stack, found,
            nextHeight, nextStack, nextFound)
            BY <1>2, SMT DEF ReadWalkStep, node, rest, nextHeight, nextStack, nextFound
        <2>. QED BY <2>2, <2>3, <2>4, <2>5, <2>6, SMT DEF StackWorkHistory
    <1>3. CASE kinds[node] # "add"
        <2>1. weights[node] = 1 /\ (kinds[node] = "read" => reads[node] \in Keys)
            BY <1>1, <1>3, SMT DEF ExpressionPlan, ExpressionWorkHistory, NodeWork
        <2>2. nextHeight \in Nat /\ nextStack \in [1..nextHeight -> 1..count]
              /\ nextFound \in SUBSET Keys
            BY <1>1, <1>3, <2>1, SMT DEF nextHeight, nextStack, rest, nextFound, HistoryPrefix
        <2>3. StackWorkHistory(nextHeight, nextStack, weights, nextSums)
            BY <1>1, <1>3, SMT DEF nextHeight, nextStack, rest, nextSums, StackWorkHistory, HistoryPrefix
        <2>4. nextSums[nextHeight] = sums[height] - 1
            BY <1>1, <1>3, <2>1, SMT DEF nextSums, nextHeight, StackWorkHistory, node
        <2>5. ReadWalkStep(kinds, reads, left, right, height, stack, found,
            nextHeight, nextStack, nextFound)
            BY <1>3, SMT DEF ReadWalkStep, node, rest, nextHeight, nextStack, nextFound
        <2>. QED BY <2>2, <2>3, <2>4, <2>5, SMT
    <1>. QED BY <1>2, <1>3, SMT

ReadWalkSegment(count, kinds, reads, left, right, steps, heights, stacks, found) ==
    /\ steps \in Nat
    /\ heights \in [0..steps -> Nat]
    /\ found \in [0..steps -> SUBSET Keys]
    /\ \A index \in 0..steps : stacks[index] \in [1..heights[index] -> 1..count]
    /\ \A index \in 1..steps :
        /\ heights[index - 1] > 0
        /\ ReadWalkStep(kinds, reads, left, right,
            heights[index - 1], stacks[index - 1], found[index - 1],
            heights[index], stacks[index], found[index])

ReadWalkHistory(count, kinds, reads, left, right, steps, heights, stacks, found) ==
    /\ ReadWalkSegment(count, kinds, reads, left, right, steps, heights, stacks, found)
    /\ heights[0] = 1 /\ stacks[0][1] = count /\ found[0] = {}

ReadWalkCompletion(count, kinds, reads, left, right, height, stack, initialFound) ==
    \E steps, heights, stacks, found :
        /\ ReadWalkSegment(count, kinds, reads, left, right, steps, heights, stacks, found)
        /\ heights[0] = height /\ stacks[0] = stack /\ found[0] = initialFound
        /\ heights[steps] = 0

THEOREM EmptyPendingStackHasAReadWalkCompletion ==
    ASSUME NEW count \in Nat, NEW kinds, NEW reads, NEW left, NEW right,
           NEW stack \in [1..0 -> 1..count], NEW initialFound \in SUBSET Keys
    PROVE ReadWalkCompletion(count, kinds, reads, left, right, 0, stack, initialFound)
    PROOF
    <1>. DEFINE heights == [index \in 0..0 |-> 0]
                stacks == [index \in 0..0 |-> stack]
                found == [index \in 0..0 |-> initialFound]
    <1>1. ReadWalkSegment(count, kinds, reads, left, right, 0, heights, stacks, found)
        BY SMT DEF ReadWalkSegment, heights, stacks, found
    <1>. QED BY <1>1, SMT DEF ReadWalkCompletion, heights, stacks, found

THEOREM PrependingAReadWalkStepPreservesCompletion ==
    ASSUME NEW count \in Nat, NEW kinds, NEW reads, NEW left, NEW right,
           NEW height \in Nat \ {0}, NEW stack \in [1..height -> 1..count],
           NEW initialFound \in SUBSET Keys,
           NEW nextHeight, NEW nextStack, NEW nextFound,
           ReadWalkStep(kinds, reads, left, right, height, stack, initialFound,
               nextHeight, nextStack, nextFound),
           ReadWalkCompletion(count, kinds, reads, left, right, nextHeight, nextStack, nextFound)
    PROVE ReadWalkCompletion(count, kinds, reads, left, right, height, stack, initialFound)
    PROOF
    <1>1. PICK steps, heights, stacks, found :
        /\ ReadWalkSegment(count, kinds, reads, left, right, steps, heights, stacks, found)
        /\ heights[0] = nextHeight /\ stacks[0] = nextStack /\ found[0] = nextFound
        /\ heights[steps] = 0
        BY DEF ReadWalkCompletion
    <1>. DEFINE extendedHeights == [index \in 0..(steps + 1) |->
                    IF index = 0 THEN height ELSE heights[index - 1]]
                extendedStacks == [index \in 0..(steps + 1) |->
                    IF index = 0 THEN stack ELSE stacks[index - 1]]
                extendedFound == [index \in 0..(steps + 1) |->
                    IF index = 0 THEN initialFound ELSE found[index - 1]]
    <1>2. steps \in Nat /\ extendedHeights \in [0..(steps + 1) -> Nat]
          /\ extendedFound \in [0..(steps + 1) -> SUBSET Keys]
          /\ \A index \in 0..(steps + 1) :
              extendedStacks[index] \in [1..extendedHeights[index] -> 1..count]
        BY <1>1, SMT DEF ReadWalkSegment, extendedHeights, extendedStacks, extendedFound
    <1>3. \A index \in 1..(steps + 1) :
        /\ extendedHeights[index - 1] > 0
        /\ ReadWalkStep(kinds, reads, left, right,
            extendedHeights[index - 1], extendedStacks[index - 1], extendedFound[index - 1],
            extendedHeights[index], extendedStacks[index], extendedFound[index])
        <2>. SUFFICES ASSUME NEW index \in 1..(steps + 1)
                     PROVE /\ extendedHeights[index - 1] > 0
                           /\ ReadWalkStep(kinds, reads, left, right,
                               extendedHeights[index - 1], extendedStacks[index - 1], extendedFound[index - 1],
                               extendedHeights[index], extendedStacks[index], extendedFound[index])
            BY SMT
        <2>1. CASE index = 1
            BY <1>1, <1>2, <2>1, SMT DEF extendedHeights, extendedStacks, extendedFound
        <2>2. CASE index # 1
            BY <1>1, <1>2, <2>2, SMT DEF ReadWalkSegment,
                extendedHeights, extendedStacks, extendedFound
        <2>. QED BY <2>1, <2>2, SMT
    <1>4. ReadWalkSegment(count, kinds, reads, left, right,
        steps + 1, extendedHeights, extendedStacks, extendedFound)
        BY <1>2, <1>3, SMT DEF ReadWalkSegment
    <1>5. extendedHeights[0] = height /\ extendedStacks[0] = stack
          /\ extendedFound[0] = initialFound /\ extendedHeights[steps + 1] = 0
        BY <1>1, <1>2, SMT DEF extendedHeights, extendedStacks, extendedFound
    <1>. QED BY <1>4, <1>5, SMT DEF ReadWalkCompletion

THEOREM FinitePendingWorkConstructsAReadWalkCompletion ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, NEW weights,
           ExpressionPlan(count, kinds, literals, reads, left, right, state),
           ExpressionWorkHistory(count, kinds, left, right, weights),
           NEW height \in Nat, NEW stack \in [1..height -> 1..count],
           NEW initialFound \in SUBSET Keys, NEW sums,
           StackWorkHistory(height, stack, weights, sums)
    PROVE ReadWalkCompletion(count, kinds, reads, left, right, height, stack, initialFound)
    PROOF
    <1>. DEFINE P(fuel) ==
        \A h \in Nat : \A pending \in [1..h -> 1..count] : \A collected \in SUBSET Keys : \A work :
            (StackWorkHistory(h, pending, weights, work) /\ work[h] = fuel)
            => ReadWalkCompletion(count, kinds, reads, left, right, h, pending, collected)
    <1>0. count \in Nat /\ weights \in [1..count -> Nat \ {0}]
        BY SMT DEF ExpressionPlan, ExpressionWorkHistory
    <1>1. P(0)
        <2>. SUFFICES ASSUME NEW h \in Nat, NEW pending \in [1..h -> 1..count],
                             NEW collected \in SUBSET Keys, NEW work,
                             StackWorkHistory(h, pending, weights, work), work[h] = 0
                     PROVE ReadWalkCompletion(count, kinds, reads, left, right, h, pending, collected)
            BY SMT DEF P
        <2>1. h = 0 BY <1>0, PositiveNodeWorkBoundsStackHeight, SMT
        <2>. QED BY <1>0, <2>1, EmptyPendingStackHasAReadWalkCompletion, SMT
    <1>2. ASSUME NEW fuel \in Nat, P(fuel)
          PROVE P(fuel + 1)
        <2>. SUFFICES ASSUME NEW h \in Nat, NEW pending \in [1..h -> 1..count],
                             NEW collected \in SUBSET Keys, NEW work,
                             StackWorkHistory(h, pending, weights, work), work[h] = fuel + 1
                     PROVE ReadWalkCompletion(count, kinds, reads, left, right, h, pending, collected)
            BY SMT DEF P
        <2>1. CASE h = 0
            BY <1>0, <2>1, EmptyPendingStackHasAReadWalkCompletion, SMT
        <2>2. CASE h # 0
            <3>1. PICK nextHeight, nextStack, nextFound, nextSums :
                /\ nextHeight \in Nat /\ nextFound \in SUBSET Keys
                /\ nextStack \in [1..nextHeight -> 1..count]
                /\ StackWorkHistory(nextHeight, nextStack, weights, nextSums)
                /\ nextSums[nextHeight] = work[h] - 1
                /\ ReadWalkStep(kinds, reads, left, right, h, pending, collected,
                    nextHeight, nextStack, nextFound)
                BY <2>2, ReadWalkHasAOneLessWorkSuccessor, SMT
            <3>2. ReadWalkCompletion(count, kinds, reads, left, right, nextHeight, nextStack, nextFound)
                BY P(fuel), <3>1, SMT DEF P
            <3>. QED BY <1>0, <2>2, <3>1, <3>2, PrependingAReadWalkStepPreservesCompletion, SMT
        <2>. QED BY <2>1, <2>2, SMT
    <1>3. HIDE DEF P
    <1>4. \A fuel \in Nat : P(fuel) BY <1>1, <1>2, NatInduction
    <1>5. sums[height] \in Nat BY SMT DEF StackWorkHistory
    <1>. QED BY <1>4, <1>5, SMT DEF P

THEOREM EveryExpressionPlanHasACompletedReadWalk ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, ExpressionPlan(count, kinds, literals, reads, left, right, state)
    PROVE \E steps, heights, stacks, found :
        /\ ReadWalkHistory(count, kinds, reads, left, right, steps, heights, stacks, found)
        /\ heights[steps] = 0
    PROOF
    <1>1. PICK weights : ExpressionWorkHistory(count, kinds, left, right, weights)
        BY ExpressionWorkHistoryExists
    <1>. DEFINE stack == [index \in 1..1 |-> count]
                sums == [index \in 0..1 |-> IF index = 0 THEN 0 ELSE weights[count]]
    <1>2. count \in Nat /\ count \in 1..count /\ stack \in [1..1 -> 1..count]
          /\ StackWorkHistory(1, stack, weights, sums)
        BY <1>1, SMT DEF ExpressionPlan, ExpressionWorkHistory, StackWorkHistory, stack, sums
    <1>3. ReadWalkCompletion(count, kinds, reads, left, right, 1, stack, {})
        BY <1>1, <1>2, FinitePendingWorkConstructsAReadWalkCompletion, SMT
    <1>4. PICK steps, heights, stacks, found :
        /\ ReadWalkSegment(count, kinds, reads, left, right, steps, heights, stacks, found)
        /\ heights[0] = 1 /\ stacks[0] = stack /\ found[0] = {}
        /\ heights[steps] = 0
        BY <1>3 DEF ReadWalkCompletion
    <1>. QED BY <1>4, SMT DEF ReadWalkHistory, stack

THEOREM ReadWalkStepHasAUniqueSuccessor ==
    ASSUME NEW kinds, NEW reads, NEW left, NEW right, NEW height, NEW stack, NEW found,
           NEW nextHeight, NEW nextStack, NEW nextFound,
           NEW otherHeight, NEW otherStack, NEW otherFound,
           ReadWalkStep(kinds, reads, left, right, height, stack, found, nextHeight, nextStack, nextFound),
           ReadWalkStep(kinds, reads, left, right, height, stack, found, otherHeight, otherStack, otherFound)
    PROVE nextHeight = otherHeight /\ nextStack = otherStack /\ nextFound = otherFound
    BY SMT DEF ReadWalkStep

THEOREM ReadWalkSegmentsAgreeWhileBothExist ==
    ASSUME NEW count, NEW kinds, NEW reads, NEW left, NEW right,
           NEW steps, NEW heights, NEW stacks, NEW found,
           NEW otherSteps, NEW otherHeights, NEW otherStacks, NEW otherFound,
           ReadWalkSegment(count, kinds, reads, left, right, steps, heights, stacks, found),
           ReadWalkSegment(count, kinds, reads, left, right, otherSteps, otherHeights, otherStacks, otherFound),
           heights[0] = otherHeights[0], stacks[0] = otherStacks[0], found[0] = otherFound[0]
    PROVE \A index \in 0..steps : index <= otherSteps =>
        /\ heights[index] = otherHeights[index]
        /\ stacks[index] = otherStacks[index]
        /\ found[index] = otherFound[index]
    PROOF
    <1>. DEFINE P(index) == index <= otherSteps =>
        /\ heights[index] = otherHeights[index]
        /\ stacks[index] = otherStacks[index]
        /\ found[index] = otherFound[index]
    <1>1. P(0) BY SMT DEF P
    <1>2. steps \in Nat /\ otherSteps \in Nat BY SMT DEF ReadWalkSegment
    <1>3. \A index \in 1..steps :
        ((\A prior \in 0..(index - 1) : P(prior)) => P(index))
        <2>. SUFFICES ASSUME NEW index \in 1..steps,
                             \A prior \in 0..(index - 1) : P(prior), index <= otherSteps
                     PROVE /\ heights[index] = otherHeights[index]
                           /\ stacks[index] = otherStacks[index]
                           /\ found[index] = otherFound[index]
            BY SMT DEF P
        <2>1. heights[index - 1] = otherHeights[index - 1]
              /\ stacks[index - 1] = otherStacks[index - 1]
              /\ found[index - 1] = otherFound[index - 1]
            BY <1>2, SMT DEF P
        <2>2. ReadWalkStep(kinds, reads, left, right,
            heights[index - 1], stacks[index - 1], found[index - 1],
            heights[index], stacks[index], found[index])
            BY SMT DEF ReadWalkSegment
        <2>3. ReadWalkStep(kinds, reads, left, right,
            otherHeights[index - 1], otherStacks[index - 1], otherFound[index - 1],
            otherHeights[index], otherStacks[index], otherFound[index])
            BY <1>2, SMT DEF ReadWalkSegment
        <2>. QED BY <2>1, <2>2, <2>3, ReadWalkStepHasAUniqueSuccessor, SMT
    <1>4. HIDE DEF P
    <1>5. \A index \in 0..steps : P(index)
        BY <1>1, <1>2, <1>3, FiniteIndexedPrefixProperty
    <1>. QED BY <1>5 DEF P

THEOREM ACompletedReadWalkBoundsEveryOtherSegment ==
    ASSUME NEW count, NEW kinds, NEW reads, NEW left, NEW right,
           NEW steps, NEW heights, NEW stacks, NEW found,
           NEW otherSteps, NEW otherHeights, NEW otherStacks, NEW otherFound,
           ReadWalkSegment(count, kinds, reads, left, right, steps, heights, stacks, found),
           ReadWalkSegment(count, kinds, reads, left, right, otherSteps, otherHeights, otherStacks, otherFound),
           heights[0] = otherHeights[0], stacks[0] = otherStacks[0], found[0] = otherFound[0],
           heights[steps] = 0
    PROVE otherSteps <= steps
    PROOF
    <1>1. steps \in Nat /\ otherSteps \in Nat BY SMT DEF ReadWalkSegment
    <1>2. steps < otherSteps => otherHeights[steps] = 0
        BY <1>1, ReadWalkSegmentsAgreeWhileBothExist, SMT
    <1>3. ASSUME steps < otherSteps
          PROVE otherHeights[steps] > 0
        <2>1. steps + 1 \in 1..otherSteps BY <1>1, <1>3, SMT
        <2>2. otherHeights[(steps + 1) - 1] > 0
            BY <2>1, SMT DEF ReadWalkSegment
        <2>. QED BY <1>1, <2>2, SMT
    <1>. QED BY <1>1, <1>2, <1>3, SMT

THEOREM CompletedReadWalkReturnsExactlyTheConstructedPlanReads ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, NEW effects, NEW constructionHeights, NEW constructionStacks,
           NEW steps, NEW heights, NEW stacks, NEW found,
           ExpressionPlan(count, kinds, literals, reads, left, right, state),
           ExpressionReadHistory(count, kinds, reads, left, right, effects),
           ExpressionIndexStack(count, kinds, left, right, constructionHeights, constructionStacks),
           ReadWalkHistory(count, kinds, reads, left, right, steps, heights, stacks, found),
           heights[steps] = 0
    PROVE found[steps] = ExpressionReadKeys(count, kinds, reads)
    PROOF
    <1>. DEFINE P(index) == found[index] \cup StackReadKeys(stacks[index], heights[index], effects)
        = effects[count]
    <1>1. effects[count] \subseteq Keys
        BY SMT DEF ExpressionReadHistory, ExpressionPlan
    <1>2. P(0)
        BY <1>1, SMT DEF P, ReadWalkHistory, ReadWalkSegment, StackReadKeys
    <1>3. \A index \in 1..steps :
        ((\A prior \in 0..(index - 1) : P(prior)) => P(index))
        <2>. SUFFICES ASSUME NEW index \in 1..steps,
                             \A prior \in 0..(index - 1) : P(prior)
                     PROVE P(index)
            BY SMT
        <2>1. P(index - 1) BY SMT
        <2>2. found[index - 1] \cup StackReadKeys(stacks[index - 1], heights[index - 1], effects)
            = found[index] \cup StackReadKeys(stacks[index], heights[index], effects)
            BY ReadWalkStepPreservesReadEffects, SMT DEF ReadWalkHistory, ReadWalkSegment
        <2>. QED BY <2>1, <2>2, SMT DEF P
    <1>4. steps \in Nat BY SMT DEF ReadWalkHistory, ReadWalkSegment
    <1>5. \A index \in 0..steps : P(index)
        BY <1>2, <1>3, <1>4, FiniteIndexedPrefixProperty
    <1>6. P(steps) BY <1>4, <1>5, SMT
    <1>7. StackReadKeys(stacks[steps], heights[steps], effects) = {}
        BY SMT DEF StackReadKeys
    <1>8. found[steps] \subseteq Keys
        BY <1>4, SMT DEF ReadWalkHistory, ReadWalkSegment
    <1>9. found[steps] = effects[count]
        BY <1>6, <1>7, <1>8, SMT DEF P
    <1>. QED BY <1>9, ConstructedPlanPreservesAllReads, SMT

THEOREM EveryConstructedPlanHasAnExactCompletedReadWalk ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, NEW constructionHeights, NEW constructionStacks,
           ExpressionPlan(count, kinds, literals, reads, left, right, state),
           ExpressionIndexStack(count, kinds, left, right, constructionHeights, constructionStacks)
    PROVE \E steps, heights, stacks, found :
        /\ ReadWalkHistory(count, kinds, reads, left, right, steps, heights, stacks, found)
        /\ heights[steps] = 0
        /\ found[steps] = ExpressionReadKeys(count, kinds, reads)
    PROOF
    <1>1. PICK effects : ExpressionReadHistory(count, kinds, reads, left, right, effects)
        BY ExpressionReadHistoryExists
    <1>2. PICK steps, heights, stacks, found :
        /\ ReadWalkHistory(count, kinds, reads, left, right, steps, heights, stacks, found)
        /\ heights[steps] = 0
        BY EveryExpressionPlanHasACompletedReadWalk
    <1>3. found[steps] = ExpressionReadKeys(count, kinds, reads)
        BY <1>1, <1>2, CompletedReadWalkReturnsExactlyTheConstructedPlanReads, SMT
    <1>. QED BY <1>2, <1>3, SMT

CompletedReadKeys(count, kinds, reads, left, right, dependencies) ==
    \E steps, heights, stacks, found :
        /\ ReadWalkHistory(count, kinds, reads, left, right, steps, heights, stacks, found)
        /\ heights[steps] = 0 /\ dependencies = found[steps]
GeneratedReadDependencies(count, kinds, reads, left, right) ==
    CHOOSE dependencies \in SUBSET Keys : CompletedReadKeys(count, kinds, reads, left, right, dependencies)

THEOREM ConstructedPlanReadDependenciesAreTotalAndExact ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW state, NEW constructionHeights, NEW constructionStacks,
           ExpressionPlan(count, kinds, literals, reads, left, right, state),
           ExpressionIndexStack(count, kinds, left, right, constructionHeights, constructionStacks)
    PROVE /\ CompletedReadKeys(count, kinds, reads, left, right,
               GeneratedReadDependencies(count, kinds, reads, left, right))
          /\ GeneratedReadDependencies(count, kinds, reads, left, right)
               = ExpressionReadKeys(count, kinds, reads)
    PROOF
    <1>1. \E steps, heights, stacks, found :
        /\ ReadWalkHistory(count, kinds, reads, left, right, steps, heights, stacks, found)
        /\ heights[steps] = 0 /\ found[steps] = ExpressionReadKeys(count, kinds, reads)
        BY EveryConstructedPlanHasAnExactCompletedReadWalk
    <1>2. ExpressionReadKeys(count, kinds, reads) \in SUBSET Keys
        BY SMT DEF ExpressionReadKeys, ExpressionPlan
    <1>3. CompletedReadKeys(count, kinds, reads, left, right, ExpressionReadKeys(count, kinds, reads))
        BY <1>1, SMT DEF CompletedReadKeys
    <1>. DEFINE computed == GeneratedReadDependencies(count, kinds, reads, left, right)
    <1>4. computed \in SUBSET Keys /\ CompletedReadKeys(count, kinds, reads, left, right, computed)
        BY <1>2, <1>3, SMT DEF computed, GeneratedReadDependencies
    <1>5. PICK effects : ExpressionReadHistory(count, kinds, reads, left, right, effects)
        BY ExpressionReadHistoryExists
    <1>6. computed = ExpressionReadKeys(count, kinds, reads)
        BY <1>4, <1>5, CompletedReadWalkReturnsExactlyTheConstructedPlanReads, SMT DEF CompletedReadKeys
    <1>. QED BY <1>4, <1>6 DEF computed

THEOREM ExpressionNodeUsesOnlyItsReadKeys ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW first, NEW second, NEW history, NEW generated \in BOOLEAN,
           ExpressionPlan(count, kinds, literals, reads, left, right, first),
           NEW index \in 1..count,
           \A key \in ExpressionReadKeys(count, kinds, reads) : first[key] = second[key]
    PROVE ExpressionNode(generated, index, kinds, literals, reads, left, right, first, history)
        = ExpressionNode(generated, index, kinds, literals, reads, left, right, second, history)
    PROOF
    <1>1. kinds[index] = "read" => reads[index] \in ExpressionReadKeys(count, kinds, reads)
        BY SMT DEF ExpressionReadKeys
    <1>. QED BY <1>1, SMT DEF ExpressionNode, SourceNode, GeneratedNode

THEOREM ExpressionPrefixTransfersAcrossReadAgreement ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW first, NEW second, NEW history, NEW generated \in BOOLEAN,
           ExpressionPlan(count, kinds, literals, reads, left, right, first),
           \A key \in ExpressionReadKeys(count, kinds, reads) : first[key] = second[key],
           ExpressionPrefix(generated, count, kinds, literals, reads, left, right, first, history)
    PROVE ExpressionPrefix(generated, count, kinds, literals, reads, left, right, second, history)
    PROOF
    <1>1. \A index \in 1..count :
              ExpressionNode(generated, index, kinds, literals, reads, left, right, first, history)
                = ExpressionNode(generated, index, kinds, literals, reads, left, right, second, history)
        BY ExpressionNodeUsesOnlyItsReadKeys, SMT
    <1>. QED BY <1>1, SMT DEF ExpressionPrefix

THEOREM ExpressionHistoriesRespectReadAgreement ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW first, NEW second, NEW before, NEW after, NEW generated \in BOOLEAN,
           ExpressionPlan(count, kinds, literals, reads, left, right, first),
           \A key \in ExpressionReadKeys(count, kinds, reads) : first[key] = second[key],
           ExpressionPrefix(generated, count, kinds, literals, reads, left, right, first, before),
           ExpressionPrefix(generated, count, kinds, literals, reads, left, right, second, after)
    PROVE \A index \in 0..count : before[index] = after[index]
    PROOF
    <1>. DEFINE P(index) == before[index] = after[index]
    <1>1. P(0)
        BY SMT DEF P, ExpressionPrefix
    <1>2. \A index \in 1..count :
              ((\A child \in 0..(index - 1) : P(child)) => P(index))
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A child \in 0..(index - 1) : P(child)
                     PROVE P(index)
            BY SMT
        <2>1. ExpressionNode(generated, index, kinds, literals, reads, left, right, first, before)
                = ExpressionNode(generated, index, kinds, literals, reads, left, right, first, after)
            BY ExpressionNodeUsesOnlyEarlierResults, SMT DEF P
        <2>2. ExpressionNode(generated, index, kinds, literals, reads, left, right, first, after)
                = ExpressionNode(generated, index, kinds, literals, reads, left, right, second, after)
            BY ExpressionNodeUsesOnlyItsReadKeys
        <2>. QED BY <2>1, <2>2, SMT DEF P, ExpressionPrefix
    <1>3. count \in Nat
        BY SMT DEF ExpressionPlan
    <1>4. \A index \in 0..count : P(index)
        BY <1>1, <1>2, <1>3, FiniteIndexedPrefixProperty
    <1>. QED BY <1>4 DEF P

CompleteIntBindings(bound, bindings) ==
    [key \in Keys |-> IF key \in bound THEN bindings[key] ELSE 0]

PartialExpressionPlan(count, kinds, literals, reads, left, right, bound, bindings) ==
    /\ bound \in SUBSET Keys
    /\ bindings \in [bound -> SwiftIntMin..SwiftIntMax]
    /\ ExpressionReadKeys(count, kinds, reads) \subseteq bound
    /\ ExpressionPlan(count, kinds, literals, reads, left, right,
           CompleteIntBindings(bound, bindings))

THEOREM CompletingPartialBindingsRetainsEveryBoundValue ==
    ASSUME NEW bound \in SUBSET Keys,
           NEW bindings \in [bound -> SwiftIntMin..SwiftIntMax]
    PROVE /\ CompleteIntBindings(bound, bindings) \in [Keys -> SwiftIntMin..SwiftIntMax]
          /\ \A key \in bound : CompleteIntBindings(bound, bindings)[key] = bindings[key]
    BY IntegerDomain, SMT DEF CompleteIntBindings, IntegerDomain

THEOREM PartialOrderedIntExpressionsPreserveValueAndFailure ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW bound, NEW bindings,
           PartialExpressionPlan(count, kinds, literals, reads, left, right, bound, bindings)
    PROVE \E source, generated :
              /\ SourceExpressionHistory(count, kinds, literals, reads, left, right, bindings, source)
              /\ GeneratedExpressionHistory(count, kinds, literals, reads, left, right, bindings, generated)
              /\ \A index \in 0..count :
                     /\ OutcomeAgrees(source, generated, index)
                     /\ source[index] \in ExpressionOutcomes
                     /\ generated[index] \in ExpressionOutcomes
    PROOF
    <1>. DEFINE completed == CompleteIntBindings(bound, bindings)
    <1>1. PICK source, generated :
              /\ SourceExpressionHistory(count, kinds, literals, reads, left, right, completed, source)
              /\ GeneratedExpressionHistory(count, kinds, literals, reads, left, right, completed, generated)
              /\ \A index \in 0..count : OutcomeAgrees(source, generated, index)
        BY EveryOrderedIntExpressionPreservesOutcome DEF PartialExpressionPlan, completed
    <1>2. \A index \in 0..count :
              source[index] \in ExpressionOutcomes /\ generated[index] \in ExpressionOutcomes
        BY <1>1, ExpressionHistoriesHaveTypedOutcomes DEF PartialExpressionPlan, completed
    <1>3. \A key \in ExpressionReadKeys(count, kinds, reads) : completed[key] = bindings[key]
        BY CompletingPartialBindingsRetainsEveryBoundValue, SMT DEF PartialExpressionPlan, completed
    <1>4. ExpressionPrefix(FALSE, count, kinds, literals, reads, left, right, completed, source)
          /\ ExpressionPrefix(TRUE, count, kinds, literals, reads, left, right, completed, generated)
        BY <1>1, SMT DEF ExpressionPrefix, ExpressionNode,
            SourceExpressionHistory, GeneratedExpressionHistory
    <1>5. ExpressionPrefix(FALSE, count, kinds, literals, reads, left, right, bindings, source)
          /\ ExpressionPrefix(TRUE, count, kinds, literals, reads, left, right, bindings, generated)
        BY <1>3, <1>4, ExpressionPrefixTransfersAcrossReadAgreement, SMT
            DEF PartialExpressionPlan, completed
    <1>. QED BY <1>1, <1>2, <1>5, SMT DEF ExpressionPrefix, ExpressionNode,
        SourceExpressionHistory, GeneratedExpressionHistory

THEOREM PartialExpressionOutcomesDoNotDependOnCompletion ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW bound, NEW bindings, NEW completed \in [Keys -> SwiftIntMin..SwiftIntMax],
           NEW partialHistory, NEW completeHistory, NEW generated \in BOOLEAN,
           PartialExpressionPlan(count, kinds, literals, reads, left, right, bound, bindings),
           \A key \in bound : completed[key] = bindings[key],
           ExpressionPrefix(generated, count, kinds, literals, reads, left, right, bindings, partialHistory),
           ExpressionPrefix(generated, count, kinds, literals, reads, left, right, completed, completeHistory)
    PROVE \A index \in 0..count : partialHistory[index] = completeHistory[index]
    PROOF
    <1>1. ExpressionPlan(count, kinds, literals, reads, left, right, completed)
        BY SMT DEF PartialExpressionPlan, ExpressionPlan
    <1>2. \A key \in ExpressionReadKeys(count, kinds, reads) : completed[key] = bindings[key]
        BY SMT DEF PartialExpressionPlan
    <1>. QED BY <1>1, <1>2, ExpressionHistoriesRespectReadAgreement, SMT

THEOREM ChangingAReadValueChangesItsOutcome ==
    ASSUME NEW index, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW first, NEW second, NEW history,
           kinds[index] = "read", first[reads[index]] # second[reads[index]]
    PROVE SourceNode(index, kinds, literals, reads, left, right, first, history)
        # SourceNode(index, kinds, literals, reads, left, right, second, history)
    BY SMT DEF SourceNode, Success

THEOREM AnyPartialOrderedIntHistoriesPreserveValueAndFailure ==
    ASSUME NEW count, NEW kinds, NEW literals, NEW reads, NEW left, NEW right,
           NEW bound, NEW bindings, NEW partialSource, NEW partialGenerated,
           PartialExpressionPlan(count, kinds, literals, reads, left, right, bound, bindings),
           SourceExpressionHistory(count, kinds, literals, reads, left, right, bindings, partialSource),
           GeneratedExpressionHistory(count, kinds, literals, reads, left, right, bindings, partialGenerated)
    PROVE \A index \in 0..count :
              /\ OutcomeAgrees(partialSource, partialGenerated, index)
              /\ partialSource[index] \in ExpressionOutcomes
              /\ partialGenerated[index] \in ExpressionOutcomes
    PROOF
    <1>. DEFINE completed == CompleteIntBindings(bound, bindings)
    <1>1. PICK source, generated :
              /\ SourceExpressionHistory(count, kinds, literals, reads, left, right, completed, source)
              /\ GeneratedExpressionHistory(count, kinds, literals, reads, left, right, completed, generated)
              /\ \A index \in 0..count : OutcomeAgrees(source, generated, index)
        BY EveryOrderedIntExpressionPreservesOutcome DEF PartialExpressionPlan, completed
    <1>2. \A index \in 0..count :
              source[index] \in ExpressionOutcomes /\ generated[index] \in ExpressionOutcomes
        BY <1>1, ExpressionHistoriesHaveTypedOutcomes DEF PartialExpressionPlan, completed
    <1>3. completed \in [Keys -> SwiftIntMin..SwiftIntMax]
          /\ \A key \in bound : completed[key] = bindings[key]
        BY CompletingPartialBindingsRetainsEveryBoundValue DEF PartialExpressionPlan, completed
    <1>4. ExpressionPrefix(FALSE, count, kinds, literals, reads, left, right, bindings, partialSource)
          /\ ExpressionPrefix(TRUE, count, kinds, literals, reads, left, right, bindings, partialGenerated)
          /\ ExpressionPrefix(FALSE, count, kinds, literals, reads, left, right, completed, source)
          /\ ExpressionPrefix(TRUE, count, kinds, literals, reads, left, right, completed, generated)
        BY <1>1, SMT DEF ExpressionPrefix, ExpressionNode,
            SourceExpressionHistory, GeneratedExpressionHistory
    <1>5. \A index \in 0..count : partialSource[index] = source[index]
        BY <1>3, <1>4, PartialExpressionOutcomesDoNotDependOnCompletion
    <1>6. \A index \in 0..count : partialGenerated[index] = generated[index]
        BY <1>3, <1>4, PartialExpressionOutcomesDoNotDependOnCompletion
    <1>. QED BY <1>1, <1>2, <1>5, <1>6, SMT DEF OutcomeAgrees

\* Meaning of a reached let or guarded arithmetic site, using only stored scalar operands.
CheckedPostorderOperation(plan, state, values, index) ==
    IF plan.kinds[index] = "literal" THEN Success(plan.literals[index])
    ELSE IF plan.kinds[index] = "read" THEN Success(state[plan.reads[index]])
    ELSE GeneratedAdd(values[plan.left[index]], values[plan.right[index]])

ReachedCheckedPostorderExecution(plan, state, execution) ==
    /\ execution.completed \in 0..plan.count
    /\ execution.values \in [1..execution.completed -> SwiftIntMin..SwiftIntMax]
    /\ \A index \in 1..execution.completed :
        CheckedPostorderOperation(plan, state, execution.values, index) = Success(execution.values[index])
    /\ IF execution.completed = plan.count
       THEN execution.outcome = Success(execution.values[plan.count])
       ELSE /\ execution.outcome = CheckedPostorderOperation(plan, state,
                   execution.values, execution.completed + 1)
            /\ ~execution.outcome.ok

THEOREM ReachedCheckedOperationsRetainEverySuccessfulSourcePrefix ==
    ASSUME NEW plan, NEW bound, NEW state, NEW source, NEW execution,
           PartialExpressionPlan(plan.count, plan.kinds, plan.literals, plan.reads,
               plan.left, plan.right, bound, state),
           SourceExpressionHistory(plan.count, plan.kinds, plan.literals, plan.reads,
               plan.left, plan.right, state, source),
           ReachedCheckedPostorderExecution(plan, state, execution)
    PROVE /\ \A index \in 1..execution.completed : source[index] = Success(execution.values[index])
          /\ (execution.completed = plan.count => execution.outcome = source[plan.count])
          /\ (execution.completed < plan.count =>
                  /\ source[execution.completed + 1] = execution.outcome
                  /\ ~source[execution.completed + 1].ok)
    PROOF
    <1>. DEFINE agrees(index) == index > 0 => source[index] = Success(execution.values[index])
    <1>0. /\ plan.count \in Nat /\ plan.count >= 1
          /\ execution.completed \in Nat /\ execution.completed <= plan.count
        BY SMT DEF PartialExpressionPlan, ExpressionPlan, ReachedCheckedPostorderExecution
    <1>. USE <1>0
    <1>1. \A index \in 1..plan.count :
        /\ plan.kinds[index] \in {"literal", "read", "add"}
        /\ (plan.kinds[index] = "add" =>
                /\ plan.left[index] \in 1..(index - 1)
                /\ plan.right[index] \in 1..(index - 1))
        BY SMT DEF PartialExpressionPlan, ExpressionPlan
    <1>2. \A index \in 1..(execution.completed + 1) : index <= plan.count =>
        ((\A earlier \in 1..(index - 1) : source[earlier] = Success(execution.values[earlier]))
         => source[index] = CheckedPostorderOperation(plan, state, execution.values, index))
        <2>. SUFFICES ASSUME NEW index \in 1..(execution.completed + 1), index <= plan.count,
                             \A earlier \in 1..(index - 1) :
                                 source[earlier] = Success(execution.values[earlier])
                     PROVE source[index] = CheckedPostorderOperation(plan, state, execution.values, index)
            BY SMT
        <2>0. /\ index \in 1..plan.count
              /\ \A earlier \in 1..(index - 1) : earlier \in 1..execution.completed
            BY <1>0, SMT
        <2>1. CASE plan.kinds[index] = "add"
            <3>1. /\ source[plan.left[index]] = Success(execution.values[plan.left[index]])
                  /\ source[plan.right[index]] = Success(execution.values[plan.right[index]])
                  /\ InRange(execution.values[plan.left[index]])
                  /\ InRange(execution.values[plan.right[index]])
                BY <1>1, <2>0, <2>1, SMT DEF ReachedCheckedPostorderExecution, InRange
            <3>2. SourceAdd(execution.values[plan.left[index]], execution.values[plan.right[index]])
                    = GeneratedAdd(execution.values[plan.left[index]], execution.values[plan.right[index]])
                BY <3>1, CheckedAdditionRule, SMT DEF InRange
            <3>. QED BY <2>0, <2>1, <3>1, <3>2, SMT
                DEF SourceExpressionHistory, SourceNode, SourceCombine, Success, CheckedPostorderOperation
        <2>2. CASE plan.kinds[index] # "add"
            BY <1>1, <2>0, <2>2, SMT DEF SourceExpressionHistory, SourceNode, CheckedPostorderOperation
        <2>. QED BY <2>1, <2>2, SMT
    <1>3. agrees(0) BY SMT DEF agrees
    <1>4. \A index \in 1..execution.completed :
        ((\A earlier \in 0..(index - 1) : agrees(earlier)) => agrees(index))
        <2>. SUFFICES ASSUME NEW index \in 1..execution.completed,
                             \A earlier \in 0..(index - 1) : agrees(earlier)
                     PROVE agrees(index)
            BY SMT
        <2>1. /\ index \in 1..(execution.completed + 1) /\ index <= plan.count
              /\ \A earlier \in 1..(index - 1) :
                     source[earlier] = Success(execution.values[earlier])
            BY <1>0, SMT DEF agrees
        <2>2. source[index] = CheckedPostorderOperation(plan, state, execution.values, index)
            BY <1>2, <2>1, SMT
        <2>. QED BY <2>2, SMT DEF agrees, ReachedCheckedPostorderExecution
    <1>5. \A index \in 0..execution.completed : agrees(index)
        <2>. DEFINE P(length) ==
            \A index \in 0..execution.completed : index <= length => agrees(index)
        <2>1. P(0) BY <1>3, SMT DEF P
        <2>2. ASSUME NEW length \in Nat, P(length)
              PROVE P(length + 1)
            <3>. SUFFICES ASSUME length + 1 \in 1..execution.completed
                         PROVE agrees(length + 1)
                BY P(length), SMT DEF P
            <3>1. \A earlier \in 0..length : agrees(earlier)
                BY P(length), SMT DEF P
            <3>. QED BY <1>4, <3>1, SMT
        <2>3. \A length \in Nat : P(length)
            BY <2>1, <2>2, NatInduction
        <2>. QED BY <1>0, <2>3, SMT DEF P
    <1>6. \A index \in 1..execution.completed : source[index] = Success(execution.values[index])
        BY <1>0, <1>5, SMT DEF agrees
    <1>7. execution.completed = plan.count => execution.outcome = source[plan.count]
        BY <1>0, <1>6, SMT DEF ReachedCheckedPostorderExecution
    <1>8. execution.completed < plan.count =>
        /\ source[execution.completed + 1] = execution.outcome
        /\ ~source[execution.completed + 1].ok
        <2>. SUFFICES ASSUME execution.completed < plan.count
                     PROVE /\ source[execution.completed + 1] = execution.outcome
                           /\ ~source[execution.completed + 1].ok
            BY SMT
        <2>1. /\ execution.completed + 1 \in 1..(execution.completed + 1)
              /\ execution.completed + 1 <= plan.count
              /\ \A earlier \in 1..((execution.completed + 1) - 1) :
                     source[earlier] = Success(execution.values[earlier])
            BY <1>0, <1>6, SMT
        <2>2. source[execution.completed + 1]
                = CheckedPostorderOperation(plan, state, execution.values, execution.completed + 1)
            BY <1>2, <2>1, SMT
        <2>. QED BY <2>2, SMT DEF ReachedCheckedPostorderExecution
    <1>. QED BY <1>6, <1>7, <1>8

THEOREM CompletedSyntaxVisitRetainsTheReachedCheckedOutcome ==
    ASSUME NEW steps, NEW root, NEW view, NEW heights, NEW pendings, NEW currents, NEW emissions,
           NEW bound \in SUBSET Keys, NEW state \in [bound -> SwiftIntMin..SwiftIntMax],
           NEW meaning, NEW execution, NEW fallbackRead \in Keys,
           SynchronizedNodeHistory(steps, root, view, heights, pendings, currents, emissions),
           heights[steps] = 0, SourceSyntaxHistory(view, state, meaning),
           \A step \in 1..steps : pendings[step - 1][heights[step - 1]].node \in DOMAIN view.kinds,
           TypedVisitedSourceInputs(view, emissions[steps]),
           {emissions[steps].origins[index] : index \in 1..emissions[steps].count} \subseteq DOMAIN view.kinds,
           LET plan == ExtractedNodePlan(emissions[steps], fallbackRead)
           IN /\ ExpressionReadKeys(plan.count, plan.kinds, plan.reads) \subseteq bound
              /\ ReachedCheckedPostorderExecution(plan, state, execution)
    PROVE meaning[root] = execution.outcome
    PROOF
    <1>. DEFINE emitted == emissions[steps]
                plan == ExtractedNodePlan(emitted, fallbackRead)
                source == EmittedSourceSyntaxHistory(emitted, meaning)
    <1>0. steps \in Nat /\ steps \in 0..steps
        BY SMT DEF SynchronizedNodeHistory, PendingVisitHistory
    <1>0a. \A step \in 0..steps :
        /\ NodeEmissionArrays(emissions[step])
        /\ AllNodePayloadsMatchSource(view, emissions[step])
        BY SynchronizedNodeHistoryPreservesEverySourcePayload, SMT
    <1>1. /\ NodeEmissionArrays(emitted) /\ emitted.count \in Nat \ {0}
          /\ AllNodePayloadsMatchSource(view, emitted)
          /\ emitted.origins[emitted.count] = root
        BY <1>0, <1>0a,
            SuccessfulSynchronizedVisitIdentifiesTheEmittedSourceRoot, SMT
            DEF emitted
    <1>1a. /\ plan.count = emitted.count /\ plan.count \in Nat /\ plan.count >= 1
           /\ source[plan.count] = meaning[root]
        BY <1>1, SMT DEF plan, source, ExtractedNodePlan, EmittedSourceSyntaxHistory
    <1>2. PartialExpressionPlan(plan.count, plan.kinds, plan.literals, plan.reads,
        plan.left, plan.right, bound, state)
        BY <1>1, SourceMatchedNodesSupplyTheTypedExpressionPlan,
            CompletingPartialBindingsRetainsEveryBoundValue, SMT
            DEF PartialExpressionPlan, plan, emitted
    <1>3. SourceExpressionHistory(plan.count, plan.kinds, plan.literals, plan.reads,
        plan.left, plan.right, state, source)
        BY <1>1, MatchedPostorderNodesRetainIndependentSourceSyntaxMeaning
            DEF source, plan, emitted
    <1>4. /\ \A index \in 1..execution.completed : source[index] = Success(execution.values[index])
          /\ (execution.completed = plan.count => execution.outcome = source[plan.count])
          /\ (execution.completed < plan.count =>
                  /\ source[execution.completed + 1] = execution.outcome
                  /\ ~source[execution.completed + 1].ok)
        BY <1>2, <1>3, ReachedCheckedOperationsRetainEverySuccessfulSourcePrefix
            DEF plan, emitted
    <1>5. CASE execution.completed = plan.count
        BY <1>1a, <1>4, <1>5, SMT
    <1>6. CASE execution.completed < plan.count
        <2>0. /\ execution.completed \in Nat
              /\ execution.completed + 1 \in 1..emitted.count
              /\ meaning[emitted.origins[execution.completed + 1]] = execution.outcome
              /\ ~execution.outcome.ok
              /\ \A earlier \in 1..execution.completed : meaning[emitted.origins[earlier]].ok
            BY <1>1a, <1>4, <1>6, SMT DEF source, plan,
                EmittedSourceSyntaxHistory, ExtractedNodePlan, Success, ReachedCheckedPostorderExecution
        <2>1. FirstRootFailureIs(emitted.count, emitted.origins, meaning, execution.outcome)
            BY <2>0, SMT DEF FirstRootFailureIs
        <2>. QED BY <2>1, CompletedSyntaxVisitIdentifiesTheFirstReachedFailure, SMT DEF emitted
    <1>. QED BY <1>1a, <1>5, <1>6, SMT DEF ReachedCheckedPostorderExecution

\* Enumeration width is a capability; it does not restrict logical members.
SourceIntRangeMembers(lower, upper) ==
    {member \in Int : lower <= member /\ member <= upper}
SourceRangeWidthFits(lower, upper) ==
    lower > upper \/ upper - lower + 1 <= SwiftIntMax
GeneratedRangeBoundsGuard(lower, upper) ==
    IF lower > upper THEN TRUE
    ELSE InRange(upper - lower) /\ InRange(upper - lower + 1)

THEOREM RangeBoundsGuardMatchesIndependentWidthBudget ==
    ASSUME NEW lower \in SwiftIntMin..SwiftIntMax,
           NEW upper \in SwiftIntMin..SwiftIntMax
    PROVE GeneratedRangeBoundsGuard(lower, upper)
        <=> SourceRangeWidthFits(lower, upper)
    BY IntegerDomain, SMT DEF IntegerDomain, InRange,
        GeneratedRangeBoundsGuard, SourceRangeWidthFits

THEOREM ReversedRangeHasNoLogicalMembersButFitsEnumeration ==
    ASSUME NEW lower \in SwiftIntMin..SwiftIntMax,
           NEW upper \in SwiftIntMin..SwiftIntMax, lower > upper
    PROVE /\ SourceIntRangeMembers(lower, upper) = {}
          /\ GeneratedRangeBoundsGuard(lower, upper)
    BY SMT DEF SourceIntRangeMembers, GeneratedRangeBoundsGuard

THEOREM SelectedRangeMembershipIsTheBoundsPredicate ==
    ASSUME NEW lower \in Int, NEW upper \in Int, NEW member \in Int
    PROVE member \in SourceIntRangeMembers(lower, upper)
        <=> (lower <= member /\ member <= upper)
    BY SMT DEF SourceIntRangeMembers

THEOREM EnumerationGuardCanExcludeALogicalSelectedRangeValue ==
    /\ 0 \in SourceIntRangeMembers(SwiftIntMin, SwiftIntMax)
    /\ ~GeneratedRangeBoundsGuard(SwiftIntMin, SwiftIntMax)
    PROOF
    <1>1. /\ 0 \in SourceIntRangeMembers(SwiftIntMin, SwiftIntMax)
          /\ SwiftIntMin \in SwiftIntMin..SwiftIntMax
          /\ SwiftIntMax \in SwiftIntMin..SwiftIntMax
        BY IntegerDomain, SMT DEF IntegerDomain, SourceIntRangeMembers
    <1>2. ~SourceRangeWidthFits(SwiftIntMin, SwiftIntMax)
        BY IntegerDomain, SMT DEF IntegerDomain, SourceRangeWidthFits
    <1>3. GeneratedRangeBoundsGuard(SwiftIntMin, SwiftIntMax)
            <=> SourceRangeWidthFits(SwiftIntMin, SwiftIntMax)
        BY <1>1, RangeBoundsGuardMatchesIndependentWidthBudget
    <1>. QED BY <1>1, <1>2, <1>3, SMT


\* Structural certificate data only: no evaluator or preservation premise.
LiteralReadAddCertificate(view, emitted, inverse, fallback, bound) ==
    /\ bound \subseteq Keys /\ fallback \in Keys
    /\ NodeEmissionArrays(emitted) /\ emitted.count > 0
    /\ AllNodePayloadsMatchSource(view, emitted)
    /\ TypedVisitedSourceInputs(view, emitted)
    /\ inverse \in [DOMAIN view.kinds -> 1..emitted.count]
    /\ emitted.origins \in [1..emitted.count -> DOMAIN view.kinds]
    /\ \A index \in 1..emitted.count : inverse[emitted.origins[index]] = index
    /\ \A node \in DOMAIN view.kinds : emitted.origins[inverse[node]] = node
    /\ emitted.origins[emitted.count] = view.root
    /\ \A index \in 1..emitted.count : emitted.nodes[index].kind = "read"
           => emitted.nodes[index].payload \in bound

THEOREM CertifiedPlanHistoriesSupplySourceSyntaxHistories ==
    ASSUME NEW view, NEW emitted, NEW inverse, NEW fallback, NEW bound,
           LiteralReadAddCertificate(view, emitted, inverse, fallback, bound),
           NEW state, NEW history,
           LET plan == ExtractedNodePlan(emitted, fallback)
           IN SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
                  plan.reads, plan.left, plan.right, state, history)
    PROVE SourceSyntaxHistory(view, state,
              [node \in DOMAIN view.kinds |-> history[inverse[node]]])
    PROOF
    <1>. DEFINE plan == ExtractedNodePlan(emitted, fallback)
                meaning == [node \in DOMAIN view.kinds |-> history[inverse[node]]]
    <1>1. \A node \in DOMAIN view.kinds : meaning[node] =
        IF view.kinds[node] = "literal" THEN Success(view.literals[node])
        ELSE IF view.kinds[node] = "read" THEN Success(state[view.reads[node]])
        ELSE SourceCombine(meaning[view.left[node]], meaning[view.right[node]])
        PROOF
        <2>. SUFFICES ASSUME NEW node \in DOMAIN view.kinds
                     PROVE meaning[node] =
                       IF view.kinds[node] = "literal" THEN Success(view.literals[node])
                       ELSE IF view.kinds[node] = "read" THEN Success(state[view.reads[node]])
                       ELSE SourceCombine(meaning[view.left[node]], meaning[view.right[node]])
            BY SMT
        <2>. DEFINE index == inverse[node]
        <2>1. /\ index \in 1..emitted.count /\ emitted.origins[index] = node
              /\ NodePayloadMatchesSource(view, emitted, index)
            BY SMT DEF index, LiteralReadAddCertificate, AllNodePayloadsMatchSource
        <2>2. history[index] = SourceNode(index, plan.kinds, plan.literals,
                          plan.reads, plan.left, plan.right, state, history)
            BY <2>1, SMT DEF plan, ExtractedNodePlan, SourceExpressionHistory
        <2>3. view.kinds[node] \in {"literal", "read", "add"}
            BY <2>1 DEF NodePayloadMatchesSource
        <2>4. CASE view.kinds[node] = "literal"
            BY <2>1, <2>2, <2>4, SMT
                DEF meaning, index, plan, ExtractedNodePlan, NodePayloadMatchesSource, SourceNode
        <2>5. CASE view.kinds[node] = "read"
            BY <2>1, <2>2, <2>5, SMT
                DEF meaning, index, plan, ExtractedNodePlan, NodePayloadMatchesSource, SourceNode
        <2>6. CASE view.kinds[node] = "add"
            PROOF
            <3>1. /\ emitted.nodes[index].left \in 1..emitted.count
                  /\ emitted.nodes[index].right \in 1..emitted.count
                  /\ emitted.origins[emitted.nodes[index].left] = view.left[node]
                  /\ emitted.origins[emitted.nodes[index].right] = view.right[node]
                PROOF
                <4>1. /\ emitted.nodes[index].kind = "add"
                      /\ emitted.origins[index] = node
                      /\ index \in 1..emitted.count
                    BY ONLY <2>1, <2>6, SMT DEF NodePayloadMatchesSource
                <4>2. /\ emitted.nodes[index].left \in 1..(index - 1)
                      /\ emitted.nodes[index].right \in 1..(index - 1)
                      /\ emitted.origins[emitted.nodes[index].left] = view.left[node]
                      /\ emitted.origins[emitted.nodes[index].right] = view.right[node]
                    BY ONLY <2>1, <4>1, SMT DEF NodePayloadMatchesSource
                <4>3. emitted.count \in Nat
                    BY SMT DEF LiteralReadAddCertificate, NodeEmissionArrays
                <4>. QED BY ONLY <4>1, <4>2, <4>3, SMT
            <3>2. /\ view.left[node] \in DOMAIN view.kinds
                  /\ view.right[node] \in DOMAIN view.kinds
                  /\ inverse[view.left[node]] = emitted.nodes[index].left
                  /\ inverse[view.right[node]] = emitted.nodes[index].right
                BY <3>1, SMT DEF LiteralReadAddCertificate
            <3>. QED BY <2>1, <2>2, <2>6, <3>2, SMT
                DEF meaning, index, plan, ExtractedNodePlan, NodePayloadMatchesSource, SourceNode
        <2>. QED BY <2>3, <2>4, <2>5, <2>6, SMT
    <1>. QED BY <1>1, SMT DEF meaning, SourceSyntaxHistory

THEOREM LiteralReadAddCertificateSuppliesExpressionParent ==
    ASSUME NEW view, NEW emitted, NEW inverse, NEW fallback, NEW bound,
           LiteralReadAddCertificate(view, emitted, inverse, fallback, bound),
           NEW state \in [bound -> SwiftIntMin..SwiftIntMax]
    PROVE LET plan == ExtractedNodePlan(emitted, fallback)
          IN /\ PartialExpressionPlan(plan.count, plan.kinds, plan.literals,
                    plan.reads, plan.left, plan.right, bound, state)
             /\ \A history : SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
                    plan.reads, plan.left, plan.right, state, history) =>
                   /\ \E meaning : SourceSyntaxHistory(view, state, meaning)
                   /\ \A meaning : SourceSyntaxHistory(view, state, meaning)
                          => history[plan.count] = meaning[view.root]
             /\ \E source, generated :
                   /\ SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
                          plan.reads, plan.left, plan.right, state, source)
                   /\ GeneratedExpressionHistory(plan.count, plan.kinds, plan.literals,
                          plan.reads, plan.left, plan.right, state, generated)
                   /\ \A index \in 0..plan.count :
                          /\ OutcomeAgrees(source, generated, index)
                          /\ source[index] \in ExpressionOutcomes
                          /\ generated[index] \in ExpressionOutcomes
    PROOF
    <1>. DEFINE plan == ExtractedNodePlan(emitted, fallback)
                completed == CompleteIntBindings(bound, state)
    <1>1. completed \in [Keys -> SwiftIntMin..SwiftIntMax]
        BY CompletingPartialBindingsRetainsEveryBoundValue, SMT
            DEF completed, LiteralReadAddCertificate
    <1>2. ExpressionPlan(plan.count, plan.kinds, plan.literals, plan.reads,
                         plan.left, plan.right, completed)
        BY <1>1, SourceMatchedNodesSupplyTheTypedExpressionPlan, SMT
            DEF plan, LiteralReadAddCertificate
    <1>3. ExpressionReadKeys(plan.count, plan.kinds, plan.reads) \subseteq bound
        BY SMT DEF plan, ExtractedNodePlan, ExpressionReadKeys, LiteralReadAddCertificate
    <1>4. PartialExpressionPlan(plan.count, plan.kinds, plan.literals,
                plan.reads, plan.left, plan.right, bound, state)
        BY <1>2, <1>3, SMT DEF PartialExpressionPlan, completed, LiteralReadAddCertificate
    <1>5. \E source, generated :
              /\ SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
                     plan.reads, plan.left, plan.right, state, source)
              /\ GeneratedExpressionHistory(plan.count, plan.kinds, plan.literals,
                     plan.reads, plan.left, plan.right, state, generated)
              /\ \A index \in 0..plan.count :
                     /\ OutcomeAgrees(source, generated, index)
                     /\ source[index] \in ExpressionOutcomes
                     /\ generated[index] \in ExpressionOutcomes
        BY <1>4, PartialOrderedIntExpressionsPreserveValueAndFailure
    <1>6. \A history : SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
                plan.reads, plan.left, plan.right, state, history) =>
              /\ \E meaning : SourceSyntaxHistory(view, state, meaning)
              /\ \A meaning : SourceSyntaxHistory(view, state, meaning)
                     => history[plan.count] = meaning[view.root]
        PROOF
        <2>. SUFFICES ASSUME NEW history,
                     SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
                         plan.reads, plan.left, plan.right, state, history)
                     PROVE /\ \E meaning : SourceSyntaxHistory(view, state, meaning)
                           /\ \A meaning : SourceSyntaxHistory(view, state, meaning)
                                  => history[plan.count] = meaning[view.root]
            BY SMT
        <2>1. SourceSyntaxHistory(view, state,
                  [node \in DOMAIN view.kinds |-> history[inverse[node]]])
            BY CertifiedPlanHistoriesSupplySourceSyntaxHistories DEF plan
        <2>2. \A meaning : SourceSyntaxHistory(view, state, meaning)
                     => history[plan.count] = meaning[view.root]
            PROOF
            <3>. SUFFICES ASSUME NEW meaning, SourceSyntaxHistory(view, state, meaning)
                         PROVE history[plan.count] = meaning[view.root]
                BY SMT
            <3>1. /\ SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
                       plan.reads, plan.left, plan.right, state, EmittedSourceSyntaxHistory(emitted, meaning))
                  /\ EmittedSourceSyntaxHistory(emitted, meaning)[plan.count] = meaning[view.root]
                BY MatchedPostorderNodesRetainIndependentSourceSyntaxMeaning, SMT
                    DEF plan, LiteralReadAddCertificate
            <3>2. PICK generated : GeneratedExpressionHistory(plan.count, plan.kinds,
                          plan.literals, plan.reads, plan.left, plan.right, state, generated)
                BY <1>5, SMT
            <3>3. \A index \in 0..plan.count : OutcomeAgrees(history, generated, index)
                BY <1>4, <3>2, AnyPartialOrderedIntHistoriesPreserveValueAndFailure, SMT
            <3>4. \A index \in 0..plan.count :
                    OutcomeAgrees(EmittedSourceSyntaxHistory(emitted, meaning), generated, index)
                BY <1>4, <3>1, <3>2, AnyPartialOrderedIntHistoriesPreserveValueAndFailure, SMT
            <3>5. plan.count \in 0..plan.count
                BY SMT DEF plan, ExtractedNodePlan, LiteralReadAddCertificate, NodeEmissionArrays
            <3>. QED BY ONLY <3>1, <3>3, <3>4, <3>5, SMT DEF OutcomeAgrees
        <2>. QED BY <2>1, <2>2, SMT
    <1>. QED BY <1>4, <1>5, <1>6 DEF plan


CertificateSource(view, bound) ==
    /\ bound \subseteq Keys
    /\ view.root \in DOMAIN view.kinds
    /\ \A node \in DOMAIN view.kinds :
        /\ view.kinds[node] \in {"literal", "read", "add"}
        /\ (view.kinds[node] = "literal" => InRange(view.literals[node]))
        /\ (view.kinds[node] = "read" => view.reads[node] \in bound)
        /\ (view.kinds[node] = "add" =>
               /\ view.left[node] \in DOMAIN view.kinds
               /\ view.right[node] \in DOMAIN view.kinds)

EmptyCertificateConstruction(view) ==
    [emitted |-> EmptyNodeEmission,
     inverse |-> [node \in DOMAIN view.kinds |-> 0]]

CertificateConstructorReady(view, before, origin) ==
    /\ origin \in DOMAIN view.kinds
    /\ before.inverse[origin] = 0
    /\ view.kinds[origin] \in {"literal", "read", "add"}
    /\ (view.kinds[origin] = "add" =>
           /\ view.left[origin] \in DOMAIN view.kinds
           /\ view.right[origin] \in DOMAIN view.kinds
           /\ before.inverse[view.left[origin]] \in 1..before.emitted.count
           /\ before.inverse[view.right[origin]] \in 1..before.emitted.count)

AppendCertificateConstructor(view, before, origin) ==
    LET emitted == before.emitted
        count == emitted.count + 1
        kind == view.kinds[origin]
        node == [kind |-> kind,
                 payload |-> IF kind = "literal" THEN view.literals[origin]
                             ELSE IF kind = "read" THEN view.reads[origin] ELSE 0,
                 left |-> IF kind = "add" THEN before.inverse[view.left[origin]] ELSE 0,
                 right |-> IF kind = "add" THEN before.inverse[view.right[origin]] ELSE 0]
    IN [emitted |-> [count |-> count, height |-> 1, indices |-> <<count>>,
                    nodes |-> HistoryAppend(emitted.nodes, emitted.count, node),
                    origins |-> HistoryAppend(emitted.origins, emitted.count, origin)],
        inverse |-> [source \in DOMAIN view.kinds |->
                     IF source = origin THEN count ELSE before.inverse[source]]]

CertificateConstructionInvariant(view, current) ==
    /\ NodeEmissionArrays(current.emitted)
    /\ current.emitted.origins \in [1..current.emitted.count -> DOMAIN view.kinds]
    /\ current.inverse \in [DOMAIN view.kinds -> 0..current.emitted.count]
    /\ \A index \in 1..current.emitted.count :
           current.inverse[current.emitted.origins[index]] = index
    /\ \A node \in DOMAIN view.kinds : current.inverse[node] > 0 =>
           current.emitted.origins[current.inverse[node]] = node
    /\ AllNodePayloadsMatchSource(view, current.emitted)

THEOREM EmptyCompilerCertificateStartsTheConstruction ==
    ASSUME NEW view
    PROVE CertificateConstructionInvariant(view, EmptyCertificateConstruction(view))
    BY SMT DEF CertificateConstructionInvariant, EmptyCertificateConstruction,
        EmptyNodeEmission, NodeEmissionArrays, AllNodePayloadsMatchSource

THEOREM CompilerCertificateConstructorPreservesTheInvariant ==
    ASSUME NEW view, NEW before, NEW origin,
           CertificateConstructionInvariant(view, before),
           CertificateConstructorReady(view, before, origin)
    PROVE CertificateConstructionInvariant(view, AppendCertificateConstructor(view, before, origin))
    PROOF
    <1>. DEFINE after == AppendCertificateConstructor(view, before, origin)
                count == before.emitted.count
    <1>1. count \in Nat
        BY SMT DEF count, CertificateConstructionInvariant, NodeEmissionArrays
    <1>2. /\ after.emitted.count = count + 1
          /\ NodeEmissionArrays(after.emitted)
          /\ after.emitted.origins \in [1..(count + 1) -> DOMAIN view.kinds]
          /\ after.inverse \in [DOMAIN view.kinds -> 0..(count + 1)]
        BY <1>1, SMT DEF after, count, AppendCertificateConstructor,
            CertificateConstructionInvariant, CertificateConstructorReady, NodeEmissionArrays, HistoryAppend
    <1>3. \A index \in 1..count :
          /\ after.emitted.nodes[index] = before.emitted.nodes[index]
          /\ after.emitted.origins[index] = before.emitted.origins[index]
          /\ before.emitted.origins[index] # origin
          /\ after.inverse[before.emitted.origins[index]] = index
        BY <1>1, SMT DEF after, count, AppendCertificateConstructor,
            CertificateConstructionInvariant, CertificateConstructorReady, HistoryAppend
    <1>4. /\ after.emitted.origins[count + 1] = origin
          /\ after.inverse[origin] = count + 1
        BY <1>1, SMT DEF after, count, AppendCertificateConstructor, CertificateConstructorReady, HistoryAppend
    <1>5. \A index \in 1..after.emitted.count :
              after.inverse[after.emitted.origins[index]] = index
        BY ONLY <1>1, <1>2, <1>3, <1>4, SMT
    <1>6. \A node \in DOMAIN view.kinds : after.inverse[node] > 0 =>
              after.emitted.origins[after.inverse[node]] = node
        BY <1>1, <1>3, <1>4, SMT DEF after, count, AppendCertificateConstructor,
            CertificateConstructionInvariant
    <1>7. \A index \in 1..count : NodePayloadMatchesSource(view, after.emitted, index)
        PROOF
        <2>. SUFFICES ASSUME NEW index \in 1..count
                     PROVE NodePayloadMatchesSource(view, after.emitted, index)
            BY SMT
        <2>1. NodePayloadMatchesSource(view, before.emitted, index)
            BY SMT DEF count, CertificateConstructionInvariant, AllNodePayloadsMatchSource
        <2>2. before.emitted.nodes[index].kind = "add" =>
              /\ before.emitted.nodes[index].left \in 1..count
              /\ before.emitted.nodes[index].right \in 1..count
            BY ONLY <1>1, <2>1, SMT DEF NodePayloadMatchesSource
        <2>. QED BY ONLY <1>3, <2>1, <2>2, SMT DEF NodePayloadMatchesSource
    <1>8. NodePayloadMatchesSource(view, after.emitted, count + 1)
        PROOF
        <2>1. view.kinds[origin] = "add" =>
              /\ before.inverse[view.left[origin]] \in 1..count
              /\ before.inverse[view.right[origin]] \in 1..count
            BY SMT DEF count, CertificateConstructorReady
        <2>2. view.kinds[origin] = "add" =>
              /\ before.emitted.origins[before.inverse[view.left[origin]]] = view.left[origin]
              /\ before.emitted.origins[before.inverse[view.right[origin]]] = view.right[origin]
            BY <2>1, SMT DEF count, CertificateConstructionInvariant, CertificateConstructorReady
        <2>. QED BY <1>1, <1>3, <1>4, <2>1, <2>2, SMT
            DEF after, count, AppendCertificateConstructor, CertificateConstructorReady,
                NodePayloadMatchesSource, HistoryAppend
    <1>9. AllNodePayloadsMatchSource(view, after.emitted)
        BY ONLY <1>1, <1>2, <1>7, <1>8, SMT DEF AllNodePayloadsMatchSource
    <1>. QED BY <1>2, <1>5, <1>6, <1>9 DEF CertificateConstructionInvariant, after

CompilerCertificateConstruction(view, steps, origins, history) ==
    /\ steps \in Nat \ {0}
    /\ origins \in [1..steps -> DOMAIN view.kinds]
    /\ history[0] = EmptyCertificateConstruction(view)
    /\ \A step \in 1..steps :
        /\ CertificateConstructorReady(view, history[step - 1], origins[step])
        /\ history[step] = AppendCertificateConstructor(view, history[step - 1], origins[step])
    /\ \A node \in DOMAIN view.kinds : history[steps].inverse[node] > 0
    /\ history[steps].emitted.origins[history[steps].emitted.count] = view.root

THEOREM CompilerConstructionSuppliesLiteralReadAddCertificate ==
    ASSUME NEW view, NEW bound, NEW fallback \in Keys,
           CertificateSource(view, bound), NEW steps, NEW origins, NEW history,
           CompilerCertificateConstruction(view, steps, origins, history)
    PROVE LiteralReadAddCertificate(view, history[steps].emitted,
              history[steps].inverse, fallback, bound)
    PROOF
    <1>. DEFINE holds(step) == CertificateConstructionInvariant(view, history[step])
    <1>1. holds(0)
        BY EmptyCompilerCertificateStartsTheConstruction DEF holds, CompilerCertificateConstruction
    <1>2. \A step \in 1..steps :
              (\A prior \in 0..(step - 1) : holds(prior)) => holds(step)
        PROOF
        <2>. SUFFICES ASSUME NEW step \in 1..steps,
                             \A prior \in 0..(step - 1) : holds(prior)
                     PROVE holds(step)
            BY SMT
        <2>1. holds(step - 1)
            BY SMT DEF CompilerCertificateConstruction
        <2>. QED BY <2>1, CompilerCertificateConstructorPreservesTheInvariant, SMT
            DEF holds, CompilerCertificateConstruction
    <1>3. steps \in Nat
        BY SMT DEF CompilerCertificateConstruction
    <1>4. \A step \in 0..steps : holds(step)
        BY <1>1, <1>2, <1>3, FiniteIndexedPrefixProperty
    <1>5. CertificateConstructionInvariant(view, history[steps])
        BY <1>3, <1>4, SMT DEF holds
    <1>6. history[steps].emitted.count > 0
        PROOF
        <2>0. history[steps].emitted.count \in Nat
            BY <1>5 DEF CertificateConstructionInvariant, NodeEmissionArrays
        <2>1. view.root \in DOMAIN view.kinds
            BY DEF CertificateSource
        <2>2. /\ history[steps].inverse[view.root] \in 0..history[steps].emitted.count
              /\ history[steps].inverse[view.root] > 0
            BY <1>5, <2>1, SMT DEF CertificateConstructionInvariant, CompilerCertificateConstruction
        <2>. QED BY ONLY <2>0, <2>2, SMT
    <1>7. TypedVisitedSourceInputs(view, history[steps].emitted)
        BY <1>5, SMT DEF CertificateConstructionInvariant, CertificateSource, TypedVisitedSourceInputs
    <1>. QED BY <1>5, <1>6, <1>7, SMT DEF LiteralReadAddCertificate,
        CertificateConstructionInvariant, CertificateSource, CompilerCertificateConstruction,
        AllNodePayloadsMatchSource, NodePayloadMatchesSource


CompilerCertificatePrefix(view, emitted, inverse, upto) ==
    [emitted |-> [count |-> upto, height |-> IF upto = 0 THEN 0 ELSE 1,
       indices |-> [position \in 1..(IF upto = 0 THEN 0 ELSE 1) |-> upto],
       nodes |-> [index \in 1..upto |-> emitted.nodes[index]],
       origins |-> [index \in 1..upto |-> emitted.origins[index]]],
     inverse |-> [source \in DOMAIN view.kinds |->
       IF inverse[source] <= upto THEN inverse[source] ELSE 0]]

THEOREM CompilerCertificatePrefixesRealizeTheConstructor ==
    ASSUME NEW view, NEW emitted, NEW inverse, NEW step \in Nat \ {0},
           LET before == CompilerCertificatePrefix(view, emitted, inverse, step - 1)
               after == CompilerCertificatePrefix(view, emitted, inverse, step)
               appended == AppendCertificateConstructor(view, before, emitted.origins[step])
           IN /\ emitted.nodes[step] = appended.emitted.nodes[step]
              /\ \A node \in DOMAIN view.kinds : after.inverse[node] = appended.inverse[node]
    PROVE CompilerCertificatePrefix(view, emitted, inverse, step)
        = AppendCertificateConstructor(view,
            CompilerCertificatePrefix(view, emitted, inverse, step - 1), emitted.origins[step])
    PROOF
    <1>. DEFINE before == CompilerCertificatePrefix(view, emitted, inverse, step - 1)
                after == CompilerCertificatePrefix(view, emitted, inverse, step)
                appended == AppendCertificateConstructor(view, before, emitted.origins[step])
    <1>1. /\ before.emitted.count = step - 1
          /\ appended.emitted.count = step
          /\ after.emitted.count = step
          /\ after.emitted.height = appended.emitted.height
          /\ after.emitted.indices = appended.emitted.indices
        BY SMT DEF before, after, appended, CompilerCertificatePrefix, AppendCertificateConstructor
    <1>2. \A index \in 1..step : after.emitted.nodes[index] = appended.emitted.nodes[index]
        PROOF
        <2>. SUFFICES ASSUME NEW index \in 1..step
                     PROVE after.emitted.nodes[index] = appended.emitted.nodes[index]
            BY SMT
        <2>1. CASE index = step
            BY <2>1, SMT DEF after, CompilerCertificatePrefix, appended, before
        <2>2. CASE index # step
            BY <2>2, SMT DEF before, after, appended, CompilerCertificatePrefix,
                AppendCertificateConstructor, HistoryAppend
        <2>. QED BY <2>1, <2>2, SMT
    <1>3. after.emitted.nodes = appended.emitted.nodes
        BY <1>2, SMT DEF before, after, appended, CompilerCertificatePrefix,
            AppendCertificateConstructor, HistoryAppend
    <1>4. after.emitted.origins = appended.emitted.origins
        BY SMT DEF before, after, appended, CompilerCertificatePrefix,
            AppendCertificateConstructor, HistoryAppend
    <1>5. after.inverse = appended.inverse
        BY SMT DEF before, after, appended, CompilerCertificatePrefix, AppendCertificateConstructor
    <1>6a. after.emitted = [count |-> after.emitted.count, height |-> after.emitted.height,
                indices |-> after.emitted.indices, nodes |-> after.emitted.nodes, origins |-> after.emitted.origins]
        BY SMT DEF after, CompilerCertificatePrefix
    <1>6b. appended.emitted = [count |-> appended.emitted.count, height |-> appended.emitted.height,
                indices |-> appended.emitted.indices, nodes |-> appended.emitted.nodes, origins |-> appended.emitted.origins]
        BY SMT DEF appended, AppendCertificateConstructor
    <1>6. after.emitted = appended.emitted
        BY ONLY <1>1, <1>3, <1>4, <1>6a, <1>6b, SMT
    <1>7a. after = [emitted |-> after.emitted, inverse |-> after.inverse]
        BY SMT DEF after, CompilerCertificatePrefix
    <1>7b. appended = [emitted |-> appended.emitted, inverse |-> appended.inverse]
        BY SMT DEF appended, AppendCertificateConstructor
    <1>. QED BY ONLY <1>5, <1>6, <1>7a, <1>7b, SMT DEF before, after, appended


\* orderedIntCertificate's second loop: completed contains source occurrence IDs;
\* current.emitted.nodes/origins and current.inverse correspond to nodes/origins/indices.
\* These guard lemmas feed EmittingACompilerFramePreservesLoopInvariants.
CompletedCertificateRoots(view, current, completed) ==
    /\ WellFormedVisitPrefix(completed)
    /\ \A position \in 1..completed.height :
        /\ completed.terms[position] \in DOMAIN view.kinds
        /\ current.inverse[completed.terms[position]] \in 1..current.emitted.count

THEOREM EmptyCompilerCertificateHasNoCompletedRoots ==
    ASSUME NEW view
    PROVE CompletedCertificateRoots(view, EmptyCertificateConstruction(view), EmptyVisitPrefix)
    BY SMT DEF CompletedCertificateRoots, WellFormedVisitPrefix, EmptyVisitPrefix, VisitPrefix

THEOREM PendingCompilerAddHasItsOrderedCompletedChildren ==
    ASSUME NEW view, NEW before, NEW height, NEW pending, NEW completed, NEW goal,
           PendingVisitContract(height, pending, completed, goal, view.left, view.right),
           CompletedCertificateRoots(view, before, completed),
           height > 0, pending[height].expanded
    PROVE LET origin == pending[height].node
          IN /\ completed.height >= 2
             /\ completed.terms[completed.height - 1] = view.left[origin]
             /\ completed.terms[completed.height] = view.right[origin]
             /\ view.left[origin] \in DOMAIN view.kinds
             /\ view.right[origin] \in DOMAIN view.kinds
             /\ before.inverse[view.left[origin]] \in 1..before.emitted.count
             /\ before.inverse[view.right[origin]] \in 1..before.emitted.count
    PROOF
    <1>1. /\ completed = pending[height].prefix
          /\ WellFormedVisitFrame(pending[height], view.left, view.right)
        BY SMT DEF PendingVisitContract
    <1>2. /\ completed.height \in Nat /\ completed.height >= 2
          /\ completed.terms[completed.height - 1] = view.left[pending[height].node]
          /\ completed.terms[completed.height] = view.right[pending[height].node]
        BY <1>1, SMT DEF WellFormedVisitFrame, WellFormedVisitPrefix
    <1>3. /\ completed.height - 1 \in 1..completed.height
          /\ completed.height \in 1..completed.height
        BY ONLY <1>2, SMT
    <1>. QED BY <1>2, <1>3, SMT DEF CompletedCertificateRoots

THEOREM PendingCompilerEmissionDerivesConstructorReadiness ==
    ASSUME NEW view, NEW before, NEW height, NEW pending, NEW completed, NEW goal,
           PendingVisitContract(height, pending, completed, goal, view.left, view.right),
           CompletedCertificateRoots(view, before, completed),
           height > 0, pending[height].node \in DOMAIN view.kinds,
           before.inverse[pending[height].node] = 0,
           (pending[height].expanded /\ view.kinds[pending[height].node] = "add")
             \/ (~pending[height].expanded /\ view.kinds[pending[height].node] \in {"literal", "read"})
    PROVE /\ CertificateConstructorReady(view, before, pending[height].node)
          /\ (CertificateConstructionInvariant(view, before) =>
                CertificateConstructionInvariant(view,
                  AppendCertificateConstructor(view, before, pending[height].node)))
    PROOF
    <1>1. pending[height].expanded =>
              /\ view.left[pending[height].node] \in DOMAIN view.kinds
              /\ view.right[pending[height].node] \in DOMAIN view.kinds
              /\ before.inverse[view.left[pending[height].node]] \in 1..before.emitted.count
              /\ before.inverse[view.right[pending[height].node]] \in 1..before.emitted.count
        PROOF
        <2>. SUFFICES ASSUME pending[height].expanded
                     PROVE /\ view.left[pending[height].node] \in DOMAIN view.kinds
                           /\ view.right[pending[height].node] \in DOMAIN view.kinds
                           /\ before.inverse[view.left[pending[height].node]] \in 1..before.emitted.count
                           /\ before.inverse[view.right[pending[height].node]] \in 1..before.emitted.count
            BY SMT
        <2>1. LET origin == pending[height].node
              IN /\ completed.height >= 2
                 /\ completed.terms[completed.height - 1] = view.left[origin]
                 /\ completed.terms[completed.height] = view.right[origin]
                 /\ view.left[origin] \in DOMAIN view.kinds
                 /\ view.right[origin] \in DOMAIN view.kinds
                 /\ before.inverse[view.left[origin]] \in 1..before.emitted.count
                 /\ before.inverse[view.right[origin]] \in 1..before.emitted.count
            BY PendingCompilerAddHasItsOrderedCompletedChildren
        <2>. QED BY ONLY <2>1, SMT
    <1>2. CertificateConstructorReady(view, before, pending[height].node)
        BY <1>1, SMT DEF CertificateConstructorReady
    <1>. QED BY <1>2, CompilerCertificateConstructorPreservesTheInvariant, SMT


THEOREM AppendingCompilerNodePreservesCompletedRoots ==
    ASSUME NEW view, NEW before, NEW completed,
           CompletedCertificateRoots(view, before, completed),
           before.emitted.count \in Nat, NEW origin \in DOMAIN view.kinds,
           NEW retained \in 0..completed.height
    PROVE CompletedCertificateRoots(view, AppendCertificateConstructor(view, before, origin),
              PushVisitPrefix(VisitPrefix(retained, HistoryPrefix(completed.terms, retained)), origin))
    PROOF
    <1>. DEFINE after == AppendCertificateConstructor(view, before, origin)
                next == PushVisitPrefix(VisitPrefix(retained, HistoryPrefix(completed.terms, retained)), origin)
    <1>1. /\ completed.height \in Nat /\ retained \in Nat
          /\ after.emitted.count = before.emitted.count + 1
          /\ next.height = retained + 1
          /\ WellFormedVisitPrefix(next)
        BY SMT DEF after, next, CompletedCertificateRoots, WellFormedVisitPrefix,
            AppendCertificateConstructor, PushVisitPrefix, VisitPrefix, HistoryPrefix, HistoryAppend
    <1>2. \A position \in 1..retained :
              /\ next.terms[position] = completed.terms[position]
              /\ completed.terms[position] \in DOMAIN view.kinds
              /\ before.inverse[completed.terms[position]] \in 1..before.emitted.count
        BY <1>1, SMT DEF next, CompletedCertificateRoots, PushVisitPrefix,
            VisitPrefix, HistoryPrefix, HistoryAppend
    <1>3. \A position \in 1..retained :
              after.inverse[next.terms[position]] \in 1..after.emitted.count
        BY <1>1, <1>2, SMT DEF after, AppendCertificateConstructor
    <1>4. /\ next.terms[retained + 1] = origin
          /\ after.inverse[origin] = after.emitted.count
          /\ after.emitted.count \in 1..after.emitted.count
        BY <1>1, SMT DEF after, next, AppendCertificateConstructor,
            PushVisitPrefix, VisitPrefix, HistoryAppend
    <1>5. \A position \in 1..next.height :
              /\ next.terms[position] \in DOMAIN view.kinds
              /\ after.inverse[next.terms[position]] \in 1..after.emitted.count
        BY ONLY <1>1, <1>2, <1>3, <1>4, SMT
    <1>. QED BY <1>1, <1>5 DEF CompletedCertificateRoots, after, next


THEOREM EmittingACompilerFramePreservesLoopInvariants ==
    ASSUME NEW view, NEW before, NEW height, NEW pending, NEW completed, NEW goal,
           PendingVisitContract(height, pending, completed, goal, view.left, view.right),
           CompletedCertificateRoots(view, before, completed),
           CertificateConstructionInvariant(view, before),
           height > 0, pending[height].node \in DOMAIN view.kinds,
           before.inverse[pending[height].node] = 0,
           (pending[height].expanded /\ view.kinds[pending[height].node] = "add")
             \/ (~pending[height].expanded /\ view.kinds[pending[height].node] \in {"literal", "read"})
    PROVE LET after == AppendCertificateConstructor(view, before, pending[height].node)
              nextCompleted == VisitFrameExit(pending[height])
          IN /\ PendingVisitContract(height - 1, HistoryPrefix(pending, height - 1),
                    nextCompleted, goal, view.left, view.right)
             /\ CertificateConstructionInvariant(view, after)
             /\ CompletedCertificateRoots(view, after, nextCompleted)
    PROOF
    <1>. DEFINE origin == pending[height].node
                after == AppendCertificateConstructor(view, before, origin)
                nextCompleted == VisitFrameExit(pending[height])
                retained == IF pending[height].expanded THEN completed.height - 2 ELSE completed.height
    <1>1. /\ CertificateConstructorReady(view, before, pending[height].node)
          /\ (CertificateConstructionInvariant(view, before) =>
                CertificateConstructionInvariant(view,
                    AppendCertificateConstructor(view, before, pending[height].node)))
        BY PendingCompilerEmissionDerivesConstructorReadiness
    <1>2. /\ completed = pending[height].prefix
          /\ WellFormedVisitPrefix(completed)
          /\ completed.height \in Nat
          /\ (pending[height].expanded => completed.height >= 2)
          /\ before.emitted.count \in Nat
        BY SMT DEF PendingVisitContract, WellFormedVisitFrame, WellFormedVisitPrefix,
            CertificateConstructionInvariant, NodeEmissionArrays
    <1>3. retained \in 0..completed.height
        BY <1>2, SMT DEF retained
    <1>4. nextCompleted =
              PushVisitPrefix(VisitPrefix(retained, HistoryPrefix(completed.terms, retained)), origin)
        BY <1>2, <1>3, SMT DEF nextCompleted, retained, origin, VisitFrameExit,
            FoldVisitPrefix, PushVisitPrefix, VisitPrefix, HistoryPrefix, HistoryAppend,
            WellFormedVisitPrefix
    <1>5. CompletedCertificateRoots(view, AppendCertificateConstructor(view, before, origin),
              PushVisitPrefix(VisitPrefix(retained, HistoryPrefix(completed.terms, retained)), origin))
        BY <1>2, <1>3, AppendingCompilerNodePreservesCompletedRoots, SMT DEF origin
    <1>6. PendingVisitContract(height - 1, HistoryPrefix(pending, height - 1),
              VisitFrameExit(pending[height]), goal, view.left, view.right)
        BY CompletingAPendingFramePreservesTheVisitContract
    <1>. QED BY <1>1, <1>4, <1>5, <1>6, SMT DEF after, nextCompleted, origin


\* Required output property of the Swift allocation loop, not a proved interpretation
\* of that loop. The traversal results below are conditional on this source shape.
CompilerOccurrenceTree(view, count) ==
    /\ count \in Nat \ {0}
    /\ view.root = 1
    /\ DOMAIN view.kinds = 1..count
    /\ \A node \in 1..count :
        /\ view.kinds[node] \in {"literal", "read", "add"}
        /\ (view.kinds[node] = "add" =>
            /\ view.left[node] \in (node + 1)..count
            /\ view.right[node] \in (node + 1)..count
            /\ view.left[node] # view.right[node])
    /\ \A first, second \in 1..count :
        (view.kinds[first] = "add" /\ view.kinds[second] = "add" /\
         {view.left[first], view.right[first]} \cap {view.left[second], view.right[second]} # {})
        => first = second
    /\ \A child \in 2..count : \E parent \in 1..(child - 1) :
        view.kinds[parent] = "add" /\ child \in {view.left[parent], view.right[parent]}

\* Insert after CompilerOccurrenceTree and before CompilerScheduledOccurrences.
\* expressions/source use one-based histories; Swift position remains zero-based.
\* mass is erased ghost data, recording prefix subtree sizes, never Swift storage.
SupportedAllocationInput(root, terms, syntax, weight, bound) ==
    /\ root \in terms /\ bound \subseteq Keys
    /\ DOMAIN syntax = terms
    /\ weight \in [terms -> Nat \ {0}]
    /\ \A term \in terms :
        /\ syntax[term].kind \in {"literal", "read", "add"}
        /\ (syntax[term].kind = "literal" =>
              /\ InRange(syntax[term].literal) /\ weight[term] = 1)
        /\ (syntax[term].kind = "read" =>
              /\ syntax[term].read \in bound /\ weight[term] = 1)
        /\ (syntax[term].kind = "add" =>
              /\ syntax[term].left \in terms /\ syntax[term].right \in terms
              /\ weight[term] = 1 + weight[syntax[term].left] + weight[syntax[term].right])

\* Independent finite typed-source constructor derivations, not compiler runs.
\* Reviewed constructor map: .value(.int(v)) -> <<"literal",v>>;
\* .variable(k) -> <<"read",k>>; .add(l,r) -> <<"add",l,r>>.
AllocationConstructorDerivation(root, bound, derivation) ==
    /\ bound \subseteq Keys
    /\ derivation.count \in Nat \ {0}
    /\ DOMAIN derivation.terms = 1..derivation.count
    /\ DOMAIN derivation.left = 1..derivation.count
    /\ DOMAIN derivation.right = 1..derivation.count
    /\ derivation.terms[derivation.count] = root
    /\ \A index \in 1..derivation.count :
        LET term == derivation.terms[index]
        IN /\ term[1] \in {"literal", "read", "add"}
           /\ (term[1] = "literal" => /\ DOMAIN term = 1..2 /\ InRange(term[2]))
           /\ (term[1] = "read" => /\ DOMAIN term = 1..2 /\ term[2] \in bound)
           /\ (term[1] = "add" =>
                 /\ DOMAIN term = 1..3
                 /\ derivation.left[index] \in 1..(index - 1)
                 /\ derivation.right[index] \in 1..(index - 1)
                 /\ term[2] = derivation.terms[derivation.left[index]]
                 /\ term[3] = derivation.terms[derivation.right[index]])
    \* No disconnected constructor premises: every nonroot has a later parent.
    /\ \A child \in 1..(derivation.count - 1) :
        \E parent \in (child + 1)..derivation.count :
            /\ derivation.terms[parent][1] = "add"
            /\ child \in {derivation.left[parent], derivation.right[parent]}

FiniteSupportedAllocationTerm(root, bound) ==
    \E derivation : AllocationConstructorDerivation(root, bound, derivation)

AllocationLeafDerivation(term) ==
    [count |-> 1, terms |-> [index \in 1..1 |-> term],
     left |-> [index \in 1..1 |-> 0], right |-> [index \in 1..1 |-> 0]]

AllocationAddDerivation(first, second) ==
    LET total == first.count + second.count + 1
        term == <<"add", first.terms[first.count], second.terms[second.count]>>
    IN [count |-> total,
        terms |-> [index \in 1..total |->
            IF index <= first.count THEN first.terms[index]
            ELSE IF index < total THEN second.terms[index - first.count]
            ELSE term],
        left |-> [index \in 1..total |->
            IF index <= first.count THEN first.left[index]
            ELSE IF index < total THEN second.left[index - first.count] + first.count
            ELSE first.count],
        right |-> [index \in 1..total |->
            IF index <= first.count THEN first.right[index]
            ELSE IF index < total THEN second.right[index - first.count] + first.count
            ELSE first.count + second.count]]

THEOREM LiteralAndReadConstructorsHaveFiniteSourceDerivations ==
    ASSUME NEW bound \in SUBSET Keys
    PROVE /\ \A value \in SwiftIntMin..SwiftIntMax :
                FiniteSupportedAllocationTerm(<<"literal", value>>, bound)
          /\ \A key \in bound : FiniteSupportedAllocationTerm(<<"read", key>>, bound)
    PROOF
    <1>1. \A value \in SwiftIntMin..SwiftIntMax :
              AllocationConstructorDerivation(<<"literal", value>>, bound,
                  AllocationLeafDerivation(<<"literal", value>>))
        BY SMT DEF AllocationConstructorDerivation, AllocationLeafDerivation, InRange
    <1>2. \A key \in bound :
              AllocationConstructorDerivation(<<"read", key>>, bound,
                  AllocationLeafDerivation(<<"read", key>>))
        BY SMT DEF AllocationConstructorDerivation, AllocationLeafDerivation
    <1>. QED BY <1>1, <1>2, SMT DEF FiniteSupportedAllocationTerm

THEOREM AddingFiniteSourceDerivationsPreservesConstructorClosure ==
    ASSUME NEW left, NEW right, NEW bound,
           NEW first, AllocationConstructorDerivation(left, bound, first),
           NEW second, AllocationConstructorDerivation(right, bound, second)
    PROVE AllocationConstructorDerivation(<<"add", left, right>>, bound,
              AllocationAddDerivation(first, second))
    PROOF
    <1>. DEFINE combined == AllocationAddDerivation(first, second)
                total == first.count + second.count + 1
    <1>1. /\ first.count \in Nat \ {0} /\ second.count \in Nat \ {0}
          /\ total \in Nat \ {0}
        BY SMT DEF AllocationConstructorDerivation, total
    <1>2. \A index \in 1..combined.count :
            LET term == combined.terms[index]
            IN /\ term[1] \in {"literal", "read", "add"}
               /\ (term[1] = "literal" => /\ DOMAIN term = 1..2 /\ InRange(term[2]))
               /\ (term[1] = "read" => /\ DOMAIN term = 1..2 /\ term[2] \in bound)
               /\ (term[1] = "add" =>
                     /\ DOMAIN term = 1..3
                     /\ combined.left[index] \in 1..(index - 1)
                     /\ combined.right[index] \in 1..(index - 1)
                     /\ term[2] = combined.terms[combined.left[index]]
                     /\ term[3] = combined.terms[combined.right[index]])
        BY <1>1, SMT DEF combined, total, AllocationAddDerivation, AllocationConstructorDerivation
    <1>3. \A child \in 1..(combined.count - 1) :
            \E parent \in (child + 1)..combined.count :
                /\ combined.terms[parent][1] = "add"
                /\ child \in {combined.left[parent], combined.right[parent]}
        PROOF
        <2>coverage. /\ \A child \in 1..(first.count - 1) :
                          \E parent \in (child + 1)..first.count :
                              /\ first.terms[parent][1] = "add"
                              /\ child \in {first.left[parent], first.right[parent]}
                     /\ \A child \in 1..(second.count - 1) :
                          \E parent \in (child + 1)..second.count :
                              /\ second.terms[parent][1] = "add"
                              /\ child \in {second.left[parent], second.right[parent]}
            BY DEF AllocationConstructorDerivation
        <2>count. combined.count = total
            BY DEF combined, total, AllocationAddDerivation
        <2>. SUFFICES ASSUME NEW child \in 1..(combined.count - 1)
              PROVE \E parent \in (child + 1)..combined.count :
                  /\ combined.terms[parent][1] = "add"
                  /\ child \in {combined.left[parent], combined.right[parent]}
            OBVIOUS
        <2>bounds. child \in 1..(first.count + second.count)
            BY <1>1, <2>count, SMT DEF total
        <2>first. CASE child < first.count
            <3>index. child \in 1..(first.count - 1)
                BY <1>1, <2>bounds, <2>first, SMT
            <3>parent. PICK parent \in (child + 1)..first.count :
                          /\ first.terms[parent][1] = "add"
                          /\ child \in {first.left[parent], first.right[parent]}
                BY ONLY <2>coverage, <3>index, SMT
            <3>witness. /\ parent \in (child + 1)..combined.count
                        /\ combined.terms[parent][1] = "add"
                        /\ child \in {combined.left[parent], combined.right[parent]}
                BY <1>1, <2>count, <3>index, <3>parent, SMT DEF combined, total, AllocationAddDerivation
            <3>. QED BY <3>witness, SMT
        <2>second. CASE first.count < child /\ child < first.count + second.count
            <3>index. child - first.count \in 1..(second.count - 1)
                BY <1>1, <2>bounds, <2>second, SMT
            <3>parent. PICK parent \in (child - first.count + 1)..second.count :
                          /\ second.terms[parent][1] = "add"
                          /\ child - first.count \in {second.left[parent], second.right[parent]}
                BY ONLY <2>coverage, <3>index, SMT
            <3>witness. /\ parent + first.count \in (child + 1)..combined.count
                        /\ combined.terms[parent + first.count][1] = "add"
                        /\ child \in {combined.left[parent + first.count], combined.right[parent + first.count]}
                BY <1>1, <2>count, <3>index, <3>parent, SMT DEF combined, total, AllocationAddDerivation
            <3>. QED BY <3>witness, SMT
        <2>roots. CASE child \in {first.count, first.count + second.count}
            <3>witness. /\ total \in (child + 1)..combined.count
                        /\ combined.terms[total][1] = "add"
                        /\ child \in {combined.left[total], combined.right[total]}
                BY <1>1, <2>count, <2>roots, SMT DEF combined, total, AllocationAddDerivation
            <3>. QED BY <3>witness, SMT
        <2>. QED BY <1>1, <2>bounds, <2>first, <2>second, <2>roots, SMT
    <1>roots. /\ bound \subseteq Keys
               /\ first.terms[first.count] = left /\ second.terms[second.count] = right
        BY DEF AllocationConstructorDerivation
    <1>head. /\ bound \subseteq Keys /\ combined.count \in Nat \ {0}
              /\ DOMAIN combined.terms = 1..combined.count
              /\ DOMAIN combined.left = 1..combined.count
              /\ DOMAIN combined.right = 1..combined.count
              /\ combined.terms[combined.count] = <<"add", left, right>>
        BY ONLY <1>1, <1>roots, SMT DEF combined, total, AllocationAddDerivation
    <1>. QED BY <1>head, <1>2, <1>3 DEF AllocationConstructorDerivation

THEOREM AddConstructorHasAFiniteSourceDerivation ==
    ASSUME NEW left, NEW right, NEW bound,
           FiniteSupportedAllocationTerm(left, bound), FiniteSupportedAllocationTerm(right, bound)
    PROVE FiniteSupportedAllocationTerm(<<"add", left, right>>, bound)
    BY AddingFiniteSourceDerivationsPreservesConstructorClosure, SMT DEF FiniteSupportedAllocationTerm

AllocationConstructorSizes(derivation, sizes) ==
    /\ sizes \in [1..derivation.count -> Nat \ {0}]
    /\ \A index \in 1..derivation.count :
        sizes[index] = IF derivation.terms[index][1] = "add"
            THEN 1 + sizes[derivation.left[index]] + sizes[derivation.right[index]] ELSE 1

THEOREM FiniteSourceDerivationsHavePositiveStructuralSizes ==
    ASSUME NEW root, NEW bound, NEW derivation,
           AllocationConstructorDerivation(root, bound, derivation)
    PROVE \E sizes : AllocationConstructorSizes(derivation, sizes)
    PROOF
    <1>. DEFINE steps == [index \in 1..derivation.count |->
        [prior \in [1..(index - 1) -> Nat \ {0}] |->
            IF derivation.terms[index][1] = "add"
            THEN 1 + prior[derivation.left[index]] + prior[derivation.right[index]] ELSE 1]]
    <1>1. \A index \in 1..derivation.count :
              steps[index] \in [[1..(index - 1) -> Nat \ {0}] -> Nat \ {0}]
        BY SMT DEF steps, AllocationConstructorDerivation
    <1>2. PICK sizes \in [1..derivation.count -> Nat \ {0}] :
              IndexedHistory(steps, sizes, derivation.count)
        BY <1>1, FiniteIndexedHistoryExists DEF AllocationConstructorDerivation
    <1>3. AllocationConstructorSizes(derivation, sizes)
        BY <1>2, SMT DEF AllocationConstructorSizes, AllocationConstructorDerivation,
            IndexedHistory, steps, HistoryPrefix
    <1>. QED BY <1>3, SMT

THEOREM EqualSourceConstructorValuesHaveEqualStructuralSizes ==
    ASSUME NEW root, NEW bound, NEW derivation,
           AllocationConstructorDerivation(root, bound, derivation),
           NEW sizes, AllocationConstructorSizes(derivation, sizes)
    PROVE \A first, second \in 1..derivation.count :
              derivation.terms[first] = derivation.terms[second] => sizes[first] = sizes[second]
    PROOF
    <1>. DEFINE holds(limit) == \A first, second \in 1..limit :
        derivation.terms[first] = derivation.terms[second] => sizes[first] = sizes[second]
    <1>1. holds(0) BY SMT DEF holds
    <1>2. ASSUME NEW index \in 1..derivation.count,
                 \A earlier \in 0..(index - 1) : holds(earlier)
          PROVE holds(index)
        <2>1. holds(index - 1)
            PROOF
            <3>count. derivation.count \in Nat \ {0}
                BY DEF AllocationConstructorDerivation
            <3>index. index - 1 \in 0..(index - 1)
                BY <3>count, SMT
            <3>. QED BY ONLY <3>index, (\A earlier \in 0..(index - 1) : holds(earlier)), SMT
        <2>. SUFFICES ASSUME NEW first \in 1..index, NEW second \in 1..index,
                             derivation.terms[first] = derivation.terms[second]
                     PROVE sizes[first] = sizes[second]
            BY SMT DEF holds
        <2>2. CASE derivation.terms[first][1] # "add"
            PROOF
            <3>indices. /\ first \in 1..derivation.count /\ second \in 1..derivation.count
                BY SMT DEF AllocationConstructorDerivation
            <3>leaves. /\ sizes[first] = 1 /\ sizes[second] = 1
                BY ONLY <3>indices, <2>2,
                    (derivation.terms[first] = derivation.terms[second]),
                    AllocationConstructorSizes(derivation, sizes), SMT DEF AllocationConstructorSizes
            <3>. QED BY <3>leaves
        <2>3. CASE derivation.terms[first][1] = "add"
            <3>1. /\ derivation.left[first] \in 1..(index - 1)
                  /\ derivation.left[second] \in 1..(index - 1)
                  /\ derivation.right[first] \in 1..(index - 1)
                  /\ derivation.right[second] \in 1..(index - 1)
                  /\ derivation.terms[derivation.left[first]] = derivation.terms[derivation.left[second]]
                  /\ derivation.terms[derivation.right[first]] = derivation.terms[derivation.right[second]]
                BY <2>3, SMT DEF AllocationConstructorDerivation
            <3>2. /\ sizes[derivation.left[first]] = sizes[derivation.left[second]]
                  /\ sizes[derivation.right[first]] = sizes[derivation.right[second]]
                BY <2>1, <3>1, SMT DEF holds
            <3>indices. /\ first \in 1..derivation.count /\ second \in 1..derivation.count
                BY SMT DEF AllocationConstructorDerivation
            <3>sizes. /\ sizes[first] = 1 + sizes[derivation.left[first]] + sizes[derivation.right[first]]
                       /\ sizes[second] = 1 + sizes[derivation.left[second]] + sizes[derivation.right[second]]
                BY ONLY <3>indices, <2>3,
                    (derivation.terms[first] = derivation.terms[second]),
                    AllocationConstructorSizes(derivation, sizes), SMT DEF AllocationConstructorSizes
            <3>. QED BY ONLY <3>sizes, <3>2, SMT
        <2>. QED BY <2>2, <2>3
    <1>count. derivation.count \in Nat
        BY DEF AllocationConstructorDerivation
    <1>. DEFINE flags == [index \in 0..derivation.count |-> holds(index)]
    <1>flags. /\ flags \in [0..derivation.count -> BOOLEAN] /\ flags[0]
               /\ \A index \in 1..derivation.count :
                     (\A earlier \in 0..(index - 1) : flags[earlier]) => flags[index]
        BY ONLY <1>count, <1>1, <1>2, SMT DEF flags
    <1>allFlags. \A index \in 0..derivation.count : flags[index]
        BY ONLY <1>count, <1>flags, FiniteBooleanPrefixProperty
    <1>3. \A index \in 0..derivation.count : holds(index)
        BY ONLY <1>allFlags DEF flags
    <1>. QED BY <1>3, SMT DEF holds, AllocationConstructorDerivation

AllocationTermSyntax(terms) ==
    [term \in terms |->
        [kind |-> term[1],
         literal |-> IF term[1] = "literal" THEN term[2] ELSE 0,
         read |-> IF term[1] = "read" THEN term[2] ELSE 0,
         left |-> IF term[1] = "add" THEN term[2] ELSE 0,
         right |-> IF term[1] = "add" THEN term[3] ELSE 0]]

THEOREM EveryFiniteSourceDerivationSuppliesTheAllocationInput ==
    ASSUME NEW root, NEW bound, NEW derivation,
           AllocationConstructorDerivation(root, bound, derivation)
    PROVE \E terms, weight :
              /\ terms = {derivation.terms[index] : index \in 1..derivation.count}
              /\ SupportedAllocationInput(root, terms, AllocationTermSyntax(terms), weight, bound)
    PROOF
    <1>1. PICK sizes : AllocationConstructorSizes(derivation, sizes)
        BY FiniteSourceDerivationsHavePositiveStructuralSizes
    <1>2. \A first, second \in 1..derivation.count :
              derivation.terms[first] = derivation.terms[second] => sizes[first] = sizes[second]
        BY <1>1, EqualSourceConstructorValuesHaveEqualStructuralSizes
    <1>. DEFINE terms == {derivation.terms[index] : index \in 1..derivation.count}
                representative(term) == CHOOSE index \in 1..derivation.count : derivation.terms[index] = term
                weight == [term \in terms |-> sizes[representative(term)]]
                syntax == AllocationTermSyntax(terms)
    <1>3. \A term \in terms :
              /\ representative(term) \in 1..derivation.count
              /\ derivation.terms[representative(term)] = term
        BY SMT DEF terms, representative
    <1>4. \A index \in 1..derivation.count : weight[derivation.terms[index]] = sizes[index]
        BY <1>2, <1>3, SMT DEF terms, weight
    <1>5. SupportedAllocationInput(root, terms, syntax, weight, bound)
        BY <1>1, <1>3, <1>4, SMT DEF SupportedAllocationInput,
            AllocationConstructorDerivation, AllocationConstructorSizes,
            terms, syntax, weight, AllocationTermSyntax
    <1>. QED BY <1>5, SMT DEF terms, syntax

THEOREM CheckedSourceSizesSupplyTheCanonicalAllocationInput ==
    ASSUME NEW root, NEW bound, NEW derivation,
           AllocationConstructorDerivation(root, bound, derivation),
           NEW sizes, AllocationConstructorSizes(derivation, sizes)
    PROVE \E terms, weight :
              /\ terms = {derivation.terms[index] : index \in 1..derivation.count}
              /\ SupportedAllocationInput(root, terms, AllocationTermSyntax(terms), weight, bound)
              /\ weight[root] = sizes[derivation.count]
    PROOF
    <1>input. PICK terms, weight :
        /\ terms = {derivation.terms[index] : index \in 1..derivation.count}
        /\ SupportedAllocationInput(root, terms, AllocationTermSyntax(terms), weight, bound)
        BY EveryFiniteSourceDerivationSuppliesTheAllocationInput
    <1>. DEFINE history == [index \in 1..derivation.count |-> weight[derivation.terms[index]]]
    <1>weightType. weight \in [terms -> Nat \ {0}]
        BY <1>input DEF SupportedAllocationInput
    <1>types. /\ derivation.count \in Nat \ {0}
               /\ history \in [1..derivation.count -> Nat \ {0}]
               /\ sizes \in [1..derivation.count -> Nat \ {0}]
        BY <1>input, <1>weightType, SMT DEF history,
            AllocationConstructorDerivation, AllocationConstructorSizes
    <1>recurrence. \A index \in 1..derivation.count :
        history[index] = IF derivation.terms[index][1] = "add"
            THEN 1 + history[derivation.left[index]] + history[derivation.right[index]] ELSE 1
        PROOF
        <2>. SUFFICES ASSUME NEW index \in 1..derivation.count
              PROVE history[index] = IF derivation.terms[index][1] = "add"
                  THEN 1 + history[derivation.left[index]] + history[derivation.right[index]] ELSE 1
            OBVIOUS
        <2>member. derivation.terms[index] \in terms
            BY ONLY <1>input, (index \in 1..derivation.count), SMT
        <2>syntax. LET node == AllocationTermSyntax(terms)[derivation.terms[index]]
                    IN /\ node.kind = derivation.terms[index][1]
                       /\ (derivation.terms[index][1] = "add" =>
                             /\ node.left = derivation.terms[index][2]
                             /\ node.right = derivation.terms[index][3])
            BY ONLY <2>member, SMT DEF AllocationTermSyntax
        <2>shape. /\ derivation.terms[index][1] \in {"literal", "read", "add"}
                   /\ (derivation.terms[index][1] = "add" =>
                         /\ derivation.left[index] \in 1..derivation.count
                         /\ derivation.right[index] \in 1..derivation.count
                         /\ derivation.terms[index][2] = derivation.terms[derivation.left[index]]
                         /\ derivation.terms[index][3] = derivation.terms[derivation.right[index]])
            BY <1>types, SMT DEF AllocationConstructorDerivation
        <2>leaf. CASE derivation.terms[index][1] # "add"
            <3>weight. weight[derivation.terms[index]] = 1
                BY <1>input, <2>member, <2>syntax, <2>shape, <2>leaf, SMT DEF SupportedAllocationInput
            <3>. QED BY <2>member, <2>leaf, <3>weight, SMT DEF history
        <2>add. CASE derivation.terms[index][1] = "add"
            <3>weight. weight[derivation.terms[index]] =
                1 + weight[derivation.terms[derivation.left[index]]] + weight[derivation.terms[derivation.right[index]]]
                BY <1>input, <2>member, <2>syntax, <2>shape, <2>add, SMT DEF SupportedAllocationInput
            <3>. QED BY <2>shape, <2>add, <3>weight, SMT DEF history
        <2>. QED BY <2>leaf, <2>add
    <1>step. \A index \in 1..derivation.count :
        ((\A child \in 1..(index - 1) : history[child] = sizes[child]) => history[index] = sizes[index])
        BY <1>recurrence, <1>types, SMT DEF AllocationConstructorDerivation, AllocationConstructorSizes
    <1>agree. history = sizes
        BY ONLY <1>types, <1>step, FiniteIndexedHistoriesAgree
    <1>root. weight[root] = sizes[derivation.count]
        BY <1>agree, <1>types, SMT DEF history, AllocationConstructorDerivation
    <1>. QED BY <1>input, <1>root, SMT

THEOREM EveryFiniteSupportedConstructorTermSuppliesTheAllocationInput ==
    ASSUME NEW root, NEW bound, FiniteSupportedAllocationTerm(root, bound)
    PROVE \E terms, weight :
              SupportedAllocationInput(root, terms, AllocationTermSyntax(terms), weight, bound)
    BY EveryFiniteSourceDerivationSuppliesTheAllocationInput, SMT DEF FiniteSupportedAllocationTerm

InitialCompilerAllocation(root, weight) ==
    [count |-> 1, position |-> 0,
     expressions |-> [index \in 1..1 |-> root],
     source |-> [index \in 1..0 |-> index],
     mass |-> [index \in 0..1 |-> IF index = 0 THEN 0 ELSE weight[root]]]

CompilerAllocationSourceNode(syntax, state) ==
    LET term == syntax[state.expressions[state.position + 1]]
    IN IF term.kind = "add"
       THEN [kind |-> "add", literal |-> 0, read |-> 0,
             left |-> state.count + 1, right |-> state.count + 2]
       ELSE term

ReviewedSwiftAllocationIteration(syntax, weight, state) ==
    LET term == syntax[state.expressions[state.position + 1]]
        isAdd == term.kind = "add"
        expressions == IF isAdd THEN
            HistoryAppend(HistoryAppend(state.expressions, state.count, term.left),
                          state.count + 1, term.right)
            ELSE state.expressions
        mass == IF isAdd THEN
            [index \in 0..(state.count + 2) |->
                IF index = state.count + 2 THEN
                    state.mass[state.count] + weight[term.left] + weight[term.right]
                ELSE IF index = state.count + 1 THEN
                    state.mass[state.count] + weight[term.left]
                ELSE state.mass[index]]
            ELSE state.mass
    IN [count |-> IF isAdd THEN state.count + 2 ELSE state.count,
        position |-> state.position + 1, expressions |-> expressions,
        source |-> HistoryAppend(state.source, state.position,
                                 CompilerAllocationSourceNode(syntax, state)),
        mass |-> mass]

THEOREM ReviewedAllocationIterationProjectsStoredFields ==
    ASSUME NEW syntax, NEW weight, NEW state
    PROVE /\ ReviewedSwiftAllocationIteration(syntax, weight, state).source =
                 HistoryAppend(state.source, state.position, CompilerAllocationSourceNode(syntax, state))
          /\ ReviewedSwiftAllocationIteration(syntax, weight, state).position = state.position + 1
          /\ ReviewedSwiftAllocationIteration(syntax, weight, state).count =
                 IF syntax[state.expressions[state.position + 1]].kind = "add" THEN state.count + 2 ELSE state.count
          /\ ReviewedSwiftAllocationIteration(syntax, weight, state).expressions =
                 IF syntax[state.expressions[state.position + 1]].kind = "add"
                 THEN HistoryAppend(HistoryAppend(state.expressions, state.count,
                          syntax[state.expressions[state.position + 1]].left),
                          state.count + 1, syntax[state.expressions[state.position + 1]].right)
                 ELSE state.expressions
    PROOF
    <1>source. ReviewedSwiftAllocationIteration(syntax, weight, state).source =
                   HistoryAppend(state.source, state.position, CompilerAllocationSourceNode(syntax, state))
        BY ONLY DEF ReviewedSwiftAllocationIteration
    <1>position. ReviewedSwiftAllocationIteration(syntax, weight, state).position = state.position + 1
        BY ONLY DEF ReviewedSwiftAllocationIteration
    <1>count. ReviewedSwiftAllocationIteration(syntax, weight, state).count =
                  IF syntax[state.expressions[state.position + 1]].kind = "add" THEN state.count + 2 ELSE state.count
        BY ONLY DEF ReviewedSwiftAllocationIteration
    <1>expressions. ReviewedSwiftAllocationIteration(syntax, weight, state).expressions =
        IF syntax[state.expressions[state.position + 1]].kind = "add"
        THEN HistoryAppend(HistoryAppend(state.expressions, state.count,
                 syntax[state.expressions[state.position + 1]].left),
                 state.count + 1, syntax[state.expressions[state.position + 1]].right)
        ELSE state.expressions
        BY ONLY DEF ReviewedSwiftAllocationIteration
    <1>. QED BY ONLY <1>source, <1>position, <1>count, <1>expressions

CompilerAllocatedPrefixShape(state) ==
    /\ \A node \in 1..state.position :
        /\ state.source[node].kind \in {"literal", "read", "add"}
        /\ (state.source[node].kind = "add" =>
              /\ state.source[node].left \in (node + 1)..state.count
              /\ state.source[node].right \in (node + 1)..state.count
              /\ state.source[node].left # state.source[node].right)
    /\ \A first, second \in 1..state.position :
        (state.source[first].kind = "add" /\ state.source[second].kind = "add" /\
          {state.source[first].left, state.source[first].right} \cap
          {state.source[second].left, state.source[second].right} # {}) => first = second
    /\ \A child \in 2..state.count : \E parent \in 1..state.position :
        /\ parent < child /\ state.source[parent].kind = "add"
        /\ child \in {state.source[parent].left, state.source[parent].right}

CompilerAllocatedPayloadsMatch(syntax, state) ==
    \A node \in 1..state.position :
        LET term == syntax[state.expressions[node]]
            actual == state.source[node]
        IN /\ actual.kind = term.kind
           /\ (term.kind = "literal" => actual.literal = term.literal)
           /\ (term.kind = "read" => actual.read = term.read)
           /\ (term.kind = "add" =>
                 /\ state.expressions[actual.left] = term.left
                 /\ state.expressions[actual.right] = term.right)

CompilerAllocationInvariant(root, terms, syntax, weight, bound, state) ==
    /\ state.position \in Nat /\ state.count \in Nat \ {0}
    /\ state.position <= state.count
    /\ state.expressions \in [1..state.count -> terms]
    /\ state.expressions[1] = root
    /\ DOMAIN state.source = 1..state.position
    /\ CompilerAllocatedPrefixShape(state)
    /\ CompilerAllocatedPayloadsMatch(syntax, state)
    /\ state.mass \in [0..state.count -> Nat]
    /\ state.mass[0] = 0
    /\ \A index \in 1..state.count :
          state.mass[index] = state.mass[index - 1] + weight[state.expressions[index]]
    /\ \A first, second \in 0..state.count : first <= second =>
          state.mass[second] - state.mass[first] >= second - first
    /\ state.mass[state.count] - state.mass[state.position] = weight[root] - state.position

THEOREM CompilerAllocationStartsWithItsLoopInvariant ==
    ASSUME NEW root, NEW terms, NEW syntax, NEW weight, NEW bound,
           SupportedAllocationInput(root, terms, syntax, weight, bound)
    PROVE CompilerAllocationInvariant(root, terms, syntax, weight, bound,
              InitialCompilerAllocation(root, weight))
    BY SMT DEF SupportedAllocationInput, CompilerAllocationInvariant,
        InitialCompilerAllocation, CompilerAllocatedPrefixShape, CompilerAllocatedPayloadsMatch

THEOREM CompilerAllocationPreservesOccurrenceOwnership ==
    ASSUME NEW root, NEW terms, NEW syntax, NEW weight, NEW bound,
           SupportedAllocationInput(root, terms, syntax, weight, bound),
           NEW state, CompilerAllocationInvariant(root, terms, syntax, weight, bound, state),
           state.position < state.count
    PROVE /\ CompilerAllocatedPrefixShape(ReviewedSwiftAllocationIteration(syntax, weight, state))
          /\ CompilerAllocatedPayloadsMatch(syntax, ReviewedSwiftAllocationIteration(syntax, weight, state))
    PROOF
    <1>. DEFINE next == ReviewedSwiftAllocationIteration(syntax, weight, state)
                term == syntax[state.expressions[state.position + 1]]
    <1>1. /\ state.position + 1 \in 1..state.count
          /\ state.expressions[state.position + 1] \in terms
          /\ term.kind \in {"literal", "read", "add"}
        BY SMT DEF CompilerAllocationInvariant, SupportedAllocationInput, term
    <1>2. \A node \in 1..state.position : next.source[node] = state.source[node]
        PROOF
        <2>1. /\ state.count \in Nat \ {0} /\ state.position \in Nat
            BY DEF CompilerAllocationInvariant
        <2>. QED BY <2>1, SMT DEF next, ReviewedSwiftAllocationIteration, HistoryAppend
    <1>3. \A node \in 1..state.count : next.expressions[node] = state.expressions[node]
        PROOF
        <2>1. /\ state.count \in Nat \ {0} /\ state.position \in Nat
            BY DEF CompilerAllocationInvariant
        <2>. QED BY <2>1, SMT DEF next, ReviewedSwiftAllocationIteration, HistoryAppend
    <1>4. CASE term.kind = "add"
        <2>1. /\ next.count = state.count + 2 /\ next.position = state.position + 1
              /\ next.source[next.position].kind = "add"
              /\ next.source[next.position].left = state.count + 1
              /\ next.source[next.position].right = state.count + 2
              /\ next.expressions[state.count + 1] = term.left
              /\ next.expressions[state.count + 2] = term.right
            PROOF
            <3>1. /\ state.count \in Nat \ {0} /\ state.position \in Nat
                BY DEF CompilerAllocationInvariant
            <3>. QED BY <3>1, <1>4, SMT DEF next, term,
                ReviewedSwiftAllocationIteration, CompilerAllocationSourceNode, HistoryAppend
        <2>2. \A node \in 1..state.position : state.source[node].kind = "add" =>
                  /\ state.source[node].left \in 1..state.count
                  /\ state.source[node].right \in 1..state.count
            BY SMT DEF CompilerAllocationInvariant, CompilerAllocatedPrefixShape
        <2>3. CompilerAllocatedPrefixShape(next)
            PROOF
            <3>base. /\ state.position \in Nat /\ state.count \in Nat \ {0}
                      /\ state.position < state.count /\ CompilerAllocatedPrefixShape(state)
                BY DEF CompilerAllocationInvariant
            <3>nodes. \A node \in 1..next.position :
                /\ next.source[node].kind \in {"literal", "read", "add"}
                /\ (next.source[node].kind = "add" =>
                      /\ next.source[node].left \in (node + 1)..next.count
                      /\ next.source[node].right \in (node + 1)..next.count
                      /\ next.source[node].left # next.source[node].right)
                BY ONLY <3>base, <1>2, <2>1, SMT DEF CompilerAllocatedPrefixShape
            <3>owners. \A first, second \in 1..next.position :
                (next.source[first].kind = "add" /\ next.source[second].kind = "add" /\
                  {next.source[first].left, next.source[first].right} \cap
                  {next.source[second].left, next.source[second].right} # {}) => first = second
                BY ONLY <3>base, <1>2, <2>1, <2>2, SMT DEF CompilerAllocatedPrefixShape
            <3>coverage. \A child \in 2..next.count : \E parent \in 1..next.position :
                /\ parent < child /\ next.source[parent].kind = "add"
                /\ child \in {next.source[parent].left, next.source[parent].right}
                PROOF
                <4>. SUFFICES ASSUME NEW child \in 2..next.count
                      PROVE \E parent \in 1..next.position :
                        /\ parent < child /\ next.source[parent].kind = "add"
                        /\ child \in {next.source[parent].left, next.source[parent].right}
                    OBVIOUS
                <4>old. CASE child <= state.count
                    <5>1. PICK parent \in 1..state.position :
                              /\ parent < child /\ state.source[parent].kind = "add"
                              /\ child \in {state.source[parent].left, state.source[parent].right}
                        PROOF
                        <6>1. child \in 2..state.count
                            BY <3>base, <2>1, <4>old, SMT
                        <6>. QED BY ONLY <6>1, <3>base, SMT DEF CompilerAllocatedPrefixShape
                    <5>. QED BY <3>base, <5>1, <1>2, <2>1, SMT
                <4>new. CASE child > state.count
                    BY <3>base, <2>1, <4>new, SMT
                <4>. QED BY <3>base, <2>1, <4>old, <4>new, SMT
            <3>. QED BY <3>nodes, <3>owners, <3>coverage DEF CompilerAllocatedPrefixShape
        <2>4. CompilerAllocatedPayloadsMatch(syntax, next)
            BY <1>2, <1>3, <1>4, <2>1, <2>2, SMT
                DEF CompilerAllocationInvariant, CompilerAllocatedPayloadsMatch, term
        <2>. QED BY <2>3, <2>4
    <1>5. CASE term.kind # "add"
        PROOF
        <2>base. /\ state.position \in Nat /\ state.count \in Nat \ {0}
                  /\ state.position < state.count
                  /\ CompilerAllocatedPrefixShape(state)
                  /\ CompilerAllocatedPayloadsMatch(syntax, state)
            BY DEF CompilerAllocationInvariant
        <2>projection. /\ next.count = state.count /\ next.position = state.position + 1
                        /\ next.expressions = state.expressions
                        /\ next.source[next.position] = term
                        /\ term.kind \in {"literal", "read"}
            BY <2>base, <1>1, <1>5, SMT DEF next, term,
                ReviewedSwiftAllocationIteration, CompilerAllocationSourceNode, HistoryAppend
        <2>. QED BY <2>base, <2>projection, <1>1, <1>2, <1>3, SMT
            DEF CompilerAllocatedPrefixShape, CompilerAllocatedPayloadsMatch, term
    <1>. QED BY <1>4, <1>5 DEF next

THEOREM CompilerAllocationPreservesMassAndMakesProgress ==
    ASSUME NEW root, NEW terms, NEW syntax, NEW weight, NEW bound,
           SupportedAllocationInput(root, terms, syntax, weight, bound),
           NEW state, CompilerAllocationInvariant(root, terms, syntax, weight, bound, state),
           state.position < state.count
    PROVE LET next == ReviewedSwiftAllocationIteration(syntax, weight, state)
          IN /\ CompilerAllocationInvariant(root, terms, syntax, weight, bound, next)
             /\ weight[root] - next.position = weight[root] - state.position - 1
    PROOF
    <1>. DEFINE next == ReviewedSwiftAllocationIteration(syntax, weight, state)
                term == syntax[state.expressions[state.position + 1]]
    <1>1. /\ state.position + 1 \in 1..state.count
          /\ state.expressions[state.position + 1] \in terms
          /\ term.kind \in {"literal", "read", "add"}
        BY SMT DEF CompilerAllocationInvariant, SupportedAllocationInput, term
    <1>2. /\ CompilerAllocatedPrefixShape(next)
          /\ CompilerAllocatedPayloadsMatch(syntax, next)
        BY CompilerAllocationPreservesOccurrenceOwnership DEF next
    <1>3. CASE term.kind = "add"
        <2>1. /\ term.left \in terms /\ term.right \in terms
              /\ weight[term.left] \in Nat \ {0} /\ weight[term.right] \in Nat \ {0}
              /\ weight[state.expressions[state.position + 1]] = 1 + weight[term.left] + weight[term.right]
            BY <1>1, <1>3, SMT DEF term, SupportedAllocationInput
        <2>2. /\ next.position = state.position + 1 /\ next.count = state.count + 2
              /\ next.mass[next.count] = state.mass[state.count] + weight[term.left] + weight[term.right]
              /\ next.mass[next.position] = state.mass[state.position] + weight[state.expressions[state.position + 1]]
            BY <1>1, <1>3, SMT DEF next, term, ReviewedSwiftAllocationIteration,
                CompilerAllocationInvariant
        <2>3. /\ next.mass \in [0..next.count -> Nat] /\ next.mass[0] = 0
              /\ \A index \in 1..next.count :
                    next.mass[index] = next.mass[index - 1] + weight[next.expressions[index]]
            PROOF
            <3>base. /\ state.count \in Nat \ {0}
                      /\ state.mass \in [0..state.count -> Nat] /\ state.mass[0] = 0
                      /\ \A index \in 1..state.count :
                            state.mass[index] = state.mass[index - 1] + weight[state.expressions[index]]
                BY DEF CompilerAllocationInvariant
            <3>projection. /\ next.count = state.count + 2
                /\ next.mass = [index \in 0..(state.count + 2) |->
                    IF index = state.count + 2
                    THEN state.mass[state.count] + weight[term.left] + weight[term.right]
                    ELSE IF index = state.count + 1
                         THEN state.mass[state.count] + weight[term.left]
                         ELSE state.mass[index]]
                /\ next.expressions =
                    HistoryAppend(HistoryAppend(state.expressions, state.count, term.left),
                                  state.count + 1, term.right)
                BY <1>3, <2>2, SMT DEF next, term, ReviewedSwiftAllocationIteration
            <3>types. /\ next.mass \in [0..next.count -> Nat] /\ next.mass[0] = 0
                BY ONLY <3>base, <3>projection, <2>1, SMT
            <3>recurrence. \A index \in 1..next.count :
                next.mass[index] = next.mass[index - 1] + weight[next.expressions[index]]
                BY ONLY <3>base, <3>projection, <2>1, SMT DEF HistoryAppend
            <3>. QED BY <3>types, <3>recurrence
        <2>4. \A first, second \in 0..next.count : first <= second =>
                    next.mass[second] - next.mass[first] >= second - first
            PROOF
            <3>base. /\ state.count \in Nat \ {0}
                      /\ state.mass \in [0..state.count -> Nat]
                      /\ \A first, second \in 0..state.count : first <= second =>
                            state.mass[second] - state.mass[first] >= second - first
                BY DEF CompilerAllocationInvariant
            <3>retained. \A index \in 0..state.count : next.mass[index] = state.mass[index]
                BY <3>base, <1>3, SMT DEF next, term, ReviewedSwiftAllocationIteration
            <3>boundary. /\ next.count = state.count + 2
                        /\ next.mass[state.count + 1] = state.mass[state.count] + weight[term.left]
                        /\ next.mass[state.count + 2] =
                              state.mass[state.count] + weight[term.left] + weight[term.right]
                BY <3>base, <1>3, <2>2, SMT DEF next, term, ReviewedSwiftAllocationIteration
            <3>. QED BY ONLY <3>base, <3>retained, <3>boundary, <2>1, SMT
        <2>base. /\ state.position \in Nat /\ state.count \in Nat \ {0}
                  /\ state.position < state.count
                  /\ state.expressions \in [1..state.count -> terms]
                  /\ state.expressions[1] = root
                  /\ state.mass \in [0..state.count -> Nat]
                  /\ weight[root] \in Nat \ {0}
                  /\ state.mass[state.count] - state.mass[state.position] = weight[root] - state.position
            BY DEF CompilerAllocationInvariant, SupportedAllocationInput
        <2>projection. /\ next.expressions =
                           HistoryAppend(HistoryAppend(state.expressions, state.count, term.left),
                                         state.count + 1, term.right)
                       /\ next.source = HistoryAppend(state.source, state.position,
                                                      CompilerAllocationSourceNode(syntax, state))
            BY <1>3, SMT DEF next, term, ReviewedSwiftAllocationIteration
        <2>arrays. /\ next.position \in Nat /\ next.count \in Nat \ {0}
                    /\ next.position <= next.count
                    /\ next.expressions \in [1..next.count -> terms]
                    /\ next.expressions[1] = root
                    /\ DOMAIN next.source = 1..next.position
            BY ONLY <2>base, <2>projection, <2>1, <2>2, SMT DEF HistoryAppend
        <2>mass. /\ next.mass[next.count] - next.mass[next.position] = weight[root] - next.position
                  /\ weight[root] - next.position = weight[root] - state.position - 1
            BY ONLY <2>base, <2>1, <2>2, SMT
        <2>. QED BY <1>2, <2>3, <2>4, <2>arrays, <2>mass DEF CompilerAllocationInvariant
    <1>4. CASE term.kind # "add"
        <2>1. weight[state.expressions[state.position + 1]] = 1
            BY <1>1, <1>4, SMT DEF term, SupportedAllocationInput
        <2>base. /\ state.position \in Nat /\ state.count \in Nat \ {0}
                  /\ state.position < state.count
                  /\ state.mass \in [0..state.count -> Nat]
                  /\ weight[root] \in Nat \ {0}
                  /\ \A index \in 1..state.count :
                        state.mass[index] = state.mass[index - 1] + weight[state.expressions[index]]
                  /\ state.mass[state.count] - state.mass[state.position] = weight[root] - state.position
            BY DEF CompilerAllocationInvariant, SupportedAllocationInput
        <2>projection. /\ next.count = state.count /\ next.position = state.position + 1
                       /\ next.expressions = state.expressions /\ next.mass = state.mass
                       /\ next.source = HistoryAppend(state.source, state.position,
                                                      CompilerAllocationSourceNode(syntax, state))
            BY <1>4, SMT DEF next, term, ReviewedSwiftAllocationIteration
        <2>mass. /\ next.mass[next.count] - next.mass[next.position] = weight[root] - next.position
                  /\ weight[root] - next.position = weight[root] - state.position - 1
            BY ONLY <2>base, <2>projection, <2>1, SMT
        <2>. QED BY <1>2, <2>base, <2>projection, <2>mass, SMT
            DEF CompilerAllocationInvariant, HistoryAppend
    <1>. QED BY <1>3, <1>4 DEF next

THEOREM CompilerAllocationFitsItsFiniteInputSize ==
    ASSUME NEW root, NEW terms, NEW syntax, NEW weight, NEW bound,
           SupportedAllocationInput(root, terms, syntax, weight, bound),
           NEW state, CompilerAllocationInvariant(root, terms, syntax, weight, bound, state)
    PROVE /\ state.count <= weight[root]
          /\ weight[root] - state.position \in Nat
          /\ (state.position = state.count <=> weight[root] - state.position = 0)
    PROOF
    <1>types. /\ state.position \in Nat /\ state.count \in Nat \ {0}
               /\ state.position <= state.count /\ weight[root] \in Nat \ {0}
               /\ state.mass[state.count] \in Nat /\ state.mass[state.position] \in Nat
        BY SMT DEF CompilerAllocationInvariant, SupportedAllocationInput
    <1>remaining. /\ state.mass[state.count] - state.mass[state.position] = weight[root] - state.position
                   /\ state.mass[state.count] - state.mass[state.position] >= state.count - state.position
        BY <1>types, SMT DEF CompilerAllocationInvariant
    <1>. QED BY ONLY <1>types, <1>remaining, SMT

AllocatedSourceView(state) ==
    [root |-> 1,
     kinds |-> [node \in 1..state.count |-> state.source[node].kind],
     literals |-> [node \in 1..state.count |->
         IF state.source[node].kind = "literal" THEN state.source[node].literal ELSE 0],
     reads |-> [node \in 1..state.count |->
         IF state.source[node].kind = "read" THEN state.source[node].read ELSE 0],
     left |-> [node \in 1..state.count |->
         IF state.source[node].kind = "add" THEN state.source[node].left ELSE 0],
     right |-> [node \in 1..state.count |->
         IF state.source[node].kind = "add" THEN state.source[node].right ELSE 0]]

THEOREM CompletedAllocationSuppliesOccurrenceTreeAndSource ==
    ASSUME NEW root, NEW terms, NEW syntax, NEW weight, NEW bound,
           SupportedAllocationInput(root, terms, syntax, weight, bound),
           NEW state, CompilerAllocationInvariant(root, terms, syntax, weight, bound, state),
           state.position = state.count
    PROVE LET view == AllocatedSourceView(state)
          IN /\ CompilerOccurrenceTree(view, state.count)
             /\ CertificateSource(view, bound)
             /\ state.count = weight[root]
             /\ state.expressions[1] = root
             /\ CompilerAllocatedPayloadsMatch(syntax, state)
    PROOF
    <1>1. CompilerOccurrenceTree(AllocatedSourceView(state), state.count)
        PROOF
        <2>base. /\ state.count \in Nat \ {0} /\ state.position = state.count
                  /\ CompilerAllocatedPrefixShape(state)
            BY DEF CompilerAllocationInvariant
        <2>view. LET view == AllocatedSourceView(state)
                  IN /\ view.root = 1 /\ DOMAIN view.kinds = 1..state.count
                     /\ \A node \in 1..state.count :
                           /\ view.kinds[node] = state.source[node].kind
                           /\ (state.source[node].kind = "add" =>
                                 /\ view.left[node] = state.source[node].left
                                 /\ view.right[node] = state.source[node].right)
            BY ONLY <2>base, SMT DEF AllocatedSourceView
        <2>. QED BY ONLY <2>base, <2>view, SMT
            DEF CompilerOccurrenceTree, CompilerAllocatedPrefixShape
    <1>2. CertificateSource(AllocatedSourceView(state), bound)
        PROOF
        <2>base. /\ state.count \in Nat \ {0} /\ state.position = state.count
                  /\ state.expressions \in [1..state.count -> terms]
                  /\ bound \subseteq Keys /\ CompilerAllocatedPayloadsMatch(syntax, state)
            BY DEF CompilerAllocationInvariant, SupportedAllocationInput
        <2>inputs. \A term \in terms :
            /\ (syntax[term].kind = "literal" => InRange(syntax[term].literal))
            /\ (syntax[term].kind = "read" => syntax[term].read \in bound)
            BY DEF SupportedAllocationInput
        <2>view. LET view == AllocatedSourceView(state)
                  IN \A node \in 1..state.count :
                       /\ view.kinds[node] = state.source[node].kind
                       /\ (state.source[node].kind = "literal" =>
                             view.literals[node] = state.source[node].literal)
                       /\ (state.source[node].kind = "read" =>
                             view.reads[node] = state.source[node].read)
            BY ONLY <2>base, SMT DEF AllocatedSourceView
        <2>payloads. LET view == AllocatedSourceView(state)
                      IN \A node \in 1..state.count :
                           /\ (view.kinds[node] = "literal" => InRange(view.literals[node]))
                           /\ (view.kinds[node] = "read" => view.reads[node] \in bound)
            BY ONLY <2>base, <2>inputs, <2>view, SMT DEF CompilerAllocatedPayloadsMatch
        <2>. QED BY ONLY <2>base, <2>payloads, <1>1, SMT
            DEF CertificateSource, CompilerOccurrenceTree
    <1>3. state.count = weight[root]
        PROOF
        <2>zero. weight[root] - state.position = 0
            BY CompilerAllocationFitsItsFiniteInputSize, SMT
        <2>types. /\ state.count \in Nat \ {0} /\ weight[root] \in Nat \ {0}
            BY DEF CompilerAllocationInvariant, SupportedAllocationInput
        <2>. QED BY <2>zero, <2>types, SMT
    <1>. QED BY <1>1, <1>2, <1>3 DEF CompilerAllocationInvariant

CompilerAllocationCompletion(syntax, weight, initial, steps, history) ==
    /\ steps \in Nat /\ history[0] = initial
    /\ \A step \in 1..steps :
          /\ history[step - 1].position < history[step - 1].count
          /\ history[step] = ReviewedSwiftAllocationIteration(syntax, weight, history[step - 1])
    /\ history[steps].position = history[steps].count

THEOREM FiniteSupportedInputConstructsATerminatingAllocation ==
    ASSUME NEW root, NEW terms, NEW syntax, NEW weight, NEW bound,
           SupportedAllocationInput(root, terms, syntax, weight, bound),
           NEW initial, CompilerAllocationInvariant(root, terms, syntax, weight, bound, initial)
    PROVE \E steps, history :
              /\ CompilerAllocationCompletion(syntax, weight, initial, steps, history)
              /\ CompilerAllocationInvariant(root, terms, syntax, weight, bound, history[steps])
    PROOF
    <1>. DEFINE completes(fuel) == \A state :
        (CompilerAllocationInvariant(root, terms, syntax, weight, bound, state) /\
         weight[root] - state.position = fuel) =>
        \E steps, history :
            /\ CompilerAllocationCompletion(syntax, weight, state, steps, history)
            /\ CompilerAllocationInvariant(root, terms, syntax, weight, bound, history[steps])
    <1>1. completes(0)
        <2>. SUFFICES ASSUME NEW state,
                 CompilerAllocationInvariant(root, terms, syntax, weight, bound, state),
                 weight[root] - state.position = 0
              PROVE \E steps, history :
                /\ CompilerAllocationCompletion(syntax, weight, state, steps, history)
                /\ CompilerAllocationInvariant(root, terms, syntax, weight, bound, history[steps])
            BY SMT DEF completes
        <2>1. state.position = state.count
            BY CompilerAllocationFitsItsFiniteInputSize, SMT
        <2>2. CompilerAllocationCompletion(syntax, weight, state, 0, [step \in 0..0 |-> state])
            BY <2>1, SMT DEF CompilerAllocationCompletion
        <2>. QED BY <2>2, SMT
    <1>2. ASSUME NEW fuel \in Nat, completes(fuel)
          PROVE completes(fuel + 1)
        <2>. SUFFICES ASSUME NEW state,
                 CompilerAllocationInvariant(root, terms, syntax, weight, bound, state),
                 weight[root] - state.position = fuel + 1
              PROVE \E steps, history :
                /\ CompilerAllocationCompletion(syntax, weight, state, steps, history)
                /\ CompilerAllocationInvariant(root, terms, syntax, weight, bound, history[steps])
            BY SMT DEF completes
        <2>. DEFINE next == ReviewedSwiftAllocationIteration(syntax, weight, state)
        <2>1. state.position < state.count
            BY CompilerAllocationFitsItsFiniteInputSize, SMT DEF CompilerAllocationInvariant
        <2>2. /\ CompilerAllocationInvariant(root, terms, syntax, weight, bound, next)
              /\ weight[root] - next.position = fuel
            BY <2>1, CompilerAllocationPreservesMassAndMakesProgress, SMT DEF next
        <2>3. PICK steps, history :
                /\ CompilerAllocationCompletion(syntax, weight, next, steps, history)
                /\ CompilerAllocationInvariant(root, terms, syntax, weight, bound, history[steps])
            BY <2>2, completes(fuel), SMT DEF completes
        <2>. DEFINE extended == [step \in 0..(steps + 1) |->
                     IF step = 0 THEN state ELSE history[step - 1]]
        <2>4. /\ extended[0] = state /\ extended[1] = next
              /\ extended[steps + 1] = history[steps]
            BY <2>3, SMT DEF extended, CompilerAllocationCompletion
        <2>5. CompilerAllocationCompletion(syntax, weight, state, steps + 1, extended)
            BY <2>1, <2>3, <2>4, SMT DEF extended, CompilerAllocationCompletion, next
        <2>. QED BY <2>3, <2>4, <2>5, SMT
    <1>3. \A fuel \in Nat : completes(fuel)
        BY <1>1, <1>2, NatInduction
    <1>4. weight[root] - initial.position \in Nat
        BY CompilerAllocationFitsItsFiniteInputSize
    <1>. QED BY <1>3, <1>4, SMT DEF completes

CompilerAllocationArrayOperationsFit(syntax, state) ==
    /\ state.position \in Nat /\ state.count \in Nat \ {0}
    /\ state.position < state.count /\ state.count <= SwiftIntMax
    /\ state.position < SwiftIntMax /\ state.position + 1 <= SwiftIntMax
    /\ (syntax[state.expressions[state.position + 1]].kind = "add" =>
          /\ state.count < SwiftIntMax /\ state.count + 1 < SwiftIntMax
          /\ state.count + 2 <= SwiftIntMax)

THEOREM SupportedAllocationIterationFitsSwiftArrayOperations ==
    ASSUME NEW root, NEW terms, NEW syntax, NEW weight, NEW bound,
           SupportedAllocationInput(root, terms, syntax, weight, bound),
           weight[root] <= SwiftIntMax,
           NEW state, CompilerAllocationInvariant(root, terms, syntax, weight, bound, state),
           state.position < state.count
    PROVE CompilerAllocationArrayOperationsFit(syntax, state)
    PROOF
    <1>. DEFINE next == ReviewedSwiftAllocationIteration(syntax, weight, state)
    <1>types. /\ state.position \in Nat /\ state.count \in Nat \ {0}
               /\ weight[root] \in Nat \ {0} /\ SwiftIntMax \in Int
        BY IntegerDomain, SMT DEF CompilerAllocationInvariant, SupportedAllocationInput, IntegerDomain
    <1>next. CompilerAllocationInvariant(root, terms, syntax, weight, bound, next)
        BY CompilerAllocationPreservesMassAndMakesProgress DEF next
    <1>bounds. /\ state.count <= weight[root] /\ next.count <= weight[root]
        BY <1>next, CompilerAllocationFitsItsFiniteInputSize, SMT
    <1>addCount. syntax[state.expressions[state.position + 1]].kind = "add" =>
                    next.count = state.count + 2
        BY SMT DEF next, ReviewedSwiftAllocationIteration
    <1>. QED BY <1>types, <1>bounds, <1>addCount, SMT DEF CompilerAllocationArrayOperationsFit

THEOREM AllocationCompletionRetainsEveryLoopInvariant ==
    ASSUME NEW root, NEW terms, NEW syntax, NEW weight, NEW bound,
           SupportedAllocationInput(root, terms, syntax, weight, bound),
           NEW initial, CompilerAllocationInvariant(root, terms, syntax, weight, bound, initial),
           NEW steps, NEW history, CompilerAllocationCompletion(syntax, weight, initial, steps, history)
    PROVE \A step \in 0..steps :
              CompilerAllocationInvariant(root, terms, syntax, weight, bound, history[step])
    PROOF
    <1>. DEFINE holds(step) == CompilerAllocationInvariant(root, terms, syntax, weight, bound, history[step])
    <1>count. steps \in Nat BY DEF CompilerAllocationCompletion
    <1>1. holds(0) BY SMT DEF holds, CompilerAllocationCompletion
    <1>2. ASSUME NEW step \in 1..steps,
                 \A earlier \in 0..(step - 1) : holds(earlier)
          PROVE holds(step)
        <2>prior. CompilerAllocationInvariant(root, terms, syntax, weight, bound, history[step - 1])
            PROOF
            <3>index. step - 1 \in 0..(step - 1)
                BY <1>count, SMT
            <3>ih. holds(step - 1)
                BY ONLY <3>index, (\A earlier \in 0..(step - 1) : holds(earlier)), SMT
            <3>. QED BY <3>ih DEF holds
        <2>advance. /\ history[step - 1].position < history[step - 1].count
                     /\ history[step] = ReviewedSwiftAllocationIteration(syntax, weight, history[step - 1])
            BY DEF CompilerAllocationCompletion
        <2>. QED BY <2>prior, <2>advance, CompilerAllocationPreservesMassAndMakesProgress, SMT DEF holds
    <1>3. \A step \in 0..steps : holds(step)
        BY <1>count, <1>1, <1>2, FiniteIndexedPrefixProperty
    <1>. QED BY <1>3 DEF holds

\* Consumer: replace the supplied occurrence-tree premise by the actual loop
\* invariant and its derived completion, then invoke the existing traversal parent.
THEOREM ActualAllocationConstructsTheTraversalSource ==
    ASSUME NEW root, NEW terms, NEW syntax, NEW weight, NEW bound,
           SupportedAllocationInput(root, terms, syntax, weight, bound)
    PROVE \E steps, history :
        /\ CompilerAllocationCompletion(syntax, weight,
               InitialCompilerAllocation(root, weight), steps, history)
        /\ CompilerOccurrenceTree(AllocatedSourceView(history[steps]), history[steps].count)
        /\ CertificateSource(AllocatedSourceView(history[steps]), bound)
        /\ history[steps].count = weight[root]
        /\ history[steps].expressions[1] = root
        /\ CompilerAllocatedPayloadsMatch(syntax, history[steps])
        /\ (weight[root] <= SwiftIntMax =>
              \A step \in 0..(steps - 1) : CompilerAllocationArrayOperationsFit(syntax, history[step]))
    PROOF
    <1>1. CompilerAllocationInvariant(root, terms, syntax, weight, bound,
              InitialCompilerAllocation(root, weight))
        BY CompilerAllocationStartsWithItsLoopInvariant
    <1>2. PICK steps, history :
              /\ CompilerAllocationCompletion(syntax, weight,
                     InitialCompilerAllocation(root, weight), steps, history)
              /\ CompilerAllocationInvariant(root, terms, syntax, weight, bound, history[steps])
        BY <1>1, FiniteSupportedInputConstructsATerminatingAllocation
    <1>3. /\ CompilerOccurrenceTree(AllocatedSourceView(history[steps]), history[steps].count)
          /\ CertificateSource(AllocatedSourceView(history[steps]), bound)
          /\ history[steps].count = weight[root]
          /\ history[steps].expressions[1] = root
          /\ CompilerAllocatedPayloadsMatch(syntax, history[steps])
        BY <1>2, CompletedAllocationSuppliesOccurrenceTreeAndSource DEF CompilerAllocationCompletion
    <1>4. \A step \in 0..steps :
              CompilerAllocationInvariant(root, terms, syntax, weight, bound, history[step])
        BY <1>1, <1>2, AllocationCompletionRetainsEveryLoopInvariant
    <1>5. weight[root] <= SwiftIntMax =>
              \A step \in 0..(steps - 1) : CompilerAllocationArrayOperationsFit(syntax, history[step])
        PROOF
        <2>. SUFFICES ASSUME weight[root] <= SwiftIntMax, NEW step \in 0..(steps - 1)
              PROVE CompilerAllocationArrayOperationsFit(syntax, history[step])
            BY SMT
        <2>index. /\ step \in 0..steps /\ step + 1 \in 1..steps
            BY <1>2, SMT DEF CompilerAllocationCompletion
        <2>invariant. CompilerAllocationInvariant(root, terms, syntax, weight, bound, history[step])
            BY <1>4, <2>index, SMT
        <2>guard. history[step].position < history[step].count
            BY <1>2, <2>index, SMT DEF CompilerAllocationCompletion
        <2>. QED BY <2>invariant, <2>guard, SupportedAllocationIterationFitsSwiftArrayOperations
    <1>. QED BY <1>2, <1>3, <1>5, SMT


CompilerScheduledOccurrences(view, opened) ==
    {view.root} \cup {view.left[node] : node \in opened} \cup {view.right[node] : node \in opened}
CompilerPendingTasks(height, pending) ==
    {<<pending[position].node, pending[position].expanded>> : position \in 1..height}
CompilerExpectedTasks(view, opened, done) ==
    {<<node, FALSE>> : node \in CompilerScheduledOccurrences(view, opened) \ (opened \cup done)}
    \cup {<<node, TRUE>> : node \in opened \ done}
CompilerOccurrenceStages(view, height, pending, opened, done) ==
    /\ height \in Nat
    /\ opened \subseteq {node \in DOMAIN view.kinds : view.kinds[node] = "add"}
    /\ opened \subseteq CompilerScheduledOccurrences(view, opened)
    /\ done \subseteq CompilerScheduledOccurrences(view, opened)
    /\ \A node \in done : view.kinds[node] = "add" => node \in opened
    /\ CompilerPendingTasks(height, pending) = CompilerExpectedTasks(view, opened, done)
    /\ \A first, second \in 1..height :
        (pending[first].node = pending[second].node /\
         pending[first].expanded = pending[second].expanded) => first = second

THEOREM SourceRootStartsTheOccurrenceStages ==
    ASSUME NEW view
    PROVE CompilerOccurrenceStages(view, 1,
              <<VisitFrame(view.root, FALSE, EmptyVisitPrefix)>>, {}, {})
    BY SMT DEF CompilerOccurrenceStages, CompilerPendingTasks, CompilerExpectedTasks,
        CompilerScheduledOccurrences, VisitFrame

THEOREM AnUnexpandedCompilerParentSchedulesFreshOccurrences ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW opened \in SUBSET {node \in DOMAIN view.kinds : view.kinds[node] = "add"},
           NEW origin \in DOMAIN view.kinds,
           view.kinds[origin] = "add", origin \notin opened
    PROVE /\ view.left[origin] \notin CompilerScheduledOccurrences(view, opened)
          /\ view.right[origin] \notin CompilerScheduledOccurrences(view, opened)
          /\ view.left[origin] # view.right[origin]
    PROOF
    <1>1. /\ view.left[origin] \in (origin + 1)..count
          /\ view.right[origin] \in (origin + 1)..count
          /\ view.left[origin] # view.right[origin]
          /\ origin \in 1..count /\ view.root = 1
        BY SMT DEF CompilerOccurrenceTree
    <1>2. \A prior \in opened :
              /\ view.left[origin] \notin {view.left[prior], view.right[prior]}
              /\ view.right[origin] \notin {view.left[prior], view.right[prior]}
        BY SMT DEF CompilerOccurrenceTree
    <1>. QED BY <1>1, <1>2, SMT DEF CompilerScheduledOccurrences

THEOREM PendingCompilerFramesHaveFreshEmissionOrigins ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW height, NEW pending, NEW opened, NEW done,
           CompilerOccurrenceStages(view, height, pending, opened, done), height > 0,
           NEW current, CertificateConstructionInvariant(view, current),
           \A node \in DOMAIN view.kinds : (current.inverse[node] > 0) \equiv (node \in done)
    PROVE /\ pending[height].node \in DOMAIN view.kinds
          /\ pending[height].expanded \in BOOLEAN
          /\ current.inverse[pending[height].node] = 0
          /\ (pending[height].expanded => view.kinds[pending[height].node] = "add")
          /\ (~pending[height].expanded => pending[height].node \notin opened)
    PROOF
    <1>1. CompilerScheduledOccurrences(view, opened) \subseteq DOMAIN view.kinds
        BY SMT DEF CompilerOccurrenceTree, CompilerOccurrenceStages, CompilerScheduledOccurrences
    <1>2. <<pending[height].node, pending[height].expanded>> \in CompilerExpectedTasks(view, opened, done)
        BY SMT DEF CompilerOccurrenceStages, CompilerPendingTasks
    <1>3. /\ pending[height].node \in DOMAIN view.kinds
          /\ pending[height].node \notin done
          /\ pending[height].expanded \in BOOLEAN
          /\ (pending[height].expanded => pending[height].node \in opened)
          /\ (~pending[height].expanded => pending[height].node \notin opened)
        BY <1>1, <1>2, SMT DEF CompilerExpectedTasks, CompilerOccurrenceStages
    <1>. QED BY <1>3, SMT DEF CertificateConstructionInvariant, CompilerOccurrenceStages

THEOREM CompilerOccurrenceStagesDeriveEmissionReadiness ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW before, NEW height, NEW pending, NEW completed, NEW goal,
           NEW opened, NEW done,
           CompilerOccurrenceStages(view, height, pending, opened, done),
           PendingVisitContract(height, pending, completed, goal, view.left, view.right),
           CompletedCertificateRoots(view, before, completed),
           CertificateConstructionInvariant(view, before), height > 0,
           \A node \in DOMAIN view.kinds : (before.inverse[node] > 0) \equiv (node \in done),
           pending[height].expanded \/ view.kinds[pending[height].node] # "add"
    PROVE /\ CertificateConstructorReady(view, before, pending[height].node)
          /\ CertificateConstructionInvariant(view,
                 AppendCertificateConstructor(view, before, pending[height].node))
    PROOF
    <1>1. /\ pending[height].node \in DOMAIN view.kinds
          /\ pending[height].expanded \in BOOLEAN
          /\ before.inverse[pending[height].node] = 0
          /\ (pending[height].expanded => view.kinds[pending[height].node] = "add")
          /\ (~pending[height].expanded => pending[height].node \notin opened)
        BY PendingCompilerFramesHaveFreshEmissionOrigins
    <1>2. (pending[height].expanded /\ view.kinds[pending[height].node] = "add")
            \/ (~pending[height].expanded /\ view.kinds[pending[height].node] \in {"literal", "read"})
        BY <1>1, SMT DEF CompilerOccurrenceTree
    <1>3. /\ CertificateConstructorReady(view, before, pending[height].node)
          /\ (CertificateConstructionInvariant(view, before) =>
                CertificateConstructionInvariant(view,
                    AppendCertificateConstructor(view, before, pending[height].node)))
        BY <1>1, <1>2, PendingCompilerEmissionDerivesConstructorReadiness
    <1>. QED BY <1>3


THEOREM PoppingAUniqueCompilerTaskRemovesOnlyThatTask ==
    ASSUME NEW height \in Nat \ {0}, NEW pending,
           \A first, second \in 1..height :
               (pending[first].node = pending[second].node /\
                pending[first].expanded = pending[second].expanded) => first = second
    PROVE CompilerPendingTasks(height - 1, HistoryPrefix(pending, height - 1)) =
              CompilerPendingTasks(height, pending) \ {<<pending[height].node, pending[height].expanded>>}
    PROOF
    <1>1. \A position \in 1..(height - 1) :
              <<pending[position].node, pending[position].expanded>> #
                  <<pending[height].node, pending[height].expanded>>
        BY SMT
    <1>. QED BY <1>1, SMT DEF CompilerPendingTasks, HistoryPrefix

THEOREM ExpandingACompilerParentPreservesOccurrenceStages ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW height, NEW pending, NEW opened, NEW done,
           CompilerOccurrenceStages(view, height, pending, opened, done),
           height > 0, ~pending[height].expanded, view.kinds[pending[height].node] = "add"
    PROVE CompilerOccurrenceStages(view, height + 2,
              ReplaceTopVisitFrame(pending, height,
                  ExpandedVisitFrames(pending[height], view.left, view.right)),
              opened \cup {pending[height].node}, done)
    PROOF
    <1>. DEFINE origin == pending[height].node
                left == view.left[origin]
                right == view.right[origin]
                next == ReplaceTopVisitFrame(pending, height,
                    ExpandedVisitFrames(pending[height], view.left, view.right))
                scheduled == CompilerScheduledOccurrences(view, opened)
    <1>1. /\ origin \in scheduled /\ origin \notin opened /\ origin \notin done
          /\ origin \in DOMAIN view.kinds /\ height \in Nat
          /\ scheduled \subseteq DOMAIN view.kinds
          /\ opened \subseteq scheduled /\ done \subseteq scheduled
        PROOF
        <2>1. /\ scheduled \subseteq DOMAIN view.kinds
              /\ opened \subseteq scheduled /\ done \subseteq scheduled /\ height \in Nat
            BY SMT DEF scheduled, CompilerOccurrenceTree, CompilerOccurrenceStages, CompilerScheduledOccurrences
        <2>2. <<origin, pending[height].expanded>> \in CompilerExpectedTasks(view, opened, done)
            BY SMT DEF origin, CompilerOccurrenceStages, CompilerPendingTasks
        <2>3. /\ origin \in scheduled /\ origin \notin opened /\ origin \notin done
            BY <2>2, SMT DEF CompilerExpectedTasks, scheduled
        <2>. QED BY ONLY <2>1, <2>3, SMT
    <1>2. /\ left \notin scheduled /\ right \notin scheduled /\ left # right
        BY <1>1, AnUnexpandedCompilerParentSchedulesFreshOccurrences, SMT
            DEF left, right, scheduled, CompilerOccurrenceStages, origin
    <1>3. /\ \A position \in 1..(height - 1) : next[position] = pending[position]
          /\ next[height].node = origin /\ next[height].expanded = TRUE
          /\ next[height + 1].node = right /\ next[height + 1].expanded = FALSE
          /\ next[height + 2].node = left /\ next[height + 2].expanded = FALSE
        BY <1>1, SMT DEF next, left, right, origin, ReplaceTopVisitFrame, ExpandedVisitFrames, VisitFrame
    <1>4. CompilerPendingTasks(height - 1, HistoryPrefix(pending, height - 1)) =
              CompilerPendingTasks(height, pending) \ {<<origin, FALSE>>}
        PROOF
        <2>1. /\ height \in Nat \ {0}
              /\ \A first, second \in 1..height :
                  (pending[first].node = pending[second].node /\
                   pending[first].expanded = pending[second].expanded) => first = second
            BY SMT DEF CompilerOccurrenceStages
        <2>2. CompilerPendingTasks(height - 1, HistoryPrefix(pending, height - 1)) =
                  CompilerPendingTasks(height, pending) \ {<<pending[height].node, pending[height].expanded>>}
            BY <2>1, PoppingAUniqueCompilerTaskRemovesOnlyThatTask
        <2>3. <<origin, pending[height].expanded>> \in CompilerExpectedTasks(view, opened, done)
            BY SMT DEF origin, CompilerOccurrenceStages, CompilerPendingTasks
        <2>4. pending[height].expanded = FALSE
            BY <2>3, SMT DEF CompilerExpectedTasks
        <2>. QED BY ONLY <2>2, <2>4 DEF origin
    <1>5. CompilerPendingTasks(height + 2, next) =
              (CompilerPendingTasks(height, pending) \ {<<origin, FALSE>>})
                  \cup {<<origin, TRUE>>, <<right, FALSE>>, <<left, FALSE>>}
        PROOF
        <2>. DEFINE rest == CompilerPendingTasks(height - 1, HistoryPrefix(pending, height - 1))
                    added == {<<origin, TRUE>>, <<right, FALSE>>, <<left, FALSE>>}
        <2>1. CompilerPendingTasks(height + 2, next) \subseteq rest \cup added
            PROOF
            <3>. SUFFICES ASSUME NEW task \in CompilerPendingTasks(height + 2, next)
                         PROVE task \in rest \cup added
                BY SMT
            <3>1. PICK position \in 1..(height + 2) :
                      task = <<next[position].node, next[position].expanded>>
                BY DEF CompilerPendingTasks
            <3>2. position < height => task \in rest
                BY ONLY <1>1, <1>3, <3>1, SMT DEF rest, CompilerPendingTasks, HistoryPrefix
            <3>3. position >= height => task \in added
                BY ONLY <1>1, <1>3, <3>1, SMT DEF added
            <3>. QED BY ONLY <1>1, <3>1, <3>2, <3>3, SMT
        <2>2. rest \subseteq CompilerPendingTasks(height + 2, next)
            PROOF
            <3>. SUFFICES ASSUME NEW task \in rest
                         PROVE task \in CompilerPendingTasks(height + 2, next)
                BY SMT
            <3>1. PICK position \in 1..(height - 1) :
                      task = <<pending[position].node, pending[position].expanded>>
                BY SMT DEF rest, CompilerPendingTasks, HistoryPrefix
            <3>. QED BY ONLY <1>1, <1>3, <3>1, SMT DEF CompilerPendingTasks
        <2>3. added \subseteq CompilerPendingTasks(height + 2, next)
            PROOF
            <3>1. height \in 1..(height + 2) /\ height + 1 \in 1..(height + 2)
                  /\ height + 2 \in 1..(height + 2)
                BY <1>1, SMT
            <3>2. \A position \in 1..(height + 2) :
                      <<next[position].node, next[position].expanded>> \in CompilerPendingTasks(height + 2, next)
                BY SMT DEF CompilerPendingTasks
            <3>. QED BY ONLY <1>3, <3>1, <3>2, SMT DEF added
        <2>. QED BY ONLY <1>4, <2>1, <2>2, <2>3, SMT DEF rest, added
    <1>6. CompilerScheduledOccurrences(view, opened \cup {origin}) = scheduled \cup {left, right}
        BY SMT DEF CompilerScheduledOccurrences, scheduled, left, right
    <1>7. CompilerExpectedTasks(view, opened \cup {origin}, done) =
              (CompilerExpectedTasks(view, opened, done) \ {<<origin, FALSE>>})
                  \cup {<<origin, TRUE>>, <<right, FALSE>>, <<left, FALSE>>}
        BY ONLY <1>1, <1>2, <1>6, SMT DEF CompilerExpectedTasks, scheduled
    <1>8. \A position \in 1..height :
              /\ pending[position].node \in scheduled
              /\ (pending[position].expanded => pending[position].node \in opened)
        PROOF
        <2>. SUFFICES ASSUME NEW position \in 1..height
                     PROVE /\ pending[position].node \in scheduled
                           /\ (pending[position].expanded => pending[position].node \in opened)
            BY SMT
        <2>1. <<pending[position].node, pending[position].expanded>> \in CompilerExpectedTasks(view, opened, done)
            BY SMT DEF CompilerOccurrenceStages, CompilerPendingTasks
        <2>. QED BY ONLY <1>1, <2>1, SMT DEF CompilerExpectedTasks, scheduled
    <1>9. \A first, second \in 1..(height + 2) :
              (next[first].node = next[second].node /\ next[first].expanded = next[second].expanded)
                  => first = second
        BY <1>1, <1>2, <1>3, <1>8, SMT DEF CompilerOccurrenceStages
    <1>. QED BY <1>1, <1>5, <1>6, <1>7, <1>9, SMT
        DEF CompilerOccurrenceStages, next, origin

THEOREM EmittingACompilerNodePreservesOccurrenceStages ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW height, NEW pending, NEW opened, NEW done,
           CompilerOccurrenceStages(view, height, pending, opened, done), height > 0,
           pending[height].expanded \/ view.kinds[pending[height].node] # "add"
    PROVE CompilerOccurrenceStages(view, height - 1, HistoryPrefix(pending, height - 1),
              opened, done \cup {pending[height].node})
    PROOF
    <1>. DEFINE origin == pending[height].node
                task == <<origin, pending[height].expanded>>
    <1>1. /\ origin \in CompilerScheduledOccurrences(view, opened) /\ origin \notin done
          /\ pending[height].expanded \in BOOLEAN /\ height \in Nat
          /\ (pending[height].expanded => origin \in opened)
          /\ (~pending[height].expanded => origin \notin opened)
          /\ (view.kinds[origin] = "add" => origin \in opened)
        PROOF
        <2>1. /\ height \in Nat
              /\ opened \subseteq CompilerScheduledOccurrences(view, opened)
            BY DEF CompilerOccurrenceStages
        <2>2. <<origin, pending[height].expanded>> \in CompilerExpectedTasks(view, opened, done)
            BY SMT DEF origin, CompilerOccurrenceStages, CompilerPendingTasks
        <2>3. /\ origin \in CompilerScheduledOccurrences(view, opened) /\ origin \notin done
              /\ pending[height].expanded \in BOOLEAN
              /\ (pending[height].expanded => origin \in opened)
              /\ (~pending[height].expanded => origin \notin opened)
            BY ONLY <2>1, <2>2, SMT DEF CompilerExpectedTasks
        <2>. QED BY <2>1, <2>3, SMT DEF origin
    <1>2. CompilerPendingTasks(height - 1, HistoryPrefix(pending, height - 1)) =
              CompilerPendingTasks(height, pending) \ {task}
        BY <1>1, PoppingAUniqueCompilerTaskRemovesOnlyThatTask, SMT
            DEF CompilerOccurrenceStages, task, origin
    <1>3. CompilerExpectedTasks(view, opened, done \cup {origin}) =
              CompilerExpectedTasks(view, opened, done) \ {task}
        BY <1>1, SMT DEF CompilerExpectedTasks, task
    <1>. QED BY <1>1, <1>2, <1>3, SMT DEF CompilerOccurrenceStages, HistoryPrefix, origin


THEOREM EmptyCompilerPendingStackHasEmittedEveryOccurrence ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW pending, NEW opened, NEW done,
           CompilerOccurrenceStages(view, 0, pending, opened, done)
    PROVE done = DOMAIN view.kinds
    PROOF
    <1>1. CompilerExpectedTasks(view, opened, done) = {}
        BY SMT DEF CompilerOccurrenceStages, CompilerPendingTasks
    <1>2. /\ opened \subseteq done
          /\ CompilerScheduledOccurrences(view, opened) \subseteq done
        BY <1>1, SMT DEF CompilerExpectedTasks
    <1>3. /\ count \in Nat /\ view.root = 1 /\ DOMAIN view.kinds = 1..count
          /\ done \subseteq DOMAIN view.kinds
          /\ view.root \in done
        BY <1>2, SMT DEF CompilerOccurrenceTree, CompilerOccurrenceStages, CompilerScheduledOccurrences
    <1>. DEFINE reached(index) == index \in 1..count => index \in done
    <1>4. reached(0) BY SMT DEF reached
    <1>5. \A index \in 1..count :
              (\A prior \in 0..(index - 1) : reached(prior)) => reached(index)
        PROOF
        <2>. SUFFICES ASSUME NEW index \in 1..count,
                             \A prior \in 0..(index - 1) : reached(prior)
                     PROVE reached(index)
            BY SMT
        <2>1. CASE index = 1
            BY <1>3, <2>1, SMT DEF reached
        <2>2. CASE index # 1
            PROOF
            <3>1. PICK parent \in 1..(index - 1) :
                      view.kinds[parent] = "add" /\ index \in {view.left[parent], view.right[parent]}
                BY <2>2, SMT DEF CompilerOccurrenceTree
            <3>2. parent \in done
                BY <1>3, <3>1, SMT DEF reached
            <3>3. parent \in opened
                BY <3>1, <3>2, SMT DEF CompilerOccurrenceStages
            <3>4. index \in CompilerScheduledOccurrences(view, opened)
                BY <3>1, <3>3, SMT DEF CompilerScheduledOccurrences
            <3>. QED BY <1>2, <3>4, SMT DEF reached
        <2>. QED BY <2>1, <2>2
    <1>6. HIDE DEF reached
    <1>7. \A index \in 0..count : reached(index)
        BY <1>3, <1>4, <1>5, FiniteIndexedPrefixProperty
    <1>. QED BY <1>3, <1>7, SMT DEF reached

CompilerRemainingTasks(view, opened, done) ==
    {<<node, FALSE>> : node \in (DOMAIN view.kinds) \ (opened \cup done)}
    \cup {<<node, TRUE>> : node \in {node \in DOMAIN view.kinds : view.kinds[node] = "add"} \ done}

THEOREM CompilerTaskExpansionStrictlyRemovesOneRemainingTask ==
    ASSUME NEW view, NEW origin \in DOMAIN view.kinds,
           NEW opened, NEW done, origin \notin opened, origin \notin done
    PROVE /\ <<origin, FALSE>> \in CompilerRemainingTasks(view, opened, done)
          /\ CompilerRemainingTasks(view, opened \cup {origin}, done) =
               CompilerRemainingTasks(view, opened, done) \ {<<origin, FALSE>>}
    BY SMT DEF CompilerRemainingTasks

THEOREM CompilerTaskEmissionStrictlyRemovesOneRemainingTask ==
    ASSUME NEW view, NEW origin \in DOMAIN view.kinds, NEW expanded \in BOOLEAN,
           NEW opened, NEW done, origin \notin done,
           IF expanded THEN origin \in opened /\ view.kinds[origin] = "add"
           ELSE origin \notin opened /\ view.kinds[origin] # "add"
    PROVE /\ <<origin, expanded>> \in CompilerRemainingTasks(view, opened, done)
          /\ CompilerRemainingTasks(view, opened, done \cup {origin}) =
               CompilerRemainingTasks(view, opened, done) \ {<<origin, expanded>>}
    BY SMT DEF CompilerRemainingTasks

THEOREM CompilerRemainingTaskCountIsFinite ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count), NEW opened, NEW done
    PROVE /\ LayoutNamesFS!IsFiniteSet(CompilerRemainingTasks(view, opened, done))
          /\ LayoutNamesFS!Cardinality(CompilerRemainingTasks(view, opened, done)) \in Nat
    PROOF
    <1>1. /\ LayoutNamesFS!IsFiniteSet(1..count)
          /\ LayoutNamesFS!IsFiniteSet({TRUE} \cup {FALSE})
        PROOF
        <2>1. 1 \in Int /\ count \in Int
            BY SMT DEF CompilerOccurrenceTree
        <2>2. /\ LayoutNamesFS!IsFiniteSet(1..count)
              /\ LayoutNamesFS!Cardinality(1..count) = IF 1 > count THEN 0 ELSE count - 1 + 1
            BY <2>1, LayoutNamesFS!FS_Interval
        <2>3. LayoutNamesFS!IsFiniteSet({TRUE})
            BY LayoutNamesFS!FS_Singleton
        <2>4. /\ LayoutNamesFS!IsFiniteSet({TRUE} \cup {FALSE})
              /\ LayoutNamesFS!Cardinality({TRUE} \cup {FALSE}) =
                   IF FALSE \in {TRUE} THEN LayoutNamesFS!Cardinality({TRUE})
                   ELSE LayoutNamesFS!Cardinality({TRUE}) + 1
            BY <2>3, LayoutNamesFS!FS_AddElement
        <2>. QED BY ONLY <2>2, <2>4
    <1>2. LayoutNamesFS!IsFiniteSet((1..count) \X ({TRUE} \cup {FALSE}))
        BY <1>1, LayoutNamesFS!FS_Product
    <1>3. CompilerRemainingTasks(view, opened, done) \subseteq (1..count) \X ({TRUE} \cup {FALSE})
        BY SMT DEF CompilerRemainingTasks, CompilerOccurrenceTree
    <1>4. LayoutNamesFS!IsFiniteSet(CompilerRemainingTasks(view, opened, done))
        BY <1>2, <1>3, LayoutNamesFS!FS_Subset
    <1>. QED BY <1>4, LayoutNamesFS!FS_CardinalityType


\* Historical quotation proofs retained as mathematical results only.
\* The actual expansion parent below uses ReviewedSwiftExpansionIteration.
CompilerExpansionCode ==
    [popBinding |-> <<"let", "(", "origin", ",", "expanded", ")", "=", "pending", ".", "popLast", "(", ")">>,
     sourceSelection |-> <<"source", "[", "origin", "-", "1", "]">>,
     childBinding |-> <<"case", ".", "add", "(", "let", "left", ",", "let", "right", ")", ":">>,
     condition |-> <<"!", "expanded">>,
     statements |-> <<
        <<"pending", ".", "append", "(", "(", "origin", ",", "true", ")", ")">>,
        <<"pending", ".", "append", "(", "(", "right", ",", "false", ")", ")">>,
        <<"pending", ".", "append", "(", "(", "left", ",", "false", ")", ")">>,
        <<"continue">>>>]

SwiftPendingArray(height, pending) ==
    [count |-> height,
     items |-> [index \in 0..(height - 1) |->
         <<pending[index + 1].node, pending[index + 1].expanded>>]]
SwiftArrayRemovingLast(array) ==
    [count |-> array.count - 1,
     items |-> [index \in 0..(array.count - 2) |-> array.items[index]]]
SwiftArrayAppending(array, value) ==
    [count |-> array.count + 1,
     items |-> [index \in 0..array.count |->
         IF index = array.count THEN value ELSE array.items[index]]]

\* This small statement semantics reads operand names from syntax, rather than
\* assigning an "expand" meaning to a recognized statement sequence.
SwiftExpansionStatement(statement, locals, execution) ==
    IF execution.control # "normal" THEN execution
    ELSE IF statement = <<"continue">> THEN [execution EXCEPT !.control = "continue"]
    ELSE IF DOMAIN statement # 1..10 THEN [execution EXCEPT !.control = "unsupported"]
    ELSE IF /\ statement = <<"pending", ".", "append", "(", "(", statement[6], ",", statement[8], ")", ")">>
            /\ statement[6] \in DOMAIN locals
            /\ statement[8] \in {"true", "false"}
         THEN IF execution.pending.count < SwiftIntMax
              THEN [execution EXCEPT !.pending = SwiftArrayAppending(execution.pending,
                       <<locals[statement[6]], statement[8] = "true">>)]
              ELSE [execution EXCEPT !.control = "capacity"]
         ELSE [execution EXCEPT !.control = "unsupported"]

\* shortcut: exactly four statements for this branch; extend the interpreter
\* only when a further actual branch needs longer sequential execution.
SwiftExpansionBlock(statements, locals, execution) ==
    IF DOMAIN statements # 1..4 THEN [execution EXCEPT !.control = "unsupported"]
    ELSE LET first == SwiftExpansionStatement(statements[1], locals, execution)
             second == SwiftExpansionStatement(statements[2], locals, first)
             third == SwiftExpansionStatement(statements[3], locals, second)
         IN SwiftExpansionStatement(statements[4], locals, third)

SwiftSourceArray(view, count) ==
    [count |-> count, items |-> [index \in 0..(count - 1) |->
        [kind |-> view.kinds[index + 1],
         payload |-> IF view.kinds[index + 1] = "literal" THEN view.literals[index + 1]
                     ELSE IF view.kinds[index + 1] = "read" THEN view.reads[index + 1] ELSE 0,
         left |-> IF view.kinds[index + 1] = "add" THEN view.left[index + 1] ELSE 0,
         right |-> IF view.kinds[index + 1] = "add" THEN view.right[index + 1] ELSE 0]]]

SwiftExpansionContextSupported(syntax) ==
    /\ syntax.popBinding = <<"let", "(", "origin", ",", "expanded", ")", "=", "pending", ".", "popLast", "(", ")">>
    /\ syntax.sourceSelection = <<"source", "[", "origin", "-", "1", "]">>
    /\ syntax.childBinding = <<"case", ".", "add", "(", "let", "left", ",", "let", "right", ")", ":">>
    /\ syntax.condition = <<"!", "expanded">>

SwiftExpansionIteration(syntax, pending, source, untouched) ==
    LET start == [pending |-> pending, control |-> "normal", untouched |-> untouched]
    IN IF ~SwiftExpansionContextSupported(syntax)
       THEN [start EXCEPT !.control = "unsupported"]
       ELSE IF pending.count = 0 THEN [start EXCEPT !.control = "exit"]
       ELSE LET frame == pending.items[pending.count - 1]
                popped == [start EXCEPT !.pending = SwiftArrayRemovingLast(pending)]
            IN IF frame[1] \notin 1..source.count THEN [popped EXCEPT !.control = "indexFailure"]
               ELSE LET node == source.items[frame[1] - 1]
                    IN IF node.kind # "add" \/ frame[2]
                       THEN [popped EXCEPT !.control = "otherBranch"]
                       ELSE SwiftExpansionBlock(syntax.statements,
                           [origin |-> frame[1], left |-> node.left, right |-> node.right], popped)

THEOREM InterpretedExpansionAppendsInSourceOrder ==
    ASSUME NEW array, array.count \in Nat, array.count + 3 <= SwiftIntMax,
           NEW origin, NEW left, NEW right, NEW untouched
    PROVE SwiftExpansionBlock(CompilerExpansionCode.statements,
              [origin |-> origin, left |-> left, right |-> right],
              [pending |-> array, control |-> "normal", untouched |-> untouched]) =
          [pending |-> SwiftArrayAppending(SwiftArrayAppending(SwiftArrayAppending(
              array, <<origin, TRUE>>), <<right, FALSE>>), <<left, FALSE>>),
           control |-> "continue", untouched |-> untouched]
    PROOF
    <1>0. USE IntegerDomain DEF IntegerDomain
    <1>. DEFINE locals == [origin |-> origin, left |-> left, right |-> right]
                start == [pending |-> array, control |-> "normal", untouched |-> untouched]
                one == [pending |-> SwiftArrayAppending(array, <<origin, TRUE>>),
                        control |-> "normal", untouched |-> untouched]
                two == [pending |-> SwiftArrayAppending(one.pending, <<right, FALSE>>),
                        control |-> "normal", untouched |-> untouched]
                three == [pending |-> SwiftArrayAppending(two.pending, <<left, FALSE>>),
                          control |-> "normal", untouched |-> untouched]
                finish == [pending |-> three.pending, control |-> "continue", untouched |-> untouched]
    <1>syntax. CompilerExpansionCode.statements = <<
        <<"pending", ".", "append", "(", "(", "origin", ",", "true", ")", ")">>,
        <<"pending", ".", "append", "(", "(", "right", ",", "false", ")", ")">>,
        <<"pending", ".", "append", "(", "(", "left", ",", "false", ")", ")">>,
        <<"continue">>>>
        BY ONLY DEF CompilerExpansionCode
    <1>space. array.count < SwiftIntMax
        BY SMT
    <1>1. SwiftExpansionStatement(CompilerExpansionCode.statements[1], locals, start) = one
        BY ONLY <1>syntax, <1>space DEF SwiftExpansionStatement, locals, start, one
    <1>2. one.pending.count < SwiftIntMax
        BY SMT DEF one, SwiftArrayAppending
    <1>3. SwiftExpansionStatement(CompilerExpansionCode.statements[2], locals, one) = two
        BY ONLY <1>syntax, <1>2 DEF SwiftExpansionStatement, locals, one, two
    <1>4. two.pending.count < SwiftIntMax
        BY SMT DEF two, one, SwiftArrayAppending
    <1>5. SwiftExpansionStatement(CompilerExpansionCode.statements[3], locals, two) = three
        BY ONLY <1>syntax, <1>4 DEF SwiftExpansionStatement, locals, two, three
    <1>6. SwiftExpansionStatement(CompilerExpansionCode.statements[4], locals, three) = finish
        BY ONLY <1>syntax DEF SwiftExpansionStatement, locals, three, finish
    <1>7. SwiftExpansionBlock(CompilerExpansionCode.statements, locals, start) = finish
        BY ONLY <1>syntax, <1>1, <1>3, <1>5, <1>6 DEF SwiftExpansionBlock
    <1>. QED BY <1>7 DEF locals, start, finish, three, two, one

THEOREM InterpretedExpansionImplementsPendingReplacement ==
    ASSUME NEW height \in Nat, height > 0, height + 2 <= SwiftIntMax,
           NEW pending, NEW left, NEW right, NEW untouched
    PROVE SwiftExpansionBlock(CompilerExpansionCode.statements,
              [origin |-> pending[height].node,
               left |-> left[pending[height].node], right |-> right[pending[height].node]],
              [pending |-> SwiftArrayRemovingLast(SwiftPendingArray(height, pending)),
               control |-> "normal", untouched |-> untouched]) =
          [pending |-> SwiftPendingArray(height + 2,
              ReplaceTopVisitFrame(pending, height,
                  ExpandedVisitFrames(pending[height], left, right))),
           control |-> "continue", untouched |-> untouched]
    PROOF
    <1>1. /\ SwiftArrayRemovingLast(SwiftPendingArray(height, pending)).count \in Nat
          /\ SwiftArrayRemovingLast(SwiftPendingArray(height, pending)).count + 3 <= SwiftIntMax
        BY SMT DEF SwiftArrayRemovingLast, SwiftPendingArray
    <1>2. SwiftArrayAppending(SwiftArrayAppending(SwiftArrayAppending(
              SwiftArrayRemovingLast(SwiftPendingArray(height, pending)),
              <<pending[height].node, TRUE>>),
              <<right[pending[height].node], FALSE>>),
              <<left[pending[height].node], FALSE>>) =
          SwiftPendingArray(height + 2, ReplaceTopVisitFrame(pending, height,
              ExpandedVisitFrames(pending[height], left, right)))
        BY SMT DEF SwiftArrayAppending, SwiftArrayRemovingLast, SwiftPendingArray,
            ReplaceTopVisitFrame, ExpandedVisitFrames, VisitFrame
    <1>. QED BY <1>1, <1>2, InterpretedExpansionAppendsInSourceOrder

THEOREM InterpretedExpansionBindsThePoppedSourceChildren ==
    ASSUME NEW height \in Nat, height > 0, NEW pending, NEW view, NEW count \in Nat,
           pending[height].node \in 1..count,
           view.kinds[pending[height].node] = "add", ~pending[height].expanded,
           NEW untouched
    PROVE SwiftExpansionIteration(CompilerExpansionCode, SwiftPendingArray(height, pending),
              SwiftSourceArray(view, count), untouched) =
          SwiftExpansionBlock(CompilerExpansionCode.statements,
              [origin |-> pending[height].node,
               left |-> view.left[pending[height].node], right |-> view.right[pending[height].node]],
              [pending |-> SwiftArrayRemovingLast(SwiftPendingArray(height, pending)),
               control |-> "normal", untouched |-> untouched])
    PROOF
    <1>syntax. SwiftExpansionContextSupported(CompilerExpansionCode)
        BY ONLY DEF SwiftExpansionContextSupported, CompilerExpansionCode
    <1>1. SwiftPendingArray(height, pending).items[height - 1] =
              <<pending[height].node, pending[height].expanded>>
        BY SMT DEF SwiftPendingArray
    <1>2. SwiftSourceArray(view, count).items[pending[height].node - 1] =
              [kind |-> "add", payload |-> 0, left |-> view.left[pending[height].node],
               right |-> view.right[pending[height].node]]
        BY SMT DEF SwiftSourceArray
    <1>. QED BY <1>syntax, <1>1, <1>2, SMT
        DEF SwiftExpansionIteration, SwiftPendingArray, SwiftSourceArray

\* Reviewed interpretation of StraightLineAssignmentCheck.swift:46-58,76-81.
\* Source SHA256 9dc886404fa0b901254582079511b1e7f122a6a8c99313058cdb24e7e82a8a9d.
\* The source-to-operation mapping is an explicitly trusted foundation (2026-11-16),
\* not a mechanically verified Swift frontend. See the active .context plan.
\* Each primitive below denotes documented Swift value-array behavior on normal
\* execution with sufficient storage; capacity is explicit, not a model failure.
SwiftAppendPendingFrame(execution, value) ==
    IF execution.control # "normal" THEN execution
    ELSE IF execution.pending.count < SwiftIntMax
         THEN [execution EXCEPT !.pending = SwiftArrayAppending(execution.pending, value)]
         ELSE [execution EXCEPT !.control = "capacity"]

ReviewedSwiftExpansionHelper(array, origin, left, right, untouched) ==
    LET start == [pending |-> array, control |-> "normal", untouched |-> untouched]
        parent == SwiftAppendPendingFrame(start, <<origin, TRUE>>)
        rightChild == SwiftAppendPendingFrame(parent, <<right, FALSE>>)
    IN SwiftAppendPendingFrame(rightChild, <<left, FALSE>>)

ReviewedSwiftExpansionIteration(pending, source, untouched) ==
    LET start == [pending |-> pending, control |-> "normal", untouched |-> untouched]
    IN IF pending.count = 0 THEN [start EXCEPT !.control = "exit"]
       ELSE LET frame == pending.items[pending.count - 1]
                popped == SwiftArrayRemovingLast(pending)
            IN IF frame[1] \notin 1..source.count
               THEN [start EXCEPT !.pending = popped, !.control = "indexFailure"]
               ELSE LET node == source.items[frame[1] - 1]
                    IN IF node.kind # "add" \/ frame[2]
                       THEN [start EXCEPT !.pending = popped, !.control = "otherBranch"]
                       ELSE LET returned == ReviewedSwiftExpansionHelper(
                                    popped, frame[1], node.left, node.right, untouched)
                            IN IF returned.control = "normal"
                               THEN [returned EXCEPT !.control = "continue"] ELSE returned

\* Closes the real helper's ordered append obligation; consumed by the caller below.
THEOREM ReviewedHelperDerivesThreeAppends ==
    ASSUME NEW array, array.count \in Nat, array.count + 3 <= SwiftIntMax,
           NEW origin, NEW left, NEW right, NEW untouched
    PROVE ReviewedSwiftExpansionHelper(array, origin, left, right, untouched) =
          [pending |-> SwiftArrayAppending(SwiftArrayAppending(SwiftArrayAppending(
              array, <<origin, TRUE>>), <<right, FALSE>>), <<left, FALSE>>),
           control |-> "normal", untouched |-> untouched]
    PROOF
    <1>domain. USE IntegerDomain DEF IntegerDomain
    <1>. DEFINE start == [pending |-> array, control |-> "normal", untouched |-> untouched]
                one == [pending |-> SwiftArrayAppending(array, <<origin, TRUE>>),
                        control |-> "normal", untouched |-> untouched]
                two == [pending |-> SwiftArrayAppending(one.pending, <<right, FALSE>>),
                        control |-> "normal", untouched |-> untouched]
    <1>counts. /\ one.pending.count = array.count + 1
               /\ two.pending.count = (array.count + 1) + 1
        BY ONLY DEF one, two, SwiftArrayAppending
    <1>space. /\ array.count < SwiftIntMax
              /\ one.pending.count < SwiftIntMax
              /\ two.pending.count < SwiftIntMax
        BY <1>counts, SMT
    <1>first. SwiftAppendPendingFrame(start, <<origin, TRUE>>) = one
        BY ONLY <1>space DEF SwiftAppendPendingFrame, start, one
    <1>second. SwiftAppendPendingFrame(one, <<right, FALSE>>) = two
        BY ONLY <1>space DEF SwiftAppendPendingFrame, one, two
    <1>. QED BY <1>space, <1>first, <1>second
        DEF ReviewedSwiftExpansionHelper, SwiftAppendPendingFrame, start, one, two

\* Closes popLast, source/add binding, helper inout and continue for this branch.
\* Consumed directly by ExpandingACompilerFramePreservesAllLoopInvariants.
THEOREM ReviewedExpansionDerivesPendingReplacement ==
    ASSUME NEW height \in Nat, height > 0, height + 2 <= SwiftIntMax,
           NEW pending, NEW view, NEW count \in Nat,
           pending[height].node \in 1..count,
           view.kinds[pending[height].node] = "add", ~pending[height].expanded,
           NEW untouched
    PROVE ReviewedSwiftExpansionIteration(SwiftPendingArray(height, pending),
              SwiftSourceArray(view, count), untouched) =
          [pending |-> SwiftPendingArray(height + 2,
              ReplaceTopVisitFrame(pending, height,
                  ExpandedVisitFrames(pending[height], view.left, view.right))),
           control |-> "continue", untouched |-> untouched]
    PROOF
    <1>frame. SwiftPendingArray(height, pending).items[height - 1] =
              <<pending[height].node, pending[height].expanded>>
        BY SMT DEF SwiftPendingArray
    <1>source. SwiftSourceArray(view, count).items[pending[height].node - 1] =
              [kind |-> "add", payload |-> 0, left |-> view.left[pending[height].node],
               right |-> view.right[pending[height].node]]
        PROOF
        <2>offset. /\ pending[height].node - 1 \in 0..(count - 1)
                    /\ (pending[height].node - 1) + 1 = pending[height].node
            BY SMT
        <2>. QED BY ONLY <2>offset, view.kinds[pending[height].node] = "add"
            DEF SwiftSourceArray
    <1>space. /\ SwiftArrayRemovingLast(SwiftPendingArray(height, pending)).count \in Nat
              /\ SwiftArrayRemovingLast(SwiftPendingArray(height, pending)).count + 3 <= SwiftIntMax
        BY SMT DEF SwiftArrayRemovingLast, SwiftPendingArray
    <1>helper. ReviewedSwiftExpansionHelper(SwiftArrayRemovingLast(SwiftPendingArray(height, pending)),
                  pending[height].node, view.left[pending[height].node], view.right[pending[height].node],
                  untouched) =
              [pending |-> SwiftArrayAppending(SwiftArrayAppending(SwiftArrayAppending(
                  SwiftArrayRemovingLast(SwiftPendingArray(height, pending)),
                  <<pending[height].node, TRUE>>), <<view.right[pending[height].node], FALSE>>),
                  <<view.left[pending[height].node], FALSE>>), control |-> "normal", untouched |-> untouched]
        BY <1>space, ReviewedHelperDerivesThreeAppends
    <1>replacement. SwiftArrayAppending(SwiftArrayAppending(SwiftArrayAppending(
                  SwiftArrayRemovingLast(SwiftPendingArray(height, pending)),
                  <<pending[height].node, TRUE>>), <<view.right[pending[height].node], FALSE>>),
                  <<view.left[pending[height].node], FALSE>>) =
              SwiftPendingArray(height + 2, ReplaceTopVisitFrame(pending, height,
                  ExpandedVisitFrames(pending[height], view.left, view.right)))
        BY SMT DEF SwiftArrayAppending, SwiftArrayRemovingLast, SwiftPendingArray,
            ReplaceTopVisitFrame, ExpandedVisitFrames, VisitFrame
    <1>. QED BY <1>frame, <1>source, <1>helper, <1>replacement, SMT
        DEF ReviewedSwiftExpansionIteration, SwiftPendingArray, SwiftSourceArray

\* height = pending.count; frame.node/expanded model the actual tuple fields.
\* frame.prefix, opened and done are ghost data, not a retained Swift execution.
\* No Swift-body-to-TLA refinement theorem is supplied by these definitions.
InitialCompilerTraversal(view) ==
    [height |-> 1, pending |-> <<VisitFrame(view.root, FALSE, EmptyVisitPrefix)>>,
     completed |-> EmptyVisitPrefix, current |-> EmptyCertificateConstruction(view),
     opened |-> {}, done |-> {}]

CompilerTraversalNext(view, state) ==
    LET frame == state.pending[state.height]
        origin == frame.node
        expands == view.kinds[origin] = "add" /\ ~frame.expanded
    IN [height |-> IF expands THEN state.height + 2 ELSE state.height - 1,
        pending |-> IF expands THEN ReplaceTopVisitFrame(state.pending, state.height,
                           ExpandedVisitFrames(frame, view.left, view.right))
                    ELSE HistoryPrefix(state.pending, state.height - 1),
        completed |-> IF expands THEN state.completed ELSE VisitFrameExit(frame),
        current |-> IF expands THEN state.current ELSE AppendCertificateConstructor(view, state.current, origin),
        opened |-> IF expands THEN state.opened \cup {origin} ELSE state.opened,
        done |-> IF expands THEN state.done ELSE state.done \cup {origin}]

THEOREM CompilerTraversalNextProjectsStoredFields ==
    ASSUME NEW view, NEW state
    PROVE LET frame == state.pending[state.height]
              expands == view.kinds[frame.node] = "add" /\ ~frame.expanded
              next == CompilerTraversalNext(view, state)
          IN /\ next.height = IF expands THEN state.height + 2 ELSE state.height - 1
             /\ next.pending = IF expands THEN ReplaceTopVisitFrame(state.pending, state.height,
                                  ExpandedVisitFrames(frame, view.left, view.right))
                               ELSE HistoryPrefix(state.pending, state.height - 1)
             /\ next.current = IF expands THEN state.current
                               ELSE AppendCertificateConstructor(view, state.current, frame.node)
    PROOF
    <1>. DEFINE frame == state.pending[state.height]
                expands == view.kinds[frame.node] = "add" /\ ~frame.expanded
                next == CompilerTraversalNext(view, state)
    <1>height. next.height = IF expands THEN state.height + 2 ELSE state.height - 1
        BY ONLY DEF frame, expands, next, CompilerTraversalNext
    <1>pending. next.pending = IF expands THEN ReplaceTopVisitFrame(state.pending, state.height,
                                    ExpandedVisitFrames(frame, view.left, view.right))
                                 ELSE HistoryPrefix(state.pending, state.height - 1)
        BY ONLY DEF frame, expands, next, CompilerTraversalNext
    <1>current. next.current = IF expands THEN state.current
                                 ELSE AppendCertificateConstructor(view, state.current, frame.node)
        BY ONLY DEF frame, expands, next, CompilerTraversalNext
    <1>. QED BY ONLY <1>height, <1>pending, <1>current DEF frame, expands, next

CompilerTraversalInvariant(view, state) ==
    /\ CompilerOccurrenceStages(view, state.height, state.pending, state.opened, state.done)
    /\ PendingVisitContract(state.height, state.pending, state.completed,
           PushVisitPrefix(EmptyVisitPrefix, view.root), view.left, view.right)
    /\ CertificateConstructionInvariant(view, state.current)
    /\ CompletedCertificateRoots(view, state.current, state.completed)
    /\ \A node \in DOMAIN view.kinds : (state.current.inverse[node] > 0) \equiv (node \in state.done)
    /\ (state.completed.height > 0 =>
           state.completed.terms[state.completed.height] = state.current.emitted.origins[state.current.emitted.count])

ReviewedExpansionOperationSafety(view, count, state) ==
    LET origin == state.pending[state.height].node
    IN /\ state.height \in 1..(SwiftIntMax - 2)
       /\ origin - 1 \in 0..(count - 1)
       /\ InRange(origin - 1)
       /\ origin \in 1..SwiftIntMax
       /\ view.left[origin] \in 1..SwiftIntMax
       /\ view.right[origin] \in 1..SwiftIntMax
       /\ state.height - 1 + 3 <= SwiftIntMax

ReviewedExpansionMatchesTraversal(view, count, state, untouched) ==
    ReviewedSwiftExpansionIteration(SwiftPendingArray(state.height, state.pending),
        SwiftSourceArray(view, count), untouched) =
    [pending |-> SwiftPendingArray(CompilerTraversalNext(view, state).height,
                                  CompilerTraversalNext(view, state).pending),
     control |-> "continue", untouched |-> untouched]

THEOREM CompilerTraversalStartsWithItsLoopInvariants ==
    ASSUME NEW view
    PROVE CompilerTraversalInvariant(view, InitialCompilerTraversal(view))
    PROOF
    <1>1. CompilerOccurrenceStages(view, 1,
              <<VisitFrame(view.root, FALSE, EmptyVisitPrefix)>>, {}, {})
        BY SourceRootStartsTheOccurrenceStages
    <1>2. PendingVisitContract(1, <<VisitFrame(view.root, FALSE, EmptyVisitPrefix)>>,
              EmptyVisitPrefix, PushVisitPrefix(EmptyVisitPrefix, view.root), view.left, view.right)
        BY ASourceRootStartsItsOwnPendingVisitContract
    <1>3. CertificateConstructionInvariant(view, EmptyCertificateConstruction(view))
        BY EmptyCompilerCertificateStartsTheConstruction
    <1>4. CompletedCertificateRoots(view, EmptyCertificateConstruction(view), EmptyVisitPrefix)
        BY EmptyCompilerCertificateHasNoCompletedRoots
    <1>. QED BY <1>1, <1>2, <1>3, <1>4, SMT DEF CompilerTraversalInvariant,
        InitialCompilerTraversal, EmptyCertificateConstruction, EmptyVisitPrefix, VisitPrefix

THEOREM ExpandingACompilerFramePreservesAllLoopInvariants ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW state, CompilerTraversalInvariant(view, state), state.height > 0,
           view.kinds[state.pending[state.height].node] = "add", ~state.pending[state.height].expanded
    PROVE /\ CompilerTraversalInvariant(view, CompilerTraversalNext(view, state))
          /\ (state.height + 2 <= SwiftIntMax /\ count <= SwiftIntMax =>
                 /\ ReviewedExpansionOperationSafety(view, count, state)
                 /\ \A untouched : ReviewedExpansionMatchesTraversal(view, count, state, untouched))
    PROOF
    <1>1. CompilerOccurrenceStages(view, state.height + 2,
              ReplaceTopVisitFrame(state.pending, state.height,
                  ExpandedVisitFrames(state.pending[state.height], view.left, view.right)),
              state.opened \cup {state.pending[state.height].node}, state.done)
        BY ExpandingACompilerParentPreservesOccurrenceStages DEF CompilerTraversalInvariant
    <1>2. PendingVisitContract(state.height + 2,
              ReplaceTopVisitFrame(state.pending, state.height,
                  ExpandedVisitFrames(state.pending[state.height], view.left, view.right)),
              state.completed, PushVisitPrefix(EmptyVisitPrefix, view.root), view.left, view.right)
        BY ExpandingAPendingParentPreservesTheVisitContract DEF CompilerTraversalInvariant
    <1>origin. state.pending[state.height].node \in 1..count
        BY PendingCompilerFramesHaveFreshEmissionOrigins, SMT
            DEF CompilerTraversalInvariant, CompilerOccurrenceTree
    <1>safe. state.height + 2 <= SwiftIntMax /\ count <= SwiftIntMax =>
                 ReviewedExpansionOperationSafety(view, count, state)
        BY <1>origin, IntegerDomain, SMT DEF ReviewedExpansionOperationSafety,
            InRange, IntegerDomain, CompilerOccurrenceTree, CompilerTraversalInvariant,
            CompilerOccurrenceStages
    <1>3. state.height + 2 <= SwiftIntMax /\ count <= SwiftIntMax =>
              \A untouched : ReviewedExpansionMatchesTraversal(view, count, state, untouched)
        BY <1>origin, ReviewedExpansionDerivesPendingReplacement, SMT
            DEF ReviewedExpansionMatchesTraversal, CompilerTraversalNext,
                CompilerTraversalInvariant, CompilerOccurrenceStages, CompilerOccurrenceTree
    <1>. QED BY <1>1, <1>2, <1>safe, <1>3, SMT DEF CompilerTraversalInvariant, CompilerTraversalNext

\* Reviewed interpretation of orderedIntCertificate's emitting iteration and return.
\* The Swift/source binding is the expressly trusted reviewed interpretation;
\* documented Swift value-array operations require sufficient operational storage.
SwiftIndexedArray(length, values) ==
    [count |-> length, items |-> [offset \in 0..(length - 1) |-> values[offset + 1]]]

SwiftArrayReplacing(array, offset, value) ==
    [count |-> array.count, items |-> [index \in 0..(array.count - 1) |->
        IF index = offset THEN value ELSE array.items[index]]]

SwiftCompilerStorage(view, count, state) ==
    [pending |-> SwiftPendingArray(state.height, state.pending),
     nodes |-> SwiftIndexedArray(state.current.emitted.count, state.current.emitted.nodes),
     origins |-> SwiftIndexedArray(state.current.emitted.count, state.current.emitted.origins),
     indices |-> SwiftIndexedArray(count, state.current.inverse),
     completed |-> SwiftIndexedArray(state.completed.height, state.completed.terms),
     control |-> "normal"]

\* Common suffix: guard freshness; append node; append origin; set the new
\* nodes.count in indices; append origin to completed, in that source order.
ReviewedSwiftAppendCertificate(storage, origin, node) ==
    IF origin \notin 1..storage.indices.count THEN [storage EXCEPT !.control = "indexFailure"]
    ELSE IF storage.indices.items[origin - 1] # 0 THEN [storage EXCEPT !.control = "reject"]
    ELSE IF storage.nodes.count >= SwiftIntMax \/ storage.origins.count >= SwiftIntMax
              \/ storage.completed.count >= SwiftIntMax
         THEN [storage EXCEPT !.control = "capacity"]
    ELSE LET nodes == SwiftArrayAppending(storage.nodes, node)
             origins == SwiftArrayAppending(storage.origins, origin)
             indices == SwiftArrayReplacing(storage.indices, origin - 1, nodes.count)
         IN [storage EXCEPT !.nodes = nodes, !.origins = origins, !.indices = indices,
                           !.completed = SwiftArrayAppending(storage.completed, origin)]

ReviewedSwiftEmissionIteration(source, storage) ==
    IF storage.pending.count = 0 THEN [storage EXCEPT !.control = "exit"]
    ELSE LET frame == storage.pending.items[storage.pending.count - 1]
             popped == [storage EXCEPT !.pending = SwiftArrayRemovingLast(storage.pending)]
         IN IF frame[1] \notin 1..source.count THEN [popped EXCEPT !.control = "indexFailure"]
            ELSE LET node == source.items[frame[1] - 1]
                     completed == storage.completed
                 IN IF node.kind \in {"literal", "read"}
                    THEN ReviewedSwiftAppendCertificate(popped, frame[1], node)
                    ELSE IF node.kind # "add" THEN [popped EXCEPT !.control = "reject"]
                    ELSE IF ~frame[2] THEN [popped EXCEPT !.control = "otherBranch"]
                    ELSE IF completed.count < 2 THEN [popped EXCEPT !.control = "reject"]
                    ELSE IF completed.items[completed.count - 2] # node.left
                         THEN [popped EXCEPT !.control = "reject"]
                    ELSE IF completed.items[completed.count - 1] # node.right
                         THEN [popped EXCEPT !.control = "reject"]
                    ELSE IF node.left \notin 1..storage.indices.count
                         THEN [popped EXCEPT !.control = "indexFailure"]
                    ELSE IF storage.indices.items[node.left - 1] <= 0
                         THEN [popped EXCEPT !.control = "reject"]
                    ELSE IF node.right \notin 1..storage.indices.count
                         THEN [popped EXCEPT !.control = "indexFailure"]
                    ELSE IF storage.indices.items[node.right - 1] <= 0
                         THEN [popped EXCEPT !.control = "reject"]
                    ELSE ReviewedSwiftAppendCertificate(
                        [popped EXCEPT !.completed = SwiftArrayRemovingLast(SwiftArrayRemovingLast(completed))],
                        frame[1], [kind |-> "add", payload |-> 0,
                                   left |-> storage.indices.items[node.left - 1],
                                   right |-> storage.indices.items[node.right - 1]])

ReviewedEmissionOperationSafety(view, count, state) ==
    LET origin == state.pending[state.height].node
    IN /\ state.height \in 1..SwiftIntMax
       /\ count \in 1..SwiftIntMax
       /\ origin - 1 \in 0..(count - 1)
       /\ state.current.inverse[origin] = 0
       /\ state.current.emitted.count + 1 \in 1..SwiftIntMax
       /\ state.completed.height + 1 \in 1..SwiftIntMax
       /\ (view.kinds[origin] = "add" =>
            /\ state.completed.height >= 2
            /\ state.completed.height - 2 \in 0..(state.completed.height - 1)
            /\ state.completed.height - 1 \in 0..(state.completed.height - 1)
            /\ state.completed.terms[state.completed.height - 1] = view.left[origin]
            /\ state.completed.terms[state.completed.height] = view.right[origin]
            /\ view.left[origin] - 1 \in 0..(count - 1)
            /\ view.right[origin] - 1 \in 0..(count - 1)
            /\ state.current.inverse[view.left[origin]] \in 1..state.current.emitted.count
            /\ state.current.inverse[view.right[origin]] \in 1..state.current.emitted.count)

ReviewedEmissionMatchesTraversal(view, count, state) ==
    ReviewedSwiftEmissionIteration(SwiftSourceArray(view, count), SwiftCompilerStorage(view, count, state)) =
        SwiftCompilerStorage(view, count, CompilerTraversalNext(view, state))

THEOREM CompilerEmissionDerivesEveryRejectingGuard ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW state, CompilerTraversalInvariant(view, state), state.height > 0,
           state.pending[state.height].expanded \/ view.kinds[state.pending[state.height].node] # "add"
    PROVE LET origin == state.pending[state.height].node
          IN /\ origin \in 1..count
             /\ state.current.inverse[origin] = 0
             /\ state.pending[state.height].expanded \in BOOLEAN
             /\ (state.pending[state.height].expanded \equiv (view.kinds[origin] = "add"))
             /\ state.completed = state.pending[state.height].prefix
             /\ state.completed.height \in Nat
             /\ state.current.emitted.count \in Nat
             /\ (view.kinds[origin] = "add" =>
                  /\ state.completed.height >= 2
                  /\ state.completed.terms[state.completed.height - 1] = view.left[origin]
                  /\ state.completed.terms[state.completed.height] = view.right[origin]
                  /\ view.left[origin] \in 1..count /\ view.right[origin] \in 1..count
                  /\ state.current.inverse[view.left[origin]] \in 1..state.current.emitted.count
                  /\ state.current.inverse[view.right[origin]] \in 1..state.current.emitted.count)
    PROOF
    <1>fresh. /\ state.pending[state.height].node \in DOMAIN view.kinds
              /\ state.pending[state.height].expanded \in BOOLEAN
              /\ state.current.inverse[state.pending[state.height].node] = 0
              /\ (state.pending[state.height].expanded =>
                    view.kinds[state.pending[state.height].node] = "add")
              /\ (~state.pending[state.height].expanded =>
                    state.pending[state.height].node \notin state.opened)
        BY PendingCompilerFramesHaveFreshEmissionOrigins DEF CompilerTraversalInvariant
    <1>branch. state.pending[state.height].expanded \equiv
                  (view.kinds[state.pending[state.height].node] = "add")
        BY <1>fresh, SMT
    <1>children. state.pending[state.height].expanded =>
        LET origin == state.pending[state.height].node
        IN /\ state.completed.height >= 2
           /\ state.completed.terms[state.completed.height - 1] = view.left[origin]
           /\ state.completed.terms[state.completed.height] = view.right[origin]
           /\ view.left[origin] \in DOMAIN view.kinds /\ view.right[origin] \in DOMAIN view.kinds
           /\ state.current.inverse[view.left[origin]] \in 1..state.current.emitted.count
           /\ state.current.inverse[view.right[origin]] \in 1..state.current.emitted.count
        BY PendingCompilerAddHasItsOrderedCompletedChildren, SMT DEF CompilerTraversalInvariant
    <1>. QED BY <1>fresh, <1>branch, <1>children, SMT
        DEF CompilerTraversalInvariant, CompilerOccurrenceTree, PendingVisitContract,
            WellFormedVisitFrame, WellFormedVisitPrefix, CertificateConstructionInvariant, NodeEmissionArrays

THEOREM ReviewedEmissionDerivesTraversalStep ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW state, CompilerTraversalInvariant(view, state), state.height > 0,
           state.pending[state.height].expanded \/ view.kinds[state.pending[state.height].node] # "add",
           state.height <= SwiftIntMax, count <= SwiftIntMax,
           state.current.emitted.count + 1 <= SwiftIntMax,
           state.completed.height + 1 <= SwiftIntMax
    PROVE /\ ReviewedEmissionOperationSafety(view, count, state)
          /\ ReviewedEmissionMatchesTraversal(view, count, state)
    PROOF
    <1>. DEFINE origin == state.pending[state.height].node
                frame == state.pending[state.height]
                before == SwiftCompilerStorage(view, count, state)
                after == CompilerTraversalNext(view, state)
                kind == view.kinds[origin]
                node == [kind |-> kind,
                         payload |-> IF kind = "literal" THEN view.literals[origin]
                                     ELSE IF kind = "read" THEN view.reads[origin] ELSE 0,
                         left |-> IF kind = "add" THEN state.current.inverse[view.left[origin]] ELSE 0,
                         right |-> IF kind = "add" THEN state.current.inverse[view.right[origin]] ELSE 0]
                retained == IF frame.expanded
                            THEN SwiftArrayRemovingLast(SwiftArrayRemovingLast(before.completed))
                            ELSE before.completed
                popped == [before EXCEPT !.pending = SwiftArrayRemovingLast(before.pending), !.completed = retained]
    <1>guards. LET origin == state.pending[state.height].node
               IN /\ origin \in 1..count /\ state.current.inverse[origin] = 0
                  /\ frame.expanded \in BOOLEAN /\ (frame.expanded \equiv (kind = "add"))
                  /\ state.completed = frame.prefix /\ state.completed.height \in Nat
                  /\ state.current.emitted.count \in Nat
                  /\ (kind = "add" =>
                       /\ state.completed.height >= 2
                       /\ state.completed.terms[state.completed.height - 1] = view.left[origin]
                       /\ state.completed.terms[state.completed.height] = view.right[origin]
                       /\ view.left[origin] \in 1..count /\ view.right[origin] \in 1..count
                       /\ state.current.inverse[view.left[origin]] \in 1..state.current.emitted.count
                       /\ state.current.inverse[view.right[origin]] \in 1..state.current.emitted.count)
        BY CompilerEmissionDerivesEveryRejectingGuard DEF frame, kind
    <1>safe. ReviewedEmissionOperationSafety(view, count, state)
        BY <1>guards, IntegerDomain, SMT DEF ReviewedEmissionOperationSafety,
            CompilerOccurrenceTree, CompilerTraversalInvariant, CompilerOccurrenceStages, frame, kind
    <1>counts. /\ before.nodes.count = state.current.emitted.count
               /\ before.origins.count = before.nodes.count
               /\ before.indices.count = count
               /\ retained.count \in 0..state.completed.height
               /\ popped.completed.count < SwiftIntMax
        PROOF
        <2>storage. /\ before.nodes.count = state.current.emitted.count
                    /\ before.origins.count = before.nodes.count
                    /\ before.indices.count = count
                    /\ before.completed.count = state.completed.height
                    /\ popped.completed = retained
            BY DEF before, popped, SwiftCompilerStorage, SwiftIndexedArray
        <2>retained. retained.count = IF frame.expanded
                     THEN (state.completed.height - 1) - 1 ELSE state.completed.height
            BY ONLY <2>storage DEF retained, SwiftArrayRemovingLast
        <2>types. /\ state.completed.height \in Nat /\ SwiftIntMax \in Int
                  /\ frame.expanded \in BOOLEAN
                  /\ (frame.expanded => state.completed.height >= 2)
            BY <1>guards, IntegerDomain, SMT DEF frame, kind, IntegerDomain
        <2>range. retained.count \in 0..state.completed.height
            BY ONLY <2>retained, <2>types, SMT
        <2>space. popped.completed.count < SwiftIntMax
            BY <2>storage, <2>range, <2>types, SMT
        <2>. QED BY ONLY <2>storage, <2>range, <2>space
    <1>selected. ReviewedSwiftEmissionIteration(SwiftSourceArray(view, count), before) =
                    ReviewedSwiftAppendCertificate(popped, origin, node)
        PROOF
        <2>shape. /\ state.height \in Nat /\ origin \in 1..count
                  /\ kind \in {"literal", "read", "add"}
                  /\ before.pending = SwiftPendingArray(state.height, state.pending)
                  /\ before.indices = SwiftIndexedArray(count, state.current.inverse)
                  /\ before.completed = SwiftIndexedArray(state.completed.height, state.completed.terms)
                  /\ SwiftSourceArray(view, count).count = count
            BY <1>guards, SMT DEF CompilerTraversalInvariant, CompilerOccurrenceStages,
                CompilerOccurrenceTree, before, SwiftCompilerStorage, SwiftSourceArray, origin, kind
        <2>frame. /\ before.pending.count = state.height /\ before.pending.count > 0
                  /\ before.pending.items[state.height - 1] = <<origin, frame.expanded>>
            BY <2>shape, SMT DEF SwiftPendingArray, origin, frame
        <2>source. SwiftSourceArray(view, count).items[origin - 1] =
            [kind |-> kind,
             payload |-> IF kind = "literal" THEN view.literals[origin]
                         ELSE IF kind = "read" THEN view.reads[origin] ELSE 0,
             left |-> IF kind = "add" THEN view.left[origin] ELSE 0,
             right |-> IF kind = "add" THEN view.right[origin] ELSE 0]
            PROOF
            <3>offset. /\ origin - 1 \in 0..(count - 1) /\ (origin - 1) + 1 = origin
                BY <1>guards, SMT DEF origin, CompilerOccurrenceTree
            <3>. QED BY ONLY <3>offset DEF SwiftSourceArray, kind
        <2>leaf. CASE kind # "add"
            PROOF
            <3>binding. /\ ~frame.expanded /\ retained = before.completed
                        /\ node.kind \in {"literal", "read"}
                        /\ SwiftSourceArray(view, count).items[origin - 1] = node
                BY <1>guards, <2>shape, <2>source, <2>leaf, SMT DEF retained, node
            <3>storage. popped = [before EXCEPT !.pending = SwiftArrayRemovingLast(before.pending)]
                BY <3>binding, SMT DEF popped, before, SwiftCompilerStorage
            <3>. QED BY ONLY <1>guards, <2>shape, <2>frame, <3>binding, <3>storage, SMT
                DEF ReviewedSwiftEmissionIteration
        <2>add. CASE kind = "add"
            PROOF
            <3>reads. /\ frame.expanded /\ before.completed.count >= 2
                      /\ before.completed.items[before.completed.count - 2] = view.left[origin]
                      /\ before.completed.items[before.completed.count - 1] = view.right[origin]
                      /\ before.indices.count = count
                      /\ view.left[origin] \in 1..before.indices.count
                      /\ view.right[origin] \in 1..before.indices.count
                      /\ before.indices.items[view.left[origin] - 1] = state.current.inverse[view.left[origin]]
                      /\ before.indices.items[view.right[origin] - 1] = state.current.inverse[view.right[origin]]
                      /\ before.indices.items[view.left[origin] - 1] > 0
                      /\ before.indices.items[view.right[origin] - 1] > 0
                PROOF
                <4>bounds. /\ count \in Nat /\ state.completed.height \in Nat
                           /\ state.completed.height >= 2 /\ frame.expanded
                           /\ before.completed.count = state.completed.height
                           /\ before.indices.count = count
                           /\ view.left[origin] \in 1..count /\ view.right[origin] \in 1..count
                           /\ state.current.inverse[view.left[origin]] \in 1..state.current.emitted.count
                           /\ state.current.inverse[view.right[origin]] \in 1..state.current.emitted.count
                           /\ state.completed.terms[state.completed.height - 1] = view.left[origin]
                           /\ state.completed.terms[state.completed.height] = view.right[origin]
                    BY <1>guards, <2>shape, <2>add, SMT
                        DEF SwiftIndexedArray, CompilerOccurrenceTree, origin, frame, kind
                <4>offsets. /\ state.completed.height - 2 \in 0..(state.completed.height - 1)
                            /\ state.completed.height - 1 \in 0..(state.completed.height - 1)
                            /\ (state.completed.height - 2) + 1 = state.completed.height - 1
                            /\ (state.completed.height - 1) + 1 = state.completed.height
                            /\ view.left[origin] - 1 \in 0..(count - 1)
                            /\ view.right[origin] - 1 \in 0..(count - 1)
                            /\ (view.left[origin] - 1) + 1 = view.left[origin]
                            /\ (view.right[origin] - 1) + 1 = view.right[origin]
                    BY ONLY <4>bounds, SMT
                <4>completed. /\ before.completed.items[state.completed.height - 2] =
                                     state.completed.terms[state.completed.height - 1]
                              /\ before.completed.items[state.completed.height - 1] =
                                     state.completed.terms[state.completed.height]
                    BY ONLY <2>shape, <4>offsets DEF SwiftIndexedArray
                <4>indices. /\ before.indices.items[view.left[origin] - 1] =
                                   state.current.inverse[view.left[origin]]
                            /\ before.indices.items[view.right[origin] - 1] =
                                   state.current.inverse[view.right[origin]]
                    BY ONLY <2>shape, <4>offsets DEF SwiftIndexedArray
                <4>. QED BY ONLY <4>bounds, <4>completed, <4>indices, SMT
            <3>binding. /\ SwiftSourceArray(view, count).items[origin - 1] =
                            [kind |-> "add", payload |-> 0,
                             left |-> view.left[origin], right |-> view.right[origin]]
                        /\ node = [kind |-> "add", payload |-> 0,
                             left |-> state.current.inverse[view.left[origin]],
                             right |-> state.current.inverse[view.right[origin]]]
                BY <2>source, <2>add, SMT DEF node
            <3>storage. popped = [[before EXCEPT !.pending = SwiftArrayRemovingLast(before.pending)]
                        EXCEPT !.completed = SwiftArrayRemovingLast(SwiftArrayRemovingLast(before.completed))]
                BY <3>reads DEF popped, retained
            <3>types. /\ before.pending.count \in Nat /\ before.completed.count \in Nat
                      /\ before.indices.items[view.left[origin] - 1] \in Int
                      /\ before.indices.items[view.right[origin] - 1] \in Int
                BY <1>guards, <2>shape, <2>frame, <2>add, <3>reads, SMT
                    DEF SwiftIndexedArray, origin, kind
            <3>tests. /\ before.pending.count # 0
                      /\ ~(before.completed.count < 2)
                      /\ ~(before.indices.items[view.left[origin] - 1] <= 0)
                      /\ ~(before.indices.items[view.right[origin] - 1] <= 0)
                BY ONLY <3>types, <2>frame, <3>reads, SMT
            <3>. QED BY ONLY <2>shape, <2>frame, <2>add, <3>reads, <3>binding, <3>storage, <3>tests
                DEF ReviewedSwiftEmissionIteration
        <2>. QED BY ONLY <2>leaf, <2>add, SMT
    <1>pending. popped.pending = SwiftPendingArray(after.height, after.pending)
        PROOF
        <2>mode. /\ state.height \in Nat
                 /\ ~(view.kinds[origin] = "add" /\ ~frame.expanded)
            BY <1>guards, SMT DEF CompilerTraversalInvariant, CompilerOccurrenceStages, origin, frame, kind
        <2>projection. /\ popped.pending = SwiftArrayRemovingLast(SwiftPendingArray(state.height, state.pending))
                       /\ after.height = state.height - 1
                       /\ after.pending = HistoryPrefix(state.pending, state.height - 1)
            BY ONLY <2>mode DEF popped, before, after, CompilerTraversalNext,
                SwiftCompilerStorage, frame, origin
        <2>offsets. /\ (state.height - 1) - 1 = state.height - 2
                    /\ \A offset \in 0..(state.height - 2) : offset + 1 \in 1..(state.height - 1)
            BY ONLY <2>mode, SMT
        <2>. QED BY ONLY <2>mode, <2>projection, <2>offsets, SMT
            DEF SwiftArrayRemovingLast, SwiftPendingArray, HistoryPrefix
    <1>completed. SwiftArrayAppending(retained, origin) =
                     SwiftIndexedArray(after.completed.height, after.completed.terms)
        BY <1>guards, SMT DEF retained, before, after, origin, frame, kind,
            CompilerTraversalNext, SwiftCompilerStorage, SwiftIndexedArray,
            SwiftArrayRemovingLast, SwiftArrayAppending, VisitFrameExit, FoldVisitPrefix,
            PushVisitPrefix, VisitPrefix, HistoryAppend
    <1>nodes. SwiftArrayAppending(before.nodes, node) =
                 SwiftIndexedArray(after.current.emitted.count, after.current.emitted.nodes)
        PROOF
        <2>mode. /\ state.current.emitted.count \in Nat
                 /\ ~(view.kinds[origin] = "add" /\ ~frame.expanded)
            BY <1>guards, SMT DEF origin, frame, kind
        <2>projection. /\ before.nodes = SwiftIndexedArray(state.current.emitted.count, state.current.emitted.nodes)
                       /\ after.current.emitted.count = state.current.emitted.count + 1
                       /\ after.current.emitted.nodes = HistoryAppend(state.current.emitted.nodes,
                              state.current.emitted.count, node)
            BY ONLY <2>mode DEF before, after, CompilerTraversalNext, AppendCertificateConstructor,
                SwiftCompilerStorage, origin, frame, kind, node
        <2>offsets. /\ (state.current.emitted.count + 1) - 1 = state.current.emitted.count
                    /\ \A offset \in 0..state.current.emitted.count :
                        /\ offset + 1 \in 1..(state.current.emitted.count + 1)
                        /\ ((offset = state.current.emitted.count) \equiv
                              (offset + 1 = state.current.emitted.count + 1))
                        /\ (offset # state.current.emitted.count =>
                              offset \in 0..(state.current.emitted.count - 1))
            BY ONLY <2>mode, SMT
        <2>. QED BY ONLY <2>mode, <2>projection, <2>offsets, SMT
            DEF SwiftArrayAppending, SwiftIndexedArray, HistoryAppend
    <1>origins. SwiftArrayAppending(before.origins, origin) =
                   SwiftIndexedArray(after.current.emitted.count, after.current.emitted.origins)
        BY <1>guards, SMT DEF before, after, origin, frame, kind,
            CompilerTraversalNext, AppendCertificateConstructor, SwiftCompilerStorage,
            SwiftIndexedArray, SwiftArrayAppending, HistoryAppend
    <1>indices. SwiftArrayReplacing(before.indices, origin - 1, before.nodes.count + 1) =
                   SwiftIndexedArray(count, after.current.inverse)
        PROOF
        <2>mode. /\ count \in Nat /\ origin \in 1..count
                 /\ DOMAIN view.kinds = 1..count
                 /\ ~(view.kinds[origin] = "add" /\ ~frame.expanded)
            BY <1>guards, SMT DEF CompilerOccurrenceTree, origin, frame, kind
        <2>projection. /\ before.indices = SwiftIndexedArray(count, state.current.inverse)
                       /\ before.nodes.count = state.current.emitted.count
                       /\ after.current.inverse = [source \in 1..count |->
                              IF source = origin THEN state.current.emitted.count + 1
                              ELSE state.current.inverse[source]]
            BY ONLY <2>mode DEF before, after, CompilerTraversalNext, AppendCertificateConstructor,
                SwiftCompilerStorage, SwiftIndexedArray, origin, frame
        <2>offsets. \A offset \in 0..(count - 1) :
                    /\ offset + 1 \in 1..count
                    /\ ((offset = origin - 1) \equiv (offset + 1 = origin))
            BY ONLY <2>mode, SMT
        <2>. QED BY ONLY <2>projection, <2>offsets, SMT
            DEF SwiftArrayReplacing, SwiftIndexedArray
    <1>append. ReviewedSwiftAppendCertificate(popped, origin, node) =
                   SwiftCompilerStorage(view, count, after)
        PROOF
        <2>storage. /\ popped.nodes = before.nodes /\ popped.origins = before.origins
                    /\ popped.indices = before.indices /\ popped.completed = retained
                    /\ popped = [pending |-> popped.pending, nodes |-> before.nodes,
                         origins |-> before.origins, indices |-> before.indices,
                         completed |-> retained, control |-> "normal"]
            BY DEF popped, before, SwiftCompilerStorage
        <2>offset. /\ origin - 1 \in 0..(count - 1) /\ (origin - 1) + 1 = origin
            BY <1>guards, SMT DEF origin, CompilerOccurrenceTree
        <2>fresh. popped.indices.items[origin - 1] = 0
            BY ONLY <2>storage, <2>offset, <1>guards
                DEF before, SwiftCompilerStorage, SwiftIndexedArray, origin
        <2>tests. /\ origin \in 1..popped.indices.count
                  /\ ~(popped.nodes.count >= SwiftIntMax)
                  /\ ~(popped.origins.count >= SwiftIntMax)
                  /\ ~(popped.completed.count >= SwiftIntMax)
            BY <2>storage, <1>guards, <1>safe, <1>counts, IntegerDomain, SMT
                DEF ReviewedEmissionOperationSafety, origin, IntegerDomain
        <2>newCount. SwiftArrayAppending(popped.nodes, node).count = before.nodes.count + 1
            BY ONLY <2>storage DEF SwiftArrayAppending
        <2>result. ReviewedSwiftAppendCertificate(popped, origin, node) =
            [pending |-> popped.pending, nodes |-> SwiftArrayAppending(before.nodes, node),
             origins |-> SwiftArrayAppending(before.origins, origin),
             indices |-> SwiftArrayReplacing(before.indices, origin - 1, before.nodes.count + 1),
             completed |-> SwiftArrayAppending(retained, origin), control |-> "normal"]
            PROOF
            <3>shape. popped = [pending |-> SwiftArrayRemovingLast(before.pending),
                          nodes |-> before.nodes, origins |-> before.origins,
                          indices |-> before.indices, completed |-> retained, control |-> "normal"]
                BY DEF popped, before, SwiftCompilerStorage
            <3>branch. ReviewedSwiftAppendCertificate(popped, origin, node) =
                [popped EXCEPT !.nodes = SwiftArrayAppending(popped.nodes, node),
                    !.origins = SwiftArrayAppending(popped.origins, origin),
                    !.indices = SwiftArrayReplacing(popped.indices, origin - 1,
                                   SwiftArrayAppending(popped.nodes, node).count),
                    !.completed = SwiftArrayAppending(popped.completed, origin)]
                BY ONLY <2>fresh, <2>tests DEF ReviewedSwiftAppendCertificate
            <3>record. [popped EXCEPT !.nodes = SwiftArrayAppending(popped.nodes, node),
                    !.origins = SwiftArrayAppending(popped.origins, origin),
                    !.indices = SwiftArrayReplacing(popped.indices, origin - 1,
                                   SwiftArrayAppending(popped.nodes, node).count),
                    !.completed = SwiftArrayAppending(popped.completed, origin)] =
                [pending |-> popped.pending, nodes |-> SwiftArrayAppending(before.nodes, node),
                 origins |-> SwiftArrayAppending(before.origins, origin),
                 indices |-> SwiftArrayReplacing(before.indices, origin - 1, before.nodes.count + 1),
                 completed |-> SwiftArrayAppending(retained, origin), control |-> "normal"]
                PROOF
                <4>. DEFINE updated == [popped EXCEPT !.nodes = SwiftArrayAppending(popped.nodes, node),
                                !.origins = SwiftArrayAppending(popped.origins, origin),
                                !.indices = SwiftArrayReplacing(popped.indices, origin - 1,
                                               SwiftArrayAppending(popped.nodes, node).count),
                                !.completed = SwiftArrayAppending(popped.completed, origin)]
                            target == [pending |-> popped.pending, nodes |-> SwiftArrayAppending(before.nodes, node),
                                origins |-> SwiftArrayAppending(before.origins, origin),
                                indices |-> SwiftArrayReplacing(before.indices, origin - 1, before.nodes.count + 1),
                                completed |-> SwiftArrayAppending(retained, origin), control |-> "normal"]
                <4>domains. /\ DOMAIN updated = {"pending", "nodes", "origins", "indices", "completed", "control"}
                            /\ DOMAIN target = {"pending", "nodes", "origins", "indices", "completed", "control"}
                    BY ONLY <3>shape DEF updated, target
                <4>pending. updated.pending = target.pending
                    BY ONLY <3>shape DEF updated, target
                <4>nodes. updated.nodes = target.nodes
                    BY ONLY <3>shape DEF updated, target
                <4>origins. updated.origins = target.origins
                    BY ONLY <3>shape DEF updated, target
                <4>indices. updated.indices = target.indices
                    BY ONLY <3>shape, <2>newCount DEF updated, target
                <4>completed. updated.completed = target.completed
                    BY ONLY <3>shape DEF updated, target
                <4>control. updated.control = target.control
                    BY ONLY <3>shape DEF updated, target
                <4>. QED BY ONLY <4>domains, <4>pending, <4>nodes, <4>origins,
                    <4>indices, <4>completed, <4>control, SMT DEF updated, target
            <3>. QED BY ONLY <3>branch, <3>record
        <2>. QED BY ONLY <2>result, <1>pending, <1>completed, <1>nodes, <1>origins, <1>indices
            DEF SwiftCompilerStorage
    <1>. QED BY <1>safe, <1>selected, <1>append DEF ReviewedEmissionMatchesTraversal, before, after

ReviewedSwiftCertificateReturn(source, storage) ==
    IF storage.completed.count # 1 THEN [control |-> "reject"]
    ELSE IF storage.completed.items[0] # 1 THEN [control |-> "reject"]
    ELSE IF \E offset \in 0..(storage.indices.count - 1) : storage.indices.items[offset] = 0
         THEN [control |-> "reject"]
    ELSE IF storage.origins.count = 0 THEN [control |-> "reject"]
    ELSE IF storage.origins.items[storage.origins.count - 1] # 1 THEN [control |-> "reject"]
    ELSE [control |-> "return", certificate |->
        [source |-> source, nodes |-> storage.nodes, origins |-> storage.origins, indices |-> storage.indices]]

ReviewedReturnMatchesCertificate(view, count, final) ==
    ReviewedSwiftCertificateReturn(SwiftSourceArray(view, count), SwiftCompilerStorage(view, count, final)) =
        [control |-> "return", certificate |->
            [source |-> SwiftSourceArray(view, count),
             nodes |-> SwiftIndexedArray(final.current.emitted.count, final.current.emitted.nodes),
             origins |-> SwiftIndexedArray(final.current.emitted.count, final.current.emitted.origins),
             indices |-> SwiftIndexedArray(count, final.current.inverse)]]

THEOREM TerminatedCompilerInvariantDerivesEveryReturnGuard ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW final, CompilerTraversalInvariant(view, final), final.height = 0
    PROVE /\ final.completed.height = 1 /\ final.completed.terms[1] = 1
          /\ \A origin \in 1..count : final.current.inverse[origin] > 0
          /\ final.current.emitted.count > 0
          /\ final.current.emitted.origins[final.current.emitted.count] = 1
          /\ ReviewedReturnMatchesCertificate(view, count, final)
    PROOF
    <1>covered. final.done = DOMAIN view.kinds
        BY EmptyCompilerPendingStackHasEmittedEveryOccurrence DEF CompilerTraversalInvariant
    <1>completed. /\ final.completed.height = 1 /\ final.completed.terms[1] = 1
        BY SMT DEF CompilerOccurrenceTree, CompilerTraversalInvariant, PendingVisitContract,
            PushVisitPrefix, EmptyVisitPrefix, VisitPrefix, HistoryAppend
    <1>indices. \A origin \in 1..count : final.current.inverse[origin] > 0
        BY <1>covered, SMT DEF CompilerOccurrenceTree, CompilerTraversalInvariant
    <1>last. /\ final.current.emitted.count > 0
              /\ final.current.emitted.origins[final.current.emitted.count] = 1
        BY <1>completed, SMT DEF CompilerTraversalInvariant, CompletedCertificateRoots,
            CertificateConstructionInvariant, NodeEmissionArrays
    <1>return. ReviewedReturnMatchesCertificate(view, count, final)
        PROOF
        <2>. DEFINE storage == SwiftCompilerStorage(view, count, final)
        <2>shape. /\ storage.completed = SwiftIndexedArray(1, final.completed.terms)
                  /\ storage.indices = SwiftIndexedArray(count, final.current.inverse)
                  /\ storage.indices.count = count
                  /\ storage.origins = SwiftIndexedArray(final.current.emitted.count, final.current.emitted.origins)
            BY ONLY <1>completed DEF storage, SwiftCompilerStorage, SwiftIndexedArray
        <2>types. /\ count \in Nat /\ final.current.emitted.count \in Nat
                  /\ final.current.emitted.count > 0
            BY <1>last, SMT DEF CompilerOccurrenceTree, CompilerTraversalInvariant,
                CertificateConstructionInvariant, NodeEmissionArrays
        <2>offsets. /\ final.current.emitted.count - 1 \in 0..(final.current.emitted.count - 1)
                    /\ (final.current.emitted.count - 1) + 1 = final.current.emitted.count
                    /\ \A offset \in 0..(count - 1) : offset + 1 \in 1..count
            BY ONLY <2>types, SMT
        <2>completed. /\ storage.completed.count = 1 /\ storage.completed.items[0] = 1
            BY ONLY <2>shape, <1>completed DEF SwiftIndexedArray
        <2>noZero. ~(\E offset \in 0..(storage.indices.count - 1) : storage.indices.items[offset] = 0)
            PROOF
            <3>positive. \A offset \in 0..(count - 1) : storage.indices.items[offset] > 0
                BY ONLY <2>shape, <2>offsets, <1>indices DEF SwiftIndexedArray
            <3>. QED BY ONLY <3>positive, <2>shape, SMT
        <2>last. /\ storage.origins.count > 0
                 /\ storage.origins.items[storage.origins.count - 1] = 1
            BY ONLY <2>shape, <2>types, <2>offsets, <1>last DEF SwiftIndexedArray
        <2>decision. ReviewedSwiftCertificateReturn(SwiftSourceArray(view, count), storage) =
            [control |-> "return", certificate |->
                [source |-> SwiftSourceArray(view, count),
                 nodes |-> storage.nodes, origins |-> storage.origins, indices |-> storage.indices]]
            BY ONLY <2>completed, <2>noZero, <2>last DEF ReviewedSwiftCertificateReturn
        <2>. QED BY ONLY <2>decision DEF ReviewedReturnMatchesCertificate, storage, SwiftCompilerStorage
    <1>. QED BY <1>completed, <1>indices, <1>last, <1>return


THEOREM EmittingACompilerFramePreservesAllLoopInvariants ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW state, CompilerTraversalInvariant(view, state), state.height > 0,
           state.pending[state.height].expanded \/ view.kinds[state.pending[state.height].node] # "add"
    PROVE /\ CompilerTraversalInvariant(view, CompilerTraversalNext(view, state))
          /\ (state.height <= SwiftIntMax /\ count <= SwiftIntMax /\
                state.current.emitted.count + 1 <= SwiftIntMax /\
                state.completed.height + 1 <= SwiftIntMax =>
                 /\ ReviewedEmissionOperationSafety(view, count, state)
                 /\ ReviewedEmissionMatchesTraversal(view, count, state))
    PROOF
    <1>. DEFINE frame == state.pending[state.height]
                origin == frame.node
                after == AppendCertificateConstructor(view, state.current, origin)
                completed == VisitFrameExit(frame)
    <1>1. /\ frame.node \in DOMAIN view.kinds /\ frame.expanded \in BOOLEAN
          /\ state.current.inverse[frame.node] = 0
          /\ (frame.expanded => view.kinds[frame.node] = "add")
          /\ (~frame.expanded => frame.node \notin state.opened)
        BY PendingCompilerFramesHaveFreshEmissionOrigins DEF CompilerTraversalInvariant, frame
    <1>2. (frame.expanded /\ view.kinds[origin] = "add")
              \/ (~frame.expanded /\ view.kinds[origin] \in {"literal", "read"})
        BY <1>1, SMT DEF CompilerOccurrenceTree, frame, origin
    <1>3. LET after == AppendCertificateConstructor(view, state.current, state.pending[state.height].node)
              nextCompleted == VisitFrameExit(state.pending[state.height])
          IN /\ PendingVisitContract(state.height - 1, HistoryPrefix(state.pending, state.height - 1),
                    nextCompleted, PushVisitPrefix(EmptyVisitPrefix, view.root), view.left, view.right)
             /\ CertificateConstructionInvariant(view, after)
             /\ CompletedCertificateRoots(view, after, nextCompleted)
        BY <1>1, <1>2, EmittingACompilerFramePreservesLoopInvariants
            DEF CompilerTraversalInvariant, frame, origin
    <1>4. CompilerOccurrenceStages(view, state.height - 1, HistoryPrefix(state.pending, state.height - 1),
              state.opened, state.done \cup {state.pending[state.height].node})
        BY EmittingACompilerNodePreservesOccurrenceStages DEF CompilerTraversalInvariant
    <1>5. /\ state.current.emitted.count \in Nat
          /\ state.completed = frame.prefix /\ WellFormedVisitPrefix(state.completed)
          /\ (frame.expanded => state.completed.height >= 2)
        BY SMT DEF CompilerTraversalInvariant, CertificateConstructionInvariant, NodeEmissionArrays,
            PendingVisitContract, WellFormedVisitFrame, frame
    <1>6. \A node \in DOMAIN view.kinds : (after.inverse[node] > 0) \equiv (node \in state.done \cup {origin})
        BY <1>1, <1>5, SMT DEF after, AppendCertificateConstructor, CompilerTraversalInvariant
    <1>7. /\ completed.height > 0
          /\ completed.terms[completed.height] = origin
          /\ after.emitted.origins[after.emitted.count] = origin
        BY <1>1, <1>5, SMT DEF completed, after, origin, VisitFrameExit, FoldVisitPrefix,
            PushVisitPrefix, VisitPrefix, HistoryAppend, AppendCertificateConstructor, WellFormedVisitPrefix
    <1>reviewed. state.height <= SwiftIntMax /\ count <= SwiftIntMax /\
                    state.current.emitted.count + 1 <= SwiftIntMax /\
                    state.completed.height + 1 <= SwiftIntMax =>
                     /\ ReviewedEmissionOperationSafety(view, count, state)
                     /\ ReviewedEmissionMatchesTraversal(view, count, state)
        BY ReviewedEmissionDerivesTraversalStep, SMT
    <1>. QED BY <1>1, <1>3, <1>4, <1>6, <1>7, <1>reviewed, SMT
        DEF CompilerTraversalInvariant, CompilerTraversalNext, frame, origin, after, completed


THEOREM CompilerTraversalStepPreservesInvariantsAndMakesProgress ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW state, CompilerTraversalInvariant(view, state), state.height > 0
    PROVE LET next == CompilerTraversalNext(view, state)
              task == <<state.pending[state.height].node, state.pending[state.height].expanded>>
              remaining == CompilerRemainingTasks(view, state.opened, state.done)
          IN /\ CompilerTraversalInvariant(view, next)
             /\ task \in remaining
             /\ CompilerRemainingTasks(view, next.opened, next.done) = remaining \ {task}
    PROOF
    <1>. DEFINE origin == state.pending[state.height].node
                expanded == state.pending[state.height].expanded
                next == CompilerTraversalNext(view, state)
                remaining == CompilerRemainingTasks(view, state.opened, state.done)
    <1>1. /\ origin \in DOMAIN view.kinds /\ expanded \in BOOLEAN
          /\ state.current.inverse[origin] = 0
          /\ (expanded => view.kinds[origin] = "add")
          /\ (~expanded => origin \notin state.opened)
        BY PendingCompilerFramesHaveFreshEmissionOrigins DEF origin, expanded, CompilerTraversalInvariant
    <1>2. /\ origin \notin state.done
          /\ (expanded => origin \in state.opened)
        BY <1>1, SMT DEF origin, expanded, CompilerTraversalInvariant,
            CompilerOccurrenceStages, CompilerPendingTasks, CompilerExpectedTasks
    <1>3. CASE view.kinds[origin] = "add" /\ ~expanded
        PROOF
        <2>1. CompilerTraversalInvariant(view, next)
            BY <1>3, ExpandingACompilerFramePreservesAllLoopInvariants DEF origin, expanded, next
        <2>2. /\ <<origin, FALSE>> \in remaining
              /\ CompilerRemainingTasks(view, state.opened \cup {origin}, state.done) =
                   remaining \ {<<origin, FALSE>>}
            BY <1>1, <1>2, <1>3, CompilerTaskExpansionStrictlyRemovesOneRemainingTask DEF remaining
        <2>. QED BY <1>1, <1>3, <2>1, <2>2, SMT DEF next, remaining, CompilerTraversalNext, origin, expanded
    <1>4. CASE ~(view.kinds[origin] = "add" /\ ~expanded)
        PROOF
        <2>1. expanded \/ view.kinds[origin] # "add"
            BY <1>1, <1>4, SMT
        <2>2. CompilerTraversalInvariant(view, next)
            BY <2>1, EmittingACompilerFramePreservesAllLoopInvariants DEF origin, expanded, next
        <2>3. IF expanded THEN origin \in state.opened /\ view.kinds[origin] = "add"
              ELSE origin \notin state.opened /\ view.kinds[origin] # "add"
            BY ONLY <1>1, <1>2, <2>1, SMT
        <2>4. /\ <<origin, expanded>> \in remaining
              /\ CompilerRemainingTasks(view, state.opened, state.done \cup {origin}) =
                   remaining \ {<<origin, expanded>>}
            BY <1>1, <1>2, <2>3, CompilerTaskEmissionStrictlyRemovesOneRemainingTask DEF remaining
        <2>. QED BY <1>4, <2>2, <2>4, SMT DEF next, remaining, CompilerTraversalNext, origin, expanded
    <1>. QED BY <1>3, <1>4

CompilerTraversalCompletion(view, initial, steps, history) ==
    /\ steps \in Nat
    /\ history[0] = initial
    /\ \A step \in 1..steps :
        /\ history[step - 1].height > 0
        /\ history[step] = CompilerTraversalNext(view, history[step - 1])
    /\ history[steps].height = 0
    /\ CompilerTraversalInvariant(view, history[steps])

THEOREM FiniteCompilerTasksConstructATerminatingTraversal ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW initial, CompilerTraversalInvariant(view, initial)
    PROVE \E steps, history : CompilerTraversalCompletion(view, initial, steps, history)
    PROOF
    <1>. DEFINE initialTasks == CompilerRemainingTasks(view, initial.opened, initial.done)
                completes(tasks) == \A state :
                    (CompilerTraversalInvariant(view, state) /\
                     CompilerRemainingTasks(view, state.opened, state.done) = tasks)
                    => \E steps, history : CompilerTraversalCompletion(view, state, steps, history)
    <1>1. LayoutNamesFS!IsFiniteSet(initialTasks)
        BY CompilerRemainingTaskCountIsFinite DEF initialTasks
    <1>2. ASSUME NEW tasks \in SUBSET initialTasks,
                 \A smaller \in (SUBSET tasks) \ {tasks} : completes(smaller)
          PROVE completes(tasks)
        PROOF
        <2>. SUFFICES ASSUME NEW state, CompilerTraversalInvariant(view, state),
                             CompilerRemainingTasks(view, state.opened, state.done) = tasks
                     PROVE \E steps, history : CompilerTraversalCompletion(view, state, steps, history)
            BY SMT DEF completes
        <2>1. state.height \in Nat
            BY DEF CompilerTraversalInvariant, CompilerOccurrenceStages
        <2>2. CASE state.height = 0
            PROOF
            <3>1. CompilerTraversalCompletion(view, state, 0, [step \in 0..0 |-> state])
                BY <2>2, SMT DEF CompilerTraversalCompletion
            <3>. QED BY <3>1, SMT
        <2>3. CASE state.height # 0
            PROOF
            <3>. DEFINE next == CompilerTraversalNext(view, state)
                        task == <<state.pending[state.height].node, state.pending[state.height].expanded>>
                        smaller == CompilerRemainingTasks(view, next.opened, next.done)
            <3>1. state.height > 0 BY <2>1, <2>3, SMT
            <3>2. /\ CompilerTraversalInvariant(view, next)
                  /\ task \in tasks /\ smaller = tasks \ {task}
                BY <3>1, CompilerTraversalStepPreservesInvariantsAndMakesProgress
                    DEF next, task, smaller
            <3>3. smaller \in (SUBSET tasks) \ {tasks}
                BY ONLY <3>2, SMT
            <3>4. completes(smaller)
                BY <3>3, (\A smaller \in (SUBSET tasks) \ {tasks} : completes(smaller)), SMT
            <3>5. PICK steps, history : CompilerTraversalCompletion(view, next, steps, history)
                BY <3>2, <3>4, SMT DEF completes, smaller
            <3>. DEFINE extended == [step \in 0..(steps + 1) |-> IF step = 0 THEN state ELSE history[step - 1]]
            <3>6. /\ steps \in Nat /\ extended[0] = state /\ extended[1] = next
                  /\ extended[steps + 1] = history[steps]
                BY <3>5, SMT DEF extended, CompilerTraversalCompletion
            <3>7. \A step \in 1..(steps + 1) :
                      /\ extended[step - 1].height > 0
                      /\ extended[step] = CompilerTraversalNext(view, extended[step - 1])
                BY <3>1, <3>5, <3>6, SMT DEF extended, CompilerTraversalCompletion, next
            <3>8. CompilerTraversalCompletion(view, state, steps + 1, extended)
                BY <3>5, <3>6, <3>7, SMT DEF CompilerTraversalCompletion
            <3>. QED BY <3>8, SMT
        <2>. QED BY <2>2, <2>3
    <1>3. HIDE DEF completes
    <1>4. completes(initialTasks)
        BY <1>1, <1>2, LayoutNamesFS!FS_WFInduction, IsaM("blast")
    <1>. QED BY <1>4, SMT DEF completes, initialTasks

THEOREM TerminatedCompilerTraversalSuppliesTheCertificate ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW bound, CertificateSource(view, bound), NEW fallback \in Keys,
           NEW final, CompilerTraversalInvariant(view, final), final.height = 0
    PROVE /\ LiteralReadAddCertificate(view, final.current.emitted, final.current.inverse, fallback, bound)
          /\ ReviewedReturnMatchesCertificate(view, count, final)
    PROOF
    <1>guards. /\ \A origin \in DOMAIN view.kinds : final.current.inverse[origin] > 0
               /\ final.current.emitted.count > 0
               /\ final.current.emitted.origins[final.current.emitted.count] = view.root
               /\ ReviewedReturnMatchesCertificate(view, count, final)
        BY TerminatedCompilerInvariantDerivesEveryReturnGuard, SMT DEF CompilerOccurrenceTree
    <1>invariant. CertificateConstructionInvariant(view, final.current)
        BY DEF CompilerTraversalInvariant
    <1>typed. TypedVisitedSourceInputs(view, final.current.emitted)
        BY <1>invariant, SMT DEF CertificateConstructionInvariant, CertificateSource, TypedVisitedSourceInputs
    <1>. QED BY <1>guards, <1>invariant, <1>typed, SMT DEF LiteralReadAddCertificate,
        CertificateConstructionInvariant, CertificateSource, AllNodePayloadsMatchSource, NodePayloadMatchesSource


THEOREM OccurrenceTreeTraversalConstructsAValidCertificate ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW bound, CertificateSource(view, bound), NEW fallback \in Keys
    PROVE \E steps, history :
              /\ CompilerTraversalCompletion(view, InitialCompilerTraversal(view), steps, history)
              /\ LiteralReadAddCertificate(view, history[steps].current.emitted,
                     history[steps].current.inverse, fallback, bound)
    PROOF
    <1>1. CompilerTraversalInvariant(view, InitialCompilerTraversal(view))
        BY CompilerTraversalStartsWithItsLoopInvariants
    <1>2. PICK steps, history : CompilerTraversalCompletion(view, InitialCompilerTraversal(view), steps, history)
        BY <1>1, FiniteCompilerTasksConstructATerminatingTraversal
    <1>3. LiteralReadAddCertificate(view, history[steps].current.emitted,
              history[steps].current.inverse, fallback, bound)
        BY <1>2, TerminatedCompilerTraversalSuppliesTheCertificate DEF CompilerTraversalCompletion
    <1>. QED BY <1>2, <1>3, SMT

\* Insert after OccurrenceTreeTraversalConstructsAValidCertificate.
\* Candidate only: no diagnostic has been run.

THEOREM CompilerTraversalArraysFitTheirOccurrenceTree ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW state, CompilerTraversalInvariant(view, state)
    PROVE /\ state.height <= count
          /\ state.current.emitted.count <= count
    PROOF
    <1>. DEFINE pendingOrigins == [index \in 1..state.height |-> state.pending[index].node]
                emittedOrigins == state.current.emitted.origins
                emittedCount == state.current.emitted.count
    <1>1. /\ count \in Nat \ {0} /\ state.height \in Nat /\ emittedCount \in Nat
          /\ DOMAIN view.kinds = 1..count
        BY SMT DEF CompilerOccurrenceTree, CompilerTraversalInvariant,
            CompilerOccurrenceStages, CertificateConstructionInvariant, NodeEmissionArrays, emittedCount
    <1>2. /\ LayoutNamesFS!IsFiniteSet(1..count)
          /\ LayoutNamesFS!Cardinality(1..count) = count
          /\ LayoutNamesFS!Cardinality(1..state.height) = state.height
          /\ LayoutNamesFS!Cardinality(1..emittedCount) = emittedCount
        BY <1>1, LayoutNamesFS!FS_Interval, SMT
    <1>3. \A index \in 1..state.height :
          /\ state.pending[index].node \in 1..count
          /\ (state.pending[index].expanded \equiv state.pending[index].node \in state.opened)
        BY <1>1, SMT DEF CompilerTraversalInvariant, CompilerOccurrenceStages,
            CompilerPendingTasks, CompilerExpectedTasks, CompilerScheduledOccurrences, CompilerOccurrenceTree
    <1>4. \A first, second \in 1..state.height :
              pendingOrigins[first] = pendingOrigins[second] => first = second
        PROOF
        <2>. SUFFICES ASSUME NEW first \in 1..state.height,
                             NEW second \in 1..state.height,
                             pendingOrigins[first] = pendingOrigins[second]
                     PROVE first = second
            BY SMT
        <2>tasks. /\ <<state.pending[first].node, state.pending[first].expanded>>
                         \in CompilerExpectedTasks(view, state.opened, state.done)
                   /\ <<state.pending[second].node, state.pending[second].expanded>>
                         \in CompilerExpectedTasks(view, state.opened, state.done)
            BY SMT DEF CompilerTraversalInvariant, CompilerOccurrenceStages, CompilerPendingTasks
        <2>bits. /\ state.pending[first].expanded \in BOOLEAN
                  /\ state.pending[second].expanded \in BOOLEAN
            BY ONLY <2>tasks, SMT DEF CompilerExpectedTasks
        <2>nodes. state.pending[first].node = state.pending[second].node
            BY ONLY first \in 1..state.height, second \in 1..state.height,
                pendingOrigins[first] = pendingOrigins[second], SMT DEF pendingOrigins
        <2>expanded. state.pending[first].expanded = state.pending[second].expanded
            BY ONLY <1>3, <2>bits, <2>nodes,
                first \in 1..state.height, second \in 1..state.height
        <2>. QED BY <2>nodes, <2>expanded, SMT
            DEF CompilerTraversalInvariant, CompilerOccurrenceStages
    <1>5. pendingOrigins \in LayoutNamesFS!Injection(1..state.height, 1..count)
        BY <1>3, <1>4, SMT DEF pendingOrigins,
            LayoutNamesFS!Injection, LayoutNamesFS!IsInjective
    <1>6. LayoutNamesFS!Cardinality(1..state.height) <= LayoutNamesFS!Cardinality(1..count)
        BY <1>2, <1>5, LayoutNamesFS!FS_Injection
    <1>7. /\ emittedOrigins \in [1..emittedCount -> 1..count]
          /\ \A first, second \in 1..emittedCount :
                  emittedOrigins[first] = emittedOrigins[second] => first = second
        BY <1>1, SMT DEF CompilerTraversalInvariant, CertificateConstructionInvariant,
            emittedOrigins, emittedCount
    <1>8. emittedOrigins \in LayoutNamesFS!Injection(1..emittedCount, 1..count)
        BY <1>7, SMT DEF LayoutNamesFS!Injection, LayoutNamesFS!IsInjective
    <1>9. LayoutNamesFS!Cardinality(1..emittedCount) <= LayoutNamesFS!Cardinality(1..count)
        BY <1>2, <1>8, LayoutNamesFS!FS_Injection
    <1>. QED BY <1>2, <1>6, <1>9 DEF emittedCount

THEOREM CompilerTraversalStepBoundsItsCompletedStorage ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW state, CompilerTraversalInvariant(view, state), state.height > 0,
           state.completed.height <= state.current.emitted.count
    PROVE LET next == CompilerTraversalNext(view, state)
          IN next.completed.height <= next.current.emitted.count
    PROOF
    <1>. DEFINE frame == state.pending[state.height]
    <1>1. /\ state.completed = frame.prefix
          /\ frame.expanded \in BOOLEAN
          /\ (frame.expanded => state.completed.height >= 2)
        BY SMT DEF frame, CompilerTraversalInvariant, PendingVisitContract, WellFormedVisitFrame
    <1>types. /\ state.completed.height \in Nat
               /\ state.current.emitted.count \in Nat
        BY SMT DEF CompilerTraversalInvariant, CompletedCertificateRoots,
            WellFormedVisitPrefix, CertificateConstructionInvariant, NodeEmissionArrays
    <1>completed. CompilerTraversalNext(view, state).completed.height =
        IF view.kinds[frame.node] = "add" /\ ~frame.expanded THEN state.completed.height
        ELSE IF frame.expanded THEN state.completed.height - 1 ELSE state.completed.height + 1
        BY ONLY <1>1 DEF CompilerTraversalNext, VisitFrameExit,
            PushVisitPrefix, FoldVisitPrefix, VisitPrefix, frame
    <1>emitted. CompilerTraversalNext(view, state).current.emitted.count =
        IF view.kinds[frame.node] = "add" /\ ~frame.expanded THEN state.current.emitted.count
        ELSE state.current.emitted.count + 1
        BY DEF CompilerTraversalNext, AppendCertificateConstructor, frame
    <1>. QED BY ONLY <1>1, <1>types, <1>completed, <1>emitted,
        state.completed.height <= state.current.emitted.count, SMT

\* A prefix contains only the initialized seed and actual one-step equations.
\* It does not assume termination, successful guards, output validity or coverage.
CompilerTraversalPrefix(view, steps, history) ==
    /\ steps \in Nat
    /\ history[0] = InitialCompilerTraversal(view)
    /\ \A step \in 1..steps :
        /\ history[step - 1].height > 0
        /\ history[step] = CompilerTraversalNext(view, history[step - 1])

THEOREM CompilerTraversalPrefixesDeriveStorageBounds ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count),
           NEW steps, NEW history, CompilerTraversalPrefix(view, steps, history)
    PROVE \A step \in 0..steps :
          /\ CompilerTraversalInvariant(view, history[step])
          /\ history[step].height <= count
          /\ history[step].current.emitted.count <= count
          /\ history[step].completed.height <= history[step].current.emitted.count
    PROOF
    <1>. DEFINE holds(step) ==
                /\ CompilerTraversalInvariant(view, history[step])
                /\ history[step].completed.height <= history[step].current.emitted.count
    <1>1. holds(0)
        BY CompilerTraversalStartsWithItsLoopInvariants, SMT DEF holds,
            CompilerTraversalPrefix, InitialCompilerTraversal, EmptyVisitPrefix,
            VisitPrefix, EmptyCertificateConstruction, EmptyNodeEmission
    <1>2. \A step \in 1..steps :
              (\A prior \in 0..(step - 1) : holds(prior)) => holds(step)
        PROOF
        <2>. SUFFICES ASSUME NEW step \in 1..steps,
                             \A prior \in 0..(step - 1) : holds(prior)
                     PROVE holds(step)
            BY SMT
        <2>1. /\ holds(step - 1)
              /\ history[step - 1].height > 0
              /\ history[step] = CompilerTraversalNext(view, history[step - 1])
            BY SMT DEF CompilerTraversalPrefix
        <2>2. CompilerTraversalInvariant(view, history[step])
            BY <2>1, CompilerTraversalStepPreservesInvariantsAndMakesProgress DEF holds
        <2>3. history[step].completed.height <= history[step].current.emitted.count
            BY <2>1, CompilerTraversalStepBoundsItsCompletedStorage DEF holds
        <2>. QED BY <2>2, <2>3 DEF holds
    <1>3. steps \in Nat BY DEF CompilerTraversalPrefix
    <1>4. \A step \in 0..steps : holds(step)
        BY <1>1, <1>2, <1>3, FiniteIndexedPrefixProperty
    <1>. QED BY <1>4, CompilerTraversalArraysFitTheirOccurrenceTree, SMT DEF holds

\* Append after 01-traversal-storage-bounds.tla and emission's reviewed operations.
\* Candidate only: no diagnostic has been run.
\* Reviewed Swift mapping: initial value arrays, then each pop/switch iteration;
\* `continue` returns to the same loop boundary with all other storage unchanged.
\* Array allocation success is an operational resource contract. It is neither a
\* model failure nor an extra restriction on the accepted StateExpr constructors.
ReviewedSwiftTraversalInitialization(source) ==
    [pending |-> [count |-> 1, items |-> [offset \in 0..0 |-> <<1, FALSE>>]],
     nodes |-> [count |-> 0, items |-> [offset \in 0..-1 |-> 0]],
     origins |-> [count |-> 0, items |-> [offset \in 0..-1 |-> 0]],
     indices |-> [count |-> source.count, items |-> [offset \in 0..(source.count - 1) |-> 0]],
     completed |-> [count |-> 0, items |-> [offset \in 0..-1 |-> 0]],
     control |-> "normal"]

ReviewedSwiftCompilerIteration(source, storage) ==
    IF storage.pending.count = 0 THEN [storage EXCEPT !.control = "exit"]
    ELSE LET frame == storage.pending.items[storage.pending.count - 1]
         IN IF frame[1] \notin 1..source.count
            THEN [storage EXCEPT !.control = "indexFailure"]
            ELSE IF source.items[frame[1] - 1].kind = "add" /\ ~frame[2]
                 THEN LET expansion == ReviewedSwiftExpansionIteration(storage.pending, source, storage)
                      IN IF expansion.control = "continue"
                         THEN [storage EXCEPT !.pending = expansion.pending]
                         ELSE [storage EXCEPT !.pending = expansion.pending, !.control = expansion.control]
                 ELSE ReviewedSwiftEmissionIteration(source, storage)

THEOREM ReviewedArrayInitializationStartsTheCompilerTraversal ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count)
    PROVE ReviewedSwiftTraversalInitialization(SwiftSourceArray(view, count)) =
              SwiftCompilerStorage(view, count, InitialCompilerTraversal(view))
    BY SMT DEF ReviewedSwiftTraversalInitialization, SwiftSourceArray, SwiftCompilerStorage,
        SwiftPendingArray, SwiftIndexedArray, InitialCompilerTraversal, VisitFrame,
        EmptyVisitPrefix, VisitPrefix, EmptyCertificateConstruction, EmptyNodeEmission,
        CompilerOccurrenceTree

THEOREM ReviewedCompilerIterationDerivesTraversalStep ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count), count <= SwiftIntMax,
           NEW state, CompilerTraversalInvariant(view, state), state.height > 0,
           state.completed.height <= state.current.emitted.count
    PROVE /\ ReviewedSwiftCompilerIteration(SwiftSourceArray(view, count),
                 SwiftCompilerStorage(view, count, state)) =
                 SwiftCompilerStorage(view, count, CompilerTraversalNext(view, state))
          /\ LET frame == state.pending[state.height]
             IN IF view.kinds[frame.node] = "add" /\ ~frame.expanded
                THEN ReviewedExpansionOperationSafety(view, count, state)
                ELSE ReviewedEmissionOperationSafety(view, count, state)
    PROOF
    <1>. DEFINE next == CompilerTraversalNext(view, state)
                frame == state.pending[state.height]
                origin == frame.node
                expands == view.kinds[origin] = "add" /\ ~frame.expanded
    <1>invariant. CompilerTraversalInvariant(view, next)
        BY CompilerTraversalStepPreservesInvariantsAndMakesProgress DEF next
    <1>before. /\ state.height <= count /\ state.current.emitted.count <= count
        BY CompilerTraversalArraysFitTheirOccurrenceTree
    <1>after. /\ next.height <= count /\ next.current.emitted.count <= count
        BY <1>invariant, CompilerTraversalArraysFitTheirOccurrenceTree
    <1>origin. /\ origin \in 1..count /\ frame.expanded \in BOOLEAN
        BY PendingCompilerFramesHaveFreshEmissionOrigins, SMT
            DEF CompilerTraversalInvariant, CompilerOccurrenceTree, origin, frame
    <1>expand. CASE expands
        PROOF
        <2>capacity. state.height + 2 <= SwiftIntMax
            PROOF
            <3>height. next.height = state.height + 2
                BY ONLY <1>expand DEF next, CompilerTraversalNext, expands, origin, frame
            <3>types. /\ state.height \in Nat /\ count \in Nat /\ SwiftIntMax \in Int
                BY IntegerDomain, SMT DEF CompilerTraversalInvariant,
                    CompilerOccurrenceStages, CompilerOccurrenceTree, IntegerDomain
            <3>. QED BY ONLY <1>after, <3>height, <3>types, count <= SwiftIntMax, SMT
        <2>step. /\ ReviewedExpansionOperationSafety(view, count, state)
                  /\ ReviewedExpansionMatchesTraversal(view, count, state,
                         SwiftCompilerStorage(view, count, state))
            BY <1>expand, <2>capacity, ExpandingACompilerFramePreservesAllLoopInvariants, SMT
                DEF expands, origin, frame
        <2>storage. [SwiftCompilerStorage(view, count, state) EXCEPT
                        !.pending = SwiftPendingArray(next.height, next.pending)] =
                        SwiftCompilerStorage(view, count, next)
            BY <1>expand, SMT DEF next, expands, origin, frame, CompilerTraversalNext, SwiftCompilerStorage
        <2>. DEFINE before == SwiftCompilerStorage(view, count, state)
                    source == SwiftSourceArray(view, count)
                    returned == ReviewedSwiftExpansionIteration(before.pending, source, before)
        <2>offsets. /\ state.height - 1 \in 0..(state.height - 1)
                     /\ (state.height - 1) + 1 = state.height
                     /\ origin - 1 \in 0..(count - 1)
                     /\ (origin - 1) + 1 = origin
            BY <1>origin, <2>step, SMT DEF ReviewedExpansionOperationSafety
        <2>pending. /\ before.pending.count = state.height
                     /\ before.pending.items[state.height - 1] = <<origin, frame.expanded>>
            BY ONLY <2>offsets DEF before, SwiftCompilerStorage, SwiftPendingArray, origin, frame
        <2>source. /\ source.count = count
                    /\ source.items[origin - 1].kind = view.kinds[origin]
            BY ONLY <2>offsets DEF source, SwiftSourceArray
        <2>returned. returned =
            [pending |-> SwiftPendingArray(next.height, next.pending),
             control |-> "continue", untouched |-> before]
            BY ONLY <2>step DEF returned, before, source,
                ReviewedExpansionMatchesTraversal, SwiftCompilerStorage, next
        <2>selected. ReviewedSwiftCompilerIteration(source, before) =
            [before EXCEPT !.pending = SwiftPendingArray(next.height, next.pending)]
            BY ONLY <1>origin, <1>expand, <2>pending, <2>source, <2>returned, state.height > 0
                DEF ReviewedSwiftCompilerIteration, returned, expands
        <2>. QED BY ONLY <1>expand, <2>step, <2>storage, <2>selected
            DEF before, source, next, expands, origin, frame
    <1>emit. CASE ~expands
        PROOF
        <2>branch. frame.expanded \/ view.kinds[origin] # "add"
            BY <1>origin, <1>emit, SMT DEF expands
        <2>capacity. /\ state.height <= SwiftIntMax
                      /\ state.current.emitted.count + 1 <= SwiftIntMax
                      /\ state.completed.height + 1 <= SwiftIntMax
            PROOF
            <3>count. next.current.emitted.count = state.current.emitted.count + 1
                BY ONLY <1>emit DEF next, CompilerTraversalNext,
                    AppendCertificateConstructor, expands, origin, frame
            <3>types. /\ state.height \in Nat /\ state.completed.height \in Nat
                       /\ state.current.emitted.count \in Nat
                       /\ count \in Nat /\ SwiftIntMax \in Int
                BY IntegerDomain, SMT DEF CompilerTraversalInvariant, CompilerOccurrenceStages,
                    CompletedCertificateRoots, WellFormedVisitPrefix, CertificateConstructionInvariant,
                    NodeEmissionArrays, CompilerOccurrenceTree, IntegerDomain
            <3>. QED BY ONLY <1>before, <1>after, <3>count, <3>types,
                state.completed.height <= state.current.emitted.count, count <= SwiftIntMax, SMT
        <2>step. /\ ReviewedEmissionOperationSafety(view, count, state)
                  /\ ReviewedEmissionMatchesTraversal(view, count, state)
            BY <2>branch, <2>capacity, ReviewedEmissionDerivesTraversalStep DEF origin, frame
        <2>. DEFINE before == SwiftCompilerStorage(view, count, state)
                    source == SwiftSourceArray(view, count)
        <2>offsets. /\ state.height - 1 \in 0..(state.height - 1)
                     /\ (state.height - 1) + 1 = state.height
                     /\ origin - 1 \in 0..(count - 1)
                     /\ (origin - 1) + 1 = origin
            BY <1>origin, <2>step, SMT DEF ReviewedEmissionOperationSafety
        <2>pending. /\ before.pending.count = state.height
                     /\ before.pending.items[state.height - 1] = <<origin, frame.expanded>>
            BY ONLY <2>offsets DEF before, SwiftCompilerStorage, SwiftPendingArray, origin, frame
        <2>source. /\ source.count = count
                    /\ source.items[origin - 1].kind = view.kinds[origin]
            BY ONLY <2>offsets DEF source, SwiftSourceArray
        <2>selected. ReviewedSwiftCompilerIteration(source, before) =
                         ReviewedSwiftEmissionIteration(source, before)
            BY ONLY <1>origin, <1>emit, <2>pending, <2>source, state.height > 0
                DEF ReviewedSwiftCompilerIteration, expands
        <2>emitted. ReviewedSwiftEmissionIteration(source, before) =
                        SwiftCompilerStorage(view, count, next)
            BY ONLY <2>step DEF ReviewedEmissionMatchesTraversal, before, source, next
        <2>. QED BY ONLY <1>emit, <2>step, <2>selected, <2>emitted
            DEF before, source, next, expands, origin, frame
    <1>. QED BY <1>expand, <1>emit DEF expands, frame, origin

ReviewedCompilerTraversalExecution(view, count, steps, execution) ==
    /\ steps \in Nat
    /\ execution[0] = ReviewedSwiftTraversalInitialization(SwiftSourceArray(view, count))
    /\ \A step \in 1..steps :
        /\ execution[step - 1].pending.count > 0
        /\ execution[step] = ReviewedSwiftCompilerIteration(SwiftSourceArray(view, count), execution[step - 1])
    /\ ReviewedSwiftCompilerIteration(SwiftSourceArray(view, count), execution[steps]).control = "exit"
    /\ ReviewedSwiftCertificateReturn(SwiftSourceArray(view, count), execution[steps]).control = "return"

THEOREM CompilerTraversalPrefixesExecuteTheReviewedSwiftLoop ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count), count <= SwiftIntMax,
           NEW steps, NEW history, CompilerTraversalPrefix(view, steps, history)
    PROVE /\ SwiftCompilerStorage(view, count, history[0]) =
                 ReviewedSwiftTraversalInitialization(SwiftSourceArray(view, count))
          /\ \A step \in 1..steps :
               /\ SwiftCompilerStorage(view, count, history[step - 1]).pending.count > 0
               /\ SwiftCompilerStorage(view, count, history[step]) =
                      ReviewedSwiftCompilerIteration(SwiftSourceArray(view, count),
                          SwiftCompilerStorage(view, count, history[step - 1]))
    PROOF
    <1>bounds. \A step \in 0..steps :
              /\ CompilerTraversalInvariant(view, history[step])
              /\ history[step].completed.height <= history[step].current.emitted.count
        BY CompilerTraversalPrefixesDeriveStorageBounds, SMT
    <1>initial. SwiftCompilerStorage(view, count, history[0]) =
                    ReviewedSwiftTraversalInitialization(SwiftSourceArray(view, count))
        BY ReviewedArrayInitializationStartsTheCompilerTraversal DEF CompilerTraversalPrefix
    <1>iterations. \A step \in 1..steps :
              /\ SwiftCompilerStorage(view, count, history[step - 1]).pending.count > 0
              /\ SwiftCompilerStorage(view, count, history[step]) =
                     ReviewedSwiftCompilerIteration(SwiftSourceArray(view, count),
                         SwiftCompilerStorage(view, count, history[step - 1]))
        PROOF
        <2>. SUFFICES ASSUME NEW step \in 1..steps PROVE
                  /\ SwiftCompilerStorage(view, count, history[step - 1]).pending.count > 0
                  /\ SwiftCompilerStorage(view, count, history[step]) =
                         ReviewedSwiftCompilerIteration(SwiftSourceArray(view, count),
                             SwiftCompilerStorage(view, count, history[step - 1]))
            BY SMT
        <2>states. /\ step - 1 \in 0..steps
                    /\ history[step - 1].height > 0
                    /\ history[step] = CompilerTraversalNext(view, history[step - 1])
            BY SMT DEF CompilerTraversalPrefix
        <2>. QED BY <1>bounds, <2>states, ReviewedCompilerIterationDerivesTraversalStep, SMT
            DEF SwiftCompilerStorage, SwiftPendingArray
    <1>. QED BY ONLY <1>initial, <1>iterations

THEOREM OccurrenceTreeTraversalExecutesTheReviewedSwiftAndReturnsAValidCertificate ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count), count <= SwiftIntMax,
           NEW bound, CertificateSource(view, bound)
    PROVE \E steps, history, execution :
          /\ CompilerTraversalCompletion(view, InitialCompilerTraversal(view), steps, history)
          /\ execution = [step \in 0..steps |-> SwiftCompilerStorage(view, count, history[step])]
          /\ ReviewedCompilerTraversalExecution(view, count, steps, execution)
          /\ CertificateConstructionInvariant(view, history[steps].current)
          /\ TypedVisitedSourceInputs(view, history[steps].current.emitted)
          /\ \A origin \in DOMAIN view.kinds : history[steps].current.inverse[origin] > 0
          /\ history[steps].current.emitted.count > 0
          /\ history[steps].current.emitted.origins[history[steps].current.emitted.count] = view.root
          /\ ReviewedReturnMatchesCertificate(view, count, history[steps])
    PROOF
    <1>initial. CompilerTraversalInvariant(view, InitialCompilerTraversal(view))
        BY CompilerTraversalStartsWithItsLoopInvariants
    <1>completed. PICK steps, history :
              CompilerTraversalCompletion(view, InitialCompilerTraversal(view), steps, history)
        BY <1>initial, FiniteCompilerTasksConstructATerminatingTraversal
    <1>prefix. CompilerTraversalPrefix(view, steps, history)
        BY <1>completed, SMT DEF CompilerTraversalCompletion, CompilerTraversalPrefix
    <1>domain. /\ steps \in Nat /\ steps \in 0..steps
        BY <1>completed, SMT DEF CompilerTraversalCompletion
    <1>. DEFINE execution == [step \in 0..steps |-> SwiftCompilerStorage(view, count, history[step])]
    <1>projection. \A step \in 0..steps :
        execution[step] = SwiftCompilerStorage(view, count, history[step])
        BY ONLY DEF execution
    <1>loop. /\ execution[0] = ReviewedSwiftTraversalInitialization(SwiftSourceArray(view, count))
             /\ \A step \in 1..steps :
                  /\ execution[step - 1].pending.count > 0
                  /\ execution[step] = ReviewedSwiftCompilerIteration(SwiftSourceArray(view, count),
                         execution[step - 1])
        PROOF
        <2>direct. /\ SwiftCompilerStorage(view, count, history[0]) =
                         ReviewedSwiftTraversalInitialization(SwiftSourceArray(view, count))
                    /\ \A step \in 1..steps :
                         /\ SwiftCompilerStorage(view, count, history[step - 1]).pending.count > 0
                         /\ SwiftCompilerStorage(view, count, history[step]) =
                                ReviewedSwiftCompilerIteration(SwiftSourceArray(view, count),
                                    SwiftCompilerStorage(view, count, history[step - 1]))
            BY ONLY <1>prefix, CompilerOccurrenceTree(view, count), count <= SwiftIntMax,
                CompilerTraversalPrefixesExecuteTheReviewedSwiftLoop
        <2>domains. /\ 0 \in 0..steps
                    /\ \A step \in 1..steps : step \in 0..steps /\ step - 1 \in 0..steps
            BY ONLY <1>domain, SMT
        <2>. QED BY ONLY <1>projection, <2>direct, <2>domains
    <1>final. /\ CompilerTraversalInvariant(view, history[steps])
              /\ history[steps].height = 0
        BY <1>completed DEF CompilerTraversalCompletion
    <1>invariant. CertificateConstructionInvariant(view, history[steps].current)
        BY <1>final DEF CompilerTraversalInvariant
    <1>typed. TypedVisitedSourceInputs(view, history[steps].current.emitted)
        BY <1>invariant, SMT DEF CertificateConstructionInvariant, CertificateSource, TypedVisitedSourceInputs
    <1>guards. /\ \A origin \in DOMAIN view.kinds : history[steps].current.inverse[origin] > 0
               /\ history[steps].current.emitted.count > 0
               /\ history[steps].current.emitted.origins[history[steps].current.emitted.count] = view.root
               /\ ReviewedReturnMatchesCertificate(view, count, history[steps])
        BY <1>final, TerminatedCompilerInvariantDerivesEveryReturnGuard, SMT DEF CompilerOccurrenceTree
    <1>last. execution[steps] = SwiftCompilerStorage(view, count, history[steps])
        BY ONLY <1>domain DEF execution
    <1>exit. ReviewedSwiftCompilerIteration(SwiftSourceArray(view, count), execution[steps]).control = "exit"
        BY ONLY <1>last, <1>final
            DEF ReviewedSwiftCompilerIteration, SwiftCompilerStorage, SwiftPendingArray
    <1>returned. ReviewedSwiftCertificateReturn(SwiftSourceArray(view, count), execution[steps]).control = "return"
        BY ONLY <1>last, <1>guards DEF ReviewedReturnMatchesCertificate
    <1>execution. ReviewedCompilerTraversalExecution(view, count, steps, execution)
        BY ONLY <1>domain, <1>loop, <1>exit, <1>returned DEF ReviewedCompilerTraversalExecution
    <1>. QED BY <1>completed, <1>invariant, <1>typed, <1>guards, <1>execution, SMT DEF execution

\* The input root and actualReads bind the actual pre-call StateExpr and reads.
\* Histories below are witnesses to the existing loop equations, never an
\* assumed valid certificate, assumed output equality, or source-meaning input.
ReviewedOrderedIntCertificateInvocation(root, actualReads, syntax, weight, result) ==
    /\ \A term \in DOMAIN syntax : syntax[term].kind = "read" => syntax[term].read \in actualReads
    /\ \E allocationSteps, allocationHistory, traversalSteps, execution :
        /\ CompilerAllocationCompletion(syntax, weight, InitialCompilerAllocation(root, weight),
               allocationSteps, allocationHistory)
        /\ LET allocated == allocationHistory[allocationSteps]
               view == AllocatedSourceView(allocated)
           IN /\ ReviewedCompilerTraversalExecution(view, allocated.count, traversalSteps, execution)
              /\ result = ReviewedSwiftCertificateReturn(SwiftSourceArray(view, allocated.count),
                     execution[traversalSteps]).certificate

THEOREM SupportedInputHasExactlyOneReviewedCompilerResult ==
    ASSUME NEW root, NEW terms, NEW syntax, NEW weight, NEW bound,
           SupportedAllocationInput(root, terms, syntax, weight, bound), weight[root] <= SwiftIntMax,
           NEW actualReads, bound \subseteq actualReads
    PROVE \E result :
        /\ ReviewedOrderedIntCertificateInvocation(root, actualReads, syntax, weight, result)
        /\ \A actual : ReviewedOrderedIntCertificateInvocation(root, actualReads, syntax, weight, actual)
               => actual = result
    PROOF
    <1>allocation. PICK allocationSteps, allocationHistory :
        /\ CompilerAllocationCompletion(syntax, weight, InitialCompilerAllocation(root, weight),
               allocationSteps, allocationHistory)
        /\ CompilerOccurrenceTree(AllocatedSourceView(allocationHistory[allocationSteps]),
               allocationHistory[allocationSteps].count)
        /\ CertificateSource(AllocatedSourceView(allocationHistory[allocationSteps]), bound)
        /\ allocationHistory[allocationSteps].count = weight[root]
        BY ActualAllocationConstructsTheTraversalSource, SMT
    <1>. DEFINE allocated == allocationHistory[allocationSteps]
                view == AllocatedSourceView(allocated)
    <1>capacity. allocated.count <= SwiftIntMax
        BY <1>allocation DEF allocated
    <1>traversal. PICK traversalSteps, traversalHistory, execution :
        /\ CompilerTraversalCompletion(view, InitialCompilerTraversal(view), traversalSteps, traversalHistory)
        /\ execution = [step \in 0..traversalSteps |-> SwiftCompilerStorage(view, allocated.count, traversalHistory[step])]
        /\ ReviewedCompilerTraversalExecution(view, allocated.count, traversalSteps, execution)
        /\ ReviewedReturnMatchesCertificate(view, allocated.count, traversalHistory[traversalSteps])
        BY <1>allocation, <1>capacity,
            OccurrenceTreeTraversalExecutesTheReviewedSwiftAndReturnsAValidCertificate, SMT DEF view, allocated
    <1>. DEFINE result == ReviewedSwiftCertificateReturn(SwiftSourceArray(view, allocated.count),
                              execution[traversalSteps]).certificate
    <1>reads. \A term \in DOMAIN syntax : syntax[term].kind = "read" => syntax[term].read \in actualReads
        BY SMT DEF SupportedAllocationInput
    <1>invocation. ReviewedOrderedIntCertificateInvocation(root, actualReads, syntax, weight, result)
        BY <1>allocation, <1>traversal, <1>reads, SMT
            DEF ReviewedOrderedIntCertificateInvocation, result, view, allocated
    <1>unique. \A actual : ReviewedOrderedIntCertificateInvocation(root, actualReads, syntax, weight, actual)
                  => actual = result
        PROOF
        <2>. SUFFICES ASSUME NEW actual,
                     ReviewedOrderedIntCertificateInvocation(root, actualReads, syntax, weight, actual)
                     PROVE actual = result
            BY SMT
        <2>other. PICK otherAllocationSteps, otherAllocationHistory, otherTraversalSteps, otherExecution :
            /\ CompilerAllocationCompletion(syntax, weight, InitialCompilerAllocation(root, weight),
                   otherAllocationSteps, otherAllocationHistory)
            /\ LET otherAllocated == otherAllocationHistory[otherAllocationSteps]
                   otherView == AllocatedSourceView(otherAllocated)
               IN /\ ReviewedCompilerTraversalExecution(otherView, otherAllocated.count,
                          otherTraversalSteps, otherExecution)
                  /\ actual = ReviewedSwiftCertificateReturn(SwiftSourceArray(otherView, otherAllocated.count),
                         otherExecution[otherTraversalSteps]).certificate
            BY SMT DEF ReviewedOrderedIntCertificateInvocation
        <2>allocationTypes. allocationSteps \in Nat /\ otherAllocationSteps \in Nat
            BY <1>allocation, <2>other, SMT DEF CompilerAllocationCompletion
        <2>. DEFINE allocationAgrees(index) == index <= otherAllocationSteps =>
                        allocationHistory[index] = otherAllocationHistory[index]
        <2>allocationBase. allocationAgrees(0)
            BY <1>allocation, <2>other, SMT DEF allocationAgrees, CompilerAllocationCompletion
        <2>allocationStep. \A index \in 1..allocationSteps :
            ((\A prior \in 0..(index - 1) : allocationAgrees(prior)) => allocationAgrees(index))
            PROOF
            <3>. SUFFICES ASSUME NEW index \in 1..allocationSteps,
                                 \A prior \in 0..(index - 1) : allocationAgrees(prior),
                                 index <= otherAllocationSteps
                         PROVE allocationHistory[index] = otherAllocationHistory[index]
                BY SMT DEF allocationAgrees
            <3>domains. /\ index - 1 \in 0..(index - 1) /\ index - 1 <= otherAllocationSteps
                         /\ index \in 1..otherAllocationSteps
                BY <2>allocationTypes, SMT
            <3>prior. allocationHistory[index - 1] = otherAllocationHistory[index - 1]
                BY <3>domains, SMT DEF allocationAgrees
            <3>equations.
                /\ allocationHistory[index] = ReviewedSwiftAllocationIteration(syntax, weight, allocationHistory[index - 1])
                /\ otherAllocationHistory[index] = ReviewedSwiftAllocationIteration(syntax, weight, otherAllocationHistory[index - 1])
                BY <1>allocation, <2>other, <3>domains, SMT DEF CompilerAllocationCompletion
            <3>. QED BY ONLY <3>prior, <3>equations
        <2>allocationOverlap. \A index \in 0..allocationSteps : allocationAgrees(index)
            BY <2>allocationTypes, <2>allocationBase, <2>allocationStep, FiniteIndexedPrefixProperty
        <2>allocationLength. allocationSteps = otherAllocationSteps
            PROOF
            <3>firstShort. ASSUME allocationSteps < otherAllocationSteps PROVE FALSE
                PROOF
                <4>domains. /\ allocationSteps \in 0..allocationSteps
                             /\ allocationSteps + 1 \in 1..otherAllocationSteps
                    BY ONLY <2>allocationTypes, <3>firstShort, SMT
                <4>same. allocationHistory[allocationSteps] = otherAllocationHistory[allocationSteps]
                    BY <2>allocationOverlap, <3>firstShort, <4>domains, SMT DEF allocationAgrees
                <4>. QED BY <1>allocation, <2>other, <4>domains, <4>same, SMT DEF CompilerAllocationCompletion
            <3>secondShort. ASSUME otherAllocationSteps < allocationSteps PROVE FALSE
                PROOF
                <4>domains. /\ otherAllocationSteps \in 0..allocationSteps
                             /\ otherAllocationSteps + 1 \in 1..allocationSteps
                    BY ONLY <2>allocationTypes, <3>secondShort, SMT
                <4>same. allocationHistory[otherAllocationSteps] = otherAllocationHistory[otherAllocationSteps]
                    BY <2>allocationOverlap, <4>domains, SMT DEF allocationAgrees
                <4>. QED BY <1>allocation, <2>other, <4>domains, <4>same, SMT DEF CompilerAllocationCompletion
            <3>. QED BY <2>allocationTypes, <3>firstShort, <3>secondShort, SMT
        <2>sameAllocation. allocated = otherAllocationHistory[otherAllocationSteps]
            BY <2>allocationTypes, <2>allocationOverlap, <2>allocationLength, SMT DEF allocationAgrees, allocated
        <2>otherTraversal. /\ ReviewedCompilerTraversalExecution(view, allocated.count, otherTraversalSteps, otherExecution)
                           /\ actual = ReviewedSwiftCertificateReturn(SwiftSourceArray(view, allocated.count),
                                  otherExecution[otherTraversalSteps]).certificate
            BY ONLY <2>other, <2>sameAllocation DEF view
        <2>traversalTypes. traversalSteps \in Nat /\ otherTraversalSteps \in Nat
            BY <1>traversal, <2>otherTraversal, SMT DEF ReviewedCompilerTraversalExecution
        <2>projection. \A index \in 0..traversalSteps :
                          execution[index] = SwiftCompilerStorage(view, allocated.count, traversalHistory[index])
            BY ONLY <1>traversal
        <2>normal. \A index \in 0..traversalSteps : execution[index].control = "normal"
            BY ONLY <2>projection DEF SwiftCompilerStorage
        <2>empty. execution[traversalSteps].pending.count = 0
            BY <1>traversal, <2>traversalTypes, <2>projection, SMT
                DEF CompilerTraversalCompletion, SwiftCompilerStorage, SwiftPendingArray
        <2>. DEFINE traversalAgrees(index) == index <= otherTraversalSteps => execution[index] = otherExecution[index]
        <2>traversalBase. traversalAgrees(0)
            BY <1>traversal, <2>otherTraversal, SMT DEF traversalAgrees, ReviewedCompilerTraversalExecution
        <2>traversalStep. \A index \in 1..traversalSteps :
            ((\A prior \in 0..(index - 1) : traversalAgrees(prior)) => traversalAgrees(index))
            PROOF
            <3>. SUFFICES ASSUME NEW index \in 1..traversalSteps,
                                 \A prior \in 0..(index - 1) : traversalAgrees(prior), index <= otherTraversalSteps
                         PROVE execution[index] = otherExecution[index]
                BY SMT DEF traversalAgrees
            <3>domains. /\ index - 1 \in 0..(index - 1) /\ index - 1 <= otherTraversalSteps
                         /\ index \in 1..otherTraversalSteps
                BY <2>traversalTypes, SMT
            <3>prior. execution[index - 1] = otherExecution[index - 1]
                BY <3>domains, SMT DEF traversalAgrees
            <3>equations.
                /\ execution[index] = ReviewedSwiftCompilerIteration(SwiftSourceArray(view, allocated.count), execution[index - 1])
                /\ otherExecution[index] = ReviewedSwiftCompilerIteration(SwiftSourceArray(view, allocated.count), otherExecution[index - 1])
                BY <1>traversal, <2>otherTraversal, <3>domains, SMT DEF ReviewedCompilerTraversalExecution
            <3>. QED BY ONLY <3>prior, <3>equations
        <2>traversalOverlap. \A index \in 0..traversalSteps : traversalAgrees(index)
            BY <2>traversalTypes, <2>traversalBase, <2>traversalStep, FiniteIndexedPrefixProperty
        <2>traversalLength. traversalSteps = otherTraversalSteps
            PROOF
            <3>firstShort. ASSUME traversalSteps < otherTraversalSteps PROVE FALSE
                PROOF
                <4>domains. /\ traversalSteps \in 0..traversalSteps
                             /\ traversalSteps + 1 \in 1..otherTraversalSteps
                    BY ONLY <2>traversalTypes, <3>firstShort, SMT
                <4>same. execution[traversalSteps] = otherExecution[traversalSteps]
                    BY <2>traversalOverlap, <3>firstShort, <4>domains, SMT DEF traversalAgrees
                <4>. QED BY <2>otherTraversal, <2>empty, <4>domains, <4>same, SMT
                    DEF ReviewedCompilerTraversalExecution
            <3>secondShort. ASSUME otherTraversalSteps < traversalSteps PROVE FALSE
                PROOF
                <4>domains. /\ otherTraversalSteps \in 0..traversalSteps
                             /\ otherTraversalSteps + 1 \in 1..traversalSteps
                    BY ONLY <2>traversalTypes, <3>secondShort, SMT
                <4>same. execution[otherTraversalSteps] = otherExecution[otherTraversalSteps]
                    BY <2>traversalOverlap, <4>domains, SMT DEF traversalAgrees
                <4>normalNext. execution[otherTraversalSteps + 1].control = "normal"
                    BY <2>normal, <4>domains, SMT
                <4>. QED BY <1>traversal, <2>otherTraversal, <4>domains, <4>same, <4>normalNext, SMT
                    DEF ReviewedCompilerTraversalExecution
            <3>. QED BY <2>traversalTypes, <3>firstShort, <3>secondShort, SMT
        <2>sameReturn. execution[traversalSteps] = otherExecution[otherTraversalSteps]
            BY <2>traversalTypes, <2>traversalOverlap, <2>traversalLength, SMT DEF traversalAgrees
        <2>. QED BY ONLY <2>otherTraversal, <2>sameReturn DEF result
    <1>. QED BY <1>invocation, <1>unique, SMT

\* The reviewed Swift interpretation assumes documented value semantics and
\* successful storage allocation for the arrays whose lengths are proved below.
\* Integer representability is explicit. Resource exhaustion is operational
\* failure, never rejection of supported syntax or an expression/model failure.

\* Erase the allocation proof's per-variant fields into the actual enum array.
AllocatedSwiftSource(state) ==
    [count |-> state.count,
     items |-> [offset \in 0..(state.count - 1) |->
         LET node == state.source[offset + 1]
         IN [kind |-> node.kind,
             payload |-> IF node.kind = "literal" THEN node.literal
                         ELSE IF node.kind = "read" THEN node.read ELSE 0,
             left |-> IF node.kind = "add" THEN node.left ELSE 0,
             right |-> IF node.kind = "add" THEN node.right ELSE 0]]]

THEOREM AllocatedEnumArrayIsTheTraversalSource ==
    ASSUME NEW state, state.count \in Nat
    PROVE AllocatedSwiftSource(state) = SwiftSourceArray(AllocatedSourceView(state), state.count)
    PROOF
    <1>. DEFINE actual == AllocatedSwiftSource(state)
                interpreted == SwiftSourceArray(AllocatedSourceView(state), state.count)
    <1>counts. actual.count = state.count /\ interpreted.count = state.count
        BY ONLY DEF actual, interpreted, AllocatedSwiftSource, SwiftSourceArray
    <1>domains. /\ DOMAIN actual.items = 0..(state.count - 1)
                 /\ DOMAIN interpreted.items = 0..(state.count - 1)
        BY ONLY DEF actual, interpreted, AllocatedSwiftSource, SwiftSourceArray
    <1>entries. \A offset \in 0..(state.count - 1) : actual.items[offset] = interpreted.items[offset]
        PROOF
        <2>. SUFFICES ASSUME NEW offset \in 0..(state.count - 1)
                     PROVE actual.items[offset] = interpreted.items[offset]
            BY SMT
        <2>origin. offset + 1 \in 1..state.count
            BY SMT
        <2>. DEFINE node == state.source[offset + 1]
        <2>actual. actual.items[offset] =
            [kind |-> node.kind,
             payload |-> IF node.kind = "literal" THEN node.literal ELSE IF node.kind = "read" THEN node.read ELSE 0,
             left |-> IF node.kind = "add" THEN node.left ELSE 0,
             right |-> IF node.kind = "add" THEN node.right ELSE 0]
            BY ONLY offset \in 0..(state.count - 1) DEF actual, AllocatedSwiftSource, node
        <2>interpreted. interpreted.items[offset] =
            [kind |-> node.kind,
             payload |-> IF node.kind = "literal" THEN node.literal ELSE IF node.kind = "read" THEN node.read ELSE 0,
             left |-> IF node.kind = "add" THEN node.left ELSE 0,
             right |-> IF node.kind = "add" THEN node.right ELSE 0]
            BY ONLY offset \in 0..(state.count - 1), <2>origin
                DEF interpreted, SwiftSourceArray, AllocatedSourceView, node
        <2>. QED BY ONLY <2>actual, <2>interpreted
    <1>items. actual.items = interpreted.items
        BY ONLY <1>domains, <1>entries
            DEF actual, interpreted, AllocatedSwiftSource, SwiftSourceArray
    <1>. QED BY ONLY <1>counts, <1>items
        DEF actual, interpreted, AllocatedSwiftSource, SwiftSourceArray

THEOREM ActualSupportedInputReturnsAReviewedCertificate ==
    ASSUME NEW root, NEW terms, NEW syntax, NEW weight, NEW bound,
           SupportedAllocationInput(root, terms, syntax, weight, bound),
           weight[root] <= SwiftIntMax, NEW fallback \in Keys
    PROVE \E allocationSteps, allocationHistory, traversalSteps, traversalHistory, execution :
        /\ CompilerAllocationCompletion(syntax, weight, InitialCompilerAllocation(root, weight),
               allocationSteps, allocationHistory)
        /\ LET allocated == allocationHistory[allocationSteps]
               view == AllocatedSourceView(allocated)
               final == traversalHistory[traversalSteps]
           IN /\ allocated.count = weight[root]
              /\ AllocatedSwiftSource(allocated) = SwiftSourceArray(view, allocated.count)
              /\ CompilerTraversalCompletion(view, InitialCompilerTraversal(view),
                     traversalSteps, traversalHistory)
              /\ execution = [step \in 0..traversalSteps |->
                     SwiftCompilerStorage(view, allocated.count, traversalHistory[step])]
              /\ ReviewedCompilerTraversalExecution(view, allocated.count, traversalSteps, execution)
              /\ ReviewedReturnMatchesCertificate(view, allocated.count, final)
              /\ LiteralReadAddCertificate(view, final.current.emitted, final.current.inverse, fallback, bound)
    PROOF
    <1>allocation. PICK allocationSteps, allocationHistory :
        /\ CompilerAllocationCompletion(syntax, weight, InitialCompilerAllocation(root, weight),
               allocationSteps, allocationHistory)
        /\ CompilerOccurrenceTree(AllocatedSourceView(allocationHistory[allocationSteps]),
               allocationHistory[allocationSteps].count)
        /\ CertificateSource(AllocatedSourceView(allocationHistory[allocationSteps]), bound)
        /\ allocationHistory[allocationSteps].count = weight[root]
        /\ CompilerAllocatedPayloadsMatch(syntax, allocationHistory[allocationSteps])
        BY ActualAllocationConstructsTheTraversalSource
    <1>. DEFINE allocated == allocationHistory[allocationSteps]
                view == AllocatedSourceView(allocated)
    <1>count. allocated.count <= SwiftIntMax
        BY <1>allocation DEF allocated
    <1>traversal. PICK traversalSteps, traversalHistory, execution :
        /\ CompilerTraversalCompletion(view, InitialCompilerTraversal(view), traversalSteps, traversalHistory)
        /\ execution = [step \in 0..traversalSteps |->
               SwiftCompilerStorage(view, allocated.count, traversalHistory[step])]
        /\ ReviewedCompilerTraversalExecution(view, allocated.count, traversalSteps, execution)
        /\ CertificateConstructionInvariant(view, traversalHistory[traversalSteps].current)
        /\ TypedVisitedSourceInputs(view, traversalHistory[traversalSteps].current.emitted)
        /\ \A origin \in DOMAIN view.kinds :
               traversalHistory[traversalSteps].current.inverse[origin] > 0
        /\ traversalHistory[traversalSteps].current.emitted.count > 0
        /\ traversalHistory[traversalSteps].current.emitted.origins[
               traversalHistory[traversalSteps].current.emitted.count] = view.root
        /\ ReviewedReturnMatchesCertificate(view, allocated.count, traversalHistory[traversalSteps])
        BY <1>allocation, <1>count,
            OccurrenceTreeTraversalExecutesTheReviewedSwiftAndReturnsAValidCertificate DEF view, allocated
    <1>certificate. LiteralReadAddCertificate(view, traversalHistory[traversalSteps].current.emitted,
                        traversalHistory[traversalSteps].current.inverse, fallback, bound)
        PROOF
        <2>. DEFINE final == traversalHistory[traversalSteps]
        <2>source. CertificateSource(view, bound)
            BY <1>allocation DEF view, allocated
        <2>keys. bound \subseteq Keys /\ fallback \in Keys
            BY <2>source DEF CertificateSource
        <2>inverse. final.current.inverse \in [DOMAIN view.kinds -> 1..final.current.emitted.count]
            BY <1>traversal, SMT DEF final, CertificateConstructionInvariant
        <2>reads. \A index \in 1..final.current.emitted.count :
            final.current.emitted.nodes[index].kind = "read" =>
                final.current.emitted.nodes[index].payload \in bound
            BY <1>traversal, <2>source, SMT DEF final, CertificateConstructionInvariant,
                AllNodePayloadsMatchSource, NodePayloadMatchesSource, CertificateSource
        <2>. QED BY <1>traversal, <2>keys, <2>inverse, <2>reads, SMT
            DEF LiteralReadAddCertificate, CertificateConstructionInvariant, final
    <1>allocatedType. allocated.count \in Nat
        BY <1>allocation DEF allocated, CompilerOccurrenceTree
    <1>source. AllocatedSwiftSource(allocated) = SwiftSourceArray(view, allocated.count)
        BY <1>allocatedType, AllocatedEnumArrayIsTheTraversalSource DEF view
    <1>. WITNESS allocationSteps, allocationHistory, traversalSteps, traversalHistory, execution
    <1>. QED BY ONLY <1>allocation, <1>traversal, <1>certificate, <1>source, SMT DEF allocated, view

\* Exact inverse storage projections for the actual returned enum/value arrays.
SwiftArrayAsHistory(array) ==
    [index \in 1..array.count |-> array.items[index - 1]]

THEOREM SwiftIndexedArrayDecodesToHistory ==
    ASSUME NEW length \in Nat, NEW values,
           values = [index \in 1..length |-> values[index]]
    PROVE SwiftArrayAsHistory(SwiftIndexedArray(length, values)) = values
    PROOF
    <1>offsets. \A index \in 1..length :
                   /\ index - 1 \in 0..(length - 1) /\ (index - 1) + 1 = index
        BY SMT
    <1>entries. \A index \in 1..length :
                   SwiftArrayAsHistory(SwiftIndexedArray(length, values))[index] = values[index]
        BY ONLY <1>offsets DEF SwiftArrayAsHistory, SwiftIndexedArray
    <1>. QED BY ONLY <1>entries, values = [index \in 1..length |-> values[index]]
        DEF SwiftArrayAsHistory, SwiftIndexedArray

SwiftSourceArrayAsView(array) ==
    [root |-> 1,
     kinds |-> [origin \in 1..array.count |-> array.items[origin - 1].kind],
     literals |-> [origin \in 1..array.count |->
         IF array.items[origin - 1].kind = "literal" THEN array.items[origin - 1].payload ELSE 0],
     reads |-> [origin \in 1..array.count |->
         IF array.items[origin - 1].kind = "read" THEN array.items[origin - 1].payload ELSE 0],
     left |-> [origin \in 1..array.count |->
         IF array.items[origin - 1].kind = "add" THEN array.items[origin - 1].left ELSE 0],
     right |-> [origin \in 1..array.count |->
         IF array.items[origin - 1].kind = "add" THEN array.items[origin - 1].right ELSE 0]]

SwiftCertificateArraysAsEmission(result) ==
    [count |-> result.nodes.count, height |-> 1, indices |-> <<result.nodes.count>>,
     nodes |-> SwiftArrayAsHistory(result.nodes), origins |-> SwiftArrayAsHistory(result.origins)]

THEOREM AllocatedSwiftSourceDecodesToSourceView ==
    ASSUME NEW state, state.count \in Nat
    PROVE SwiftSourceArrayAsView(SwiftSourceArray(AllocatedSourceView(state), state.count)) =
          AllocatedSourceView(state)
    PROOF
    <1>. DEFINE view == AllocatedSourceView(state)
                packed == SwiftSourceArray(view, state.count)
                decoded == SwiftSourceArrayAsView(packed)
    <1>offsets. \A origin \in 1..state.count :
        /\ origin - 1 \in 0..(state.count - 1) /\ (origin - 1) + 1 = origin
        BY ONLY state.count \in Nat, SMT
    <1>count. packed.count = state.count
        BY ONLY DEF packed, SwiftSourceArray
    <1>allocatedSource. packed = AllocatedSwiftSource(state)
        BY ONLY state.count \in Nat, AllocatedEnumArrayIsTheTraversalSource DEF packed, view
    <1>entries. \A origin \in 1..state.count :
        /\ decoded.kinds[origin] = view.kinds[origin]
        /\ decoded.literals[origin] = view.literals[origin]
        /\ decoded.reads[origin] = view.reads[origin]
        /\ decoded.left[origin] = view.left[origin]
        /\ decoded.right[origin] = view.right[origin]
        PROOF
        <2>. SUFFICES ASSUME NEW origin \in 1..state.count PROVE
            /\ decoded.kinds[origin] = view.kinds[origin]
            /\ decoded.literals[origin] = view.literals[origin]
            /\ decoded.reads[origin] = view.reads[origin]
            /\ decoded.left[origin] = view.left[origin]
            /\ decoded.right[origin] = view.right[origin]
            BY SMT
        <2>lookup. packed.items[origin - 1] =
            [kind |-> state.source[origin].kind,
             payload |-> IF state.source[origin].kind = "literal" THEN state.source[origin].literal
                         ELSE IF state.source[origin].kind = "read" THEN state.source[origin].read ELSE 0,
             left |-> IF state.source[origin].kind = "add" THEN state.source[origin].left ELSE 0,
             right |-> IF state.source[origin].kind = "add" THEN state.source[origin].right ELSE 0]
            PROOF
            <3>offset. /\ origin - 1 \in 0..(state.count - 1)
                        /\ (origin - 1) + 1 = origin
                BY ONLY <1>offsets, origin \in 1..state.count, SMT
            <3>. QED BY ONLY <1>allocatedSource, <3>offset DEF AllocatedSwiftSource
        <2>viewFields.
            /\ view.kinds[origin] = state.source[origin].kind
            /\ view.literals[origin] = IF state.source[origin].kind = "literal" THEN state.source[origin].literal ELSE 0
            /\ view.reads[origin] = IF state.source[origin].kind = "read" THEN state.source[origin].read ELSE 0
            /\ view.left[origin] = IF state.source[origin].kind = "add" THEN state.source[origin].left ELSE 0
            /\ view.right[origin] = IF state.source[origin].kind = "add" THEN state.source[origin].right ELSE 0
            BY ONLY origin \in 1..state.count DEF view, AllocatedSourceView
        <2>. QED BY ONLY <1>count, <2>lookup, <2>viewFields, origin \in 1..state.count
            DEF decoded, SwiftSourceArrayAsView
    <1>root. decoded.root = view.root
        BY ONLY DEF decoded, SwiftSourceArrayAsView, view, AllocatedSourceView
    <1>kinds. decoded.kinds = view.kinds
        BY ONLY <1>count, <1>entries DEF decoded, SwiftSourceArrayAsView, view, AllocatedSourceView
    <1>literals. decoded.literals = view.literals
        BY ONLY <1>count, <1>entries DEF decoded, SwiftSourceArrayAsView, view, AllocatedSourceView
    <1>reads. decoded.reads = view.reads
        BY ONLY <1>count, <1>entries DEF decoded, SwiftSourceArrayAsView, view, AllocatedSourceView
    <1>left. decoded.left = view.left
        BY ONLY <1>count, <1>entries DEF decoded, SwiftSourceArrayAsView, view, AllocatedSourceView
    <1>right. decoded.right = view.right
        BY ONLY <1>count, <1>entries DEF decoded, SwiftSourceArrayAsView, view, AllocatedSourceView
    <1>shape.
        /\ decoded = [root |-> decoded.root, kinds |-> decoded.kinds, literals |-> decoded.literals,
                       reads |-> decoded.reads, left |-> decoded.left, right |-> decoded.right]
        /\ view = [root |-> view.root, kinds |-> view.kinds, literals |-> view.literals,
                    reads |-> view.reads, left |-> view.left, right |-> view.right]
        BY ONLY DEF decoded, SwiftSourceArrayAsView, view, AllocatedSourceView
    <1>. QED BY ONLY <1>root, <1>kinds, <1>literals, <1>reads, <1>left, <1>right, <1>shape DEF decoded, packed, view

THEOREM ActualReviewedCompilerResultSuppliesInitializerCertificate ==
    ASSUME NEW root, NEW terms, NEW syntax, NEW weight, NEW bound,
           SupportedAllocationInput(root, terms, syntax, weight, bound), weight[root] <= SwiftIntMax,
           NEW actualReads, bound \subseteq actualReads, NEW actualResult,
           ReviewedOrderedIntCertificateInvocation(root, actualReads, syntax, weight, actualResult),
           NEW fallback \in Keys
    PROVE LiteralReadAddCertificate(SwiftSourceArrayAsView(actualResult.source),
              SwiftCertificateArraysAsEmission(actualResult), SwiftArrayAsHistory(actualResult.indices),
              fallback, bound)
    PROOF
    <1>expected. PICK allocationSteps, allocationHistory, traversalSteps, traversalHistory, execution :
        /\ CompilerAllocationCompletion(syntax, weight, InitialCompilerAllocation(root, weight), allocationSteps, allocationHistory)
        /\ allocationHistory[allocationSteps].count = weight[root]
        /\ CompilerTraversalCompletion(AllocatedSourceView(allocationHistory[allocationSteps]),
               InitialCompilerTraversal(AllocatedSourceView(allocationHistory[allocationSteps])), traversalSteps, traversalHistory)
        /\ execution = [step \in 0..traversalSteps |->
               SwiftCompilerStorage(AllocatedSourceView(allocationHistory[allocationSteps]),
                   allocationHistory[allocationSteps].count, traversalHistory[step])]
        /\ ReviewedCompilerTraversalExecution(AllocatedSourceView(allocationHistory[allocationSteps]),
               allocationHistory[allocationSteps].count, traversalSteps, execution)
        /\ LiteralReadAddCertificate(AllocatedSourceView(allocationHistory[allocationSteps]),
               traversalHistory[traversalSteps].current.emitted, traversalHistory[traversalSteps].current.inverse, fallback, bound)
        /\ ReviewedReturnMatchesCertificate(AllocatedSourceView(allocationHistory[allocationSteps]),
               allocationHistory[allocationSteps].count, traversalHistory[traversalSteps])
        BY ActualSupportedInputReturnsAReviewedCertificate, SMT
    <1>. DEFINE allocated == allocationHistory[allocationSteps]
                view == AllocatedSourceView(allocated)
                final == traversalHistory[traversalSteps]
                emitted == final.current.emitted
                inverse == final.current.inverse
                expectedResult == ReviewedSwiftCertificateReturn(SwiftSourceArray(view, allocated.count),
                                      execution[traversalSteps]).certificate
    <1>types. /\ allocated.count \in Nat \ {0} /\ emitted.count \in Nat \ {0}
               /\ traversalSteps \in Nat /\ traversalSteps \in 0..traversalSteps
        BY <1>expected, SMT DEF SupportedAllocationInput, LiteralReadAddCertificate,
            NodeEmissionArrays, CompilerTraversalCompletion, allocated, emitted, final
    <1>last. execution[traversalSteps] = SwiftCompilerStorage(view, allocated.count, final)
        BY ONLY <1>expected, <1>types DEF view, allocated, final
    <1>fields. expectedResult =
        [source |-> SwiftSourceArray(view, allocated.count),
         nodes |-> SwiftIndexedArray(emitted.count, emitted.nodes),
         origins |-> SwiftIndexedArray(emitted.count, emitted.origins),
         indices |-> SwiftIndexedArray(allocated.count, inverse)]
        BY ONLY <1>expected, <1>last
            DEF ReviewedReturnMatchesCertificate, expectedResult, view, allocated, emitted, inverse, final
    <1>reads. \A term \in DOMAIN syntax : syntax[term].kind = "read" => syntax[term].read \in actualReads
        BY SMT DEF SupportedAllocationInput
    <1>invocation. ReviewedOrderedIntCertificateInvocation(root, actualReads, syntax, weight, expectedResult)
        BY <1>expected, <1>reads, SMT
            DEF ReviewedOrderedIntCertificateInvocation, expectedResult, view, allocated
    <1>unique. PICK onlyResult :
        /\ ReviewedOrderedIntCertificateInvocation(root, actualReads, syntax, weight, onlyResult)
        /\ \A actual : ReviewedOrderedIntCertificateInvocation(root, actualReads, syntax, weight, actual) => actual = onlyResult
        BY SupportedInputHasExactlyOneReviewedCompilerResult
    <1>identified. actualResult = expectedResult
        BY <1>invocation, <1>unique, SMT
    <1>sourceDomain. DOMAIN view.kinds = 1..allocated.count
        BY ONLY DEF view, AllocatedSourceView
    <1>functionShapes. /\ emitted.nodes = [index \in 1..emitted.count |-> emitted.nodes[index]]
                        /\ emitted.origins = [index \in 1..emitted.count |-> emitted.origins[index]]
                        /\ inverse = [origin \in 1..allocated.count |-> inverse[origin]]
        BY <1>expected, <1>sourceDomain, SMT
            DEF LiteralReadAddCertificate, NodeEmissionArrays, emitted, inverse, final, view, allocated
    <1>arrays. /\ SwiftArrayAsHistory(expectedResult.nodes) = emitted.nodes
                /\ SwiftArrayAsHistory(expectedResult.origins) = emitted.origins
                /\ SwiftArrayAsHistory(expectedResult.indices) = inverse
                /\ expectedResult.nodes.count = emitted.count
        BY <1>fields, <1>types, <1>functionShapes, SwiftIndexedArrayDecodesToHistory
            DEF SwiftIndexedArray
    <1>source. SwiftSourceArrayAsView(expectedResult.source) = view
        PROOF
        <2>packed. expectedResult.source = SwiftSourceArray(view, allocated.count)
            BY ONLY <1>fields
        <2>roundTrip. SwiftSourceArrayAsView(SwiftSourceArray(view, allocated.count)) = view
            BY ONLY <1>types, AllocatedSwiftSourceDecodesToSourceView DEF view
        <2>. QED BY ONLY <2>packed, <2>roundTrip
    <1>emission. LET decoded == SwiftCertificateArraysAsEmission(expectedResult)
                 IN /\ decoded.count = emitted.count /\ decoded.nodes = emitted.nodes
                    /\ decoded.origins = emitted.origins
        BY ONLY <1>fields, <1>arrays DEF SwiftCertificateArraysAsEmission, SwiftIndexedArray
    <1>normalized. NodeEmissionArrays(SwiftCertificateArraysAsEmission(expectedResult))
        BY <1>types, <1>functionShapes, <1>emission, SMT
            DEF SwiftCertificateArraysAsEmission, NodeEmissionArrays
    <1>certificate. LiteralReadAddCertificate(view, SwiftCertificateArraysAsEmission(expectedResult), inverse, fallback, bound)
        BY <1>expected, <1>normalized, <1>emission, SMT
            DEF LiteralReadAddCertificate, AllNodePayloadsMatchSource, NodePayloadMatchesSource,
                TypedVisitedSourceInputs, emitted, inverse, final, view, allocated
    <1>. QED BY ONLY <1>identified, <1>source, <1>arrays, <1>certificate

=============================================================================
