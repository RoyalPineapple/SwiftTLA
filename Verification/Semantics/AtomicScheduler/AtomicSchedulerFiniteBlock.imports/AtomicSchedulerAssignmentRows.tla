---- MODULE AtomicSchedulerAssignmentRows ----
EXTENDS OrderedIntAssignmentListRule

\* rhs is the reviewed constructor encoding of the actual typed StateExpr:
\* integer literal, root read, or add with its two ordered children.
SchedulerSupportedAssignmentStatement(statement) ==
    /\ statement.kind = "rootSet"
    /\ statement.target \in Keys
    /\ \E derivation, sizes :
        /\ AllocationConstructorDerivation(statement.rhs, Keys, derivation)
        /\ AllocationConstructorSizes(derivation, sizes)
        /\ sizes[derivation.count] <= SwiftIntMax

SchedulerAssignmentRhsRow(target, actual) ==
    [target |-> target,
     view |-> SwiftSourceArrayAsView(actual.source),
     emitted |-> SwiftCertificateArraysAsEmission(actual),
     inverse |-> SwiftArrayAsHistory(actual.indices),
     fallback |-> target]

SchedulerAssignmentRhsInvocation(statement, actual) ==
    \E terms, weight :
        LET syntax == AllocationTermSyntax(terms)
        IN /\ SupportedAllocationInput(statement.rhs, terms, syntax, weight, Keys)
           /\ weight[statement.rhs] <= SwiftIntMax
           /\ ReviewedOrderedIntCertificateInvocation(statement.rhs, Keys, syntax, weight, actual)

THEOREM ActualAssignmentRhsCompilerReturnsASupportedRow ==
    ASSUME NEW statement, SchedulerSupportedAssignmentStatement(statement)
    PROVE /\ \E actual : SchedulerAssignmentRhsInvocation(statement, actual)
          /\ \A actual : SchedulerAssignmentRhsInvocation(statement, actual) =>
                AssignmentRhsCertificate(SchedulerAssignmentRhsRow(statement.target, actual))
PROOF
<1>. DEFINE rhs == statement.rhs
<1>source. PICK derivation, sizes :
        /\ AllocationConstructorDerivation(rhs, Keys, derivation)
        /\ AllocationConstructorSizes(derivation, sizes)
        /\ sizes[derivation.count] <= SwiftIntMax
    BY ONLY SchedulerSupportedAssignmentStatement(statement) DEF rhs, SchedulerSupportedAssignmentStatement
<1>allocation. PICK terms, weight :
        /\ terms = {derivation.terms[index] : index \in 1..derivation.count}
        /\ SupportedAllocationInput(rhs, terms, AllocationTermSyntax(terms), weight, Keys)
        /\ weight[rhs] = sizes[derivation.count]
    BY ONLY <1>source, CheckedSourceSizesSupplyTheCanonicalAllocationInput
<1>bound. weight[rhs] <= SwiftIntMax
    BY ONLY <1>source, <1>allocation, SMT
<1>readBound. Keys \subseteq Keys
    BY SMT
<1>result. PICK result :
        /\ ReviewedOrderedIntCertificateInvocation(rhs, Keys, AllocationTermSyntax(terms), weight, result)
        /\ \A other : ReviewedOrderedIntCertificateInvocation(rhs, Keys, AllocationTermSyntax(terms), weight, other)
                     => other = result
    BY ONLY <1>bound, <1>allocation, <1>readBound, SupportedInputHasExactlyOneReviewedCompilerResult, SMTT(20)
<1>exists. \E actual : SchedulerAssignmentRhsInvocation(statement, actual)
    <2>. WITNESS result
    <2>. SUFFICES
        \E inputs, sizes :
            /\ SupportedAllocationInput(rhs, inputs, AllocationTermSyntax(inputs), sizes, Keys)
            /\ sizes[rhs] <= SwiftIntMax
            /\ ReviewedOrderedIntCertificateInvocation(rhs, Keys, AllocationTermSyntax(inputs), sizes, result)
        BY DEF SchedulerAssignmentRhsInvocation, rhs
    <2>. WITNESS terms, weight
    <2>. QED BY ONLY <1>allocation, <1>bound, <1>result
