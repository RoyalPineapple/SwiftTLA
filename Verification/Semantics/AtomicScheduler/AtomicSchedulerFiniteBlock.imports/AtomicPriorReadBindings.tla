---- MODULE AtomicPriorReadBindings ----
EXTENDS PhysicalIntAssignmentRhsRule

PutRootName(before, target, binding) ==
    [key \in DOMAIN before \cup {target} |-> IF key = target THEN binding ELSE before[key]]

TraceBindingNames(rows) == [i \in 1..Len(rows) |-> rows[i].binding]

PriorRootNames(rows, prefix) ==
    ScheduledRootReplacementNames(DirectCopyRoutes(Keys, rows)[prefix], TraceBindingNames(rows))

THEOREM RoutingOneCaptureUpdatesOnlyItsRootName ==
    ASSUME NEW routes, NEW names, NEW target \in Keys, NEW position
    PROVE ScheduledRootReplacementNames(CopyReplace(Keys, routes, target, <<"capture",position>>), names) =
              PutRootName(ScheduledRootReplacementNames(routes,names),target,names[position])
PROOF
<1>. DEFINE after == CopyReplace(Keys,routes,target,<<"capture",position>>)
            beforeNames == ScheduledRootReplacementNames(routes,names)
            actual == ScheduledRootReplacementNames(after,names)
            expected == PutRootName(beforeNames,target,names[position])
<1>beforeDomain. DOMAIN beforeNames = {k \in Keys : routes[k][1] = "capture"}
    BY ONLY SMT DEF beforeNames, ScheduledRootReplacementNames
<1>afterDomain. DOMAIN actual = {k \in Keys : after[k][1] = "capture"}
    BY ONLY SMT DEF actual, ScheduledRootReplacementNames
<1>expectedDomain. DOMAIN expected = DOMAIN beforeNames \cup {target}
    BY ONLY SMT DEF expected, PutRootName
<1>target. after[target][1] = "capture"
    BY ONLY (target \in Keys), SMT DEF after, CopyReplace
<1>others. \A k \in Keys : k # target => after[k][1] = routes[k][1]
    BY ONLY SMT DEF after, CopyReplace
<1>membership. \A key : key \in DOMAIN actual <=> key \in DOMAIN expected
    <2>. TAKE key
    <2>changed. CASE key = target
        BY ONLY <2>changed, <1>afterDomain, <1>expectedDomain, <1>target, (target \in Keys), SMT
    <2>same. CASE key \in Keys /\ key # target
        BY ONLY <2>same, <1>beforeDomain, <1>afterDomain, <1>expectedDomain, <1>others, SMT
    <2>outside. CASE key \notin Keys
        BY ONLY <2>outside, <1>beforeDomain, <1>afterDomain, <1>expectedDomain, (target \in Keys), SMT
    <2>. QED BY ONLY <2>changed, <2>same, <2>outside, SMT
<1>domain. DOMAIN actual = DOMAIN expected
    BY ONLY <1>membership, SetExtensionality, Zenon
<1>keys. \A key \in DOMAIN actual : actual[key] = expected[key]
    <2>. TAKE key \in DOMAIN actual
    <2>changed. CASE key = target
        BY ONLY (target \in Keys), <2>changed, SMT
            DEF actual, expected, after, ScheduledRootReplacementNames, PutRootName, CopyReplace
    <2>kept. CASE key # target
        BY ONLY (key \in DOMAIN actual), <1>domain, <2>kept, SMT
            DEF actual, expected, after, beforeNames, ScheduledRootReplacementNames, PutRootName, CopyReplace
    <2>. QED BY ONLY <2>changed, <2>kept, SMT
<1>. QED BY ONLY <1>domain, <1>keys, SMT DEF actual, expected, ScheduledRootReplacementNames, PutRootName

RecordedNameMapsFollowRows(rows, maps) ==
    /\ maps[1] = [key \in {} |-> key]
    /\ \A i \in 1..Len(rows) :
           maps[i+1] = PutRootName(maps[i],rows[i].target,rows[i].binding)

