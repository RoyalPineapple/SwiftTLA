---- MODULE GeneratedCertificateExpansionRule ----
EXTENDS OrderedIntExpressionRule, Sequences

CompilerGeneratedExpansionSuffix(origin, left, right) ==
    << <<origin, TRUE>>, <<right, FALSE>>, <<left, FALSE>> >>

SwiftExtendPending(array, suffix) ==
    [count |-> array.count + Len(suffix),
     items |-> [offset \in 0..(array.count + Len(suffix) - 1) |->
         IF offset < array.count THEN array.items[offset] ELSE suffix[offset - array.count + 1]]]

GeneratedExpansionCallerStep(storage, suffix) ==
    [storage EXCEPT !.pending = SwiftExtendPending(SwiftArrayRemovingLast(storage.pending), suffix)]

THEOREM ExtendingPendingByTheGeneratedFramesIsThreeAppends ==
    ASSUME NEW array, array.count \in Nat, NEW origin, NEW left, NEW right
    PROVE SwiftExtendPending(array, CompilerGeneratedExpansionSuffix(origin, left, right)) =
          SwiftArrayAppending(SwiftArrayAppending(SwiftArrayAppending(array,
             <<origin, TRUE>>), <<right, FALSE>>), <<left, FALSE>>)
PROOF
<1>. DEFINE suffix == CompilerGeneratedExpansionSuffix(origin, left, right)
            extended == SwiftExtendPending(array, suffix)
            one == SwiftArrayAppending(array, <<origin, TRUE>>)
            two == SwiftArrayAppending(one, <<right, FALSE>>)
            three == SwiftArrayAppending(two, <<left, FALSE>>)
<1>count. /\ extended.count = array.count + 3
          /\ one.count = array.count + 1 /\ two.count = array.count + 2
          /\ three.count = extended.count
    BY ONLY SMT DEF extended, one, two, three, suffix, CompilerGeneratedExpansionSuffix,
        SwiftExtendPending, SwiftArrayAppending
<1>prefix. \A offset \in 0..(array.count-1) :
    /\ extended.items[offset] = array.items[offset]
    /\ three.items[offset] = array.items[offset]
    BY ONLY array.count \in Nat, <1>count, SMT
        DEF extended, one, two, three, SwiftExtendPending, SwiftArrayAppending
<1>last. \A slot \in 1..3 :
    /\ extended.items[array.count + slot - 1] = suffix[slot]
    /\ three.items[array.count + slot - 1] = suffix[slot]
    BY ONLY array.count \in Nat, <1>count, SMT
        DEF extended, one, two, three, SwiftExtendPending, SwiftArrayAppending,
            suffix, CompilerGeneratedExpansionSuffix
<1>items. extended.items = three.items
    BY ONLY array.count \in Nat, <1>count, <1>prefix, <1>last, SMT
        DEF extended, three, SwiftExtendPending, SwiftArrayAppending
<1>. QED BY ONLY <1>count, <1>items, SMT
    DEF extended, three, SwiftExtendPending, SwiftArrayAppending

THEOREM GeneratedSuffixPreservesTheExistingCompilerTraversalStep ==
    ASSUME NEW view, NEW count, CompilerOccurrenceTree(view, count), count <= SwiftIntMax,
           NEW state, CompilerTraversalInvariant(view, state), state.height > 0,
           state.completed.height <= state.current.emitted.count,
           view.kinds[state.pending[state.height].node] = "add", ~state.pending[state.height].expanded
    PROVE LET origin == state.pending[state.height].node
              left == view.left[origin]  right == view.right[origin]
              suffix == CompilerGeneratedExpansionSuffix(origin, left, right)
              old == SwiftCompilerStorage(view, count, state)
              next == CompilerTraversalNext(view, state)
          IN /\ GeneratedExpansionCallerStep(old, suffix) = SwiftCompilerStorage(view, count, next)
             /\ CompilerTraversalInvariant(view, next)
             /\ ReviewedExpansionOperationSafety(view, count, state)
PROOF
<1>. DEFINE frame == state.pending[state.height]
            origin == frame.node
            left == view.left[origin]
            right == view.right[origin]
            suffix == CompilerGeneratedExpansionSuffix(origin, left, right)
            old == SwiftCompilerStorage(view, count, state)
            rest == SwiftArrayRemovingLast(old.pending)
            source == SwiftSourceArray(view, count)
            next == CompilerTraversalNext(view, state)
            expanded == ReviewedSwiftExpansionIteration(old.pending, source, old)
<1>step. /\ ReviewedSwiftCompilerIteration(source, old) = SwiftCompilerStorage(view, count, next)
         /\ ReviewedExpansionOperationSafety(view, count, state)
    BY ONLY ReviewedCompilerIterationDerivesTraversalStep, SMT DEF frame, origin, old, source, next
<1>invariant. CompilerTraversalInvariant(view, next)
    BY ONLY CompilerTraversalStepPreservesInvariantsAndMakesProgress, SMT DEF next
<1>inputs. /\ old.pending.count = state.height
            /\ old.pending.items[state.height - 1] = <<origin, FALSE>>
            /\ source.count = count /\ origin \in 1..count
            /\ source.items[origin - 1] = [kind |-> "add", payload |-> 0, left |-> left, right |-> right]
            /\ rest.count \in Nat /\ rest.count + 3 <= SwiftIntMax
    BY ONLY <1>step, IntegerDomain, SMT DEF old, source, rest, SwiftCompilerStorage,
        SwiftPendingArray, SwiftSourceArray, SwiftArrayRemovingLast, ReviewedExpansionOperationSafety,
        origin, frame, left, right
<1>helper. ReviewedSwiftExpansionHelper(rest, origin, left, right, old) =
           [pending |-> SwiftExtendPending(rest, suffix), control |-> "normal", untouched |-> old]
    BY ONLY <1>inputs, ReviewedHelperDerivesThreeAppends,
        ExtendingPendingByTheGeneratedFramesIsThreeAppends, SMT DEF suffix
<1>whole. ReviewedSwiftCompilerIteration(source, old) = GeneratedExpansionCallerStep(old, suffix)
    BY ONLY <1>inputs, <1>helper, SMT DEF old, source, rest, expanded,
        ReviewedSwiftCompilerIteration, ReviewedSwiftExpansionIteration, GeneratedExpansionCallerStep
<1>. QED BY ONLY <1>step, <1>invariant, <1>whole DEF old, next, suffix, origin, left, right, frame
====
