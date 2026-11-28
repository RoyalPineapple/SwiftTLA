---- MODULE AtomicSchedulerHandoff ----
EXTENDS TLAPS, Sequences, CompilerInputPageBlock183
\* CompilerInputPage11681 CompilerInputPage11682 CompilerInputPage11683 CompilerInputPage11684 CompilerInputPage11685 CompilerInputPage11686 CompilerInputPage11687 CompilerInputPage11688 CompilerInputPage11689 CompilerInputPage11690 CompilerInputPage11691 CompilerInputPage11692 CompilerInputPage11693 CompilerInputPage11694 CompilerInputPage11695 CompilerInputPage11696 CompilerInputPage11697 CompilerInputPage11698 CompilerInputPage11699 CompilerInputPage11700 CompilerInputPage11701 CompilerInputPage11702 CompilerInputPage11703 CompilerInputPage11704 CompilerInputPage11705 CompilerInputPage11706
CallerPrefix ==
    /\ \A j \in 1..16 : CompilerInputByte[186880+j-1] = <<58,93,10,32,32,32,32,32,32,32,32,108,101,116,32,115>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[186896+j-1] = <<99,104,101,100,117,108,101,100,32,61,32,115,99,104,101,100>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[186912+j-1] = <<117,108,101,65,116,111,109,105,99,83,116,97,116,101,109,101>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[186928+j-1] = <<110,116,115,40,115,116,101,112,46,109,111,100,101,108,46,115>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[186944+j-1] = <<116,97,116,101,109,101,110,116,115,44,32,98,105,110,100,105>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[186960+j-1] = <<110,103,58,32,98,105,110,100,105,110,103,44,10,32,32,32>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[186976+j-1] = <<32,32,32,32,32,32,32,32,32,114,101,99,111,114,100,65>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[186992+j-1] = <<115,115,105,103,110,109,101,110,116,58,32,114,101,99,111,114>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187008+j-1] = <<100,83,99,104,101,100,117,108,101,100,65,115,115,105,103,110>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187024+j-1] = <<109,101,110,116,41,32,123,10,32,32,32,32,32,32,32,32>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187040+j-1] = <<32,32,32,32,100,105,115,112,108,97,99,101,100,84,97,114>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187056+j-1] = <<103,101,116,115,91,36,48,93,32,61,32,36,49,10,32,32>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187072+j-1] = <<32,32,32,32,32,32,125,10,32,32,32,32,32,32,32,32>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187088+j-1] = <<108,101,116,32,108,111,119,101,114,101,100,32,61,32,108,111>>[j]
LocalSpellingAndTail ==
    /\ \A j \in 1..16 : CompilerInputByte[187104+j-1] = <<119,101,114,40,115,99,104,101,100,117,108,101,100,44,32,112>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187120+j-1] = <<114,111,99,101,115,115,76,111,99,97,108,82,111,111,116,115>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187136+j-1] = <<58,32,110,105,108,44,32,112,114,111,99,101,100,117,114,101>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187152+j-1] = <<115,58,32,91,93,44,32,111,119,110,101,114,58,32,110,105>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187168+j-1] = <<108,44,32,110,101,120,116,76,97,98,101,108,58,32,110,105>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187184+j-1] = <<108,44,32,99,111,110,116,114,111,108,58,32,110,105,108,41>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187200+j-1] = <<10,32,32,32,32,32,32,32,32,114,101,116,117,114,110,32>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187216+j-1] = <<40,108,111,119,101,114,101,100,46,97,99,116,105,111,110,44>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187232+j-1] = <<32,108,111,119,101,114,101,100,46,97,115,115,101,114,116,105>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187248+j-1] = <<111,110,115,44,32,100,105,115,112,108,97,99,101,100,84,97>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187264+j-1] = <<114,103,101,116,115,41,10,32,32,32,32,125,10,10,32,32>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187280+j-1] = <<32,32,112,114,105,118,97,116,101,32,115,116,97,116,105,99>>[j]
AuthoredSpellingAndTail ==
    /\ \A j \in 1..16 : CompilerInputByte[187104+j-1] = <<119,101,114,40,115,116,101,112,46,109,111,100,101,108,46,115>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187120+j-1] = <<116,97,116,101,109,101,110,116,115,44,32,112,114,111,99,101>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187136+j-1] = <<115,115,76,111,99,97,108,82,111,111,116,115,58,32,110,105>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187152+j-1] = <<108,44,32,112,114,111,99,101,100,117,114,101,115,58,32,91>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187168+j-1] = <<93,44,32,111,119,110,101,114,58,32,110,105,108,44,32,110>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187184+j-1] = <<101,120,116,76,97,98,101,108,58,32,110,105,108,44,32,99>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187200+j-1] = <<111,110,116,114,111,108,58,32,110,105,108,41,10,32,32,32>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187216+j-1] = <<32,32,32,32,32,114,101,116,117,114,110,32,40,108,111,119>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187232+j-1] = <<101,114,101,100,46,97,99,116,105,111,110,44,32,108,111,119>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187248+j-1] = <<101,114,101,100,46,97,115,115,101,114,116,105,111,110,115,44>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187264+j-1] = <<32,100,105,115,112,108,97,99,101,100,84,97,114,103,101,116>>[j]
    /\ \A j \in 1..16 : CompilerInputByte[187280+j-1] = <<115,41,10,32,32,32,32,125,10,10,32,32,32,32,112,114>>[j]

