-------------------- MODULE AlternativeTraversalRule --------------------
EXTENDS TLAPS, NaturalsInduction, SequenceTheorems_proofs

CONSTANTS UpdateValues, FailureValues, NoFailure

Outcome == [updates: SUBSET UpdateValues, failure: FailureValues \cup {NoFailure}]
OrderedOutcome == [updates: Seq(UpdateValues), failure: FailureValues \cup {NoFailure}]

CombineOrdered(first, second) ==
    [updates |-> first.updates \o second.updates,
     failure |-> IF first.failure # NoFailure
                THEN first.failure ELSE second.failure]

EmptyOrdered == [updates |-> <<>>, failure |-> NoFailure]

THEOREM OrderedCompositionIsClosed ==
    ASSUME NEW first \in OrderedOutcome,
           NEW second \in OrderedOutcome
    PROVE CombineOrdered(first, second) \in OrderedOutcome
    BY ConcatProperties, SMT DEF CombineOrdered, OrderedOutcome

THEOREM OrderedAlternativeCompositionIsAssociative ==
    ASSUME NEW first \in OrderedOutcome,
           NEW second \in OrderedOutcome,
           NEW third \in OrderedOutcome
    PROVE CombineOrdered(CombineOrdered(first, second), third) =
          CombineOrdered(first, CombineOrdered(second, third))
    PROOF
    <1>1. (first.updates \o second.updates) \o third.updates =
          first.updates \o (second.updates \o third.updates)
        BY ConcatAssociative DEF OrderedOutcome
    <1>. QED
        BY <1>1, SMT DEF CombineOrdered

THEOREM EmptyOrderedIsAnIdentity ==
    ASSUME NEW result \in OrderedOutcome
    PROVE /\ CombineOrdered(EmptyOrdered, result) = result
          /\ CombineOrdered(result, EmptyOrdered) = result
    BY ConcatEmptySeq, SMT DEF CombineOrdered, EmptyOrdered, OrderedOutcome

THEOREM ReversingFailingAlternativesChangesFirstFailure ==
    ASSUME NEW first \in OrderedOutcome,
           NEW second \in OrderedOutcome,
           first.failure # NoFailure,
           second.failure # NoFailure,
           first.failure # second.failure
    PROVE CombineOrdered(first, second).failure #
          CombineOrdered(second, first).failure
    BY SMT DEF CombineOrdered

SourceUpdates(results, prefix) ==
    UNION {results[index].updates : index \in 1..prefix}

SourceFirstFailure(results, prefix, failure) ==
    /\ ((failure = NoFailure) <=>
           (\A index \in 1..prefix : results[index].failure = NoFailure))
    /\ \A index \in 1..prefix :
           (results[index].failure # NoFailure
            /\ \A earlier \in 1..(index - 1) :
                   results[earlier].failure = NoFailure)
            => failure = results[index].failure

VisitedHistory(results, history) ==
    /\ history[0] = [updates |-> {}, failure |-> NoFailure]
    /\ \A index \in 1..Len(results) :
           history[index] =
               [updates |-> history[index - 1].updates \cup results[index].updates,
                failure |-> IF history[index - 1].failure # NoFailure
                           THEN history[index - 1].failure
                           ELSE results[index].failure]

VisitedOrderedHistory(results, history) ==
    /\ history[0] = [updates |-> <<>>, failure |-> NoFailure]
    /\ \A index \in 1..Len(results) :
           history[index] =
               [updates |-> history[index - 1].updates \o results[index].updates,
                failure |-> IF history[index - 1].failure # NoFailure
                           THEN history[index - 1].failure
                           ELSE results[index].failure]

