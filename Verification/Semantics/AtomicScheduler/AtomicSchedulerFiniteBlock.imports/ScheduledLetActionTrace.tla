---- MODULE ScheduledLetActionTrace ----
EXTENDS Integers, NaturalsInduction, ScheduledLetActionAtChild

ActualActionDefinesMatchTheScheduledLets(trace, actions) ==
    /\ DOMAIN actions = 1..(Len(trace.rows) + 1)
    /\ \A i \in DOMAIN trace.rows :
           LET scheduled == trace.bodies[i][1]
           IN actions[i] = [kind |-> "define", name |-> scheduled.variable,
                            value |-> scheduled.value, body |-> actions[i + 1]]

\* The terminal action is a parameter: even if it includes control or writes,
\* the compiler's LET branch must wrap that very action, in occurrence order.
\* A recursive result may only be used for the actual child operands.
ScheduledLetSuffixStep(trace, pending, previous, depth) ==
    LET i == Len(trace.rows) + 1 - depth
    IN ScheduledLetActionForChild(trace.bodies[i],pending,trace.bodies[i+1],previous)

ScheduledLetSuffixValues(trace, pending, terminalAction) ==
    LET suffix[k \in 0..Len(trace.rows)] ==
            IF k = 0 THEN terminalAction
            ELSE ScheduledLetSuffixStep(trace,pending,suffix[k-1],k)
    IN suffix

CompiledLetSuffixes(trace, pending, terminalAction) ==
    LET count == Len(trace.rows)
        suffix == ScheduledLetSuffixValues(trace,pending,terminalAction)
    IN [i \in 1..(count+1) |-> suffix[count+1-i]]

THEOREM ScheduledLetLoweringProducesTheActionColumn ==
    ASSUME NEW trace, NEW pending, NEW terminalAction, NEW statementSet,
           Len(trace.rows) \in Nat, DOMAIN trace.rows = 1..Len(trace.rows),
           \A i \in DOMAIN trace.rows :
               /\ trace.bodies[i] = <<trace.bodies[i][1]>>
               /\ trace.bodies[i][1].kind = "letBinding"
               /\ trace.bodies[i][1].body = trace.bodies[i+1]
               /\ trace.bodies[i+1] \in Seq(statementSet)
    PROVE LET actions == CompiledLetSuffixes(trace,pending,terminalAction)
          IN /\ actions[Len(trace.rows)+1] = terminalAction
             /\ ActualActionDefinesMatchTheScheduledLets(trace, actions)
PROOF
<1>. DEFINE count == Len(trace.rows)
            actions == CompiledLetSuffixes(trace,pending,terminalAction)
            suffix == ScheduledLetSuffixValues(trace,pending,terminalAction)
            advance(previous,depth) == ScheduledLetSuffixStep(trace,pending,previous,depth)
<1>hypothesis. FiniteNatInductiveDefHypothesis(suffix,terminalAction,advance,0,count)
    BY ONLY DEF FiniteNatInductiveDefHypothesis, suffix, ScheduledLetSuffixValues, advance, count
<1>bounds. 0 \in Nat /\ count \in Nat
    BY ONLY (Len(trace.rows) \in Nat), SMT DEF count
<1>law. FiniteNatInductiveDefConclusion(suffix,terminalAction,advance,0,count)
    BY ONLY <1>hypothesis, <1>bounds, FiniteNatInductiveDef, IsaM("blast"), SMT
<1>recurrence. suffix =
    [depth \in 0..count |->
        IF depth = 0 THEN terminalAction ELSE advance(suffix[depth-1],depth)]
    BY ONLY <1>law DEF FiniteNatInductiveDefConclusion
<1>index. \A i \in 1..(count+1) : actions[i] = suffix[count+1-i]
    BY ONLY SMT DEF actions, CompiledLetSuffixes, suffix, count
<1>size. DOMAIN actions = 1..(count+1)
    BY ONLY DEF CompiledLetSuffixes, actions, count