<1>arbitrary. \A actual : SchedulerAssignmentRhsInvocation(statement, actual) =>
                        AssignmentRhsCertificate(SchedulerAssignmentRhsRow(statement.target, actual))
    <2>. SUFFICES ASSUME NEW actual, SchedulerAssignmentRhsInvocation(statement, actual)
                  PROVE AssignmentRhsCertificate(SchedulerAssignmentRhsRow(statement.target, actual))
        OBVIOUS
    <2>target. statement.target \in Keys
        BY ONLY SchedulerSupportedAssignmentStatement(statement) DEF SchedulerSupportedAssignmentStatement
    <2>actual. PICK inputs, weights :
            /\ SupportedAllocationInput(rhs, inputs, AllocationTermSyntax(inputs), weights, Keys)
            /\ weights[rhs] <= SwiftIntMax
            /\ ReviewedOrderedIntCertificateInvocation(rhs, Keys, AllocationTermSyntax(inputs), weights, actual)
        BY ONLY SchedulerAssignmentRhsInvocation(statement, actual) DEF SchedulerAssignmentRhsInvocation, rhs
    <2>certified. LiteralReadAddCertificate(SwiftSourceArrayAsView(actual.source),
          SwiftCertificateArraysAsEmission(actual), SwiftArrayAsHistory(actual.indices),
          statement.target, Keys)
        BY ONLY <2>target, <2>actual, ActualReviewedCompilerResultSuppliesInitializerCertificate, SMT
    <2>. QED BY ONLY <2>certified DEF AssignmentRhsCertificate, SchedulerAssignmentRhsRow
<1>. QED BY ONLY <1>exists, <1>arbitrary

THEOREM ActualAssignmentRhsSourceArrayHasTheOccurrenceTree ==
    ASSUME NEW statement, NEW actual, SchedulerAssignmentRhsInvocation(statement, actual)
    PROVE CompilerOccurrenceTree(SwiftSourceArrayAsView(actual.source), actual.source.count)
PROOF
<1>. DEFINE rhs == statement.rhs
<1>inputs. PICK terms, weight :
        /\ SupportedAllocationInput(rhs, terms, AllocationTermSyntax(terms), weight, Keys)
        /\ ReviewedOrderedIntCertificateInvocation(rhs, Keys, AllocationTermSyntax(terms), weight, actual)
    BY ONLY SchedulerAssignmentRhsInvocation(statement, actual) DEF SchedulerAssignmentRhsInvocation, rhs
<1>. DEFINE syntax == AllocationTermSyntax(terms)
            initial == InitialCompilerAllocation(rhs, weight)
<1>execution. PICK count, history, steps, execution :
        /\ CompilerAllocationCompletion(syntax, weight, initial, count, history)
        /\ LET allocated == history[count]
               view == AllocatedSourceView(allocated)
           IN /\ ReviewedCompilerTraversalExecution(view, allocated.count, steps, execution)
              /\ actual = ReviewedSwiftCertificateReturn(SwiftSourceArray(view, allocated.count),
                                                          execution[steps]).certificate
    BY ONLY <1>inputs, SMT DEF ReviewedOrderedIntCertificateInvocation, syntax, initial
<1>. DEFINE allocated == history[count]
            view == AllocatedSourceView(allocated)
            source == SwiftSourceArray(view, allocated.count)
            result == ReviewedSwiftCertificateReturn(source, execution[steps])
<1>initialized. CompilerAllocationInvariant(rhs, terms, syntax, weight, Keys, initial)
    BY ONLY <1>inputs, CompilerAllocationStartsWithItsLoopInvariant DEF syntax, initial
<1>finished. /\ allocated.position = allocated.count
             /\ CompilerAllocationInvariant(rhs, terms, syntax, weight, Keys, allocated)
    BY ONLY <1>inputs, <1>initialized, <1>execution, AllocationCompletionRetainsEveryLoopInvariant, SMT
        DEF CompilerAllocationCompletion, syntax, allocated
