------------- MODULE BranchwiseConjunctionFailureOrderProof -------------
EXTENDS TLAPS, BranchwiseConjunctionFailureOrderModel
LOCAL INSTANCE SequenceTheorems

LOCAL FailurePayloads ==
    Seq(Int \cup Seq(Int) \cup {"divisionByZero", "negativeModuloDivisor", "integerOverflow", "division"})
LOCAL ObservedFailureEvents ==
    [source: Seq(Int), action: Nat, branch: Nat, site: Nat, target: Nat, payload: FailurePayloads,
     before: Seq([binding: Nat, target: Nat, value: Int])]
LOCAL MissingObservedFailure ==
    [source |-> <<>>, action |-> -1, branch |-> 0, site |-> 0, target |-> 0,
     payload |-> <<>>, before |-> <<>>]
LOCAL FailureHistory == INSTANCE ActionTreeOutcomeComposition
    WITH UpdateValues <- {0}, FailureValues <- ObservedFailureEvents, NoFailure <- MissingObservedFailure

SourceDomain ==
    /\ divisor \in 0..1
    /\ modulus \in {-1, 0, 1, 2}
    /\ selected \in Int
    /\ result \in Int

SourceInit ==
    /\ divisor \in 0..1
    /\ modulus \in {-1, 0, 1, 2}
    /\ selected = -1
    /\ result = 0

\* Either is visited branch by branch. The first branch sets selected to zero;
\* both branches then evaluate the shared division before committing a step.
SourcePick ==
    /\ UNCHANGED <<divisor, modulus>>
    /\ divisor = 1
    /\ \/ selected' = 0 /\ result' = 1
       \/ modulus > 0 /\ selected' = 1 % modulus /\ result' = 1

SourceFirstDivisionFailure == divisor = 0
SourceLaterModuloZeroFailure == divisor = 1 /\ modulus = 0
SourceLaterNegativeModuloFailure == divisor = 1 /\ modulus < 0
SourceEvaluationOK == divisor = 1 /\ modulus > 0
UngatedLaterModuloFailure == modulus < 0

THEOREM EmittedInitialMatchesSource ==
    Init <=> SourceInit
    BY DEF Init, SourceInit

THEOREM EmittedInitialInDomain ==
    Init => SourceDomain
    BY SMT DEF Init, SourceDomain

THEOREM EmittedStepPreservesDomain ==
    ASSUME SourceDomain, pick
    PROVE divisor' \in 0..1 /\ modulus' \in {-1, 0, 1, 2}
          /\ selected' \in Int /\ result' \in Int
    BY SMT DEF SourceDomain, pick

THEOREM EmittedStepMatchesSource ==
    ASSUME SourceDomain, divisor' \in Int, modulus' \in Int,
           selected' \in Int, result' \in Int
    PROVE pick <=> SourcePick
    BY SMT DEF SourceDomain, SourcePick, pick

THEOREM EmittedFirstFailureMatchesSource ==
    ASSUME SourceDomain
    PROVE /\ __SwiftTLADivisionByZeroFailure0 <=> SourceFirstDivisionFailure
          /\ __SwiftTLADivisionByZeroDivisor0 = divisor
          /\ ~__SwiftTLAOverflowFailure0
          /\ __SwiftTLADivisionByZeroFailure0_1 <=> SourceLaterModuloZeroFailure
          /\ __SwiftTLANegativeModuloDivisorFailure0 <=> SourceLaterNegativeModuloFailure
          /\ __SwiftTLANegativeModuloDivisorValue0 = modulus
          /\ ~__SwiftTLADivisionByZeroFailure0_2
          /\ ~__SwiftTLAOverflowFailure0_1
          /\ __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY SMT DEF SourceDomain, SourceFirstDivisionFailure,
        SourceLaterModuloZeroFailure, SourceLaterNegativeModuloFailure,
        SourceEvaluationOK, __SwiftTLADivisionByZeroFailure0,
        __SwiftTLADivisionByZeroDivisor0, __SwiftTLAOverflowFailure0,
        __SwiftTLADivisionByZeroFailure0_1,
        __SwiftTLANegativeModuloDivisorFailure0,
        __SwiftTLANegativeModuloDivisorValue0,
        __SwiftTLADivisionByZeroFailure0_2, __SwiftTLAOverflowFailure0_1,
        __SwiftTLAAnyEvaluationFailure0, __SwiftTLAEvaluationOK