THEOREM ActualIncomingNameMapsFollowTheStrictlyPriorWrites ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW maps, RecordedNameMapsFollowRows(rows,maps)
    PROVE \A prefix \in 0..Len(rows) : maps[prefix+1] = PriorRootNames(rows,prefix)
PROOF
<1>. DEFINE count == Len(rows)
            names == TraceBindingNames(rows)
            routes == DirectCopyRoutes(Keys,rows)
            P(prefix) == maps[prefix+1] = PriorRootNames(rows,prefix)
<1>shape. count \in Nat /\ \A i \in 1..count : rows[i].target \in Keys
    BY ONLY SupportedAssignmentList(rows), SMT DEF SupportedAssignmentList, count
<1>start. P(0)
    <2>entryRoutes. routes[0] = CopyEntryRoutes(Keys)
        BY ONLY <1>shape, DirectCopyRoutesFollowEveryCapture, SMT DEF routes, count
    <2>. QED BY ONLY <2>entryRoutes, RecordedNameMapsFollowRows(rows,maps), SMT
        DEF P, PriorRootNames, routes, CopyEntryRoutes, ScheduledRootReplacementNames, RecordedNameMapsFollowRows
<1>step. \A i \in 1..count : (\A earlier \in 0..(i-1) : P(earlier)) => P(i)
    <2>. SUFFICES ASSUME NEW i \in 1..count, \A earlier \in 0..(i-1) : P(earlier)
                  PROVE P(i)
        OBVIOUS
    <2>old. maps[i] = ScheduledRootReplacementNames(routes[i-1],names)
        BY ONLY (i \in 1..count), (\A earlier \in 0..(i-1) : P(earlier)),
            SMT DEF P, PriorRootNames, names, routes
    <2>routes. routes[i] = CopyReplace(Keys,routes[i-1],rows[i].target,<<"capture",i>>)
        BY ONLY <1>shape, (i \in 1..count), DirectCopyRoutesFollowEveryCapture, SMT DEF routes, count
    <2>write. /\ names[i] = rows[i].binding /\ rows[i].target \in Keys
              /\ maps[i+1] = PutRootName(maps[i],rows[i].target,rows[i].binding)
        BY ONLY <1>shape, (i \in 1..count), RecordedNameMapsFollowRows(rows,maps), SMT
            DEF names, count, TraceBindingNames, RecordedNameMapsFollowRows
    <2>map. ScheduledRootReplacementNames(routes[i],names) =
                  PutRootName(ScheduledRootReplacementNames(routes[i-1],names),rows[i].target,names[i])
        BY ONLY <2>write, <2>routes, RoutingOneCaptureUpdatesOnlyItsRootName, SMT
    <2>. QED BY ONLY <2>old, <2>write, <2>map, SMT DEF P, PriorRootNames, names, routes
<1>. HIDE DEF P
<1>all. \A prefix \in 0..count : P(prefix)
    BY ONLY <1>shape, <1>start, <1>step, FiniteIndexedPrefixProperty, Isa
<1>. QED BY ONLY <1>all DEF P, count

THEOREM PriorRootNameIsTheLastWriterOrTheEntryName ==
    ASSUME NEW rows, Len(rows) \in Nat, NEW prefix \in 0..Len(rows),
           NEW key \in Keys, NEW writer, LastDirectCopy(rows,prefix,key,writer)
    PROVE StateExprReplaceReadName(PriorRootNames(rows,prefix),key) =
              IF writer = 0 THEN key ELSE rows[writer].binding
PROOF
<1>. DEFINE routes == DirectCopyRoutes(Keys,rows)[prefix]
            names == TraceBindingNames(rows)