<1>tree. CompilerOccurrenceTree(view, allocated.count) /\ allocated.count \in Nat
    BY ONLY <1>inputs, <1>finished, CompletedAllocationSuppliesOccurrenceTreeAndSource, SMT
        DEF syntax, view, CompilerOccurrenceTree
<1>returned. /\ result.control = "return" /\ actual = result.certificate
    BY ONLY <1>execution, SMT DEF ReviewedCompilerTraversalExecution, result, source, view, allocated
<1>array. actual.source = source
    BY ONLY <1>returned, SMT DEF result, ReviewedSwiftCertificateReturn
<1>view. SwiftSourceArrayAsView(actual.source) = view /\ actual.source.count = allocated.count
    BY ONLY <1>array, <1>tree, AllocatedSwiftSourceDecodesToSourceView, SMT DEF source, view, SwiftSourceArray
<1>. QED BY ONLY <1>view, <1>tree, SMT

\* The Swift allocation loop has four physical locals. Its proof-only mass
\* and the size function never feed the selection of a constructor or child.
SameRhsAllocationLocals(a,b) ==
    /\ a.position = b.position /\ a.count = b.count
    /\ a.expressions = b.expressions /\ a.source = b.source

THEOREM TheSameRhsConstructorProducesTheSamePhysicalAllocationStep ==
    ASSUME NEW a, NEW b, SameRhsAllocationLocals(a,b),
           NEW leftTerms, NEW rightTerms, NEW leftWeight, NEW rightWeight,
           a.expressions[a.position+1] \in leftTerms,
           b.expressions[b.position+1] \in rightTerms
    PROVE SameRhsAllocationLocals(
              ReviewedSwiftAllocationIteration(AllocationTermSyntax(leftTerms),leftWeight,a),
              ReviewedSwiftAllocationIteration(AllocationTermSyntax(rightTerms),rightWeight,b))
PROOF
<1>. DEFINE left == AllocationTermSyntax(leftTerms)
            right == AllocationTermSyntax(rightTerms)
            ta == a.expressions[a.position+1]
            tb == b.expressions[b.position+1]
<1>key. ta = tb BY ONLY SameRhsAllocationLocals(a,b), SMT DEF SameRhsAllocationLocals, ta, tb
<1>decode. left[ta] = right[tb]
    BY ONLY <1>key, (a.expressions[a.position+1] \in leftTerms),
        (b.expressions[b.position+1] \in rightTerms), IsaM("simp"), SMT
        DEF left,right,ta,tb,AllocationTermSyntax
<1>node. CompilerAllocationSourceNode(left,a) = CompilerAllocationSourceNode(right,b)
    BY ONLY <1>decode, SameRhsAllocationLocals(a,b), SMT
        DEF CompilerAllocationSourceNode,SameRhsAllocationLocals,ta,tb
<1>. QED BY ONLY <1>node, <1>decode, SameRhsAllocationLocals(a,b),
        ReviewedAllocationIterationProjectsStoredFields, SMT
        DEF SameRhsAllocationLocals,ta,tb,left,right

\* Repackage the two actual loop executions from the existing M2 invocation.
\* The checked history can contain different auxiliary terms for the same RHS.
AllocatedRhsReturn(rhs, w, actual) ==
    LET syntax == AllocationTermSyntax(w.terms)
        start == InitialCompilerAllocation(rhs,w.weight)
        last == w.history[w.steps]
    IN /\ SupportedAllocationInput(rhs,w.terms,syntax,w.weight,Keys)
       /\ CompilerAllocationCompletion(syntax,w.weight,start,w.steps,w.history)
       /\ actual.source = SwiftSourceArray(AllocatedSourceView(last),last.count)

THEOREM TheReturnedRhsKeepsTheAllocationOfItsActualInput ==
    ASSUME NEW statement, NEW actual, SchedulerAssignmentRhsInvocation(statement,actual)
    PROVE \E w : AllocatedRhsReturn(statement.rhs,w,actual)