THEOREM EveryFiniteAlternativeListHasAnOrderedHistory ==
    \A results \in Seq(OrderedOutcome) :
        \E history \in [0..Len(results) -> OrderedOutcome] :
            VisitedOrderedHistory(results, history)
    PROOF
    <1>. DEFINE P(results) ==
        \E history \in [0..Len(results) -> OrderedOutcome] :
            VisitedOrderedHistory(results, history)
    <1>1. P(<<>>)
        <2>. DEFINE empty == [index \in 0..0 |-> EmptyOrdered]
        <2>1. empty \in [0..0 -> OrderedOutcome]
            BY SMT DEF empty, EmptyOrdered, OrderedOutcome
        <2>2. VisitedOrderedHistory(<<>>, empty)
            BY SMT DEF VisitedOrderedHistory, empty, EmptyOrdered
        <2>. QED
            BY <2>1, <2>2, SMT DEF P
    <1>2. ASSUME NEW prior \in Seq(OrderedOutcome),
                  NEW next \in OrderedOutcome,
                  P(prior)
          PROVE P(Append(prior, next))
        <2>1. PICK history \in [0..Len(prior) -> OrderedOutcome] :
                 VisitedOrderedHistory(prior, history)
            BY P(prior), SMT DEF P
        <2>. DEFINE extended ==
            [index \in 0..(Len(prior) + 1) |->
                IF index <= Len(prior) THEN history[index]
                ELSE CombineOrdered(history[Len(prior)], next)]
        <2>2. CombineOrdered(history[Len(prior)], next) \in OrderedOutcome
            BY <2>1, OrderedCompositionIsClosed, SMT
        <2>3. Len(Append(prior, next)) = Len(prior) + 1
            BY AppendProperties
        <2>4. extended \in [0..Len(Append(prior, next)) -> OrderedOutcome]
            <3>1. \A index \in 0..(Len(prior) + 1) :
                      extended[index] \in OrderedOutcome
                <4>. SUFFICES ASSUME NEW index \in 0..(Len(prior) + 1)
                             PROVE extended[index] \in OrderedOutcome
                    BY SMT
                <4>1. CASE index <= Len(prior)
                    BY <2>1, <4>1, SMT DEF extended
                <4>2. CASE index > Len(prior)
                    BY <2>2, <4>2, SMT DEF extended
                <4>. QED BY <4>1, <4>2, SMT
            <3>. QED BY <2>3, <3>1, SMT DEF extended
        <2>5. VisitedOrderedHistory(Append(prior, next), extended)
            <3>1. \A index \in 0..Len(prior) :
                      extended[index] = history[index]
                BY SMT DEF extended
            <3>2. extended[Len(prior) + 1] =
                     CombineOrdered(history[Len(prior)], next)
                BY SMT DEF extended
            <3>3. \A index \in 1..Len(prior) :
                      Append(prior, next)[index] = prior[index]
                BY AppendProperties, SMT
            <3>4. Append(prior, next)[Len(prior) + 1] = next
                BY AppendProperties, SMT
            <3>5. extended[0] = EmptyOrdered
                BY <2>1, <3>1, SMT DEF VisitedOrderedHistory, EmptyOrdered
            <3>6. \A index \in 1..Len(prior) :
                      extended[index] =
                          CombineOrdered(extended[index - 1], Append(prior, next)[index])
                BY <2>1, <3>1, <3>3, SMT
                   DEF VisitedOrderedHistory, CombineOrdered
            <3>7. extended[Len(prior) + 1] =
                      CombineOrdered(extended[Len(prior)], Append(prior, next)[Len(prior) + 1])
                BY <3>1, <3>2, <3>4, SMT
            <3>8. \A index \in 1..Len(Append(prior, next)) :
                      extended[index] =
                          CombineOrdered(extended[index - 1], Append(prior, next)[index])
                <4>. SUFFICES ASSUME NEW index \in 1..Len(Append(prior, next))
                             PROVE extended[index] =
                                   CombineOrdered(extended[index - 1], Append(prior, next)[index])
                    BY SMT
                <4>1. CASE index <= Len(prior)
                    BY <3>6, <4>1, SMT
                <4>2. CASE index > Len(prior)
                    BY <2>3, <3>7, <4>2, SMT
                <4>. QED BY <4>1, <4>2, SMT
            <3>9. \A index \in 1..Len(Append(prior, next)) :
                      extended[index] =
                          [updates |-> extended[index - 1].updates \o Append(prior, next)[index].updates,
                           failure |-> IF extended[index - 1].failure # NoFailure
                                      THEN extended[index - 1].failure
                                      ELSE Append(prior, next)[index].failure]
                BY <3>8, SMT DEF CombineOrdered
            <3>. QED
                BY <3>5, <3>9, SMT DEF VisitedOrderedHistory, EmptyOrdered
        <2>. QED
            BY <2>4, <2>5, SMT DEF P
    <1>. QED
        BY <1>1, <1>2, SequencesInductionAppend DEF P

