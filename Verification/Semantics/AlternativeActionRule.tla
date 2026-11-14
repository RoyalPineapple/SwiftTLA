-------------------- MODULE AlternativeActionRule --------------------
EXTENDS AlternativeTraversalRule

SourceOr(first, second) ==
    [updates |-> first.updates \o second.updates,
     failure |-> IF first.failure = NoFailure THEN second.failure ELSE first.failure]

THEOREM AlternativeRuleComposes ==
    ASSUME NEW sourceFirst \in OrderedOutcome, NEW sourceSecond \in OrderedOutcome,
           NEW generatedFirst \in OrderedOutcome, NEW generatedSecond \in OrderedOutcome,
           sourceFirst = generatedFirst, sourceSecond = generatedSecond
    PROVE SourceOr(sourceFirst, sourceSecond) =
              CombineOrdered(generatedFirst, generatedSecond)
    BY SMT DEF SourceOr, CombineOrdered

THEOREM AlternativeOutcomeIsClosed ==
    ASSUME NEW first \in OrderedOutcome, NEW second \in OrderedOutcome
    PROVE SourceOr(first, second) \in OrderedOutcome
    BY OrderedCompositionIsClosed, SMT DEF SourceOr, CombineOrdered

THEOREM AlternativeRetainsCompleteSuccessorsAlongsideFailure ==
    ASSUME NEW fields, NEW values,
           NEW prior \in [fields -> values], NEW label,
           NEW finish \in [UpdateValues -> [fields -> values]],
           NEW first \in OrderedOutcome, NEW second \in OrderedOutcome
    PROVE LET combined == CompleteLabeledOutcome(prior, label, finish, NoFailure,
                              CombineOrdered(first, second))
              left == CompleteLabeledOutcome(prior, label, finish, NoFailure, first)
              right == CompleteLabeledOutcome(prior, label, finish, NoFailure, second)
          IN /\ combined.successors = left.successors \cup right.successors
             /\ combined.selectedFailure =
                    IF first.failure = NoFailure THEN second.failure ELSE first.failure
    PROOF
    <1>1. first.updates \in Seq(UpdateValues) /\
          second.updates \in Seq(UpdateValues)
        BY SMT DEF OrderedOutcome
    <1>2. /\ Len(first.updates) \in Nat
          /\ Len(second.updates) \in Nat
          /\ Len(first.updates \o second.updates) =
                 Len(first.updates) + Len(second.updates)
          /\ \A index \in 1..(Len(first.updates) + Len(second.updates)) :
                 (first.updates \o second.updates)[index] =
                     IF index <= Len(first.updates) THEN first.updates[index]
                     ELSE second.updates[index - Len(first.updates)]
        BY <1>1, LenProperties, ConcatProperties
    <1>3. \A index \in 1..Len(first.updates) :
              (first.updates \o second.updates)[index] = first.updates[index]
        BY <1>2, SMT
    <1>4. \A index \in 1..Len(second.updates) :
              (first.updates \o second.updates)[Len(first.updates) + index] =
                  second.updates[index]
        BY <1>2, SMT
    <1>. DEFINE combined == {finish[(first.updates \o second.updates)[index]] :
                                index \in 1..Len(first.updates \o second.updates)}
                left == {finish[first.updates[index]] : index \in 1..Len(first.updates)}
                right == {finish[second.updates[index]] : index \in 1..Len(second.updates)}
    <1>5. combined \subseteq left \cup right
        <2>. SUFFICES ASSUME NEW target \in combined
                     PROVE target \in left \cup right
            BY SMT
        <2>1. PICK index \in 1..Len(first.updates \o second.updates) :
                  target = finish[(first.updates \o second.updates)[index]]
            BY SMT DEF combined
        <2>2. CASE index <= Len(first.updates)
            BY <1>2, <1>3, <2>1, <2>2, SMT DEF left
        <2>3. CASE index > Len(first.updates)
            BY <1>2, <2>1, <2>3, SMT DEF right
        <2>. QED BY <1>2, <2>1, <2>2, <2>3, SMT
    <1>6. left \cup right \subseteq combined
        <2>. SUFFICES ASSUME NEW target \in left \cup right
                     PROVE target \in combined
            BY SMT
        <2>1. CASE target \in left
            <3>1. PICK index \in 1..Len(first.updates) :
                      target = finish[first.updates[index]]
                BY <2>1, SMT DEF left
            <3>. QED BY <1>2, <1>3, <3>1, SMT DEF combined
        <2>2. CASE target \in right
            <3>1. PICK index \in 1..Len(second.updates) :
                      target = finish[second.updates[index]]
                BY <2>2, SMT DEF right
            <3>. QED BY <1>2, <1>4, <3>1, SMT DEF combined
        <2>. QED BY <2>1, <2>2, SMT
    <1>. QED
        BY <1>5, <1>6, SMT
            DEF CompleteLabeledOutcome, CombineOrdered, combined, left, right

THEOREM ChoosingTheLastFailureChangesItsPayload ==
    ASSUME NEW first \in OrderedOutcome, NEW second \in OrderedOutcome,
           first.failure # NoFailure, second.failure # NoFailure,
           first.failure # second.failure
    PROVE SourceOr(first, second).failure # second.failure
    BY SMT DEF SourceOr

=============================================================================
