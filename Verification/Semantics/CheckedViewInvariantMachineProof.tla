---------------- MODULE CheckedViewInvariantMachineProof ----------------
EXTENDS CheckedViewInvariantRule, CheckingSelectionComposition
LOCAL Emitted(s) == INSTANCE CheckedViewInvariantMachine WITH slot <- s

Passed(v) == [ok |-> TRUE, value |-> v]
Entry(v) == DOMAIN v = {"id", "limit"} /\ v \in [id: Int, limit: Int]
Left(v) == Passed(v.id = 1)
Right(v) == Passed(v.limit = 2)
Mismatch(s, site) == [ok |-> FALSE, site |-> site, error |-> "noMatchingCase",
                      operands |-> <<>>, before |-> s]
First(s) == CheckedRead(Passed(s), Entry, Mismatch(s, "first view"))
SourceInvariant(s) ==
    ContinueWithView(First(s), TRUE, Left, Right,
                     CheckedRead(Passed(s), Entry, Mismatch(s, "second view")))
SingleViewInvariant(s) == ContinueWithView(First(s), TRUE, Left, Right, Passed(s))

THEOREM WithinLimitConsumesCheckedViewReuse ==
    ASSUME NEW s, Entry(s) \in BOOLEAN
    PROVE /\ SourceInvariant(s) = SingleViewInvariant(s)
          /\ (Entry(s) => SingleViewInvariant(s) = Passed(Emitted(s)!WithinLimit))
          /\ (~Entry(s) => SingleViewInvariant(s) = Mismatch(s, "first view"))
    PROOF
    <1>1. SourceInvariant(s) = SingleViewInvariant(s)
        BY RepeatedCheckedReadHasTheSameCompleteOutcome
            DEF SourceInvariant, SingleViewInvariant, First, Passed, Mismatch
    <1>2. Entry(s) => SingleViewInvariant(s) = Passed(Emitted(s)!WithinLimit)
        BY SMT DEF SingleViewInvariant, ContinueWithView, CheckedRead, First,
            Left, Right, Passed, Emitted!WithinLimit, Entry
    <1>3. ~Entry(s) => SingleViewInvariant(s) = Mismatch(s, "first view")
        BY SMT DEF SingleViewInvariant, ContinueWithView, CheckedRead, First,
            Mismatch, Passed
    <1>. QED BY <1>1, <1>2, <1>3

THEOREM ShortCircuitSkipsInvalidView == Emitted(0)!ShortCircuit
    BY SMT DEF Emitted!ShortCircuit

\* The shared checking parent consumes Boolean claims on the domain where
\* the predicate returns a Boolean. The preceding theorem retains failures.
SourceClaims(states) == [p \in {"WithinLimit"} |-> [s \in states |-> SourceInvariant(s).value]]
EmittedClaims(states) == [p \in {"WithinLimit"} |-> [s \in states |-> Emitted(s)!WithinLimit]]

THEOREM SelectedInvariantParentUsesTheActualExport ==
    ASSUME NEW states, NEW labels, NEW initials \in SUBSET states,
           NEW edges \in SUBSET (states \X labels \X states),
           \A s \in states : Entry(s)
    PROVE LET reached == SourceCheckingReachable(states, labels, initials, edges)
          IN SourceCheckingObservation(states, labels, initials, edges, {"WithinLimit"}, {},
                   SourceClaims(states), {}, {}, FALSE) =
             GeneratedCheckingObservation(labels, initials, edges, reached, {"WithinLimit"}, {},
                   EmittedClaims(states), {}, {}, FALSE)
    PROOF
    <1>1. \A s \in states : SourceInvariant(s).value = Emitted(s)!WithinLimit
        BY WithinLimitConsumesCheckedViewReuse DEF Passed
    <1>2. SourceCheckingReachable(states, labels, initials, edges) \subseteq states
        BY SMT DEF SourceCheckingReachable
    <1>bool. \A s \in states : Emitted(s)!WithinLimit \in BOOLEAN
        BY IsaM("auto") DEF Emitted!WithinLimit
    <1>3. /\ SourceClaims(states) \in [{"WithinLimit"} -> [states -> BOOLEAN]]
          /\ EmittedClaims(states) \in [{"WithinLimit"} -> [states -> BOOLEAN]]
          /\ \A p \in {"WithinLimit"} \cup {}, s \in states :
                 SourceClaims(states)[p][s] = EmittedClaims(states)[p][s]
        BY ONLY <1>1, <1>bool, SMT DEF SourceClaims, EmittedClaims
    <1>4. /\ {} \in SUBSET {} /\ {} \in SUBSET (states \X labels \X {})
          /\ {} \in SUBSET {"WithinLimit"} /\ {"WithinLimit"} \in SUBSET {"WithinLimit"}
          /\ FALSE \in BOOLEAN
        BY SMT
    <1>. QED BY <1>2, <1>3, <1>4, ExhaustiveSelectedCheckingObservationsCompose
=====================================================================
