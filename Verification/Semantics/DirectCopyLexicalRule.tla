---- MODULE DirectCopyLexicalRule ----
EXTENDS DirectCopyParserRule
LOCAL INSTANCE SequenceTheorems_proofs

\* parseAlgorithm appends a shared .variable root, or an immutable direct
\* lexical alias with the value obtained from the already visible scope.
\* A direct alias captures the root identity at its declaration. It adds no
\* AlgorithmComponent and is not a later read of an assigned state value.

CopySharedRoots(operations) ==
    {ParserRoot(operations[index]) :
         index \in {position \in DOMAIN operations : operations[position].kind = "shared"}}

CopyLexicalOperationsAreWellBound(operations) ==
    /\ ParserSequence(operations)
    /\ \A left, right \in DOMAIN operations :
         operations[left].binding = operations[right].binding => left = right
    /\ \A index \in DOMAIN operations :
         LET op == operations[index]
         IN  \/ op.kind = "shared"
             \/ /\ op.kind = "alias"
                /\ \E source \in 1..(index - 1) : operations[source].binding = op.readBinding

CopyAliasSource(operations, index) ==
    CHOOSE source \in 1..(index - 1) : operations[source].binding = operations[index].readBinding

CopyLexicalSteps(operations) ==
    [index \in DOMAIN operations |->
        [prior \in [1..(index - 1) -> CopySharedRoots(operations)] |->
            IF operations[index].kind = "shared" THEN ParserRoot(operations[index])
            ELSE prior[CopyAliasSource(operations, index)]]]

CopyLexicalRootHistory(operations, history) ==
    /\ history \in [1..Len(operations) -> CopySharedRoots(operations)]
    /\ IndexedHistory(CopyLexicalSteps(operations), history, Len(operations))

CopyLexicalRoots(operations) ==
    CHOOSE history : CopyLexicalRootHistory(operations, history)

CopyLexicalDeclarations(operations) ==
    [index \in DOMAIN operations |->
        [binding |-> operations[index].binding,
         explicit |-> [present |-> TRUE, value |-> CopyLexicalRoots(operations)[index]]]]

THEOREM CopyAliasNamesExactlyOneVisibleSource ==
    ASSUME NEW operations, NEW index \in DOMAIN operations,
           CopyLexicalOperationsAreWellBound(operations), operations[index].kind = "alias"
    PROVE LET source == CopyAliasSource(operations, index)
          IN /\ source \in 1..(index - 1)
             /\ operations[source].binding = operations[index].readBinding
             /\ \A other \in 1..(index - 1) :
                  operations[other].binding = operations[index].readBinding => other = source
    PROOF
    <1>exists. \E source \in 1..(index - 1) : operations[source].binding = operations[index].readBinding
        BY ONLY (index \in DOMAIN operations), (operations[index].kind = "alias"),
            CopyLexicalOperationsAreWellBound(operations), SMT DEF CopyLexicalOperationsAreWellBound
    <1>chosen. /\ CopyAliasSource(operations, index) \in 1..(index - 1)
               /\ operations[CopyAliasSource(operations, index)].binding = operations[index].readBinding
        BY ONLY <1>exists, SMT DEF CopyAliasSource
    <1>unique. \A other \in 1..(index - 1) :
            operations[other].binding = operations[index].readBinding => other = CopyAliasSource(operations, index)
        BY ONLY (index \in DOMAIN operations), <1>chosen, CopyLexicalOperationsAreWellBound(operations), SMT
            DEF CopyLexicalOperationsAreWellBound, ParserSequence
    <1>. QED BY ONLY <1>chosen, <1>unique