THEOREM OrderedHistoryPreservesItsPrefix ==
    ASSUME NEW first \in Seq(OrderedOutcome),
           NEW second \in Seq(OrderedOutcome),
           NEW combined \in Seq(OrderedOutcome),
           combined = first \o second,
           NEW firstHistory \in [0..Len(first) -> OrderedOutcome],
           NEW combinedHistory \in [0..Len(combined) -> OrderedOutcome],
           VisitedOrderedHistory(first, firstHistory),
           VisitedOrderedHistory(combined, combinedHistory)
    PROVE \A index \in 0..Len(first) :
              combinedHistory[index] = firstHistory[index]
    PROOF
    <1>. DEFINE P(index) ==
        index \in 0..Len(first) => combinedHistory[index] = firstHistory[index]
    <1>1. P(0)
        BY SMT DEF P, VisitedOrderedHistory
    <1>2. ASSUME NEW index \in Nat, P(index)
          PROVE P(index + 1)
        <2>. SUFFICES ASSUME index + 1 \in 0..Len(first)
                     PROVE combinedHistory[index + 1] = firstHistory[index + 1]
            BY SMT DEF P
        <2>1. index \in 0..Len(first)
            BY SMT DEF P
        <2>2. combined[index + 1] = first[index + 1]
            BY ConcatProperties, SMT DEF OrderedOutcome
        <2>3. combinedHistory[index + 1] =
                 CombineOrdered(combinedHistory[index], combined[index + 1])
            BY SMT DEF VisitedOrderedHistory, CombineOrdered
        <2>4. firstHistory[index + 1] =
                 CombineOrdered(firstHistory[index], first[index + 1])
            BY SMT DEF VisitedOrderedHistory, CombineOrdered
        <2>. QED
            BY <2>1, <2>2, <2>3, <2>4, P(index), SMT DEF P
    <1>3. \A index \in Nat : P(index)
        BY <1>1, <1>2, NatInduction
    <1>. QED
        BY <1>3, SMT DEF P

THEOREM ConsecutiveAlternativeHistoriesCompose ==
    ASSUME NEW first \in Seq(OrderedOutcome),
           NEW second \in Seq(OrderedOutcome),
           NEW combined \in Seq(OrderedOutcome),
           combined = first \o second,
           NEW firstHistory \in [0..Len(first) -> OrderedOutcome],
           NEW secondHistory \in [0..Len(second) -> OrderedOutcome],
           NEW combinedHistory \in [0..Len(combined) -> OrderedOutcome],
           VisitedOrderedHistory(first, firstHistory),
           VisitedOrderedHistory(second, secondHistory),
           VisitedOrderedHistory(combined, combinedHistory)
    PROVE combinedHistory[Len(combined)] =
          CombineOrdered(firstHistory[Len(first)], secondHistory[Len(second)])
    PROOF
    <1>1. \A index \in 0..Len(first) :
              combinedHistory[index] = firstHistory[index]
        BY OrderedHistoryPreservesItsPrefix
    <1>. DEFINE P(offset) ==
        offset \in 0..Len(second) =>
            combinedHistory[Len(first) + offset] =
                CombineOrdered(firstHistory[Len(first)], secondHistory[offset])
    <1>2. P(0)
        BY <1>1, EmptyOrderedIsAnIdentity, SMT
           DEF P, VisitedOrderedHistory, EmptyOrdered
    <1>3. ASSUME NEW offset \in Nat, P(offset)
          PROVE P(offset + 1)
        <2>. SUFFICES ASSUME offset + 1 \in 0..Len(second)
                     PROVE combinedHistory[Len(first) + offset + 1] =
                           CombineOrdered(firstHistory[Len(first)], secondHistory[offset + 1])
            BY SMT DEF P
        <2>1. offset \in 0..Len(second)
            BY SMT DEF P
        <2>2. combined[Len(first) + offset + 1] = second[offset + 1]
            BY ConcatProperties, SMT DEF OrderedOutcome
        <2>3. combinedHistory[Len(first) + offset + 1] =
                 CombineOrdered(combinedHistory[Len(first) + offset],
                     combined[Len(first) + offset + 1])
            BY SMT DEF VisitedOrderedHistory, CombineOrdered
        <2>4. secondHistory[offset + 1] =
                 CombineOrdered(secondHistory[offset], second[offset + 1])
            BY SMT DEF VisitedOrderedHistory, CombineOrdered
        <2>5. CombineOrdered(
                 CombineOrdered(firstHistory[Len(first)], secondHistory[offset]),
                 second[offset + 1]) =
                 CombineOrdered(firstHistory[Len(first)],
                     CombineOrdered(secondHistory[offset], second[offset + 1]))
            BY OrderedAlternativeCompositionIsAssociative
        <2>. QED
            BY <2>1, <2>2, <2>3, <2>4, <2>5, P(offset), SMT DEF P
    <1>4. \A offset \in Nat : P(offset)
        BY <1>2, <1>3, NatInduction
    <1>5. Len(combined) = Len(first) + Len(second)
        BY ConcatProperties
    <1>. QED
        BY <1>4, <1>5, SMT DEF P

