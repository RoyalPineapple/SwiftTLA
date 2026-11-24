---- MODULE CompilerExpansionUsesGeneratedPass ----
EXTENDS GeneratedCertificateExpansionRule, OrderedIntTraversalNativeRule, OrderedIntTraversalPassConfiguredProof

\* CallerInputPage1 CallerInputPage2 CallerInputPage3

ActualGeneratedSingleton(origin, left, right) ==
    NativeTraversalReturnedField(<< <<origin, FALSE>> >>, left, right, 1)

THEOREM InstalledGeneratedSingletonPushesInCompilerOrder ==
    ASSUME NEW origin \in SeedIntValues, NEW left \in SeedIntValues, NEW right \in SeedIntValues
    PROVE LET one == << <<origin, FALSE>> >>
              actual == ActualGeneratedSingleton(origin, left, right)
          IN /\ NativeTraversalStep(one, left, right, actual, left, right)
             /\ actual = CompilerGeneratedExpansionSuffix(origin, left, right)
PROOF
<1>. DEFINE one == << <<origin, FALSE>> >>
            actual == ActualGeneratedSingleton(origin, left, right)
<1>one. /\ one \in Seq(SeedFrames) /\ Len(one) = 1 /\ SeedExpansionEnabled(one)
    BY ONLY origin \in SeedIntValues, SeqDef, SMT DEF one, SeedFrames, SeedExpansionEnabled
<1>functions. /\ NativeTraversalEnabled(one)
              /\ NativeTraversalExpandedPending(one, left, right) = SeedExpandedPending(one, left, right)
    BY ONLY <1>one, left \in SeedIntValues, right \in SeedIntValues, NativeSeedTraversalAgreesWithSeedReplacement, SMT
<1>shape. /\ SeedExpandedPending(one, left, right) \in Seq(SeedFrames)
          /\ Len(SeedExpandedPending(one, left, right)) = 3
          /\ SeedExpandedPending(one, left, right)[1] = <<origin, TRUE>>
          /\ SeedExpandedPending(one, left, right)[2] = <<right, FALSE>>
          /\ SeedExpandedPending(one, left, right)[3] = <<left, FALSE>>
    BY ONLY <1>one, left \in SeedIntValues, right \in SeedIntValues,
        SeedPendingExpansionRetainsPrefixAndPushOrder, SMT DEF one
<1>suffix. SeedExpandedPending(one, left, right) = CompilerGeneratedExpansionSuffix(origin, left, right)
    BY ONLY <1>shape, LenProperties, SeqDef, SMT DEF CompilerGeneratedExpansionSuffix
<1>. QED BY ONLY <1>functions, <1>suffix, SMT DEF actual, ActualGeneratedSingleton,
    NativeTraversalStep, NativeTraversalReturnedField, NativeStackReturnedSlots

THEOREM GeneratedSingletonAndRenderedExpansionSupplyTheSameFrames ==
    ASSUME NEW origin \in SeedIntValues, SeedExpansionInput, pending = << <<origin, FALSE>> >>
    PROVE /\ ActualGeneratedSingleton(origin, leftChild, rightChild) =
                   CompilerGeneratedExpansionSuffix(origin, leftChild, rightChild)
          /\ (Next <=> /\ pending' = ActualGeneratedSingleton(origin, leftChild, rightChild)
                       /\ UNCHANGED <<leftChild, rightChild>>)
          /\ SeedAuthoredExpansionFailures = <<>>
          /\ SeedRenderedExpansionFailures = <<>>
          /\ SeedTraversalHelperCallsAreSafe
          /\ ActualSeedExpansionCFG = SeedExpansionCFG
PROOF
<1>type. /\ leftChild \in SeedIntValues /\ rightChild \in SeedIntValues
    BY ONLY SeedExpansionInput DEF SeedExpansionInput
<1>enabled. NativeTraversalEnabled(pending)
    BY ONLY <1>type, origin \in SeedIntValues, pending = << <<origin, FALSE>> >>,
        InstalledGeneratedSingletonPushesInCompilerOrder, SMT DEF NativeTraversalStep
<1>suffix. ActualGeneratedSingleton(origin, leftChild, rightChild) =
                 CompilerGeneratedExpansionSuffix(origin, leftChild, rightChild)
    BY ONLY origin \in SeedIntValues, <1>type, InstalledGeneratedSingletonPushesInCompilerOrder, SMT
