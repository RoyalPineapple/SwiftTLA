-------------------- MODULE AlternativeTraversalRule --------------------
EXTENDS TLAPS, NaturalsInduction, Sequences

CONSTANTS UpdateValues, FailureValues, NoFailure

Outcome == [updates: SUBSET UpdateValues, failure: FailureValues \cup {NoFailure}]

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
