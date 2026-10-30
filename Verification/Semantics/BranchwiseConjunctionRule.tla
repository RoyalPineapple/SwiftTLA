-------------------- MODULE BranchwiseConjunctionRule --------------------
EXTENDS AlternativeTraversalRule

\* The continuation includes the compatible-write merge. The lowerer must
\* distribute alternatives before applying this single-candidate rule.
SourceAnd(left, continuation) ==
    IF left.failure # NoFailure
    THEN [updates |-> <<>>, failure |-> left.failure]
    ELSE IF Len(left.updates) = 0 THEN EmptyOrdered
    ELSE continuation[left.updates[1]]

THEOREM BranchwiseConjunctionRuleComposes ==
    ASSUME NEW sourceLeft \in SingleCandidateLeft,
           NEW generatedLeft \in SingleCandidateLeft,
           NEW sourceContinuation \in [UpdateValues -> OrderedOutcome],
           NEW generatedContinuation \in [UpdateValues -> OrderedOutcome],
           sourceLeft = generatedLeft,
           sourceContinuation = generatedContinuation
    PROVE SourceAnd(sourceLeft, sourceContinuation) =
              ContinueBranch(generatedLeft, generatedContinuation)
    BY SMT DEF SourceAnd, ContinueBranch, EmptyOrdered,
        SingleCandidateLeft, OrderedOutcome

THEOREM ConjunctionOutcomeIsClosed ==
    ASSUME NEW left \in OrderedOutcome,
           NEW continuation \in [UpdateValues -> OrderedOutcome]
    PROVE SourceAnd(left, continuation) \in OrderedOutcome
    BY LenProperties, ElementOfSeq, SMT
        DEF SourceAnd, EmptyOrdered, OrderedOutcome

THEOREM GeneratedConjunctionOutcomeIsClosed ==
    ASSUME NEW left \in OrderedOutcome,
           NEW continuation \in [UpdateValues -> OrderedOutcome]
    PROVE ContinueBranch(left, continuation) \in OrderedOutcome
    BY ElementOfSeq, SMT DEF ContinueBranch, OrderedOutcome

THEOREM OmittingTheContinuationChangesTheOutcome ==
    ASSUME NEW left \in SingleCandidateLeft,
           Len(left.updates) = 1,
           NEW continuation \in [UpdateValues -> OrderedOutcome],
           continuation[left.updates[1]] # left
    PROVE SourceAnd(left, continuation) # left
    BY SMT DEF SourceAnd, SingleCandidateLeft

=============================================================================
