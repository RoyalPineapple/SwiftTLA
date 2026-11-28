---- MODULE StandaloneAtomicRun ----
EXTENDS ScheduledLetActionTrace, StandaloneAtomicLoweringSource

StandaloneRunCall(statements, values) == [statements |-> statements, values |-> values]
StandaloneRunProbe(statements, values) == [action |-> StandaloneRunCall(statements,values)]

\* Read the operands supplied to the actual recursive LET call. The probe
\* returns them as an action payload solely to observe the call; normal return
\* evaluation below supplies the independently computed child action.
StandaloneChildCall(call) ==
    ScheduledLetAction(call.statements,call.values,<<>>,
                       LAMBDA value,roots : value,StandaloneRunProbe).body

StandaloneBoundedChain(initial, first, last, Step(_, _)) ==
    LET chain[i \in first..last] ==
            IF i = first THEN initial ELSE Step(chain[i-1],i)
    IN chain

StandaloneRunCalls(statements, values, count) ==
    StandaloneBoundedChain(StandaloneRunCall(statements,values),1,count+1,
                           LAMBDA call,index : StandaloneChildCall(call))

StandaloneRunReturnStep(calls, count, childAction, depth) ==
    LET i == count + 1 - depth
        call == calls[i]
        child == calls[i+1]
    IN ScheduledLetActionForChild(call.statements,call.values,child.statements,childAction)

StandaloneRunReturns(calls, count, Less(_, _)) ==
    LET terminal == calls[count+1]
        action == ActualStandaloneTerminalRun(terminal.statements,terminal.values,Less)
    IN StandaloneBoundedChain(action,0,count,
                              LAMBDA child,depth : StandaloneRunReturnStep(calls,count,child,depth))

\* Source-backed execution depends only on the operands passed to run. The
\* count is a finite depth bound; the theorem below proves every preceding
\* call selected a LET and that its terminal came from that same chain.
ActualStandaloneRun(statements, values, count, Less(_, _)) ==
    LET calls == StandaloneRunCalls(statements,values,count)
    IN [action |-> StandaloneRunReturns(calls,count,Less)[count]]

THEOREM TheStandaloneLetCallsItsActualChildWithTheOldValues ==
    ASSUME NEW head, NEW values, NEW items, head.kind = "letBinding", head.body \in Seq(items)
    PROVE StandaloneChildCall(StandaloneRunCall(<<head>>,values)) =
          StandaloneRunCall(head.body,values)
PROOF
<1>actual. ScheduledLetAction(<<head>>,values,<<>>,LAMBDA value,roots : value,StandaloneRunProbe) =
    [kind |-> "define", name |-> head.variable,
     value |-> ScopedLetValue(<<>>,head.value,LAMBDA value,roots : value),
     body |-> StandaloneRunProbe(head.body,values).action]
    BY ONLY (head.kind = "letBinding"), (head.body \in Seq(items)),
        OneReturnedScheduledLetIsTheActualDefineAroundItsContinuation
<1>. QED BY ONLY <1>actual, IsaM("simp"), SMT
    DEF StandaloneChildCall, StandaloneRunCall, StandaloneRunProbe

THEOREM StandaloneBoundedChainUsesTheGivenSourceSteps ==
    ASSUME NEW initial, NEW first \in Nat, NEW last \in Nat, NEW Step(_, _)
    PROVE FiniteNatInductiveDefConclusion(
              StandaloneBoundedChain(initial,first,last,Step),initial,Step,first,last)
PROOF
<1>chosen. FiniteNatInductiveDefHypothesis(
    StandaloneBoundedChain(initial,first,last,Step),initial,Step,first,last)
    BY ONLY DEF StandaloneBoundedChain, FiniteNatInductiveDefHypothesis
<1>. QED BY ONLY <1>chosen, (first \in Nat), (last \in Nat), FiniteNatInductiveDef, IsaM("blast")

THEOREM StandaloneRunCallsFollowTheReturnedLetChildren ==
    ASSUME NEW trace, NEW items, NEW values, Len(trace.rows) \in Nat,
           \A i \in 1..Len(trace.rows) :
               /\ trace.bodies[i] = <<trace.bodies[i][1]>>
               /\ trace.bodies[i][1].kind = "letBinding"
               /\ trace.bodies[i][1].body = trace.bodies[i+1]
               /\ trace.bodies[i+1] \in Seq(items)
    PROVE StandaloneRunCalls(trace.bodies[1],values,Len(trace.rows)) =
          [i \in 1..(Len(trace.rows)+1) |-> StandaloneRunCall(trace.bodies[i],values)]
