---- MODULE SeedAndArithmeticConfiguredBehavior ----
EXTENDS SeedConfiguredBehavior, SwiftTLACopyCertifiedAssignmentObservation, CallerInputPageBlock1,
        OrderedOverflowInitialDisabled, SwiftTLAArithmeticPublicSendBinding

\* CompilerInputPage1 CompilerInputPage2 CompilerInputPage3
\* CallerInputPage1 CallerInputPage2 CallerInputPage3 CallerInputPage4 CallerInputPage5

LOCAL Arithmetic == INSTANCE SwiftTLAOrderedRHSBackendAgreement
    WITH pc <- arithmeticPC, count <- arithmeticCount

LOCAL ArithmeticSendBefore == <<arithmeticPC, Arithmetic!RHSOutputBefore>>

LOCAL Send == INSTANCE NativePublicSendFlowRule
LOCAL ArithmeticSendAction == Arithmetic!ActualNativeAssignmentHandle
LOCAL ArithmeticSendVisits == Arithmetic!ActualNativeAssignmentCallbackSnapshots
LOCAL ArithmeticSendFailures == Arithmetic!ActualNativeAssignmentFailureReasons
LOCAL ArithmeticPublicSend ==
    Send!DecodedPublicSend(ArithmeticSendBinding, ArithmeticSendBefore, ArithmeticSendAction,
                           ArithmeticSendVisits, ArithmeticSendFailures)

