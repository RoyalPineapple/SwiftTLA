---------------- MODULE DefinedChoiceDomainRule ----------------
EXTENDS TLAPS

SourceStep(defined, domain, branch) ==
    defined /\ (\E candidate \in domain : branch[candidate])
RenderedStep(defined, domain, branch) ==
    IF defined THEN (\E candidate \in domain : branch[candidate]) ELSE FALSE

SourceFirstFailure(defined, domain, bodyFails) ==
    IF ~defined THEN "domain"
    ELSE IF (\E candidate \in domain : bodyFails[candidate]) THEN "body"
    ELSE "none"
RenderedDomainFailure(defined) == ~defined
RenderedBodyFailure(defined, domain, bodyFails) ==
    IF defined THEN (\E candidate \in domain : bodyFails[candidate]) ELSE FALSE
RenderedFirstFailure(defined, domain, bodyFails) ==
    IF RenderedDomainFailure(defined) THEN "domain"
    ELSE IF RenderedBodyFailure(defined, domain, bodyFails) THEN "body"
    ELSE "none"

THEOREM DefinedDomainPreservesStepAndFirstFailure ==
    ASSUME NEW Values,
           NEW domain \in SUBSET Values,
           NEW defined \in BOOLEAN,
           NEW branch \in [domain -> BOOLEAN],
           NEW bodyFails \in [domain -> BOOLEAN]
    PROVE /\ SourceStep(defined, domain, branch)
               <=> RenderedStep(defined, domain, branch)
          /\ SourceFirstFailure(defined, domain, bodyFails)
               = RenderedFirstFailure(defined, domain, bodyFails)
    BY SMT DEF SourceStep, RenderedStep,
        SourceFirstFailure, RenderedDomainFailure,
        RenderedBodyFailure, RenderedFirstFailure

THEOREM UnguardedDomainIsNotEquivalent ==
    SourceStep(FALSE, {0}, [candidate \in {0} |-> TRUE])
      # (\E candidate \in {0} : TRUE)
    BY SMT DEF SourceStep

============================================================
