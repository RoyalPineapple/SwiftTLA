----------------------- MODULE SingleAssignment -----------------------
EXTENDS TLAPS, NaturalsInduction, SequenceTheorems, GeneratedAtomicCopyProofModel
VARIABLE choiceSelected
Choice == INSTANCE GeneratedGuardedChoiceProofModel WITH selected <- choiceSelected
VARIABLES dependentPC, dependentSeed, dependentChoice
DependentInit == INSTANCE DependentInitializationOutputProofModel
    WITH pc <- dependentPC, seed <- dependentSeed, choice <- dependentChoice
CONSTANTS Vars, Values, Key, ActionLabels
ASSUME KeyIsVariable == Key \in Vars

States == [Vars -> Values]
LabeledEdges == States \X ActionLabels \X States

ChoiceEdges(domain, branches) == UNION {branches[value] : value \in domain}
GuardEdges(enabled, edges) == IF enabled THEN edges ELSE {}
EnabledIn(edges, state, action) ==
    \E successor \in States : <<state, action, successor>> \in edges

InjectiveOn(mapping, domain) ==
    \A first, second \in domain : mapping[first] = mapping[second] => first = second
PointwiseStateEncoding(valueMap, state) ==
    [key \in Vars |-> valueMap[state[key]]]
TypedStates(domains) ==
    {state \in States : \A key \in Vars : state[key] \in domains[key]}
PerFieldStateEncoding(valueMaps, state) ==
    [key \in Vars |-> valueMaps[key][state[key]]]

THEOREM PointwiseStateEncodingIsInjective ==
    \A valueMap \in [Values -> Values] :
        InjectiveOn(valueMap, Values) =>
            InjectiveOn(
                [state \in States |-> PointwiseStateEncoding(valueMap, state)],
                States)
    BY SMT DEF InjectiveOn, PointwiseStateEncoding, States

THEOREM PerFieldStateEncodingIsInjective ==
    \A domains \in [Vars -> SUBSET Values],
       valueMaps \in [Vars -> [Values -> Values]] :
        (\A key \in Vars : InjectiveOn(valueMaps[key], domains[key]))
        => InjectiveOn(
            [state \in TypedStates(domains) |-> PerFieldStateEncoding(valueMaps, state)],
            TypedStates(domains))
    PROOF
    <1>. SUFFICES ASSUME NEW domains \in [Vars -> SUBSET Values],
                          NEW valueMaps \in [Vars -> [Values -> Values]],
                          \A key \in Vars : InjectiveOn(valueMaps[key], domains[key])
                  PROVE InjectiveOn(
                      [state \in TypedStates(domains) |-> PerFieldStateEncoding(valueMaps, state)],
                      TypedStates(domains))
    <1>1. \A first, second \in TypedStates(domains) :
             PerFieldStateEncoding(valueMaps, first)
                 = PerFieldStateEncoding(valueMaps, second)
             => first = second
        PROOF
        <2>. SUFFICES ASSUME NEW first \in TypedStates(domains),
                              NEW second \in TypedStates(domains),
                              PerFieldStateEncoding(valueMaps, first)
                                  = PerFieldStateEncoding(valueMaps, second)
                      PROVE first = second
        <2>1. \A key \in Vars : first[key] = second[key]
            PROOF
            <3>. SUFFICES ASSUME NEW key \in Vars
                          PROVE first[key] = second[key]
            <3>1. first[key] \in domains[key]
                BY SMT DEF TypedStates, States
            <3>2. second[key] \in domains[key]
                BY SMT DEF TypedStates, States
            <3>3. PerFieldStateEncoding(valueMaps, first)[key]
                    = PerFieldStateEncoding(valueMaps, second)[key]
                BY SMT
            <3>4. PerFieldStateEncoding(valueMaps, first)[key]
                    = valueMaps[key][first[key]]
                BY DEF PerFieldStateEncoding
            <3>5. PerFieldStateEncoding(valueMaps, second)[key]
                    = valueMaps[key][second[key]]
                BY DEF PerFieldStateEncoding
            <3>6. valueMaps[key][first[key]] = valueMaps[key][second[key]]
                BY <3>3, <3>4, <3>5, SMT
            <3>7. first[key] = second[key]
                BY <3>1, <3>2, <3>6, SMT DEF InjectiveOn
            <3>8. QED BY <3>7
        <2>2. first = second
            BY <2>1, SMT DEF TypedStates, States
        <2>3. QED BY <2>2
    <1>2. QED BY <1>1 DEF InjectiveOn

UniqueControlName(ids, source, location) ==
    \A other \in ids : source[other] = source[location] => other = location
ScopedControlName(ids, source, fresh, location) ==
    IF UniqueControlName(ids, source, location)
    THEN source[location]
    ELSE fresh[location]

THEOREM ScopedControlNamingIsInjective ==
    \A ids \in SUBSET Values :
      \A source, fresh \in [ids -> Values] :
        (InjectiveOn(fresh, ids)
         /\ {fresh[location] : location \in ids}
            \cap {source[location] : location \in ids} = {})
        => InjectiveOn(
            [location \in ids |-> ScopedControlName(ids, source, fresh, location)],
            ids)
    BY SMT DEF InjectiveOn, ScopedControlName, UniqueControlName

MappedSetEncoding(valueMap, members) ==
    {valueMap[value] : value \in members}

THEOREM MappedSetMembership ==
    \A valueMap \in [Values -> Values], members \in SUBSET Values,
       encoded \in Values :
        (encoded \in MappedSetEncoding(valueMap, members))
        <=> (\E value \in members : valueMap[value] = encoded)
    BY SMT DEF MappedSetEncoding

THEOREM EqualEncodedSetsHaveSubset ==
    \A valueMap \in [Values -> Values] :
        InjectiveOn(valueMap, Values) =>
            \A first, second \in SUBSET Values :
                MappedSetEncoding(valueMap, first)
                    = MappedSetEncoding(valueMap, second)
                => first \subseteq second
    PROOF
    <1>. SUFFICES ASSUME NEW valueMap \in [Values -> Values],
                          InjectiveOn(valueMap, Values),
                          NEW first \in SUBSET Values,
                          NEW second \in SUBSET Values,
                          MappedSetEncoding(valueMap, first)
                            = MappedSetEncoding(valueMap, second),
                          NEW value \in first
                  PROVE value \in second
        BY SMT DEF InjectiveOn
    <1>1. valueMap[value] \in MappedSetEncoding(valueMap, first)
        BY SMT DEF MappedSetEncoding
    <1>2. valueMap[value] \in MappedSetEncoding(valueMap, second)
        BY <1>1, SMT
    <1>3. \E other \in second : valueMap[other] = valueMap[value]
        BY <1>2, MappedSetMembership, SMT
    <1>4. PICK other \in second : valueMap[other] = valueMap[value]
        BY <1>3
    <1>5. other = value
        BY <1>4, SMT DEF InjectiveOn
    <1>. QED
        BY <1>4, <1>5

THEOREM InjectiveSetEncoding ==
    \A valueMap \in [Values -> Values] :
        InjectiveOn(valueMap, Values) =>
            InjectiveOn(
                [members \in SUBSET Values |-> MappedSetEncoding(valueMap, members)],
                SUBSET Values)
    PROOF
    <1>. SUFFICES ASSUME NEW valueMap \in [Values -> Values],
                          InjectiveOn(valueMap, Values),
                          NEW first \in SUBSET Values,
                          NEW second \in SUBSET Values,
                          MappedSetEncoding(valueMap, first)
                            = MappedSetEncoding(valueMap, second)
                  PROVE first = second
        BY SMT DEF InjectiveOn
    <1>1. first \subseteq second
        BY EqualEncodedSetsHaveSubset, SMT
    <1>2. second \subseteq first
        BY EqualEncodedSetsHaveSubset, SMT
    <1>3. \A value : (value \in first) <=> (value \in second)
        BY <1>1, <1>2, SMT
    <1>. QED
        BY <1>3, SetExtensionality

MappedSequenceEncoding(valueMap, sequence) ==
    [index \in 1..Len(sequence) |-> valueMap[sequence[index]]]

THEOREM InjectiveSequenceEncoding ==
    \A valueMap \in [Values -> Values] :
        InjectiveOn(valueMap, Values) =>
            InjectiveOn(
                [sequence \in Seq(Values) |-> MappedSequenceEncoding(valueMap, sequence)],
                Seq(Values))
    PROOF
    <1>. SUFFICES ASSUME NEW valueMap \in [Values -> Values],
                          InjectiveOn(valueMap, Values),
                          NEW first \in Seq(Values),
                          NEW second \in Seq(Values),
                          MappedSequenceEncoding(valueMap, first)
                            = MappedSequenceEncoding(valueMap, second)
                  PROVE first = second
        BY SMT DEF InjectiveOn
    <1>1. Len(first) = Len(second)
        BY SMT DEF MappedSequenceEncoding
    <1>2. \A index \in 1..Len(first) : first[index] = second[index]
        BY <1>1, SMT DEF MappedSequenceEncoding, InjectiveOn
    <1>. QED
        BY <1>1, <1>2, SeqEqual

ActionCalls == ActionLabels \X Seq(Values)
MappedActionCall(nameMap, valueMap, call) ==
    <<nameMap[call[1]], MappedSequenceEncoding(valueMap, call[2])>>

THEOREM InjectiveActionCallEncoding ==
    \A nameMap \in [ActionLabels -> ActionLabels],
       valueMap \in [Values -> Values] :
        (InjectiveOn(nameMap, ActionLabels)
         /\ InjectiveOn(valueMap, Values))
        => InjectiveOn(
            [call \in ActionCalls |-> MappedActionCall(nameMap, valueMap, call)],
            ActionCalls)
    PROOF
    <1>. SUFFICES ASSUME NEW nameMap \in [ActionLabels -> ActionLabels],
                          NEW valueMap \in [Values -> Values],
                          InjectiveOn(nameMap, ActionLabels),
                          InjectiveOn(valueMap, Values),
                          NEW first \in ActionCalls,
                          NEW second \in ActionCalls,
                          MappedActionCall(nameMap, valueMap, first)
                            = MappedActionCall(nameMap, valueMap, second)
                  PROVE first = second
        BY SMT DEF InjectiveOn
    <1>1. nameMap[first[1]] = nameMap[second[1]]
          /\ MappedSequenceEncoding(valueMap, first[2])
                = MappedSequenceEncoding(valueMap, second[2])
        BY SMT DEF MappedActionCall
    <1>2. first[1] = second[1]
        BY <1>1, SMT DEF InjectiveOn, ActionCalls
    <1>3. first[2] = second[2]
        BY <1>1, InjectiveSequenceEncoding, SMT DEF InjectiveOn, ActionCalls
    <1>. QED
        BY <1>2, <1>3, SMT DEF ActionCalls

PartialFunctions == UNION {[keys -> Values] : keys \in SUBSET Values}
MappedFunctionGraph(keyMap, valueMap, mapping) ==
    {<<keyMap[key], valueMap[mapping[key]]>> : key \in DOMAIN mapping}

THEOREM InjectiveFunctionGraphEncoding ==
    \A keyMap, valueMap \in [Values -> Values] :
        (InjectiveOn(keyMap, Values) /\ InjectiveOn(valueMap, Values))
        => InjectiveOn(
            [mapping \in PartialFunctions |->
                MappedFunctionGraph(keyMap, valueMap, mapping)],
            PartialFunctions)
    PROOF
    <1>. SUFFICES ASSUME NEW keyMap \in [Values -> Values],
                          NEW valueMap \in [Values -> Values],
                          InjectiveOn(keyMap, Values),
                          InjectiveOn(valueMap, Values),
                          NEW first \in PartialFunctions,
                          NEW second \in PartialFunctions,
                          MappedFunctionGraph(keyMap, valueMap, first)
                            = MappedFunctionGraph(keyMap, valueMap, second)
                  PROVE first = second
        BY SMT DEF InjectiveOn
    <1>1. \A key \in DOMAIN first :
             \E other \in DOMAIN second :
                 keyMap[key] = keyMap[other]
                 /\ valueMap[first[key]] = valueMap[second[other]]
        BY SMT DEF MappedFunctionGraph
    <1>2. \A key \in DOMAIN first :
             key \in DOMAIN second /\ first[key] = second[key]
        BY <1>1, SMT DEF InjectiveOn, PartialFunctions
    <1>3. \A key \in DOMAIN second : key \in DOMAIN first
        PROOF
        <2>. SUFFICES ASSUME NEW key \in DOMAIN second
                      PROVE key \in DOMAIN first
        <2>1. <<keyMap[key], valueMap[second[key]]>>
                \in MappedFunctionGraph(keyMap, valueMap, second)
            BY SMT DEF MappedFunctionGraph
        <2>2. <<keyMap[key], valueMap[second[key]]>>
                \in MappedFunctionGraph(keyMap, valueMap, first)
            BY <2>1, SMT
        <2>3. \E other \in DOMAIN first : keyMap[key] = keyMap[other]
            BY <2>2, SMT DEF MappedFunctionGraph
        <2>4. PICK other \in DOMAIN first : keyMap[key] = keyMap[other]
            BY <2>3
        <2>5. other = key
            BY <2>4, SMT DEF InjectiveOn, PartialFunctions
        <2>. QED
            BY <2>4, <2>5
    <1>4. DOMAIN first = DOMAIN second
        BY <1>2, <1>3, SetExtensionality
    <1>. QED
        BY <1>2, <1>4, SMT DEF PartialFunctions

UntaggedUnionEncoding(leftDomain, rightDomain, leftMap, rightMap) ==
    [tagged \in ({"left"} \X leftDomain) \cup ({"right"} \X rightDomain) |->
        IF tagged[1] = "left"
        THEN leftMap[tagged[2]]
        ELSE rightMap[tagged[2]]]

THEOREM DisjointUntaggedUnionEncodingIsInjective ==
    \A leftDomain, rightDomain \in SUBSET Values :
        \A leftMap \in [leftDomain -> Values],
           rightMap \in [rightDomain -> Values] :
            (InjectiveOn(leftMap, leftDomain)
             /\ InjectiveOn(rightMap, rightDomain)
             /\ {leftMap[value] : value \in leftDomain}
                \cap {rightMap[value] : value \in rightDomain} = {})
            => InjectiveOn(
                UntaggedUnionEncoding(leftDomain, rightDomain,
                    leftMap, rightMap),
                ({"left"} \X leftDomain) \cup ({"right"} \X rightDomain))
    BY SMT DEF InjectiveOn, UntaggedUnionEncoding, States

MappedStates(states, stateMap) ==
    {stateMap[state] : state \in states}
MappedEdges(edges, stateMap, actionMap) ==
    {<<stateMap[edge[1]], actionMap[edge[2]], stateMap[edge[3]]>> : edge \in edges}

THEOREM ExactStateCorrespondence ==
    \A stateMap \in [States -> States] :
        InjectiveOn(stateMap, States) =>
            \A initial \in SUBSET States, state \in States :
                (stateMap[state] \in MappedStates(initial, stateMap))
                <=> (state \in initial)
    BY SMT DEF InjectiveOn, MappedStates, States

THEOREM ExactLabeledEdgeCorrespondence ==
    \A stateMap \in [States -> States],
       actionMap \in [ActionLabels -> ActionLabels] :
        InjectiveOn(stateMap, States) /\ InjectiveOn(actionMap, ActionLabels) =>
            \A edges \in SUBSET LabeledEdges,
               source, target \in States, action \in ActionLabels :
                (<<stateMap[source], actionMap[action], stateMap[target]>>
                 \in MappedEdges(edges, stateMap, actionMap))
                <=> (<<source, action, target>> \in edges)
    BY SMT DEF InjectiveOn, MappedEdges, LabeledEdges, States

EnabledChanging(edges, state, action) ==
    \E successor \in States :
        successor # state /\ <<state, action, successor>> \in edges

THEOREM ExactChangingEnablednessCorrespondence ==
    \A stateMap \in [States -> States],
       actionMap \in [ActionLabels -> ActionLabels] :
        InjectiveOn(stateMap, States) /\ InjectiveOn(actionMap, ActionLabels) =>
            \A edges \in SUBSET LabeledEdges,
               state \in States, action \in ActionLabels :
                EnabledChanging(MappedEdges(edges, stateMap, actionMap),
                    stateMap[state], actionMap[action])
                <=> EnabledChanging(edges, state, action)
    BY ExactLabeledEdgeCorrespondence, SMT
        DEF EnabledChanging, InjectiveOn, MappedEdges, LabeledEdges, States

HasOutgoing(edges, state) ==
    \E action \in ActionLabels, successor \in States :
        <<state, action, successor>> \in edges
Deadlocked(edges, state) == ~HasOutgoing(edges, state)

THEOREM ExactOutgoingCorrespondence ==
    \A stateMap \in [States -> States],
       actionMap \in [ActionLabels -> ActionLabels] :
        InjectiveOn(stateMap, States) =>
            \A edges \in SUBSET LabeledEdges, state \in States :
                HasOutgoing(MappedEdges(edges, stateMap, actionMap),
                    stateMap[state])
                <=> HasOutgoing(edges, state)
    BY SMT DEF HasOutgoing, MappedEdges, InjectiveOn, LabeledEdges, States