<1>physical. expand <=> /\ pending' = ActualGeneratedSingleton(origin, leftChild, rightChild)
                         /\ UNCHANGED <<leftChild, rightChild>>
    BY ONLY <1>enabled, pending = << <<origin, FALSE>> >>, SeedExpansionInput,
        NativeAndRenderedSeedVisitTheSameExpansion, SMT DEF NativeTraversalStep, ActualGeneratedSingleton,
            NativeTraversalReturnedField, NativeStackReturnedSlots
<1>configured. /\ (Next <=> expand)
                 /\ SeedAuthoredExpansionFailures = <<>>
                 /\ SeedRenderedExpansionFailures = <<>>
                 /\ SeedTraversalHelperCallsAreSafe
                 /\ ActualSeedExpansionCFG = SeedExpansionCFG
    BY ONLY SeedExpansionInput, ConfiguredSeedUsesTheTypedExpansion,
        ActualSeedExpansionPreservesThePendingReplacement, SMT
<1>. QED BY ONLY <1>suffix, <1>physical, <1>configured, SMT

GeneratedCompilerIteration(source, storage) ==
    IF storage.pending.count = 0 THEN ReviewedSwiftCompilerIteration(source, storage)
    ELSE LET frame == storage.pending.items[storage.pending.count - 1]
         IN IF frame[1] \notin 1..source.count
               THEN ReviewedSwiftCompilerIteration(source, storage)
            ELSE LET row == source.items[frame[1] - 1]
                 IN IF row.kind = "add" /\ ~frame[2]
                       THEN GeneratedExpansionCallerStep(storage, ActualGeneratedSingleton(frame[1], row.left, row.right))
                    ELSE ReviewedSwiftCompilerIteration(source, storage)

THEOREM GeneratedCompilerIterationPreservesTheCertificateConstruction ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count), count <= SwiftIntMax, SwiftIntMax = SeedIntMax,
           NEW state, CompilerTraversalInvariant(view, state), state.height > 0,
           state.completed.height <= state.current.emitted.count
    PROVE GeneratedCompilerIteration(SwiftSourceArray(view, count), SwiftCompilerStorage(view, count, state)) =
          SwiftCompilerStorage(view, count, CompilerTraversalNext(view, state))
PROOF
<1>. DEFINE frame == state.pending[state.height]
            origin == frame.node
            left == view.left[origin]
            right == view.right[origin]
            storage == SwiftCompilerStorage(view, count, state)
            source == SwiftSourceArray(view, count)
            next == CompilerTraversalNext(view, state)
            expands == view.kinds[origin] = "add" /\ ~frame.expanded
<1>domain. /\ origin \in 1..count /\ count \in Nat
    BY ONLY PendingCompilerFramesHaveFreshEmissionOrigins, SMT
        DEF origin, frame, CompilerTraversalInvariant, CompilerOccurrenceTree
<1>selection. /\ storage.pending.count = state.height
               /\ storage.pending.items[state.height - 1] = <<origin, frame.expanded>>
               /\ source.count = count
               /\ source.items[origin - 1].kind = view.kinds[origin]
    BY ONLY <1>domain, state.height > 0, SMT DEF storage, source, SwiftCompilerStorage, SwiftPendingArray,
        SwiftSourceArray, origin, frame
<1>reviewed. ReviewedSwiftCompilerIteration(source, storage) = SwiftCompilerStorage(view, count, next)
    BY ONLY ReviewedCompilerIterationDerivesTraversalStep, SMT DEF storage, source, next
<1>expand. CASE expands
    PROOF
    <2>inputs. /\ origin \in SeedIntValues /\ left \in SeedIntValues /\ right \in SeedIntValues
               /\ source.items[origin-1].left = left /\ source.items[origin-1].right = right
        BY ONLY <1>domain, <1>expand, CompilerOccurrenceTree(view, count), count <= SwiftIntMax,
            SwiftIntMax = SeedIntMax, SMT DEF expands, origin, left, right, source, SwiftSourceArray,
            CompilerOccurrenceTree, SeedIntValues, SeedIntMin
    <2>native. ActualGeneratedSingleton(origin, left, right) = CompilerGeneratedExpansionSuffix(origin, left, right)
        BY ONLY <2>inputs, InstalledGeneratedSingletonPushesInCompilerOrder, SMT
    <2>existing. GeneratedExpansionCallerStep(storage, CompilerGeneratedExpansionSuffix(origin, left, right)) =
                 SwiftCompilerStorage(view, count, next)
        BY ONLY <1>expand, GeneratedSuffixPreservesTheExistingCompilerTraversalStep, SMT
            DEF expands, origin, frame, left, right, storage, next
    <2>. QED BY ONLY <1>domain, <1>selection, <1>expand, <2>inputs, <2>native, <2>existing, SMT
        DEF GeneratedCompilerIteration, expands, storage, source, next