<1>route. routes[key] = DirectCopyReference(key,writer)
    BY ONLY (Len(rows) \in Nat), (prefix \in 0..Len(rows)), (key \in Keys),
        LastDirectCopy(rows,prefix,key,writer), RecordedWriterSuppliesTheProjectedRead, SMT DEF routes
<1>entry. CASE writer = 0
    BY ONLY <1>entry, <1>route, (key \in Keys), SMT
        DEF PriorRootNames, routes, ScheduledRootReplacementNames, DirectCopyReference, StateExprReplaceReadName
<1>capture. CASE writer # 0
    <2>bounds. writer \in 1..Len(rows)
        BY ONLY (Len(rows) \in Nat), (prefix \in 0..Len(rows)), <1>capture, LastDirectCopy(rows,prefix,key,writer),
            SMT DEF LastDirectCopy
    <2>name. names[writer] = rows[writer].binding
        BY ONLY <2>bounds, SMT DEF names, TraceBindingNames
    <2>. QED BY ONLY <1>capture, <1>route, <2>name, (key \in Keys), SMT
        DEF PriorRootNames, names, routes, ScheduledRootReplacementNames, DirectCopyReference, StateExprReplaceReadName
<1>. QED BY ONLY <1>entry, <1>capture, SMT

RowsReadExactlyTheirStrictlyPriorWriters(rows, maps) ==
    \A i \in 1..Len(rows) :
      /\ maps[i] = PriorRootNames(rows,i-1)
      /\ \A origin \in DOMAIN rows[i].view.kinds : rows[i].view.kinds[origin] = "read" =>
            LET key == rows[i].view.reads[origin]
            IN \E writer \in 0..(i-1) :
                  /\ LastDirectCopy(rows,i-1,key,writer)
                  /\ \A other \in 0..(i-1) : LastDirectCopy(rows,i-1,key,other) => other = writer
                  /\ rows[i].substitutedRhs[origin].payload =
                        IF writer=0 THEN key ELSE rows[writer].binding

THEOREM SourceBoundSubstitutionReadsOnlyTheLatestStrictlyPriorWrite ==
    ASSUME NEW rows, SupportedAssignmentList(rows), NEW maps, RecordedNameMapsFollowRows(rows,maps),
           \A i \in 1..Len(rows) :
                rows[i].substitutedRhs = StateExprReplaceProjection(rows[i].view,maps[i])
    PROVE RowsReadExactlyTheirStrictlyPriorWriters(rows,maps)
PROOF
<1>domains. Len(rows) \in Nat /\ DOMAIN rows = 1..Len(rows)
    BY ONLY SupportedAssignmentList(rows), SMT DEF SupportedAssignmentList
<1>maps. \A prefix \in 0..Len(rows) : maps[prefix+1] = PriorRootNames(rows,prefix)
    BY ONLY SupportedAssignmentList(rows), RecordedNameMapsFollowRows(rows,maps), ActualIncomingNameMapsFollowTheStrictlyPriorWrites
<1>. SUFFICES \A i \in 1..Len(rows) :
      /\ maps[i] = PriorRootNames(rows,i-1)
      /\ \A origin \in DOMAIN rows[i].view.kinds : rows[i].view.kinds[origin] = "read" =>
            LET key == rows[i].view.reads[origin]
            IN \E writer \in 0..(i-1) :
                  /\ LastDirectCopy(rows,i-1,key,writer)
                  /\ \A other \in 0..(i-1) : LastDirectCopy(rows,i-1,key,other) => other = writer
                  /\ rows[i].substitutedRhs[origin].payload =
                        IF writer=0 THEN key ELSE rows[writer].binding
    BY DEF RowsReadExactlyTheirStrictlyPriorWriters
<1>. TAKE i \in 1..Len(rows)
<1>. DEFINE row == rows[i]
            view == row.view
            prefix == i-1
<1>index. prefix \in Nat /\ prefix \in 0..Len(rows)
    BY ONLY <1>domains, (i \in 1..Len(rows)), SMT DEF prefix