THEOREM ExactDeadlockCorrespondence ==
    \A stateMap \in [States -> States],
       actionMap \in [ActionLabels -> ActionLabels] :
        InjectiveOn(stateMap, States) =>
            \A edges \in SUBSET LabeledEdges, state \in States :
                Deadlocked(MappedEdges(edges, stateMap, actionMap),
                    stateMap[state])
                <=> Deadlocked(edges, state)
    BY ExactOutgoingCorrespondence, SMT DEF Deadlocked

TraceStep(edges, before, after) ==
    before = after
    \/ (\E action \in ActionLabels : <<before, action, after>> \in edges)
MappedRun(run, stateMap) ==
    [index \in Nat |-> stateMap[run[index]]]
ValidRun(edges, run) ==
    \A index \in Nat : TraceStep(edges, run[index], run[index + 1])

THEOREM ExactTraceStepCorrespondence ==
    \A stateMap \in [States -> States],
       actionMap \in [ActionLabels -> ActionLabels] :
        InjectiveOn(stateMap, States) /\ InjectiveOn(actionMap, ActionLabels) =>
            \A edges \in SUBSET LabeledEdges, before, after \in States :
                TraceStep(MappedEdges(edges, stateMap, actionMap),
                    stateMap[before], stateMap[after])
                <=> TraceStep(edges, before, after)
    BY ExactLabeledEdgeCorrespondence, SMT
        DEF TraceStep, InjectiveOn, MappedEdges, LabeledEdges, States

THEOREM MappedEdgeEndpointsHavePreimages ==
    \A stateMap \in [States -> States],
       actionMap \in [ActionLabels -> ActionLabels] :
        \A edges \in SUBSET LabeledEdges,
           before, after \in States, action \in ActionLabels :
            <<before, action, after>> \in MappedEdges(edges, stateMap, actionMap)
            => before \in MappedStates(States, stateMap)
               /\ after \in MappedStates(States, stateMap)
    BY SMT DEF MappedEdges, MappedStates, LabeledEdges, States

THEOREM ExactRunCorrespondence ==
    \A stateMap \in [States -> States],
       actionMap \in [ActionLabels -> ActionLabels] :
        InjectiveOn(stateMap, States) /\ InjectiveOn(actionMap, ActionLabels) =>
            \A edges \in SUBSET LabeledEdges, run \in [Nat -> States] :
                ValidRun(MappedEdges(edges, stateMap, actionMap),
                    MappedRun(run, stateMap))
                <=> ValidRun(edges, run)
    BY ExactTraceStepCorrespondence, SMT
        DEF ValidRun, MappedRun, States

THEOREM TargetRunStaysInImage ==
    ASSUME NEW stateMap \in [States -> States],
           NEW actionMap \in [ActionLabels -> ActionLabels],
           NEW edges \in SUBSET LabeledEdges,
           NEW initial \in SUBSET States,
           NEW run \in [Nat -> States],
           run[0] \in MappedStates(initial, stateMap),
           ValidRun(MappedEdges(edges, stateMap, actionMap), run)
    PROVE \A index \in Nat : run[index] \in MappedStates(States, stateMap)
    PROOF
    <1>. DEFINE P(index) == run[index] \in MappedStates(States, stateMap)
    <1>1. P(0)
        BY SMT DEF P, MappedStates, States
    <1>2. ASSUME NEW index \in Nat, P(index)
          PROVE P(index + 1)
        <2>1. TraceStep(MappedEdges(edges, stateMap, actionMap),
                    run[index], run[index + 1])
            BY SMT DEF ValidRun
        <2>2. run[index] = run[index + 1] => P(index + 1)
            BY P(index), SMT DEF P
        <2>3. ASSUME \E action \in ActionLabels :
                    <<run[index], action, run[index + 1]>>
                    \in MappedEdges(edges, stateMap, actionMap)
              PROVE P(index + 1)
            <3>1. index + 1 \in Nat /\ run[index] \in States
                    /\ run[index + 1] \in States
                BY SMT
            <3>2. PICK action \in ActionLabels :
                    <<run[index], action, run[index + 1]>>
                    \in MappedEdges(edges, stateMap, actionMap)
                BY <2>3
            <3>3. run[index + 1] \in MappedStates(States, stateMap)
                BY <3>1, <3>2, MappedEdgeEndpointsHavePreimages, SMT
            <3>. QED
                BY <3>3 DEF P
        <2>. QED
            BY <2>1, <2>2, <2>3, SMT DEF TraceStep, P
    <1>. QED
        BY <1>1, <1>2, NatInduction DEF P

InverseState(stateMap, target) ==
    CHOOSE source \in States : stateMap[source] = target
LiftedRun(run, stateMap) ==
    [index \in Nat |-> InverseState(stateMap, run[index])]

THEOREM MappedStateHasInverse ==
    \A stateMap \in [States -> States] :
        \A target \in MappedStates(States, stateMap) :
            /\ InverseState(stateMap, target) \in States
            /\ stateMap[InverseState(stateMap, target)] = target
    BY SMT DEF InverseState, MappedStates, States

THEOREM InjectiveStateInverse ==
    \A stateMap \in [States -> States] :
        InjectiveOn(stateMap, States) =>
            \A state \in States : InverseState(stateMap, stateMap[state]) = state
    BY MappedStateHasInverse, SMT
        DEF InverseState, InjectiveOn, MappedStates, States

THEOREM LiftedRunIsMappedInverse ==
    ASSUME NEW stateMap \in [States -> States],
           NEW run \in [Nat -> States],
           \A index \in Nat : run[index] \in MappedStates(States, stateMap)
    PROVE /\ LiftedRun(run, stateMap) \in [Nat -> States]
          /\ MappedRun(LiftedRun(run, stateMap), stateMap) = run
    BY MappedStateHasInverse, SMT
        DEF LiftedRun, MappedRun, States

THEOREM MappedInitialHasSourceInverse ==
    \A stateMap \in [States -> States] :
        InjectiveOn(stateMap, States) =>
            \A initial \in SUBSET States :
                \A target \in MappedStates(initial, stateMap) :
                    InverseState(stateMap, target) \in initial
    BY InjectiveStateInverse, SMT
        DEF InverseState, MappedStates, InjectiveOn, States

THEOREM EveryMappedTargetRunLifts ==
    ASSUME NEW stateMap \in [States -> States],
           NEW actionMap \in [ActionLabels -> ActionLabels],
           InjectiveOn(stateMap, States),
           InjectiveOn(actionMap, ActionLabels),
           NEW edges \in SUBSET LabeledEdges,
           NEW initial \in SUBSET States,
           NEW targetRun \in [Nat -> States],
           targetRun[0] \in MappedStates(initial, stateMap),
           ValidRun(MappedEdges(edges, stateMap, actionMap), targetRun)
    PROVE /\ LiftedRun(targetRun, stateMap) \in [Nat -> States]
          /\ LiftedRun(targetRun, stateMap)[0] \in initial
          /\ ValidRun(edges, LiftedRun(targetRun, stateMap))
          /\ MappedRun(LiftedRun(targetRun, stateMap), stateMap) = targetRun
    PROOF
    <1>1. \A index \in Nat :
            targetRun[index] \in MappedStates(States, stateMap)
        BY TargetRunStaysInImage
    <1>2. /\ LiftedRun(targetRun, stateMap) \in [Nat -> States]
          /\ MappedRun(LiftedRun(targetRun, stateMap), stateMap) = targetRun
        BY <1>1, LiftedRunIsMappedInverse
    <1>3. LiftedRun(targetRun, stateMap)[0] \in initial
        BY MappedInitialHasSourceInverse, SMT DEF LiftedRun
    <1>4. ValidRun(edges, LiftedRun(targetRun, stateMap))
        BY <1>2, ExactRunCorrespondence, SMT
    <1>. QED
        BY <1>2, <1>3, <1>4

TakenChangingPair(edges, before, after, action) ==
    before # after /\ <<before, action, after>> \in edges
TakenChanging(edges, run, action, index) ==
    TakenChangingPair(edges, run[index], run[index + 1], action)

THEOREM ExactChangingActionEdgeCorrespondence ==
    \A stateMap \in [States -> States],
       actionMap \in [ActionLabels -> ActionLabels] :
        InjectiveOn(stateMap, States) /\ InjectiveOn(actionMap, ActionLabels) =>
            \A edges \in SUBSET LabeledEdges,
               before, after \in States, action \in ActionLabels :
                TakenChangingPair(MappedEdges(edges, stateMap, actionMap),
                    stateMap[before], stateMap[after], actionMap[action])
                <=> TakenChangingPair(edges, before, after, action)
    BY ExactLabeledEdgeCorrespondence, SMT
        DEF TakenChangingPair, InjectiveOn, States

THEOREM ExactRunEnablednessCorrespondence ==
    \A stateMap \in [States -> States],
       actionMap \in [ActionLabels -> ActionLabels] :
        InjectiveOn(stateMap, States) /\ InjectiveOn(actionMap, ActionLabels) =>
            \A edges \in SUBSET LabeledEdges,
               run \in [Nat -> States], action \in ActionLabels,
               index \in Nat :
                EnabledChanging(MappedEdges(edges, stateMap, actionMap),
                    stateMap[run[index]], actionMap[action])
                <=> EnabledChanging(edges, run[index], action)
    BY ExactChangingEnablednessCorrespondence, SMT DEF States

THEOREM ExactRunActionOccurrenceCorrespondence ==
    \A stateMap \in [States -> States],
       actionMap \in [ActionLabels -> ActionLabels] :
        InjectiveOn(stateMap, States) /\ InjectiveOn(actionMap, ActionLabels) =>
            \A edges \in SUBSET LabeledEdges,
               run \in [Nat -> States], action \in ActionLabels,
               index \in Nat :
                TakenChanging(MappedEdges(edges, stateMap, actionMap),
                    MappedRun(run, stateMap), actionMap[action], index)
                <=> TakenChanging(edges, run, action, index)
    BY ExactChangingActionEdgeCorrespondence, SMT
        DEF TakenChanging, MappedRun, States

WeakFairRun(edges, run, action) ==
    \A start \in Nat :
        (\A index \in Nat :
            index >= start => EnabledChanging(edges, run[index], action))
        => (\E index \in Nat :
            index >= start /\ TakenChanging(edges, run, action, index))
StrongFairRun(edges, run, action) ==
    (\A start \in Nat : \E index \in Nat :
        index >= start /\ EnabledChanging(edges, run[index], action))
    => (\A start \in Nat : \E index \in Nat :
        index >= start /\ TakenChanging(edges, run, action, index))

THEOREM ExactWeakFairRunCorrespondence ==
    \A stateMap \in [States -> States],
       actionMap \in [ActionLabels -> ActionLabels] :
        InjectiveOn(stateMap, States) /\ InjectiveOn(actionMap, ActionLabels) =>
            \A edges \in SUBSET LabeledEdges,
               run \in [Nat -> States], action \in ActionLabels :
                WeakFairRun(MappedEdges(edges, stateMap, actionMap),
                    MappedRun(run, stateMap), actionMap[action])
                <=> WeakFairRun(edges, run, action)
    BY ExactRunEnablednessCorrespondence,
        ExactRunActionOccurrenceCorrespondence, SMT
        DEF WeakFairRun, MappedRun, States

THEOREM ExactStrongFairRunCorrespondence ==
    \A stateMap \in [States -> States],
       actionMap \in [ActionLabels -> ActionLabels] :
        InjectiveOn(stateMap, States) /\ InjectiveOn(actionMap, ActionLabels) =>
            \A edges \in SUBSET LabeledEdges,
               run \in [Nat -> States], action \in ActionLabels :
                StrongFairRun(MappedEdges(edges, stateMap, actionMap),
                    MappedRun(run, stateMap), actionMap[action])
                <=> StrongFairRun(edges, run, action)
    BY ExactRunEnablednessCorrespondence,
        ExactRunActionOccurrenceCorrespondence, SMT
        DEF StrongFairRun, MappedRun, States

ClaimsAgreeUnderMap(sourceClaim, targetClaim, stateMap) ==
    \A state \in States : sourceClaim[state] = targetClaim[stateMap[state]]
AlwaysClaim(run, claim) ==
    \A index \in Nat : claim[run[index]]
EventuallyClaim(run, claim) ==
    \E index \in Nat : claim[run[index]]

THEOREM ExactInvariantClaimCorrespondence ==
    \A stateMap \in [States -> States],
       sourceClaim, targetClaim \in [States -> BOOLEAN],
       run \in [Nat -> States] :
        ClaimsAgreeUnderMap(sourceClaim, targetClaim, stateMap)
        => (AlwaysClaim(run, sourceClaim)
            <=> AlwaysClaim(MappedRun(run, stateMap), targetClaim))
    BY SMT DEF ClaimsAgreeUnderMap, AlwaysClaim, MappedRun, States

THEOREM ExactReachabilityClaimCorrespondence ==
    \A stateMap \in [States -> States],
       sourceClaim, targetClaim \in [States -> BOOLEAN],
       run \in [Nat -> States] :
        ClaimsAgreeUnderMap(sourceClaim, targetClaim, stateMap)
        => (EventuallyClaim(run, sourceClaim)
            <=> EventuallyClaim(MappedRun(run, stateMap), targetClaim))
    BY SMT DEF ClaimsAgreeUnderMap, EventuallyClaim, MappedRun, States

RefinementSteps(concreteEdges, abstractEdges, projection) ==
    \A edge \in concreteEdges :
        TraceStep(abstractEdges, projection[edge[1]], projection[edge[3]])

THEOREM EveryConcreteRunRefines ==
    ASSUME NEW concreteInitial \in SUBSET States,
           NEW abstractInitial \in SUBSET States,
           NEW concreteEdges \in SUBSET LabeledEdges,
           NEW abstractEdges \in SUBSET LabeledEdges,
           NEW projection \in [States -> States],
           NEW run \in [Nat -> States],
           MappedStates(concreteInitial, projection) \subseteq abstractInitial,
           RefinementSteps(concreteEdges, abstractEdges, projection),
           run[0] \in concreteInitial,
           ValidRun(concreteEdges, run)
    PROVE /\ MappedRun(run, projection)[0] \in abstractInitial
          /\ ValidRun(abstractEdges, MappedRun(run, projection))
    BY SMT DEF MappedStates, RefinementSteps, TraceStep, ValidRun,
        MappedRun, LabeledEdges, States

FairnessProjection(concreteEdges, abstractEdges, projection, run,
                   concreteAction, abstractAction) ==
    /\ \A index \in Nat :
        EnabledChanging(abstractEdges, projection[run[index]], abstractAction)
        => EnabledChanging(concreteEdges, run[index], concreteAction)
    /\ \A index \in Nat :
        TakenChanging(concreteEdges, run, concreteAction, index)
        => TakenChanging(abstractEdges, MappedRun(run, projection),
            abstractAction, index)

THEOREM WeakFairnessSurvivesRefinement ==
    \A concreteEdges, abstractEdges \in SUBSET LabeledEdges,
       projection \in [States -> States], run \in [Nat -> States],
       concreteAction, abstractAction \in ActionLabels :
        FairnessProjection(concreteEdges, abstractEdges, projection, run,
            concreteAction, abstractAction)
        => (WeakFairRun(concreteEdges, run, concreteAction)
            => WeakFairRun(abstractEdges, MappedRun(run, projection), abstractAction))
    BY SMT DEF FairnessProjection, WeakFairRun, MappedRun, States

THEOREM StrongFairnessSurvivesRefinement ==
    \A concreteEdges, abstractEdges \in SUBSET LabeledEdges,
       projection \in [States -> States], run \in [Nat -> States],
       concreteAction, abstractAction \in ActionLabels :
        FairnessProjection(concreteEdges, abstractEdges, projection, run,
            concreteAction, abstractAction)
        => (StrongFairRun(concreteEdges, run, concreteAction)
            => StrongFairRun(abstractEdges, MappedRun(run, projection), abstractAction))
    BY SMT DEF FairnessProjection, StrongFairRun, MappedRun, States

THEOREM GuardedChoiceComposition ==
    \A domain \in SUBSET Values :
        \A source, rendered \in [domain -> SUBSET LabeledEdges] :
            (\A value \in domain : source[value] = rendered[value]) =>
                \A guard \in BOOLEAN :
                    GuardEdges(guard, ChoiceEdges(domain, source))
                    = GuardEdges(guard, ChoiceEdges(domain, rendered))
    BY SMT DEF GuardEdges, ChoiceEdges, LabeledEdges, States

THEOREM GuardedChoiceEnabledness ==
    \A domain \in SUBSET Values :
        \A source, rendered \in [domain -> SUBSET LabeledEdges] :
            (\A value \in domain : source[value] = rendered[value]) =>
                \A guard \in BOOLEAN, state \in States, action \in ActionLabels :
                    EnabledIn(GuardEdges(guard, ChoiceEdges(domain, source)), state, action)
                    <=> EnabledIn(GuardEdges(guard, ChoiceEdges(domain, rendered)), state, action)
    BY GuardedChoiceComposition, SMT DEF EnabledIn

SequenceMembers(sequence) ==
    {sequence[index] : index \in 1..Len(sequence)}
