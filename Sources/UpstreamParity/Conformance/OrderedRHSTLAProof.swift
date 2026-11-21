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
        let plans = TLAValue.tuple(captures.map(\.plan))
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

        LOCAL RHSOutputPlans == \#(plans)
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
            BY ONLY SMT DEF RHSOutputRows, RHSOutputInput!\#(sourceRows), RHSOutputPlans
        <1>. QED BY ONLY <1>fields, <1>authored, <1>domain

        THEOREM ActualRenderedRightHandSidesMatchAuthoredAssignmentRoutes ==
            \A index \in DOMAIN RHSOutputRows :
                RHSOutputInput!Rule!PhysicalAssignmentReadsMatchRoutes(RHSOutputRows, index, RHSOutputPlans[index])
        PROOF
        <1>named. \A index \in DOMAIN RHSOutputRows :
            RHSOutputInput!Rule!PhysicalAssignmentReadsNameWriters(RHSOutputRows, index, RHSOutputPlans[index])
            BY SMT DEF RHSOutputRows, RHSOutputInput!\#(sourceRows), RHSOutputPlans, RHSOutputKeys,
                RHSOutputInput!Rule!PhysicalAssignmentReadsNameWriters, RHSOutputInput!Rule!PhysicalAssignmentOperandsMatch,
                RHSOutputInput!Rule!AssignmentRhsPlan, RHSOutputInput!Rule!ExtractedNodePlan, RHSOutputInput!Rule!CopyReceiptNamesWriter,
                RHSOutputInput!Rule!CopyReceiptOrdinal, RHSOutputInput!Rule!LastDirectCopy, RHSOutputInput!Rule!DirectCopyReference
        <1>. QED BY <1>named, RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory,
            RHSOutputInput!Rule!NamedAssignmentOperandsMatchTheirRoutes, SMT DEF RHSOutputInput!Rule!SupportedAssignmentList

        THEOREM ActualRenderedWriteRoutesAreTheFinalAuthoredWriters ==
            RHSOutputWriteRoutes = RHSOutputInput!Rule!DirectCopyRoutes(RHSOutputKeys, RHSOutputRows)[RHSOutputCount]
        PROOF
        <1>routes. \A key \in RHSOutputKeys :
            RHSOutputInput!Rule!CopyReceiptNamesWriter(RHSOutputRows, RHSOutputCount, key, RHSOutputWriteRoutes[key])
            BY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
               DEF RHSOutputRows, RHSOutputInput!\#(sourceRows), RHSOutputWriteRoutes, RHSOutputKeys,
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
                DEF RHSOutputRaw, RHSOutputStarts, RHSOutputPlans, RHSOutputStateType, RHSOutputBefore,
                    RHSOutputKeys, RHSOutputInput!Rule!RenderedRhsTerms, RHSOutputInput!Rule!PhysicalRhsBindings,
                    RHSOutputInput!Rule!HistoryPrefix, RHSOutputInput!Rule!CopyReferenceValue
        <1>guards. \A index \in DOMAIN RHSOutputRows :
            RHSOutputInput!Rule!RenderedRhsGuards(RHSOutputPlans[index], RHSOutputRaw.terms[index], RHSOutputRaw.guards[index])
            BY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
               DEF RHSOutputRaw, RHSOutputPlans, RHSOutputMin, RHSOutputMax,
                   RHSOutputInput!Rule!RenderedRhsGuards, RHSOutputInput!Rule!GeneratedAddDefined, RHSOutputInput!Rule!SmallAddOperands
        <1>roots. \A index \in DOMAIN RHSOutputRows :
            RHSOutputRaw.roots[index] = RHSOutputRaw.terms[index][RHSOutputPlans[index].count]
            BY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
                DEF RHSOutputRaw, RHSOutputPlans
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
                    RHSOutputWriteRoutes, RHSOutputPlans, RHSOutputInput!Rule!RenderedAssignmentsPass,
                    RHSOutputInput!Rule!EveryRenderedGuardPasses, RHSOutputInput!Rule!CopyMaterializedState,
                    RHSOutputInput!Rule!CopyReferenceValue
        <1>aggregate. RHSOutputFailureSelected = (RHSOutputSelected /\ ~RHSOutputPasses)
            BY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SMT
                DEF RHSOutputSelected, RHSOutputEntry, RHSOutputFailureSelected\#(aggregateName), RHSOutputPasses,
                    RHSOutputCount, RHSOutputRaw, RHSOutputPlans, RHSOutputInput!Rule!RenderedAssignmentsPass,
                    RHSOutputInput!Rule!EveryRenderedGuardPasses
        <1>sites. RHSOutputSelectedSubExpressions =
            {place \in RHSOutputPhysicalNodeSlots :
                RHSOutputSelected /\ RHSOutputFailsAt(place)}
            BY RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory, SetExtensionality, SMT
                DEF RHSOutputSelectedSubExpressions, RHSOutputPhysicalNodeSlots, RHSOutputFailureProbeSites, RHSOutputProbePositions, RHSOutputGuards,
                    RHSOutputRaw, RHSOutputPlans, RHSOutputCount, RHSOutputSelected, RHSOutputEntry, RHSOutputFailsAt,
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
                RHSOutputRaw, RHSOutputPlans, RHSOutputInput!Rule!HistoryPrefix\#(actualNames)
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
