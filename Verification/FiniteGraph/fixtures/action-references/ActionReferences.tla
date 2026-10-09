---- MODULE ActionReferences ----
EXTENDS Naturals
VARIABLE count
Init == count = 0
Advance(amount) == /\ count = 0
                   /\ count' = amount
AdvanceAny == \E amount \in {1, 2}: Advance(amount)
Stay == /\ count > 0
        /\ UNCHANGED count
Next == Advance(1) \/ Advance(2) \/ Stay
CanAdvance == (ENABLED AdvanceAny) \/ count > 0
InRange == count \in 0..2
EventuallyAdvanced == <>(count > 0)
Spec == /\ Init
        /\ [][Next]_count
        /\ WF_count(AdvanceAny)
====