THEOREM TypedArithmeticSendUsesTheCertifiedActionObservation ==
    ASSUME Arithmetic!RHSOutputStateType
    PROVE /\ ArithmeticSendBinding.checking = "none"
          /\ (Arithmetic!advance <=> (ArithmeticPublicSend.kind = "success" /\
                  ArithmeticPublicSend.current = <<arithmeticPC', Arithmetic!RHSOutputAfter>>))
          /\ (ArithmeticPublicSend.kind = "success" => ArithmeticSendVisits = <<ArithmeticPublicSend.current>>)
          /\ \E history :
                /\ Arithmetic!RHSOutputSourceHistory(history)
                /\ Arithmetic!RHSOutputHistoryObservation(history)
                /\ LET final == history[Arithmetic!RHSOutputCount]
                       sent == ArithmeticPublicSend
                   IN IF ~Arithmetic!RHSOutputSelected
                      THEN /\ sent.kind = "disabled" /\ sent.value = "noMatchingSuccessor"
                           /\ sent.current = ArithmeticSendBefore
                      ELSE IF final.failure # <<>>
                      THEN /\ sent.kind = "evaluationFailure" /\ sent.value = final.failure.payload
                           /\ sent.current = ArithmeticSendBefore
                           /\ ArithmeticSendVisits = <<>>
                      ELSE /\ sent.kind = "success"
                           /\ sent.current = <<Arithmetic!RHSOutputExit, final.bindings>>
                           /\ sent.value = [action |-> Arithmetic!RHSOutputActionLabel,
                                             before |-> Arithmetic!RHSOutputBefore, after |-> final.bindings]
PROOF
<1>route. ArithmeticSendBinding.checking = "none"
    BY ONLY SMT DEF ArithmeticSendBinding
<1>handle. Arithmetic!ActualNativeAssignmentHandle = Arithmetic!RHSOutputActionLabel
    BY ONLY CallerInputDomain, CallerInputPageBlock1AtFileOffsets,
        Arithmetic!ActualArithmeticCandidateInvokesTheCheckedNativeVisitor, PTL
        DEF CallerInputSize, Arithmetic!CallerInputSize
<1>name. Arithmetic!RHSOutputActionLabel = "advance"
    BY ONLY SMT DEF Arithmetic!RHSOutputActionLabel
<1>visit. PICK history :
    /\ Arithmetic!RHSOutputSourceHistory(history)
    /\ Arithmetic!RHSOutputHistoryObservation(history)
    /\ LET final == history[Arithmetic!RHSOutputCount] IN
        /\ Arithmetic!ActualNativeAssignmentCallbackSnapshots =
            IF Arithmetic!RHSOutputSelected /\ final.failure = <<>>
            THEN << <<Arithmetic!RHSOutputExit, final.bindings>> >> ELSE <<>>
        /\ Arithmetic!ActualNativeAssignmentFailureReasons =
            IF Arithmetic!RHSOutputSelected /\ final.failure # <<>> THEN <<final.failure.payload>> ELSE <<>>
    BY ONLY Arithmetic!RHSOutputStateType, CallerInputDomain, CallerInputPageBlock1AtFileOffsets,
        Arithmetic!ActualNativeAndTLAAdvanceAgreeOnTypedInput, PTL
        DEF CallerInputSize, Arithmetic!CallerInputSize
<1>. DEFINE final == history[Arithmetic!RHSOutputCount]
            sent == ArithmeticPublicSend
<1>operands. Send!DecodedSendOperands(ArithmeticSendBinding, ArithmeticSendAction)
    BY ONLY <1>handle, <1>name, SMT
        DEF Send!DecodedSendOperands, ArithmeticSendBinding, ArithmeticSendAction
<1>. DEFINE snapshots == {<<Arithmetic!RHSOutputExit, final.bindings>>}
            reasons == Arithmetic!RHSOutputInput!Rule!ArithmeticFailures
<1>errorType. final.failure # <<>> => final.failure.payload \in reasons
    <2>end. Arithmetic!RHSOutputCount \in 0..Len(Arithmetic!RHSOutputRows)
        BY ONLY Arithmetic!RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
            DEF Arithmetic!RHSOutputCount, Arithmetic!RHSOutputInput!Rule!SupportedAssignmentList
    <2>. QED BY ONLY <1>visit, <2>end, SMT DEF final, reasons,
        Arithmetic!RHSOutputSourceHistory, Arithmetic!RHSOutputInput!Rule!AssignmentListHistory,
        Arithmetic!RHSOutputInput!Rule!AssignmentPrefixStates, Arithmetic!RHSOutputInput!Rule!AssignmentFailureEvents
<1>sequences.
    /\ ArithmeticSendVisits \in Seq(snapshots)
    /\ ArithmeticSendFailures \in Seq(reasons)
    /\ <<>> \notin reasons
    BY ONLY <1>errorType, <1>visit, SeqDef, SMT DEF ArithmeticSendVisits, ArithmeticSendFailures,
        snapshots, final, reasons, Arithmetic!RHSOutputInput!Rule!ArithmeticFailures
<1>interpreted. sent =
    Send!PublicSendOutcome(ArithmeticSendBinding, ArithmeticSendBefore, ArithmeticSendAction,
                           ArithmeticSendVisits, ArithmeticSendFailures)
    BY ONLY <1>operands, <1>sequences, Send!DecodedSendUsesTheFirstErrorOrCommitsExactlyOneCallback, SMT
        DEF sent, ArithmeticPublicSend
<1>off. ~Arithmetic!RHSOutputSelected =>
    /\ sent.kind = "disabled" /\ sent.value = "noMatchingSuccessor"
    /\ sent.current = ArithmeticSendBefore
    BY ONLY <1>visit, <1>interpreted, LenProperties, SMT
        DEF Send!PublicSendOutcome, ArithmeticSendBinding, ArithmeticSendVisits, ArithmeticSendFailures
<1>overflow. Arithmetic!RHSOutputSelected /\ final.failure # <<>> =>
    /\ sent.kind = "evaluationFailure" /\ sent.value = final.failure.payload
    /\ sent.current = ArithmeticSendBefore
    /\ ArithmeticSendVisits = <<>>
    BY ONLY <1>visit, <1>interpreted, LenProperties, SMT
        DEF Send!PublicSendOutcome, ArithmeticSendFailures, ArithmeticSendVisits, final
<1>commit. Arithmetic!RHSOutputSelected /\ final.failure = <<>> =>
    /\ sent.kind = "success" /\ sent.current = <<Arithmetic!RHSOutputExit, final.bindings>>
    /\ sent.value = [action |-> Arithmetic!RHSOutputActionLabel,
                      before |-> Arithmetic!RHSOutputBefore, after |-> final.bindings]
    BY ONLY <1>visit, <1>handle, <1>interpreted, LenProperties, SMT
        DEF Send!PublicSendOutcome, ArithmeticSendBefore, ArithmeticSendAction,
            ArithmeticSendVisits, ArithmeticSendFailures, final
<1>step. Arithmetic!advance <=> (ArithmeticPublicSend.kind = "success" /\
                  ArithmeticPublicSend.current = <<arithmeticPC', Arithmetic!RHSOutputAfter>>)
    BY ONLY <1>visit, <1>off, <1>overflow, <1>commit, SMT
        DEF sent, final, Arithmetic!RHSOutputHistoryObservation, Arithmetic!RHSOutputHistoryAdvance
<1>commitsCallback. ArithmeticPublicSend.kind = "success" =>
    ArithmeticSendVisits = <<ArithmeticPublicSend.current>>
    BY ONLY <1>visit, <1>off, <1>overflow, <1>commit, SMT DEF ArithmeticSendVisits, sent, final
<1>result. \E witness :
    /\ Arithmetic!RHSOutputSourceHistory(witness)
    /\ Arithmetic!RHSOutputHistoryObservation(witness)
    /\ LET tail == witness[Arithmetic!RHSOutputCount]
           result == ArithmeticPublicSend
       IN IF ~Arithmetic!RHSOutputSelected
          THEN /\ result.kind = "disabled" /\ result.value = "noMatchingSuccessor"
               /\ result.current = ArithmeticSendBefore
          ELSE IF tail.failure # <<>>
          THEN /\ result.kind = "evaluationFailure" /\ result.value = tail.failure.payload
               /\ result.current = ArithmeticSendBefore
               /\ ArithmeticSendVisits = <<>>
          ELSE /\ result.kind = "success"
               /\ result.current = <<Arithmetic!RHSOutputExit, tail.bindings>>
               /\ result.value = [action |-> Arithmetic!RHSOutputActionLabel,
                                   before |-> Arithmetic!RHSOutputBefore, after |-> tail.bindings]
    <2>. WITNESS history
    <2>. QED BY ONLY <1>visit, <1>off, <1>overflow, <1>commit, SMT DEF sent, final
<1>. QED BY ONLY <1>route, <1>step, <1>commitsCallback, <1>result, PTL

THEOREM ConfiguredNativeAndTLAUseTheCertifiedCopyAndOverflowOutcomes ==
    /\ (\A label : SwiftTLACopyNativeLabeled(label) <=> SwiftTLACopySourceLabeled(label))
    /\ ([NativeSteps]_vars <=> [SourceSteps]_vars)
    /\ (SelectedBehavior <=> (Init /\ [][NativeSteps]_vars))
    /\ (CopyInputTyped =>
        /\ \A label : SwiftTLACopyEmittedLabeled(label) <=> CertifiedCopyStep(label)
        /\ \A label : SwiftTLACopyNativeLabeled(label) <=> CertifiedCopyStep(label)
        /\ Next <=> (\E label : CertifiedCopyStep(label)))
    /\ (Arithmetic!RHSOutputStateType =>
            /\ (Arithmetic!ActualNativeAssignmentAdvance <=> Arithmetic!advance)
            /\ Arithmetic!ActualNativeAssignmentFailures = Arithmetic!RHSOutputActualFailures)
    /\ Arithmetic!LocalOrderedRHSActualCFG = Arithmetic!LocalOrderedRHSExpectedCFG
    /\ (Arithmetic!Next <=> Arithmetic!RHSConfiguredCatalogSteps)
    /\ (Arithmetic!Spec <=> Arithmetic!RHSConfiguredCatalogBehavior)
    /\ (Arithmetic!RHSOutputStateType =>
        (Arithmetic!RHSOutputSelectedEvaluationCheck <=> Arithmetic!RHSOutputActualFailures = {}))
    /\ (Arithmetic!RHSOutputStateType =>
        /\ (Arithmetic!advance <=> (ArithmeticPublicSend.kind = "success" /\
              ArithmeticPublicSend.current = <<arithmeticPC', Arithmetic!RHSOutputAfter>>))
        /\ (ArithmeticPublicSend.kind = "success" => ArithmeticSendVisits = <<ArithmeticPublicSend.current>>))
    /\ (Arithmetic!Init =>
        /\ ArithmeticPublicSend.kind = "evaluationFailure"
        /\ ArithmeticPublicSend.value = <<"integerOverflow", "addition", <<Arithmetic!RHSOutputMax, 1>>>>
        /\ ArithmeticPublicSend.current = ArithmeticSendBefore
        /\ ArithmeticSendVisits = <<>>
        /\ Arithmetic!RHSOutputSelectedSubExpressions = {<<2, 3>>}
        /\ Arithmetic!RHSOutputActualFailures = {Arithmetic!ActualNativeProjection}
        /\ Arithmetic!RHSOutputActualFailures =
            {[site |-> 2, target |-> "count",
              payload |-> <<"integerOverflow", "addition", <<Arithmetic!RHSOutputMax, 1>>>>,
              completed |-> <<Arithmetic!RHSOutputMax>>, before |-> [count |-> Arithmetic!RHSOutputMax]]}
        /\ ~ENABLED Arithmetic!Next
        /\ ~Arithmetic!RHSOutputSelectedEvaluationCheck)
PROOF
<1>copy. /\ (\A label : SwiftTLACopyNativeLabeled(label) <=> SwiftTLACopySourceLabeled(label))
         /\ ([NativeSteps]_vars <=> [SourceSteps]_vars)
         /\ (SelectedBehavior <=> (Init /\ [][NativeSteps]_vars))
    BY ONLY NormalConfigurationAndNativeDispatchPreserveSourceSteps
<1>certified. ASSUME CopyInputTyped
              PROVE /\ \A label : SwiftTLACopyEmittedLabeled(label) <=> CertifiedCopyStep(label)
                    /\ \A label : SwiftTLACopyNativeLabeled(label) <=> CertifiedCopyStep(label)
                    /\ Next <=> (\E label : CertifiedCopyStep(label))
    BY CopyInputTyped, ActualTLAAndNativeCopyStepsUseTheCertifiedAssignmentHistory
<1>advance. ASSUME Arithmetic!RHSOutputStateType
             PROVE /\ (Arithmetic!ActualNativeAssignmentAdvance <=> Arithmetic!advance)
                   /\ Arithmetic!ActualNativeAssignmentFailures = Arithmetic!RHSOutputActualFailures
    BY ONLY Arithmetic!RHSOutputStateType, CallerInputDomain, CallerInputPageBlock1AtFileOffsets,
        Arithmetic!ActualNativeAndTLAAdvanceAgreeOnTypedInput, PTL
        DEF CallerInputSize, Arithmetic!CallerInputSize
<1>cfg. /\ Arithmetic!LocalOrderedRHSActualCFG = Arithmetic!LocalOrderedRHSExpectedCFG
        /\ (Arithmetic!Next <=> Arithmetic!RHSConfiguredCatalogSteps)
        /\ (Arithmetic!Spec <=> Arithmetic!RHSConfiguredCatalogBehavior)
        /\ (Arithmetic!RHSOutputStateType =>
             (Arithmetic!RHSOutputSelectedEvaluationCheck <=> Arithmetic!RHSOutputActualFailures = {}))
    BY ONLY CallerInputDomain, CallerInputPageBlock1AtFileOffsets,
        Arithmetic!ConfiguredArithmeticUsesTheCompleteLabeledActionCatalog, PTL
        DEF CallerInputSize, Arithmetic!CallerInputSize
<1>overflow. ASSUME Arithmetic!Init
    PROVE /\ Arithmetic!RHSOutputSelectedSubExpressions = {<<2, 3>>}
          /\ Arithmetic!RHSOutputActualFailures = {Arithmetic!ActualNativeProjection}
          /\ Arithmetic!RHSOutputActualFailures =
            {[site |-> 2, target |-> "count",
              payload |-> <<"integerOverflow", "addition", <<Arithmetic!RHSOutputMax, 1>>>>,
              completed |-> <<Arithmetic!RHSOutputMax>>, before |-> [count |-> Arithmetic!RHSOutputMax]]}
          /\ ~Arithmetic!RHSOutputSelectedEvaluationCheck
    BY ONLY Arithmetic!Init, CallerInputDomain, CallerInputPageBlock1AtFileOffsets,
        Arithmetic!ActualInitialEventRecordsTheExactOverflowAndPrecedingBindings, PTL
        DEF CallerInputSize, Arithmetic!CallerInputSize
<1>sendStep. ASSUME Arithmetic!RHSOutputStateType
    PROVE /\ (Arithmetic!advance <=> (ArithmeticPublicSend.kind = "success" /\
              ArithmeticPublicSend.current = <<arithmeticPC', Arithmetic!RHSOutputAfter>>))
          /\ (ArithmeticPublicSend.kind = "success" => ArithmeticSendVisits = <<ArithmeticPublicSend.current>>)
    BY ONLY Arithmetic!RHSOutputStateType, TypedArithmeticSendUsesTheCertifiedActionObservation, PTL
<1>sendFailure. ASSUME Arithmetic!Init
    PROVE /\ ArithmeticPublicSend.kind = "evaluationFailure"
          /\ ArithmeticPublicSend.value = <<"integerOverflow", "addition", <<Arithmetic!RHSOutputMax, 1>>>>
          /\ ArithmeticPublicSend.current = ArithmeticSendBefore
          /\ ArithmeticSendVisits = <<>>
    <2>type. Arithmetic!RHSOutputStateType
        BY ONLY Arithmetic!Init, SMT DEF Arithmetic!Init, Arithmetic!RHSOutputStateType,
            Arithmetic!RHSOutputBefore, Arithmetic!RHSOutputKeys, Arithmetic!RHSOutputMin, Arithmetic!RHSOutputMax
    <2>event. Arithmetic!RHSOutputActualFailures =
        {[site |-> 2, target |-> "count",
          payload |-> <<"integerOverflow", "addition", <<Arithmetic!RHSOutputMax, 1>>>>,
          completed |-> <<Arithmetic!RHSOutputMax>>, before |-> [count |-> Arithmetic!RHSOutputMax]]}
        BY ONLY Arithmetic!Init, <1>overflow, PTL
    <2>history. PICK history :
        /\ Arithmetic!RHSOutputHistoryObservation(history)
        /\ LET final == history[Arithmetic!RHSOutputCount]
               sent == ArithmeticPublicSend
           IN (Arithmetic!RHSOutputSelected /\ final.failure # <<>>) =>
               /\ sent.kind = "evaluationFailure" /\ sent.value = final.failure.payload
               /\ sent.current = ArithmeticSendBefore
               /\ ArithmeticSendVisits = <<>>
        BY ONLY <2>type, TypedArithmeticSendUsesTheCertifiedActionObservation, SMT
    <2>. QED BY ONLY <2>event, <2>history, SMT DEF Arithmetic!RHSOutputHistoryObservation,
        Arithmetic!RHSOutputHistoryFailures, Arithmetic!RHSOutputFailureEvent
<1>blocked. ASSUME Arithmetic!Init
             PROVE ~ENABLED Arithmetic!Next
    <2>entry. OverflowActions!Init
        BY ONLY Arithmetic!Init, SMT DEF Arithmetic!Init, OverflowActions!Init
    <2>disabled. ~ENABLED OverflowActions!Next
        BY ONLY <2>entry, InitialOrderedOverflowHasNoSuccessor, PTL
    <2>. QED BY ONLY <2>disabled, PTL
        DEF Arithmetic!Next, Arithmetic!advance, Arithmetic!Terminating,
            OverflowActions!Next, OverflowActions!advance, OverflowActions!Terminating
<1>. QED BY ONLY <1>copy, <1>certified, <1>advance, <1>cfg, <1>overflow, <1>sendStep, <1>sendFailure, <1>blocked, Zenon

====
