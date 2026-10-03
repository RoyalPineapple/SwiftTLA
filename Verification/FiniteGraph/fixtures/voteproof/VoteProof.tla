---- MODULE VoteProof ----
EXTENDS Integers, FiniteSets, Sequences

CONSTANTS Acceptor, Ballot, Quorum, Value
ASSUME Acceptor = {"a1", "a2", "a3"}
ASSUME Ballot = {0, 1, 2}
ASSUME Quorum = {{"a1", "a2", "a3"}, {"a1", "a2"}, {"a1", "a3"}, {"a2", "a3"}}
ASSUME Value = {"v1", "v2"}

VARIABLES votes, maxBal

SafeAt(value0, value1) == LET SA[__binder_VoteProof_99_21 \in {0, 1, 2}] == (IF (__binder_VoteProof_99_21 = 0) THEN TRUE ELSE \E __binder_VoteProof_100_47 \in {{"a1", "a2"}, {"a1", "a3"}, {"a2", "a3"}, {"a1", "a2", "a3"}} : (\A __binder_VoteProof_101_29 \in __binder_VoteProof_100_47 : (maxBal[__binder_VoteProof_101_29] >= __binder_VoteProof_99_21) /\ \E __binder_VoteProof_103_34 \in -1..(__binder_VoteProof_99_21 - 1) : ((IF (__binder_VoteProof_103_34 = -1) THEN TRUE ELSE (SA[__binder_VoteProof_103_34] /\ \A __binder_VoteProof_106_44 \in __binder_VoteProof_100_47 : \A __binder_VoteProof_107_45 \in {"v1", "v2"} : (IF (~(<<__binder_VoteProof_103_34, __binder_VoteProof_107_45>> \in votes[__binder_VoteProof_106_44])) THEN TRUE ELSE (__binder_VoteProof_107_45 = value1)))) /\ \A __binder_VoteProof_112_39 \in (__binder_VoteProof_103_34 + 1)..(__binder_VoteProof_99_21 - 1) : \A __binder_VoteProof_113_37 \in __binder_VoteProof_100_47 : \A __binder_VoteProof_114_41 \in {"v1", "v2"} : (~(<<__binder_VoteProof_112_39, __binder_VoteProof_114_41>> \in votes[__binder_VoteProof_113_37])))))
IN SA[value0]

ChosenIn(value0, value1) == \E __binder_VoteProof_127_21 \in {{"a1", "a2"}, {"a1", "a3"}, {"a2", "a3"}, {"a1", "a2", "a3"}} : \A __binder_VoteProof_128_25 \in __binder_VoteProof_127_21 : (<<value0, value1>> \in votes[__binder_VoteProof_128_25])

chosen == {__binder_VoteProof_137_27 \in {"v1", "v2"} : \E __binder_VoteProof_138_25 \in {0, 1, 2} : ChosenIn(__binder_VoteProof_138_25, __binder_VoteProof_137_27)}

VoteProofTypeOK == \A __binder_VoteProof_149_27 \in {"a1", "a2", "a3"} : (\A __binder_VoteProof_150_25 \in votes[__binder_VoteProof_149_27] : ((__binder_VoteProof_150_25[1] \in {0, 1, 2}) /\ (__binder_VoteProof_150_25[2] \in {"v1", "v2"})) /\ (maxBal[__binder_VoteProof_149_27] \in ({0, 1, 2} \cup {-1})))

VoteProofSingleVotePerBallot == \A __binder_VoteProof_161_27 \in {"a1", "a2", "a3"} : \A __binder_VoteProof_162_25 \in {0, 1, 2} : \A __binder_VoteProof_163_29 \in {"v1", "v2"} : \A __binder_VoteProof_164_33 \in {"v1", "v2"} : (IF (IF (~(<<__binder_VoteProof_162_25, __binder_VoteProof_163_29>> \in votes[__binder_VoteProof_161_27])) THEN TRUE ELSE (~(<<__binder_VoteProof_162_25, __binder_VoteProof_164_33>> \in votes[__binder_VoteProof_161_27]))) THEN TRUE ELSE (__binder_VoteProof_163_29 = __binder_VoteProof_164_33))

VoteProofVotesAreSafe == \A __binder_VoteProof_179_27 \in {"a1", "a2", "a3"} : \A __binder_VoteProof_180_25 \in {0, 1, 2} : \A __binder_VoteProof_181_29 \in {"v1", "v2"} : (IF (~(<<__binder_VoteProof_180_25, __binder_VoteProof_181_29>> \in votes[__binder_VoteProof_179_27])) THEN TRUE ELSE SafeAt(__binder_VoteProof_180_25, __binder_VoteProof_181_29))