PROOF
<1>. DEFINE last == Len(trace.rows)+1
            initial == StandaloneRunCall(trace.bodies[1],values)
            calls == StandaloneRunCalls(trace.bodies[1],values,Len(trace.rows))
            seen == [i \in 1..last |-> StandaloneRunCall(trace.bodies[i],values)]
            advance(call,i) == StandaloneChildCall(call)
<1>nat. 1 \in Nat /\ last \in Nat
    BY ONLY (Len(trace.rows) \in Nat), SMT DEF last
<1>actual. FiniteNatInductiveDefConclusion(calls,initial,advance,1,last)
    BY ONLY <1>nat, StandaloneBoundedChainUsesTheGivenSourceSteps
        DEF calls, StandaloneRunCalls, initial, advance, last
<1>forward. \A i \in 2..last : seen[i] = advance(seen[i-1],i)
    <2>. TAKE i \in 2..last
    <2>. DEFINE parent == trace.bodies[i-1]
                head == parent[1]
    <2>indices. /\ i-1 \in 1..Len(trace.rows) /\ i-1+1 = i
                /\ i \in 1..last /\ i-1 \in 1..last
        BY ONLY (i \in 2..last), (Len(trace.rows) \in Nat), SMT DEF last
    <2>shape. /\ parent = <<head>> /\ head.kind = "letBinding"
              /\ head.body = trace.bodies[i] /\ head.body \in Seq(items)
        BY ONLY <2>indices,
            (\A j \in 1..Len(trace.rows) : /\ trace.bodies[j] = <<trace.bodies[j][1]>>
               /\ trace.bodies[j][1].kind = "letBinding"
               /\ trace.bodies[j][1].body = trace.bodies[j+1]
               /\ trace.bodies[j+1] \in Seq(items)), SMT DEF parent, head
    <2>child. StandaloneChildCall(StandaloneRunCall(<<head>>,values)) =
                StandaloneRunCall(head.body,values)
        BY ONLY <2>shape, TheStandaloneLetCallsItsActualChildWithTheOldValues
    <2>lookups. /\ seen[i] = StandaloneRunCall(trace.bodies[i],values)
                /\ seen[i-1] = StandaloneRunCall(parent,values)
        BY ONLY <2>indices, SMT DEF seen, parent
    <2>. QED BY ONLY <2>shape, <2>child, <2>lookups, SMT DEF advance
<1>base. seen[1] = initial /\ DOMAIN seen = 1..last
    BY ONLY <1>nat, (Len(trace.rows) \in Nat), SMT DEF seen, initial, last
<1>reference. FiniteNatInductiveDefConclusion(seen,initial,advance,1,last)
    BY ONLY <1>base, <1>forward, <1>nat, SMT DEF FiniteNatInductiveDefConclusion
<1>unique. calls = seen
    BY ONLY <1>nat, <1>actual, <1>reference, FiniteNatInductiveUnique, Zenon, SMT, IsaM("blast")
<1>. QED BY ONLY <1>unique DEF calls, seen, last

THEOREM StandaloneRunReturnsTheCompiledLetSuffix ==
    ASSUME NEW trace, NEW items, NEW values, NEW Less(_, _), Len(trace.rows) \in Nat,
           \A i \in 1..Len(trace.rows) :
               /\ trace.bodies[i] = <<trace.bodies[i][1]>>
               /\ trace.bodies[i][1].kind = "letBinding"
               /\ trace.bodies[i][1].body = trace.bodies[i+1]
               /\ trace.bodies[i+1] \in Seq(items)
    PROVE LET terminal == ActualStandaloneTerminalRun(trace.bodies[Len(trace.rows)+1],values,Less)
          IN ActualStandaloneRun(trace.bodies[1],values,Len(trace.rows),Less).action =
                CompiledLetSuffixes(trace,values,terminal)[1]
PROOF
<1>. DEFINE count == Len(trace.rows)
            last == count+1
            seen == [i \in 1..last |-> StandaloneRunCall(trace.bodies[i],values)]
            calls == StandaloneRunCalls(trace.bodies[1],values,count)
            returns == StandaloneRunReturns(calls,count,Less)
            terminal == ActualStandaloneTerminalRun(trace.bodies[last],values,Less)
            suffix == ScheduledLetSuffixValues(trace,values,terminal)
            sourceStep(action,depth) == StandaloneRunReturnStep(calls,count,action,depth)
            suffixStep(action,depth) == ScheduledLetSuffixStep(trace,values,action,depth)
