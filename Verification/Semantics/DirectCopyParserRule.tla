---- MODULE DirectCopyParserRule ----
EXTENDS Integers, Sequences, IndexedHistoryRules

\* Reviewed interpretation of the direct #spec fragment:
\* parseAlgorithm extends the inherited TypedFacadeScope with one .variable
\* binding per sharedVar, in syntax order. Each Do reads the scope so far.
\* value(for:) compares
\* SwiftSyntax identifier UTF-8 spelling and picks the last matching entry.
\* No Assign extends the scope. parseAlgorithmStatements and parseAlgorithm
\* each append exactly one result per applicable input, in its original order.
\* registeredStringEnumCase resolves a direct registered String-backed enum
\* and takes its named case with the exact authored String raw value.

ParserSequence(items) ==
    /\ Len(items) \in Nat
    /\ DOMAIN items = 1..Len(items)
    /\ items = [index \in 1..Len(items) |-> items[index]]

ParserName(explicit, spelling) ==
    IF explicit.present THEN explicit.value ELSE spelling

ParserRoot(declaration) == ParserName(declaration.explicit, declaration.binding)

ParserCopyFields(declarations) ==
    {ParserRoot(declarations[index]) : index \in DOMAIN declarations}

DeclaredCopyBindings(declarations, visible) ==
    {declarations[index].binding : index \in 1..visible}

ParserVariableEntry(declaration) ==
    [binding |-> declaration.binding, kind |-> "variable", root |-> ParserRoot(declaration)]

ParserScopeAt(inherited, declarations, count) ==
    [index \in 1..(Len(inherited) + count) |->
        IF index <= Len(inherited) THEN inherited[index]
        ELSE ParserVariableEntry(declarations[index - Len(inherited)])]

LatestParserBinding(scope, binding, index) ==
    /\ index \in DOMAIN scope
    /\ scope[index].binding = binding
    /\ \A later \in DOMAIN scope : later > index => scope[later].binding # binding

ParserScopeValue(scope, binding) ==
    scope[CHOOSE index \in DOMAIN scope : LatestParserBinding(scope, binding, index)]

RegisteredParserCases(enumCases, step) ==
    {entry \in enumCases : entry.enumName = step.enumName /\ entry.caseName = step.caseName}

RegisteredCaseRaw(entry) == ParserName(entry.explicit, entry.caseName)

ParserLabel(enumCases, step) ==
    RegisteredCaseRaw(CHOOSE entry \in RegisteredParserCases(enumCases, step) : TRUE)

ParserCopy(scope, assignment) ==
    [target |-> ParserScopeValue(scope, assignment.targetBinding).root,
     read |-> ParserScopeValue(scope, assignment.readBinding).root]

ParserCopies(scope, step) ==
    [index \in 1..Len(step.copies) |-> ParserCopy(scope, step.copies[index])]

ParserTargets(copies) == {copies[index].target : index \in DOMAIN copies}

ParserCopyRow(declarations, scope, enumCases, step) ==
    LET copies == ParserCopies(scope, step)
    IN [label |-> ParserLabel(enumCases, step), copies |-> copies,
        frame |-> ParserCopyFields(declarations) \ ParserTargets(copies)]

ParserCopyRows(inherited, declarations, enumCases, steps) ==
    [index \in 1..Len(steps) |->
        LET step == steps[index]
            scope == ParserScopeAt(inherited, declarations, step.visible)
        IN ParserCopyRow(declarations, scope, enumCases, step)]

WellBoundDirectCopySyntax(declarations, enumCases, steps) ==
    /\ ParserSequence(declarations)
    /\ ParserSequence(steps)
    /\ \A left, right \in DOMAIN declarations :
        declarations[left].binding = declarations[right].binding => left = right
    /\ \A left, right \in enumCases :
        (left.enumName = right.enumName /\ left.caseName = right.caseName) => left = right
    /\ \A index \in DOMAIN steps :
        LET step == steps[index]
        IN /\ step.visible \in 0..Len(declarations)
           /\ \A earlier \in DOMAIN steps :
                  earlier < index => steps[earlier].visible <= step.visible
           /\ ParserSequence(step.copies)
           /\ RegisteredParserCases(enumCases, step) # {}
           /\ \A position \in DOMAIN step.copies :
                LET assignment == step.copies[position]
                IN /\ assignment.targetBinding \in DeclaredCopyBindings(declarations, step.visible)
                   /\ assignment.readBinding \in DeclaredCopyBindings(declarations, step.visible)