EnumeratedExistentialEdges(candidates, branches) ==
    {edge \in LabeledEdges :
        \E index \in 1..Len(candidates[edge[1]]) :
            edge \in branches[edge[1]][candidates[edge[1]][index]]}
QuantifiedExistentialEdges(domains, branches) ==
    {edge \in LabeledEdges :
        \E value \in domains[edge[1]] :
            edge \in branches[edge[1]][value]}

THEOREM ExistentialEnumerationPreservesEdges ==
    \A candidates \in [States -> Seq(Values)] :
        \A domains \in [States -> SUBSET Values] :
            \A native, rendered \in [States -> [Values -> SUBSET LabeledEdges]] :
                (\A state \in States :
                    SequenceMembers(candidates[state]) = domains[state]
                    /\ (\A value \in domains[state] :
                        native[state][value] = rendered[state][value]))
                => EnumeratedExistentialEdges(candidates, native)
                   = QuantifiedExistentialEdges(domains, rendered)
    BY SMT DEF EnumeratedExistentialEdges, QuantifiedExistentialEdges,
        SequenceMembers, LabeledEdges, States

THEOREM ExistentialEnumerationPreservesEnabledness ==
    \A candidates \in [States -> Seq(Values)] :
        \A domains \in [States -> SUBSET Values] :
            \A native, rendered \in [States -> [Values -> SUBSET LabeledEdges]] :
                (\A state \in States :
                    SequenceMembers(candidates[state]) = domains[state]
                    /\ (\A value \in domains[state] :
                        native[state][value] = rendered[state][value]))
                => \A state \in States, action \in ActionLabels :
                    EnabledIn(EnumeratedExistentialEdges(candidates, native), state, action)
                    <=> EnabledIn(QuantifiedExistentialEdges(domains, rendered), state, action)
    BY ExistentialEnumerationPreservesEdges, SMT DEF EnabledIn

NativeDefinedEdges(values, branches) ==
    {edge \in LabeledEdges : edge \in branches[edge[1]][values[edge[1]]]}
RenderedDefinedEdges(values, branches) ==
    {edge \in LabeledEdges :
        LET bound == values[edge[1]]
        IN edge \in branches[edge[1]][bound]}

THEOREM DefinedBindingPreservesEdges ==
    \A nativeValues, renderedValues \in [States -> Values] :
        \A native, rendered \in [States -> [Values -> SUBSET LabeledEdges]] :
            (\A state \in States :
                nativeValues[state] = renderedValues[state]
                /\ native[state][nativeValues[state]]
                   = rendered[state][renderedValues[state]])
            => NativeDefinedEdges(nativeValues, native)
               = RenderedDefinedEdges(renderedValues, rendered)
    BY SMT DEF NativeDefinedEdges, RenderedDefinedEdges, LabeledEdges, States

THEOREM DefinedBindingPreservesEnabledness ==
    \A nativeValues, renderedValues \in [States -> Values] :
        \A native, rendered \in [States -> [Values -> SUBSET LabeledEdges]] :
            (\A state \in States :
                nativeValues[state] = renderedValues[state]
                /\ native[state][nativeValues[state]]
                   = rendered[state][renderedValues[state]])
            => \A state \in States, action \in ActionLabels :
                EnabledIn(NativeDefinedEdges(nativeValues, native), state, action)
                <=> EnabledIn(RenderedDefinedEdges(renderedValues, rendered), state, action)
    BY DefinedBindingPreservesEdges, SMT DEF EnabledIn

THEOREM UniqueExpressionChoice ==
    \A domain \in SUBSET Values :
        \A predicate \in [domain -> BOOLEAN] :
            \A witness \in domain :
                (predicate[witness]
                 /\ (\A member \in domain : predicate[member] => member = witness))
                => (CHOOSE member \in domain : predicate[member]) = witness
    BY SMT

THEOREM ObservationalExpressionChoice ==
    \A domain \in SUBSET Values :
        \A predicate \in [domain -> BOOLEAN] :
            \A observation \in [domain -> Values] :
                (\E witness \in domain : predicate[witness])
                /\ (\A first, second \in domain :
                    predicate[first] /\ predicate[second]
                    => observation[first] = observation[second])
                => \A native \in domain :
                    predicate[native]
                    => observation[native] =
                        observation[CHOOSE member \in domain : predicate[member]]
    BY SMT

THEOREM LazyConjunctionPreservesBooleanValue ==
    \A left, right \in BOOLEAN :
        (IF left THEN right ELSE FALSE) <=> (left /\ right)
    BY SMT

ConditionalEdges(selector, yes, no) ==
    {edge \in LabeledEdges :
        IF selector[edge[1]] THEN edge \in yes ELSE edge \in no}

THEOREM ConditionalEdgePreservation ==
    \A sourceSelector, renderedSelector \in [States -> BOOLEAN] :
        \A sourceYes, sourceNo, renderedYes, renderedNo \in SUBSET LabeledEdges :
            ((\A state \in States : sourceSelector[state] = renderedSelector[state])
             /\ sourceYes = renderedYes /\ sourceNo = renderedNo)
            => ConditionalEdges(sourceSelector, sourceYes, sourceNo)
               = ConditionalEdges(renderedSelector, renderedYes, renderedNo)
    BY SMT DEF ConditionalEdges, LabeledEdges, States

THEOREM ConditionalEnabledness ==
    \A selector \in [States -> BOOLEAN] :
        \A yes, no \in SUBSET LabeledEdges :
            \A state \in States, action \in ActionLabels :
                EnabledIn(ConditionalEdges(selector, yes, no), state, action)
                <=> (IF selector[state] THEN EnabledIn(yes, state, action)
                     ELSE EnabledIn(no, state, action))
    BY SMT DEF ConditionalEdges, EnabledIn, LabeledEdges, States

ApplyDelta(s, keys, delta) ==
    [key \in Vars |-> IF key \in keys THEN delta[key] ELSE s[key]]

RenderedDelta(s, t, keys, delta) ==
    /\ \A key \in keys : t[key] = delta[key]
    /\ \A key \in Vars \ keys : t[key] = s[key]

THEOREM CompleteDeltaUpdate ==
    \A keys \in SUBSET Vars :
        \A s, t \in States :
            \A delta \in [keys -> Values] :
                (t = ApplyDelta(s, keys, delta)) <=> RenderedDelta(s, t, keys, delta)
    BY SMT DEF ApplyDelta, RenderedDelta, States

EnumeratedInitialStates(prior, key, candidates) ==
    {[prior EXCEPT ![key] = candidates[index]] : index \in 1..Len(candidates)}
MembershipInitialStates(prior, key, domain) ==
    {state \in States :
        /\ state[key] \in domain
        /\ \A variable \in Vars \ {key} : state[variable] = prior[variable]}

THEOREM InitialMembershipMatchesEnumeration ==
    \A key \in Vars, prior \in States :
        \A candidates \in Seq(Values), domain \in SUBSET Values :
            SequenceMembers(candidates) = domain
            => EnumeratedInitialStates(prior, key, candidates)
               = MembershipInitialStates(prior, key, domain)
    BY SMT DEF EnumeratedInitialStates,
        MembershipInitialStates, SequenceMembers, States

EqualityInitialStates(prior, key, value) ==
    {state \in States :
        /\ state[key] = value
        /\ \A variable \in Vars \ {key} : state[variable] = prior[variable]}

THEOREM InitialEqualityMatchesSingletonEnumeration ==
    \A key \in Vars, prior \in States, value \in Values :
        EnumeratedInitialStates(prior, key, <<value>>)
        = EqualityInitialStates(prior, key, value)
    BY InitialMembershipMatchesEnumeration,
        SMT DEF EnumeratedInitialStates, MembershipInitialStates,
            EqualityInitialStates, SequenceMembers, States

ExtendEnumeratedInitialStates(priorStates, key, candidates) ==
    UNION {EnumeratedInitialStates(prior, key, candidates[prior]) : prior \in priorStates}
ExtendMembershipInitialStates(priorStates, key, domains) ==
    UNION {MembershipInitialStates(prior, key, domains[prior]) : prior \in priorStates}

THEOREM DependentDeterministicInitializationComposes ==
    \A key \in Vars, priorStates \in SUBSET States :
        \A valueByPrior \in [States -> Values] :
            ExtendEnumeratedInitialStates(
                priorStates, key,
                [prior \in States |-> <<valueByPrior[prior]>>])
            = UNION {EqualityInitialStates(prior, key, valueByPrior[prior])
                : prior \in priorStates}
    BY InitialEqualityMatchesSingletonEnumeration,
        SMT DEF ExtendEnumeratedInitialStates

THEOREM InitialMembershipComposesAcrossPriorChoices ==
    \A key \in Vars, priorStates \in SUBSET States :
        \A candidates \in [States -> Seq(Values)] :
            \A domains \in [States -> SUBSET Values] :
                (\A prior \in priorStates :
                    SequenceMembers(candidates[prior]) = domains[prior])
                => ExtendEnumeratedInitialStates(priorStates, key, candidates)
                   = ExtendMembershipInitialStates(priorStates, key, domains)
    BY InitialMembershipMatchesEnumeration,
        SMT DEF ExtendEnumeratedInitialStates, ExtendMembershipInitialStates

InitializationPlans ==
    [key: Vars, candidates: [States -> Seq(Values)], domains: [States -> SUBSET Values]]
InitializationPlanAgrees(plan) ==
    \A prior \in States :
        SequenceMembers(plan.candidates[prior]) = plan.domains[prior]
EnumeratedInitialHistory(start, plans, history) ==
    /\ history[0] = start
    /\ \A index \in 1..Len(plans) :
        history[index] = ExtendEnumeratedInitialStates(
            history[index - 1], plans[index].key, plans[index].candidates)
MembershipInitialHistory(start, plans, history) ==
    /\ history[0] = start
    /\ \A index \in 1..Len(plans) :
        history[index] = ExtendMembershipInitialStates(
            history[index - 1], plans[index].key, plans[index].domains)

THEOREM OrderedInitialHistoriesAgree ==
    ASSUME NEW start \in SUBSET States,
           NEW plans \in Seq(InitializationPlans),
           NEW enumerated \in [0..Len(plans) -> SUBSET States],
           NEW membership \in [0..Len(plans) -> SUBSET States],
           \A index \in 1..Len(plans) : InitializationPlanAgrees(plans[index]),
           EnumeratedInitialHistory(start, plans, enumerated),
           MembershipInitialHistory(start, plans, membership)
    PROVE \A index \in 0..Len(plans) : enumerated[index] = membership[index]
    PROOF
    <1>. DEFINE P(index) ==
        index \in 0..Len(plans) => enumerated[index] = membership[index]
    <1>1. P(0)
        BY SMT DEF P, EnumeratedInitialHistory, MembershipInitialHistory
    <1>2. ASSUME NEW index \in Nat, P(index)
          PROVE P(index + 1)
        <2>. SUFFICES ASSUME index + 1 \in 0..Len(plans)
                     PROVE enumerated[index + 1] = membership[index + 1]
            BY SMT DEF P
        <2>1. index \in 0..Len(plans)
            BY P(index), SMT DEF P
        <2>2. enumerated[index] = membership[index]
            BY <2>1, P(index), SMT DEF P
        <2>3. plans[index + 1] \in InitializationPlans
            BY LenProperties, SMT
        <2>4. InitializationPlanAgrees(plans[index + 1])
            BY SMT
        <2>5. enumerated[index + 1] = ExtendEnumeratedInitialStates(
                enumerated[index], plans[index + 1].key,
                plans[index + 1].candidates)
            BY SMT DEF EnumeratedInitialHistory
        <2>6. membership[index + 1] = ExtendMembershipInitialStates(
                membership[index], plans[index + 1].key,
                plans[index + 1].domains)
            BY SMT DEF MembershipInitialHistory
        <2>. QED
            BY <2>2, <2>3, <2>4, <2>5, <2>6,
                InitialMembershipComposesAcrossPriorChoices,
                SMT DEF InitializationPlanAgrees, InitializationPlans
    <1>3. \A index \in Nat : P(index)
        BY <1>1, <1>2, NatInduction
    <1>. QED
        BY <1>3, SMT DEF P

ValidInitializationPlans(plans) ==
    \A index \in 1..Len(plans) : InitializationPlanAgrees(plans[index])
InitialHistoriesExist(start, plans) ==
    \E history \in [0..Len(plans) -> SUBSET States] :
        EnumeratedInitialHistory(start, plans, history)
        /\ MembershipInitialHistory(start, plans, history)
ExtendInitialHistory(history, length, nextStates) ==
    [index \in 0..(length + 1) |->
        IF index = length + 1 THEN nextStates ELSE history[index]]

THEOREM OrderedInitialHistoriesExist ==
    ASSUME NEW start \in SUBSET States
    PROVE \A plans \in Seq(InitializationPlans) :
        ValidInitializationPlans(plans) => InitialHistoriesExist(start, plans)
    PROOF
    <1>. DEFINE P(plans) ==
        ValidInitializationPlans(plans) => InitialHistoriesExist(start, plans)
    <1>1. P(<<>>)
        <2>. DEFINE empty == [index \in 0..0 |-> start]
        <2>1. empty \in [0..Len(<<>>) -> SUBSET States]
            BY SMT DEF empty
        <2>2. EnumeratedInitialHistory(start, <<>>, empty)
            BY SMT DEF EnumeratedInitialHistory, empty
        <2>3. MembershipInitialHistory(start, <<>>, empty)
            BY SMT DEF MembershipInitialHistory, empty
        <2>. QED
            BY <2>1, <2>2, <2>3, SMT DEF P, InitialHistoriesExist
    <1>2. ASSUME NEW prior \in Seq(InitializationPlans),
                  NEW plan \in InitializationPlans,
                  P(prior)
          PROVE P(Append(prior, plan))
        <2>. SUFFICES ASSUME ValidInitializationPlans(Append(prior, plan))
                     PROVE InitialHistoriesExist(start, Append(prior, plan))
            BY SMT DEF P
        <2>1. ValidInitializationPlans(prior)
            BY AppendProperties, SMT DEF ValidInitializationPlans
        <2>2. InitializationPlanAgrees(plan)
            BY AppendProperties, SMT DEF ValidInitializationPlans
        <2>3. PICK history \in [0..Len(prior) -> SUBSET States] :
                    EnumeratedInitialHistory(start, prior, history)
                    /\ MembershipInitialHistory(start, prior, history)
            BY P(prior), <2>1, SMT DEF P, InitialHistoriesExist
        <2>. DEFINE nextStates == ExtendEnumeratedInitialStates(
            history[Len(prior)], plan.key, plan.candidates)
        <2>4. nextStates = ExtendMembershipInitialStates(
                    history[Len(prior)], plan.key, plan.domains)
            BY <2>2, <2>3, InitialMembershipComposesAcrossPriorChoices,
                SMT DEF nextStates, InitializationPlanAgrees, InitializationPlans
        <2>5. nextStates \in SUBSET States
            BY <2>4, SMT DEF ExtendMembershipInitialStates,
                MembershipInitialStates, nextStates
        <2>6. ExtendInitialHistory(history, Len(prior), nextStates)
            \in [0..Len(Append(prior, plan)) -> SUBSET States]
            BY <2>3, <2>5, AppendProperties, SMT DEF ExtendInitialHistory
        <2>7. /\ EnumeratedInitialHistory(start, Append(prior, plan),
                        ExtendInitialHistory(history, Len(prior), nextStates))
              /\ MembershipInitialHistory(start, Append(prior, plan),
                        ExtendInitialHistory(history, Len(prior), nextStates))
            <3>1. \A index \in 0..Len(prior) :
                    ExtendInitialHistory(history, Len(prior), nextStates)[index]
                    = history[index]
                BY SMT DEF ExtendInitialHistory
            <3>2. ExtendInitialHistory(history, Len(prior), nextStates)
                    [Len(prior) + 1] = nextStates
                BY SMT DEF ExtendInitialHistory
            <3>3. \A index \in 1..Len(prior) :
                    Append(prior, plan)[index] = prior[index]
                BY AppendProperties, SMT
            <3>4. Append(prior, plan)[Len(prior) + 1] = plan
                BY AppendProperties, SMT
            <3>5. EnumeratedInitialHistory(start, Append(prior, plan),
                    ExtendInitialHistory(history, Len(prior), nextStates))
                BY <2>3, <3>1, <3>2, <3>3, <3>4,
                    AppendProperties, SMT DEF EnumeratedInitialHistory
            <3>6. MembershipInitialHistory(start, Append(prior, plan),
                    ExtendInitialHistory(history, Len(prior), nextStates))
                <4>1. ExtendInitialHistory(history, Len(prior), nextStates)[0]
                        = start
                    BY <2>3, <3>1, SMT DEF MembershipInitialHistory
                <4>2. \A index \in 1..Len(prior) :
                        ExtendInitialHistory(history, Len(prior), nextStates)[index]
                        = ExtendMembershipInitialStates(
                            ExtendInitialHistory(history, Len(prior), nextStates)[index - 1],
                            Append(prior, plan)[index].key,
                            Append(prior, plan)[index].domains)
                    BY <2>3, <3>1, <3>3, SMT
                        DEF MembershipInitialHistory
                <4>3. ExtendInitialHistory(history, Len(prior), nextStates)
                        [Len(prior) + 1]
                        = ExtendMembershipInitialStates(
                            ExtendInitialHistory(history, Len(prior), nextStates)[Len(prior)],
                            Append(prior, plan)[Len(prior) + 1].key,
                            Append(prior, plan)[Len(prior) + 1].domains)
                    BY <2>4, <3>1, <3>2, <3>4, SMT
                <4>. QED
                    BY <4>1, <4>2, <4>3, AppendProperties, SMT
                        DEF MembershipInitialHistory
            <3>. QED
                BY <3>5, <3>6
        <2>. QED
            BY <2>6, <2>7 DEF InitialHistoriesExist
    <1>3. \A plans \in Seq(InitializationPlans) : P(plans)
        BY <1>1, <1>2, SequencesInductionAppend
    <1>. QED
        BY <1>3 DEF P