RecognizedHandoff == CallerPrefix /\ (LocalSpellingAndTail \/ AuthoredSpellingAndTail)
LocalDeclaration == <<CompilerInputByte[186895],CompilerInputByte[186896],CompilerInputByte[186897],CompilerInputByte[186898],CompilerInputByte[186899],CompilerInputByte[186900],CompilerInputByte[186901],CompilerInputByte[186902],CompilerInputByte[186903]>>
SchedulerInput == <<CompilerInputByte[186932],CompilerInputByte[186933],CompilerInputByte[186934],CompilerInputByte[186935],CompilerInputByte[186936],CompilerInputByte[186937],CompilerInputByte[186938],CompilerInputByte[186939],CompilerInputByte[186940],CompilerInputByte[186941],CompilerInputByte[186942],CompilerInputByte[186943],CompilerInputByte[186944],CompilerInputByte[186945],CompilerInputByte[186946],CompilerInputByte[186947],CompilerInputByte[186948],CompilerInputByte[186949],CompilerInputByte[186950],CompilerInputByte[186951],CompilerInputByte[186952]>>
LowerInput == IF CompilerInputByte[187117] = 44
              THEN <<CompilerInputByte[187108],CompilerInputByte[187109],CompilerInputByte[187110],CompilerInputByte[187111],CompilerInputByte[187112],CompilerInputByte[187113],CompilerInputByte[187114],CompilerInputByte[187115],CompilerInputByte[187116]>>
              ELSE <<CompilerInputByte[187108],CompilerInputByte[187109],CompilerInputByte[187110],CompilerInputByte[187111],CompilerInputByte[187112],CompilerInputByte[187113],CompilerInputByte[187114],CompilerInputByte[187115],CompilerInputByte[187116],CompilerInputByte[187117],CompilerInputByte[187118],CompilerInputByte[187119],CompilerInputByte[187120],CompilerInputByte[187121],CompilerInputByte[187122],CompilerInputByte[187123],CompilerInputByte[187124],CompilerInputByte[187125],CompilerInputByte[187126],CompilerInputByte[187127],CompilerInputByte[187128]>>

\* Reviewed Swift semantics: normal let initialization binds the call result;
\* evaluating a local or member path reads the value of that expression.
\* The source spells both operands. Neither callee has a specified result.
LowerCall(authored, Schedule(_), Lower(_)) ==
    LET b == Schedule(authored)
        env == [k \in {LocalDeclaration,SchedulerInput} |->
                    IF k = LocalDeclaration THEN b ELSE authored]
        arg == env[LowerInput]
    IN IF RecognizedHandoff /\ LocalDeclaration # SchedulerInput /\ LowerInput \in DOMAIN env
       THEN [called |-> TRUE, body |-> arg, result |-> Lower(arg)]
       ELSE [called |-> FALSE]

HandoffSelectsLocal == RecognizedHandoff /\ LocalDeclaration # SchedulerInput /\ LowerInput = LocalDeclaration
HandoffSelectsAuthored == RecognizedHandoff /\ LocalDeclaration # SchedulerInput /\ LowerInput = SchedulerInput

THEOREM TheCallReadsItsScheduledLocal == HandoffSelectsLocal
PROOF
<1>grammar. RecognizedHandoff
    BY ONLY CompilerInputPageBlock183AtFileOffsets, PTL DEF CallerPrefix,LocalSpellingAndTail,AuthoredSpellingAndTail,RecognizedHandoff
<1>argument. LocalDeclaration # SchedulerInput /\ LowerInput = LocalDeclaration
    BY ONLY CompilerInputPageBlock183AtFileOffsets, SMT DEF LocalDeclaration,SchedulerInput,LowerInput
<1>. QED BY ONLY <1>grammar,<1>argument DEF HandoffSelectsLocal

THEOREM LowerReceivesTheSchedulerReturn ==
    ASSUME NEW authored, NEW Schedule(_), NEW Lower(_)
    PROVE LowerCall(authored,Schedule,Lower) =
          [called |-> TRUE, body |-> Schedule(authored), result |-> Lower(Schedule(authored))]
    BY ONLY TheCallReadsItsScheduledLocal, IsaM("auto"), SMT DEF HandoffSelectsLocal,LowerCall
====
