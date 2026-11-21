---- MODULE CertifiedReadAssignmentObservation ----
EXTENDS OrderedIntAssignmentListRule

ReadAssignmentView(read) ==
    [root |-> 1, kinds |-> <<"read">>, literals |-> <<0>>,
     reads |-> <<read>>, left |-> <<0>>, right |-> <<0>>]

ReadAssignmentRow(copy) ==
    [target |-> copy.target, view |-> ReadAssignmentView(copy.read),
     emitted |-> [count |-> 1, height |-> 1, indices |-> <<1>>, origins |-> <<1>>,
                  nodes |-> <<[kind |-> "read", payload |-> copy.read, left |-> 0, right |-> 0]>>],
     inverse |-> <<1>>, fallback |-> copy.read]

ReadAssignmentRows(copies) == [index \in DOMAIN copies |-> ReadAssignmentRow(copies[index])]

TypedCopyRows(copies) ==
    /\ Len(copies) \in Nat
    /\ DOMAIN copies = 1..Len(copies)
    /\ \A index \in DOMAIN copies : copies[index].target \in Keys /\ copies[index].read \in Keys

THEOREM DirectReadSuppliesTheAssignmentCertificate ==
    ASSUME NEW copy, copy.read \in Keys, copy.target \in Keys
    PROVE /\ ReadAssignmentRow(copy).target \in Keys
          /\ AssignmentRhsCertificate(ReadAssignmentRow(copy))
    PROOF
    <1>. DEFINE row == ReadAssignmentRow(copy)
    <1>arrays. NodeEmissionArrays(row.emitted)
        BY SMT DEF row, ReadAssignmentRow, NodeEmissionArrays
    <1>payload. AllNodePayloadsMatchSource(row.view, row.emitted)
        BY SMT DEF row, ReadAssignmentRow, ReadAssignmentView,
           AllNodePayloadsMatchSource, NodePayloadMatchesSource
    <1>typed. TypedVisitedSourceInputs(row.view, row.emitted)
        BY SMT DEF row, ReadAssignmentRow, ReadAssignmentView, TypedVisitedSourceInputs
    <1>. QED BY <1>arrays, <1>payload, <1>typed, SMT
        DEF AssignmentRhsCertificate, LiteralReadAddCertificate, ReadAssignmentRow, ReadAssignmentView, row

THEOREM DirectReadsSupplySupportedIntegerAssignmentRows ==
    ASSUME NEW copies, TypedCopyRows(copies)
    PROVE /\ SupportedAssignmentList(ReadAssignmentRows(copies))
          /\ Len(ReadAssignmentRows(copies)) = Len(copies)
    PROOF
    <1>. DEFINE rows == ReadAssignmentRows(copies)
    <1>shape. /\ DOMAIN rows = 1..Len(copies) /\ Len(copies) \in Nat
        BY SMT DEF rows, ReadAssignmentRows, TypedCopyRows
    <1>. DEFINE values == {rows[index] : index \in DOMAIN rows}
    <1>function. rows \in [1..Len(copies) -> values]
        BY <1>shape, SMT DEF values, rows, ReadAssignmentRows
    <1>sequence. rows \in Seq(values)
        BY <1>shape, <1>function, SeqDef, SMT
    <1>length. Len(rows) = Len(copies)
        BY <1>shape, <1>sequence, LenProperties, SMT
    <1>certificate. \A index \in DOMAIN rows :
          rows[index].target \in Keys /\ AssignmentRhsCertificate(rows[index])
        BY DirectReadSuppliesTheAssignmentCertificate, SMT DEF rows, ReadAssignmentRows, TypedCopyRows
    <1>. QED BY <1>shape, <1>length, <1>certificate, SMT DEF SupportedAssignmentList, rows

THEOREM DirectReadSelectsTheCurrentBinding ==
    ASSUME NEW copy, NEW bindings
    PROVE SourceAssignmentRHS(ReadAssignmentRow(copy), bindings) = Success(bindings[copy.read])
    PROOF
    <1>. DEFINE view == ReadAssignmentView(copy.read)
                outcome == Success(bindings[copy.read])
                meaning == CHOOSE witness : SourceSyntaxHistory(view, bindings, witness)
    <1>witness. SourceSyntaxHistory(view, bindings, <<outcome>>)
        BY SMT DEF SourceSyntaxHistory, view, ReadAssignmentView
    <1>exists. \E witness : SourceSyntaxHistory(view, bindings, witness)
        BY <1>witness, SMT
    <1>chosen. SourceSyntaxHistory(view, bindings, meaning)
        BY <1>exists, SMT DEF meaning
    <1>. QED BY <1>chosen, SMT DEF SourceAssignmentRHS, ReadAssignmentRow, view, outcome, meaning,
        ReadAssignmentView, SourceSyntaxHistory