PROOF
<1>. DEFINE rhs == statement.rhs
<1>args. PICK terms,weight :
    /\ SupportedAllocationInput(rhs,terms,AllocationTermSyntax(terms),weight,Keys)
    /\ ReviewedOrderedIntCertificateInvocation(rhs,Keys,AllocationTermSyntax(terms),weight,actual)
    BY ONLY SchedulerAssignmentRhsInvocation(statement,actual) DEF SchedulerAssignmentRhsInvocation,rhs
<1>. DEFINE syntax == AllocationTermSyntax(terms)
<1>runs. PICK steps,history,n,execution :
    /\ CompilerAllocationCompletion(syntax,weight,InitialCompilerAllocation(rhs,weight),steps,history)
    /\ LET last == history[steps]
           view == AllocatedSourceView(last)
       IN /\ ReviewedCompilerTraversalExecution(view,last.count,n,execution)
          /\ actual = ReviewedSwiftCertificateReturn(SwiftSourceArray(view,last.count),execution[n]).certificate
    BY ONLY <1>args DEF ReviewedOrderedIntCertificateInvocation,syntax
<1>. DEFINE last == history[steps]
            source == SwiftSourceArray(AllocatedSourceView(last),last.count)
            result == ReviewedSwiftCertificateReturn(source,execution[n])
<1>returned. /\ result.control = "return" /\ actual = result.certificate
    BY ONLY <1>runs, SMT DEF ReviewedCompilerTraversalExecution,source,result,last
<1>source. actual.source = source
    BY ONLY <1>returned, SMT DEF result,ReviewedSwiftCertificateReturn
<1>. WITNESS [terms |-> terms, weight |-> weight, steps |-> steps, history |-> history]
<1>. QED BY ONLY <1>source,<1>args,<1>runs, IsaM("simp"), SMT
              DEF AllocatedRhsReturn,rhs,source,last,syntax

THEOREM EveryReachedAllocationReadIsInItsRhsDomain ==
    ASSUME NEW rhs, NEW w, NEW actual, AllocatedRhsReturn(rhs,w,actual),
           NEW k \in 1..w.steps
    PROVE LET state == w.history[k-1]
          IN state.expressions[state.position+1] \in w.terms
PROOF
<1>. DEFINE syntax == AllocationTermSyntax(w.terms)
            start == InitialCompilerAllocation(rhs,w.weight)
            state == w.history[k-1]
<1>args. /\ SupportedAllocationInput(rhs,w.terms,syntax,w.weight,Keys)
         /\ CompilerAllocationCompletion(syntax,w.weight,start,w.steps,w.history)
    BY ONLY AllocatedRhsReturn(rhs,w,actual) DEF AllocatedRhsReturn,syntax,start
<1>init. CompilerAllocationInvariant(rhs,w.terms,syntax,w.weight,Keys,start)
    BY ONLY <1>args, CompilerAllocationStartsWithItsLoopInvariant DEF start
<1>states. \A i \in 0..w.steps : CompilerAllocationInvariant(rhs,w.terms,syntax,w.weight,Keys,w.history[i])
    BY ONLY <1>args,<1>init,AllocationCompletionRetainsEveryLoopInvariant
<1>counter. w.steps \in Nat BY ONLY <1>args DEF CompilerAllocationCompletion
<1>index. k-1 \in 0..w.steps BY ONLY <1>counter,(k \in 1..w.steps),SMT
<1>prior. CompilerAllocationInvariant(rhs,w.terms,syntax,w.weight,Keys,state)
    BY ONLY <1>states,<1>index,IsaM("blast") DEF state
<1>access. state.position < state.count
    BY ONLY <1>args,(k \in 1..w.steps),SMT DEF CompilerAllocationCompletion,state
<1>. QED BY ONLY <1>prior,<1>access,SMT DEF CompilerAllocationInvariant,state

THEOREM AnyTwoRhsAllocationsAgreeThroughTheirCommonPrefix ==
    ASSUME NEW rhs, NEW a, NEW x, AllocatedRhsReturn(rhs,a,x),
           NEW b, NEW y, AllocatedRhsReturn(rhs,b,y)
    PROVE LET limit == IF a.steps <= b.steps THEN a.steps ELSE b.steps
          IN \A k \in 0..limit : SameRhsAllocationLocals(a.history[k],b.history[k])
