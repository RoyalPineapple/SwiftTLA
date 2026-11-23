import Foundation
import SwiftTLA

package enum OrderedRHSTLAProof {
    /// The source module owns independently selected authored rows and their certificate support.
    static func render(
        _ rendered: RenderedSpecification, program: CompiledProgram, source: AuthoredCopySyntax.ArithmeticProofInput
    ) throws -> (name: String, bytes: Data)? {
        let bundle = rendered.tlaBundle
        let layout = program.layout
        let controls = layout.variables.filter { $0.declaration.origin == .programCounter }
        let roots = layout.variables.filter { $0.declaration.origin == .source }
        let live = layout.actions.filter { !$0.isTermination }
        let terminals = layout.actions.filter(\.isTermination)
        let sourceAction = source.label
        guard bundle.imports.isEmpty, layout.parameters.isEmpty,
              case .compiled(let identity, _, _) = bundle.provenance, identity == program.identity,
              controls.count == 1, let counter = controls.first, !roots.isEmpty,
              roots.count + 1 == layout.variables.count,
              roots.allSatisfy({ program.variableTypes[$0.id] == .int }),
              live.count == source.labels.count, live.indices.contains(source.ordinal),
              zip(live, source.labels).allSatisfy({ $0.0.declaration.name.utf8.elementsEqual($0.1.utf8) }),
              terminals.count == 1, let terminal = terminals.first, layout.actions.last == terminal,
              rendered.actions.map(\.renderedName) == layout.actions.map(\.renderedName),
              rendered.actions.allSatisfy({ $0.arguments.isEmpty }) else { return nil }
        let step = live[source.ordinal]
        guard step.id.ordinal == source.ordinal, program.requiresOrderedIntOutput(step.id) else { return nil }
        let direct = try program.renderModule()
        guard direct.renderedModuleSource.utf8.elementsEqual(bundle.root.tla.utf8),
              let normalCFG = bundle.root.cfg,
              normalCFG.utf8.elementsEqual(try direct.configuration.render(usesSymmetryReduction: false).utf8)
        else { return nil }

        let action = program[step.id]
        let owner = ControlOwner.sequential(algorithm: source.algorithm)
        guard action.bindings.isEmpty,
              case .and(.guard_(let gate), let body) = action.body,
              case .equal = gate.operation, gate.children.count == 2,
              gate.children[0].operation == .stateVariable(counter.id),
              case .controlLocation(let entryID) = gate.children[1].operation,
              let entry = layout.controlLocations.first(where: { $0.id == entryID }),
              entry.owner == owner, entry.sourceName.utf8.elementsEqual(sourceAction.utf8),
              let destinationID = controlDestination(in: body, for: counter.id),
              let destination = layout.controlLocations.first(where: { $0.id == destinationID }) else { return nil }
        let doneName = CompilerControlSymbol.done.rawValue
        let expectedOwner = source.continuation == nil
            ? ControlOwner.generated(algorithm: source.algorithm, purpose: doneName) : owner
        guard destination.owner == expectedOwner, destination.id != entry.id,
              destination.sourceName.utf8.elementsEqual((source.continuation ?? doneName).utf8) else { return nil }
        let entryControl = try CompiledValue.controlLocation(entry.id).rendered(using: layout)
        let endControl = try CompiledValue.controlLocation(destination.id).rendered(using: layout)
        guard let physical = OrderedRHSPhysicalAction.decode(in: bundle.root.tla, action: step.renderedName,
            body: body, fields: roots, counter: counter, destination: endControl.description) else { return nil }

        // Preserve the original one-action packet. In a larger machine the selected action proof
        // has no conclusion about the other actions or the disjunction in Next.
        let wholeModule = live.count == 1
        let suffix = wholeModule ? "" : "\(bundle.root.name)Action\(step.id.ordinal + 1)"
        let name = "SwiftTLAOrderedRHSOutputProof" + suffix
        let identifiers = [bundle.root.name, name, source.name, counter.formalName, step.renderedName,
                           terminal.renderedName] + roots.map(\.formalName)
        guard identifiers.allSatisfy(formalIdentifier), !bundle.root.tla.contains("RHSOutput"),
              ![bundle.root.name, source.name].contains(name) else { return nil }

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
        let operationNames = definitions(probes.map(\.operation))
        let operandNames = definitions(probes.map(\.operands))
        let prefixNames = definitions(probes.map(\.before))
        let predicateNames = definitions(probes.map(\.failed))
        let aggregateName = definitions(aggregate.map { [$0] } ?? [])
        let failureGuards = tuple(probes.map(\.failed))
        let failureData = probes.map { site in
            "(IF \(site.failed) THEN [operands |-> \(site.operands), "
                + "operation |-> \(site.operation), prefix |-> \(site.before)] ELSE <<>>)"
        }.joined(separator: ",\n    ")
        let keys = TLAValue.set(Set(roots.map { .string($0.declaration.name) }))
        let pc = counter.formalName
        let compiledContinuation: String?
        if case .sequential = destination.owner { compiledContinuation = destination.sourceName }
        else { compiledContinuation = nil }
        guard case .sequential(let compiledAlgorithm) = entry.owner else { return nil }
        let compiledRoute = AuthoredCopySyntax.arithmeticRoute(algorithm: compiledAlgorithm,
            label: step.declaration.name, ordinal: step.id.ordinal, continuation: compiledContinuation)
        let routeDefinition = wholeModule ? #"""
        RHSOutputTermination ==
            /\ \#(pc) = RHSOutputExit /\ UNCHANGED \#(pc)
            /\ RHSOutputBefore = RHSOutputAfter
        """# : "RHSOutputCompiledRoute == \(compiledRoute)"
        let routeObservation = wholeModule ? #"""
            /\ (Next <=> (RHSOutputHistoryAdvance(history) \/ RHSOutputTermination))
        """# : #"""
            /\ RHSOutputCompiledRoute = RHSOutputInput!MasterSelectedRoute
        """#
        let routeProof = wholeModule ? #"""
        <1>terminal. \#(terminal.renderedName) <=> RHSOutputTermination
            BY SMT DEF \#(terminal.renderedName), RHSOutputTermination, RHSOutputExit, RHSOutputKeys, RHSOutputBefore, RHSOutputAfter
        <1>next. Next <=> (RHSOutputHistoryAdvance(history) \/ RHSOutputTermination)
            BY ONLY <1>terminal, <1>frame DEF Next
        """# : #"""
        <1>route. RHSOutputCompiledRoute = RHSOutputInput!MasterSelectedRoute
            BY ONLY DEF RHSOutputCompiledRoute, RHSOutputInput!MasterSelectedRoute
        """#
        let routeFact = wholeModule ? "<1>next" : "<1>route"
        let proof = #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(bundle.root.name), TLAPS

        RHSOutputKeys == \#(keys)
        RHSOutputMin == \#(TLAValue.int(Int.min))
        RHSOutputMax == \#(TLAValue.int(Int.max))
        RHSOutputInput == INSTANCE \#(source.name)

        RHSOutputRows == RHSOutputInput!MasterRows
        RHSOutputBefore == [key \in RHSOutputKeys |-> \#(lookup(roots, primed: false))]
        RHSOutputAfter == [key \in RHSOutputKeys |-> \#(lookup(roots, primed: true))]
        RHSOutputStateType == RHSOutputBefore \in [RHSOutputKeys -> RHSOutputMin..RHSOutputMax]
        RHSOutputActionLabel == \#(TLAValue.string(sourceAction))
        RHSOutputEntry == \#(entryControl)
        RHSOutputExit == \#(endControl)
        RHSOutputSelected == \#(pc) = RHSOutputEntry
        RHSOutputFailureSelected == \#(aggregate ?? "FALSE")
        RHSOutputCount == Len(RHSOutputRows)

        RHSOutputNodeCounts == \#(counts)
        RHSOutputNodeKinds == \#(kinds)
        RHSOutputNodeLiterals == \#(literals)
        RHSOutputNodeReads == \#(reads)
        RHSOutputNodeLeft == \#(left)
        RHSOutputNodeRight == \#(right)
        RHSOutputPlans == [index \in DOMAIN RHSOutputNodeCounts |->
            [count |-> RHSOutputNodeCounts[index], kinds |-> RHSOutputNodeKinds[index],
             literals |-> RHSOutputNodeLiterals[index], reads |-> RHSOutputNodeReads[index],
             left |-> RHSOutputNodeLeft[index], right |-> RHSOutputNodeRight[index]]]
        LOCAL RHSOutputStarts == \#(starts)
        LOCAL RHSOutputRaw ==
            \#(scoped)[plans |-> RHSOutputPlans, starts |-> RHSOutputStarts,
                        terms |-> \#(terms), guards |-> \#(guards), roots |-> \#(values)]\#(closed)
        RHSOutputWriteRoutes == \#(writeRoutes)
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

        \#(routeDefinition)

        RHSOutputSourceHistory(history) ==
            RHSOutputInput!Rule!AssignmentListHistory(FALSE, RHSOutputBefore, RHSOutputRows, history)
        RHSOutputGeneratedHistory(history) ==
            RHSOutputInput!Rule!AssignmentListHistory(TRUE, RHSOutputBefore, RHSOutputRows, history)
        RHSOutputHistoryObservation(history) ==
            /\ (\#(step.renderedName) <=> RHSOutputHistoryAdvance(history))
            /\ RHSOutputActualFailures = RHSOutputHistoryFailures(history)
            /\ RHSOutputFailureSelected = (RHSOutputActualFailures # {})
        \#(routeObservation)

        THEOREM RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory ==
            /\ RHSOutputKeys = RHSOutputInput!MasterFields
            /\ RHSOutputInput!Rule!SupportedAssignmentList(RHSOutputRows)
            /\ RHSOutputCount = \#(physical.captures.count)
            /\ DOMAIN RHSOutputRows = DOMAIN RHSOutputPlans
        PROOF
        <1>fields. RHSOutputKeys = RHSOutputInput!MasterFields
            BY ONLY SMT DEF RHSOutputKeys, RHSOutputInput!MasterFields
        <1>authored. /\ RHSOutputInput!Rule!SupportedAssignmentList(RHSOutputRows)
                     /\ RHSOutputCount = \#(physical.captures.count)
            BY ONLY RHSOutputInput!MasterAssignmentsAreSupported, SMT DEF RHSOutputRows, RHSOutputCount
        <1>domain. DOMAIN RHSOutputRows = DOMAIN RHSOutputPlans
            BY ONLY SMT DEF RHSOutputRows, RHSOutputInput!MasterRows, RHSOutputInput!MasterNodeCounts, RHSOutputPlans, RHSOutputNodeCounts
        <1>. QED BY ONLY <1>fields, <1>authored, <1>domain

        THEOREM RHSOutputUsesTheMachineIntegerDomain ==
            RHSOutputInput!Rule!IntegerDomain
            BY ONLY SMT DEF RHSOutputInput!Rule!IntegerDomain

        THEOREM ActualRenderedRightHandSidesNameTheAuthoredWriters ==
            \A index \in DOMAIN RHSOutputRows :
                RHSOutputInput!Rule!PhysicalAssignmentReadsNameWriters(RHSOutputRows, index, RHSOutputPlans[index])
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
                DEF physical, expected, RHSOutputPlans, RHSOutputRows, RHSOutputInput!MasterRows,
                    RHSOutputInput!Rule!AssignmentRhsPlan, RHSOutputInput!Rule!ExtractedNodePlan
        <1>physicalDomain. index \in DOMAIN RHSOutputPlans
            BY ONLY <1>domain, (index \in DOMAIN RHSOutputRows), SMT
        <1>physicalColumns. /\ physical.kinds = RHSOutputNodeKinds[index]
                            /\ physical.literals = RHSOutputNodeLiterals[index]
                            /\ physical.left = RHSOutputNodeLeft[index]
                            /\ physical.right = RHSOutputNodeRight[index]
            BY ONLY <1>physicalDomain, SMT DEF physical, RHSOutputPlans
        <1>sourceDomain. index \in DOMAIN RHSOutputInput!MasterNodeCounts
            BY ONLY (index \in DOMAIN RHSOutputRows), SMT DEF RHSOutputRows, RHSOutputInput!MasterRows
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
                BY ONLY <1>sourceDomain, <2>node, SMT DEF cell, RHSOutputRows, RHSOutputInput!MasterRows,
                    RHSOutputInput!MasterNodes
            <2>payload. cell(node).payload = (IF cell(node).kind = "read"
                                             THEN RHSOutputInput!MasterNodeReadKeys[index][node]
                                             ELSE RHSOutputInput!MasterNodeLiterals[index][node])
                BY ONLY <1>sourceDomain, <2>node, <2>kind, SMT DEF cell, RHSOutputRows, RHSOutputInput!MasterRows,
                    RHSOutputInput!MasterNodes
            <2>children. /\ cell(node).left = RHSOutputInput!MasterNodeLeft[index][node]
                         /\ cell(node).right = RHSOutputInput!MasterNodeRight[index][node]
                BY ONLY <1>sourceDomain, <2>node, SMT DEF cell, RHSOutputRows, RHSOutputInput!MasterRows,
                    RHSOutputInput!MasterNodes
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
            BY ONLY SMT DEF RHSOutputRows, RHSOutputInput!MasterRows
        <1>reads. \A node \in 1..expected.count : expected.kinds[node] = "read" =>
                /\ expected.reads[node] \in RHSOutputInput!MasterFields
                /\ RHSOutputInput!Rule!CopyReceiptNamesWriter(RHSOutputRows, index - 1, expected.reads[node], physical.reads[node])
            <2>. SUFFICES ASSUME NEW node \in 1..expected.count, expected.kinds[node] = "read"
                PROVE /\ expected.reads[node] \in RHSOutputInput!MasterFields
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
            <2>field. key \in RHSOutputInput!MasterFields
                BY ONLY <1>sourceDomain, <2>slot, SMT
                    DEF key, RHSOutputInput!MasterNodeCounts, RHSOutputInput!MasterNodeReadKeys, RHSOutputInput!MasterFields
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
        <1>. QED BY ONLY <1>named DEF physical

        THEOREM ActualRenderedRightHandSidesMatchAuthoredAssignmentRoutes ==
            \A index \in DOMAIN RHSOutputRows :
                RHSOutputInput!Rule!PhysicalAssignmentReadsMatchRoutes(RHSOutputRows, index, RHSOutputPlans[index])
        PROOF
        <1>domain. /\ Len(RHSOutputRows) \in Nat
                   /\ DOMAIN RHSOutputRows = 1..Len(RHSOutputRows)
            BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory
                DEF RHSOutputInput!Rule!SupportedAssignmentList
        <1>. TAKE index \in DOMAIN RHSOutputRows
        <1>range. index \in 1..Len(RHSOutputRows)
            BY ONLY <1>domain, (index \in DOMAIN RHSOutputRows), SMT
        <1>. QED BY ONLY <1>range, <1>domain, (index \in DOMAIN RHSOutputRows),
            ActualRenderedRightHandSidesNameTheAuthoredWriters, RHSOutputUsesTheMachineIntegerDomain,
            RHSOutputInput!Rule!NamedAssignmentOperandsMatchTheirRoutes, SMT

        THEOREM ActualRenderedWriteRoutesNameTheAuthoredWriters ==
            \A key \in RHSOutputKeys :
                RHSOutputInput!Rule!CopyReceiptNamesWriter(RHSOutputRows, RHSOutputCount, key, RHSOutputWriteRoutes[key])
        BY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
           DEF RHSOutputRows, RHSOutputInput!MasterRows, RHSOutputInput!MasterNodeCounts,
               RHSOutputInput!MasterTargets, RHSOutputWriteRoutes, RHSOutputKeys, RHSOutputCount,
               RHSOutputInput!Rule!CopyReceiptNamesWriter, RHSOutputInput!Rule!CopyReceiptOrdinal,
               RHSOutputInput!Rule!LastDirectCopy, RHSOutputInput!Rule!DirectCopyReference

        THEOREM ActualRenderedWriteRoutesAreTheFinalAuthoredWriters ==
            RHSOutputWriteRoutes = RHSOutputInput!Rule!DirectCopyRoutes(RHSOutputKeys, RHSOutputRows)[RHSOutputCount]
        PROOF
        <1>. DEFINE scheduled == RHSOutputInput!Rule!DirectCopyRoutes(RHSOutputKeys, RHSOutputRows)[RHSOutputCount]
        <1>bounds. /\ Len(RHSOutputRows) \in Nat /\ RHSOutputCount \in 0..Len(RHSOutputRows)
            BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
                DEF RHSOutputCount, RHSOutputInput!Rule!SupportedAssignmentList
        <1>fields. RHSOutputKeys = RHSOutputInput!MasterFields
            BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory
        <1>points. \A key \in RHSOutputKeys : RHSOutputWriteRoutes[key] = scheduled[key]
            <2>. TAKE key \in RHSOutputKeys
            <2>field. key \in RHSOutputInput!MasterFields
                BY ONLY <1>fields, (key \in RHSOutputKeys)
            <2>named. RHSOutputInput!Rule!CopyReceiptNamesWriter(RHSOutputRows, RHSOutputCount, key, RHSOutputWriteRoutes[key])
                BY ONLY (key \in RHSOutputKeys), ActualRenderedWriteRoutesNameTheAuthoredWriters, SMT
            <2>. QED BY ONLY <1>bounds, <1>fields, <2>field, <2>named, RHSOutputUsesTheMachineIntegerDomain,
                RHSOutputInput!Rule!NamedAssignmentReadRouteIsTheScheduledRoute, SMT DEF scheduled
        <1>actualShape. RHSOutputWriteRoutes = [key \in RHSOutputKeys |-> RHSOutputWriteRoutes[key]]
            BY ONLY SMT DEF RHSOutputWriteRoutes, RHSOutputKeys
        <1>scheduledShape. scheduled = [key \in RHSOutputKeys |-> scheduled[key]]
            BY ONLY <1>bounds, SMT DEF scheduled, RHSOutputInput!Rule!DirectCopyRoutes
        <1>. QED BY ONLY <1>points, <1>actualShape, <1>scheduledShape, SMT DEF scheduled

        THEOREM ActualRenderedTermsAndGuardsSupplyTheAssignmentInventory ==
            ASSUME RHSOutputStateType
            PROVE RHSOutputInput!Rule!RenderedAssignmentInventory(RHSOutputRows, RHSOutputBefore, RHSOutputRaw)
        PROOF
        <1>terms. \A index \in DOMAIN RHSOutputRows :
            RHSOutputInput!Rule!RenderedRhsTerms(RHSOutputPlans[index], RHSOutputBefore,
                RHSOutputInput!Rule!HistoryPrefix(RHSOutputRaw.roots, index - 1),
                RHSOutputStarts[index], RHSOutputRaw.terms[index])
            <2>domain. DOMAIN RHSOutputRows = DOMAIN RHSOutputNodeCounts
                BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT DEF RHSOutputPlans
            <2>state. \A key \in RHSOutputKeys : RHSOutputBefore[key] \in Int
                BY ONLY RHSOutputStateType, SMT DEF RHSOutputStateType, RHSOutputMin, RHSOutputMax
            <2>. TAKE index \in DOMAIN RHSOutputRows
            <2>. DEFINE plan == RHSOutputPlans[index]
                        starts == RHSOutputStarts[index]
                        terms == RHSOutputRaw.terms[index]
                        completed == RHSOutputInput!Rule!HistoryPrefix(RHSOutputRaw.roots, index - 1)
            <2>width. index \in DOMAIN RHSOutputNodeCounts
                BY ONLY <2>domain, (index \in DOMAIN RHSOutputRows), SMT
            <2>columns. /\ plan.count = RHSOutputNodeCounts[index]
                        /\ plan.kinds = RHSOutputNodeKinds[index]
                        /\ plan.literals = RHSOutputNodeLiterals[index]
                        /\ plan.reads = RHSOutputNodeReads[index]
                        /\ plan.left = RHSOutputNodeLeft[index]
                        /\ plan.right = RHSOutputNodeRight[index]
                BY ONLY <2>width, SMT DEF plan, RHSOutputPlans
            <2>root. /\ plan.count \in Nat \ {0}
                     /\ starts[plan.count] = 1
                BY ONLY <2>width, <2>columns, SMT DEF starts, RHSOutputStarts, RHSOutputNodeCounts
            <2>tree. \A node \in 1..plan.count :
                /\ starts[node] \in 1..node
                /\ plan.kinds[node] \in {"literal", "read", "add"}
                /\ (plan.kinds[node] # "add" => starts[node] = node)
                /\ (plan.kinds[node] = "add" =>
                      /\ plan.left[node] \in 1..(node - 1)
                      /\ plan.right[node] = node - 1
                      /\ starts[node] = starts[plan.left[node]]
                      /\ starts[plan.right[node]] = plan.left[node] + 1)
                BY ONLY <2>width, <2>columns, SMT
                    DEF starts, RHSOutputStarts, RHSOutputNodeCounts, RHSOutputNodeKinds, RHSOutputNodeLeft, RHSOutputNodeRight
            <2>values. \A node \in 1..plan.count :
                /\ terms[node] \in Int
                /\ (plan.kinds[node] = "literal" => terms[node] = plan.literals[node])
                /\ (plan.kinds[node] = "read" =>
                      terms[node] = RHSOutputInput!Rule!PhysicalRhsBindings(plan, RHSOutputBefore, completed)[node])
                /\ (plan.kinds[node] = "add" => terms[node] = terms[plan.left[node]] + terms[plan.right[node]])
                <3>. TAKE node \in 1..plan.count
                <3>integers. terms[node] \in Int
                    BY ONLY <2>width, <2>columns, <2>state, (node \in 1..plan.count), SMT
                        DEF terms, RHSOutputRaw, RHSOutputNodeCounts, RHSOutputBefore, RHSOutputKeys
                <3>literal. plan.kinds[node] = "literal" => terms[node] = plan.literals[node]
                    BY ONLY <2>width, <2>columns, (node \in 1..plan.count), SMT
                        DEF terms, RHSOutputRaw, RHSOutputNodeCounts, RHSOutputNodeKinds, RHSOutputNodeLiterals
                <3>reference. plan.kinds[node] = "read" =>
                    terms[node] = RHSOutputInput!Rule!CopyReferenceValue(RHSOutputBefore, completed, plan.reads[node])
                    BY ONLY <2>width, <2>columns, (node \in 1..plan.count), SMT
                        DEF terms, completed, RHSOutputRaw, RHSOutputNodeCounts, RHSOutputNodeKinds, RHSOutputNodeReads,
                            RHSOutputBefore, RHSOutputKeys, RHSOutputInput!Rule!HistoryPrefix, RHSOutputInput!Rule!CopyReferenceValue
                <3>read. plan.kinds[node] = "read" =>
                    terms[node] = RHSOutputInput!Rule!PhysicalRhsBindings(plan, RHSOutputBefore, completed)[node]
                    BY ONLY <3>reference, (node \in 1..plan.count), SMT DEF RHSOutputInput!Rule!PhysicalRhsBindings
                <3>sum. plan.kinds[node] = "add" => terms[node] = terms[plan.left[node]] + terms[plan.right[node]]
                    BY ONLY <2>width, <2>columns, (node \in 1..plan.count), SMT
                        DEF terms, RHSOutputRaw, RHSOutputNodeCounts, RHSOutputNodeKinds, RHSOutputNodeLeft, RHSOutputNodeRight
                <3>. QED BY ONLY <3>integers, <3>literal, <3>read, <3>sum
            <2>. QED BY ONLY <2>root, <2>tree, <2>values, SMT
                DEF plan, starts, terms, completed, RHSOutputInput!Rule!RenderedRhsTerms
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

        THEOREM RHSOutputEarlierIndexInBoundedInterval ==
            ASSUME NEW n \in Nat, NEW k \in 1..n, NEW i \in 1..(k - 1)
            PROVE i \in 1..n
        PROOF
        <1>limit. /\ n \in Int /\ k \in Int /\ k <= n
            BY ONLY (n \in Nat), (k \in 1..n), SMT
        <1>index. /\ i \in Int /\ 1 <= i /\ i <= k - 1
            BY ONLY <1>limit, (i \in 1..(k - 1)), SMT
        <1>. QED BY ONLY <1>limit, <1>index, SMT

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
        <1>. DEFINE probes == DOMAIN RHSOutputProbePositions
                    placeAt(probe) == RHSOutputProbePositions[probe]
                    probePlaces == {placeAt(probe) : probe \in probes}
                    guardAt(place) == RHSOutputRaw.guards[place[1]][place[2]]
                    earlier(first, second) ==
                        first[1] < second[1] \/ (first[1] = second[1] /\ first[2] < second[2])
                    physicalPrefix(place) ==
                        \A prior \in RHSOutputPhysicalNodeSlots : earlier(prior, place) => guardAt(prior)
                    probePrefix(probe) ==
                        \A prior \in probes : prior < probe => guardAt(placeAt(prior))
        <1>domains. /\ DOMAIN RHSOutputGuards = probes
                     /\ DOMAIN RHSOutputPayloads = probes
            BY ONLY IsaM("simp") DEF probes, RHSOutputProbePositions, RHSOutputGuards, RHSOutputPayloads
        <1>coordinates. probePlaces =
            {place \in RHSOutputPhysicalNodeSlots : RHSOutputNodeKinds[place[1]][place[2]] = "add"}
            BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
                DEF probePlaces, probes, placeAt, RHSOutputProbePositions, RHSOutputPhysicalNodeSlots,
                    RHSOutputPlans, RHSOutputNodeCounts, RHSOutputNodeKinds
        <1>order. \A first, second \in probes :
                (first < second) <=> earlier(placeAt(first), placeAt(second))
            BY ONLY SMT DEF probes, placeAt, earlier, RHSOutputProbePositions
        <1>plans. RHSOutputRaw.plans = RHSOutputPlans
            BY ONLY SMT DEF RHSOutputRaw
        <1>inventory. /\ RHSOutputInput!Rule!SupportedAssignmentList(RHSOutputRows)
                       /\ RHSOutputInput!Rule!RenderedAssignmentInventory(RHSOutputRows, RHSOutputBefore, RHSOutputRaw)
            BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, RHSOutputStateType,
                ActualRenderedTermsAndGuardsSupplyTheAssignmentInventory
        <1>slotBounds. \A place \in RHSOutputPhysicalNodeSlots :
            /\ place[1] \in 1..RHSOutputCount
            /\ place[2] \in 1..RHSOutputPlans[place[1]].count
            <2>. TAKE place \in RHSOutputPhysicalNodeSlots
            <2>row. PICK row \in 1..RHSOutputCount :
                place \in {<<row, node>> : node \in 1..RHSOutputPlans[row].count}
                BY ONLY (place \in RHSOutputPhysicalNodeSlots), SMT DEF RHSOutputPhysicalNodeSlots
            <2>node. PICK node \in 1..RHSOutputPlans[row].count : place = <<row, node>>
                BY ONLY <2>row, SMT
            <2>. QED BY ONLY <2>row, <2>node, SMT
        <1>slotMember. \A row \in 1..RHSOutputCount : \A node \in 1..RHSOutputPlans[row].count :
            <<row, node>> \in RHSOutputPhysicalNodeSlots
            <2>. TAKE row \in 1..RHSOutputCount
            <2>. TAKE node \in 1..RHSOutputPlans[row].count
            <2>. DEFINE rowSlots == {<<row, other>> : other \in 1..RHSOutputPlans[row].count}
            <2>row. rowSlots \in {{<<index, other>> : other \in 1..RHSOutputPlans[index].count} : index \in 1..RHSOutputCount}
                BY ONLY (row \in 1..RHSOutputCount), SMT DEF rowSlots
            <2>node. <<row, node>> \in rowSlots
                BY ONLY (node \in 1..RHSOutputPlans[row].count), SMT DEF rowSlots
            <2>. QED BY ONLY <2>row, <2>node, SMT DEF RHSOutputPhysicalNodeSlots
        <1>rowDomains. /\ DOMAIN RHSOutputRows = 1..RHSOutputCount
                       /\ DOMAIN RHSOutputPlans = DOMAIN RHSOutputRows
            BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory
                DEF RHSOutputCount, RHSOutputInput!Rule!SupportedAssignmentList
        <1>countNat. RHSOutputCount \in Nat
            BY ONLY <1>inventory DEF RHSOutputCount, RHSOutputInput!Rule!SupportedAssignmentList
        <1>nodeCountsNat. \A row \in 1..RHSOutputCount : RHSOutputPlans[row].count \in Nat
            <2>. TAKE row \in 1..RHSOutputCount
            <2>domain. row \in DOMAIN RHSOutputRows
                BY ONLY <1>rowDomains, (row \in 1..RHSOutputCount)
            <2>terms. RHSOutputInput!Rule!RenderedRhsTerms(
                RHSOutputPlans[row], RHSOutputBefore, RHSOutputInput!Rule!HistoryPrefix(RHSOutputRaw.roots, row - 1),
                RHSOutputRaw.starts[row], RHSOutputRaw.terms[row])
                BY ONLY <2>domain, <1>plans, <1>inventory, SMT
                    DEF RHSOutputInput!Rule!RenderedAssignmentInventory
            <2>. QED BY ONLY <2>terms, SMT DEF RHSOutputInput!Rule!RenderedRhsTerms
        <1>guardRows. \A row \in DOMAIN RHSOutputRows :
            RHSOutputInput!Rule!RenderedRhsGuards(RHSOutputPlans[row], RHSOutputRaw.terms[row], RHSOutputRaw.guards[row])
            BY ONLY <1>plans, <1>inventory, SMT DEF RHSOutputInput!Rule!RenderedAssignmentInventory
        <1>unprobed. \A place \in (RHSOutputPhysicalNodeSlots \ probePlaces) : guardAt(place)
            <2>. TAKE place \in (RHSOutputPhysicalNodeSlots \ probePlaces)
            <2>axes. /\ place[1] \in DOMAIN RHSOutputRows
                     /\ place[1] \in DOMAIN RHSOutputPlans
                     /\ place[2] \in 1..RHSOutputPlans[place[1]].count
                BY ONLY <1>slotBounds, <1>rowDomains, (place \in (RHSOutputPhysicalNodeSlots \ probePlaces)), SMT
            <2>kind. RHSOutputPlans[place[1]].kinds[place[2]] = RHSOutputNodeKinds[place[1]][place[2]]
                BY ONLY <2>axes, SMT DEF RHSOutputPlans
            <2>notAdd. RHSOutputPlans[place[1]].kinds[place[2]] # "add"
                BY ONLY <1>coordinates, <2>kind, (place \in (RHSOutputPhysicalNodeSlots \ probePlaces)), SMT
            <2>. QED BY ONLY <2>axes, <2>notAdd, <1>guardRows, SMT DEF guardAt, RHSOutputInput!Rule!RenderedRhsGuards
        <1>prefix. \A probe \in probes : physicalPrefix(placeAt(probe)) <=> probePrefix(probe)
            BY ONLY <1>coordinates, <1>order, <1>unprobed, SMT
                DEF physicalPrefix, probePrefix, probePlaces
        <1>. DEFINE rowPrefix(place) ==
                /\ \A row \in 1..(place[1] - 1) : \A node \in 1..RHSOutputPlans[row].count :
                       RHSOutputRaw.guards[row][node]
                /\ \A node \in 1..(place[2] - 1) : RHSOutputRaw.guards[place[1]][node]
        <1>physical. \A place \in RHSOutputPhysicalNodeSlots :
            RHSOutputFailsAt(place) <=> (physicalPrefix(place) /\ ~guardAt(place))
            <2>. TAKE place \in RHSOutputPhysicalNodeSlots
            <2>bounds. /\ place[1] \in 1..RHSOutputCount
                       /\ place[2] \in 1..RHSOutputPlans[place[1]].count
                BY ONLY <1>slotBounds, (place \in RHSOutputPhysicalNodeSlots), SMT
            <2>raw. RHSOutputFailsAt(place) <=> (rowPrefix(place) /\ ~guardAt(place))
                BY ONLY <1>plans, <2>bounds, SMT
                    DEF RHSOutputFailsAt, rowPrefix, guardAt, RHSOutputInput!Rule!RenderedAssignmentFailsAt,
                        RHSOutputInput!Rule!RenderedAssignmentsPass, RHSOutputInput!Rule!FirstRejectedRenderedGuard,
                        RHSOutputInput!Rule!EveryRenderedGuardPasses
            <2>fromRows. ASSUME rowPrefix(place)
                          PROVE physicalPrefix(place)
                <3>. SUFFICES ASSUME NEW prior \in RHSOutputPhysicalNodeSlots, earlier(prior, place)
                             PROVE guardAt(prior)
                    BY SMT DEF physicalPrefix
                <3>bounds. /\ prior[1] \in 1..RHSOutputCount
                           /\ prior[2] \in 1..RHSOutputPlans[prior[1]].count
                    BY ONLY <1>slotBounds, (prior \in RHSOutputPhysicalNodeSlots), SMT
                <3>previous. CASE prior[1] < place[1]
                    BY ONLY <3>previous, <3>bounds, <2>bounds, rowPrefix(place), SMT DEF rowPrefix, guardAt
                <3>same. CASE prior[1] = place[1]
                    BY ONLY <3>same, <3>bounds, <2>bounds, earlier(prior, place), rowPrefix(place), SMT
                        DEF earlier, rowPrefix, guardAt
                <3>. QED BY ONLY <3>previous, <3>same, earlier(prior, place), SMT DEF earlier
            <2>fromSlots. ASSUME physicalPrefix(place)
                           PROVE rowPrefix(place)
                <3>rows. \A row \in 1..(place[1] - 1) : \A node \in 1..RHSOutputPlans[row].count :
                                RHSOutputRaw.guards[row][node]
                    <4>. TAKE row \in 1..(place[1] - 1)
                    <4>. TAKE node \in 1..RHSOutputPlans[row].count
                    <4>rowDomain. row \in 1..RHSOutputCount
                        BY ONLY <1>countNat, <2>bounds, (row \in 1..(place[1] - 1)),
                            RHSOutputEarlierIndexInBoundedInterval, SMT
                    <4>slot. <<row, node>> \in RHSOutputPhysicalNodeSlots
                        BY ONLY <1>slotMember, <4>rowDomain, (node \in 1..RHSOutputPlans[row].count), SMT
                    <4>strict. row < place[1]
                        BY ONLY <2>bounds, (row \in 1..(place[1] - 1)), SMT
                    <4>earlier. earlier(<<row, node>>, place)
                        BY ONLY <4>strict, SMT DEF earlier
                    <4>guard. guardAt(<<row, node>>)
                        BY ONLY physicalPrefix(place), <4>slot, <4>earlier, SMT DEF physicalPrefix
                    <4>. QED BY ONLY <4>guard, SMT DEF guardAt
                <3>nodes. \A node \in 1..(place[2] - 1) : RHSOutputRaw.guards[place[1]][node]
                    <4>. TAKE node \in 1..(place[2] - 1)
                    <4>rowDomain. place[1] \in 1..RHSOutputCount
                        BY ONLY <2>bounds
                    <4>nodeCountNat. RHSOutputPlans[place[1]].count \in Nat
                        BY ONLY <1>nodeCountsNat, <4>rowDomain, SMT
                    <4>nodeDomain. node \in 1..RHSOutputPlans[place[1]].count
                        BY ONLY <4>nodeCountNat, <2>bounds, (node \in 1..(place[2] - 1)),
                            RHSOutputEarlierIndexInBoundedInterval, SMT
                    <4>slot. <<place[1], node>> \in RHSOutputPhysicalNodeSlots
                        BY ONLY <1>slotMember, <4>rowDomain, <4>nodeDomain, SMT
                    <4>strict. node < place[2]
                        BY ONLY <2>bounds, (node \in 1..(place[2] - 1)), SMT
                    <4>earlier. earlier(<<place[1], node>>, place)
                        BY ONLY <4>strict, SMT DEF earlier
                    <4>guard. guardAt(<<place[1], node>>)
                        BY ONLY physicalPrefix(place), <4>slot, <4>earlier, SMT DEF physicalPrefix
                    <4>. QED BY ONLY <4>guard, SMT DEF guardAt
                <3>. QED BY ONLY <3>rows, <3>nodes DEF rowPrefix
            <2>. QED BY ONLY <2>raw, <2>fromRows, <2>fromSlots, SMT
        <1>actualProbe. \A probe \in probes :
            RHSOutputGuards[probe] <=> (RHSOutputSelected /\ probePrefix(probe) /\ ~guardAt(placeAt(probe)))
            BY ONLY SMT DEF probes, probePrefix, placeAt, guardAt, RHSOutputRaw, RHSOutputProbePositions,
                RHSOutputGuards, RHSOutputSelected, RHSOutputEntry\#(predicateNames)
        <1>selected. \A probe \in probes :
            RHSOutputGuards[probe] <=> (RHSOutputSelected /\ RHSOutputFailsAt(placeAt(probe)))
            BY ONLY <1>coordinates, <1>prefix, <1>physical, <1>actualProbe, SMT DEF probePlaces
        <1>failedPlaces. \A place \in RHSOutputPhysicalNodeSlots :
            RHSOutputFailsAt(place) => place \in probePlaces
            BY ONLY <1>unprobed, <1>physical, SMT
        <1>sites. RHSOutputSelectedSubExpressions =
            {place \in RHSOutputPhysicalNodeSlots : RHSOutputSelected /\ RHSOutputFailsAt(place)}
            <2>member. \A place : place \in RHSOutputSelectedSubExpressions <=>
                (place \in RHSOutputPhysicalNodeSlots /\ RHSOutputSelected /\ RHSOutputFailsAt(place))
                BY ONLY <1>domains, <1>coordinates, <1>selected, <1>failedPlaces, SMT
                    DEF RHSOutputSelectedSubExpressions, RHSOutputFailureProbeSites, probePlaces, placeAt
            <2>. QED BY ONLY <2>member, SetExtensionality, SMT
        <1>actualAggregate. RHSOutputFailureSelected = (RHSOutputFailureProbeSites # {})
            BY ONLY SMT DEF RHSOutputFailureSelected, RHSOutputFailureProbeSites, RHSOutputGuards\#(aggregateName)\#(predicateNames)
        <1>reached. ~RHSOutputPasses <=>
            (\E row \in 1..RHSOutputCount : \E node \in 1..RHSOutputPlans[row].count : RHSOutputFailsAt(<<row, node>>))
            BY ONLY <1>inventory, <1>plans, RHSOutputUsesTheMachineIntegerDomain,
                RHSOutputInput!Rule!WholeGuardTableHasAnExactFirstFailureSite, SMT
                DEF RHSOutputPasses, RHSOutputFailsAt, RHSOutputCount
        <1>firstFailure. ~RHSOutputPasses <=>
            (\E place \in RHSOutputPhysicalNodeSlots : RHSOutputFailsAt(place))
            <2>encode. ASSUME \E row \in 1..RHSOutputCount :
                                   \E node \in 1..RHSOutputPlans[row].count : RHSOutputFailsAt(<<row, node>>)
                       PROVE \E place \in RHSOutputPhysicalNodeSlots : RHSOutputFailsAt(place)
                <3>row. PICK row \in 1..RHSOutputCount :
                    \E node \in 1..RHSOutputPlans[row].count : RHSOutputFailsAt(<<row, node>>)
                    BY ONLY (\E index \in 1..RHSOutputCount : \E node \in 1..RHSOutputPlans[index].count :
                                 RHSOutputFailsAt(<<index, node>>)), SMT
                <3>node. PICK node \in 1..RHSOutputPlans[row].count : RHSOutputFailsAt(<<row, node>>)
                    BY ONLY <3>row, SMT
                <3>slot. <<row, node>> \in RHSOutputPhysicalNodeSlots
                    BY ONLY <1>slotMember, <3>row, <3>node, SMT
                <3>. QED BY ONLY <3>slot, <3>node, Zenon
            <2>decode. ASSUME \E place \in RHSOutputPhysicalNodeSlots : RHSOutputFailsAt(place)
                       PROVE \E row \in 1..RHSOutputCount :
                                 \E node \in 1..RHSOutputPlans[row].count : RHSOutputFailsAt(<<row, node>>)
                <3>slot. PICK place \in RHSOutputPhysicalNodeSlots : RHSOutputFailsAt(place)
                    BY ONLY (\E site \in RHSOutputPhysicalNodeSlots : RHSOutputFailsAt(site)), SMT
                <3>bounds. /\ place[1] \in 1..RHSOutputCount
                           /\ place[2] \in 1..RHSOutputPlans[place[1]].count
                    BY ONLY <3>slot, <1>slotBounds, SMT
                <3>same. RHSOutputFailsAt(<<place[1], place[2]>>)
                    BY ONLY <3>slot, SMT DEF RHSOutputFailsAt
                <3>nodeExists. \E node \in 1..RHSOutputPlans[place[1]].count : RHSOutputFailsAt(<<place[1], node>>)
                    BY ONLY <3>bounds, <3>same, Zenon
                <3>. QED BY ONLY <3>bounds, <3>nodeExists, Zenon
            <2>. QED BY ONLY <1>reached, <2>encode, <2>decode, SMT
        <1>aggregate. RHSOutputFailureSelected = (RHSOutputSelected /\ ~RHSOutputPasses)
            BY ONLY <1>actualAggregate, <1>firstFailure, <1>sites, SMT DEF RHSOutputSelectedSubExpressions
        <1>payloads. \A probe \in RHSOutputFailureProbeSites :
            LET place == RHSOutputProbePositions[probe]
                row == RHSOutputPlans[place[1]]
                terms == RHSOutputRaw.terms[place[1]]
            IN RHSOutputPayloads[probe] =
                [operation |-> "addition", operands |-> <<terms[row.left[place[2]]], terms[row.right[place[2]]]>>,
                 prefix |-> RHSOutputInput!Rule!HistoryPrefix(RHSOutputRaw.roots, place[1] - 1)]
            <2>. TAKE probe \in RHSOutputFailureProbeSites
            <2>. DEFINE place == placeAt(probe)
                        payload == RHSOutputPayloads[probe]
                        terms == RHSOutputRaw.terms[place[1]]
            <2>active. /\ probe \in probes /\ RHSOutputGuards[probe]
                BY ONLY <1>domains, (probe \in RHSOutputFailureProbeSites), SMT DEF RHSOutputFailureProbeSites
            <2>located. /\ place \in RHSOutputPhysicalNodeSlots
                         /\ place[1] \in DOMAIN RHSOutputPlans
                BY ONLY <1>coordinates, <2>active, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
                    DEF place, probePlaces, RHSOutputPhysicalNodeSlots, RHSOutputCount,
                        RHSOutputInput!Rule!SupportedAssignmentList
            <2>shape. payload = [operation |-> payload.operation, operands |-> payload.operands, prefix |-> payload.prefix]
                BY ONLY <2>active, SMT DEF probes, payload, RHSOutputPayloads, RHSOutputGuards, RHSOutputProbePositions
            <2>operation. payload.operation = "addition"
                BY ONLY <2>active, SMT DEF probes, payload, RHSOutputPayloads, RHSOutputGuards, RHSOutputProbePositions\#(operationNames)
            <2>operands. payload.operands =
                <<terms[RHSOutputNodeLeft[place[1]][place[2]]], terms[RHSOutputNodeRight[place[1]][place[2]]]>>
                BY ONLY <2>active, SMT DEF probes, place, placeAt, terms, payload, RHSOutputPayloads, RHSOutputGuards,
                    RHSOutputProbePositions, RHSOutputRaw, RHSOutputNodeLeft, RHSOutputNodeRight\#(operandNames)
            <2>prefix. payload.prefix = RHSOutputInput!Rule!HistoryPrefix(RHSOutputRaw.roots, place[1] - 1)
                BY ONLY <2>active, SMT DEF probes, place, placeAt, payload, RHSOutputPayloads, RHSOutputGuards,
                    RHSOutputProbePositions, RHSOutputRaw, RHSOutputInput!Rule!HistoryPrefix\#(prefixNames)
            <2>children. /\ RHSOutputPlans[place[1]].left = RHSOutputNodeLeft[place[1]]
                          /\ RHSOutputPlans[place[1]].right = RHSOutputNodeRight[place[1]]
                BY ONLY <2>located, SMT DEF RHSOutputPlans
            <2>. QED BY ONLY <2>shape, <2>operation, <2>operands, <2>prefix, <2>children, SMT
                DEF place, placeAt, payload, terms
        <1>. QED BY <1>advance, <1>aggregate, <1>sites, <1>payloads

        THEOREM RHSOutputStateSuppliesAssignmentBindings ==
            ASSUME RHSOutputStateType
            PROVE RHSOutputBefore \in RHSOutputInput!Rule!AssignmentBindings
        PROOF
        <1>keys. RHSOutputKeys = RHSOutputInput!MasterFields
            BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory
        <1>. QED BY ONLY <1>keys, RHSOutputStateType, SMT
            DEF RHSOutputStateType, RHSOutputMin, RHSOutputMax,
                RHSOutputInput!Rule!AssignmentBindings, RHSOutputInput!Rule!AssignmentIntValues

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
            BY ONLY RHSOutputStateType, RHSOutputStateSuppliesAssignmentBindings, RHSOutputUsesTheMachineIntegerDomain,
                RHSOutputSourceHistory(history), <1>shape, <1>inventory,
                RHSOutputInput!Rule!PhysicalGuardedAssignmentTablesDetermineTheCompleteOutcome,
                RHSOutputInput!Rule!OrderedAssignmentHistoriesRetainTheExactFirstFailurePrefix, SMT
                DEF RHSOutputSourceHistory, RHSOutputCount, RHSOutputInput!Rule!SupportedAssignmentList
        <1>plans. RHSOutputRaw.plans = RHSOutputPlans
            BY ONLY SMT DEF RHSOutputRaw
        <1>reached. ~RHSOutputPasses <=>
            (\E index \in 1..RHSOutputCount : \E node \in 1..RHSOutputPlans[index].count : RHSOutputFailsAt(<<index, node>>))
            BY ONLY <1>shape, <1>inventory, <1>plans, RHSOutputUsesTheMachineIntegerDomain,
                RHSOutputInput!Rule!WholeGuardTableHasAnExactFirstFailureSite, SMT
                DEF RHSOutputPasses, RHSOutputFailsAt, RHSOutputCount
        <1>. DEFINE final == history[RHSOutputCount]
                    placeAt(probe) == RHSOutputProbePositions[probe]
                    observed(probe) ==
                        LET payload == RHSOutputPayloads[probe]
                        IN RHSOutputFailureEvent(placeAt(probe)[1], payload.operation, payload.operands, payload.prefix)
                    certified ==
                        [site |-> final.failure.site, target |-> RHSOutputRows[final.failure.site].target,
                         payload |-> final.failure.payload, completed |-> final.completed, before |-> final.failure.before]
        <1>failureAt. \A row \in 1..RHSOutputCount : \A node \in 1..RHSOutputPlans[row].count :
            RHSOutputFailsAt(<<row, node>>) =>
              /\ final.failure = RHSOutputInput!Rule!RenderedAssignmentFailure(RHSOutputRows, RHSOutputBefore, RHSOutputRaw, row, node)
              /\ final.completed = RHSOutputInput!Rule!HistoryPrefix(RHSOutputRaw.roots, row - 1)
              /\ final.failure # <<>>
            <2>. TAKE row \in 1..RHSOutputCount
            <2>. TAKE node \in 1..RHSOutputPlans[row].count
            <2>failing. ASSUME RHSOutputFailsAt(<<row, node>>)
                 PROVE /\ final.failure = RHSOutputInput!Rule!RenderedAssignmentFailure(RHSOutputRows, RHSOutputBefore, RHSOutputRaw, row, node)
                       /\ final.completed = RHSOutputInput!Rule!HistoryPrefix(RHSOutputRaw.roots, row - 1)
                       /\ final.failure # <<>>
                <3>projection. /\ final.failure = RHSOutputInput!Rule!RenderedAssignmentFailure(RHSOutputRows, RHSOutputBefore, RHSOutputRaw, row, node)
                               /\ final.completed = RHSOutputInput!Rule!HistoryPrefix(RHSOutputRaw.roots, row - 1)
                    BY ONLY <1>history, <1>plans, RHSOutputFailsAt(<<row, node>>),
                        (row \in 1..RHSOutputCount), (node \in 1..RHSOutputPlans[row].count), SMT
                        DEF final, RHSOutputFailsAt, RHSOutputInput!Rule!RenderedAssignmentHistoryAt
                <3>. QED BY ONLY <3>projection, SMT DEF RHSOutputInput!Rule!RenderedAssignmentFailure
            <2>. QED BY ONLY <2>failing, SMT
        <1>passed. RHSOutputPasses =>
            /\ final.failure = <<>>
            /\ final.completed = RHSOutputInput!Rule!HistoryPrefix(RHSOutputRaw.roots, RHSOutputCount)
            BY ONLY <1>history, SMT DEF final, RHSOutputPasses, RHSOutputInput!Rule!RenderedAssignmentHistoryAt
        <1>success. RHSOutputPasses <=> final.failure = <<>>
            BY ONLY <1>passed, <1>reached, <1>failureAt, SMT
        <1>roots. /\ DOMAIN RHSOutputRaw.roots = 1..RHSOutputCount
                   /\ Len(RHSOutputRaw.roots) = RHSOutputCount
            BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT DEF RHSOutputRaw
        <1>. DEFINE roots == RHSOutputRaw.roots
                    captureSlots == 1..RHSOutputCount
                    captureValues == {roots[index] : index \in captureSlots}
                    completePrefix == RHSOutputInput!Rule!HistoryPrefix(roots, RHSOutputCount)
        <1>rootsAreAFunction. roots \in [captureSlots -> captureValues]
            BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
                DEF roots, captureSlots, captureValues, RHSOutputRaw
        <1>fullPrefix. RHSOutputInput!Rule!HistoryPrefix(RHSOutputRaw.roots, RHSOutputCount) = RHSOutputRaw.roots
            <2>cells. \A index \in captureSlots : completePrefix[index] = roots[index]
                BY ONLY SMT DEF completePrefix, captureSlots, RHSOutputInput!Rule!HistoryPrefix
            <2>prefixIsAFunction. completePrefix \in [captureSlots -> captureValues]
                BY ONLY <1>rootsAreAFunction, SMT
                    DEF completePrefix, captureSlots, RHSOutputInput!Rule!HistoryPrefix
            <2>. QED BY ONLY <1>rootsAreAFunction, <2>prefixIsAFunction, <2>cells, SMT
                DEF roots, completePrefix
        <1>writes. RHSOutputPasses =>
            final.bindings =
                RHSOutputInput!Rule!CopyMaterializedState(RHSOutputKeys, RHSOutputBefore, RHSOutputRaw.roots, RHSOutputWriteRoutes)
            <2>. SUFFICES ASSUME RHSOutputPasses
                 PROVE final.bindings =
                     RHSOutputInput!Rule!CopyMaterializedState(RHSOutputKeys, RHSOutputBefore, RHSOutputRaw.roots, RHSOutputWriteRoutes)
                OBVIOUS
            <2>complete. final.completed = RHSOutputRaw.roots
                BY ONLY RHSOutputPasses, <1>passed, <1>fullPrefix, SMT
            <2>bindings. final.bindings = RHSOutputInput!Rule!CompletedAssignmentBindings(RHSOutputBefore, RHSOutputRows, final.completed)
                BY ONLY <1>history, SMT DEF final, RHSOutputInput!Rule!AssignmentPrefixMeaning
            <2>keys. RHSOutputKeys = RHSOutputInput!MasterFields
                BY ONLY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory
            <2>. QED BY ONLY <2>complete, <2>bindings, <2>keys, <1>roots,
                ActualRenderedWriteRoutesAreTheFinalAuthoredWriters, SMT DEF RHSOutputInput!Rule!CompletedAssignmentBindings
        <1>actualAdvance. \#(step.renderedName) <=> RHSOutputRawAdvance
            BY ONLY RHSOutputStateType, ActualEmittedActionUsesThePhysicalGuardTable
        <1>frame. \#(step.renderedName) <=> RHSOutputHistoryAdvance(history)
            BY ONLY <1>actualAdvance, <1>success, <1>writes, SMT DEF final, RHSOutputHistoryAdvance, RHSOutputRawAdvance

        <1>places. RHSOutputSelectedSubExpressions =
            {place \in RHSOutputPhysicalNodeSlots : RHSOutputSelected /\ RHSOutputFailsAt(place)}
            BY ONLY RHSOutputStateType, ActualEmittedActionUsesThePhysicalGuardTable
        <1>probeNonempty. (RHSOutputFailureProbeSites # {}) <=> (RHSOutputSelected /\ ~RHSOutputPasses)
            <2>image. (RHSOutputFailureProbeSites # {}) <=> (RHSOutputSelectedSubExpressions # {})
                BY ONLY SMT DEF RHSOutputSelectedSubExpressions
            <2>slots. (\E place \in RHSOutputPhysicalNodeSlots : RHSOutputFailsAt(place)) <=>
                (\E row \in 1..RHSOutputCount : \E node \in 1..RHSOutputPlans[row].count : RHSOutputFailsAt(<<row, node>>))
                BY ONLY SMT DEF RHSOutputPhysicalNodeSlots
            <2>selection. (RHSOutputSelectedSubExpressions # {}) <=>
                (RHSOutputSelected /\ \E place \in RHSOutputPhysicalNodeSlots : RHSOutputFailsAt(place))
                BY ONLY <1>places, SMT
            <2>. QED BY ONLY <2>image, <2>slots, <2>selection, <1>reached, SMT
        <1>probeValue. \A probe \in RHSOutputFailureProbeSites : observed(probe) = certified
            <2>. TAKE probe \in RHSOutputFailureProbeSites
            <2>. DEFINE place == placeAt(probe)
                        row == place[1]
                        node == place[2]
                        plan == RHSOutputPlans[row]
                        terms == RHSOutputRaw.terms[row]
                        prefix == RHSOutputInput!Rule!HistoryPrefix(RHSOutputRaw.roots, row - 1)
                        operands == <<terms[plan.left[node]], terms[plan.right[node]]>>
            <2>slot. /\ place \in RHSOutputPhysicalNodeSlots /\ RHSOutputFailsAt(place)
                BY ONLY <1>places, (probe \in RHSOutputFailureProbeSites), SMT
                    DEF place, placeAt, RHSOutputSelectedSubExpressions
            <2>coordinate. /\ row \in 1..RHSOutputCount /\ node \in 1..plan.count /\ place = <<row, node>>
                BY ONLY <2>slot, SMT DEF row, node, plan, RHSOutputPhysicalNodeSlots
            <2>history. /\ final.failure = RHSOutputInput!Rule!RenderedAssignmentFailure(RHSOutputRows, RHSOutputBefore, RHSOutputRaw, row, node)
                         /\ final.completed = prefix
                BY ONLY <2>slot, <2>coordinate, <1>failureAt, SMT DEF prefix, plan
            <2>physicalPayload. RHSOutputPayloads[probe] =
                [operation |-> "addition", operands |-> operands, prefix |-> prefix]
                BY ONLY RHSOutputStateType, ActualEmittedActionUsesThePhysicalGuardTable, (probe \in RHSOutputFailureProbeSites), SMT
                    DEF place, placeAt, row, node, plan, terms, prefix, operands
            <2>historyPayload. final.failure =
                [before |-> RHSOutputInput!Rule!CompletedAssignmentBindings(RHSOutputBefore, RHSOutputRows, prefix),
                 site |-> row, payload |-> <<"integerOverflow", "addition", operands>>]
                BY ONLY <2>history, <1>plans, SMT DEF plan, terms, prefix, operands,
                    RHSOutputInput!Rule!RenderedAssignmentFailure, RHSOutputInput!Rule!RenderedTermOverflow,
                    RHSOutputInput!Rule!GeneratedOverflow
            <2>. QED BY ONLY <2>history, <2>historyPayload, <2>physicalPayload, SMT
                DEF observed, certified, row, place, RHSOutputFailureEvent
        <1>actualImage. RHSOutputActualFailures = {observed(probe) : probe \in RHSOutputFailureProbeSites}
            BY ONLY SMT DEF observed, placeAt, RHSOutputActualFailures
        <1>failure. RHSOutputActualFailures = RHSOutputHistoryFailures(history)
            <2>actual. RHSOutputActualFailures = IF RHSOutputFailureProbeSites # {} THEN {certified} ELSE {}
                <3>empty. CASE RHSOutputFailureProbeSites = {}
                    <4>none. \A event : event \notin RHSOutputActualFailures
                        BY ONLY <3>empty, <1>actualImage, SMT
                    <4>emptyImage. RHSOutputActualFailures = {}
                        <5>membership. \A event : (event \in RHSOutputActualFailures) <=> (event \in {})
                            BY ONLY <4>none, SMT
                        <5>. QED BY ONLY <5>membership, SetExtensionality, Zenon
                    <4>. QED BY ONLY <3>empty, <4>emptyImage, IsaM("simp")
                <3>active. CASE RHSOutputFailureProbeSites # {}
                    <4>probe. PICK probe \in RHSOutputFailureProbeSites : TRUE
                        BY ONLY <3>active, SMT
                    <4>includes. certified \in RHSOutputActualFailures
                        BY ONLY <4>probe, <1>actualImage, <1>probeValue, SMT
                    <4>only. \A event \in RHSOutputActualFailures : event = certified
                        <5>. TAKE event \in RHSOutputActualFailures
                        <5>origin. PICK other \in RHSOutputFailureProbeSites : event = observed(other)
                            BY ONLY <1>actualImage, (event \in RHSOutputActualFailures), SMT
                        <5>. QED BY ONLY <5>origin, <1>probeValue, SMT
                    <4>singletonImage. RHSOutputActualFailures = {certified}
                        <5>membership. \A event : (event \in RHSOutputActualFailures) <=> (event \in {certified})
                            BY ONLY <4>includes, <4>only, SMT
                        <5>. QED BY ONLY <5>membership, SetExtensionality, Zenon
                    <4>. QED BY ONLY <3>active, <4>singletonImage, IsaM("simp")
                <3>. QED BY ONLY <3>empty, <3>active
            <2>source. RHSOutputHistoryFailures(history) =
                IF RHSOutputSelected /\ final.failure # <<>> THEN {certified} ELSE {}
                BY ONLY DEF RHSOutputHistoryFailures, final, certified
            <2>. QED BY ONLY <2>actual, <2>source, <1>probeNonempty, <1>success, SMT
        <1>aggregate. RHSOutputFailureSelected = (RHSOutputActualFailures # {})
            <2>emitted. RHSOutputFailureSelected = (RHSOutputSelected /\ ~RHSOutputPasses)
                BY ONLY RHSOutputStateType, ActualEmittedActionUsesThePhysicalGuardTable
            <2>nonempty. (RHSOutputActualFailures # {}) <=> (RHSOutputFailureProbeSites # {})
                BY ONLY <1>actualImage, SMT
            <2>. QED BY ONLY <2>emitted, <2>nonempty, <1>probeNonempty, SMT
        \#(routeProof)
        <1>. QED BY ONLY <1>frame, <1>failure, <1>aggregate, \#(routeFact) DEF RHSOutputHistoryObservation

        THEOREM ActualTLAActionHasACertifiedAssignmentHistory ==
            ASSUME RHSOutputStateType
            PROVE \E history :
                /\ RHSOutputSourceHistory(history)
                /\ RHSOutputGeneratedHistory(history)
                /\ RHSOutputHistoryObservation(history)
        PROOF
        <1>history. PICK history : RHSOutputSourceHistory(history) /\ RHSOutputGeneratedHistory(history)
            BY ONLY RHSOutputStateType, RHSOutputStateSuppliesAssignmentBindings, RHSOutputUsesTheMachineIntegerDomain,
                RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory,
                RHSOutputInput!Rule!CertifiedOrderedAssignmentListConstructsCompleteActionOutcome, SMT
                DEF RHSOutputSourceHistory, RHSOutputGeneratedHistory
        <1>observed. RHSOutputHistoryObservation(history)
            BY RHSOutputStateType, <1>history, ActualTLAActionObservesTheCertifiedAssignmentHistory
        <1>. WITNESS history
        <1>. QED BY <1>history, <1>observed

        ====

        """#
        return (name, Data(proof.utf8))
    }

    private static func controlDestination(in body: CompiledActionExpr, for counter: VariableID) -> ControlLocationID? {
        var pending = [body]
        var destination: ControlLocationID?
        while let action = pending.popLast() {
            switch action {
            case .and(let left, let right):
                pending.append(right)
                pending.append(left)
            case .define(_, _, let continuation):
                pending.append(continuation)
            case .assign(let id, let value) where id == counter:
                guard destination == nil, value.resultType == .controlLocation, value.children.isEmpty,
                      case .controlLocation(let label) = value.operation else { return nil }
                destination = label
            case .unchanged(let id) where id == counter:
                return nil
            case .existsAction, .ifElse, .or:
                return nil
            default:
                break
            }
        }
        return destination
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