THEOREM EveryWellBoundLexicalListProducesARootHistory ==
    ASSUME NEW operations, CopyLexicalOperationsAreWellBound(operations)
    PROVE CopyLexicalRootHistory(operations, CopyLexicalRoots(operations))
    PROOF
    <1>. DEFINE count == Len(operations)
                roots == CopySharedRoots(operations)
    <1>shape. /\ count \in Nat /\ DOMAIN operations = 1..count
        BY ONLY CopyLexicalOperationsAreWellBound(operations), SMT
            DEF CopyLexicalOperationsAreWellBound, ParserSequence, count
    <1>returns. ASSUME NEW index \in 1..count
                PROVE CopyLexicalSteps(operations)[index] \in [[1..(index - 1) -> roots] -> roots]
        PROOF
        <2>index. index \in DOMAIN operations
            BY ONLY (index \in 1..count), <1>shape
        <2>shared. CASE operations[index].kind = "shared"
            <3>root. ParserRoot(operations[index]) \in roots
                BY ONLY <2>index, <2>shared, SMT DEF roots, CopySharedRoots
            <3>. QED BY ONLY <2>index, <2>shared, <3>root, SMT DEF CopyLexicalSteps, roots
        <2>alias. CASE operations[index].kind # "shared"
            <3>kind. operations[index].kind = "alias"
                BY ONLY <2>index, <2>alias, CopyLexicalOperationsAreWellBound(operations), SMT
                    DEF CopyLexicalOperationsAreWellBound
            <3>read. CopyAliasSource(operations, index) \in 1..(index - 1)
                BY ONLY <2>index, <3>kind, CopyLexicalOperationsAreWellBound(operations),
                    CopyAliasNamesExactlyOneVisibleSource, SMT
            <3>. QED BY ONLY <2>index, <2>alias, <3>read, SMT DEF CopyLexicalSteps, roots
        <2>. QED BY ONLY <2>shared, <2>alias, SMT
    <1>exists. \E history : CopyLexicalRootHistory(operations, history)
        BY ONLY <1>shape, <1>returns, FiniteIndexedHistoryExists, SMT
            DEF CopyLexicalRootHistory, count, roots
    <1>. QED BY ONLY <1>exists, SMT DEF CopyLexicalRoots

THEOREM TheAliasHistoryUsesTheActualEarlierRoot ==
    ASSUME NEW operations, NEW index \in DOMAIN operations,
           CopyLexicalOperationsAreWellBound(operations)
    PROVE LET op == operations[index]
              roots == CopyLexicalRoots(operations)
          IN /\ op.kind = "shared" => roots[index] = ParserRoot(op)
             /\ op.kind = "alias" => roots[index] = roots[CopyAliasSource(operations, index)]
    PROOF
    <1>. DEFINE roots == CopyLexicalRoots(operations)
                domain == CopySharedRoots(operations)
                prior == HistoryPrefix(roots, index - 1)
    <1>shape. /\ Len(operations) \in Nat /\ DOMAIN operations = 1..Len(operations)
        BY ONLY CopyLexicalOperationsAreWellBound(operations), SMT
            DEF CopyLexicalOperationsAreWellBound, ParserSequence
    <1>history. CopyLexicalRootHistory(operations, roots)
        BY ONLY CopyLexicalOperationsAreWellBound(operations), EveryWellBoundLexicalListProducesARootHistory DEF roots
    <1>typed. prior \in [1..(index - 1) -> domain]
        BY ONLY (index \in DOMAIN operations), <1>shape, <1>history, SMT
            DEF CopyLexicalRootHistory, prior, HistoryPrefix, domain
    <1>step. roots[index] = CopyLexicalSteps(operations)[index][prior]
        BY ONLY (index \in DOMAIN operations), <1>shape, <1>history, SMT
            DEF CopyLexicalRootHistory, IndexedHistory, prior
    <1>shared. CASE operations[index].kind = "shared"
        BY ONLY (index \in DOMAIN operations), <1>typed, <1>step, <1>shared, SMT DEF CopyLexicalSteps, domain
    <1>alias. CASE operations[index].kind = "alias"
        <2>source. CopyAliasSource(operations, index) \in 1..(index - 1)
            BY ONLY (index \in DOMAIN operations), CopyLexicalOperationsAreWellBound(operations),
                <1>alias, CopyAliasNamesExactlyOneVisibleSource, SMT
        <2>. QED BY ONLY (index \in DOMAIN operations), <1>typed, <1>step, <1>alias, <2>source, SMT
            DEF CopyLexicalSteps, prior, HistoryPrefix, domain
    <1>. QED BY ONLY <1>shared, <1>alias, SMT