PROOF
<1>. DEFINE limit == IF a.steps <= b.steps THEN a.steps ELSE b.steps
            agree(k) == SameRhsAllocationLocals(a.history[k],b.history[k])
<1>runs. /\ CompilerAllocationCompletion(AllocationTermSyntax(a.terms),a.weight,
               InitialCompilerAllocation(rhs,a.weight),a.steps,a.history)
         /\ CompilerAllocationCompletion(AllocationTermSyntax(b.terms),b.weight,
               InitialCompilerAllocation(rhs,b.weight),b.steps,b.history)
    BY ONLY AllocatedRhsReturn(rhs,a,x),AllocatedRhsReturn(rhs,b,y) DEF AllocatedRhsReturn
<1>nat. /\ a.steps \in Nat /\ b.steps \in Nat /\ limit \in Nat
    BY ONLY <1>runs,SMT DEF CompilerAllocationCompletion,limit
<1>base. agree(0)
    BY ONLY <1>runs,SMT DEF CompilerAllocationCompletion,InitialCompilerAllocation,SameRhsAllocationLocals,agree
<1>step. ASSUME NEW k \in 1..limit, agree(k-1)
         PROVE agree(k)
    <2>range. /\ k \in 1..a.steps /\ k \in 1..b.steps
        BY ONLY <1>nat,(k \in 1..limit),SMT DEF limit
    <2>keys. /\ a.history[k-1].expressions[a.history[k-1].position+1] \in a.terms
             /\ b.history[k-1].expressions[b.history[k-1].position+1] \in b.terms
        BY ONLY <2>range, AllocatedRhsReturn(rhs,a,x), AllocatedRhsReturn(rhs,b,y),
                EveryReachedAllocationReadIsInItsRhsDomain, SMT
    <2>iterations. /\ a.history[k] = ReviewedSwiftAllocationIteration(AllocationTermSyntax(a.terms),a.weight,a.history[k-1])
                   /\ b.history[k] = ReviewedSwiftAllocationIteration(AllocationTermSyntax(b.terms),b.weight,b.history[k-1])
        BY ONLY <1>runs,<2>range,SMT DEF CompilerAllocationCompletion
    <2>. QED BY ONLY <2>keys,<2>iterations,agree(k-1),
        TheSameRhsConstructorProducesTheSamePhysicalAllocationStep,SMT DEF agree
<1>. DEFINE flags == [i \in 0..limit |-> agree(i)]
<1>type. flags \in [0..limit -> BOOLEAN]
    BY ONLY IsaM("auto"), SMT DEF flags,agree,SameRhsAllocationLocals
<1>zero. flags[0]
    BY ONLY <1>nat,<1>base,SMT DEF flags
<1>flagStep. ASSUME NEW k \in 1..limit, \A j \in 0..(k-1) : flags[j]
             PROVE flags[k]
    <2>range. /\ k-1 \in 0..(k-1) /\ k-1 \in 0..limit /\ k \in 0..limit
        BY ONLY (k \in 1..limit),<1>nat,SMT
    <2>prior. flags[k-1] BY ONLY <2>range,(\A j \in 0..(k-1) : flags[j]),IsaM("blast")
    <2>input. agree(k-1) BY ONLY <2>range,<2>prior,IsaM("simp") DEF flags
    <2>next. agree(k) BY ONLY <2>input,(k \in 1..limit),<1>step
    <2>. QED BY ONLY <2>next,<2>range,IsaM("simp") DEF flags
<1>count. limit \in Nat BY ONLY <1>nat,PTL
<1>each. \A i \in 0..limit : flags[i]
    BY ONLY <1>type,<1>count,<1>zero,<1>flagStep,FiniteBooleanPrefixProperty,SMT