THEOREM CertifiedDirectReadsHaveExactlyTheSourceCopyBranch ==
    ASSUME NEW copies, TypedCopyRows(copies), NEW before \in AssignmentBindings, NEW after,
           NEW history, AssignmentListHistory(FALSE, before, ReadAssignmentRows(copies), history)
    PROVE /\ \A index \in 0..Len(copies) : history[index].failure = <<>>
          /\ (SourceCopyBranch(Keys, copies, before, after) <=> after = history[Len(copies)].bindings)
    PROOF
    <1>. DEFINE count == Len(copies)
                rows == ReadAssignmentRows(copies)
                states == [index \in 0..count |-> history[index].bindings]
                complete(index) == history[index].failure = <<>>
    <1>shape. /\ count \in Nat /\ Len(rows) = count /\ DOMAIN rows = 1..count
        BY DirectReadsSupplySupportedIntegerAssignmentRows, SMT
           DEF TypedCopyRows, ReadAssignmentRows, count, rows
    <1>start. complete(0) /\ states[0] = before
        BY <1>shape, SMT DEF AssignmentListHistory, AssignmentListStart, complete, states, count, rows
    <1>advance. \A index \in 1..count : complete(index - 1) =>
        /\ complete(index)
        /\ states[index] = CopyReplace(Keys, states[index - 1], copies[index].target,
                                       states[index - 1][copies[index].read])
        PROOF
        <2>. SUFFICES ASSUME NEW index \in 1..count, complete(index - 1)
             PROVE /\ complete(index)
                   /\ states[index] = CopyReplace(Keys, states[index - 1], copies[index].target,
                                                     states[index - 1][copies[index].read])
            OBVIOUS
        <2>row. rows[index] = ReadAssignmentRow(copies[index])
            BY (index \in 1..count), SMT DEF rows, ReadAssignmentRows, TypedCopyRows, count
        <2>rhs. SourceAssignmentRHS(rows[index], history[index - 1].bindings)
                     = Success(history[index - 1].bindings[copies[index].read])
            BY <2>row, DirectReadSelectsTheCurrentBinding, SMT
        <2>step. history[index] = AssignmentListStep(FALSE, history[index - 1], rows[index], index)
            BY <1>shape, (index \in 1..count), SMT DEF AssignmentListHistory, rows
        <2>. QED BY <2>row, <2>rhs, <2>step, <1>shape, (index \in 1..count), complete(index - 1), SMT
                 DEF ReadAssignmentRow, AssignmentListStep, Success, states, complete
    <1>success. \A index \in 0..count : complete(index)
        PROOF
        <2>one. ASSUME NEW index \in 1..count, \A prior \in 0..(index - 1) : complete(prior)
                PROVE complete(index)
            BY ONLY <1>advance, (index \in 1..count), (\A prior \in 0..(index - 1) : complete(prior)), SMT
        <2>. QED BY ONLY <1>shape, <1>start, <2>one, FiniteIndexedPrefixProperty, Isa
    <1>history. SourceCopyStateHistory(Keys, copies, before, states)
        BY <1>start, <1>advance, <1>success, <1>shape, SMT
           DEF SourceCopyStateHistory, AssignmentBindings, states, count
    <1>unique. \A other : SourceCopyStateHistory(Keys, copies, before, other) => other[count] = states[count]
        PROOF
        <2>. SUFFICES ASSUME NEW other, SourceCopyStateHistory(Keys, copies, before, other)
                     PROVE other[count] = states[count]
            OBVIOUS
        <2>. DEFINE agrees(index) == other[index] = states[index]
        <2>start. agrees(0)
            BY <1>history, SMT DEF SourceCopyStateHistory, agrees
        <2>one. ASSUME NEW index \in 1..count, \A prior \in 0..(index - 1) : agrees(prior)
                PROVE agrees(index)
            BY ONLY <1>history, (SourceCopyStateHistory(Keys, copies, before, other)),
                (index \in 1..count), (\A prior \in 0..(index - 1) : agrees(prior)), SMT
                DEF SourceCopyStateHistory, agrees, count
        <2>all. \A index \in 0..count : agrees(index)
            BY ONLY <1>shape, <2>start, <2>one, FiniteIndexedPrefixProperty, Isa
        <2>. QED BY <2>all, <1>shape, SMT DEF agrees
    <1>source. ASSUME after = history[count].bindings
                PROVE SourceCopyBranch(Keys, copies, before, after)
        <2>. WITNESS states
        <2>. QED BY <1>history, <1>shape, (after = history[count].bindings), SMT DEF states, count
    <1>. QED BY <1>source, <1>unique, <1>shape, <1>success, SMT DEF SourceCopyBranch, states, count, complete

====