THEOREM WellBoundCopyLexicalOperationsConstructParserDeclarations ==
    ASSUME NEW operations, CopyLexicalOperationsAreWellBound(operations)
    PROVE LET declarations == CopyLexicalDeclarations(operations)
          IN /\ ParserSequence(declarations)
             /\ Len(declarations) = Len(operations)
             /\ DOMAIN declarations = DOMAIN operations
             /\ \A index \in DOMAIN operations : declarations[index].binding = operations[index].binding
             /\ \A left, right \in DOMAIN declarations :
                  declarations[left].binding = declarations[right].binding => left = right
             /\ ParserCopyFields(declarations) = CopySharedRoots(operations)
             /\ \A index \in DOMAIN operations :
                  operations[index].kind = "shared" =>
                      ParserRoot(declarations[index]) = ParserRoot(operations[index])
    PROOF
    <1>. DEFINE declarations == CopyLexicalDeclarations(operations)
                history == CopyLexicalRoots(operations)
                fields == CopySharedRoots(operations)
    <1>input. /\ Len(operations) \in Nat /\ DOMAIN operations = 1..Len(operations)
        BY ONLY CopyLexicalOperationsAreWellBound(operations), SMT
            DEF CopyLexicalOperationsAreWellBound, ParserSequence
    <1>domain. DOMAIN declarations = DOMAIN operations
        BY ONLY SMT DEF declarations, CopyLexicalDeclarations
    <1>names. \A index \in DOMAIN operations : declarations[index].binding = operations[index].binding
        BY ONLY SMT DEF declarations, CopyLexicalDeclarations
    <1>distinct. \A left, right \in DOMAIN declarations :
            declarations[left].binding = declarations[right].binding => left = right
        BY ONLY CopyLexicalOperationsAreWellBound(operations), <1>domain, <1>names, SMT
            DEF CopyLexicalOperationsAreWellBound
    <1>result. \A index \in DOMAIN operations : ParserRoot(declarations[index]) = history[index]
        BY ONLY SMT DEF declarations, CopyLexicalDeclarations, ParserRoot, ParserName, history
    <1>sequence. /\ ParserSequence(declarations)
                  /\ Len(declarations) = Len(operations)
        <2>. DEFINE values == {declarations[index] : index \in DOMAIN declarations}
        <2>function. declarations \in [1..Len(operations) -> values]
            BY ONLY <1>domain, <1>input, SMT DEF declarations, CopyLexicalDeclarations, values
        <2>seq. declarations \in Seq(values)
            BY ONLY <1>input, <2>function, SeqDef, SMT
        <2>length. Len(declarations) = Len(operations)
            BY ONLY <1>input, <1>domain, <2>seq, LenProperties, SMT
        <2>. QED BY ONLY <1>input, <1>domain, <2>length, SMT
            DEF ParserSequence, declarations, CopyLexicalDeclarations
    <1>shared. \A index \in DOMAIN operations : operations[index].kind = "shared" =>
               ParserRoot(declarations[index]) = ParserRoot(operations[index])
        BY ONLY CopyLexicalOperationsAreWellBound(operations), <1>result,
            TheAliasHistoryUsesTheActualEarlierRoot, SMT DEF history
    <1>root. \A index \in DOMAIN declarations : ParserRoot(declarations[index]) \in fields
        BY ONLY CopyLexicalOperationsAreWellBound(operations), EveryWellBoundLexicalListProducesARootHistory,
            <1>domain, <1>input, <1>result, SMT DEF CopyLexicalRootHistory, history, fields
    <1>fields. ParserCopyFields(declarations) = fields
        BY ONLY <1>root, <1>shared, <1>domain, SMT DEF ParserCopyFields, fields, CopySharedRoots
    <1>. QED BY ONLY <1>sequence, <1>domain, <1>names, <1>distinct, <1>fields, <1>shared DEF fields

