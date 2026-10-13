---------------- MODULE DefinedActionFailureRule ----------------
EXTENDS TLAPS

SourceDefinedStep(defined, value, body) == defined /\ body[value]
RenderedDefinedStep(defined, value, body) ==
    IF defined THEN (LET bound == value IN body[bound]) ELSE FALSE
SourceFirstFailure(defined, value, bodyFails) ==
    IF ~defined THEN "binding"
    ELSE IF bodyFails[value] THEN "body" ELSE "none"
RenderedBindingFailure(defined) == ~defined
RenderedBodyFailure(defined, value, bodyFails) ==
    IF defined THEN (LET bound == value IN bodyFails[bound]) ELSE FALSE
RenderedFirstFailure(defined, value, bodyFails) ==
    IF RenderedBindingFailure(defined) THEN "binding"
    ELSE IF RenderedBodyFailure(defined, value, bodyFails) THEN "body"
    ELSE "none"

THEOREM DefinedActionPreservesStepAndFirstFailure ==
    ASSUME NEW domain, NEW value \in domain,
           NEW body \in [domain -> BOOLEAN],
           NEW defined \in BOOLEAN,
           NEW bodyFails \in [domain -> BOOLEAN]
    PROVE /\ (SourceDefinedStep(defined, value, body)
                <=> RenderedDefinedStep(defined, value, body))
          /\ SourceFirstFailure(defined, value, bodyFails)
                = RenderedFirstFailure(defined, value, bodyFails)
    BY SMT DEF SourceDefinedStep, RenderedDefinedStep,
        SourceFirstFailure, RenderedFirstFailure,
        RenderedBindingFailure, RenderedBodyFailure

DroppedBodyFailure(defined) ==
    IF ~defined THEN "binding" ELSE "none"

THEOREM OmittingBoundBodyFailureIsRejected ==
    SourceFirstFailure(TRUE, 0, [x \in {0} |-> TRUE])
        # DroppedBodyFailure(TRUE)
    BY SMT DEF SourceFirstFailure, DroppedBodyFailure

=================================================================
