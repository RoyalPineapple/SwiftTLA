---- MODULE StringLiterals ----
VARIABLE text
Init == text = "plain"
Escape == /\ text = "plain"
          /\ text' = "quote\" slash\\ newline\n return\r tab\t form\f é"
Reset == /\ text # "plain"
         /\ text' = "plain"
Next == Escape \/ Reset
Spec == Init /\ [][Next]_text
KnownText == text \in {"plain", "quote\" slash\\ newline\n return\r tab\t form\f é"}
====