<1>emit. CASE ~expands
    BY ONLY <1>domain, <1>selection, <1>emit, <1>reviewed, state.height > 0, SMT
        DEF GeneratedCompilerIteration, expands, storage, source, next
<1>. QED BY ONLY <1>expand, <1>emit

THEOREM GeneratedExpansionRunsInTheExistingFourArrayTraversal ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count), count <= SwiftIntMax, SwiftIntMax = SeedIntMax,
           NEW steps, NEW history, CompilerTraversalPrefix(view, steps, history)
    PROVE LET storage == [step \in 0..steps |-> SwiftCompilerStorage(view, count, history[step])]
              source == SwiftSourceArray(view, count)
          IN /\ storage[0] = ReviewedSwiftTraversalInitialization(source)
             /\ \A step \in 1..steps : storage[step] = GeneratedCompilerIteration(source, storage[step-1])
             /\ \A step \in 0..steps : ReviewedSwiftCertificateReturn(source, storage[step]).control = "return" =>
                  ReviewedSwiftCertificateReturn(source, storage[step]).certificate =
                     [source |-> source, nodes |-> storage[step].nodes,
                      origins |-> storage[step].origins, indices |-> storage[step].indices]
PROOF
<1>. DEFINE storage == [step \in 0..steps |-> SwiftCompilerStorage(view, count, history[step])]
            source == SwiftSourceArray(view, count)
<1>bounds. \A step \in 0..steps :
              /\ CompilerTraversalInvariant(view, history[step])
              /\ history[step].completed.height <= history[step].current.emitted.count
    BY ONLY CompilerTraversalPrefixesDeriveStorageBounds, SMT
<1>initial. storage[0] = ReviewedSwiftTraversalInitialization(source)
    BY ONLY CompilerTraversalPrefixesExecuteTheReviewedSwiftLoop, SMT
        DEF storage, source, CompilerTraversalPrefix
<1>iteration. \A step \in 1..steps : storage[step] = GeneratedCompilerIteration(source, storage[step-1])
    PROOF
    <2>. SUFFICES ASSUME NEW step \in 1..steps
         PROVE storage[step] = GeneratedCompilerIteration(source, storage[step-1])
        BY ONLY SMT
    <2>inputs. /\ step \in 0..steps /\ step-1 \in 0..steps
                /\ history[step-1].height > 0
                /\ history[step] = CompilerTraversalNext(view, history[step-1])
        BY ONLY CompilerTraversalPrefix(view, steps, history), step \in 1..steps, SMT
            DEF CompilerTraversalPrefix
    <2>. QED BY ONLY <1>bounds, <2>inputs, GeneratedCompilerIterationPreservesTheCertificateConstruction, SMT
        DEF storage, source
<1>return. \A step \in 0..steps : ReviewedSwiftCertificateReturn(source, storage[step]).control = "return" =>
            ReviewedSwiftCertificateReturn(source, storage[step]).certificate =
                [source |-> source, nodes |-> storage[step].nodes,
                 origins |-> storage[step].origins, indices |-> storage[step].indices]
    BY ONLY SMT DEF ReviewedSwiftCertificateReturn
<1>. QED BY ONLY <1>initial, <1>iteration, <1>return DEF storage, source