DependentSourceInit ==
    /\ dependentPC = "finish"
    /\ ((dependentSeed = 0 /\ dependentChoice = 0)
        \/ (dependentSeed = 1 /\ dependentChoice \in {0, 1}))

THEOREM EmittedDependentInitializationMatchesSource ==
    DependentInit!Init <=> DependentSourceInit
    BY SMT DEF DependentInit!Init, DependentSourceInit

THEOREM EmittedDependentInitializationHasExactlyThreeStates ==
    DependentInit!Init <=>
        <<dependentPC, dependentSeed, dependentChoice>> \in
            {<<"finish", 0, 0>>, <<"finish", 1, 0>>, <<"finish", 1, 1>>}
    BY EmittedDependentInitializationMatchesSource,
        SMT DEF DependentSourceInit

Instructions == [target: Vars, rhs: [States -> Values]]
AdvanceSource(current, instruction) ==
    [current EXCEPT ![instruction.target] = instruction.rhs[current]]
AdvanceSchedule(original, keys, values, instruction) ==
    LET current == ApplyDelta(original, keys, values)
        updated == instruction.rhs[current]
    IN  ApplyDelta(original, keys \cup {instruction.target},
            [values EXCEPT ![instruction.target] = updated])

THEOREM EmptySchedule ==
    \A original \in States : ApplyDelta(original, {}, original) = original
    BY SMT DEF ApplyDelta, States

THEOREM OrderedScheduleStep ==
    \A original, values \in States :
        \A keys \in SUBSET Vars :
            \A instruction \in Instructions :
                AdvanceSource(ApplyDelta(original, keys, values), instruction)
                = AdvanceSchedule(original, keys, values, instruction)
    BY SMT DEF AdvanceSource, AdvanceSchedule, ApplyDelta, Instructions, States

ScheduledRecords == [keys: SUBSET Vars, values: States]
AdvanceScheduleRecord(original, prior, instruction) ==
    LET current == ApplyDelta(original, prior.keys, prior.values)
    IN [keys |-> prior.keys \cup {instruction.target},
        values |-> [prior.values EXCEPT ![instruction.target] = instruction.rhs[current]]]

SourceHistory(original, steps, history) ==
    /\ history[0] = original
    /\ \A index \in 1..Len(steps) :
        history[index] = AdvanceSource(history[index - 1], steps[index])

ScheduledHistory(original, steps, history) ==
    /\ history[0] = [keys |-> {}, values |-> original]
    /\ \A index \in 1..Len(steps) :
        history[index] = AdvanceScheduleRecord(original, history[index - 1], steps[index])

THEOREM OrderedHistoryStep ==
    \A original \in States :
        \A prior \in ScheduledRecords :
            \A instruction \in Instructions :
                AdvanceSource(ApplyDelta(original, prior.keys, prior.values), instruction)
                = ApplyDelta(original,
                    AdvanceScheduleRecord(original, prior, instruction).keys,
                    AdvanceScheduleRecord(original, prior, instruction).values)
    BY OrderedScheduleStep, SMT DEF AdvanceScheduleRecord, AdvanceSchedule,
        ScheduledRecords, Instructions, States

HistoryAgrees(original, source, scheduled, index) ==
    source[index] = ApplyDelta(original, scheduled[index].keys, scheduled[index].values)

THEOREM OrderedHistoriesAgree ==
    ASSUME NEW original \in States,
           NEW steps \in Seq(Instructions),
           NEW source \in [0..Len(steps) -> States],
           NEW scheduled \in [0..Len(steps) -> ScheduledRecords],
           SourceHistory(original, steps, source),
           ScheduledHistory(original, steps, scheduled)
    PROVE  \A index \in 0..Len(steps) :
               HistoryAgrees(original, source, scheduled, index)
    PROOF
    <1>. DEFINE P(index) ==
        index \in 0..Len(steps) => HistoryAgrees(original, source, scheduled, index)
    <1>1. P(0)
        BY EmptySchedule, SMT DEF P, HistoryAgrees, SourceHistory, ScheduledHistory
    <1>2. ASSUME NEW index \in Nat, P(index)
          PROVE P(index + 1)
        <2>. SUFFICES ASSUME index + 1 \in 0..Len(steps)
                     PROVE HistoryAgrees(original, source, scheduled, index + 1)
            BY SMT DEF P
        <2>1. index \in 0..Len(steps)
            BY P(index), SMT DEF P
        <2>2. steps[index + 1] \in Instructions
            BY LenProperties, SMT
        <2>3. scheduled[index] \in ScheduledRecords
            BY <2>1, SMT
        <2>4. HistoryAgrees(original, source, scheduled, index)
            BY <2>1, P(index), SMT DEF P
        <2>5. source[index + 1] = AdvanceSource(source[index], steps[index + 1])
            BY SMT DEF SourceHistory
        <2>6. scheduled[index + 1] =
                 AdvanceScheduleRecord(original, scheduled[index], steps[index + 1])
            BY SMT DEF ScheduledHistory
        <2>. QED
            BY <2>2, <2>3, <2>4, <2>5, <2>6, OrderedHistoryStep,
                SMT DEF HistoryAgrees
    <1>3. \A index \in Nat : P(index)
        BY <1>1, <1>2, NatInduction
    <1>4. QED
        BY <1>3, SMT DEF P

THEOREM SourceHistoryIsUnique ==
    ASSUME NEW original \in States,
           NEW steps \in Seq(Instructions),
           NEW firstHistory \in [0..Len(steps) -> States],
           NEW secondHistory \in [0..Len(steps) -> States],
           SourceHistory(original, steps, firstHistory),
           SourceHistory(original, steps, secondHistory)
    PROVE firstHistory = secondHistory
    PROOF
    <1>. DEFINE P(index) ==
        index \in 0..Len(steps) => firstHistory[index] = secondHistory[index]
    <1>1. P(0)
        BY SMT DEF P, SourceHistory
    <1>2. ASSUME NEW index \in Nat, P(index)
          PROVE P(index + 1)
        <2>. SUFFICES ASSUME index + 1 \in 0..Len(steps)
                     PROVE firstHistory[index + 1] = secondHistory[index + 1]
            BY SMT DEF P
        <2>1. index \in 0..Len(steps)
            BY P(index), SMT DEF P
        <2>2. firstHistory[index] = secondHistory[index]
            BY <2>1, P(index), SMT DEF P
        <2>3. firstHistory[index + 1] =
                AdvanceSource(firstHistory[index], steps[index + 1])
            BY SMT DEF SourceHistory
        <2>4. secondHistory[index + 1] =
                AdvanceSource(secondHistory[index], steps[index + 1])
            BY SMT DEF SourceHistory
        <2>. QED
            BY <2>2, <2>3, <2>4, SMT
    <1>3. \A index \in Nat : P(index)
        BY <1>1, <1>2, NatInduction
    <1>. QED
        BY <1>3, SMT DEF P

ExtendSourceHistory(history, length, instruction) ==
    [index \in 0..(length + 1) |->
        IF index = length + 1
        THEN AdvanceSource(history[length], instruction)
        ELSE history[index]]

ExtendScheduledHistory(original, history, length, instruction) ==
    [index \in 0..(length + 1) |->
        IF index = length + 1
        THEN AdvanceScheduleRecord(original, history[length], instruction)
        ELSE history[index]]

HistoriesExist(original, steps) ==
    \E source \in [0..Len(steps) -> States] :
        \E scheduled \in [0..Len(steps) -> ScheduledRecords] :
            SourceHistory(original, steps, source)
            /\ ScheduledHistory(original, steps, scheduled)

THEOREM OrderedHistoriesExist ==
    ASSUME NEW original \in States
    PROVE \A steps \in Seq(Instructions) : HistoriesExist(original, steps)
    PROOF
    <1>1. HistoriesExist(original, <<>>)
        <2>. DEFINE emptySource == [index \in 0..0 |-> original]
                    emptyScheduled ==
                        [index \in 0..0 |-> [keys |-> {}, values |-> original]]
        <2>1. emptySource \in [0..Len(<<>>) -> States]
            BY SMT DEF emptySource
        <2>2. emptyScheduled \in [0..Len(<<>>) -> ScheduledRecords]
            BY SMT DEF emptyScheduled, ScheduledRecords
        <2>3. SourceHistory(original, <<>>, emptySource)
            BY SMT DEF SourceHistory, emptySource
        <2>4. ScheduledHistory(original, <<>>, emptyScheduled)
            BY SMT DEF ScheduledHistory, emptyScheduled
        <2>. QED
            BY <2>1, <2>2, <2>3, <2>4, SMT DEF HistoriesExist
    <1>2. ASSUME NEW prior \in Seq(Instructions),
                  NEW instruction \in Instructions,
                  HistoriesExist(original, prior)
          PROVE HistoriesExist(original, Append(prior, instruction))
        <2>1. PICK source \in [0..Len(prior) -> States],
                    scheduled \in [0..Len(prior) -> ScheduledRecords] :
                    SourceHistory(original, prior, source)
                    /\ ScheduledHistory(original, prior, scheduled)
            BY HistoriesExist(original, prior) DEF HistoriesExist
        <2>2. AdvanceSource(source[Len(prior)], instruction) \in States
            BY <2>1, SMT DEF AdvanceSource, Instructions, States
        <2>3. AdvanceScheduleRecord(original, scheduled[Len(prior)], instruction)
            \in ScheduledRecords
            BY <2>1, SMT DEF AdvanceScheduleRecord, ScheduledRecords,
                Instructions, ApplyDelta, States
        <2>4. Len(Append(prior, instruction)) = Len(prior) + 1
            BY AppendProperties
        <2>5. \A index \in 0..Len(prior) : source[index] \in States
            BY <2>1, SMT
        <2>6. \A index \in 0..Len(prior) : scheduled[index] \in ScheduledRecords
            BY <2>1, SMT
        <2>7. ExtendSourceHistory(source, Len(prior), instruction)
            \in [0..Len(Append(prior, instruction)) -> States]
            BY <2>2, <2>4, <2>5, SMT DEF ExtendSourceHistory
        <2>8. ExtendScheduledHistory(original, scheduled, Len(prior), instruction)
            \in [0..Len(Append(prior, instruction)) -> ScheduledRecords]
            BY <2>3, <2>4, <2>6, SMT DEF ExtendScheduledHistory
        <2>9. SourceHistory(original, Append(prior, instruction),
                 ExtendSourceHistory(source, Len(prior), instruction))
            <3>1. \A index \in 0..Len(prior) :
                    ExtendSourceHistory(source, Len(prior), instruction)[index]
                    = source[index]
                BY SMT DEF ExtendSourceHistory
            <3>2. ExtendSourceHistory(source, Len(prior), instruction)
                    [Len(prior) + 1] = AdvanceSource(source[Len(prior)], instruction)
                BY SMT DEF ExtendSourceHistory
            <3>3. \A index \in 1..Len(prior) :
                    Append(prior, instruction)[index] = prior[index]
                BY AppendProperties, SMT
            <3>4. Append(prior, instruction)[Len(prior) + 1] = instruction
                BY AppendProperties, SMT
            <3>5. ExtendSourceHistory(source, Len(prior), instruction)[0]
                    = original
                BY <2>1, <3>1, SMT DEF SourceHistory
            <3>6. \A index \in 1..Len(prior) :
                    ExtendSourceHistory(source, Len(prior), instruction)[index]
                    = AdvanceSource(
                        ExtendSourceHistory(source, Len(prior), instruction)[index - 1],
                        Append(prior, instruction)[index])
                BY <2>1, <3>1, <3>3, SMT DEF SourceHistory
            <3>7. ExtendSourceHistory(source, Len(prior), instruction)
                    [Len(prior) + 1]
                    = AdvanceSource(
                        ExtendSourceHistory(source, Len(prior), instruction)[Len(prior)],
                        Append(prior, instruction)[Len(prior) + 1])
                BY <3>1, <3>2, <3>4, SMT
            <3>. QED
                BY <2>4, <3>5, <3>6, <3>7, SMT DEF SourceHistory
        <2>10. ScheduledHistory(original, Append(prior, instruction),
                 ExtendScheduledHistory(original, scheduled, Len(prior), instruction))
            <3>1. \A index \in 0..Len(prior) :
                    ExtendScheduledHistory(original, scheduled, Len(prior), instruction)[index]
                    = scheduled[index]
                BY SMT DEF ExtendScheduledHistory
            <3>2. ExtendScheduledHistory(original, scheduled, Len(prior), instruction)
                    [Len(prior) + 1]
                    = AdvanceScheduleRecord(original, scheduled[Len(prior)], instruction)
                BY SMT DEF ExtendScheduledHistory
            <3>. QED
                BY <2>1, <3>1, <3>2, AppendProperties,
                    SMT DEF ScheduledHistory
        <2>. QED
            BY <2>7, <2>8, <2>9, <2>10 DEF HistoriesExist
    <1>3. QED
        BY <1>1, <1>2, SequencesInductionAppend

THEOREM OrderedDoPreservation ==
    ASSUME NEW original \in States
    PROVE \A steps \in Seq(Instructions) :
        \E source \in [0..Len(steps) -> States] :
            \E scheduled \in [0..Len(steps) -> ScheduledRecords] :
                /\ SourceHistory(original, steps, source)
                /\ ScheduledHistory(original, steps, scheduled)
                /\ \A index \in 0..Len(steps) :
                    HistoryAgrees(original, source, scheduled, index)
    BY OrderedHistoriesExist, OrderedHistoriesAgree,
        SMT DEF HistoriesExist

SourceDoStep(original, steps, target) ==
    \E history \in [0..Len(steps) -> States] :
        SourceHistory(original, steps, history)
        /\ history[Len(steps)] = target

ScheduledDoStep(original, steps, target) ==
    \E history \in [0..Len(steps) -> ScheduledRecords] :
        ScheduledHistory(original, steps, history)
        /\ ApplyDelta(original, history[Len(steps)].keys,
            history[Len(steps)].values) = target

THEOREM OrderedDoTransitionEquivalence ==
    ASSUME NEW original \in States,
           NEW target \in States,
           NEW steps \in Seq(Instructions)
    PROVE SourceDoStep(original, steps, target)
          <=> ScheduledDoStep(original, steps, target)
    BY OrderedHistoriesExist, OrderedHistoriesAgree,
        SMT DEF SourceDoStep, ScheduledDoStep, HistoriesExist, HistoryAgrees

GuardPlans(steps) == [0..Len(steps) -> [States -> BOOLEAN]]

SourceGuardedDoStep(original, steps, guards, target) ==
    \E history \in [0..Len(steps) -> States] :
        /\ SourceHistory(original, steps, history)
        /\ \A index \in 0..Len(steps) : guards[index][history[index]]
        /\ history[Len(steps)] = target

ScheduledGuardedDoStep(original, steps, guards, target) ==
    \E history \in [0..Len(steps) -> ScheduledRecords] :
        /\ ScheduledHistory(original, steps, history)
        /\ \A index \in 0..Len(steps) :
            guards[index][ApplyDelta(original, history[index].keys,
                history[index].values)]
        /\ ApplyDelta(original, history[Len(steps)].keys,
            history[Len(steps)].values) = target

THEOREM OrderedGuardedHistoriesAgree ==
    ASSUME NEW original \in States,
           NEW steps \in Seq(Instructions),
           NEW guards \in GuardPlans(steps),
           NEW source \in [0..Len(steps) -> States],
           NEW scheduled \in [0..Len(steps) -> ScheduledRecords],
           SourceHistory(original, steps, source),
           ScheduledHistory(original, steps, scheduled)
    PROVE (\A index \in 0..Len(steps) : guards[index][source[index]])
          <=> (\A index \in 0..Len(steps) :
                guards[index][ApplyDelta(original, scheduled[index].keys,
                    scheduled[index].values)])
    BY OrderedHistoriesAgree, SMT DEF HistoryAgrees

