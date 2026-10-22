---------------- MODULE BooleanEqualityCaptureRule ----------------
EXTENDS TLAPS

States == [flag: BOOLEAN, mirror: BOOLEAN]

SourceInit(state) == state.flag = FALSE /\ state.mirror = FALSE
CompiledInit(state) == state.flag = FALSE /\ state.mirror = FALSE
NativeInit(state) == state.flag = FALSE /\ state.mirror = FALSE
RenderedInit(state) == state.flag = FALSE /\ state.mirror = FALSE

THEOREM BooleanEqualityCapturePreservesInitialStates ==
    \A state \in States :
        /\ SourceInit(state) <=> CompiledInit(state)
        /\ CompiledInit(state) <=> NativeInit(state)
        /\ CompiledInit(state) <=> RenderedInit(state)
    BY SMT DEF States, SourceInit, CompiledInit, NativeInit, RenderedInit

SourceValue(state) ==
    IF state.mirror THEN state.flag ELSE ~state.flag
CompiledValue(state) == state.mirror = state.flag
NativeValue(state) == state.mirror = state.flag
RenderedValue(state) ==
    LET __atomic_0 == state.mirror = state.flag
    IN LET __atomic_1 == __atomic_0 IN __atomic_1

SourceStep(before, after) ==
    /\ after.flag = SourceValue(before)
    /\ after.mirror = before.mirror
CompiledStep(before, after) ==
    /\ after.flag = CompiledValue(before)
    /\ after.mirror = before.mirror
NativeStep(before, after) ==
    /\ after.flag = NativeValue(before)
    /\ after.mirror = before.mirror
RenderedStep(before, after) ==
    /\ after.flag = RenderedValue(before)
    /\ after.mirror = before.mirror

SourceLabeledStep(action, before, after) ==
    action = "compare" /\ SourceStep(before, after)
CompiledLabeledStep(action, before, after) ==
    action = "compare" /\ CompiledStep(before, after)
NativeLabeledStep(action, before, after) ==
    action = "compare" /\ NativeStep(before, after)
RenderedLabeledStep(action, before, after) ==
    action = "compare" /\ RenderedStep(before, after)

THEOREM BooleanEqualityCapturePreservesCompleteSteps ==
    \A action : \A before, after \in States :
        /\ SourceLabeledStep(action, before, after)
           <=> CompiledLabeledStep(action, before, after)
        /\ CompiledLabeledStep(action, before, after)
           <=> NativeLabeledStep(action, before, after)
        /\ CompiledLabeledStep(action, before, after)
           <=> RenderedLabeledStep(action, before, after)
    BY SMT DEF States, SourceStep, CompiledStep, NativeStep,
        RenderedStep, SourceLabeledStep, CompiledLabeledStep,
        NativeLabeledStep, RenderedLabeledStep, SourceValue,
        CompiledValue, NativeValue, RenderedValue

SourceEnabled(before) ==
    \E after \in States : SourceStep(before, after)
NativeEnabled(before) ==
    \E after \in States : NativeStep(before, after)
RenderedEnabled(before) ==
    \E after \in States : RenderedStep(before, after)

THEOREM BooleanEqualityCapturePreservesDeadlockVerdict ==
    \A before \in States :
        /\ SourceEnabled(before) <=> NativeEnabled(before)
        /\ SourceEnabled(before) <=> RenderedEnabled(before)
    BY SMT DEF States, SourceEnabled, NativeEnabled, RenderedEnabled,
        SourceStep, NativeStep, RenderedStep, SourceValue,
        NativeValue, RenderedValue

===============================================================