THEOREM SupportedInputReturnsAFourArrayCertificateUsingTheGeneratedExpansion ==
    ASSUME NEW root, NEW terms, NEW syntax, NEW weight, NEW bound,
           SupportedAllocationInput(root, terms, syntax, weight, bound), weight[root] <= SwiftIntMax,
           SwiftIntMax = SeedIntMax, NEW fallback \in Keys
    PROVE \E allocationSteps, allocationHistory, steps, history, storage :
        /\ CompilerAllocationCompletion(syntax, weight, InitialCompilerAllocation(root, weight),
               allocationSteps, allocationHistory)
        /\ LET allocated == allocationHistory[allocationSteps]
               view == AllocatedSourceView(allocated)
               source == SwiftSourceArray(view, allocated.count)
               final == history[steps]
           IN /\ CompilerTraversalCompletion(view, InitialCompilerTraversal(view), steps, history)
              /\ storage[0] = ReviewedSwiftTraversalInitialization(source)
              /\ \A step \in 1..steps : storage[step] = GeneratedCompilerIteration(source, storage[step-1])
              /\ ReviewedSwiftCertificateReturn(source, storage[steps]) =
                   [control |-> "return", certificate |-> [source |-> source, nodes |-> storage[steps].nodes,
                       origins |-> storage[steps].origins, indices |-> storage[steps].indices]]
              /\ LiteralReadAddCertificate(view, final.current.emitted, final.current.inverse, fallback, bound)
PROOF
<1>allocation. PICK allocationSteps, allocationHistory :
    /\ CompilerAllocationCompletion(syntax, weight, InitialCompilerAllocation(root, weight),
           allocationSteps, allocationHistory)
    /\ CompilerOccurrenceTree(AllocatedSourceView(allocationHistory[allocationSteps]),
           allocationHistory[allocationSteps].count)
    /\ CertificateSource(AllocatedSourceView(allocationHistory[allocationSteps]), bound)
    /\ allocationHistory[allocationSteps].count = weight[root]
    BY ONLY ActualAllocationConstructsTheTraversalSource, SupportedAllocationInput(root, terms, syntax, weight, bound), SMT
<1>. DEFINE allocated == allocationHistory[allocationSteps]
            view == AllocatedSourceView(allocated)
            source == SwiftSourceArray(view, allocated.count)
<1>capacity. /\ CompilerOccurrenceTree(view, allocated.count)
              /\ allocated.count <= SwiftIntMax /\ CertificateSource(view, bound)
    BY ONLY <1>allocation, weight[root] <= SwiftIntMax, SMT DEF allocated, view
<1>returned. PICK steps, history, storage :
    /\ CompilerTraversalCompletion(view, InitialCompilerTraversal(view), steps, history)
    /\ storage = [step \in 0..steps |-> SwiftCompilerStorage(view, allocated.count, history[step])]
    /\ ReviewedCompilerTraversalExecution(view, allocated.count, steps, storage)
    BY ONLY <1>capacity, OccurrenceTreeTraversalExecutesTheReviewedSwiftAndReturnsAValidCertificate, SMT
<1>shape. /\ CompilerTraversalPrefix(view, steps, history) /\ steps \in 0..steps
    BY ONLY <1>returned, SMT DEF CompilerTraversalPrefix, CompilerTraversalCompletion
<1>certificate. LiteralReadAddCertificate(view, history[steps].current.emitted,
                       history[steps].current.inverse, fallback, bound)
    BY ONLY <1>capacity, <1>returned, fallback \in Keys, TerminatedCompilerTraversalSuppliesTheCertificate, SMT
<1>loop. /\ storage[0] = ReviewedSwiftTraversalInitialization(source)
         /\ \A step \in 1..steps : storage[step] = GeneratedCompilerIteration(source, storage[step-1])
         /\ \A step \in 0..steps : ReviewedSwiftCertificateReturn(source, storage[step]).control = "return" =>
                 ReviewedSwiftCertificateReturn(source, storage[step]).certificate =
                   [source |-> source, nodes |-> storage[step].nodes,
                    origins |-> storage[step].origins, indices |-> storage[step].indices]
    BY ONLY <1>returned, <1>capacity, <1>shape, SwiftIntMax = SeedIntMax, GeneratedExpansionRunsInTheExistingFourArrayTraversal, SMT
        DEF source, allocated, view
<1>control. ReviewedSwiftCertificateReturn(source, storage[steps]).control = "return"
    BY ONLY <1>returned, SMT DEF ReviewedCompilerTraversalExecution, source, allocated, view
<1>result. ReviewedSwiftCertificateReturn(source, storage[steps]) =
               [control |-> "return", certificate |-> [source |-> source, nodes |-> storage[steps].nodes,
                   origins |-> storage[steps].origins, indices |-> storage[steps].indices]]
    BY ONLY <1>control, <1>loop, <1>returned, <1>shape, SMT
        DEF ReviewedReturnMatchesCertificate, source, allocated, view
<1>. QED BY ONLY <1>allocation, <1>loop, <1>returned, <1>certificate, <1>result, SMT DEF source, allocated, view
====
