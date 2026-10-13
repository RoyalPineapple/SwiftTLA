---------------- MODULE MissingFunctionKeyProof ----------------
EXTENDS TLAPS, MissingFunctionKey, FiniteSetTheorems

SourceInit ==
    /\ table = [member \in {0} |-> 42]
    /\ key = 1
    /\ result = 0
SourceRead ==
    IF key \in DOMAIN table
    THEN result' = table[key] /\ UNCHANGED <<table, key>>
    ELSE FALSE
SourceFailure == key \notin DOMAIN table
SourceEvaluationOK == ~SourceFailure
SourceLabeledRead(label) == label = "read" /\ SourceRead
EmittedLabeledRead(label) == label = "read" /\ read

CompiledRead ==
    IF key \in DOMAIN table
    THEN result' = table[key] /\ UNCHANGED <<table, key>>
    ELSE FALSE
CompiledFailure == key \notin DOMAIN table

THEOREM SingletonHasOneMember == Cardinality({0}) = 1
    BY FS_Singleton, SMT

THEOREM EmittedInitialPreservesSource ==
    Init <=> SourceInit
    BY SingletonHasOneMember, SMT DEF Init, SourceInit

THEOREM LoweredReadPreservesSource ==
    CompiledRead <=> SourceRead
    BY DEF CompiledRead, SourceRead

THEOREM EmittedReadPreservesLowering ==
    read <=> CompiledRead
    BY SMT DEF read, CompiledRead

THEOREM EmittedFailurePreservesLowering ==
    __SwiftTLAFunctionArgumentOutsideDomainFailure0 <=> CompiledFailure
    BY SMT DEF __SwiftTLAFunctionArgumentOutsideDomainFailure0,
        CompiledFailure

THEOREM EmittedEvaluationCheckPreservesSource ==
    __SwiftTLAEvaluationOK <=> SourceEvaluationOK
    BY EmittedFailurePreservesLowering, SMT
        DEF __SwiftTLAEvaluationOK, CompiledFailure,
            SourceEvaluationOK, SourceFailure

THEOREM CompleteReadSlice ==
    ASSUME NEW label
    PROVE /\ (Init <=> SourceInit)
          /\ (SourceLabeledRead(label) <=> EmittedLabeledRead(label))
          /\ (SourceFailure <=> __SwiftTLAFunctionArgumentOutsideDomainFailure0)
          /\ (SourceEvaluationOK <=> __SwiftTLAEvaluationOK)
    BY EmittedInitialPreservesSource,
        LoweredReadPreservesSource, EmittedReadPreservesLowering,
        EmittedFailurePreservesLowering, EmittedEvaluationCheckPreservesSource,
        SMT DEF SourceLabeledRead, EmittedLabeledRead,
            SourceFailure, CompiledFailure

THEOREM MissingKeyHasNoSuccessorButReportsFailure ==
    ASSUME key \notin DOMAIN table
    PROVE /\ ~SourceRead
          /\ ~read
          /\ __SwiftTLAFunctionArgumentOutsideDomainFailure0
          /\ ~__SwiftTLAEvaluationOK
    PROOF
    <1>1. ~SourceRead
        BY SMT DEF SourceRead
    <1>2. ~read
        BY <1>1, LoweredReadPreservesSource,
            EmittedReadPreservesLowering, SMT
    <1>3. __SwiftTLAFunctionArgumentOutsideDomainFailure0
        BY SMT DEF __SwiftTLAFunctionArgumentOutsideDomainFailure0
    <1>4. ~__SwiftTLAEvaluationOK
        BY <1>3, SMT DEF __SwiftTLAEvaluationOK
    <1>5. QED BY <1>1, <1>2, <1>3, <1>4

THEOREM OmittedFailureCheckWouldDisagree ==
    ASSUME key \notin DOMAIN table
    PROVE TRUE # __SwiftTLAEvaluationOK
    BY MissingKeyHasNoSuccessorButReportsFailure

===============================================================