<1>result. \A k \in 0..limit : agree(k)
    <2>. TAKE k \in 0..limit
    <2>selected. flags[k] BY ONLY <1>each,(k \in 0..limit),IsaM("blast")
    <2>. QED BY ONLY <2>selected,(k \in 0..limit),IsaM("simp") DEF flags
<1>. QED BY ONLY <1>result DEF agree,limit

THEOREM TheSchedulerRhsHasOnlyOnePhysicalSourceArray ==
    ASSUME NEW statement, NEW x, NEW y,
           SchedulerAssignmentRhsInvocation(statement,x), SchedulerAssignmentRhsInvocation(statement,y)
    PROVE x.source = y.source
PROOF
<1>. DEFINE rhs == statement.rhs
<1>a. PICK a : AllocatedRhsReturn(rhs,a,x)
    BY ONLY SchedulerAssignmentRhsInvocation(statement,x),TheReturnedRhsKeepsTheAllocationOfItsActualInput DEF rhs
<1>b. PICK b : AllocatedRhsReturn(rhs,b,y)
    BY ONLY SchedulerAssignmentRhsInvocation(statement,y),TheReturnedRhsKeepsTheAllocationOfItsActualInput DEF rhs
<1>. DEFINE limit == IF a.steps <= b.steps THEN a.steps ELSE b.steps
<1>runs. /\ CompilerAllocationCompletion(AllocationTermSyntax(a.terms),a.weight,
                  InitialCompilerAllocation(rhs,a.weight),a.steps,a.history)
         /\ CompilerAllocationCompletion(AllocationTermSyntax(b.terms),b.weight,
                  InitialCompilerAllocation(rhs,b.weight),b.steps,b.history)
    BY ONLY <1>a,<1>b DEF AllocatedRhsReturn
<1>stages. /\ a.steps \in Nat /\ b.steps \in Nat /\ limit \in 0..limit
    BY ONLY <1>runs, SMT DEF limit,CompilerAllocationCompletion
<1>atLimit. SameRhsAllocationLocals(a.history[limit],b.history[limit])
    BY ONLY <1>a,<1>b,<1>stages,AnyTwoRhsAllocationsAgreeThroughTheirCommonPrefix, SMT DEF limit
<1>length. a.steps = b.steps
    <2>lt. CASE a.steps < b.steps
        <3>index. /\ limit+1 \in 1..b.steps /\ (limit+1)-1=limit
            BY ONLY <1>stages,<2>lt,SMT DEF limit
        <3>guards. \A k \in 1..b.steps :
            b.history[k-1].position < b.history[k-1].count
            BY ONLY <1>runs,IsaM("blast") DEF CompilerAllocationCompletion
        <3>running. b.history[limit].position < b.history[limit].count
            BY ONLY <3>index,<3>guards,SMT
        <3>. QED BY ONLY <3>running,<1>runs,<1>atLimit,<2>lt,SMT DEF limit,SameRhsAllocationLocals,CompilerAllocationCompletion
    <2>gt. CASE b.steps < a.steps
        <3>index. /\ limit+1 \in 1..a.steps /\ (limit+1)-1=limit
            BY ONLY <1>stages,<2>gt,SMT DEF limit
        <3>guards. \A k \in 1..a.steps :
            a.history[k-1].position < a.history[k-1].count
            BY ONLY <1>runs,IsaM("blast") DEF CompilerAllocationCompletion
        <3>running. a.history[limit].position < a.history[limit].count
            BY ONLY <3>index,<3>guards,SMT
        <3>. QED BY ONLY <3>running,<1>runs,<1>atLimit,<2>gt,SMT DEF limit,SameRhsAllocationLocals,CompilerAllocationCompletion
    <2>. QED BY ONLY <2>lt,<2>gt,<1>stages,SMT
<1>physical. /\ a.history[a.steps].source = b.history[b.steps].source
             /\ a.history[a.steps].count = b.history[b.steps].count
    BY ONLY <1>length,<1>atLimit,SMT DEF SameRhsAllocationLocals,limit
<1>. QED BY ONLY <1>a,<1>b,<1>physical,SMT DEF AllocatedRhsReturn,AllocatedSourceView
====