ParserScopeAppends(inherited, declarations) ==
    /\ ParserScopeAt(inherited, declarations, 0) = inherited
    /\ \A next \in DOMAIN declarations :
        ParserScopeAt(inherited, declarations, next) =
            HistoryAppend(ParserScopeAt(inherited, declarations, next - 1),
                          Len(inherited) + next - 1, ParserVariableEntry(declarations[next]))

THEOREM EachSharedDeclarationExtendsTheActualScope ==
    ASSUME NEW inherited, NEW declarations,
           ParserSequence(inherited), ParserSequence(declarations)
    PROVE ParserScopeAppends(inherited, declarations)
    PROOF
    <1>initial. ParserScopeAt(inherited, declarations, 0) = inherited
        BY SMT DEF ParserSequence, ParserScopeAt
    <1>append. ASSUME NEW next \in DOMAIN declarations
               PROVE ParserScopeAt(inherited, declarations, next) =
                   HistoryAppend(ParserScopeAt(inherited, declarations, next - 1),
                                 Len(inherited) + next - 1, ParserVariableEntry(declarations[next]))
        BY SMT DEF ParserSequence, ParserScopeAt, HistoryAppend
    <1>. QED BY <1>initial, <1>append DEF ParserScopeAppends

THEOREM TheLatestMatchingScopeEntryIsUnique ==
    ASSUME NEW scope, NEW binding, NEW left, NEW right,
           LatestParserBinding(scope, binding, left), LatestParserBinding(scope, binding, right),
           DOMAIN scope \subseteq Int
    PROVE left = right
    BY SMT DEF LatestParserBinding

THEOREM ADeclaredBindingResolvesToItsActualScopeEntry ==
    ASSUME NEW inherited, NEW declarations, NEW visible \in 0..Len(declarations),
           NEW position \in 1..visible,
           ParserSequence(inherited), ParserSequence(declarations),
           \A left, right \in DOMAIN declarations :
               declarations[left].binding = declarations[right].binding => left = right
    PROVE LET declaration == declarations[position]
              scope == ParserScopeAt(inherited, declarations, visible)
          IN ParserScopeValue(scope, declaration.binding) = ParserVariableEntry(declaration)
    PROOF
    <1>. DEFINE declaration == declarations[position]
                scope == ParserScopeAt(inherited, declarations, visible)
                actual == Len(inherited) + position
    <1>at. /\ actual \in DOMAIN scope
           /\ scope[actual] = ParserVariableEntry(declaration)
           /\ DOMAIN scope \subseteq Int
        BY SMT DEF scope, actual, declaration, ParserScopeAt, ParserSequence
    <1>later. ASSUME NEW later \in DOMAIN scope, later > actual
               PROVE scope[later].binding # declaration.binding
        <2>bounds. later \in 1..(Len(inherited) + visible)
            BY ONLY (later \in DOMAIN scope), SMT DEF scope, ParserScopeAt
        <2>index. /\ later - Len(inherited) \in DOMAIN declarations
                  /\ later - Len(inherited) > position
            BY ONLY <2>bounds, (later > actual), (position \in 1..visible),
                (visible \in 0..Len(declarations)), ParserSequence(inherited),
                ParserSequence(declarations), SMT DEF actual, ParserSequence
        <2>position. position \in DOMAIN declarations
            BY ONLY (position \in 1..visible), (visible \in 0..Len(declarations)),
                ParserSequence(declarations), SMT DEF ParserSequence
        <2>different. declarations[later - Len(inherited)].binding # declarations[position].binding
            BY <2>index, <2>position, SMT
        <2>scope. scope[later] = ParserVariableEntry(declarations[later - Len(inherited)])
            BY <2>index, SMT DEF scope, ParserScopeAt, ParserSequence
        <2>. QED BY ONLY <2>different, <2>scope, SMT DEF ParserVariableEntry, declaration
    <1>latest. LatestParserBinding(scope, declaration.binding, actual)
        BY <1>at, <1>later, SMT DEF LatestParserBinding, ParserVariableEntry
    <1>choose. (CHOOSE index \in DOMAIN scope : LatestParserBinding(scope, declaration.binding, index)) = actual
        BY <1>at, <1>latest, TheLatestMatchingScopeEntryIsUnique, SMT
    <1>. QED BY <1>at, <1>choose DEF ParserScopeValue