THEOREM ADirectAliasExtendsTheEarlierVariableBinding ==
    ASSUME NEW inherited, NEW operations, NEW index \in DOMAIN operations,
           ParserSequence(inherited), CopyLexicalOperationsAreWellBound(operations),
           operations[index].kind = "alias"
    PROVE LET declarations == CopyLexicalDeclarations(operations)
              source == CopyAliasSource(operations, index)
              scope == ParserScopeAt(inherited, declarations, index - 1)
          IN /\ source \in 1..(index - 1)
             /\ ParserScopeValue(scope, operations[index].readBinding) = ParserVariableEntry(declarations[source])
             /\ ParserRoot(declarations[index]) = ParserScopeValue(scope, operations[index].readBinding).root
    PROOF
    <1>. DEFINE declarations == CopyLexicalDeclarations(operations)
                source == CopyAliasSource(operations, index)
                scope == ParserScopeAt(inherited, declarations, index - 1)
    <1>input. /\ source \in 1..(index - 1)
               /\ operations[source].binding = operations[index].readBinding
        BY ONLY (index \in DOMAIN operations), CopyLexicalOperationsAreWellBound(operations),
            (operations[index].kind = "alias"), CopyAliasNamesExactlyOneVisibleSource, SMT DEF source
    <1>derived. /\ ParserSequence(declarations)
                 /\ DOMAIN declarations = DOMAIN operations
                 /\ \A position \in DOMAIN operations : declarations[position].binding = operations[position].binding
                 /\ \A left, right \in DOMAIN declarations :
                      declarations[left].binding = declarations[right].binding => left = right
        BY ONLY CopyLexicalOperationsAreWellBound(operations),
            WellBoundCopyLexicalOperationsConstructParserDeclarations, SMT DEF declarations
    <1>types. /\ index - 1 \in 0..Len(declarations)
               /\ source \in DOMAIN declarations
               /\ declarations[source].binding = operations[index].readBinding
        BY ONLY (index \in DOMAIN operations), <1>input, <1>derived, SMT DEF ParserSequence
    <1>lookup. ParserScopeValue(scope, operations[index].readBinding) = ParserVariableEntry(declarations[source])
        BY ONLY ParserSequence(inherited), <1>types, <1>input, <1>derived,
            ADeclaredBindingResolvesToItsActualScopeEntry, SMT DEF scope
    <1>alias. ParserRoot(declarations[index]) = ParserRoot(declarations[source])
        BY ONLY (index \in DOMAIN operations), (operations[index].kind = "alias"), <1>types, <1>derived,
            CopyLexicalOperationsAreWellBound(operations), TheAliasHistoryUsesTheActualEarlierRoot, SMT
            DEF declarations, CopyLexicalDeclarations, source, ParserRoot, ParserName
    <1>. QED BY ONLY <1>input, <1>lookup, <1>alias, SMT DEF ParserVariableEntry