<1>map. maps[i] = PriorRootNames(rows,prefix)
    BY ONLY <1>index, <1>maps, SMT DEF prefix
<1>certificate. AssignmentRhsCertificate(row)
    BY ONLY <1>domains, (i \in 1..Len(rows)), SupportedAssignmentList(rows), SMT DEF row, SupportedAssignmentList
<1>reads. \A origin \in DOMAIN view.kinds : view.kinds[origin] = "read" =>
          LET key == view.reads[origin]
          IN \E writer \in 0..prefix :
                /\ LastDirectCopy(rows,prefix,key,writer)
                /\ \A other \in 0..prefix : LastDirectCopy(rows,prefix,key,other) => other = writer
                /\ row.substitutedRhs[origin].payload =
                      IF writer=0 THEN key ELSE rows[writer].binding
    <2>. TAKE origin \in DOMAIN view.kinds
    <2>. SUFFICES ASSUME view.kinds[origin] = "read"
                  PROVE \E writer \in 0..prefix :
                       /\ LastDirectCopy(rows,prefix,view.reads[origin],writer)
                       /\ \A other \in 0..prefix : LastDirectCopy(rows,prefix,view.reads[origin],other) => other = writer
                       /\ row.substitutedRhs[origin].payload =
                              IF writer=0 THEN view.reads[origin] ELSE rows[writer].binding
        BY SMT
    <2>. DEFINE key == view.reads[origin]
                node == row.inverse[origin]
    <2>slot. /\ node \in 1..row.emitted.count /\ row.emitted.origins[node] = origin
             /\ TypedVisitedSourceInputs(view,row.emitted)
        BY ONLY <1>certificate, (origin \in DOMAIN view.kinds), SMT
            DEF node, view, AssignmentRhsCertificate, LiteralReadAddCertificate
    <2>key. key \in Keys
        BY ONLY <2>slot, (view.kinds[origin] = "read"), SMT DEF key, TypedVisitedSourceInputs
    <2>exists. \E writer \in 0..prefix : LastDirectCopy(rows,prefix,key,writer)
        BY ONLY <1>domains, <1>index, EveryFiniteCopyPrefixHasALastWriter, SMTT(25)
    <2>writer. PICK writer \in 0..prefix : LastDirectCopy(rows,prefix,key,writer)
        BY ONLY <2>exists
    <2>unique. \A other \in 0..prefix : LastDirectCopy(rows,prefix,key,other) => other = writer
        BY ONLY <1>index, <2>writer, TwoLastDirectCopiesHaveTheSamePosition, SMT
    <2>prior. StateExprReplaceReadName(PriorRootNames(rows,prefix),key) =
                  IF writer=0 THEN key ELSE rows[writer].binding
        BY ONLY <1>domains, <1>index, <2>key, <2>writer, PriorRootNameIsTheLastWriterOrTheEntryName, SMT
    <2>actual. row.substitutedRhs[origin].payload = StateExprReplaceReadName(maps[i],key)
        BY ONLY (i \in 1..Len(rows)), (origin \in DOMAIN view.kinds), (view.kinds[origin] = "read"),
            (\A j \in 1..Len(rows) : rows[j].substitutedRhs = StateExprReplaceProjection(rows[j].view,maps[j])),
            SMT DEF row, view, key, StateExprReplaceProjection, StateExprSourceOccurrence
    <2>selected. /\ writer \in 0..prefix
                 /\ LastDirectCopy(rows,prefix,key,writer)
                 /\ \A other \in 0..prefix : LastDirectCopy(rows,prefix,key,other) => other = writer
                 /\ row.substitutedRhs[origin].payload = IF writer=0 THEN key ELSE rows[writer].binding
        BY ONLY (writer \in 0..prefix), <1>map, <2>writer, <2>unique, <2>prior, <2>actual, SMT
    <2>. QED BY ONLY <2>selected, SMT DEF key
<1>. QED BY ONLY <1>map, <1>reads DEF row, view, prefix
====