THEOREM OrderedGuardedDoTransitionEquivalence ==
    ASSUME NEW original \in States,
           NEW target \in States,
           NEW steps \in Seq(Instructions),
           NEW guards \in GuardPlans(steps)
    PROVE SourceGuardedDoStep(original, steps, guards, target)
          <=> ScheduledGuardedDoStep(original, steps, guards, target)
    PROOF
    <1>1. HistoriesExist(original, steps)
        BY OrderedHistoriesExist
    <1>2. SourceGuardedDoStep(original, steps, guards, target)
           => ScheduledGuardedDoStep(original, steps, guards, target)
        <2>. SUFFICES ASSUME SourceGuardedDoStep(original, steps, guards, target)
                     PROVE ScheduledGuardedDoStep(original, steps, guards, target)
            BY SMT
        <2>1. PICK source \in [0..Len(steps) -> States] :
                    /\ SourceHistory(original, steps, source)
                    /\ \A index \in 0..Len(steps) : guards[index][source[index]]
                    /\ source[Len(steps)] = target
            BY DEF SourceGuardedDoStep
        <2>2. PICK existingSource \in [0..Len(steps) -> States],
                    scheduled \in [0..Len(steps) -> ScheduledRecords] :
                    SourceHistory(original, steps, existingSource)
                    /\ ScheduledHistory(original, steps, scheduled)
            BY <1>1 DEF HistoriesExist
        <2>3. HistoryAgrees(original, source, scheduled, Len(steps))
            BY <2>1, <2>2, OrderedHistoriesAgree, SMT
        <2>4. \A index \in 0..Len(steps) :
                    guards[index][ApplyDelta(original, scheduled[index].keys,
                        scheduled[index].values)]
            BY <2>1, <2>2, OrderedGuardedHistoriesAgree, SMT
        <2>5. ApplyDelta(original, scheduled[Len(steps)].keys,
                    scheduled[Len(steps)].values) = target
            BY <2>1, <2>3, SMT DEF HistoryAgrees
        <2>. QED
            BY <2>2, <2>4, <2>5, SMT DEF ScheduledGuardedDoStep
    <1>3. ScheduledGuardedDoStep(original, steps, guards, target)
           => SourceGuardedDoStep(original, steps, guards, target)
        <2>. SUFFICES ASSUME ScheduledGuardedDoStep(original, steps, guards, target)
                     PROVE SourceGuardedDoStep(original, steps, guards, target)
            BY SMT
        <2>1. PICK scheduled \in [0..Len(steps) -> ScheduledRecords] :
                    /\ ScheduledHistory(original, steps, scheduled)
                    /\ \A index \in 0..Len(steps) :
                        guards[index][ApplyDelta(original, scheduled[index].keys,
                            scheduled[index].values)]
                    /\ ApplyDelta(original, scheduled[Len(steps)].keys,
                        scheduled[Len(steps)].values) = target
            BY DEF ScheduledGuardedDoStep
        <2>2. PICK source \in [0..Len(steps) -> States],
                    existingScheduled \in [0..Len(steps) -> ScheduledRecords] :
                    SourceHistory(original, steps, source)
                    /\ ScheduledHistory(original, steps, existingScheduled)
            BY <1>1 DEF HistoriesExist
        <2>3. HistoryAgrees(original, source, scheduled, Len(steps))
            BY <2>1, <2>2, OrderedHistoriesAgree, SMT
        <2>4. \A index \in 0..Len(steps) : guards[index][source[index]]
            BY <2>1, <2>2, OrderedGuardedHistoriesAgree, SMT
        <2>5. source[Len(steps)] = target
            BY <2>1, <2>3, SMT DEF HistoryAgrees
        <2>. QED
            BY <2>2, <2>4, <2>5, SMT DEF SourceGuardedDoStep
    <1>. QED
        BY <1>2, <1>3, SMT

ConditionalSteps(prefix, branch, suffix) == (prefix \o branch) \o suffix
AlwaysGuard == [state \in States |-> TRUE]
OppositeGuard(predicate) == [state \in States |-> ~predicate[state]]
BranchGuardPlan(steps, position, predicate) ==
    [index \in 0..Len(steps) |->
        IF index = position THEN predicate ELSE AlwaysGuard]

THEOREM ConditionalGuardReadsAfterPrefix ==
    ASSUME NEW prefix \in Seq(Instructions),
           NEW branch \in Seq(Instructions),
           NEW suffix \in Seq(Instructions),
           NEW predicate \in [States -> BOOLEAN],
           NEW history \in [0..Len(ConditionalSteps(prefix, branch, suffix)) -> States]
    PROVE (\A index \in 0..Len(ConditionalSteps(prefix, branch, suffix)) :
            BranchGuardPlan(ConditionalSteps(prefix, branch, suffix),
                Len(prefix), predicate)[index][history[index]])
          <=> predicate[history[Len(prefix)]]
    BY ConcatProperties, SMT DEF BranchGuardPlan, AlwaysGuard,
        ConditionalSteps, States

THEOREM ConditionalPrefixIsSourceHistory ==
    ASSUME NEW original \in States,
           NEW prefix \in Seq(Instructions),
           NEW branch \in Seq(Instructions),
           NEW suffix \in Seq(Instructions),
           NEW history \in [0..Len(ConditionalSteps(prefix, branch, suffix)) -> States],
           SourceHistory(original, ConditionalSteps(prefix, branch, suffix), history)
    PROVE SourceHistory(original, prefix,
            [index \in 0..Len(prefix) |-> history[index]])
    BY ConcatProperties, SMT DEF SourceHistory, ConditionalSteps,
        Instructions, States

THEOREM ConditionalGuardUsesPrefixResult ==
    ASSUME NEW original \in States,
           NEW prefix \in Seq(Instructions),
           NEW branch \in Seq(Instructions),
           NEW suffix \in Seq(Instructions),
           NEW predicate \in [States -> BOOLEAN],
           NEW history \in [0..Len(ConditionalSteps(prefix, branch, suffix)) -> States],
           NEW prefixHistory \in [0..Len(prefix) -> States],
           SourceHistory(original, ConditionalSteps(prefix, branch, suffix), history),
           SourceHistory(original, prefix, prefixHistory)
    PROVE (\A index \in 0..Len(ConditionalSteps(prefix, branch, suffix)) :
            BranchGuardPlan(ConditionalSteps(prefix, branch, suffix),
                Len(prefix), predicate)[index][history[index]])
          <=> predicate[prefixHistory[Len(prefix)]]
    PROOF
    <1>1. SourceHistory(original, prefix,
            [index \in 0..Len(prefix) |-> history[index]])
        BY ConditionalPrefixIsSourceHistory
    <1>2. Len(prefix) <= Len(ConditionalSteps(prefix, branch, suffix))
        BY ConcatProperties DEF ConditionalSteps
    <1>3. Len(prefix) \in Nat
          /\ Len(ConditionalSteps(prefix, branch, suffix)) \in Nat
        BY LenProperties, ConcatProperties DEF ConditionalSteps
    <1>4. 0..Len(prefix) \subseteq
            0..Len(ConditionalSteps(prefix, branch, suffix))
        BY <1>2, <1>3, SMT
    <1>5. \A index \in 0..Len(prefix) : history[index] \in States
        BY <1>4, SMT
    <1>6. [index \in 0..Len(prefix) |-> history[index]]
          \in [0..Len(prefix) -> States]
        BY <1>5, SMT
    <1>7. [index \in 0..Len(prefix) |-> history[index]] = prefixHistory
        BY <1>1, <1>6, SourceHistoryIsUnique
    <1>. QED
        BY <1>7, ConditionalGuardReadsAfterPrefix

SourceConditionalDoStep(original, prefix, yes, no, suffix, predicate, target) ==
    \/ SourceGuardedDoStep(original, ConditionalSteps(prefix, yes, suffix),
        BranchGuardPlan(ConditionalSteps(prefix, yes, suffix), Len(prefix), predicate), target)
    \/ SourceGuardedDoStep(original, ConditionalSteps(prefix, no, suffix),
        BranchGuardPlan(ConditionalSteps(prefix, no, suffix), Len(prefix),
            OppositeGuard(predicate)), target)

ScheduledConditionalDoStep(original, prefix, yes, no, suffix, predicate, target) ==
    \/ ScheduledGuardedDoStep(original, ConditionalSteps(prefix, yes, suffix),
        BranchGuardPlan(ConditionalSteps(prefix, yes, suffix), Len(prefix), predicate), target)
    \/ ScheduledGuardedDoStep(original, ConditionalSteps(prefix, no, suffix),
        BranchGuardPlan(ConditionalSteps(prefix, no, suffix), Len(prefix),
            OppositeGuard(predicate)), target)

THEOREM OrderedConditionalDoTransitionEquivalence ==
    ASSUME NEW original \in States,
           NEW target \in States,
           NEW prefix \in Seq(Instructions),
           NEW yes \in Seq(Instructions),
           NEW no \in Seq(Instructions),
           NEW suffix \in Seq(Instructions),
           NEW predicate \in [States -> BOOLEAN]
    PROVE SourceConditionalDoStep(original, prefix, yes, no, suffix, predicate, target)
          <=> ScheduledConditionalDoStep(original, prefix, yes, no, suffix, predicate, target)
    PROOF
    <1>1. ConditionalSteps(prefix, yes, suffix) \in Seq(Instructions)
          /\ ConditionalSteps(prefix, no, suffix) \in Seq(Instructions)
        BY ConcatProperties DEF ConditionalSteps
    <1>2. OppositeGuard(predicate) \in [States -> BOOLEAN]
        BY SMT DEF OppositeGuard, States
    <1>3. BranchGuardPlan(
            ConditionalSteps(prefix, yes, suffix), Len(prefix), predicate)
          \in GuardPlans(ConditionalSteps(prefix, yes, suffix))
          /\ BranchGuardPlan(
            ConditionalSteps(prefix, no, suffix), Len(prefix), OppositeGuard(predicate))
          \in GuardPlans(ConditionalSteps(prefix, no, suffix))
        BY <1>1, <1>2, SMT DEF BranchGuardPlan, AlwaysGuard, GuardPlans, States
    <1>. QED
        BY <1>1, <1>3, OrderedGuardedDoTransitionEquivalence
            DEF SourceConditionalDoStep, ScheduledConditionalDoStep

THEOREM OrderedConditionalDoEnabledness ==
    ASSUME NEW original \in States,
           NEW prefix \in Seq(Instructions),
           NEW yes \in Seq(Instructions),
           NEW no \in Seq(Instructions),
           NEW suffix \in Seq(Instructions),
           NEW predicate \in [States -> BOOLEAN]
    PROVE (\E target \in States :
            SourceConditionalDoStep(original, prefix, yes, no, suffix, predicate, target))
          <=> (\E target \in States :
            ScheduledConditionalDoStep(original, prefix, yes, no, suffix, predicate, target))
    BY OrderedConditionalDoTransitionEquivalence

SourceConditionalDoEdges(label, prefix, yes, no, suffix, predicate) ==
    {edge \in LabeledEdges :
        edge[2] = label /\
        SourceConditionalDoStep(edge[1], prefix, yes, no, suffix, predicate, edge[3])}
ScheduledConditionalDoEdges(label, prefix, yes, no, suffix, predicate) ==
    {edge \in LabeledEdges :
        edge[2] = label /\
        ScheduledConditionalDoStep(edge[1], prefix, yes, no, suffix, predicate, edge[3])}

THEOREM OrderedConditionalDoLabeledEdges ==
    ASSUME NEW label \in ActionLabels,
           NEW prefix \in Seq(Instructions),
           NEW yes \in Seq(Instructions),
           NEW no \in Seq(Instructions),
           NEW suffix \in Seq(Instructions),
           NEW predicate \in [States -> BOOLEAN]
    PROVE SourceConditionalDoEdges(label, prefix, yes, no, suffix, predicate)
          = ScheduledConditionalDoEdges(label, prefix, yes, no, suffix, predicate)
    BY OrderedConditionalDoTransitionEquivalence,
        SMT DEF SourceConditionalDoEdges, ScheduledConditionalDoEdges, LabeledEdges

THEOREM OrderedDoEnabledness ==
    ASSUME NEW original \in States,
           NEW steps \in Seq(Instructions)
    PROVE (\E target \in States : SourceDoStep(original, steps, target))
          <=> (\E target \in States : ScheduledDoStep(original, steps, target))
    BY OrderedDoTransitionEquivalence

SourceDoEdges(label, steps) ==
    {edge \in LabeledEdges :
        edge[2] = label /\ SourceDoStep(edge[1], steps, edge[3])}
ScheduledDoEdges(label, steps) ==
    {edge \in LabeledEdges :
        edge[2] = label /\ ScheduledDoStep(edge[1], steps, edge[3])}

THEOREM OrderedDoLabeledEdges ==
    ASSUME NEW label \in ActionLabels,
           NEW steps \in Seq(Instructions)
    PROVE SourceDoEdges(label, steps) = ScheduledDoEdges(label, steps)
    BY OrderedDoTransitionEquivalence,
        SMT DEF SourceDoEdges, ScheduledDoEdges, LabeledEdges

MergeCompatible(firstKeys, first, secondKeys, second) ==
    [key \in firstKeys \cup secondKeys |->
        IF key \in firstKeys THEN first[key] ELSE second[key]]

Compatible(firstKeys, first, secondKeys, second) ==
    \A key \in firstKeys \cap secondKeys : first[key] = second[key]

RenderedConjunction(s, t, firstKeys, first, secondKeys, second) ==
    /\ \A key \in firstKeys : t[key] = first[key]
    /\ \A key \in secondKeys : t[key] = second[key]
    /\ \A key \in Vars \ (firstKeys \cup secondKeys) : t[key] = s[key]

THEOREM CompatibleConjunction ==
    \A firstKeys, secondKeys \in SUBSET Vars :
        \A s, t \in States :
            \A first \in [firstKeys -> Values] :
                \A second \in [secondKeys -> Values] :
                    Compatible(firstKeys, first, secondKeys, second) =>
                        (t = ApplyDelta(s, firstKeys \cup secondKeys,
                            MergeCompatible(firstKeys, first, secondKeys, second)))
                        <=> RenderedConjunction(s, t, firstKeys, first, secondKeys, second)
    BY SMT DEF ApplyDelta, MergeCompatible, Compatible, RenderedConjunction, States

THEOREM ConflictingConjunctionHasNoSuccessor ==
    \A firstKeys, secondKeys \in SUBSET Vars :
        \A s, t \in States :
            \A first \in [firstKeys -> Values] :
                \A second \in [secondKeys -> Values] :
                    ~Compatible(firstKeys, first, secondKeys, second)
                    => ~RenderedConjunction(s, t, firstKeys, first, secondKeys, second)
    BY SMT DEF Compatible, RenderedConjunction, States

ExecutableConjunction(s, t, firstKeys, first, secondKeys, second) ==
    /\ Compatible(firstKeys, first, secondKeys, second)
    /\ t = ApplyDelta(s, firstKeys \cup secondKeys,
        MergeCompatible(firstKeys, first, secondKeys, second))

THEOREM ConjunctionSuccessorsAgree ==
    \A firstKeys, secondKeys \in SUBSET Vars :
        \A s, t \in States :
            \A first \in [firstKeys -> Values] :
                \A second \in [secondKeys -> Values] :
                    ExecutableConjunction(s, t, firstKeys, first, secondKeys, second)
                    <=> RenderedConjunction(s, t, firstKeys, first, secondKeys, second)
    BY CompatibleConjunction, ConflictingConjunctionHasNoSuccessor,
        SMT DEF ExecutableConjunction

THEOREM ConjunctionEnablednessAgree ==
    \A firstKeys, secondKeys \in SUBSET Vars :
        \A s \in States :
            \A first \in [firstKeys -> Values] :
                \A second \in [secondKeys -> Values] :
                    (\E t \in States :
                        ExecutableConjunction(s, t, firstKeys, first, secondKeys, second))
                    <=> (\E t \in States :
                        RenderedConjunction(s, t, firstKeys, first, secondKeys, second))
    BY ConjunctionSuccessorsAgree, SMT

THEOREM ConjunctionLabeledEdgesAgree ==
    \A firstKeys, secondKeys \in SUBSET Vars :
        \A first \in [States -> [firstKeys -> Values]],
           second \in [States -> [secondKeys -> Values]] :
            {edge \in LabeledEdges :
                ExecutableConjunction(edge[1], edge[3], firstKeys,
                    first[edge[1]], secondKeys, second[edge[1]])}
            = {edge \in LabeledEdges :
                RenderedConjunction(edge[1], edge[3], firstKeys,
                    first[edge[1]], secondKeys, second[edge[1]])}
    BY ConjunctionSuccessorsAgree, SMT DEF LabeledEdges, States

\* The generated Swift machine replaces one value in a complete state.
NativeStep(s, t, guard, value) ==
    /\ guard
    /\ t = [s EXCEPT ![Key] = value]

\* The rendered TLA+ action assigns the target and leaves every other
\* model variable unchanged.
RenderedStep(s, t, guard, value) ==
    /\ guard
    /\ t[Key] = value
    /\ \A other \in Vars \ {Key} : t[other] = s[other]

THEOREM ForwardUpdate ==
    \A s, t \in States, value \in Values, guard \in BOOLEAN :
        NativeStep(s, t, guard, value)
        => RenderedStep(s, t, guard, value)
    BY KeyIsVariable, SMT DEF NativeStep, RenderedStep, States

THEOREM ReverseUpdate ==
    \A s, t \in States, value \in Values, guard \in BOOLEAN :
        RenderedStep(s, t, guard, value)
        => NativeStep(s, t, guard, value)
    BY KeyIsVariable, SMT DEF NativeStep, RenderedStep, States