THEOREM WellBoundAliasedCopySyntaxProducesOrderedRows ==
    ASSUME NEW inherited, NEW operations, NEW enumCases, NEW steps,
           ParserSequence(inherited),
           CopyLexicalOperationsAreWellBound(operations),
           WellBoundDirectCopySyntax(operations, enumCases, steps)
    PROVE LET declarations == CopyLexicalDeclarations(operations)
              rows == ParserCopyRows(inherited, declarations, enumCases, steps)
          IN /\ WellBoundDirectCopySyntax(declarations, enumCases, steps)
             /\ ParserCopyFields(declarations) = CopySharedRoots(operations)
             /\ ParserScopeAppends(inherited, declarations)
             /\ ParserRowsAppendInOrder(steps, rows)
             /\ \A index \in DOMAIN steps :
                    LET step == steps[index]
                        scope == ParserScopeAt(inherited, declarations, step.visible)
                    IN ParserRowUsesAuthoredSyntax(declarations, scope, enumCases, step, rows[index])
             /\ \A index \in DOMAIN operations :
                    LET op == operations[index]
                        scope == ParserScopeAt(inherited, declarations, index - 1)
                    IN op.kind = "alias" =>
                       /\ ParserScopeValue(scope, op.readBinding).kind = "variable"
                       /\ ParserRoot(declarations[index]) = ParserScopeValue(scope, op.readBinding).root
    PROOF
    <1>. DEFINE declarations == CopyLexicalDeclarations(operations)
                rows == ParserCopyRows(inherited, declarations, enumCases, steps)
    <1>shape.
        /\ ParserSequence(declarations)
        /\ Len(declarations) = Len(operations)
        /\ DOMAIN declarations = DOMAIN operations
        /\ \A index \in DOMAIN operations : declarations[index].binding = operations[index].binding
        /\ \A left, right \in DOMAIN declarations :
             declarations[left].binding = declarations[right].binding => left = right
        /\ ParserCopyFields(declarations) = CopySharedRoots(operations)
        BY ONLY CopyLexicalOperationsAreWellBound(operations),
            WellBoundCopyLexicalOperationsConstructParserDeclarations, SMT DEF declarations
    <1>prefix. \A visible \in 0..Len(operations) :
        DeclaredCopyBindings(declarations, visible) = DeclaredCopyBindings(operations, visible)
        <2>. TAKE visible \in 0..Len(operations)
        <2>positions. 1..visible \subseteq DOMAIN operations
            BY ONLY (visible \in 0..Len(operations)), CopyLexicalOperationsAreWellBound(operations), SMT
                DEF CopyLexicalOperationsAreWellBound, ParserSequence
        <2>. QED BY ONLY <1>shape, <2>positions, SMT DEF DeclaredCopyBindings
    <1>inputs. WellBoundDirectCopySyntax(declarations, enumCases, steps)
        BY ONLY WellBoundDirectCopySyntax(operations, enumCases, steps), <1>shape, <1>prefix, SMT
            DEF WellBoundDirectCopySyntax
    <1>parser.
        /\ ParserScopeAppends(inherited, declarations)
        /\ ParserRowsAppendInOrder(steps, rows)
        /\ \A index \in DOMAIN steps :
               LET step == steps[index]
                   scope == ParserScopeAt(inherited, declarations, step.visible)
               IN ParserRowUsesAuthoredSyntax(declarations, scope, enumCases, step, rows[index])
        BY ONLY <1>inputs, ParserSequence(inherited), WellBoundDirectCopySyntaxProducesOrderedRows, SMT
            DEF rows
    <1>aliases. \A index \in DOMAIN operations :
                    LET op == operations[index]
                        scope == ParserScopeAt(inherited, declarations, index - 1)
                    IN op.kind = "alias" =>
                       /\ ParserScopeValue(scope, op.readBinding).kind = "variable"
                       /\ ParserRoot(declarations[index]) = ParserScopeValue(scope, op.readBinding).root
        <2>. TAKE index \in DOMAIN operations
        <2>. DEFINE op == operations[index]
                    scope == ParserScopeAt(inherited, declarations, index - 1)
        <2>. SUFFICES ASSUME op.kind = "alias"
                     PROVE /\ ParserScopeValue(scope, op.readBinding).kind = "variable"
                           /\ ParserRoot(declarations[index]) = ParserScopeValue(scope, op.readBinding).root
            OBVIOUS
        <2>lookup. /\ ParserScopeValue(scope, op.readBinding) =
                           ParserVariableEntry(declarations[CopyAliasSource(operations, index)])
                   /\ ParserRoot(declarations[index]) = ParserScopeValue(scope, op.readBinding).root
            BY ONLY (index \in DOMAIN operations), (op.kind = "alias"), ParserSequence(inherited),
                CopyLexicalOperationsAreWellBound(operations), ADirectAliasExtendsTheEarlierVariableBinding, SMT
                DEF declarations, scope, op
        <2>. QED BY ONLY <2>lookup, SMT DEF ParserVariableEntry
    <1>. QED BY ONLY <1>shape, <1>inputs, <1>parser, <1>aliases

====
