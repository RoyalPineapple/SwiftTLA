import Foundation
import SwiftTLA

package enum OrderedRHSTLAProof {
    /// The source module owns independently selected authored rows and their certificate support.
    package static func render(
        _ rendered: RenderedSpecification, program: CompiledProgram, sourceAction: String,
        sourceModule: String, sourceRows: String, sourceFields: String = "MasterFields", supportTheorem: String
    ) throws -> (name: String, bytes: Data)? {
        let bundle = rendered.tlaBundle
        let layout = program.layout
        let controls = layout.variables.filter { $0.declaration.origin == .programCounter }
        let roots = layout.variables.filter { $0.declaration.origin == .source }
        let live = layout.actions.filter { !$0.isTermination }
        let terminals = layout.actions.filter(\.isTermination)
        guard bundle.imports.isEmpty, layout.parameters.isEmpty,
              case .compiled(let identity, _, _) = bundle.provenance, identity == program.identity,
              controls.count == 1, let counter = controls.first, !roots.isEmpty,
              roots.count + 1 == layout.variables.count,
              roots.allSatisfy({ program.variableTypes[$0.id] == .int }),
              live.count == 1, let step = live.first, step.declaration.name == sourceAction,
              terminals.count == 1, let terminal = terminals.first,
              program.requiresOrderedIntOutput(step.id),
              rendered.actions.map(\.renderedName) == [step.renderedName, terminal.renderedName],
              rendered.actions.allSatisfy({ $0.arguments.isEmpty }) else { return nil }
        let direct = try program.renderModule()
        guard direct.renderedModuleSource.utf8.elementsEqual(bundle.root.tla.utf8),
              let normalCFG = bundle.root.cfg,
              normalCFG.utf8.elementsEqual(try direct.configuration.render(usesSymmetryReduction: false).utf8)
        else { return nil }

        let action = program[step.id]
        guard action.bindings.isEmpty,
              case .and(.guard_(let gate), let body) = action.body,
              case .equal = gate.operation, gate.children.count == 2,
              gate.children[0].operation == .stateVariable(counter.id),
              case .controlLocation(let entryID) = gate.children[1].operation,
              let entry = layout.controlLocations.first(where: { $0.id == entryID }),
              entry.sourceName == sourceAction else { return nil }

        let doneName = CompilerControlSymbol.done.rawValue
        let destinations = layout.controlLocations.filter { $0.sourceName == doneName && $0.id != entryID }
        guard destinations.count == 1, let destination = destinations.first else { return nil }
        let entryControl = try CompiledValue.controlLocation(entry.id).rendered(using: layout)
        let endControl = try CompiledValue.controlLocation(destination.id).rendered(using: layout)
        guard let physical = OrderedRHSPhysicalAction.decode(in: bundle.root.tla, action: step.renderedName,
            body: body, fields: roots, counter: counter, destination: endControl.description) else { return nil }
        let name = "SwiftTLAOrderedRHSOutputProof"
        let identifiers = [bundle.root.name, sourceModule, sourceRows, sourceFields, supportTheorem,
                           counter.formalName, step.renderedName, terminal.renderedName] + roots.map(\.formalName)
        guard identifiers.allSatisfy(formalIdentifier), !bundle.root.tla.contains("RHSOutput"),
              ![bundle.root.name, sourceModule].contains(name) else { return nil }

        let settings = bundle.root.tla.split(separator: "\n").compactMap { line -> String? in
            guard let split = line.range(of: " == ") else { return nil }
            let header = String(line[..<split.lowerBound])
            return formalIdentifier(header) ? header : nil
        }
        func resolved(_ stem: String) -> String? {
            let matches = settings.filter {
                $0.hasPrefix(stem) && $0.dropFirst(stem.count).allSatisfy { $0 == "_" }
            }
            return matches.count == 1 ? matches.first : nil
        }
        let locations = physical.captures.enumerated().flatMap { offset, capture in
            capture.additionNodes.map { (row: offset + 1, node: $0) }
        }
        var probes: [(failed: String, operands: String, operation: String, before: String)] = []
        for offset in locations.indices {
            let suffix = String(step.id.ordinal) + (offset == 0 ? "" : "_\(offset)")
            guard let failure = resolved("__SwiftTLAOverflowFailure" + suffix),
                  let operands = resolved("__SwiftTLAOverflowOperands" + suffix),
                  let operation = resolved("__SwiftTLAOverflowOperation" + suffix),
                  let before = resolved("__SwiftTLAOverflowBefore" + suffix)
            else { return nil }
            probes.append((failure, operands, operation, before))
        }
        let aggregate = resolved("__SwiftTLAAnyEvaluationFailure" + String(step.id.ordinal))
        guard (aggregate == nil) == locations.isEmpty else { return nil }

        func tuple(_ values: [String]) -> String { "<<\(values.joined(separator: ", "))>>" }
        let captures = physical.captures
        let scoped = captures.map { "(LET \($0.binding) == \($0.rhs) IN " }.joined()
        let closed = String(repeating: ")", count: captures.count)
        let guards = tuple(captures.map { tuple($0.guards) })
        let terms = tuple(captures.map { tuple($0.terms) })
        let values = tuple(captures.map(\.binding))
        let counts = TLAValue.tuple(captures.map { .int($0.plan.kinds.count) })
        func column(_ path: KeyPath<OrderedRHSPhysicalAction.Plan, [TLAValue]>) -> TLAValue {
            .tuple(captures.map { .tuple($0.plan[keyPath: path]) })
        }
        let kinds = column(\.kinds)
        let literals = column(\.literals)
        let reads = column(\.reads)
        let left = column(\.left)
        let right = column(\.right)
        let starts = TLAValue.tuple(captures.map { .tuple($0.starts.map(TLAValue.int)) })
        let writeRoutes = TLAValue.function(Dictionary(uniqueKeysWithValues: physical.writes.map {
            (.string($0.key), $0.value)
        }))
        let positions = tuple(locations.map { "<<\($0.row), \($0.node)>>" })
        func definitions(_ names: [String]) -> String { names.map { ", " + $0 }.joined() }
        let actualNames = definitions(probes.flatMap { [$0.failed, $0.operands, $0.operation, $0.before] })
        let predicateNames = definitions(probes.map(\.failed))
        let aggregateName = definitions(aggregate.map { [$0] } ?? [])
        let failureGuards = tuple(probes.map(\.failed))
        let failureData = probes.map { site in
            "(IF \(site.failed) THEN [operands |-> \(site.operands), "
                + "operation |-> \(site.operation), prefix |-> \(site.before)] ELSE <<>>)"
        }.joined(separator: ",\n    ")
        let keys = TLAValue.set(Set(roots.map { .string($0.declaration.name) }))
        let pc = counter.formalName
        let proof = #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(bundle.root.name), TLAPS

        RHSOutputKeys == \#(keys)
        RHSOutputMin == \#(TLAValue.int(Int.min))
        RHSOutputMax == \#(TLAValue.int(Int.max))
        RHSOutputInput == INSTANCE \#(sourceModule)

        RHSOutputRows == RHSOutputInput!\#(sourceRows)
        RHSOutputBefore == [key \in RHSOutputKeys |-> \#(lookup(roots, primed: false))]
        RHSOutputAfter == [key \in RHSOutputKeys |-> \#(lookup(roots, primed: true))]
        RHSOutputStateType == RHSOutputBefore \in [RHSOutputKeys -> RHSOutputMin..RHSOutputMax]
        RHSOutputActionLabel == \#(TLAValue.string(sourceAction))
        RHSOutputEntry == \#(entryControl)
        RHSOutputExit == \#(endControl)
        RHSOutputSelected == \#(pc) = RHSOutputEntry
        RHSOutputFailureSelected == \#(aggregate ?? "FALSE")
        RHSOutputCount == Len(RHSOutputRows)

        LOCAL RHSOutputNodeCounts == \#(counts)
        LOCAL RHSOutputNodeKinds == \#(kinds)
        LOCAL RHSOutputNodeLiterals == \#(literals)
        LOCAL RHSOutputNodeReads == \#(reads)
        LOCAL RHSOutputNodeLeft == \#(left)
        LOCAL RHSOutputNodeRight == \#(right)
        LOCAL RHSOutputPlans == [index \in DOMAIN RHSOutputNodeCounts |->
            [count |-> RHSOutputNodeCounts[index], kinds |-> RHSOutputNodeKinds[index],
             literals |-> RHSOutputNodeLiterals[index], reads |-> RHSOutputNodeReads[index],
             left |-> RHSOutputNodeLeft[index], right |-> RHSOutputNodeRight[index]]]
        LOCAL RHSOutputStarts == \#(starts)
        LOCAL RHSOutputRaw ==
            \#(scoped)[plans |-> RHSOutputPlans, starts |-> RHSOutputStarts,
                        terms |-> \#(terms), guards |-> \#(guards), roots |-> \#(values)]\#(closed)
        LOCAL RHSOutputWriteRoutes == \#(writeRoutes)
        RHSOutputProbePositions == \#(positions)
        RHSOutputGuards == \#(failureGuards)
        RHSOutputPayloads == <<\#(failureData)>>
        RHSOutputFailureProbeSites == {probe \in DOMAIN RHSOutputGuards : RHSOutputGuards[probe]}
        LOCAL RHSOutputPhysicalNodeSlots ==
            UNION {{<<index, node>> : node \in 1..RHSOutputPlans[index].count} : index \in 1..RHSOutputCount}
        RHSOutputSelectedSubExpressions ==
            {RHSOutputProbePositions[probe] : probe \in RHSOutputFailureProbeSites}

        LOCAL RHSOutputPasses == RHSOutputInput!Rule!RenderedAssignmentsPass(RHSOutputRaw, RHSOutputCount)
        LOCAL RHSOutputFailsAt(place) ==
            RHSOutputInput!Rule!RenderedAssignmentFailsAt(RHSOutputRaw, RHSOutputCount, place[1], place[2])
        LOCAL RHSOutputRawAdvance ==
            /\ RHSOutputSelected /\ RHSOutputPasses
            /\ \#(pc)' = RHSOutputExit
            /\ RHSOutputAfter = RHSOutputInput!Rule!CopyMaterializedState(
                                   RHSOutputKeys, RHSOutputBefore, RHSOutputRaw.roots, RHSOutputWriteRoutes)

        RHSOutputFailureEvent(ordinal, operation, operands, prefix) ==
            [site |-> ordinal, target |-> RHSOutputRows[ordinal].target,
             payload |-> <<"integerOverflow", operation, operands>>, completed |-> prefix,
             before |-> RHSOutputInput!Rule!CompletedAssignmentBindings(RHSOutputBefore, RHSOutputRows, prefix)]

        RHSOutputActualFailures ==
            {LET payload == RHSOutputPayloads[probe]
             IN RHSOutputFailureEvent(RHSOutputProbePositions[probe][1], payload.operation, payload.operands, payload.prefix)
                : probe \in RHSOutputFailureProbeSites}

        RHSOutputHistoryFailures(history) ==
            LET final == history[RHSOutputCount]
            IN IF RHSOutputSelected /\ final.failure # <<>>
               THEN {[site |-> final.failure.site, target |-> RHSOutputRows[final.failure.site].target,
                      payload |-> final.failure.payload, completed |-> final.completed, before |-> final.failure.before]}
               ELSE {}

        RHSOutputHistoryAdvance(history) ==
            LET final == history[RHSOutputCount]
            IN /\ RHSOutputSelected /\ final.failure = <<>>
               /\ \#(pc)' = RHSOutputExit /\ RHSOutputAfter = final.bindings

        RHSOutputTermination ==
            /\ \#(pc) = RHSOutputExit /\ UNCHANGED \#(pc)
            /\ RHSOutputBefore = RHSOutputAfter

        RHSOutputSourceHistory(history) ==
            RHSOutputInput!Rule!AssignmentListHistory(FALSE, RHSOutputBefore, RHSOutputRows, history)
        RHSOutputGeneratedHistory(history) ==
            RHSOutputInput!Rule!AssignmentListHistory(TRUE, RHSOutputBefore, RHSOutputRows, history)
        RHSOutputHistoryObservation(history) ==
            /\ (\#(step.renderedName) <=> RHSOutputHistoryAdvance(history))
            /\ RHSOutputActualFailures = RHSOutputHistoryFailures(history)
            /\ RHSOutputFailureSelected = (RHSOutputActualFailures # {})
            /\ (Next <=> (RHSOutputHistoryAdvance(history) \/ RHSOutputTermination))

        THEOREM RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory ==
            /\ RHSOutputKeys = RHSOutputInput!\#(sourceFields)
            /\ RHSOutputInput!Rule!SupportedAssignmentList(RHSOutputRows)
            /\ RHSOutputCount = \#(physical.captures.count)
            /\ DOMAIN RHSOutputRows = DOMAIN RHSOutputPlans
        PROOF
        <1>fields. RHSOutputKeys = RHSOutputInput!\#(sourceFields)
            BY ONLY SMT DEF RHSOutputKeys, RHSOutputInput!\#(sourceFields)
        <1>authored. /\ RHSOutputInput!Rule!SupportedAssignmentList(RHSOutputRows)
                     /\ RHSOutputCount = \#(physical.captures.count)
            BY ONLY RHSOutputInput!\#(supportTheorem), SMT DEF RHSOutputRows, RHSOutputCount
        <1>domain. DOMAIN RHSOutputRows = DOMAIN RHSOutputPlans
            BY ONLY SMT DEF RHSOutputRows, RHSOutputInput!\#(sourceRows), RHSOutputInput!MasterNodeCounts, RHSOutputPlans, RHSOutputNodeCounts
        <1>. QED BY ONLY <1>fields, <1>authored, <1>domain

        THEOREM RHSOutputUsesTheMachineIntegerDomain ==
            RHSOutputInput!Rule!IntegerDomain
            BY ONLY SMT DEF RHSOutputInput!Rule!IntegerDomain

        THEOREM ActualRenderedRightHandSidesMatchAuthoredAssignmentRoutes ==
            \A index \in DOMAIN RHSOutputRows :
                RHSOutputInput!Rule!PhysicalAssignmentReadsMatchRoutes(RHSOutputRows, index, RHSOutputPlans[index])
        PROOF
        <1>domain. /\ Len(RHSOutputRows) \in Nat
                   /\ DOMAIN RHSOutputRows = 1..Len(RHSOutputRows)
                   /\ DOMAIN RHSOutputRows = DOMAIN RHSOutputPlans
            BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory
                DEF RHSOutputInput!Rule!SupportedAssignmentList
        <1>counts. RHSOutputNodeCounts = RHSOutputInput!MasterNodeCounts
            BY ONLY IsaM("simp") DEF RHSOutputNodeCounts, RHSOutputInput!MasterNodeCounts
        <1>kinds. RHSOutputNodeKinds = RHSOutputInput!MasterNodeKinds
            BY ONLY IsaM("simp") DEF RHSOutputNodeKinds, RHSOutputInput!MasterNodeKinds
        <1>literals. RHSOutputNodeLiterals = RHSOutputInput!MasterNodeLiterals
            BY ONLY SMT DEF RHSOutputNodeLiterals, RHSOutputInput!MasterNodeLiterals
        <1>children. /\ RHSOutputNodeLeft = RHSOutputInput!MasterNodeLeft
                     /\ RHSOutputNodeRight = RHSOutputInput!MasterNodeRight
            BY ONLY IsaM("simp")
                DEF RHSOutputNodeLeft, RHSOutputNodeRight, RHSOutputInput!MasterNodeLeft, RHSOutputInput!MasterNodeRight
        <1>. TAKE index \in DOMAIN RHSOutputRows
        <1>. DEFINE physical == RHSOutputPlans[index]
                    expected == RHSOutputInput!Rule!AssignmentRhsPlan(RHSOutputRows[index])
        <1>shape. /\ physical.count = expected.count
                  /\ expected.count = RHSOutputInput!MasterNodeCounts[index]
            BY ONLY <1>counts, <1>domain, (index \in DOMAIN RHSOutputRows), SMT
                DEF physical, expected, RHSOutputPlans, RHSOutputRows, RHSOutputInput!\#(sourceRows),
                    RHSOutputInput!Rule!AssignmentRhsPlan, RHSOutputInput!Rule!ExtractedNodePlan
        <1>physicalDomain. index \in DOMAIN RHSOutputPlans
            BY ONLY <1>domain, (index \in DOMAIN RHSOutputRows), SMT
        <1>physicalColumns. /\ physical.kinds = RHSOutputNodeKinds[index]
                            /\ physical.literals = RHSOutputNodeLiterals[index]
                            /\ physical.left = RHSOutputNodeLeft[index]
                            /\ physical.right = RHSOutputNodeRight[index]
            BY ONLY <1>physicalDomain, SMT DEF physical, RHSOutputPlans
        <1>sourceDomain. index \in DOMAIN RHSOutputInput!MasterNodeCounts
            BY ONLY (index \in DOMAIN RHSOutputRows), SMT DEF RHSOutputRows, RHSOutputInput!\#(sourceRows)
        <1>. DEFINE cell(node) == RHSOutputRows[index].emitted.nodes[node]
        <1>sourceCells. \A node \in 1..expected.count :
            /\ cell(node).kind = RHSOutputInput!MasterNodeKinds[index][node]
            /\ cell(node).payload = (IF cell(node).kind = "read"
                                    THEN RHSOutputInput!MasterNodeReadKeys[index][node]
                                    ELSE RHSOutputInput!MasterNodeLiterals[index][node])
            /\ cell(node).left = RHSOutputInput!MasterNodeLeft[index][node]
            /\ cell(node).right = RHSOutputInput!MasterNodeRight[index][node]
            <2>. TAKE node \in 1..expected.count
            <2>node. node \in 1..RHSOutputInput!MasterNodeCounts[index]
                BY ONLY <1>shape, (node \in 1..expected.count), SMT
            <2>kind. cell(node).kind = RHSOutputInput!MasterNodeKinds[index][node]
                BY ONLY <1>sourceDomain, <2>node, SMT DEF cell, RHSOutputRows, RHSOutputInput!\#(sourceRows)
            <2>payload. cell(node).payload = (IF cell(node).kind = "read"
                                             THEN RHSOutputInput!MasterNodeReadKeys[index][node]
                                             ELSE RHSOutputInput!MasterNodeLiterals[index][node])
                BY ONLY <1>sourceDomain, <2>node, <2>kind, SMT DEF cell, RHSOutputRows, RHSOutputInput!\#(sourceRows)
            <2>children. /\ cell(node).left = RHSOutputInput!MasterNodeLeft[index][node]
                         /\ cell(node).right = RHSOutputInput!MasterNodeRight[index][node]
                BY ONLY <1>sourceDomain, <2>node, SMT DEF cell, RHSOutputRows, RHSOutputInput!\#(sourceRows)
            <2>. QED BY ONLY <2>kind, <2>payload, <2>children
        <1>expectedCells. \A node \in 1..expected.count :
            /\ expected.kinds[node] = cell(node).kind
            /\ (expected.kinds[node] = "literal" => expected.literals[node] = cell(node).payload)
            /\ (expected.kinds[node] = "read" => expected.reads[node] = cell(node).payload)
            /\ expected.left[node] = cell(node).left
            /\ expected.right[node] = cell(node).right
            <2>. TAKE node \in 1..expected.count
            <2>kind. expected.kinds[node] = cell(node).kind
                BY ONLY (node \in 1..expected.count), SMT DEF cell, expected,
                    RHSOutputInput!Rule!AssignmentRhsPlan, RHSOutputInput!Rule!ExtractedNodePlan
            <2>literals. expected.kinds[node] = "literal" => expected.literals[node] = cell(node).payload
                BY ONLY <2>kind, (node \in 1..expected.count), SMT DEF cell, expected,
                    RHSOutputInput!Rule!AssignmentRhsPlan, RHSOutputInput!Rule!ExtractedNodePlan
            <2>reads. expected.kinds[node] = "read" => expected.reads[node] = cell(node).payload
                BY ONLY <2>kind, (node \in 1..expected.count), SMT DEF cell, expected,
                    RHSOutputInput!Rule!AssignmentRhsPlan, RHSOutputInput!Rule!ExtractedNodePlan
            <2>children. /\ expected.left[node] = cell(node).left
                         /\ expected.right[node] = cell(node).right
                BY ONLY (node \in 1..expected.count), SMT DEF cell, expected,
                    RHSOutputInput!Rule!AssignmentRhsPlan, RHSOutputInput!Rule!ExtractedNodePlan
            <2>. QED BY ONLY <2>kind, <2>literals, <2>reads, <2>children
        <1>ops. RHSOutputInput!Rule!PhysicalAssignmentOperandsMatch(RHSOutputRows[index], physical)
            <2>nodes. \A node \in 1..expected.count :
                /\ physical.kinds[node] = expected.kinds[node]
                /\ (expected.kinds[node] = "literal" => physical.literals[node] = expected.literals[node])
                /\ (expected.kinds[node] = "add" =>
                      /\ physical.left[node] = expected.left[node]
                      /\ physical.right[node] = expected.right[node])
                BY ONLY <1>physicalColumns, <1>sourceCells, <1>expectedCells, <1>kinds, <1>literals, <1>children, SMT
            <2>. QED BY ONLY <1>shape, <2>nodes DEF RHSOutputInput!Rule!PhysicalAssignmentOperandsMatch, expected
        <1>targets. \A prior \in DOMAIN RHSOutputRows :
            RHSOutputRows[prior].target = RHSOutputInput!MasterTargets[prior]
            BY ONLY SMT DEF RHSOutputRows, RHSOutputInput!\#(sourceRows)
        <1>reads. \A node \in 1..expected.count : expected.kinds[node] = "read" =>
                /\ expected.reads[node] \in RHSOutputInput!\#(sourceFields)
                /\ RHSOutputInput!Rule!CopyReceiptNamesWriter(RHSOutputRows, index - 1, expected.reads[node], physical.reads[node])
            <2>. SUFFICES ASSUME NEW node \in 1..expected.count, expected.kinds[node] = "read"
                PROVE /\ expected.reads[node] \in RHSOutputInput!\#(sourceFields)
                      /\ RHSOutputInput!Rule!CopyReceiptNamesWriter(RHSOutputRows, index - 1, expected.reads[node], physical.reads[node])
                OBVIOUS
            <2>. DEFINE key == RHSOutputInput!MasterNodeReadKeys[index][node]
                        reference == RHSOutputNodeReads[index][node]
                        writer == RHSOutputInput!Rule!CopyReceiptOrdinal(reference)
            <2>projected. /\ key = expected.reads[node] /\ reference = physical.reads[node]
                <3>physical. reference = physical.reads[node]
                    BY ONLY <1>physicalDomain, SMT DEF reference, physical, RHSOutputPlans
                <3>authored. key = expected.reads[node]
                    BY ONLY <1>sourceCells, <1>expectedCells, (node \in 1..expected.count),
                        (expected.kinds[node] = "read"), SMT DEF key
                <3>. QED BY ONLY <3>physical, <3>authored
            <2>slot. /\ node \in 1..RHSOutputInput!MasterNodeCounts[index]
                     /\ RHSOutputInput!MasterNodeKinds[index][node] = "read"
                BY ONLY <1>shape, <1>sourceCells, <1>expectedCells, (node \in 1..expected.count),
                    (expected.kinds[node] = "read"), SMT
            <2>field. key \in RHSOutputInput!\#(sourceFields)
                BY ONLY <1>sourceDomain, <2>slot, SMT
                    DEF key, RHSOutputInput!MasterNodeCounts, RHSOutputInput!MasterNodeReadKeys, RHSOutputInput!\#(sourceFields)
            <2>positionColumns. /\ writer \in 0..(index - 1)
                                /\ (writer = 0 \/ RHSOutputInput!MasterTargets[writer] = key)
                                /\ \A prior \in 1..(index - 1) :
                                      RHSOutputInput!MasterTargets[prior] = key => prior <= writer
                BY ONLY <1>sourceDomain, <2>slot, SMT
                    DEF key, reference, writer, RHSOutputInput!MasterTargets,
                        RHSOutputInput!MasterNodeCounts, RHSOutputInput!MasterNodeKinds, RHSOutputInput!MasterNodeReadKeys,
                        RHSOutputNodeReads, RHSOutputInput!Rule!CopyReceiptOrdinal
            <2>earlierRows. /\ 1..(index - 1) \subseteq DOMAIN RHSOutputRows
                            /\ (writer # 0 => writer \in DOMAIN RHSOutputRows)
                BY ONLY <1>domain, (index \in DOMAIN RHSOutputRows), <2>positionColumns, SMT
            <2>position. RHSOutputInput!Rule!LastDirectCopy(RHSOutputRows, index - 1, key, writer)
                BY ONLY <1>targets, <2>positionColumns, <2>earlierRows, SMT DEF RHSOutputInput!Rule!LastDirectCopy
            <2>reference. reference = RHSOutputInput!Rule!DirectCopyReference(key, writer)
                BY ONLY <1>sourceDomain, <2>slot, SMT
                    DEF key, reference, writer, RHSOutputInput!MasterNodeCounts, RHSOutputInput!MasterNodeKinds,
                        RHSOutputInput!MasterNodeReadKeys, RHSOutputNodeReads,
                        RHSOutputInput!Rule!CopyReceiptOrdinal, RHSOutputInput!Rule!DirectCopyReference
            <2>. QED BY ONLY <2>projected, <2>field, <2>position, <2>reference, SMT
                DEF writer, RHSOutputInput!Rule!CopyReceiptNamesWriter
        <1>named. RHSOutputInput!Rule!PhysicalAssignmentReadsNameWriters(RHSOutputRows, index, physical)
            BY ONLY <1>ops, <1>reads, SMT DEF RHSOutputInput!Rule!PhysicalAssignmentReadsNameWriters, expected
        <1>range. index \in 1..Len(RHSOutputRows)
            BY ONLY <1>domain, (index \in DOMAIN RHSOutputRows), SMT
        <1>. QED BY ONLY <1>range, <1>named, <1>domain, RHSOutputUsesTheMachineIntegerDomain,
            RHSOutputInput!Rule!NamedAssignmentOperandsMatchTheirRoutes, SMT DEF physical

        THEOREM ActualRenderedWriteRoutesAreTheFinalAuthoredWriters ==
            RHSOutputWriteRoutes = RHSOutputInput!Rule!DirectCopyRoutes(RHSOutputKeys, RHSOutputRows)[RHSOutputCount]
        PROOF
        <1>routes. \A key \in RHSOutputKeys :
            RHSOutputInput!Rule!CopyReceiptNamesWriter(RHSOutputRows, RHSOutputCount, key, RHSOutputWriteRoutes[key])
            BY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
               DEF RHSOutputRows, RHSOutputInput!\#(sourceRows), RHSOutputInput!MasterNodeCounts,
                   RHSOutputInput!MasterTargets, RHSOutputWriteRoutes, RHSOutputKeys, RHSOutputCount,
                   RHSOutputInput!Rule!CopyReceiptNamesWriter, RHSOutputInput!Rule!CopyReceiptOrdinal,
                   RHSOutputInput!Rule!LastDirectCopy, RHSOutputInput!Rule!DirectCopyReference
        <1>. QED BY <1>routes, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory,
            RHSOutputInput!Rule!NamedAssignmentReadRouteIsTheScheduledRoute, SMT
            DEF RHSOutputWriteRoutes, RHSOutputKeys, RHSOutputCount, RHSOutputInput!Rule!SupportedAssignmentList,
                RHSOutputInput!Rule!DirectCopyRoutes

        THEOREM ActualRenderedTermsAndGuardsSupplyTheAssignmentInventory ==
            ASSUME RHSOutputStateType
            PROVE RHSOutputInput!Rule!RenderedAssignmentInventory(RHSOutputRows, RHSOutputBefore, RHSOutputRaw)
        PROOF
        <1>terms. \A index \in DOMAIN RHSOutputRows :
            RHSOutputInput!Rule!RenderedRhsTerms(RHSOutputPlans[index], RHSOutputBefore,
                RHSOutputInput!Rule!HistoryPrefix(RHSOutputRaw.roots, index - 1),
                RHSOutputStarts[index], RHSOutputRaw.terms[index])
            BY RHSOutputStateType, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
                DEF RHSOutputRaw, RHSOutputStarts, RHSOutputPlans, RHSOutputNodeCounts, RHSOutputNodeKinds,
                    RHSOutputNodeLiterals, RHSOutputNodeReads, RHSOutputNodeLeft, RHSOutputNodeRight,
                    RHSOutputStateType, RHSOutputBefore,
                    RHSOutputKeys, RHSOutputInput!Rule!RenderedRhsTerms, RHSOutputInput!Rule!PhysicalRhsBindings,
                    RHSOutputInput!Rule!HistoryPrefix, RHSOutputInput!Rule!CopyReferenceValue
        <1>guards. \A index \in DOMAIN RHSOutputRows :
            RHSOutputInput!Rule!RenderedRhsGuards(RHSOutputPlans[index], RHSOutputRaw.terms[index], RHSOutputRaw.guards[index])
            BY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
               DEF RHSOutputRaw, RHSOutputPlans, RHSOutputNodeCounts, RHSOutputNodeKinds, RHSOutputNodeLeft, RHSOutputNodeRight,
                   RHSOutputMin, RHSOutputMax,
                   RHSOutputInput!Rule!RenderedRhsGuards, RHSOutputInput!Rule!GeneratedAddDefined, RHSOutputInput!Rule!SmallAddOperands
        <1>roots. \A index \in DOMAIN RHSOutputRows :
            RHSOutputRaw.roots[index] = RHSOutputRaw.terms[index][RHSOutputPlans[index].count]
            BY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
                DEF RHSOutputRaw, RHSOutputPlans, RHSOutputNodeCounts
        <1>. QED BY <1>terms, <1>guards, <1>roots, ActualRenderedRightHandSidesMatchAuthoredAssignmentRoutes,
            SMT DEF RHSOutputInput!Rule!RenderedAssignmentInventory, RHSOutputRaw

        THEOREM ActualEmittedActionUsesThePhysicalGuardTable ==
            ASSUME RHSOutputStateType
            PROVE
                /\ (\#(step.renderedName) <=> RHSOutputRawAdvance)
                /\ RHSOutputFailureSelected = (RHSOutputSelected /\ ~RHSOutputPasses)
                /\ RHSOutputSelectedSubExpressions =
                    {place \in RHSOutputPhysicalNodeSlots :
                         RHSOutputSelected /\ RHSOutputFailsAt(place)}
                /\ \A probe \in RHSOutputFailureProbeSites :
                    LET place == RHSOutputProbePositions[probe]
                        row == RHSOutputPlans[place[1]]
                        terms == RHSOutputRaw.terms[place[1]]
                    IN RHSOutputPayloads[probe] =
                        [operation |-> "addition", operands |-> <<terms[row.left[place[2]]], terms[row.right[place[2]]]>>,
                         prefix |-> RHSOutputInput!Rule!HistoryPrefix(RHSOutputRaw.roots, place[1] - 1)]
        PROOF
        <1>advance. \#(step.renderedName) <=> RHSOutputRawAdvance
            BY RHSOutputStateType, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
                DEF \#(step.renderedName), RHSOutputRawAdvance, RHSOutputRaw, RHSOutputPasses, RHSOutputSelected,
                    RHSOutputEntry, RHSOutputExit, RHSOutputAfter, RHSOutputBefore, RHSOutputCount, RHSOutputKeys,
                    RHSOutputWriteRoutes, RHSOutputPlans, RHSOutputNodeCounts, RHSOutputInput!Rule!RenderedAssignmentsPass,
                    RHSOutputInput!Rule!EveryRenderedGuardPasses, RHSOutputInput!Rule!CopyMaterializedState,
                    RHSOutputInput!Rule!CopyReferenceValue
        <1>aggregate. RHSOutputFailureSelected = (RHSOutputSelected /\ ~RHSOutputPasses)
            BY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
                DEF RHSOutputSelected, RHSOutputEntry, RHSOutputFailureSelected\#(aggregateName), RHSOutputPasses,
                    RHSOutputCount, RHSOutputRaw, RHSOutputPlans, RHSOutputNodeCounts, RHSOutputInput!Rule!RenderedAssignmentsPass,
                    RHSOutputInput!Rule!EveryRenderedGuardPasses
        <1>sites. RHSOutputSelectedSubExpressions =
            {place \in RHSOutputPhysicalNodeSlots :
                RHSOutputSelected /\ RHSOutputFailsAt(place)}
            BY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SetExtensionality, SMT
                DEF RHSOutputSelectedSubExpressions, RHSOutputPhysicalNodeSlots, RHSOutputFailureProbeSites, RHSOutputProbePositions, RHSOutputGuards,
                    RHSOutputRaw, RHSOutputPlans, RHSOutputNodeCounts, RHSOutputCount, RHSOutputSelected, RHSOutputEntry, RHSOutputFailsAt,
                    RHSOutputInput!Rule!RenderedAssignmentFailsAt, RHSOutputInput!Rule!RenderedAssignmentsPass,
                    RHSOutputInput!Rule!FirstRejectedRenderedGuard, RHSOutputInput!Rule!EveryRenderedGuardPasses\#(predicateNames)
        <1>payloads. \A probe \in RHSOutputFailureProbeSites :
            LET place == RHSOutputProbePositions[probe]
                row == RHSOutputPlans[place[1]]
                terms == RHSOutputRaw.terms[place[1]]
            IN RHSOutputPayloads[probe] =
                [operation |-> "addition", operands |-> <<terms[row.left[place[2]]], terms[row.right[place[2]]]>>,
                 prefix |-> RHSOutputInput!Rule!HistoryPrefix(RHSOutputRaw.roots, place[1] - 1)]
            BY SMT DEF RHSOutputFailureProbeSites, RHSOutputProbePositions, RHSOutputPayloads, RHSOutputGuards,
                RHSOutputRaw, RHSOutputPlans, RHSOutputNodeLeft, RHSOutputNodeRight, RHSOutputInput!Rule!HistoryPrefix\#(actualNames)
        <1>. QED BY <1>advance, <1>aggregate, <1>sites, <1>payloads

        THEOREM ActualTLAActionObservesTheCertifiedAssignmentHistory ==
            ASSUME RHSOutputStateType, NEW history, RHSOutputSourceHistory(history)
            PROVE RHSOutputHistoryObservation(history)
        PROOF
        <1>shape. RHSOutputInput!Rule!SupportedAssignmentList(RHSOutputRows)
            BY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory
        <1>inventory. RHSOutputInput!Rule!RenderedAssignmentInventory(RHSOutputRows, RHSOutputBefore, RHSOutputRaw)
            BY RHSOutputStateType, ActualRenderedTermsAndGuardsSupplyTheAssignmentInventory
        <1>history. /\ RHSOutputInput!Rule!RenderedAssignmentHistoryAt(RHSOutputRows, RHSOutputBefore, RHSOutputRaw, history, RHSOutputCount)
                    /\ RHSOutputInput!Rule!AssignmentPrefixMeaning(RHSOutputBefore, RHSOutputRows, history, RHSOutputCount)
            BY RHSOutputStateType, RHSOutputSourceHistory(history), <1>shape, <1>inventory,
                RHSOutputInput!Rule!PhysicalGuardedAssignmentTablesDetermineTheCompleteOutcome,
                RHSOutputInput!Rule!OrderedAssignmentHistoriesRetainTheExactFirstFailurePrefix, SMT
                DEF RHSOutputSourceHistory, RHSOutputStateType, RHSOutputCount, RHSOutputInput!Rule!AssignmentBindings,
                    RHSOutputInput!Rule!AssignmentIntValues, RHSOutputInput!Rule!SupportedAssignmentList
        <1>reached. ~RHSOutputPasses <=>
            (\E index \in 1..RHSOutputCount : \E node \in 1..RHSOutputPlans[index].count : RHSOutputFailsAt(<<index, node>>))
            BY <1>shape, <1>inventory, RHSOutputInput!Rule!WholeGuardTableHasAnExactFirstFailureSite, SMT
                DEF RHSOutputPasses, RHSOutputFailsAt, RHSOutputCount, RHSOutputRaw
        <1>frame. \#(step.renderedName) <=> RHSOutputHistoryAdvance(history)
            BY <1>history, <1>reached, ActualEmittedActionUsesThePhysicalGuardTable,
                ActualRenderedWriteRoutesAreTheFinalAuthoredWriters, SMT
                DEF RHSOutputHistoryAdvance, RHSOutputRawAdvance, RHSOutputCount, RHSOutputPasses, RHSOutputFailsAt,
                    RHSOutputRaw, RHSOutputInput!Rule!RenderedAssignmentHistoryAt, RHSOutputInput!Rule!RenderedAssignmentFailure,
                    RHSOutputInput!Rule!AssignmentPrefixMeaning, RHSOutputInput!Rule!CompletedAssignmentBindings,
                    RHSOutputInput!Rule!HistoryPrefix, RHSOutputInput!Rule!SupportedAssignmentList
        <1>failure. RHSOutputActualFailures = RHSOutputHistoryFailures(history)
            BY <1>history, <1>reached, ActualEmittedActionUsesThePhysicalGuardTable, SetExtensionality, SMT
                DEF RHSOutputActualFailures, RHSOutputHistoryFailures, RHSOutputFailureEvent,
                    RHSOutputSelectedSubExpressions, RHSOutputPhysicalNodeSlots, RHSOutputPasses, RHSOutputFailsAt, RHSOutputCount,
                    RHSOutputRaw, RHSOutputFailureProbeSites, RHSOutputInput!Rule!RenderedAssignmentHistoryAt,
                    RHSOutputInput!Rule!RenderedAssignmentFailure, RHSOutputInput!Rule!RenderedTermOverflow, RHSOutputInput!Rule!GeneratedOverflow
        <1>aggregate. RHSOutputFailureSelected = (RHSOutputActualFailures # {})
            BY <1>history, <1>reached, <1>failure, ActualEmittedActionUsesThePhysicalGuardTable, SMT
                DEF RHSOutputHistoryFailures, RHSOutputPasses, RHSOutputFailsAt,
                    RHSOutputInput!Rule!RenderedAssignmentHistoryAt, RHSOutputInput!Rule!RenderedAssignmentFailure
        <1>terminal. \#(terminal.renderedName) <=> RHSOutputTermination
            BY SMT DEF \#(terminal.renderedName), RHSOutputTermination, RHSOutputExit, RHSOutputKeys, RHSOutputBefore, RHSOutputAfter
        <1>next. Next <=> (RHSOutputHistoryAdvance(history) \/ RHSOutputTermination)
            BY ONLY <1>terminal, <1>frame DEF Next
        <1>. QED BY ONLY <1>frame, <1>failure, <1>aggregate, <1>next DEF RHSOutputHistoryObservation

        THEOREM ActualTLAActionHasACertifiedAssignmentHistory ==
            ASSUME RHSOutputStateType
            PROVE \E history :
                /\ RHSOutputSourceHistory(history)
                /\ RHSOutputGeneratedHistory(history)
                /\ RHSOutputHistoryObservation(history)
        PROOF
        <1>history. PICK history : RHSOutputSourceHistory(history) /\ RHSOutputGeneratedHistory(history)
            BY RHSOutputStateType, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory,
                RHSOutputInput!Rule!CertifiedOrderedAssignmentListConstructsCompleteActionOutcome, SMT
                DEF RHSOutputStateType, RHSOutputSourceHistory, RHSOutputGeneratedHistory,
                    RHSOutputInput!Rule!AssignmentBindings, RHSOutputInput!Rule!AssignmentIntValues
        <1>observed. RHSOutputHistoryObservation(history)
            BY RHSOutputStateType, <1>history, ActualTLAActionObservesTheCertifiedAssignmentHistory
        <1>. WITNESS history
        <1>. QED BY <1>history, <1>observed

        ====

        """#
        return (name, Data(proof.utf8))
    }

    private static func lookup(_ roots: [CompiledVariableLayout], primed: Bool) -> String {
        let prime = primed ? "'" : ""
        let choices = roots.dropLast().map {
            "key = \(TLAValue.string($0.declaration.name)) -> \($0.formalName)\(prime)"
        }
        let fallback = roots.last.map { $0.formalName + prime } ?? "FALSE"
        return choices.isEmpty ? fallback : "CASE " + choices.joined(separator: " [] ") + " [] OTHER -> " + fallback
    }

    private static func formalIdentifier(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z_][A-Za-z_0-9]*$", options: .regularExpression) != nil
    }
}