THEOREM CompleteStateUpdate ==
    \A s, t \in States, value \in Values, guard \in BOOLEAN :
        NativeStep(s, t, guard, value)
        <=> RenderedStep(s, t, guard, value)
    BY ForwardUpdate, ReverseUpdate

THEOREM EnabledUpdate ==
    \A s \in States, value \in Values, guard \in BOOLEAN :
        (\E t \in States : NativeStep(s, t, guard, value))
        <=> (\E t \in States : RenderedStep(s, t, guard, value))
    BY CompleteStateUpdate, SMT DEF NativeStep, RenderedStep, States

NativeParallelStep(s, t, guard, first, firstValue, second, secondValue) ==
    /\ guard
    /\ first # second
    /\ t = [s EXCEPT ![first] = firstValue, ![second] = secondValue]

RenderedParallelStep(s, t, guard, first, firstValue, second, secondValue) ==
    /\ guard
    /\ first # second
    /\ t[first] = firstValue
    /\ t[second] = secondValue
    /\ \A other \in Vars \ {first, second} : t[other] = s[other]

THEOREM ParallelUpdate ==
    \A s, t \in States, guard \in BOOLEAN,
       first, second \in Vars, firstValue, secondValue \in Values :
        NativeParallelStep(s, t, guard, first, firstValue, second, secondValue)
        <=> RenderedParallelStep(s, t, guard, first, firstValue, second, secondValue)
    BY SMT DEF NativeParallelStep, RenderedParallelStep, States

SourceOrderedCopy ==
    /\ first' = second
    /\ second' = second

SourceSequentialCopy ==
    LET before == [first |-> first, second |-> second]
        afterFirst == [before EXCEPT !.first = before.second]
        afterSecond == [afterFirst EXCEPT !.second = afterFirst.first]
    IN  /\ first' = afterSecond.first
        /\ second' = afterSecond.second

THEOREM OrderedCopySemantics ==
    SourceSequentialCopy <=> SourceOrderedCopy
    BY SMT DEF SourceSequentialCopy, SourceOrderedCopy

SourceInitialCopyState ==
    /\ first = 0
    /\ second = 1

THEOREM EmittedCopyInitialState ==
    Init <=> SourceInitialCopyState
    BY SMT DEF Init, SourceInitialCopyState

THEOREM EmittedCopyStep ==
    copy <=> SourceOrderedCopy
    BY SMT DEF copy, SourceOrderedCopy

THEOREM EmittedCopyNext ==
    Next <=> SourceOrderedCopy
    BY EmittedCopyStep DEF Next

THEOREM EmittedCopyPreservesSourceOrder ==
    Next <=> SourceSequentialCopy
    BY EmittedCopyNext, OrderedCopySemantics

WrongPreStepCopy ==
    /\ first' = second
    /\ second' = first

THEOREM PreStepSecondReadIsObservable ==
    ASSUME first = 0, second = 1, first' = 1, second' = 0
    PROVE WrongPreStepCopy /\ ~copy
    BY SMT DEF WrongPreStepCopy, copy

CopySourceState ==
    [key \in Vars |-> IF key = "first" THEN first ELSE second]
CopyTargetState ==
    [key \in Vars |-> IF key = "first" THEN first' ELSE second']
CopyInstructions ==
    <<[target |-> "first", rhs |-> [state \in States |-> state["second"]]],
      [target |-> "second", rhs |-> [state \in States |-> state["first"]]]>>
CopyIntermediateState ==
    [CopySourceState EXCEPT !["first"] = second]
CopyWitnessHistory ==
    [index \in 0..2 |->
        IF index = 0 THEN CopySourceState
        ELSE IF index = 1 THEN CopyIntermediateState
        ELSE [CopyIntermediateState EXCEPT !["second"] = CopyIntermediateState["first"]]]

THEOREM EmittedCopyMatchesOrderedInstructions ==
    ASSUME Vars = {"first", "second"},
           Values = Int,
           first \in Int,
           second \in Int,
           first' \in Int,
           second' \in Int
    PROVE copy <=> ScheduledDoStep(CopySourceState, CopyInstructions, CopyTargetState)
    PROOF
    <1>1. CopySourceState \in States /\ CopyTargetState \in States
        BY SMT DEF CopySourceState, CopyTargetState, States
    <1>2. CopyInstructions \in Seq(Instructions)
        BY <1>1, SMT DEF CopyInstructions, Instructions, States
    <1>3. CopyWitnessHistory \in [0..Len(CopyInstructions) -> States]
        BY <1>1, SMT DEF CopyWitnessHistory, CopyIntermediateState,
            CopyInstructions, States
    <1>4. SourceHistory(CopySourceState, CopyInstructions, CopyWitnessHistory)
        BY <1>1, <1>2, <1>3, SMT DEF SourceHistory, CopyWitnessHistory,
            CopyIntermediateState, CopyInstructions, CopySourceState,
            AdvanceSource, States
    <1>5. \A history \in [0..Len(CopyInstructions) -> States] :
            SourceHistory(CopySourceState, CopyInstructions, history)
            => history = CopyWitnessHistory
        BY <1>1, <1>2, <1>3, <1>4, SourceHistoryIsUnique
    <1>6. CopyWitnessHistory[Len(CopyInstructions)] = CopyTargetState
            <=> SourceOrderedCopy
        BY SMT DEF CopyWitnessHistory, CopyIntermediateState,
            CopyInstructions, CopySourceState, CopyTargetState,
            SourceOrderedCopy, States
    <1>7. SourceDoStep(CopySourceState, CopyInstructions, CopyTargetState)
            <=> SourceOrderedCopy
        BY <1>3, <1>4, <1>5, <1>6, SMT DEF SourceDoStep
    <1>. QED
        BY <1>1, <1>2, <1>7, EmittedCopyStep,
            OrderedDoTransitionEquivalence

GeneratedEmptyUpdates(state) ==
    [accepted |-> TRUE, written |-> {}, values |-> state]
GeneratedMerge(updates, key, value) ==
    IF updates.accepted
       /\ (key \notin updates.written \/ updates.values[key] = value)
    THEN [accepted |-> TRUE,
          written |-> updates.written \cup {key},
          values |-> [updates.values EXCEPT ![key] = value]]
    ELSE [accepted |-> FALSE,
          written |-> updates.written,
          values |-> updates.values]
GeneratedApply(state, updates) ==
    [key \in Vars |->
        IF key \in updates.written THEN updates.values[key] ELSE state[key]]
GeneratedTwoWrites(state, firstKey, firstValue, secondKey, secondValue) ==
    LET firstUpdate ==
            GeneratedMerge(GeneratedEmptyUpdates(state), firstKey, firstValue)
        secondUpdate ==
            GeneratedMerge(firstUpdate, secondKey, secondValue)
    IN [accepted |-> secondUpdate.accepted,
        target |-> GeneratedApply(state, secondUpdate)]

THEOREM GeneratedDisjointWritesPreserveCompleteState ==
    ASSUME NEW state \in States,
           NEW firstKey \in Vars,
           NEW secondKey \in Vars,
           firstKey # secondKey,
           NEW firstValue \in Values,
           NEW secondValue \in Values
    PROVE /\ GeneratedTwoWrites(state, firstKey, firstValue,
                secondKey, secondValue).accepted
          /\ GeneratedTwoWrites(state, firstKey, firstValue,
                secondKey, secondValue).target
             = [state EXCEPT ![firstKey] = firstValue,
                             ![secondKey] = secondValue]
    BY SMT DEF GeneratedTwoWrites, GeneratedApply, GeneratedMerge,
        GeneratedEmptyUpdates, States

GeneratedCopyStep(source, target) ==
    LET firstRead == source["second"]
        secondRead == firstRead
        outcome == GeneratedTwoWrites(source, "first", firstRead,
            "second", secondRead)
    IN outcome.accepted /\ target = outcome.target

THEOREM GeneratedCopyMatchesEmittedTLA ==
    ASSUME Vars = {"first", "second"},
           Values = Int,
           first \in Int,
           second \in Int,
           first' \in Int,
           second' \in Int
    PROVE GeneratedCopyStep(CopySourceState, CopyTargetState) <=> copy
    PROOF
    <1>1. CopySourceState \in States /\ CopyTargetState \in States
        BY SMT DEF CopySourceState, CopyTargetState, States
    <1>2. /\ GeneratedTwoWrites(CopySourceState, "first", second,
                    "second", second).accepted
          /\ GeneratedTwoWrites(CopySourceState, "first", second,
                    "second", second).target
             = [CopySourceState EXCEPT !["first"] = second,
                                       !["second"] = second]
        BY <1>1, GeneratedDisjointWritesPreserveCompleteState, SMT
    <1>3. GeneratedCopyStep(CopySourceState, CopyTargetState)
            <=> SourceOrderedCopy
        BY <1>2, SMT DEF GeneratedCopyStep, CopySourceState,
            CopyTargetState, SourceOrderedCopy, States
    <1>. QED
        BY <1>3, EmittedCopyStep

VARIABLES orderedPC, orderedX, orderedY
Repeated == INSTANCE OrderedCopy WITH pc <- orderedPC, x <- orderedX, y <- orderedY

SourceOrderedInitial ==
    /\ orderedPC = "copy"
    /\ orderedX = 1
    /\ orderedY = 0

THEOREM EmittedOrderedInitial ==
    Repeated!Init <=> SourceOrderedInitial
    BY SMT DEF Repeated!Init, SourceOrderedInitial

SourceOrderedCopyStep ==
    /\ orderedPC = "copy"
    /\ orderedX' = orderedX + 1
    /\ orderedY' = orderedX + 1
    /\ orderedPC' = "repeatWrites"

THEOREM EmittedOrderedCopyStep ==
    ASSUME orderedX \in Int
    PROVE Repeated!copy <=> SourceOrderedCopyStep
    BY SMT DEF Repeated!copy, SourceOrderedCopyStep

SourceRepeatedWrites ==
    /\ orderedPC = "repeatWrites"
    /\ orderedX' = orderedX + 2
    /\ orderedY' = orderedY
    /\ orderedPC' = "Done"

THEOREM EmittedRepeatedWrites ==
    ASSUME orderedX \in Int
    PROVE Repeated!repeatWrites <=> SourceRepeatedWrites
    BY SMT DEF Repeated!repeatWrites, SourceRepeatedWrites

SourceOrderedTerminating ==
    /\ orderedPC = "Done"
    /\ orderedPC' = orderedPC
    /\ orderedX' = orderedX
    /\ orderedY' = orderedY

THEOREM EmittedOrderedTerminating ==
    Repeated!Terminating <=> SourceOrderedTerminating
    BY SMT DEF Repeated!Terminating, SourceOrderedTerminating

SourceOrderedNext ==
    SourceOrderedCopyStep \/ SourceRepeatedWrites \/ SourceOrderedTerminating

THEOREM EmittedOrderedNext ==
    ASSUME orderedX \in Int
    PROVE Repeated!Next <=> SourceOrderedNext
    BY EmittedOrderedCopyStep, EmittedRepeatedWrites,
        EmittedOrderedTerminating DEF Repeated!Next, SourceOrderedNext

OrderedTypeOK ==
    /\ orderedX \in Int
    /\ orderedY \in Int
    /\ orderedPC \in {"copy", "repeatWrites", "Done"}

THEOREM OrderedInitialType ==
    Repeated!Init => OrderedTypeOK
    BY EmittedOrderedInitial, SMT DEF SourceOrderedInitial, OrderedTypeOK

THEOREM OrderedStepPreservesType ==
    ASSUME OrderedTypeOK, Repeated!Next
    PROVE OrderedTypeOK'
    BY EmittedOrderedNext, SMT DEF OrderedTypeOK, SourceOrderedNext,
        SourceOrderedCopyStep, SourceRepeatedWrites, SourceOrderedTerminating

THEOREM EmittedOrderedTypeInvariant ==
    Repeated!Spec => []OrderedTypeOK
    PROOF
    <1>1. OrderedTypeOK /\ [Repeated!Next]_<<orderedPC, orderedX, orderedY>>
            => OrderedTypeOK'
        BY OrderedStepPreservesType, SMT DEF OrderedTypeOK
    <1>2. OrderedTypeOK /\ [][Repeated!Next]_<<orderedPC, orderedX, orderedY>>
            => []OrderedTypeOK
        BY <1>1, PTL
    <1>. QED
        BY OrderedInitialType, <1>2 DEF Repeated!Spec

SourceOrderedSpec ==
    /\ SourceOrderedInitial
    /\ [][SourceOrderedNext]_<<orderedPC, orderedX, orderedY>>

THEOREM SourceOrderedTypeInvariant ==
    SourceOrderedSpec => []OrderedTypeOK
    PROOF
    <1>1. OrderedTypeOK /\ [SourceOrderedNext]_<<orderedPC, orderedX, orderedY>>
            => OrderedTypeOK'
        BY SMT DEF OrderedTypeOK, SourceOrderedNext,
            SourceOrderedCopyStep, SourceRepeatedWrites,
            SourceOrderedTerminating
    <1>2. OrderedTypeOK /\ [][SourceOrderedNext]_<<orderedPC, orderedX, orderedY>>
            => []OrderedTypeOK
        BY <1>1, PTL
    <1>. QED
        BY <1>2, EmittedOrderedInitial, OrderedInitialType
            DEF SourceOrderedSpec

THEOREM EmittedOrderedTemporalSpec ==
    Repeated!Spec <=> SourceOrderedSpec
    PROOF
    <1>1. []OrderedTypeOK =>
        ([][Repeated!Next]_<<orderedPC, orderedX, orderedY>>
         <=> [][SourceOrderedNext]_<<orderedPC, orderedX, orderedY>>)
        BY EmittedOrderedNext, PTL DEF OrderedTypeOK
    <1>2. Repeated!Spec => []OrderedTypeOK
        BY EmittedOrderedTypeInvariant
    <1>3. SourceOrderedSpec => []OrderedTypeOK
        BY SourceOrderedTypeInvariant
    <1>. QED
        BY <1>1, <1>2, <1>3, EmittedOrderedInitial, PTL
            DEF Repeated!Spec, SourceOrderedSpec

OrderedReachable ==
    \/ (orderedPC = "copy" /\ orderedX = 1 /\ orderedY = 0)
    \/ (orderedPC = "repeatWrites" /\ orderedX = 2 /\ orderedY = 2)
    \/ (orderedPC = "Done" /\ orderedX = 4 /\ orderedY = 2)

THEOREM OrderedInitialReachable ==
    Repeated!Init => OrderedReachable
    BY EmittedOrderedInitial, SMT DEF SourceOrderedInitial, OrderedReachable

THEOREM OrderedStepPreservesReachable ==
    ASSUME OrderedReachable, Repeated!Next
    PROVE OrderedReachable'
    BY EmittedOrderedNext, SMT DEF OrderedReachable, SourceOrderedNext,
        SourceOrderedCopyStep, SourceRepeatedWrites, SourceOrderedTerminating

THEOREM EmittedOrderedReachableInvariant ==
    Repeated!Spec => []OrderedReachable
    PROOF
    <1>1. OrderedReachable /\ [Repeated!Next]_<<orderedPC, orderedX, orderedY>>
            => OrderedReachable'
        BY OrderedStepPreservesReachable, SMT DEF OrderedReachable
    <1>2. OrderedReachable /\ [][Repeated!Next]_<<orderedPC, orderedX, orderedY>>
            => []OrderedReachable
        BY <1>1, PTL
    <1>. QED
        BY OrderedInitialReachable, <1>2 DEF Repeated!Spec

CONSTANTS SwiftIntMin, SwiftIntMax
ASSUME SwiftIntBounds ==
    /\ SwiftIntMin \in Int
    /\ SwiftIntMax \in Int
    /\ SwiftIntMin <= 0
    /\ 4 <= SwiftIntMax

WithinSwiftInt(value) == SwiftIntMin <= value /\ value <= SwiftIntMax

CurrentNativeAddOutcome(lhs, rhs) ==
    IF WithinSwiftInt(lhs + rhs)
    THEN <<"value", lhs + rhs>>
    ELSE <<"overflow">>
CurrentRenderedAddOutcome(lhs, rhs) == <<"value", lhs + rhs>>

THEOREM CurrentAdditionAgreementIsExactlyRangeSafety ==
    \A lhs, rhs \in Int :
        (WithinSwiftInt(lhs) /\ WithinSwiftInt(rhs)) =>
            ((CurrentNativeAddOutcome(lhs, rhs)
              = CurrentRenderedAddOutcome(lhs, rhs))
             <=> WithinSwiftInt(lhs + rhs))
    BY SMT DEF CurrentNativeAddOutcome, CurrentRenderedAddOutcome,
        WithinSwiftInt

THEOREM CurrentAdditionHasRepresentableOperandMismatch ==
    \E lhs, rhs \in Int :
        /\ WithinSwiftInt(lhs)
        /\ WithinSwiftInt(rhs)
        /\ CurrentNativeAddOutcome(lhs, rhs)
           # CurrentRenderedAddOutcome(lhs, rhs)
    PROOF
    <1>1. USE SwiftIntBounds DEF SwiftIntBounds
    <1>2. WITNESS SwiftIntMax \in Int, 1 \in Int
    <1>. QED
        BY SwiftIntBounds, SMT DEF CurrentNativeAddOutcome,
            CurrentRenderedAddOutcome, WithinSwiftInt, SwiftIntBounds