\* The generated visitor exhausts the left branch before the right branch and
\* appends a caught reason as it is reached. The TLA+ sequence represents this
\* order by concatenation. Both TLA+ records and the exhaustive validator's
\* typed native evidence retain the lexical prefixes. The selected checks
\* still use the first reason.
LOCAL FailureEvent(branch, site, target, payload, prefix) ==
    [source |-> vars, action |-> 0, branch |-> branch, site |-> site, target |-> target,
     payload |-> payload, before |-> prefix]
LOCAL DivisionEvent(branch, site, target, prefix) ==
    FailureEvent(branch, site, target, <<"divisionByZero">>, prefix)
LOCAL NegativeModuloEvent ==
    FailureEvent(1, 2, 2, <<"negativeModuloDivisor", modulus>>, <<>>)
LOCAL LeftBefore == <<[binding |-> 0, target |-> 2, value |-> 0]>>
LOCAL RightBefore == <<[binding |-> 2, target |-> 2, value |-> 1 % modulus]>>

SourceLeftFailureHistory ==
    IF divisor = 0 THEN <<DivisionEvent(0, 1, 3, LeftBefore)>> ELSE <<>>
SourceRightFailureHistory ==
    IF modulus = 0 THEN <<DivisionEvent(1, 2, 2, <<>>)>>
    ELSE IF modulus < 0 THEN <<NegativeModuloEvent>>
    ELSE IF divisor = 0 THEN <<DivisionEvent(1, 3, 3, RightBefore)>> ELSE <<>>

LOCAL THEOREM SourceBranchwiseFailureHistoriesAreTyped ==
    ASSUME SourceDomain
    PROVE /\ SourceLeftFailureHistory \in Seq(ObservedFailureEvents)
          /\ SourceRightFailureHistory \in Seq(ObservedFailureEvents)
          /\ MissingObservedFailure \notin ObservedFailureEvents
    PROOF
    <1>single. \A S : \A element \in S : <<element>> \in Seq(S)
        <2>. TAKE S
        <2>. TAKE element \in S
        <2>domain. /\ <<element>> \in [1..1 -> S] /\ 1 \in Nat
            BY ONLY (element \in S), SMT
        <2>. QED BY ONLY <2>domain, SeqDef, Isa
    <1>typed. /\ SourceLeftFailureHistory \in Seq(ObservedFailureEvents)
               /\ SourceRightFailureHistory \in Seq(ObservedFailureEvents)
               /\ MissingObservedFailure \notin ObservedFailureEvents
        <2>. DEFINE bindings == [binding: Nat, target: Nat, value: Int]
                    payloadValues == Int \cup Seq(Int) \cup
                        {"divisionByZero", "negativeModuloDivisor", "integerOverflow", "division"}
        <2>source. /\ vars \in [1..4 -> Int] /\ 4 \in Nat
            BY ONLY SourceDomain, SMT DEF SourceDomain, vars
        <2>snapshot. vars \in Seq(Int)
            BY ONLY <2>source, SeqDef, SMT
        <2>modulo. modulus > 0 => 1 % modulus \in Int
            BY ONLY SourceDomain, SMT DEF SourceDomain
        <2>bindings. /\ [binding |-> 0, target |-> 2, value |-> 0] \in bindings
                      /\ (modulus > 0 =>
                            [binding |-> 2, target |-> 2, value |-> 1 % modulus] \in bindings)
            BY ONLY <2>modulo, SMT DEF bindings
        <2>prefix. /\ LeftBefore \in Seq(bindings)
                    /\ <<>> \in Seq(bindings)
                    /\ (modulus > 0 => RightBefore \in Seq(bindings))
            BY ONLY <2>bindings, <1>single, EmptySeq, Isa DEF LeftBefore, RightBefore
        <2>payloadFields. /\ "divisionByZero" \in payloadValues
                          /\ <<"negativeModuloDivisor", modulus>> \in [1..2 -> payloadValues]
                          /\ 2 \in Nat
            BY ONLY SourceDomain, SMT DEF SourceDomain, payloadValues
        <2>division. <<"divisionByZero">> \in FailurePayloads
            BY ONLY <2>payloadFields, <1>single, Isa DEF FailurePayloads, payloadValues
        <2>negativeModulo. <<"negativeModuloDivisor", modulus>> \in FailurePayloads
            BY ONLY <2>payloadFields, SeqDef, SMT DEF FailurePayloads, payloadValues
        <2>payloads. /\ <<"divisionByZero">> \in FailurePayloads
                      /\ <<"negativeModuloDivisor", modulus>> \in FailurePayloads
            BY ONLY <2>division, <2>negativeModulo
        <2>left. DivisionEvent(0, 1, 3, LeftBefore) \in ObservedFailureEvents
            BY ONLY <2>snapshot, <2>prefix, <2>payloads, SMT
                DEF DivisionEvent, FailureEvent, ObservedFailureEvents, bindings
        <2>right. /\ DivisionEvent(1, 2, 2, <<>>) \in ObservedFailureEvents
                   /\ NegativeModuloEvent \in ObservedFailureEvents
                   /\ (modulus > 0 => DivisionEvent(1, 3, 3, RightBefore) \in ObservedFailureEvents)
            BY ONLY <2>snapshot, <2>prefix, <2>payloads, SMT
                DEF DivisionEvent, NegativeModuloEvent, FailureEvent, ObservedFailureEvents, bindings
        <2>none. MissingObservedFailure \notin ObservedFailureEvents
            <3>action. MissingObservedFailure \in ObservedFailureEvents => MissingObservedFailure.action \in Nat
                BY ONLY SMT DEF ObservedFailureEvents
            <3>reserved. MissingObservedFailure.action = -1 /\ -1 \notin Nat
                BY ONLY SMT DEF MissingObservedFailure
            <3>. QED BY ONLY <3>action, <3>reserved, SMT
        <2>. QED BY ONLY SourceDomain, <2>left, <2>right, <2>none, <1>single, EmptySeq, SMT
            DEF SourceDomain, SourceLeftFailureHistory, SourceRightFailureHistory
    <1>. QED BY ONLY <1>typed

