---- MODULE StringLiterals ----
\* SwiftTLA formal strings: utf8-v1
VARIABLE text
Init == text = "plain"
Escape == /\ text = "plain"
          /\ text' = "__SwiftTLA_UTF8_V1__71756F74652220736C6173685C206E65776C696E650A2072657475726E0D207461620920666F726D0C20C3A9"
Reset == /\ text # "plain"
         /\ text' = "plain"
Next == Escape \/ Reset
Spec == Init /\ [][Next]_text
KnownText == text \in {"plain", "__SwiftTLA_UTF8_V1__71756F74652220736C6173685C206E65776C696E650A2072657475726E0D207461620920666F726D0C20C3A9"}
====
