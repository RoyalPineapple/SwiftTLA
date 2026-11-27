---- MODULE ScheduledLetActionAtChild ----
EXTENDS ScheduledLetActionLowering

ScheduledLetActionForChild(statements, pending, expected, next) ==
    LET returned(child, values) ==
            [action |-> IF child = expected /\ values = pending
                       THEN next ELSE "unmatched recursive operands"]
    IN ScheduledLetAction(statements,pending,<<>>,LAMBDA expr, roots : expr,returned)

THEOREM TheActualLetWrapsItsMatchedChildAction ==
    \A head, pending, expected, next, statementSet :
        head.kind = "letBinding" /\ head.body = expected /\ head.body \in Seq(statementSet) =>
            ScheduledLetActionForChild(<<head>>,pending,expected,next) =
                [kind |-> "define", name |-> head.variable, value |-> head.value, body |-> next]
PROOF
<1>. TAKE head, pending, expected, next, statementSet
<1>. SUFFICES ASSUME head.kind = "letBinding", head.body = expected, head.body \in Seq(statementSet)
              PROVE ScheduledLetActionForChild(<<head>>,pending,expected,next) =
                  [kind |-> "define", name |-> head.variable, value |-> head.value, body |-> next]
    OBVIOUS
<1>. DEFINE returned(child, values) ==
            [action |-> IF child = expected /\ values = pending
                       THEN next ELSE "unmatched recursive operands"]
<1>raw. ScheduledLetAction(<<head>>,pending,<<>>,LAMBDA expr, roots : expr,returned) =
        [kind |-> "define", name |-> head.variable,
         value |-> ScopedLetValue(<<>>,head.value,LAMBDA expr, roots : expr),
         body |-> returned(head.body,pending).action]
    BY ONLY (head.kind = "letBinding"), (head.body \in Seq(statementSet)),
        OneReturnedScheduledLetIsTheActualDefineAroundItsContinuation
<1>value. ScopedLetValue(<<>>,head.value,LAMBDA expr, roots : expr) = head.value
    BY ONLY IsaM("simp"), SMT DEF ScopedLetValue
<1>child. returned(head.body,pending).action = next
    BY ONLY (head.body = expected), IsaM("simp"), SMT DEF returned
<1>alias. ScheduledLetActionForChild(<<head>>,pending,expected,next) =
          ScheduledLetAction(<<head>>,pending,<<>>,LAMBDA expr, roots : expr,returned)
    BY ONLY DEF ScheduledLetActionForChild, returned
<1>reduced.
    [kind |-> "define", name |-> head.variable,
     value |-> ScopedLetValue(<<>>,head.value,LAMBDA expr, roots : expr),
     body |-> returned(head.body,pending).action]
     = [kind |-> "define", name |-> head.variable, value |-> head.value, body |-> next]
    BY ONLY <1>value, <1>child, SMT
<1>. QED BY ONLY <1>alias, <1>raw, <1>reduced, SMT, IsaM("simp")
====
