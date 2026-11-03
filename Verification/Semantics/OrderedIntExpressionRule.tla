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

=============================================================================