RenderedSignedDivision(dividend, divisor) ==
    (LET __SignedDivision_dividend0 == dividend
     IN (LET __SignedDivision_divisor1 == divisor
         IN (IF __SignedDivision_divisor1 < 0
             THEN (-__SignedDivision_dividend0) \div (-__SignedDivision_divisor1)
             ELSE __SignedDivision_dividend0 \div __SignedDivision_divisor1)))

THEOREM SignedDivisionUsesPositiveDivisor ==
    \A dividend, divisor \in Int :
        divisor # 0 =>
            IF divisor < 0 THEN -divisor > 0 ELSE divisor > 0
    BY SMT

ASSUME PositiveDivisionLaw ==
    \A dividend, divisor \in Int :
        divisor > 0 =>
            \E remainder \in 0..(divisor - 1) :
                dividend = divisor * (dividend \div divisor) + remainder

THEOREM PositiveDivisionLawForNegatedDividend ==
    \A dividend, divisor \in Int :
        divisor > 0 =>
            \E remainder \in 0..(divisor - 1) :
                -dividend = divisor * ((-dividend) \div divisor) + remainder
    PROOF
    <1>. SUFFICES ASSUME NEW dividend \in Int,
                          NEW divisor \in Int,
                          divisor > 0
                  PROVE \E remainder \in 0..(divisor - 1) :
                      -dividend = divisor * ((-dividend) \div divisor)
                          + remainder
        OBVIOUS
    <1>1. -dividend \in Int
        BY SMT
    <1>. QED
        BY <1>1, PositiveDivisionLaw

THEOREM SignedDivisionHasEuclideanRemainder ==
    \A dividend, divisor \in Int :
        divisor < 0 =>
            \E remainder \in (divisor + 1)..0 :
                dividend = divisor * RenderedSignedDivision(dividend, divisor)
                    + remainder
    PROOF
    <1>. SUFFICES ASSUME NEW dividend \in Int,
                          NEW divisor \in Int,
                          divisor < 0
                  PROVE \E remainder \in (divisor + 1)..0 :
                      dividend = divisor * RenderedSignedDivision(dividend, divisor)
                          + remainder
        OBVIOUS
    <1>1. -dividend \in Int /\ -divisor \in Int /\ -divisor > 0
        BY SMT
    <1>2. PICK remainder \in 0..(-divisor - 1) :
            -dividend = (-divisor) * ((-dividend) \div (-divisor)) + remainder
        BY <1>1, PositiveDivisionLaw
    <1>3. -remainder \in (divisor + 1)..0
        BY <1>2, SMT
    <1>4. dividend = divisor * RenderedSignedDivision(dividend, divisor)
            + (-remainder)
        BY <1>2, SMT DEF RenderedSignedDivision
    <1>. QED
        BY <1>3, <1>4

THEOREM PositiveDivisionQuotientUnique ==
    \A dividend, divisor, first, second, firstRemainder, secondRemainder \in Int :
        (divisor > 0
         /\ 0 <= firstRemainder /\ firstRemainder < divisor
         /\ 0 <= secondRemainder /\ secondRemainder < divisor
         /\ dividend = divisor * first + firstRemainder
         /\ dividend = divisor * second + secondRemainder)
        => first = second
    BY SMT

THEOREM NegatedDivisionFromRemainders ==
    \A magnitude, divisor, quotient, remainder, negativeQuotient,
       negativeRemainder \in Int :
        (divisor > 0
         /\ 0 <= remainder /\ remainder < divisor
         /\ 0 <= negativeRemainder /\ negativeRemainder < divisor
         /\ magnitude = divisor * quotient + remainder
         /\ -magnitude = divisor * negativeQuotient + negativeRemainder)
        => negativeQuotient =
            IF remainder = 0 THEN 0 - quotient ELSE 0 - quotient - 1
    PROOF
    <1>. SUFFICES ASSUME NEW magnitude \in Int,
                          NEW divisor \in Int,
                          NEW quotient \in Int,
                          NEW remainder \in Int,
                          NEW negativeQuotient \in Int,
                          NEW negativeRemainder \in Int,
                          divisor > 0,
                          0 <= remainder,
                          remainder < divisor,
                          0 <= negativeRemainder,
                          negativeRemainder < divisor,
                          magnitude = divisor * quotient + remainder,
                          -magnitude = divisor * negativeQuotient
                              + negativeRemainder
                  PROVE negativeQuotient =
                      IF remainder = 0 THEN 0 - quotient
                      ELSE 0 - quotient - 1
        OBVIOUS
    <1>1. CASE remainder = 0
        <2>1. -magnitude = divisor * (0 - quotient) + 0
            BY <1>1, SMT
        <2>2. negativeQuotient = 0 - quotient
            BY <1>1, <2>1, PositiveDivisionQuotientUnique, SMT
        <2>. QED
            BY <1>1, <2>2
    <1>2. CASE remainder # 0
        <2>1. 0 < remainder /\ remainder < divisor
            BY <1>2, SMT
        <2>2. 0 <= divisor - remainder /\ divisor - remainder < divisor
            BY <1>2, <2>1, SMT
        <2>3. -magnitude = divisor * (0 - quotient - 1)
                + (divisor - remainder)
            BY <1>2, SMT
        <2>4. negativeQuotient = 0 - quotient - 1
            BY <1>2, <2>2, <2>3, PositiveDivisionQuotientUnique, SMT
        <2>. QED
            BY <1>2, <2>4
    <1>. QED
        BY <1>1, <1>2

THEOREM PositiveDivisionNegation ==
    \A magnitude, divisor \in Int :
        (magnitude >= 0 /\ divisor > 0) =>
            ((-magnitude) \div divisor
             = IF magnitude - divisor * (magnitude \div divisor) = 0
               THEN 0 - (magnitude \div divisor)
               ELSE 0 - (magnitude \div divisor) - 1)
    PROOF
    <1>. SUFFICES ASSUME NEW magnitude \in Int,
                          NEW divisor \in Int,
                          magnitude >= 0,
                          divisor > 0
                  PROVE (-magnitude) \div divisor
                      = IF magnitude - divisor * (magnitude \div divisor) = 0
                        THEN 0 - (magnitude \div divisor)
                        ELSE 0 - (magnitude \div divisor) - 1
        OBVIOUS
    <1>1. PICK remainder \in 0..(divisor - 1) :
            magnitude = divisor * (magnitude \div divisor) + remainder
        BY PositiveDivisionLaw
    <1>2. PICK negativeRemainder \in 0..(divisor - 1) :
            -magnitude = divisor * ((-magnitude) \div divisor)
                + negativeRemainder
        BY PositiveDivisionLaw
    <1>3. 0 <= remainder /\ remainder < divisor
           /\ 0 <= negativeRemainder /\ negativeRemainder < divisor
        BY <1>1, <1>2, SMT
    <1>4. (-magnitude) \div divisor =
            IF remainder = 0
            THEN 0 - (magnitude \div divisor)
            ELSE 0 - (magnitude \div divisor) - 1
        BY <1>1, <1>2, <1>3, NegatedDivisionFromRemainders, SMT
    <1>. QED
        BY <1>1, <1>4, SMT

AdjustedTruncatingDivision(dividend, divisor) ==
    LET magnitude == IF dividend < 0 THEN -dividend ELSE dividend
        positiveDivisor == IF divisor < 0 THEN -divisor ELSE divisor
        quotient == magnitude \div positiveDivisor
        remainder == magnitude - positiveDivisor * quotient
    IN IF (dividend < 0) # (divisor < 0)
       THEN IF remainder = 0 THEN 0 - quotient ELSE 0 - quotient - 1
       ELSE quotient

THEOREM AdjustedTruncatingDivisionMatchesRendered ==
    \A dividend, divisor \in Int :
        divisor # 0 =>
            AdjustedTruncatingDivision(dividend, divisor)
                = RenderedSignedDivision(dividend, divisor)
    PROOF
    <1>. SUFFICES ASSUME NEW dividend \in Int,
                          NEW divisor \in Int,
                          divisor # 0
                  PROVE AdjustedTruncatingDivision(dividend, divisor)
                      = RenderedSignedDivision(dividend, divisor)
        OBVIOUS
    <1>1. CASE dividend >= 0 /\ divisor > 0
        <2>1. AdjustedTruncatingDivision(dividend, divisor)
                = dividend \div divisor
            BY <1>1, SMT DEF AdjustedTruncatingDivision
        <2>2. RenderedSignedDivision(dividend, divisor)
                = dividend \div divisor
            BY <1>1, SMT DEF RenderedSignedDivision
        <2>. QED BY <2>1, <2>2
    <1>2. CASE dividend < 0 /\ divisor > 0
        BY <1>2, PositiveDivisionNegation, SMT
            DEF AdjustedTruncatingDivision, RenderedSignedDivision
    <1>3. CASE dividend >= 0 /\ divisor < 0
        BY <1>3, PositiveDivisionNegation, SMT
            DEF AdjustedTruncatingDivision, RenderedSignedDivision
    <1>4. CASE dividend < 0 /\ divisor < 0
        BY <1>4, SMT DEF AdjustedTruncatingDivision,
            RenderedSignedDivision
    <1>. QED
        BY <1>1, <1>2, <1>3, <1>4, SMT

ModeledTruncatingQuotient(dividend, divisor) ==
    LET magnitude == IF dividend < 0 THEN -dividend ELSE dividend
        positiveDivisor == IF divisor < 0 THEN -divisor ELSE divisor
        magnitudeQuotient == magnitude \div positiveDivisor
    IN IF (dividend < 0) # (divisor < 0)
       THEN 0 - magnitudeQuotient
       ELSE magnitudeQuotient

ModeledTruncatingRemainder(dividend, divisor) ==
    dividend - divisor * ModeledTruncatingQuotient(dividend, divisor)