THEOREM EachCopyOperandResolvesToAnAuthoredRoot ==
    ASSUME NEW inherited, NEW declarations, NEW visible \in 0..Len(declarations), NEW binding,
           ParserSequence(inherited), ParserSequence(declarations),
           \A left, right \in DOMAIN declarations :
               declarations[left].binding = declarations[right].binding => left = right,
           binding \in DeclaredCopyBindings(declarations, visible)
    PROVE LET scope == ParserScopeAt(inherited, declarations, visible)
              value == ParserScopeValue(scope, binding)
          IN /\ value.kind = "variable"
             /\ value.root \in ParserCopyFields(declarations)
             /\ \A index \in 1..visible :
                  declarations[index].binding = binding => value.root = ParserRoot(declarations[index])
    PROOF
    <1>. DEFINE value ==
        ParserScopeValue(ParserScopeAt(inherited, declarations, visible), binding)
    <1>found. PICK position \in 1..visible : declarations[position].binding = binding
        BY SMT DEF DeclaredCopyBindings
    <1>resolve. value = ParserVariableEntry(declarations[position])
        BY <1>found, ADeclaredBindingResolvesToItsActualScopeEntry, SMT DEF value
    <1>. QED BY <1>found, <1>resolve, SMT DEF ParserVariableEntry, ParserCopyFields, ParserSequence

THEOREM OneRegisteredCaseSuppliesTheParserLabel ==
    ASSUME NEW enumCases, NEW step,
           RegisteredParserCases(enumCases, step) # {},
           \A left, right \in enumCases :
               (left.enumName = right.enumName /\ left.caseName = right.caseName) => left = right
    PROVE \E entry \in enumCases :
             /\ RegisteredParserCases(enumCases, step) = {entry}
             /\ ParserLabel(enumCases, step) = RegisteredCaseRaw(entry)
    PROOF
    <1>found. PICK entry \in RegisteredParserCases(enumCases, step) : TRUE
        BY SMT
    <1>one. RegisteredParserCases(enumCases, step) = {entry}
        BY <1>found, SMT DEF RegisteredParserCases
    <1>label. ParserLabel(enumCases, step) = RegisteredCaseRaw(entry)
        BY <1>one, SMT DEF ParserLabel
    <1>. QED BY <1>found, <1>one, <1>label, SMT DEF RegisteredParserCases


ParserPrefix(results, count) == [index \in 1..count |-> results[index]]

ParserRowsAppendInOrder(input, results) ==
    /\ DOMAIN results = DOMAIN input
    /\ results = ParserPrefix(results, Len(input))
    /\ ParserPrefix(results, 0) = <<>>
    /\ \A index \in DOMAIN input : ParserPrefix(results, index) =
           HistoryAppend(ParserPrefix(results, index - 1), index - 1, results[index])

THEOREM ParserIterationAppendsOneResultInSourceOrder ==
    ASSUME NEW input, NEW results, ParserSequence(input),
           results = [index \in 1..Len(input) |-> results[index]]
    PROVE ParserRowsAppendInOrder(input, results)
    PROOF
    <1>boundary. /\ DOMAIN results = DOMAIN input
                 /\ results = ParserPrefix(results, Len(input))
                 /\ ParserPrefix(results, 0) = <<>>
        BY SMT DEF ParserPrefix, ParserSequence
    <1>append. ASSUME NEW index \in DOMAIN input
               PROVE ParserPrefix(results, index) =
                   HistoryAppend(ParserPrefix(results, index - 1), index - 1, results[index])
        BY SMT DEF ParserSequence, ParserPrefix, HistoryAppend
    <1>. QED BY <1>boundary, <1>append DEF ParserRowsAppendInOrder

ParserCopyUsesBothBindings(declarations, scope, visible, assignment, copy) ==
    LET target == ParserScopeValue(scope, assignment.targetBinding)
        read == ParserScopeValue(scope, assignment.readBinding)
        keys == ParserCopyFields(declarations)
    IN /\ target.kind = "variable" /\ read.kind = "variable"
       /\ target.root \in keys /\ read.root \in keys
       /\ copy = [target |-> target.root, read |-> read.root]
       /\ \A declared \in 1..visible :
            /\ (declarations[declared].binding = assignment.targetBinding =>
                    copy.target = ParserRoot(declarations[declared]))
            /\ (declarations[declared].binding = assignment.readBinding =>
                    copy.read = ParserRoot(declarations[declared]))

ParserRowUsesAuthoredSyntax(declarations, scope, enumCases, step, row) ==
    /\ \E entry \in enumCases :
           /\ RegisteredParserCases(enumCases, step) = {entry}
           /\ row.label = RegisteredCaseRaw(entry)
    /\ ParserRowsAppendInOrder(step.copies, row.copies)
    /\ row.frame = ParserCopyFields(declarations) \ ParserTargets(row.copies)
    /\ \A position \in DOMAIN step.copies :
           ParserCopyUsesBothBindings(declarations, scope, step.visible,
               step.copies[position], row.copies[position])

