-------------------- MODULE CheckingSelectionRule --------------------
EXTENDS TLAPS, Integers, Sequences

CONSTANT NoPropertyHandle

CatalogMembers(catalog) == {catalog[index] : index \in 1..Len(catalog)}

SourcePropertySelection(declarations, present, handles, only, selected) ==
    {property \in declarations :
        ~only \/ (present[property] /\ handles[property] \in selected)}

LoweredPropertySelection(catalog, references, allocation, only, selected) ==
    {allocation[catalog[index]] : index \in
        {position \in 1..Len(catalog) :
            ~only \/ references[catalog[position]] \in selected}}

OutputPropertySelection(declarations, allocation, names, selected) ==
    {names[property] : property \in
        {declaration \in declarations : allocation[declaration] \in selected}}

FaithfulPropertyCatalog(catalog, declarations, present, handles, references, allocation) ==
    /\ CatalogMembers(catalog) = declarations
    /\ \A property \in declarations :
        references[property] =
            IF present[property] THEN handles[property] ELSE NoPropertyHandle
    /\ \A first, second \in declarations :
        allocation[first] = allocation[second] => first = second

THEOREM CatalogSelectionPreservesIdentity ==
    ASSUME NEW declarations, NEW handleValues, NEW compiledIDs,
           NoPropertyHandle \notin handleValues,
           NEW catalog \in Seq(declarations),
           NEW present \in [declarations -> BOOLEAN],
           NEW handles \in [declarations -> (handleValues \cup {NoPropertyHandle})],
           NEW references \in [declarations -> (handleValues \cup {NoPropertyHandle})],
           NEW allocation \in [declarations -> compiledIDs],
           FaithfulPropertyCatalog(catalog, declarations, present, handles, references, allocation),
           NEW only \in BOOLEAN, NEW selected \in SUBSET handleValues,
           NEW property \in declarations
    PROVE allocation[property] \in
              LoweredPropertySelection(catalog, references, allocation, only, selected)
          <=> property \in SourcePropertySelection(declarations, present, handles, only, selected)
    BY SMT DEF FaithfulPropertyCatalog, CatalogMembers,
        LoweredPropertySelection, SourcePropertySelection

THEOREM BothOutputProjectionsPreserveSelection ==
    ASSUME NEW declarations, NEW handleValues, NEW compiledIDs,
           NEW nativeNames, NEW formalNames,
           NoPropertyHandle \notin handleValues,
           NEW catalog \in Seq(declarations),
           NEW present \in [declarations -> BOOLEAN],
           NEW handles \in [declarations -> (handleValues \cup {NoPropertyHandle})],
           NEW references \in [declarations -> (handleValues \cup {NoPropertyHandle})],
           NEW allocation \in [declarations -> compiledIDs],
           NEW native \in [declarations -> nativeNames],
           NEW formal \in [declarations -> formalNames],
           FaithfulPropertyCatalog(catalog, declarations, present, handles, references, allocation),
           NEW only \in BOOLEAN, NEW selected \in SUBSET handleValues
    PROVE /\ OutputPropertySelection(declarations, allocation, native,
                  LoweredPropertySelection(catalog, references, allocation, only, selected))
                 = {native[property] : property \in
                     SourcePropertySelection(declarations, present, handles, only, selected)}
          /\ OutputPropertySelection(declarations, allocation, formal,
                  LoweredPropertySelection(catalog, references, allocation, only, selected))
                 = {formal[property] : property \in
                     SourcePropertySelection(declarations, present, handles, only, selected)}
    PROOF
    <1>1. \A property \in declarations :
        allocation[property] \in LoweredPropertySelection(catalog, references, allocation, only, selected)
        <=> property \in SourcePropertySelection(declarations, present, handles, only, selected)
        BY CatalogSelectionPreservesIdentity
    <1>. QED BY <1>1, SMT DEF OutputPropertySelection, SourcePropertySelection

THEOREM OmittedAndExplicitEmptySelections ==
    ASSUME NEW declarations, NEW present \in [declarations -> BOOLEAN], NEW handles
    PROVE /\ SourcePropertySelection(declarations, present, handles, FALSE, {}) = declarations
          /\ SourcePropertySelection(declarations, present, handles, TRUE, {}) = {}
    BY SMT DEF SourcePropertySelection

SourceDeadlockSelection(default, overrides, enabled) ==
    (overrides = <<>> /\ enabled = default) \/ overrides = <<enabled>>

LoweredDeadlockSelection(default, overrides) ==
    IF Len(overrides) = 0 THEN default ELSE overrides[1]

THEOREM DeadlockOverridePreservesTheUniqueSourceChoice ==
    ASSUME NEW default \in BOOLEAN, NEW overrides \in Seq(BOOLEAN),
           Len(overrides) <= 1, NEW enabled \in BOOLEAN
    PROVE SourceDeadlockSelection(default, overrides, enabled)
          <=> enabled = LoweredDeadlockSelection(default, overrides)
    BY SMT DEF SourceDeadlockSelection, LoweredDeadlockSelection

PropertyImage(projection, selected) == {projection[property] : property \in selected}

THEOREM InjectivePropertyProjectionReflectsMembership ==
    ASSUME NEW declarations, NEW names, NEW projection \in [declarations -> names],
           \A first, second \in declarations : projection[first] = projection[second] => first = second,
           NEW selected \in SUBSET declarations, NEW property \in declarations
    PROVE projection[property] \in PropertyImage(projection, selected)
          <=> property \in selected
    BY SMT DEF PropertyImage

THEOREM InjectivePropertyProjectionReflectsSelection ==
    ASSUME NEW declarations, NEW names, NEW projection \in [declarations -> names],
           \A first, second \in declarations : projection[first] = projection[second] => first = second,
           NEW left \in SUBSET declarations, NEW right \in SUBSET declarations
    PROVE (PropertyImage(projection, left) = PropertyImage(projection, right)) <=> left = right
    PROOF
    <1>1. \A property \in declarations :
        (projection[property] \in PropertyImage(projection, left) <=> property \in left)
        /\ (projection[property] \in PropertyImage(projection, right) <=> property \in right)
        BY InjectivePropertyProjectionReflectsMembership
    <1>2. (PropertyImage(projection, left) = PropertyImage(projection, right))
        => (\A property : property \in left <=> property \in right)
        BY <1>1, SMT
    <1>3. (PropertyImage(projection, left) = PropertyImage(projection, right)) => left = right
        BY <1>2, SetExtensionality
    <1>. QED BY <1>3, SMT
=============================================================================