<1>calls. calls = seen
    BY ONLY (Len(trace.rows) \in Nat),
        (\A i \in 1..Len(trace.rows) : /\ trace.bodies[i] = <<trace.bodies[i][1]>>
             /\ trace.bodies[i][1].kind = "letBinding" /\ trace.bodies[i][1].body = trace.bodies[i+1]
             /\ trace.bodies[i+1] \in Seq(items)),
        StandaloneRunCallsFollowTheReturnedLetChildren DEF calls, seen, last, count
<1>nat. 0 \in Nat /\ count \in Nat /\ last \in 1..last
    BY ONLY (Len(trace.rows) \in Nat), SMT DEF last, count
<1>last. calls[last] = StandaloneRunCall(trace.bodies[last],values)
    BY ONLY <1>calls, <1>nat, SMT DEF seen
<1>seed. ActualStandaloneTerminalRun(calls[last].statements,calls[last].values,Less) = terminal
    BY ONLY <1>last, SMT DEF terminal, StandaloneRunCall
<1>actual. FiniteNatInductiveDefConclusion(returns,terminal,sourceStep,0,count)
    <2>raw. FiniteNatInductiveDefConclusion(returns,
        ActualStandaloneTerminalRun(calls[last].statements,calls[last].values,Less),sourceStep,0,count)
        BY ONLY <1>nat, StandaloneBoundedChainUsesTheGivenSourceSteps
            DEF returns, StandaloneRunReturns, sourceStep, last
    <2>. QED BY ONLY <2>raw, <1>seed
<1>step. \A depth \in 1..count : \A action : sourceStep(action,depth) = suffixStep(action,depth)
    <2>. TAKE depth \in 1..count
    <2>. TAKE action
    <2>. DEFINE i == last-depth
    <2>indices. i \in 1..last /\ i+1 \in 1..last
        BY ONLY (depth \in 1..count), <1>nat, SMT DEF i, last
    <2>arguments. /\ calls[i] = StandaloneRunCall(trace.bodies[i],values)
                   /\ calls[i+1] = StandaloneRunCall(trace.bodies[i+1],values)
        BY ONLY <1>calls, <2>indices, SMT DEF seen
    <2>operands. /\ calls[i].statements = trace.bodies[i] /\ calls[i].values = values
                  /\ calls[i+1].statements = trace.bodies[i+1]
        BY ONLY <2>arguments, IsaM("simp"), SMT DEF StandaloneRunCall
    <2>source. sourceStep(action,depth) = ScheduledLetActionForChild(calls[i].statements,calls[i].values,calls[i+1].statements,action)
        BY ONLY <2>indices, (depth \in 1..count), <1>nat, SMT DEF sourceStep, StandaloneRunReturnStep, i, last
    <2>target. suffixStep(action,depth) = ScheduledLetActionForChild(trace.bodies[i],values,trace.bodies[i+1],action)
        BY ONLY <2>indices, (depth \in 1..count), <1>nat, SMT DEF suffixStep, ScheduledLetSuffixStep, i, last, count
    <2>. QED BY ONLY <2>operands, <2>source, <2>target, SMT
<1>interpreted. FiniteNatInductiveDefConclusion(returns,terminal,suffixStep,0,count)
    BY ONLY <1>actual, <1>step, <1>nat, SMT DEF FiniteNatInductiveDefConclusion
<1>suffix. FiniteNatInductiveDefConclusion(suffix,terminal,suffixStep,0,count)
    <2>chosen. FiniteNatInductiveDefHypothesis(suffix,terminal,suffixStep,0,count)
        BY ONLY DEF FiniteNatInductiveDefHypothesis, suffix, ScheduledLetSuffixValues, suffixStep, count
    <2>. QED BY ONLY <2>chosen, <1>nat, FiniteNatInductiveDef, IsaM("blast")
<1>same. returns = suffix
    BY ONLY <1>interpreted, <1>suffix, <1>nat, FiniteNatInductiveUnique, IsaM("blast")
<1>output. ActualStandaloneRun(trace.bodies[1],values,count,Less).action = returns[count]
    BY ONLY DEF ActualStandaloneRun, returns, calls
<1>first. CompiledLetSuffixes(trace,values,terminal)[1] = suffix[count]
    BY ONLY <1>nat, SMT DEF CompiledLetSuffixes, suffix, last, count
<1>. QED BY ONLY <1>same, <1>output, <1>first, SMT DEF count, terminal, last
====