<1>end. actions[count+1] = terminalAction
    BY ONLY <1>index, <1>recurrence, (Len(trace.rows) \in Nat), SMT DEF count
<1>step. \A i \in DOMAIN trace.rows :
    LET row == trace.bodies[i][1]
    IN actions[i] = [kind |-> "define", name |-> row.variable, value |-> row.value, body |-> actions[i+1]]
    <2>. TAKE i \in DOMAIN trace.rows
    <2>. DEFINE row == trace.bodies[i][1]
    <2>bounds. /\ i \in 1..count /\ count+1-i \in 1..count /\ count+1-(i+1) = (count+1-i)-1
        BY ONLY (i \in DOMAIN trace.rows), (Len(trace.rows) \in Nat),
            (DOMAIN trace.rows = 1..Len(trace.rows)), SMT DEF count
    <2>shape. /\ trace.bodies[i] = <<row>> /\ row.kind = "letBinding"
               /\ row.body = trace.bodies[i+1] /\ row.body \in Seq(statementSet)
        BY ONLY (i \in DOMAIN trace.rows),
            (\A j \in DOMAIN trace.rows : /\ trace.bodies[j] = <<trace.bodies[j][1]>>
               /\ trace.bodies[j][1].kind = "letBinding" /\ trace.bodies[j][1].body = trace.bodies[j+1]
               /\ trace.bodies[j+1] \in Seq(statementSet)), SMT DEF row
    <2>ordinals. i \in Int /\ count \in Int
        BY ONLY <1>bounds, <2>bounds, SMT
    <2>indexBounds. /\ i \in 1..(count+1) /\ i+1 \in 1..(count+1)
                     /\ count+1-(i+1) = count-i
        BY ONLY <2>bounds, <2>ordinals, SMT
    <2>atRow. actions[i] = suffix[count+1-i]
        BY ONLY <1>index, <2>indexBounds, SMT
    <2>atChild. actions[i+1] = suffix[count-i]
        BY ONLY <1>index, <2>indexBounds, SMT
    <2>depth. /\ count+1-i \in 0..count /\ count+1-i # 0
               /\ (count+1-i)-1 = count-i
        BY ONLY <2>bounds, <2>ordinals, SMT
    <2>rowStep. suffix[count+1-i] =
        IF count+1-i = 0 THEN terminalAction ELSE advance(suffix[(count+1-i)-1],count+1-i)
        BY ONLY <1>recurrence, <2>depth, SMT
    <2>rowRecurrence. suffix[count+1-i] = advance(suffix[count-i],count+1-i)
        BY ONLY <2>rowStep, <2>depth, SMT
    <2>childRecurrence. suffix[count+1-i] = advance(actions[i+1],count+1-i)
        BY ONLY <2>rowRecurrence, <2>atChild, SMT
    <2>samePosition. Len(trace.rows)+1-(count+1-i) = i
        BY ONLY <2>ordinals, SMT DEF count
    <2>advanced. advance(actions[i+1],count+1-i) =
        ScheduledLetActionForChild(trace.bodies[i],pending,trace.bodies[i+1],actions[i+1])
        BY ONLY <2>samePosition, SMT DEF advance, ScheduledLetSuffixStep
    <2>unfold. actions[i] =
        ScheduledLetActionForChild(trace.bodies[i],pending,trace.bodies[i+1],actions[i+1])
        BY ONLY <2>atRow, <2>childRecurrence, <2>advanced, SMT
    <2>sourceCall. ScheduledLetActionForChild(<<row>>,pending,trace.bodies[i+1],actions[i+1]) =
        [kind |-> "define",name |-> row.variable,value |-> row.value,body |-> actions[i+1]]
        BY ONLY <2>shape, TheActualLetWrapsItsMatchedChildAction, SMT
    <2>. QED BY ONLY <2>shape, <2>unfold, <2>sourceCall, SMT
<1>. QED BY ONLY <1>size, <1>end, <1>step DEF ActualActionDefinesMatchTheScheduledLets, count, actions
====