ModeledSwiftDivisionAlgorithm(dividend, divisor) ==
    LET quotient == ModeledTruncatingQuotient(dividend, divisor)
    IN IF ((dividend < 0) # (divisor < 0))
          /\ ModeledTruncatingRemainder(dividend, divisor) # 0
       THEN quotient - 1
       ELSE quotient

THEOREM ModeledSwiftDivisionAlgorithmMatchesAdjusted ==
    \A dividend, divisor \in Int :
        divisor # 0 =>
            ModeledSwiftDivisionAlgorithm(dividend, divisor)
                = AdjustedTruncatingDivision(dividend, divisor)
    PROOF
    <1>. SUFFICES ASSUME NEW dividend \in Int,
                          NEW divisor \in Int,
                          divisor # 0
                  PROVE ModeledSwiftDivisionAlgorithm(dividend, divisor)
                      = AdjustedTruncatingDivision(dividend, divisor)
        OBVIOUS
    <1>1. CASE dividend >= 0 /\ divisor > 0
        BY <1>1, SMT DEF ModeledSwiftDivisionAlgorithm,
            ModeledTruncatingQuotient, ModeledTruncatingRemainder,
            AdjustedTruncatingDivision
    <1>2. CASE dividend < 0 /\ divisor > 0
        BY <1>2, SMT DEF ModeledSwiftDivisionAlgorithm,
            ModeledTruncatingQuotient, ModeledTruncatingRemainder,
            AdjustedTruncatingDivision
    <1>3. CASE dividend >= 0 /\ divisor < 0
        BY <1>3, SMT DEF ModeledSwiftDivisionAlgorithm,
            ModeledTruncatingQuotient, ModeledTruncatingRemainder,
            AdjustedTruncatingDivision
    <1>4. CASE dividend < 0 /\ divisor < 0
        BY <1>4, SMT DEF ModeledSwiftDivisionAlgorithm,
            ModeledTruncatingQuotient, ModeledTruncatingRemainder,
            AdjustedTruncatingDivision
    <1>. QED
        BY <1>1, <1>2, <1>3, <1>4, SMT

THEOREM ModeledSwiftDivisionAlgorithmMatchesRendered ==
    \A dividend, divisor \in Int :
        divisor # 0 =>
            ModeledSwiftDivisionAlgorithm(dividend, divisor)
                = RenderedSignedDivision(dividend, divisor)
    BY ModeledSwiftDivisionAlgorithmMatchesAdjusted,
        AdjustedTruncatingDivisionMatchesRendered, SMT

CurrentNativeDivisionOutcome(dividend, divisor) ==
    IF WithinSwiftInt(ModeledSwiftDivisionAlgorithm(dividend, divisor))
    THEN <<"value", ModeledSwiftDivisionAlgorithm(dividend, divisor)>>
    ELSE <<"overflow">>
CurrentRenderedDivisionOutcome(dividend, divisor) ==
    <<"value", RenderedSignedDivision(dividend, divisor)>>

THEOREM CurrentDivisionAgreementIsExactlyRangeSafety ==
    \A dividend, divisor \in Int :
        (WithinSwiftInt(dividend) /\ WithinSwiftInt(divisor)
         /\ divisor # 0) =>
            ((CurrentNativeDivisionOutcome(dividend, divisor)
              = CurrentRenderedDivisionOutcome(dividend, divisor))
             <=> WithinSwiftInt(RenderedSignedDivision(dividend, divisor)))
    BY ModeledSwiftDivisionAlgorithmMatchesRendered, SMT
        DEF CurrentNativeDivisionOutcome, CurrentRenderedDivisionOutcome,
            WithinSwiftInt

ModeledSwiftModuloAlgorithm(dividend, divisor) ==
    LET remainder == ModeledTruncatingRemainder(dividend, divisor)
    IN IF remainder < 0 THEN remainder + divisor ELSE remainder

THEOREM ModeledSwiftModuloMatchesEuclideanRemainder ==
    \A dividend, divisor \in Int :
        divisor > 0 =>
            ModeledSwiftModuloAlgorithm(dividend, divisor)
                = dividend - divisor * (dividend \div divisor)
    PROOF
    <1>. SUFFICES ASSUME NEW dividend \in Int,
                          NEW divisor \in Int,
                          divisor > 0
                  PROVE ModeledSwiftModuloAlgorithm(dividend, divisor)
                      = dividend - divisor * (dividend \div divisor)
        OBVIOUS
    <1>1. CASE dividend >= 0
        <2>1. PICK remainder \in 0..(divisor - 1) :
                dividend = divisor * (dividend \div divisor) + remainder
            BY PositiveDivisionLaw
        <2>2. 0 <= remainder /\ remainder < divisor
            BY <2>1, SMT
        <2>3. ModeledTruncatingQuotient(dividend, divisor)
                = dividend \div divisor
            BY <1>1, SMT DEF ModeledTruncatingQuotient
        <2>4. ModeledTruncatingRemainder(dividend, divisor) = remainder
            BY <2>1, <2>3, SMT DEF ModeledTruncatingRemainder
        <2>. QED
            BY <2>1, <2>2, <2>4, SMT
                DEF ModeledSwiftModuloAlgorithm
    <1>2. CASE dividend < 0
        <2>1. PICK remainder \in 0..(divisor - 1) :
                -dividend = divisor * ((-dividend) \div divisor) + remainder
            BY PositiveDivisionLawForNegatedDividend
        <2>. QED
            BY <1>2, <2>1, PositiveDivisionNegation, SMT
                DEF ModeledSwiftModuloAlgorithm,
                    ModeledTruncatingQuotient, ModeledTruncatingRemainder
    <1>. QED
        BY <1>1, <1>2, SMT

ASSUME PositiveModuloLaw ==
    \A dividend, divisor \in Int :
        divisor > 0 =>
            dividend % divisor
                = dividend - divisor * (dividend \div divisor)

THEOREM ModeledSwiftModuloMatchesRendered ==
    \A dividend, divisor \in Int :
        divisor > 0 =>
            ModeledSwiftModuloAlgorithm(dividend, divisor)
                = dividend % divisor
    BY ModeledSwiftModuloMatchesEuclideanRemainder,
        PositiveModuloLaw, SMT

THEOREM ModeledSwiftModuloStaysWithinSwiftInt ==
    \A dividend, divisor \in Int :
        (WithinSwiftInt(dividend) /\ WithinSwiftInt(divisor)
         /\ divisor > 0) =>
            WithinSwiftInt(ModeledSwiftModuloAlgorithm(dividend, divisor))
    PROOF
    <1>. SUFFICES ASSUME NEW dividend \in Int,
                          NEW divisor \in Int,
                          WithinSwiftInt(dividend),
                          WithinSwiftInt(divisor),
                          divisor > 0
                  PROVE WithinSwiftInt(
                      ModeledSwiftModuloAlgorithm(dividend, divisor))
        OBVIOUS
    <1>1. PICK remainder \in 0..(divisor - 1) :
            dividend = divisor * (dividend \div divisor) + remainder
        BY PositiveDivisionLaw
    <1>2. 0 <= remainder /\ remainder < divisor
        BY <1>1, SMT
    <1>3. ModeledSwiftModuloAlgorithm(dividend, divisor) = remainder
        BY <1>1, ModeledSwiftModuloMatchesEuclideanRemainder, SMT
    <1>. QED
        BY <1>2, <1>3, SwiftIntBounds, SMT
            DEF WithinSwiftInt, SwiftIntBounds

StrictlyIncreasingIntegers(sequence) ==
    \A first, second \in 1..Len(sequence) :
        first < second => sequence[first] < sequence[second]

FirstMatchingInteger(sequence, predicate, index) ==
    /\ index \in 1..Len(sequence)
    /\ predicate[sequence[index]]
    /\ \A earlier \in 1..(index - 1) : ~predicate[sequence[earlier]]

THEOREM SortedIntegerFirstIsUniqueLeast ==
    \A sequence \in Seq(Int) :
        \A predicate \in [SequenceMembers(sequence) -> BOOLEAN] :
            \A index \in 1..Len(sequence) :
                (StrictlyIncreasingIntegers(sequence)
                 /\ FirstMatchingInteger(sequence, predicate, index)) =>
                    /\ sequence[index] \in SequenceMembers(sequence)
                    /\ \A other \in SequenceMembers(sequence) :
                        predicate[other] => sequence[index] <= other
                    /\ \A candidate \in SequenceMembers(sequence) :
                        (predicate[candidate]
                         /\ (\A other \in SequenceMembers(sequence) :
                             predicate[other] => candidate <= other))
                        => candidate = sequence[index]
    BY SMT DEF StrictlyIncreasingIntegers, FirstMatchingInteger,
        SequenceMembers

CanonicalIntegerChoice(sequence, predicate) ==
    LET candidates == SequenceMembers(sequence)
    IN CHOOSE member \in candidates :
        predicate[member]
        /\ (\A other \in candidates : predicate[other] => member <= other)

THEOREM CanonicalIntegerChoiceMatchesSortedFirst ==
    \A sequence \in Seq(Int) :
        \A predicate \in [SequenceMembers(sequence) -> BOOLEAN] :
            \A index \in 1..Len(sequence) :
                (StrictlyIncreasingIntegers(sequence)
                 /\ FirstMatchingInteger(sequence, predicate, index))
                => CanonicalIntegerChoice(sequence, predicate) = sequence[index]
    BY SortedIntegerFirstIsUniqueLeast, UniqueExpressionChoice, SMT
        DEF CanonicalIntegerChoice, StrictlyIncreasingIntegers,
            FirstMatchingInteger, SequenceMembers

CurrentNativeSubtractOutcome(lhs, rhs) ==
    IF WithinSwiftInt(lhs - rhs)
    THEN <<"value", lhs - rhs>>
    ELSE <<"overflow">>
CurrentRenderedSubtractOutcome(lhs, rhs) == <<"value", lhs - rhs>>

CurrentNativeMultiplyOutcome(lhs, rhs) ==
    IF WithinSwiftInt(lhs * rhs)
    THEN <<"value", lhs * rhs>>
    ELSE <<"overflow">>
CurrentRenderedMultiplyOutcome(lhs, rhs) == <<"value", lhs * rhs>>

CurrentNativeNegateOutcome(value) ==
    IF WithinSwiftInt(-value)
    THEN <<"value", -value>>
    ELSE <<"overflow">>
CurrentRenderedNegateOutcome(value) == <<"value", -value>>

THEOREM CurrentSubtractionAgreementIsExactlyRangeSafety ==
    \A lhs, rhs \in Int :
        (WithinSwiftInt(lhs) /\ WithinSwiftInt(rhs)) =>
            ((CurrentNativeSubtractOutcome(lhs, rhs)
              = CurrentRenderedSubtractOutcome(lhs, rhs))
             <=> WithinSwiftInt(lhs - rhs))
    BY SMT DEF CurrentNativeSubtractOutcome,
        CurrentRenderedSubtractOutcome, WithinSwiftInt

THEOREM CurrentMultiplicationAgreementIsExactlyRangeSafety ==
    \A lhs, rhs \in Int :
        (WithinSwiftInt(lhs) /\ WithinSwiftInt(rhs)) =>
            ((CurrentNativeMultiplyOutcome(lhs, rhs)
              = CurrentRenderedMultiplyOutcome(lhs, rhs))
             <=> WithinSwiftInt(lhs * rhs))
    BY SMT DEF CurrentNativeMultiplyOutcome,
        CurrentRenderedMultiplyOutcome, WithinSwiftInt

THEOREM CurrentNegationAgreementIsExactlyRangeSafety ==
    \A value \in Int :
        WithinSwiftInt(value) =>
            ((CurrentNativeNegateOutcome(value)
              = CurrentRenderedNegateOutcome(value))
             <=> WithinSwiftInt(-value))
    BY SMT DEF CurrentNativeNegateOutcome,
        CurrentRenderedNegateOutcome, WithinSwiftInt

THEOREM EmittedOrderedArithmeticIsRepresentable ==
    OrderedReachable =>
        /\ WithinSwiftInt(orderedX)
        /\ WithinSwiftInt(orderedY)
        /\ (orderedPC = "copy" => WithinSwiftInt(orderedX + 1))
        /\ (orderedPC = "repeatWrites" =>
            WithinSwiftInt(orderedX + 1)
            /\ WithinSwiftInt((orderedX + 1) + 1))
    BY SwiftIntBounds, SMT DEF OrderedReachable, WithinSwiftInt, SwiftIntBounds

OrderedStates ==
    [pc: {"copy", "repeatWrites", "Done"}, x: Int, y: Int]
OrderedBefore == [pc |-> orderedPC, x |-> orderedX, y |-> orderedY]
OrderedAfter == [pc |-> orderedPC', x |-> orderedX', y |-> orderedY']

OrderedSuccessor(state) ==
    IF state.pc = "copy"
    THEN [pc |-> "repeatWrites", x |-> state.x + 1, y |-> state.x + 1]
    ELSE IF state.pc = "repeatWrites"
         THEN [pc |-> "Done", x |-> state.x + 2, y |-> state.y]
         ELSE state

OrderedStepRelation(before, after) ==
    /\ before \in OrderedStates
    /\ after = OrderedSuccessor(before)

THEOREM OrderedSuccessorIsTotal ==
    \A state \in OrderedStates :
        /\ OrderedSuccessor(state) \in OrderedStates
        /\ OrderedStepRelation(state, OrderedSuccessor(state))
    BY SMT DEF OrderedStates, OrderedSuccessor, OrderedStepRelation

THEOREM OrderedHasNoRelationalDeadlock ==
    \A state \in OrderedStates :
        \E successor \in OrderedStates : OrderedStepRelation(state, successor)
    BY OrderedSuccessorIsTotal

THEOREM EmittedOrderedCompleteStateRelation ==
    ASSUME OrderedTypeOK,
           OrderedAfter \in OrderedStates
    PROVE Repeated!Next <=> OrderedStepRelation(OrderedBefore, OrderedAfter)
    BY EmittedOrderedNext, SMT DEF OrderedStepRelation,
        OrderedSuccessor, OrderedStates, OrderedTypeOK,
        OrderedBefore, OrderedAfter, SourceOrderedNext,
        SourceOrderedCopyStep, SourceRepeatedWrites,
        SourceOrderedTerminating

THEOREM EmittedOrderedExactRelation ==
    ASSUME OrderedTypeOK
    PROVE Repeated!Next <=> OrderedStepRelation(OrderedBefore, OrderedAfter)
    PROOF
    <1>1. Repeated!Next => OrderedAfter \in OrderedStates
        BY OrderedStepPreservesType,
            SMT DEF OrderedAfter, OrderedStates, OrderedTypeOK
    <1>2. OrderedStepRelation(OrderedBefore, OrderedAfter)
            => OrderedAfter \in OrderedStates
        BY OrderedSuccessorIsTotal,
            SMT DEF OrderedStepRelation, OrderedBefore, OrderedStates,
                OrderedTypeOK
    <1>. QED
        BY <1>1, <1>2, EmittedOrderedCompleteStateRelation

SourceGuardedChoice ==
    /\ choiceSelected = 0
    /\ (choiceSelected' = 1 \/ choiceSelected' = 2)

THEOREM EmittedGuardedChoiceInitialState ==
    Choice!Init <=> choiceSelected = 0
    BY SMT DEF Choice!Init

THEOREM EmittedGuardedChoiceStep ==
    Choice!choose <=> SourceGuardedChoice
    BY SMT DEF Choice!choose, SourceGuardedChoice

THEOREM EmittedGuardedChoiceNext ==
    Choice!Next <=> SourceGuardedChoice
    BY EmittedGuardedChoiceStep DEF Choice!Next

THEOREM GuardedChoiceDisabledAfterSelection ==
    choiceSelected # 0 => ~Choice!choose
    BY EmittedGuardedChoiceStep, SMT DEF SourceGuardedChoice

THEOREM OrderedGuardedDoEnabledness ==
    ASSUME NEW original \in States,
           NEW steps \in Seq(Instructions),
           NEW guards \in GuardPlans(steps)
    PROVE (\E target \in States :
            SourceGuardedDoStep(original, steps, guards, target))
          <=> (\E target \in States :
            ScheduledGuardedDoStep(original, steps, guards, target))
    BY OrderedGuardedDoTransitionEquivalence

SourceGuardedDoEdges(label, steps, guards) ==
    {edge \in LabeledEdges :
        edge[2] = label /\ SourceGuardedDoStep(edge[1], steps, guards, edge[3])}
ScheduledGuardedDoEdges(label, steps, guards) ==
    {edge \in LabeledEdges :
        edge[2] = label /\ ScheduledGuardedDoStep(edge[1], steps, guards, edge[3])}

THEOREM OrderedGuardedDoLabeledEdges ==
    ASSUME NEW label \in ActionLabels,
           NEW steps \in Seq(Instructions),
           NEW guards \in GuardPlans(steps)
    PROVE SourceGuardedDoEdges(label, steps, guards)
          = ScheduledGuardedDoEdges(label, steps, guards)
    BY OrderedGuardedDoTransitionEquivalence,
        SMT DEF SourceGuardedDoEdges, ScheduledGuardedDoEdges, LabeledEdges

RepeatedBefore ==
    [key \in Vars |->
        IF key = "orderedPC" THEN orderedPC
        ELSE IF key = "orderedX" THEN orderedX ELSE orderedY]
RepeatedAfter ==
    [key \in Vars |->
        IF key = "orderedPC" THEN orderedPC'
        ELSE IF key = "orderedX" THEN orderedX' ELSE orderedY']
RepeatedInstructions ==
    <<[target |-> "orderedX",
       rhs |-> [state \in States |->
           IF state["orderedX"] \in Int THEN state["orderedX"] + 1 ELSE 0]],
      [target |-> "orderedX",
       rhs |-> [state \in States |->
           IF state["orderedX"] \in Int THEN state["orderedX"] + 1 ELSE 0]],
      [target |-> "orderedPC", rhs |-> [state \in States |-> "Done"]]>>
RepeatedGuards ==
    [index \in 0..3 |-> [state \in States |->
        IF index = 0 THEN state["orderedPC"] = "repeatWrites" ELSE TRUE]]
RepeatedAfterFirst == [RepeatedBefore EXCEPT !["orderedX"] = orderedX + 1]
RepeatedAfterSecond == [RepeatedAfterFirst EXCEPT !["orderedX"] = orderedX + 2]
RepeatedAfterThird == [RepeatedAfterSecond EXCEPT !["orderedPC"] = "Done"]
RepeatedWitnessHistory ==
    [index \in 0..3 |->
        IF index = 0 THEN RepeatedBefore
        ELSE IF index = 1 THEN RepeatedAfterFirst
        ELSE IF index = 2 THEN RepeatedAfterSecond
        ELSE RepeatedAfterThird]

THEOREM EmittedRepeatedWritesMatchesGuardedHistory ==
    ASSUME Vars = {"orderedPC", "orderedX", "orderedY"},
           Values = Int \cup {"copy", "repeatWrites", "Done"},
           orderedPC \in {"copy", "repeatWrites", "Done"},
           orderedX \in Int, orderedY \in Int,
           orderedPC' \in {"copy", "repeatWrites", "Done"},
           orderedX' \in Int, orderedY' \in Int
    PROVE Repeated!repeatWrites
          <=> ScheduledGuardedDoStep(
                RepeatedBefore, RepeatedInstructions, RepeatedGuards, RepeatedAfter)
    PROOF
    <1>1. RepeatedBefore \in States /\ RepeatedAfter \in States
        BY SMT DEF RepeatedBefore, RepeatedAfter, States
    <1>2. RepeatedInstructions \in Seq(Instructions)
        BY <1>1, SMT DEF RepeatedInstructions, Instructions, States
    <1>3. RepeatedGuards \in GuardPlans(RepeatedInstructions)
        BY <1>1, <1>2, SMT DEF RepeatedGuards, GuardPlans, States,
            RepeatedInstructions
    <1>4. RepeatedWitnessHistory \in [0..Len(RepeatedInstructions) -> States]
        BY <1>1, SMT DEF RepeatedWitnessHistory, RepeatedAfterFirst,
            RepeatedAfterSecond, RepeatedAfterThird, RepeatedInstructions, States
    <1>5. /\ AdvanceSource(RepeatedBefore, RepeatedInstructions[1])
                = RepeatedAfterFirst
          /\ AdvanceSource(RepeatedAfterFirst, RepeatedInstructions[2])
                = RepeatedAfterSecond
          /\ AdvanceSource(RepeatedAfterSecond, RepeatedInstructions[3])
                = RepeatedAfterThird
        BY <1>1, SMT DEF AdvanceSource, RepeatedBefore,
            RepeatedAfterFirst, RepeatedAfterSecond, RepeatedAfterThird,
            RepeatedInstructions, States
    <1>6. SourceHistory(RepeatedBefore, RepeatedInstructions, RepeatedWitnessHistory)
        BY <1>1, <1>2, <1>4, <1>5,
            SMT DEF SourceHistory, RepeatedWitnessHistory,
                RepeatedInstructions
    <1>7. \A history \in [0..Len(RepeatedInstructions) -> States] :
            SourceHistory(RepeatedBefore, RepeatedInstructions, history)
            => history = RepeatedWitnessHistory
        BY <1>1, <1>2, <1>5, <1>6,
            SMT DEF SourceHistory, RepeatedWitnessHistory,
                RepeatedInstructions
    <1>8. RepeatedAfterThird = RepeatedAfter
            <=> /\ orderedX' = orderedX + 2
                /\ orderedY' = orderedY
                /\ orderedPC' = "Done"
        BY SMT DEF RepeatedAfterThird, RepeatedAfterSecond,
            RepeatedAfterFirst, RepeatedBefore, RepeatedAfter, States
    <1>9. RepeatedGuards[0][RepeatedWitnessHistory[0]]
            <=> orderedPC = "repeatWrites"
        BY <1>4, SMT DEF RepeatedGuards, RepeatedWitnessHistory,
            RepeatedBefore, States
    <1>10. \A index \in 1..3 :
            RepeatedGuards[index][RepeatedWitnessHistory[index]]
        BY <1>4, SMT DEF RepeatedGuards, RepeatedWitnessHistory, States
    <1>11. (\A index \in 0..Len(RepeatedInstructions) :
            RepeatedGuards[index][RepeatedWitnessHistory[index]])
            <=> orderedPC = "repeatWrites"
        BY <1>9, <1>10, SMT DEF RepeatedInstructions
    <1>12. SourceGuardedDoStep(
            RepeatedBefore, RepeatedInstructions, RepeatedGuards, RepeatedAfter)
            => SourceRepeatedWrites
        BY <1>7, <1>8, <1>11,
            SMT DEF SourceGuardedDoStep, SourceRepeatedWrites,
                RepeatedWitnessHistory, RepeatedInstructions
    <1>13. SourceRepeatedWrites
            => SourceGuardedDoStep(
                RepeatedBefore, RepeatedInstructions, RepeatedGuards, RepeatedAfter)
        PROOF
        <2>. SUFFICES ASSUME SourceRepeatedWrites
                      PROVE SourceGuardedDoStep(
                          RepeatedBefore, RepeatedInstructions,
                          RepeatedGuards, RepeatedAfter)
            OBVIOUS
        <2>1. RepeatedAfterThird = RepeatedAfter
            BY <1>8, SMT DEF SourceRepeatedWrites
        <2>2. \A index \in 0..Len(RepeatedInstructions) :
                RepeatedGuards[index][RepeatedWitnessHistory[index]]
            BY <1>11, SMT DEF SourceRepeatedWrites
        <2>3. \E history \in [0..Len(RepeatedInstructions) -> States] :
                /\ SourceHistory(RepeatedBefore, RepeatedInstructions, history)
                /\ \A index \in 0..Len(RepeatedInstructions) :
                    RepeatedGuards[index][history[index]]
                /\ history[Len(RepeatedInstructions)] = RepeatedAfter
            <3>. WITNESS RepeatedWitnessHistory
                    \in [0..Len(RepeatedInstructions) -> States]
            <3>. QED
                BY <1>4, <1>6, <2>1, <2>2, SMT
                    DEF RepeatedWitnessHistory, RepeatedInstructions
        <2>. QED
            BY <2>3 DEF SourceGuardedDoStep
    <1>14. SourceGuardedDoStep(
            RepeatedBefore, RepeatedInstructions, RepeatedGuards, RepeatedAfter)
            <=> SourceRepeatedWrites
        BY <1>12, <1>13
    <1>. QED
        BY <1>1, <1>2, <1>3, <1>14, EmittedRepeatedWrites,
            OrderedGuardedDoTransitionEquivalence
=======================================================================