THEOREM OrderedAlternativeRetainsEveryEarlierUpdate ==
    ASSUME NEW results \in Seq(OrderedOutcome),
           NEW history \in [0..Len(results) -> OrderedOutcome],
           VisitedOrderedHistory(results, history)
    PROVE \A index \in 1..Len(results) :
              /\ Len(history[index].updates) =
                     Len(history[index - 1].updates) + Len(results[index].updates)
              /\ \A earlier \in 1..Len(history[index - 1].updates) :
                     history[index].updates[earlier] =
                         history[index - 1].updates[earlier]
              /\ \A offset \in 1..Len(results[index].updates) :
                     history[index].updates[Len(history[index - 1].updates) + offset] =
                         results[index].updates[offset]
    PROOF
    <1>. SUFFICES ASSUME NEW index \in 1..Len(results)
                 PROVE /\ Len(history[index].updates) =
                              Len(history[index - 1].updates) + Len(results[index].updates)
                       /\ \A earlier \in 1..Len(history[index - 1].updates) :
                              history[index].updates[earlier] =
                                  history[index - 1].updates[earlier]
                       /\ \A offset \in 1..Len(results[index].updates) :
                              history[index].updates[Len(history[index - 1].updates) + offset] =
                                  results[index].updates[offset]
        BY SMT
    <1>1. history[index].updates =
              history[index - 1].updates \o results[index].updates
        BY SMT DEF VisitedOrderedHistory
    <1>2. history[index - 1].updates \in Seq(UpdateValues)
           /\ results[index].updates \in Seq(UpdateValues)
        BY SMT DEF OrderedOutcome
    <1>3. /\ Len(history[index - 1].updates \o results[index].updates) =
                  Len(history[index - 1].updates) + Len(results[index].updates)
          /\ \A offset \in 1..Len(history[index - 1].updates) +
                              Len(results[index].updates) :
                 (history[index - 1].updates \o results[index].updates)[offset] =
                     IF offset <= Len(history[index - 1].updates)
                     THEN history[index - 1].updates[offset]
                     ELSE results[index].updates[offset - Len(history[index - 1].updates)]
        BY ConcatProperties, <1>2, SMT
    <1>3a. Len(history[index - 1].updates) \in Nat
            /\ Len(results[index].updates) \in Nat
        BY LenProperties, <1>2, SMT
    <1>4. Len(history[index].updates) =
              Len(history[index - 1].updates) + Len(results[index].updates)
        BY <1>1, <1>3, SMT
    <1>5. \A earlier \in 1..Len(history[index - 1].updates) :
              history[index].updates[earlier] = history[index - 1].updates[earlier]
        PROOF
        <2>. SUFFICES ASSUME NEW earlier \in 1..Len(history[index - 1].updates)
                     PROVE history[index].updates[earlier] =
                               history[index - 1].updates[earlier]
            BY SMT
        <2>1. earlier \in 1..Len(history[index - 1].updates) +
                           Len(results[index].updates)
            BY <1>3a, SMT
        <2>. QED
            BY <1>1, <1>3, <1>3a, <2>1, SMT
    <1>6. \A offset \in 1..Len(results[index].updates) :
              history[index].updates[Len(history[index - 1].updates) + offset] =
                  results[index].updates[offset]
        PROOF
        <2>. SUFFICES ASSUME NEW offset \in 1..Len(results[index].updates)
                     PROVE history[index].updates[Len(history[index - 1].updates) + offset] =
                               results[index].updates[offset]
            BY SMT
        <2>1. Len(history[index - 1].updates) + offset \in
                 1..Len(history[index - 1].updates) + Len(results[index].updates)
            BY <1>3a, SMT
        <2>2. Len(history[index - 1].updates) + offset >
                 Len(history[index - 1].updates)
            BY <1>3a, SMT
        <2>. QED
            BY <1>1, <1>3, <1>3a, <2>1, <2>2, SMT
    <1>. QED
        BY <1>4, <1>5, <1>6, SMT