VoteProofAgreement == \A __binder_VoteProof_195_27 \in {"a1", "a2", "a3"} : \A __binder_VoteProof_196_25 \in {"a1", "a2", "a3"} : \A __binder_VoteProof_197_29 \in {0, 1, 2} : \A __binder_VoteProof_198_33 \in {"v1", "v2"} : \A __binder_VoteProof_199_37 \in {"v1", "v2"} : (IF (IF (~(<<__binder_VoteProof_197_29, __binder_VoteProof_198_33>> \in votes[__binder_VoteProof_195_27])) THEN TRUE ELSE (~(<<__binder_VoteProof_197_29, __binder_VoteProof_199_37>> \in votes[__binder_VoteProof_196_25]))) THEN TRUE ELSE (__binder_VoteProof_198_33 = __binder_VoteProof_199_37))

VoteProofChosenValuesAgree == \A __binder_VoteProof_215_27 \in chosen : \A __binder_VoteProof_216_25 \in chosen : (__binder_VoteProof_215_27 = __binder_VoteProof_216_25)

C == INSTANCE Consensus WITH Value <- {"v1", "v2"}, chosen <- chosen

Refines == C!Spec

vars == <<votes, maxBal>>

TypeOK == VoteProofTypeOK
VInv1 == VoteProofSingleVotePerBallot
VInv2 == VoteProofVotesAreSafe
VInv3 == VoteProofAgreement
VInv4 == VoteProofChosenValuesAgree

Init ==
  /\ votes = [__binder_VoteProof_86_63 \in {"a1", "a2", "a3"} |-> {}]
  /\ maxBal = [__binder_VoteProof_87_65 \in {"a1", "a2", "a3"} |-> -1]

pcalProcess1(_process) == (((TRUE /\ \E __binder_VoteProof_252_25 \in {0, 1, 2}: ((TRUE /\ TRUE) /\ (((__binder_VoteProof_252_25 > maxBal[_process])) = TRUE /\ maxBal' = [maxBal EXCEPT ![_process] = __binder_VoteProof_252_25]))) /\ UNCHANGED votes) \/ (TRUE /\ \E __binder_VoteProof_252_25 \in {0, 1, 2}: ((TRUE /\ TRUE) /\ \E __binder_VoteProof_256_33 \in {"v1", "v2"}: ((TRUE /\ (((((maxBal[_process] <= <<__binder_VoteProof_252_25, __binder_VoteProof_256_33>>[1]) /\ \A __binder_VoteProof_232_32 \in {"v1", "v2"} : (~(<<<<__binder_VoteProof_252_25, __binder_VoteProof_256_33>>[1], __binder_VoteProof_232_32>> \in votes[_process]))) /\ \A __binder_VoteProof_235_32 \in ({"a1", "a2", "a3"} \ {_process}) : \A __binder_VoteProof_236_33 \in {"v1", "v2"} : (IF (~(<<<<__binder_VoteProof_252_25, __binder_VoteProof_256_33>>[1], __binder_VoteProof_236_33>> \in votes[__binder_VoteProof_235_32])) THEN TRUE ELSE (__binder_VoteProof_236_33 = <<__binder_VoteProof_252_25, __binder_VoteProof_256_33>>[2]))) /\ SafeAt(<<__binder_VoteProof_252_25, __binder_VoteProof_256_33>>[1], <<__binder_VoteProof_252_25, __binder_VoteProof_256_33>>[2]))) = TRUE) /\ (votes' = [votes EXCEPT ![_process] = (votes[_process] \cup {<<<<__binder_VoteProof_252_25, __binder_VoteProof_256_33>>[1], <<__binder_VoteProof_252_25, __binder_VoteProof_256_33>>[2]>>})] /\ maxBal' = [maxBal EXCEPT ![_process] = <<__binder_VoteProof_252_25, __binder_VoteProof_256_33>>[1]])))))
pcalProcess1__0 == pcalProcess1("a1")
pcalProcess1__1 == pcalProcess1("a2")
pcalProcess1__2 == pcalProcess1("a3")

Next ==
  \/ pcalProcess1__0
  \/ pcalProcess1__1
  \/ pcalProcess1__2

Spec ==
  /\ Init
  /\ [][Next]_<<votes, maxBal>>

====