THEOREM EmittedActionFailureHistoryMatchesBranchwiseHistory ==
    ASSUME SourceDomain
    PROVE /\ __SwiftTLAActionFailureHistory0 =
                 FailureHistory!ActionAlternativeFailureHistory(SourceLeftFailureHistory, SourceRightFailureHistory)
          /\ Len(__SwiftTLAActionFailureHistory0) =
                 Len(SourceLeftFailureHistory) + Len(SourceRightFailureHistory)
          /\ FailureHistory!ActionFailureEventSet(__SwiftTLAActionFailureHistory0) =
                 FailureHistory!ActionFailureEventSet(SourceLeftFailureHistory) \cup
                 FailureHistory!ActionFailureEventSet(SourceRightFailureHistory)
          /\ \A index \in 1..Len(SourceRightFailureHistory) :
                 __SwiftTLAActionFailureHistory0[Len(SourceLeftFailureHistory) + index] =
                    SourceRightFailureHistory[index]
    PROOF
    <1>typed. /\ SourceLeftFailureHistory \in Seq(ObservedFailureEvents)
               /\ SourceRightFailureHistory \in Seq(ObservedFailureEvents)
               /\ MissingObservedFailure \notin ObservedFailureEvents
        BY ONLY SourceDomain, SourceBranchwiseFailureHistoriesAreTyped

    <1>emitted. __SwiftTLAActionFailureHistory0 =
                  FailureHistory!ActionAlternativeFailureHistory(SourceLeftFailureHistory, SourceRightFailureHistory)
        <2>. DEFINE zero == IF modulus = 0 THEN <<DivisionEvent(1, 2, 2, <<>>)>> ELSE <<>>
                    negative == IF modulus < 0 THEN <<NegativeModuloEvent>> ELSE <<>>
                    late == IF modulus > 0 /\ divisor = 0 THEN <<DivisionEvent(1, 3, 3, RightBefore)>> ELSE <<>>
        <2>bounds. /\ divisor # -1 /\ (modulus = 0 \/ modulus < 0 \/ modulus > 0)
            BY ONLY SourceDomain, SMT DEF SourceDomain
        <2>. DEFINE divisionOverflow ==
                        IF divisor # 0 THEN
                           ~((IF divisor # -1 THEN TRUE ELSE
                               1 # ((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)))
                        ELSE FALSE
                    moduloGood == IF modulus # 0 THEN (IF modulus > 0 THEN TRUE ELSE FALSE) ELSE FALSE
        <2>overflow. divisionOverflow = FALSE
            BY ONLY <2>bounds, SMT DEF divisionOverflow
        <2>negative. (IF modulus # 0 THEN ~(modulus > 0) ELSE FALSE) = (modulus < 0)
            BY ONLY SourceDomain, SMT DEF SourceDomain
        <2>late. (IF moduloGood THEN ~(divisor # 0) ELSE FALSE) = (modulus > 0 /\ divisor = 0)
            BY ONLY SourceDomain, SMT DEF moduloGood, SourceDomain
        <2>last. (IF moduloGood THEN divisionOverflow ELSE FALSE) = FALSE
            BY ONLY <2>overflow, SMT
        <2>zeroes. /\ (~(divisor # 0) <=> divisor = 0)
                    /\ (~(modulus # 0) <=> modulus = 0)
            BY ONLY SMT
        <2>physical. __SwiftTLAActionFailureHistory0 =
                        SourceLeftFailureHistory \o <<>> \o zero \o negative \o late \o <<>>
            BY ONLY <2>zeroes, <2>overflow, <2>negative, <2>late, <2>last, SMT
                DEF __SwiftTLAActionFailureHistory0, SourceLeftFailureHistory, divisionOverflow, moduloGood,
                    zero, negative, late, DivisionEvent, NegativeModuloEvent, FailureEvent, LeftBefore, RightBefore, vars
        <2>empty. <<>> \in Seq(ObservedFailureEvents)
            BY ONLY EmptySeq, Isa
        <2>integer. modulus \in Int
            BY ONLY SourceDomain, SMT DEF SourceDomain
        <2>exclusive.
            /\ (modulus = 0 => ~(modulus < 0) /\ ~(modulus > 0))
            /\ (modulus < 0 => modulus # 0 /\ ~(modulus > 0))
            /\ (modulus > 0 => modulus # 0 /\ ~(modulus < 0))
            BY ONLY <2>integer, SMT
        <2>maps.
            /\ zero = IF modulus = 0 THEN SourceRightFailureHistory ELSE <<>>
            /\ negative = IF modulus < 0 THEN SourceRightFailureHistory ELSE <<>>
            /\ late = IF modulus > 0 THEN SourceRightFailureHistory ELSE <<>>
            <3>zero. zero = IF modulus = 0 THEN SourceRightFailureHistory ELSE <<>>
                BY ONLY SMT DEF zero, SourceRightFailureHistory
            <3>negative. negative = IF modulus < 0 THEN SourceRightFailureHistory ELSE <<>>
                BY ONLY <2>exclusive, SMT DEF negative, SourceRightFailureHistory
            <3>late. late = IF modulus > 0 THEN SourceRightFailureHistory ELSE <<>>
                BY ONLY <2>exclusive, SMT DEF late, SourceRightFailureHistory
            <3>. QED BY ONLY <3>zero, <3>negative, <3>late
        <2>cells. /\ zero \in Seq(ObservedFailureEvents)
                   /\ negative \in Seq(ObservedFailureEvents)
                   /\ late \in Seq(ObservedFailureEvents)
            BY ONLY <1>typed, <2>maps, <2>empty, SMT
        <2>unit. /\ SourceRightFailureHistory \o <<>> = SourceRightFailureHistory
                  /\ <<>> \o SourceRightFailureHistory = SourceRightFailureHistory
                  /\ <<>> \o <<>> = <<>>
            BY ONLY <1>typed, <2>empty, ConcatEmptySeq, Isa
        <2>right. zero \o negative \o late = SourceRightFailureHistory
            <3>zero. CASE modulus = 0
                <4>slots. /\ zero = SourceRightFailureHistory /\ negative = <<>> /\ late = <<>>
                    BY ONLY <3>zero, <2>exclusive, <2>maps, SMT
                <4>. QED BY ONLY <4>slots, <2>unit, SMT
            <3>negative. CASE modulus < 0
                <4>slots. /\ zero = <<>> /\ negative = SourceRightFailureHistory /\ late = <<>>
                    BY ONLY <3>negative, <2>exclusive, <2>maps, SMT
                <4>. QED BY ONLY <4>slots, <2>unit, SMT
            <3>positive. CASE modulus > 0
                <4>slots. /\ zero = <<>> /\ negative = <<>> /\ late = SourceRightFailureHistory
                    BY ONLY <3>positive, <2>exclusive, <2>maps, SMT
                <4>. QED BY ONLY <4>slots, <2>unit, SMT
            <3>. QED BY ONLY <2>bounds, <3>zero, <3>negative, <3>positive, Isa
        <2>join. SourceLeftFailureHistory \o <<>> \o zero \o negative \o late \o <<>> =
                    SourceLeftFailureHistory \o (zero \o negative \o late)
            BY ONLY <1>typed, <2>cells, ConcatEmptySeq, ConcatProperties, ConcatAssociative, Isa
        <2>. QED BY ONLY <2>physical, <2>right, <2>join, SMT DEF FailureHistory!ActionAlternativeFailureHistory

    <1>append. LET left == SourceLeftFailureHistory
                   right == SourceRightFailureHistory
                   events == FailureHistory!ActionAlternativeFailureHistory(left, right)
               IN /\ events \in Seq(ObservedFailureEvents)
                  /\ Len(events) = Len(left) + Len(right)
                  /\ \A index \in 1..Len(left) : events[index] = left[index]
                  /\ \A index \in 1..Len(right) : events[Len(left) + index] = right[index]
                  /\ FailureHistory!ActionFailureEventSet(events) =
                         FailureHistory!ActionFailureEventSet(left) \cup FailureHistory!ActionFailureEventSet(right)
                  /\ FailureHistory!ActionHistoryFirstFailure(events) =
                         IF FailureHistory!ActionHistoryFirstFailure(left) = MissingObservedFailure
                         THEN FailureHistory!ActionHistoryFirstFailure(right)
                         ELSE FailureHistory!ActionHistoryFirstFailure(left)
        BY ONLY <1>typed, FailureHistory!ActionAlternativeHistoryRetainsEveryOccurrenceAndItsFirstFailure, Isa
    <1>. QED BY ONLY <1>emitted, <1>append, Isa

THEOREM FirstFailureSelectionRetainsItsVerdictAndDropsTheSecondOccurrence ==
    ASSUME SourceDomain, divisor = 0, modulus = -1
    PROVE /\ __SwiftTLADivisionByZeroFailure0
          /\ ~__SwiftTLANegativeModuloDivisorFailure0
          /\ __SwiftTLAActionFailureHistory0 = <<DivisionEvent(0, 1, 3, LeftBefore), NegativeModuloEvent>>
    PROOF
    <1>selected. /\ __SwiftTLADivisionByZeroFailure0
                  /\ ~__SwiftTLANegativeModuloDivisorFailure0
        BY ONLY SourceDomain, (divisor = 0), EmittedFirstFailureMatchesSource, Isa
            DEF SourceFirstDivisionFailure, SourceLaterNegativeModuloFailure
    <1>full. __SwiftTLAActionFailureHistory0 =
        FailureHistory!ActionAlternativeFailureHistory(SourceLeftFailureHistory, SourceRightFailureHistory)
        BY ONLY SourceDomain, EmittedActionFailureHistoryMatchesBranchwiseHistory, Isa
    <1>left. SourceLeftFailureHistory = <<DivisionEvent(0, 1, 3, LeftBefore)>>
        BY ONLY (divisor = 0), SMT DEF SourceLeftFailureHistory
    <1>right. SourceRightFailureHistory = <<NegativeModuloEvent>>
        BY ONLY (modulus = -1), SMT DEF SourceRightFailureHistory
    <1>pair. <<DivisionEvent(0, 1, 3, LeftBefore)>> \o <<NegativeModuloEvent>> =
                <<DivisionEvent(0, 1, 3, LeftBefore), NegativeModuloEvent>>
        <2>. DEFINE first == DivisionEvent(0, 1, 3, LeftBefore)
                    second == NegativeModuloEvent
                    S == {first, second}
        <2>domains. /\ <<first>> \in [1..1 -> S] /\ <<second>> \in [1..1 -> S]
                    /\ <<first, second>> \in [1..2 -> S] /\ 1 \in Nat /\ 2 \in Nat
            BY ONLY SMT DEF S
        <2>seqs. /\ <<first>> \in Seq(S) /\ <<second>> \in Seq(S)
                 /\ <<first, second>> \in Seq(S)
            BY ONLY <2>domains, SeqDef, SMT
        <2>join. /\ <<first>> \o <<second>> \in Seq(S)
                 /\ Len(<<first>> \o <<second>>) = 2
                 /\ (<<first>> \o <<second>>)[1] = first
                 /\ (<<first>> \o <<second>>)[2] = second
            BY ONLY <2>seqs, ConcatProperties, SMT
        <2>. QED BY ONLY <2>seqs, <2>join, SeqEqual, SMT DEF first, second
    <1>. QED BY ONLY <1>selected, <1>full, <1>left, <1>right, <1>pair, Isa
        DEF FailureHistory!ActionAlternativeFailureHistory

SourceLabeledStep(label) == label = "pick" /\ SourcePick
EmittedLabeledStep(label) == label = "pick" /\ pick
SourceActionDisabled ==
    ~ENABLED SourcePick /\
    FailureHistory!ActionAlternativeFailureHistory(SourceLeftFailureHistory, SourceRightFailureHistory) = <<>>
EmittedActionDisabled == ~ENABLED Next /\ __SwiftTLAActionFailureHistory0 = <<>>

THEOREM EmittedLabeledSuccessorsAndDisablednessMatchSource ==
    ASSUME SourceDomain
    PROVE /\ \A label : EmittedLabeledStep(label) <=> SourceLabeledStep(label)
          /\ (divisor = 1 /\ vars' = <<divisor, modulus, 0, 1>> => EmittedLabeledStep("pick"))
          /\ (ENABLED Next <=> divisor = 1)
          /\ (~ENABLED Next => __SwiftTLAActionFailureHistory0 # <<>>)
          /\ (EmittedActionDisabled <=> SourceActionDisabled)
          /\ ~EmittedActionDisabled
    PROOF
    <1>typed. (Next \/ SourcePick) =>
        /\ divisor' \in Int /\ modulus' \in Int /\ selected' \in Int /\ result' \in Int
        <2>physical. Next => divisor' \in Int /\ modulus' \in Int /\ selected' \in Int /\ result' \in Int
            BY ONLY SourceDomain, EmittedStepPreservesDomain, SMT DEF Next
        <2>authored. SourcePick => divisor' \in Int /\ modulus' \in Int /\ selected' \in Int /\ result' \in Int
            BY ONLY SourceDomain, SMT DEF SourceDomain, SourcePick
        <2>. QED BY ONLY <2>physical, <2>authored, SMT
    <1>step. Next <=> SourcePick
        BY ONLY SourceDomain, <1>typed, EmittedStepMatchesSource, SMT DEF Next
    <1>labels. \A label : EmittedLabeledStep(label) <=> SourceLabeledStep(label)
        BY ONLY <1>step, SMT DEF Next, EmittedLabeledStep, SourceLabeledStep
    <1>chosen. divisor = 1 /\ vars' = <<divisor, modulus, 0, 1>> => EmittedLabeledStep("pick")
        BY ONLY <1>step, SMT DEF vars, SourcePick, Next, EmittedLabeledStep
    <1>enabledSource. ENABLED SourcePick <=> divisor = 1
        <2>requires. ENABLED SourcePick => divisor = 1
            BY ONLY ExpandENABLED, SMT DEF SourcePick
        <2>exists. ASSUME divisor = 1
                   PROVE ENABLED SourcePick
            <3>witness. \E d, m, s, r : divisor = 1 /\ d = divisor /\ m = modulus /\ s = 0 /\ r = 1
                <4>. WITNESS divisor, modulus, 0, 1
                <4>. QED BY ONLY (divisor = 1), SMT
            <3>. QED BY ONLY <3>witness, ExpandENABLED, SMT DEF SourcePick
        <2>. QED BY ONLY <2>requires, <2>exists, SMT
    <1>enabled. ENABLED Next <=> ENABLED SourcePick
        BY ONLY SourceDomain, <1>enabledSource, ExpandENABLED, SMT DEF Next, pick, SourceDomain, SourcePick
    <1>history. __SwiftTLAActionFailureHistory0 =
        FailureHistory!ActionAlternativeFailureHistory(SourceLeftFailureHistory, SourceRightFailureHistory)
        BY ONLY SourceDomain, EmittedActionFailureHistoryMatchesBranchwiseHistory
    <1>noSuccessor. ~ENABLED Next => __SwiftTLAActionFailureHistory0 # <<>>
        <2>failure. ~ENABLED Next => divisor = 0
            BY ONLY SourceDomain, <1>enabled, <1>enabledSource, SMT DEF SourceDomain
        <2>length. /\ Len(__SwiftTLAActionFailureHistory0) =
                         Len(SourceLeftFailureHistory) + Len(SourceRightFailureHistory)
                   /\ Len(SourceRightFailureHistory) \in Nat
            BY ONLY SourceDomain, EmittedActionFailureHistoryMatchesBranchwiseHistory, SMT DEF SourceRightFailureHistory
        <2>. QED BY ONLY <2>failure, <2>length, SMT DEF SourceLeftFailureHistory
    <1>disabled. /\ (EmittedActionDisabled <=> SourceActionDisabled)
                  /\ ~EmittedActionDisabled
        BY ONLY <1>enabled, <1>history, <1>noSuccessor, SMT DEF EmittedActionDisabled, SourceActionDisabled
    <1>. QED BY ONLY <1>labels, <1>chosen, <1>enabled, <1>enabledSource, <1>noSuccessor, <1>disabled, SMT

THEOREM CompleteEmittedOutcomeMatchesSource ==
    ASSUME SourceDomain, divisor' \in Int, modulus' \in Int,
           selected' \in Int, result' \in Int
    PROVE /\ Init <=> SourceInit
          /\ Next <=> SourcePick
          /\ __SwiftTLADivisionByZeroFailure0 <=> SourceFirstDivisionFailure
          /\ __SwiftTLADivisionByZeroFailure0_1 <=> SourceLaterModuloZeroFailure
          /\ __SwiftTLANegativeModuloDivisorFailure0 <=> SourceLaterNegativeModuloFailure
          /\ __SwiftTLAEvaluationOK <=> SourceEvaluationOK
          /\ __SwiftTLAActionFailureHistory0 =
                 FailureHistory!ActionAlternativeFailureHistory(SourceLeftFailureHistory, SourceRightFailureHistory)
          /\ \A label : EmittedLabeledStep(label) <=> SourceLabeledStep(label)
          /\ (divisor = 1 /\ vars' = <<divisor, modulus, 0, 1>> => EmittedLabeledStep("pick"))
          /\ (ENABLED Next <=> divisor = 1)
          /\ (~ENABLED Next => __SwiftTLAActionFailureHistory0 # <<>>)
          /\ (EmittedActionDisabled <=> SourceActionDisabled)
          /\ ~EmittedActionDisabled
    BY EmittedInitialMatchesSource, EmittedStepMatchesSource,
       EmittedFirstFailureMatchesSource, EmittedActionFailureHistoryMatchesBranchwiseHistory,
       EmittedLabeledSuccessorsAndDisablednessMatchSource, SMT DEF Next

THEOREM UngatedLaterFailureWouldDisagree ==
    ASSUME divisor = 0, modulus = -1
    PROVE UngatedLaterModuloFailure
          /\ ~__SwiftTLANegativeModuloDivisorFailure0
    BY SMT DEF UngatedLaterModuloFailure,
        __SwiftTLANegativeModuloDivisorFailure0

SourceOrderedFailureHistory == SourceLeftFailureHistory \o SourceRightFailureHistory

THEOREM ActualBranchwiseHistoryMatchesAuthoredOrder ==
    ASSUME SourceDomain
    PROVE __SwiftTLAActionFailureHistory0 = SourceOrderedFailureHistory
    BY ONLY SourceDomain, EmittedActionFailureHistoryMatchesBranchwiseHistory, Isa
        DEF SourceOrderedFailureHistory, FailureHistory!ActionAlternativeFailureHistory

THEOREM ActualBranchwiseEvaluationCheckUsesTheOrderedHistory ==
    ASSUME SourceDomain
    PROVE __SwiftTLAEvaluationOK <=> DOMAIN SourceOrderedFailureHistory = {}
    PROOF
    <1>inputs. /\ SourceLeftFailureHistory \in Seq(ObservedFailureEvents)
               /\ SourceRightFailureHistory \in Seq(ObservedFailureEvents)
        BY ONLY SourceDomain, SourceBranchwiseFailureHistoriesAreTyped
    <1>left. Len(SourceLeftFailureHistory) = IF divisor = 0 THEN 1 ELSE 0
        BY ONLY SMT DEF SourceLeftFailureHistory
    <1>right. Len(SourceRightFailureHistory) = IF modulus > 0 /\ divisor = 1 THEN 0 ELSE 1
        BY ONLY SourceDomain, SMT DEF SourceDomain, SourceRightFailureHistory
    <1>concat. /\ SourceOrderedFailureHistory \in Seq(ObservedFailureEvents)
                /\ Len(SourceOrderedFailureHistory) = Len(SourceLeftFailureHistory) + Len(SourceRightFailureHistory)
        BY ONLY <1>inputs, ConcatProperties, Isa DEF SourceOrderedFailureHistory
    <1>domain. DOMAIN SourceOrderedFailureHistory = 1..Len(SourceOrderedFailureHistory)
        BY ONLY <1>concat, LenProperties, Isa
    <1>check. __SwiftTLAEvaluationOK <=> SourceEvaluationOK
        BY ONLY SourceDomain, EmittedFirstFailureMatchesSource, Isa
    <1>length. Len(SourceOrderedFailureHistory) =
        (IF divisor = 0 THEN 1 ELSE 0) + (IF modulus > 0 /\ divisor = 1 THEN 0 ELSE 1)
        BY ONLY <1>left, <1>right, <1>concat, Isa
    <1>zero. (Len(SourceOrderedFailureHistory) = 0) <=> SourceEvaluationOK
        <2>good. SourceEvaluationOK => Len(SourceOrderedFailureHistory) = 0
            BY ONLY <1>length, SMT DEF SourceEvaluationOK
        <2>bad. ~SourceEvaluationOK => Len(SourceOrderedFailureHistory) # 0
            <3>eval. ASSUME ~SourceEvaluationOK
                     PROVE Len(SourceOrderedFailureHistory) = (IF divisor = 0 THEN 1 ELSE 0) + 1
                BY ONLY (~SourceEvaluationOK), <1>length, SMT DEF SourceEvaluationOK
            <3>positive. ((IF divisor = 0 THEN 1 ELSE 0) + 1) # 0
                <4>typed. (IF divisor = 0 THEN 1 ELSE 0) \in 0..1
                    BY ONLY SMT
                <4>. QED BY ONLY <4>typed, SMT
            <3>. QED BY ONLY <3>eval, <3>positive, Isa
        <2>. QED BY ONLY <2>good, <2>bad, SMT
    <1>natural. Len(SourceOrderedFailureHistory) \in Nat
        BY ONLY <1>concat, LenProperties, Isa
    <1>empty. (DOMAIN SourceOrderedFailureHistory = {}) <=> (Len(SourceOrderedFailureHistory) = 0)
        <2>positive. Len(SourceOrderedFailureHistory) # 0 => 1 \in DOMAIN SourceOrderedFailureHistory
            BY ONLY <1>natural, <1>domain, SMT
        <2>zero. Len(SourceOrderedFailureHistory) = 0 => DOMAIN SourceOrderedFailureHistory = {}
            BY ONLY <1>domain, SMT
        <2>. QED BY ONLY <2>positive, <2>zero, SMT
    <1>. QED BY ONLY <1>empty, <1>zero, <1>check, PTL

=============================================================================
