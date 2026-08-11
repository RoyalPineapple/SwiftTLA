---- MODULE BridgeGraph ----
EXTENDS Naturals, TLC

VARIABLES x, integer, boolean, text, set, tuple, record, function

Init == /\ x \in {0, 1}
        /\ integer = 7
        /\ boolean = TRUE
        /\ text = "bridge"
        /\ set = {1, 2}
        /\ tuple = <<1, TRUE>>
        /\ record = [kind |-> "fixture"]
        /\ function = [n \in 1..2 |-> n]

ToMidA == x \in {0, 1} /\ x' = 2 /\ UNCHANGED <<integer, boolean, text, set, tuple, record, function>>
ToMidB == x \in {0, 1} /\ x' = 2 /\ UNCHANGED <<integer, boolean, text, set, tuple, record, function>>
Repeat == x = 2 /\ \E duplicate \in {"first", "second"}: x' = 3 /\ UNCHANGED <<integer, boolean, text, set, tuple, record, function>>
SelfLoop == x = 3 /\ x' = 3 /\ UNCHANGED <<integer, boolean, text, set, tuple, record, function>>
ToTerminal == x = 3 /\ x' = 4 /\ UNCHANGED <<integer, boolean, text, set, tuple, record, function>>
TerminalStep == x = 4 /\ x' = 5 /\ UNCHANGED <<integer, boolean, text, set, tuple, record, function>>

Next == ToMidA \/ ToMidB \/ Repeat \/ SelfLoop \/ ToTerminal \/ TerminalStep
TypeOK == /\ x \in 0..5
          /\ integer = 7
          /\ boolean = TRUE
          /\ text = "bridge"
          /\ set = {1, 2}
          /\ tuple = <<1, TRUE>>
          /\ record = [kind |-> "fixture"]
          /\ function = [n \in 1..2 |-> n]

====