THEOREM WellBoundDirectCopySyntaxProducesOrderedRows ==
    ASSUME NEW inherited, NEW declarations, NEW enumCases, NEW steps,
           ParserSequence(inherited), WellBoundDirectCopySyntax(declarations, enumCases, steps)
    PROVE LET rows == ParserCopyRows(inherited, declarations, enumCases, steps)
          IN /\ ParserScopeAppends(inherited, declarations)
             /\ ParserRowsAppendInOrder(steps, rows)
             /\ \A index \in DOMAIN steps :
                   LET step == steps[index]
                       scope == ParserScopeAt(inherited, declarations, step.visible)
                   IN ParserRowUsesAuthoredSyntax(declarations, scope, enumCases, step, rows[index])
    PROOF
    <1>. DEFINE rows == ParserCopyRows(inherited, declarations, enumCases, steps)
    <1>scope. ParserScopeAppends(inherited, declarations)
        BY EachSharedDeclarationExtendsTheActualScope DEF WellBoundDirectCopySyntax
    <1>order. ParserRowsAppendInOrder(steps, rows)
        BY ParserIterationAppendsOneResultInSourceOrder, SMT
            DEF rows, ParserCopyRows, WellBoundDirectCopySyntax
    <1>row. ASSUME NEW index \in DOMAIN steps
             PROVE LET step == steps[index]
                       scope == ParserScopeAt(inherited, declarations, step.visible)
                   IN ParserRowUsesAuthoredSyntax(declarations, scope, enumCases, step, rows[index])
        PROOF
        <2>. DEFINE step == steps[index]
                    scope == ParserScopeAt(inherited, declarations, step.visible)
                    row == rows[index]
        <2>projection. row = ParserCopyRow(declarations, scope, enumCases, step)
            BY SMT DEF rows, scope, step, row, ParserCopyRows,
                WellBoundDirectCopySyntax, ParserSequence
        <2>label. \E entry \in enumCases :
            /\ RegisteredParserCases(enumCases, step) = {entry}
             /\ row.label = RegisteredCaseRaw(entry)
            BY <2>projection, OneRegisteredCaseSuppliesTheParserLabel, SMT
                DEF ParserCopyRow, WellBoundDirectCopySyntax, step
        <2>order. ParserRowsAppendInOrder(step.copies, row.copies)
            BY <2>projection, ParserIterationAppendsOneResultInSourceOrder, SMT
                DEF ParserCopyRow, ParserCopies, WellBoundDirectCopySyntax, step
        <2>frame. row.frame = ParserCopyFields(declarations) \ ParserTargets(row.copies)
            BY <2>projection, SMT DEF ParserCopyRow
        <2>copy. ASSUME NEW position \in DOMAIN step.copies
                  PROVE ParserCopyUsesBothBindings(declarations, scope, step.visible,
                            step.copies[position], row.copies[position])
            PROOF
            <3>. DEFINE assignment == step.copies[position]
                        target == ParserScopeValue(scope, assignment.targetBinding)
                        read == ParserScopeValue(scope, assignment.readBinding)
            <3>target. /\ target.kind = "variable"
                       /\ target.root \in ParserCopyFields(declarations)
                       /\ \A declared \in 1..step.visible :
                            declarations[declared].binding = assignment.targetBinding =>
                               target.root = ParserRoot(declarations[declared])
                BY EachCopyOperandResolvesToAnAuthoredRoot, SMT
                   DEF WellBoundDirectCopySyntax, scope, step, assignment, target
            <3>read. /\ read.kind = "variable"
                     /\ read.root \in ParserCopyFields(declarations)
                     /\ \A declared \in 1..step.visible :
                          declarations[declared].binding = assignment.readBinding =>
                             read.root = ParserRoot(declarations[declared])
                BY EachCopyOperandResolvesToAnAuthoredRoot, SMT
                   DEF WellBoundDirectCopySyntax, scope, step, assignment, read
            <3>position. position \in 1..Len(step.copies)
                BY ONLY (index \in DOMAIN steps), (position \in DOMAIN step.copies),
                    WellBoundDirectCopySyntax(declarations, enumCases, steps), SMT
                    DEF WellBoundDirectCopySyntax, ParserSequence, step
            <3>copies. row.copies = ParserCopies(scope, step)
                BY ONLY <2>projection, SMT DEF ParserCopyRow
            <3>pair. row.copies[position] = [target |-> target.root, read |-> read.root]
                BY ONLY <3>copies, <3>position, SMT DEF ParserCopies, ParserCopy,
                    assignment, target, read
            <3>. QED BY <3>target, <3>read, <3>pair, SMT
                DEF ParserCopyUsesBothBindings, assignment, target, read
        <2>. QED BY <2>label, <2>order, <2>frame, <2>copy, SMT
            DEF ParserRowUsesAuthoredSyntax
    <1>. QED BY <1>scope, <1>order, <1>row

====