THEOREM AlternativeTraversalPreservesSuccessfulUpdates ==
    ASSUME NEW results \in Seq(Outcome),
           NEW history \in [0..Len(results) -> Outcome],
           VisitedHistory(results, history)
    PROVE  \A index \in 0..Len(results) :
               history[index].updates = SourceUpdates(results, index)
    PROOF
    <1>. DEFINE P(index) ==
        index \in 0..Len(results) =>
            history[index].updates = SourceUpdates(results, index)
    <1>1. P(0)
        BY SMT DEF P, VisitedHistory, SourceUpdates
    <1>2. ASSUME NEW index \in Nat, P(index)
          PROVE P(index + 1)
        <2>. SUFFICES ASSUME index + 1 \in 0..Len(results)
                     PROVE history[index + 1].updates =
                               SourceUpdates(results, index + 1)
            BY SMT DEF P
        <2>1. index \in 0..Len(results)
            BY SMT DEF P
        <2>2. history[index + 1] =
                 [updates |-> history[index].updates \cup results[index + 1].updates,
                  failure |-> IF history[index].failure # NoFailure
                             THEN history[index].failure
                             ELSE results[index + 1].failure]
            BY SMT DEF VisitedHistory
        <2>3. SourceUpdates(results, index + 1) =
                 SourceUpdates(results, index) \cup results[index + 1].updates
            BY SMT DEF SourceUpdates
        <2>. QED
            BY <2>1, <2>2, <2>3, P(index), SMT DEF P
    <1>3. \A index \in Nat : P(index)
        BY <1>1, <1>2, NatInduction
    <1>4. QED
        BY <1>3, SMT DEF P

THEOREM AlternativeTraversalPreservesFirstFailure ==
    ASSUME NEW results \in Seq(Outcome),
           NEW history \in [0..Len(results) -> Outcome],
           VisitedHistory(results, history)
    PROVE  \A index \in 0..Len(results) :
               SourceFirstFailure(results, index, history[index].failure)
    PROOF
    <1>. DEFINE P(index) ==
        index \in 0..Len(results) =>
            SourceFirstFailure(results, index, history[index].failure)
    <1>1. P(0)
        BY SMT DEF P, VisitedHistory, SourceFirstFailure
    <1>2. ASSUME NEW index \in Nat, P(index)
          PROVE P(index + 1)
        <2>. SUFFICES ASSUME index + 1 \in 0..Len(results)
                     PROVE SourceFirstFailure(results, index + 1,
                               history[index + 1].failure)
            BY SMT DEF P
        <2>1. index \in 0..Len(results)
            BY SMT DEF P
        <2>2. SourceFirstFailure(results, index, history[index].failure)
            BY <2>1, P(index), SMT DEF P
        <2>3. history[index + 1].failure =
                 IF history[index].failure # NoFailure
                 THEN history[index].failure
                 ELSE results[index + 1].failure
            BY SMT DEF VisitedHistory
        <2>4. CASE history[index].failure # NoFailure
            BY <2>1, <2>2, <2>3, <2>4, SMT DEF SourceFirstFailure
        <2>5. CASE history[index].failure = NoFailure
            BY <2>1, <2>2, <2>3, <2>5, SMT DEF SourceFirstFailure
        <2>. QED
            BY <2>4, <2>5, SMT
    <1>3. \A index \in Nat : P(index)
        BY <1>1, <1>2, NatInduction
    <1>4. QED
        BY <1>3, SMT DEF P

THEOREM ReplacingFirstFailureWithLastIsIncorrect ==
    ASSUME NEW first \in FailureValues,
           NEW last \in FailureValues,
           first # NoFailure,
           last # NoFailure,
           first # last
    PROVE ~SourceFirstFailure(
        <<[updates |-> {}, failure |-> first],
          [updates |-> {}, failure |-> last]>>, 2, last)
    BY SMT DEF SourceFirstFailure

=============================================================================
