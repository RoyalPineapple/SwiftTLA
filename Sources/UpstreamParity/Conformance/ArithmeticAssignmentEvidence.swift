import Foundation
import SwiftTLA

private struct ArithmeticAssignmentFailureReceipt: Codable {
    struct Binding: Codable {
        let name: String
        let value: TLAValue
    }

    let label: String
    let actionOrdinal: Int
    let site: Int
    let completed: [Int]
    let kind: String
    let operation: String
    let operands: [Int]
    let before: [Binding]

    var tla: TLAValue {
        let original = TLAValue.function(Dictionary(uniqueKeysWithValues: before.map {
            (TLAValue.string($0.name), $0.value)
        }))
        let failure = TLAValue.tuple([.string(kind), .string(operation), .tuple(operands.map(TLAValue.int))])
        return .record(TLARecord([
            .init("label", .string(label)),
            .init("actionOrdinal", .int(actionOrdinal)),
            .init("site", .int(site)),
            .init("completed", .tuple(completed.map(TLAValue.int))),
            .init("payload", failure),
            .init("before", original),
        ]))
    }
}

private struct ArithmeticAssignmentPreparation: Codable {
    let sourceSHA: String
    let sourceCompilationIdentity: String
    let authoredSourceSHA256: String
    let nativeSourceSHA256: String
    let files: [String: String]
}

package enum ArithmeticAssignmentEvidence {
    package struct Translation {
        package let sourceAction: String
        package let actionOrdinal: Int
        package let sourceContinuation: String?
        package let source: (name: String, bytes: Data)
        package let output: (name: String, bytes: Data, failureOperator: String?)
        fileprivate let program: CompiledProgram
        fileprivate let authoredSourceSHA256: String
        fileprivate let catalog: StraightLineRenderedActionCheck.FiniteActionCatalog
        fileprivate let configuration: String
    }

    /// Binds the authored assignment list to the checked program and its actual rendered action.
    /// Preparation of this proof does not depend on an observed successor or a reached failure.
    package static func translation(
        authoredSource: Data, modelName: String, spec: TLASpec, rendered: RenderedSpecification,
        sourceAction: String? = nil
    ) throws -> Translation {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        guard !authoredSource.contains(0), let authored = String(data: authoredSource, encoding: .utf8)
        else { throw invalid }
        let compilation = try spec.compile()
        let inputs = try CompiledTypeInputs(compilation: compilation,
            types: CompiledTypeContext(enums: .init(), formalNames: [:])) { spelling in
                guard ["Int", "Swift.Int"].contains(spelling) else { throw invalid }
                return .int
            }
        let program = try CompiledProgram(inputs: inputs)
        let bundle = rendered.tlaBundle
        let direct = try program.renderModule()
        guard case .compiled(let identity, _, _) = bundle.provenance, identity == program.identity,
              bundle.imports.isEmpty, direct.imports.isEmpty,
              rendered.actions == direct.renderedActions,
              let catalog = StraightLineRenderedActionCheck.unboundActionCatalog(in: rendered, layout: program.layout),
              let config = bundle.root.cfg,
              bundle.root.tla.utf8.elementsEqual(direct.renderedModuleSource.utf8),
              config.utf8.elementsEqual(try direct.configuration.render(usesSymmetryReduction: false).utf8)
        else { throw invalid }

        let selection = try AuthoredCopySyntax.select(source: authored, modelName: modelName)
        let source = try AuthoredCopySyntax.arithmeticProofInput(selection, spec: spec,
            renderedModule: bundle.root.name, sourceAction: sourceAction)
        guard let output = try OrderedRHSTLAProof.render(rendered, program: program, source: source)
        else { throw invalid }

        return .init(sourceAction: source.label, actionOrdinal: source.ordinal, sourceContinuation: source.continuation,
            source: (source.name, Data(source.module.utf8)), output: output, program: program, authoredSourceSHA256: SHA256.hex(authoredSource), catalog: catalog,
            configuration: config)
    }

    package struct CatalogProof {
        package let name: String
        package let bytes: Data
        package let dependencies: [(name: String, bytes: Data)]
        package let configured: (name: String, bytes: Data)?
    }

    /// Composes the selected action certificates for one checked render in compiler action order.
    package static func catalogProof(
        for rendered: RenderedSpecification, translations: [Translation], nativeSource: String? = nil
    ) throws -> CatalogProof {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        let ordered = translations.sorted { $0.actionOrdinal < $1.actionOrdinal }
        let root = rendered.tlaBundle.root
        let prefix = "AssignmentCatalog"
        let name = "SwiftTLAOrderedAssignmentCatalog" + root.name
        let nativeDataName = name + "NativeData"
        guard let first = ordered.first, !root.tla.contains(prefix),
              case .compiled(let identity, _, _) = rendered.tlaBundle.provenance, identity == first.program.identity,
              ordered.allSatisfy({ $0.program.identity == identity && $0.authoredSourceSHA256 == first.authoredSourceSHA256 }),
              let counter = first.program.layout.variables.first(where: { $0.declaration.origin == .programCounter }),
              let terminal = first.program.layout.actions.last, terminal.isTermination,
              first.program.requiresOrderedIntOutput(terminal.id), terminal.id.ordinal == ordered.count else { throw invalid }
        let direct = try first.program.renderModule()
        guard root.tla.utf8.elementsEqual(direct.renderedModuleSource.utf8), rendered.actions == direct.renderedActions,
              let catalog = StraightLineRenderedActionCheck.unboundActionCatalog(in: rendered, layout: first.program.layout),
              catalog.invocations.count == ordered.count + 1,
              zip(ordered, catalog.invocations).enumerated().allSatisfy({ index, row in
                  row.0.actionOrdinal == index && row.0.sourceAction.utf8.elementsEqual(row.1.sourceName.utf8)
              }) else { throw invalid }

        let modules = ordered.enumerated().map { index, translation in
            (slot: index + 1, instance: "\(prefix)Action\(index + 1)", module: translation.output.name,
             history: "history\(index + 1)", physical: catalog.invocations[index].renderedName,
             nativeModule: "\(name)NativeAction\(index + 1)")
        }
        guard let last = modules.last else { throw invalid }
        func tuple(_ values: [String]) -> String { "<<\(values.joined(separator: ", "))>>" }
        let instances = modules.map { "LOCAL \($0.instance) == INSTANCE \($0.module)" }.joined(separator: "\n")
        let types = modules.map { "/\\ \($0.instance)!RHSOutputStateType" }.joined(separator: "\n    ")
        let terminalSlot = catalog.invocations.count
        let slotSet = (1...terminalSlot).map { String($0) }.joined(separator: ", ")
        let selectedHistories = tuple(modules.map(\.history))
        let emittedFailures = tuple(modules.map { "\($0.instance)!RHSOutputActualFailures" })
        let certifiedFailures = tuple(modules.map { "\($0.instance)!RHSOutputHistoryFailures(histories[\($0.slot)])" })
        let certifiedActions = tuple(modules.map { "\($0.instance)!RHSOutputHistoryAdvance(histories[\($0.slot)])" }
            + ["\(prefix)Terminal"])
        let witnessChecks = modules.map { row in
            #"""
            /\ \#(row.instance)!RHSOutputSourceHistory(histories[\#(row.slot)])
            /\ \#(row.instance)!RHSOutputGeneratedHistory(histories[\#(row.slot)])
            /\ \#(row.instance)!RHSOutputHistoryObservation(histories[\#(row.slot)])
            """#
        }.joined(separator: "\n").replacingOccurrences(of: "\n", with: "\n    ")
        let historyProofs = modules.map { row in
            #"""
            <1>pick\#(row.slot). PICK \#(row.history) :
                /\ \#(row.instance)!RHSOutputSourceHistory(\#(row.history))
                /\ \#(row.instance)!RHSOutputGeneratedHistory(\#(row.history))
                /\ \#(row.instance)!RHSOutputHistoryObservation(\#(row.history))
                BY ONLY \#(prefix)InputType, \#(row.instance)!ActualTLAActionHasACertifiedAssignmentHistory
                    DEF \#(prefix)InputType
            <1>physical\#(row.slot). \#(row.physical) <=> \#(row.instance)!\#(row.physical)
                BY ONLY DEF \#(row.physical), \#(row.instance)!\#(row.physical)
            <1>row\#(row.slot).
                /\ (\#(row.physical) <=> \#(row.instance)!RHSOutputHistoryAdvance(\#(row.history)))
                /\ \#(row.instance)!RHSOutputActualFailures = \#(row.instance)!RHSOutputHistoryFailures(\#(row.history))
                BY ONLY <1>pick\#(row.slot), <1>physical\#(row.slot), PTL
                    DEF \#(row.instance)!RHSOutputHistoryObservation
            """#
        }.joined(separator: "\n")
        let picks = modules.map { "<1>pick\($0.slot)" }.joined(separator: ", ")
        let rows = modules.map { "<1>row\($0.slot)" }.joined(separator: ", ")
        let slots = (1...terminalSlot).map { slot in
            #"/\ (\#(prefix)ActualActionValues[\#(slot)] <=> \#(prefix)CertifiedActions(histories)[\#(slot)])"#
        }.joined(separator: "\n    ")
        let nativeDefinitions = try nativeSource.map {
            try nativeScalarActionDefinitions($0, program: first.program, retainingFailureSites: true)
        }
        let names = TLAValue.function(Dictionary(uniqueKeysWithValues:
            first.program.layout.variables.filter { $0.declaration.origin == .source }.map {
                (.string($0.declaration.name), .string($0.formalName))
            }))
        let pc = counter.formalName
        let actionCatalog = catalog.proofSource(prefix: prefix, exportDispatch: nativeSource != nil)
        let nativeData = nativeDefinitions.map { definitions in
            return #"""
            ---- MODULE \#(nativeDataName) ----
            EXTENDS \#(root.name), TLAPS

            \#(actionCatalog.dispatch)
            \#(actionCatalog.body)

            \#(definitions)
            NativeFormalNames == \#(names)
            NativeCounter == \#(TLAValue.string(pc))
            NativeVisitorPlans == [slot \in DOMAIN NativeActionRows |-> NativeActionRows[slot][2]]
            NativeActionAt(slot) == \#(prefix)Dispatch!NativeDispatchOutcome(NativeActionRoutes, NativeVisitorPlans, slot)

            ====

            """#
        }
        let nativeOperators = nativeSource == nil ? "" : #"""
        \#(prefix)NativeSelectedSteps == \#(tuple(modules.map { "NativeStep\($0.slot)" }))
        \#(prefix)NativeSelectedFailures == \#(tuple(modules.map { "NativeFailures\($0.slot)" }))
        \#(prefix)NativeOrderedOutputs == \#(tuple(modules.map { "NativeOrderedOutput\($0.slot)" }))
        \#(prefix)CertifiedOrderedOutputs(histories) ==
            \#(tuple(modules.map { "CertifiedOrderedOutput\($0.slot)(histories[\($0.slot)])" }))
        \#(prefix)NativeOrderedOutputsHold(histories) ==
            \#(modules.map { "/\\ NativeOrderedOutputHolds\($0.slot)(histories[\($0.slot)])" }.joined(separator: "\n    "))
        """#
        let nativeConclusion = nativeSource == nil ? "" : #"""
                /\ \A slot \in DOMAIN \#(prefix)NativeSelectedSteps :
                       \#(prefix)NativeSelectedSteps[slot] <=> \#(prefix)CertifiedActions(histories)[slot]
                /\ \#(prefix)NativeSelectedFailures = \#(prefix)ActualFailures
                /\ \#(prefix)NativeOrderedOutputsHold(histories)
        """#
        let nativeRows: [(name: String, bytes: Data)] = nativeSource == nil ? [] : modules.map { row in
            let proof = #"""
            ---- MODULE \#(row.nativeModule) ----
            EXTENDS \#(nativeDataName)

            \#(row.instance) == INSTANCE \#(row.module)

            LOCAL NativePlan\#(row.slot) == NativeActionAt(\#(row.slot)).outcome
            LOCAL NativeAppendSites\#(row.slot) ==
                {NativeActionFailureAppendSites[NativeActionRoutes[\#(row.slot)].visitor][index] :
                   index \in DOMAIN NativeActionFailureAppendSites[NativeActionRoutes[\#(row.slot)].visitor]}
            NativeStep\#(row.slot) ==
                \#(row.instance)!RHSOutputInput!Rule!DecodedNativeAssignmentStep(
                    \#(row.instance)!RHSOutputRows, NativePlan\#(row.slot), NativeFormalNames, NativeCounter,
                    \#(row.instance)!RHSOutputBefore, \#(row.instance)!RHSOutputAfter, \#(pc), \#(pc)')
            NativeFailures\#(row.slot) ==
                \#(row.instance)!RHSOutputInput!Rule!DecodedNativeAssignmentFailures(
                    \#(row.instance)!RHSOutputRows, NativePlan\#(row.slot), NativeFormalNames, NativeCounter,
                    \#(row.instance)!RHSOutputBefore, \#(pc), NativeAppendSites\#(row.slot))
            NativeOrderedOutput\#(row.slot) ==
                \#(row.instance)!RHSOutputInput!Rule!DecodedNativeAssignmentOrderedOutput(
                    \#(row.instance)!RHSOutputRows, NativePlan\#(row.slot), NativeFormalNames, NativeCounter,
                    \#(row.instance)!RHSOutputBefore, \#(pc), NativeAppendSites\#(row.slot))
            CertifiedOrderedOutput\#(row.slot)(history) ==
                \#(row.instance)!RHSOutputInput!Rule!CertifiedAssignmentOrderedOutput(
                    history[\#(row.instance)!RHSOutputCount], \#(row.instance)!RHSOutputSelected,
                    \#(row.instance)!RHSOutputExit)
            NativeOrderedOutputHolds\#(row.slot)(history) ==
                /\ NativeOrderedOutput\#(row.slot) = CertifiedOrderedOutput\#(row.slot)(history)
                /\ \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentOrderedOutputsTyped(
                      NativeOrderedOutput\#(row.slot), history[\#(row.instance)!RHSOutputCount], \#(row.instance)!RHSOutputExit)

            THEOREM ActualNativeAction\#(row.slot)UsesTheCertifiedHistory ==
                ASSUME \#(row.instance)!RHSOutputStateType,
                       NEW \#(row.history),
                       \#(row.instance)!RHSOutputSourceHistory(\#(row.history)),
                       \#(row.instance)!RHSOutputHistoryObservation(\#(row.history))
                PROVE /\ (NativeStep\#(row.slot) <=> \#(row.instance)!RHSOutputHistoryAdvance(\#(row.history)))
                      /\ NativeFailures\#(row.slot) = \#(row.instance)!RHSOutputActualFailures
                      /\ NativeOrderedOutputHolds\#(row.slot)(\#(row.history))
            PROOF
            <1>failureObservation.
                \#(row.instance)!RHSOutputActualFailures = \#(row.instance)!RHSOutputHistoryFailures(\#(row.history))
                BY ONLY \#(row.instance)!RHSOutputHistoryObservation(\#(row.history))
                    DEF \#(row.instance)!RHSOutputHistoryObservation
            <1>native\#(row.slot).
                /\ (NativeStep\#(row.slot) <=> \#(row.instance)!RHSOutputHistoryAdvance(\#(row.history)))
                /\ NativeFailures\#(row.slot) = \#(row.instance)!RHSOutputActualFailures
                /\ NativeOrderedOutputHolds\#(row.slot)(\#(row.history))
                PROOF
                <2>. DEFINE route == NativeActionAt(\#(row.slot))
                            raw == NativePlan\#(row.slot)
                            appendSites == NativeAppendSites\#(row.slot)
                            keys == \#(row.instance)!RHSOutputKeys
                            count == \#(row.instance)!RHSOutputCount
                            authored == \#(row.instance)!RHSOutputRows
                            selected == \#(row.instance)!RHSOutputSelected
                            entry == \#(row.instance)!RHSOutputEntry
                            destination == \#(row.instance)!RHSOutputExit
                            plan == \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentRekey(raw, NativeFormalNames, NativeCounter)
                            relevant == \#(row.instance)!RHSOutputActualFailures
                            final == \#(row.history)[count]
                <2>routing.
                    /\ route.formal = \#(prefix)ActualFormalLabels[\#(row.slot)]
                    /\ NativeActionRoutes[\#(row.slot)].visitor = \#(row.slot)
                    /\ NativeActionRows[\#(row.slot)][1] = \#(row.instance)!RHSOutputActionLabel
                    BY ONLY IsaM("simp") DEF route, NativeActionAt, NativeActionRoutes, NativeActionRows,
                        \#(prefix)Dispatch!NativeDispatchOutcome, \#(prefix)ActualFormalLabels,
                        \#(prefix)ActualActionRoutes, \#(row.instance)!RHSOutputActionLabel
                <2>. DEFINE visitorPlan == NativeVisitor\#(row.slot)Action
                            tags == NativeVisitor\#(row.slot)CaptureTags
                            captures == NativeVisitor\#(row.slot)Captures
                            columns == NativeVisitor\#(row.slot)Plans
                            rendered == \#(row.instance)!RHSOutputPlans
                <2>physicalPlan. raw = visitorPlan
                    <3>ordinal. \#(row.slot) \in DOMAIN NativeActionRows
                        BY ONLY IsaM("simp") DEF NativeActionRows
                    <3>. QED BY ONLY <2>routing, <3>ordinal, IsaM("simp"), SMT
                        DEF raw, NativePlan\#(row.slot), visitorPlan, NativeActionAt, NativeVisitorPlans,
                            \#(prefix)Dispatch!NativeDispatchOutcome, NativeActionRoutes, NativeActionRows
                <2>physicalRoles. \#(row.instance)!RHSOutputInput!Rule!NativeCopyKnownRoles(raw, keys, NativeFormalNames, NativeCounter)
                    <3>. DEFINE physical == \#(row.instance)!RHSOutputInput!Rule!NativeCopyPhysicalKeys(
                                    keys, NativeFormalNames, NativeCounter)
                    <3>layout.
                        /\ keys \subseteq STRING
                        /\ DOMAIN NativeFormalNames = keys
                        /\ \A key \in keys : NativeFormalNames[key] # NativeCounter
                        /\ \A key, other \in keys : NativeFormalNames[key] = NativeFormalNames[other] => key = other
                        BY ONLY SMT DEF keys, \#(row.instance)!RHSOutputKeys, NativeFormalNames, NativeCounter
                    <3>captureTags. \A index \in DOMAIN captures :
                        captures[index][1] = "state" => captures[index][2] \in physical
                        BY ONLY <3>layout, SMT DEF captures, tags, physical,
                            \#(row.instance)!RHSOutputInput!Rule!NativeCopyPhysicalKeys,
                            NativeVisitor\#(row.slot)Captures, NativeVisitor\#(row.slot)CaptureTags, NativeVisitor\#(row.slot)NodeReads,
                            keys, \#(row.instance)!RHSOutputKeys, NativeFormalNames, NativeCounter
                    <3>writeNames. \A index \in DOMAIN NativeVisitor\#(row.slot)Writes :
                        /\ NativeVisitor\#(row.slot)Writes[index][1] \in physical
                        /\ (NativeVisitor\#(row.slot)Writes[index][2][1] = "state" =>
                            NativeVisitor\#(row.slot)Writes[index][2][2] \in physical)
                        BY ONLY SMT DEF physical, \#(row.instance)!RHSOutputInput!Rule!NativeCopyPhysicalKeys,
                            keys, \#(row.instance)!RHSOutputKeys, NativeFormalNames, NativeCounter, NativeVisitor\#(row.slot)Writes
                    <3>. QED BY ONLY <2>physicalPlan, <3>layout, <3>captureTags, <3>writeNames, SMT
                        DEF visitorPlan, captures, physical, NativeVisitor\#(row.slot)Action,
                            \#(row.instance)!RHSOutputInput!Rule!NativeCopyKnownRoles
                <2>packed. raw.captures = [index \in DOMAIN tags |->
                        \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentPackedCapture(tags[index], columns[index])]
                    <3>physical. raw.captures = captures
                        BY ONLY <2>physicalPlan DEF visitorPlan, captures, NativeVisitor\#(row.slot)Action
                    <3>values. \A index \in DOMAIN tags :
                        /\ columns[index].literals = NativeVisitor\#(row.slot)NodeLiterals[index]
                        /\ columns[index].reads = NativeVisitor\#(row.slot)NodeReads[index]
                        BY ONLY SMT DEF tags, columns, NativeVisitor\#(row.slot)Plans
                    <3>entries. \A index \in DOMAIN tags :
                        captures[index] = \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentPackedCapture(tags[index], columns[index])
                        BY ONLY <3>values, SMT DEF tags, columns, captures, NativeVisitor\#(row.slot)Captures,
                            \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentPackedCapture
                    <3>shape. captures = [index \in DOMAIN tags |-> captures[index]]
                        BY ONLY SMT DEF tags, captures, NativeVisitor\#(row.slot)Captures
                    <3>. QED BY ONLY <3>physical, <3>entries, <3>shape, SMT
                <2>domains. /\ DOMAIN tags = 1..count /\ DOMAIN rendered = 1..count
                    BY ONLY \#(row.instance)!RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory,
                        IsaM("simp"), SMT DEF tags, NativeVisitor\#(row.slot)CaptureTags, count, \#(row.instance)!RHSOutputCount,
                            \#(row.instance)!RHSOutputInput!Rule!SupportedAssignmentList
                <2>keys. keys = \#(row.instance)!RHSOutputInput!MasterFields
                    BY ONLY \#(row.instance)!RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory DEF keys
                <2>columnFacts. \A index \in DOMAIN tags :
                    /\ \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentDirectColumn(tags[index], columns[index])
                    /\ \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentColumnRecord(rendered[index])
                    /\ columns[index] = [rendered[index] EXCEPT !.reads = columns[index].reads]
                    /\ \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentReadColumnsMatch(columns[index], rendered[index], NativeFormalNames)
                    <3>columns.
                        /\ NativeVisitor\#(row.slot)NodeCounts = \#(row.instance)!RHSOutputNodeCounts
                        /\ NativeVisitor\#(row.slot)NodeKinds = \#(row.instance)!RHSOutputNodeKinds
                        /\ NativeVisitor\#(row.slot)NodeLiterals = \#(row.instance)!RHSOutputNodeLiterals
                        /\ NativeVisitor\#(row.slot)NodeLeft = \#(row.instance)!RHSOutputNodeLeft
                        /\ NativeVisitor\#(row.slot)NodeRight = \#(row.instance)!RHSOutputNodeRight
                        BY ONLY SMT DEF NativeVisitor\#(row.slot)NodeCounts, NativeVisitor\#(row.slot)NodeKinds,
                            NativeVisitor\#(row.slot)NodeLiterals, NativeVisitor\#(row.slot)NodeLeft, NativeVisitor\#(row.slot)NodeRight,
                            \#(row.instance)!RHSOutputNodeCounts, \#(row.instance)!RHSOutputNodeKinds, \#(row.instance)!RHSOutputNodeLiterals,
                            \#(row.instance)!RHSOutputNodeLeft, \#(row.instance)!RHSOutputNodeRight
                    <3>. TAKE index \in DOMAIN tags
                    <3>direct. \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentDirectColumn(tags[index], columns[index])
                        <4>shape. tags[index] = "expression" \/
                            LET literal == tags[index] = "literal"
                            IN columns[index] = [count |-> 1, kinds |-> <<IF literal THEN "literal" ELSE "read">>,
                                literals |-> <<IF literal THEN columns[index].literals[1] ELSE 0>>,
                                reads |-> columns[index].reads, left |-> <<0>>, right |-> <<0>>]
                            BY ONLY (index \in DOMAIN tags), SMT DEF tags, columns, NativeVisitor\#(row.slot)CaptureTags,
                                NativeVisitor\#(row.slot)Plans, NativeVisitor\#(row.slot)NodeCounts, NativeVisitor\#(row.slot)NodeKinds,
                                NativeVisitor\#(row.slot)NodeLiterals, NativeVisitor\#(row.slot)NodeLeft, NativeVisitor\#(row.slot)NodeRight
                        <4>reference. tags[index] \notin {"expression", "literal"} =>
                            /\ columns[index].reads = <<columns[index].reads[1]>>
                            /\ columns[index].reads[1][1] = tags[index]
                            BY ONLY (index \in DOMAIN tags), SMT DEF tags, columns, NativeVisitor\#(row.slot)CaptureTags,
                                NativeVisitor\#(row.slot)Plans, NativeVisitor\#(row.slot)NodeReads
                        <4>. QED BY ONLY <4>shape, <4>reference, SMT
                            DEF \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentDirectColumn
                    <3>fields. \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentColumnRecord(rendered[index])
                        BY ONLY <2>domains, (index \in DOMAIN tags), SMT DEF rendered, \#(row.instance)!RHSOutputPlans,
                            \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentColumnRecord
                    <3>nonReads. columns[index] = [rendered[index] EXCEPT !.reads = columns[index].reads]
                        BY ONLY <3>columns, <2>domains, (index \in DOMAIN tags), SMT
                            DEF tags, columns, rendered, NativeVisitor\#(row.slot)Plans, \#(row.instance)!RHSOutputPlans
                    <3>readColumns.
                        \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentReadColumnsMatch(columns[index], rendered[index], NativeFormalNames)
                        BY ONLY <3>columns, <2>domains, <2>keys, (index \in DOMAIN tags), SMT
                            DEF columns, rendered, keys, NativeFormalNames, \#(row.instance)!RHSOutputCount,
                                \#(row.instance)!RHSOutputKeys, \#(row.instance)!RHSOutputPlans, \#(row.instance)!RHSOutputNodeCounts,
                                \#(row.instance)!RHSOutputNodeReads, \#(row.instance)!RHSOutputInput!MasterFields,
                                NativeVisitor\#(row.slot)Plans, NativeVisitor\#(row.slot)NodeKinds, NativeVisitor\#(row.slot)NodeReads,
                                \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentReadColumnsMatch
                    <3>. QED BY ONLY <3>direct, <3>fields, <3>nonReads, <3>readColumns
                <2>renderedVector. rendered = [index \in DOMAIN tags |-> rendered[index]]
                    BY ONLY <2>domains, SMT DEF rendered, \#(row.instance)!RHSOutputPlans
                <2>physicalInputs. \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentPhysicalColumns(raw, NativeFormalNames, NativeCounter, tags, columns, rendered)
                    BY ONLY <2>physicalRoles, <2>packed, <2>renderedVector, <2>keys, <2>columnFacts, SMT
                        DEF \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentPhysicalColumns
                <2>normalizedResult. \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentNormalizedCaptures(raw, NativeFormalNames, NativeCounter, rendered)
                    BY ONLY <2>physicalInputs, \#(row.instance)!RHSOutputUsesTheMachineIntegerDomain, \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentColumnsDetermineRekeyedCaptures, SMT
                <2>normalized.
                    /\ \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentReadNamesAreKnown(raw, NativeFormalNames)
                    /\ plan.captures = rendered
                    BY ONLY <2>normalizedResult DEF \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentNormalizedCaptures, plan
                <2>roles.
                    /\ \#(row.instance)!RHSOutputInput!Rule!NativeCopyKnownRoles(raw, keys, NativeFormalNames, NativeCounter)
                    /\ \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentReadNamesAreKnown(raw, NativeFormalNames)
                    BY ONLY <2>physicalRoles, <2>normalized
                <2>rawWrites. /\ Len(raw.writes) \in Nat /\ DOMAIN raw.writes = 1..Len(raw.writes)
                    BY ONLY <2>physicalPlan, IsaM("simp") DEF visitorPlan,
                        NativeVisitor\#(row.slot)Action, NativeVisitor\#(row.slot)Writes
                <2>. DEFINE writes == NativeVisitor\#(row.slot)Writes
                            finalRoutes == \#(row.instance)!RHSOutputWriteRoutes
                <2>physicalWrites. raw.writes = writes /\ raw.guards = <<entry>>
                    BY ONLY <2>physicalPlan, SMT DEF visitorPlan, writes, entry, NativeVisitor\#(row.slot)Action,
                        NativeVisitor\#(row.slot)Guards, \#(row.instance)!RHSOutputEntry
                <2>writeSet.
                    {writes[index] : index \in DOMAIN writes} =
                        {\#(row.instance)!RHSOutputInput!Rule!NativeAssignmentPhysicalWriteRow(NativeFormalNames, NativeCounter, destination, finalRoutes, key) :
                            key \in \#(row.instance)!RHSOutputInput!Rule!NativeCopyFields(keys)}
                    BY ONLY SMT DEF writes, finalRoutes, keys, destination, NativeVisitor\#(row.slot)Writes, NativeFormalNames, NativeCounter,
                        \#(row.instance)!RHSOutputKeys, \#(row.instance)!RHSOutputExit, \#(row.instance)!RHSOutputWriteRoutes,
                        \#(row.instance)!RHSOutputInput!Rule!NativeCopyFields, \#(row.instance)!RHSOutputInput!Rule!NativeCopyControlSlot, \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentPhysicalWriteRow
                <2>namingInputs.
                    \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentPhysicalNamingInputs(
                        authored, raw, NativeFormalNames, NativeCounter, entry, destination, rendered, finalRoutes)
                    <3>bounds. count = Len(authored) /\ DOMAIN authored = 1..count
                        BY ONLY \#(row.instance)!RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory,
                            SMT DEF authored, count, \#(row.instance)!RHSOutputCount, \#(row.instance)!RHSOutputInput!Rule!SupportedAssignmentList
                    <3>captureWriters. \A index \in DOMAIN authored :
                        \#(row.instance)!RHSOutputInput!Rule!PhysicalAssignmentReadsNameWriters(authored, index, rendered[index])
                        BY ONLY \#(row.instance)!ActualRenderedRightHandSidesNameTheAuthoredWriters DEF authored, rendered
                    <3>finalWriters. \A key \in keys : \#(row.instance)!RHSOutputInput!Rule!CopyReceiptNamesWriter(authored, count, key, finalRoutes[key])
                        BY ONLY \#(row.instance)!ActualRenderedWriteRoutesNameTheAuthoredWriters DEF authored, count, keys, finalRoutes
                    <3>control. \#(row.instance)!RHSOutputInput!Rule!NativeCopyControlSlot \notin keys
                        BY ONLY SMT DEF keys, \#(row.instance)!RHSOutputKeys, \#(row.instance)!RHSOutputInput!Rule!NativeCopyControlSlot
                    <3>. QED BY ONLY <2>keys, <2>roles, <2>normalized, <2>domains, <2>rawWrites, <2>physicalWrites, <2>writeSet,
                        <3>bounds, <3>captureWriters, <3>finalWriters, <3>control, SMT DEF \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentPhysicalNamingInputs, plan
                <2>named.
                    \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentsNameTheirOperandsAndWrites(authored, raw, NativeFormalNames, NativeCounter, entry, destination)
                    BY ONLY <2>namingInputs, \#(row.instance)!RHSOutputUsesTheMachineIntegerDomain,
                        \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentPhysicalRowsNameTheAuthoredWriters, SMT
                <2>append. \A probe \in DOMAIN \#(row.instance)!RHSOutputProbePositions :
                    \#(row.instance)!RHSOutputProbePositions[probe][1] \in appendSites
                    BY ONLY <2>routing, SMT
                        DEF appendSites, NativeAppendSites\#(row.slot), NativeActionRoutes,
                            NativeActionFailureAppendSites, NativeVisitor\#(row.slot)FailureAppendSites, \#(row.instance)!RHSOutputProbePositions
                <2>probedPositions. \#(row.instance)!RHSOutputFailureProbeSites \subseteq
                        DOMAIN \#(row.instance)!RHSOutputProbePositions
                    <3>domain. DOMAIN \#(row.instance)!RHSOutputGuards = DOMAIN \#(row.instance)!RHSOutputProbePositions
                        BY ONLY IsaM("simp") DEF \#(row.instance)!RHSOutputGuards, \#(row.instance)!RHSOutputProbePositions
                    <3>. QED BY ONLY <3>domain, SMT DEF \#(row.instance)!RHSOutputFailureProbeSites
                <2>selectedFailure. selected /\ final.failure # <<>> => final.failure.site \in appendSites
                    <3>events. \A event \in relevant : event.site \in appendSites
                        BY ONLY <2>append, <2>probedPositions, SMT
                            DEF relevant, \#(row.instance)!RHSOutputActualFailures, \#(row.instance)!RHSOutputFailureEvent
                    <3>. QED BY ONLY <3>events, <1>failureObservation, SMT DEF relevant, selected, final, count,
                        \#(row.instance)!RHSOutputHistoryFailures
                <2>observationInputs. \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentObservationInputs(authored, raw, NativeFormalNames, NativeCounter, entry, destination, \#(row.instance)!RHSOutputBefore, pc, appendSites, \#(row.history))
                    BY ONLY <2>named, <2>selectedFailure, \#(row.instance)!RHSOutputSourceHistory(\#(row.history)),
                        \#(row.instance)!RHSOutputSourceRowsAreSupportedAndMatchTheActionInventory,
                        \#(row.instance)!RHSOutputStateType, \#(row.instance)!RHSOutputStateSuppliesAssignmentBindings, SMT
                        DEF \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentObservationInputs, \#(row.instance)!RHSOutputSourceHistory, \#(row.instance)!RHSOutputSelected, \#(row.instance)!RHSOutputCount,
                            authored, entry, destination, count, selected, final
                <2>observationResult. \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentObservationMatches(authored, raw, NativeFormalNames, NativeCounter, entry, destination, \#(row.instance)!RHSOutputBefore, \#(row.instance)!RHSOutputAfter, pc, pc', appendSites, \#(row.history))
                    BY ONLY <2>observationInputs, \#(row.instance)!RHSOutputUsesTheMachineIntegerDomain, \#(row.instance)!RHSOutputInput!Rule!DecodedNativeAssignmentsUseTheCertifiedActionObservation, SMT
                <2>math. /\ (NativeStep\#(row.slot) <=> \#(row.instance)!RHSOutputHistoryAdvance(\#(row.history)))
                         /\ NativeFailures\#(row.slot) = \#(row.instance)!RHSOutputHistoryFailures(\#(row.history))
                    BY ONLY <2>observationResult, SMT DEF \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentObservationMatches, NativeStep\#(row.slot), NativeFailures\#(row.slot),
                        \#(row.instance)!RHSOutputHistoryAdvance, \#(row.instance)!RHSOutputHistoryFailures, \#(row.instance)!RHSOutputSelected, \#(row.instance)!RHSOutputCount,
                        authored, raw, appendSites, entry, destination
                <2>ordered. NativeOrderedOutputHolds\#(row.slot)(\#(row.history))
                    BY ONLY <2>observationResult, SMT
                        DEF \#(row.instance)!RHSOutputInput!Rule!NativeAssignmentObservationMatches,
                            NativeOrderedOutputHolds\#(row.slot), NativeOrderedOutput\#(row.slot),
                            CertifiedOrderedOutput\#(row.slot), \#(row.instance)!RHSOutputSelected,
                            \#(row.instance)!RHSOutputCount, authored, raw, appendSites, entry, destination
                <2>. QED BY ONLY <2>math, <2>ordered, <1>failureObservation
            <1>. QED BY ONLY <1>native\#(row.slot)

            ====

            """#
            return (row.nativeModule, Data(proof.utf8))
        }
        let nativeChecks = nativeSource == nil ? "" : modules.map { row in
            #"""
            <1>native\#(row.slot).
                /\ (NativeStep\#(row.slot) <=> \#(row.instance)!RHSOutputHistoryAdvance(\#(row.history)))
                /\ NativeFailures\#(row.slot) = \#(row.instance)!RHSOutputActualFailures
                /\ NativeOrderedOutputHolds\#(row.slot)(\#(row.history))
                BY ONLY \#(prefix)InputType, <1>pick\#(row.slot), ActualNativeAction\#(row.slot)UsesTheCertifiedHistory,
                    SMT DEF \#(prefix)InputType
            """#
        }.joined(separator: "\n")
        let nativeResults: String
        if nativeSource == nil {
            nativeResults = ""
        } else {
            let checks = modules.map { "<1>native\($0.slot)" }.joined(separator: ", ")
            let indices = modules.map { String($0.slot) }.joined(separator: ", ")
            let nativeLabeled = modules.map { row in
                #"/\ (\#(prefix)NativeSelectedSteps[\#(row.slot)] <=> \#(prefix)CertifiedActions(histories)[\#(row.slot)])"#
            }.joined(separator: "\n    ")
            nativeResults = #"""
        <1>nativeSlots.
            \#(nativeLabeled)
            BY ONLY \#(checks), IsaM("simp") DEF histories, \#(prefix)NativeSelectedSteps, \#(prefix)CertifiedActions
        <1>nativeDomain. DOMAIN \#(prefix)NativeSelectedSteps = {\#(indices)}
            BY ONLY IsaM("simp"), SMT DEF \#(prefix)NativeSelectedSteps
        <1>nativeResult.
            /\ \A slot \in DOMAIN \#(prefix)NativeSelectedSteps :
                \#(prefix)NativeSelectedSteps[slot] <=> \#(prefix)CertifiedActions(histories)[slot]
            /\ \#(prefix)NativeSelectedFailures = \#(prefix)ActualFailures
            /\ \#(prefix)NativeOrderedOutputsHold(histories)
            BY ONLY <1>nativeSlots, <1>nativeDomain, \#(checks), SMT
                DEF \#(prefix)NativeSelectedFailures, \#(prefix)ActualFailures, \#(prefix)NativeOrderedOutputsHold, histories
        """#
        }
        let nativeFact = nativeSource == nil ? "" : ", <1>nativeResult"
        let terminalRule = "\(last.instance)!RHSOutputInput!Rule"
        let nativeTerminal = nativeSource == nil ? "" : #"""
        LOCAL TerminalKeys == \#(last.instance)!RHSOutputKeys
        LOCAL TerminalBindings == \#(last.instance)!RHSOutputBefore
        LOCAL TerminalControl == \#(last.instance)!RHSOutputExit
        LOCAL TerminalPlan == \#(terminalRule)!NativeCopyRekey(NativeActionAt(\#(terminalSlot)).outcome,
            TerminalKeys, NativeFormalNames, NativeCounter)
        LOCAL TerminalAppendSites == NativeActionFailureAppendSites[NativeActionRoutes[\#(terminalSlot)].visitor]

        NativeTerminalOrderedOutput ==
            IF TerminalPlan.captures = <<>> /\ TerminalAppendSites = <<>>
            THEN [callbacks |-> \#(terminalRule)!NativeCopyCallbackSnapshots(
                  TerminalPlan, TerminalKeys, TerminalBindings, \#(pc), <<>>), reasons |-> <<>>]
            ELSE <<>>

        CertifiedTerminalOrderedOutput ==
            [callbacks |-> IF \#(pc) = TerminalControl THEN << <<\#(pc), TerminalBindings>> >> ELSE <<>>,
             reasons |-> <<>>]

        THEOREM NativeTerminalOrderedOutputUsesTheCompleteFrame ==
            ASSUME \#(prefix)InputType
            PROVE /\ NativeTerminalOrderedOutput = CertifiedTerminalOrderedOutput
                  /\ NativeTerminalOrderedOutput.callbacks \in Seq({<<\#(pc), TerminalBindings>>})
                  /\ NativeTerminalOrderedOutput.reasons \in Seq({})
        PROOF
        <1>plan. /\ \#(terminalRule)!NativeCompleteCopyPlan(TerminalPlan, TerminalKeys, <<>>,
                      \#(terminalRule)!CopyEntryRoutes(TerminalKeys), TerminalControl,
                      <<"state", \#(terminalRule)!NativeCopyControlSlot>>)
                 /\ TerminalAppendSites = <<>>
            BY ONLY SMT DEF TerminalPlan, TerminalKeys, TerminalControl, TerminalAppendSites,
                NativeActionAt, NativeActionRoutes, NativeVisitorPlans, NativeActionRows, NativeFormalNames, NativeCounter,
                NativeVisitor\#(terminalSlot)Action, NativeVisitor\#(terminalSlot)Captures,
                NativeVisitor\#(terminalSlot)CaptureTags, NativeVisitor\#(terminalSlot)Guards,
                NativeVisitor\#(terminalSlot)Writes, NativeActionFailureAppendSites, NativeVisitor\#(terminalSlot)FailureAppendSites,
                \#(prefix)Dispatch!NativeDispatchOutcome, \#(last.instance)!RHSOutputKeys, \#(last.instance)!RHSOutputExit,
                \#(terminalRule)!NativeCompleteCopyPlan, \#(terminalRule)!NativeCopyRekey,
                \#(terminalRule)!NativeCopyKey, \#(terminalRule)!NativeCopyFields,
                \#(terminalRule)!NativeCopyControlSlot, \#(terminalRule)!CopyEntryRoutes
        <1>state. TerminalBindings = [key \in TerminalKeys |-> TerminalBindings[key]]
            BY ONLY SMT DEF TerminalKeys, TerminalBindings, \#(last.instance)!RHSOutputKeys, \#(last.instance)!RHSOutputBefore
        <1>captures. \A witness : \#(terminalRule)!CopyCaptureHistory(
            \#(terminalRule)!NativeCopySnapshot(TerminalKeys, TerminalBindings, \#(pc)), TerminalPlan.captures, witness)
            => witness = <<>>
            BY ONLY <1>plan, SMT DEF \#(terminalRule)!NativeCompleteCopyPlan, \#(terminalRule)!CopyCaptureHistory
        <1>visit. \#(pc) = TerminalControl => \#(terminalRule)!NativeCopyVisits(
            TerminalPlan, TerminalKeys, TerminalBindings, TerminalBindings, \#(pc), \#(pc))
            BY ONLY <1>state, <1>plan, \#(terminalRule)!EmptyCopyPlanRetainsTheCompleteState,
                \#(terminalRule)!ValidatedNativeCopyPlansHaveTheCompleteCompiledObservation, SMT
        <1>output. NativeTerminalOrderedOutput = CertifiedTerminalOrderedOutput
            <2>done. CASE \#(pc) = TerminalControl
                BY ONLY <2>done, <1>plan, <1>visit, <1>state, <1>captures,
                    \#(terminalRule)!NativeCopyCallbackUsesTheMaterializedWriteHistory, SMT
                    DEF NativeTerminalOrderedOutput, CertifiedTerminalOrderedOutput, \#(terminalRule)!NativeCompleteCopyPlan
            <2>off. CASE \#(pc) # TerminalControl
                BY ONLY <2>off, <1>plan, SMT DEF NativeTerminalOrderedOutput, CertifiedTerminalOrderedOutput,
                    \#(terminalRule)!NativeCopyCallbackSnapshots, \#(terminalRule)!NativeCompleteCopyPlan
            <2>. QED BY ONLY <2>done, <2>off, SMT
        <1>. QED BY ONLY <1>output, \#(terminalRule)!SeqDef, SMT DEF CertifiedTerminalOrderedOutput
        """#
        let dependencies = nativeData.map { [(name: nativeDataName, bytes: Data($0.utf8))] + nativeRows } ?? []
        let extensions = nativeSource == nil ? "\(root.name), TLAPS" : nativeRows.map { $0.name }.joined(separator: ", ")
        let proof = #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(extensions)

        \#(nativeSource == nil ? actionCatalog.dispatch : "")
        \#(nativeSource == nil ? actionCatalog.body : "")

        \#(nativeSource == nil ? instances : "")
        \#(nativeOperators)

        \#(prefix)InputType ==
            \#(types)

        \#(prefix)Terminal ==
            /\ \#(counter.formalName) = \#(last.instance)!RHSOutputExit
            /\ \#(prefix)ActualFrameAfter = \#(prefix)ActualFrameBefore

        \#(nativeTerminal)

        \#(prefix)HistoriesHold(histories) ==
            \#(witnessChecks)

        \#(prefix)ActualFailures == \#(emittedFailures)
        \#(prefix)CertifiedFailures(histories) == \#(certifiedFailures)
        \#(prefix)CertifiedActions(histories) == \#(certifiedActions)
        \#(prefix)CertifiedNext(histories) ==
            \E slot \in DOMAIN \#(prefix)CertifiedActions(histories) : \#(prefix)CertifiedActions(histories)[slot]

        THEOREM ActualNextAndFailuresUseTheCertifiedAssignmentHistories ==
            ASSUME \#(prefix)InputType
            PROVE \E histories :
                /\ DOMAIN histories = 1..\#(ordered.count)
                /\ \#(prefix)HistoriesHold(histories)
        \#(nativeConclusion)
                /\ \#(prefix)ActualFailures = \#(prefix)CertifiedFailures(histories)
                /\ (\#(terminal.renderedName) <=> \#(prefix)Terminal)
                /\ (Next <=> \#(prefix)CertifiedNext(histories))
                /\ ([Next]_vars <=> (\#(prefix)CertifiedNext(histories)
                     \/ \#(prefix)ActualFrameAfter = \#(prefix)ActualFrameBefore))
        PROOF
        \#(historyProofs)
        \#(nativeChecks)
        <1>. DEFINE histories == \#(selectedHistories)
        <1>histories.
            /\ DOMAIN histories = 1..\#(ordered.count)
            /\ \#(prefix)HistoriesHold(histories)
            BY ONLY \#(picks), IsaM("simp") DEF histories, \#(prefix)HistoriesHold
        <1>failures. \#(prefix)ActualFailures = \#(prefix)CertifiedFailures(histories)
            BY ONLY \#(rows), IsaM("simp") DEF histories, \#(prefix)ActualFailures, \#(prefix)CertifiedFailures
        <1>terminal. \#(terminal.renderedName) <=> \#(prefix)Terminal
            BY ONLY SMT DEF \#(terminal.renderedName), \#(prefix)Terminal, \#(last.instance)!RHSOutputExit,
                \#(prefix)ActualFrameBefore, \#(prefix)ActualFrameAfter
        <1>domains.
            /\ DOMAIN \#(prefix)ActualActionValues = 1..\#(terminalSlot)
            /\ DOMAIN \#(prefix)CertifiedActions(histories) = 1..\#(terminalSlot)
            BY ONLY IsaM("simp") DEF \#(prefix)ActualActionValues, \#(prefix)CertifiedActions
        <1>finite. 1..\#(terminalSlot) = {\#(slotSet)}
            BY ONLY SMT
        <1>slots.
            \#(slots)
            BY ONLY \#(rows), <1>terminal, IsaM("simp")
                DEF histories, \#(prefix)ActualActionValues, \#(prefix)CertifiedActions
        <1>points. \A slot \in DOMAIN \#(prefix)ActualActionValues :
            \#(prefix)ActualActionValues[slot] <=> \#(prefix)CertifiedActions(histories)[slot]
            BY ONLY <1>domains, <1>finite, <1>slots, SMT
        <1>union. (\E \#(prefix)Index \in DOMAIN \#(prefix)ActualActionValues :
                       \#(prefix)ActualActionValues[\#(prefix)Index])
            <=> \#(prefix)CertifiedNext(histories)
            BY ONLY <1>domains, <1>points, SMT DEF \#(prefix)CertifiedNext
        <1>next. Next <=> \#(prefix)CertifiedNext(histories)
            BY ONLY \#(prefix)ActualNextUsesTheCompleteLabeledActionCatalog, <1>union, PTL
        <1>stuttering. [Next]_vars <=> (\#(prefix)CertifiedNext(histories)
            \/ \#(prefix)ActualFrameAfter = \#(prefix)ActualFrameBefore)
            BY ONLY \#(prefix)ActualNextUsesTheCompleteLabeledActionCatalog, <1>union, PTL
        \#(nativeResults)
        <1>. WITNESS histories
        <1>. QED BY ONLY <1>histories, <1>failures, <1>terminal, <1>next, <1>stuttering\#(nativeFact), PTL

        ====

        """#
        let configured = nativeSource == nil ? nil : OrderedRHSCFGProof.renderCatalog(
            for: rendered, catalogModule: name, prefix: prefix, counter: pc, actions: zip(modules, ordered).map {
                (instance: $0.0.instance, failureOperator: $0.1.output.failureOperator)
            })
        return .init(name: name, bytes: Data(proof.utf8), dependencies: dependencies, configured: configured)
    }

    package static func prepare(sourceSHA: String, authoredSource: Data, nativeSource: Data,
                                to directory: URL) throws {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        guard TLCReferencePin.isRevision(sourceSHA) else { throw InitialFailureEvidenceError.invalidSourceSHA }
        guard !nativeSource.contains(0), let native = String(data: nativeSource, encoding: .utf8) else { throw invalid }

        let rendered = try OrderedOverflowModel.render()
        let translation = try Self.translation(authoredSource: authoredSource,
            modelName: String(describing: OrderedOverflowModel.self), spec: OrderedOverflowModel.spec, rendered: rendered)
        let live = try observe(translation.program)
        guard translation.actionOrdinal == live.actionOrdinal,
              translation.sourceAction.utf8.elementsEqual(live.label.utf8),
              let configured = OrderedRHSCFGProof.render(for: rendered, catalog: translation.catalog,
                actionProofModule: translation.output.name) else { throw invalid }
        let nativeDefinitions = try nativeScalarActionDefinitions(native,
            program: translation.program, selectedActionOrdinal: live.actionOrdinal)
        let nativeModule = """
        ---- MODULE SwiftTLANativeAssignmentActions ----
        EXTENDS Integers

        \(nativeDefinitions)
        NativeAssignmentFailure == \(live.tla)
        ====

        """
        let bundle = rendered.tlaBundle
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let outputs = [
            ("authored-arithmetic-source.swift", authoredSource),
            ("native-arithmetic-source.swift", nativeSource),
            ("\(bundle.root.name).tla", Data(bundle.root.tla.utf8)),
            ("\(bundle.root.name).cfg", Data(translation.configuration.utf8)),
            ("\(translation.source.name).tla", translation.source.bytes),
            ("SwiftTLANativeAssignmentActions.tla", Data(nativeModule.utf8)),
            ("native-assignment-failure.json", try encoder.encode(live)),
            ("\(translation.output.name).tla", translation.output.bytes),
            ("\(configured.name).tla", configured.bytes),
        ]
        let manifest = ArithmeticAssignmentPreparation(sourceSHA: sourceSHA,
            sourceCompilationIdentity: translation.program.identity.description, authoredSourceSHA256: SHA256.hex(authoredSource),
            nativeSourceSHA256: SHA256.hex(nativeSource),
            files: Dictionary(uniqueKeysWithValues: outputs.map { ($0.0, SHA256.hex($0.1)) }))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in outputs {
            try data.write(to: directory.appendingPathComponent(name), options: .withoutOverwriting)
        }
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("arithmetic-preparation.json"),
                                           options: .withoutOverwriting)
    }

    private static func observe(_ program: CompiledProgram) throws -> ArithmeticAssignmentFailureReceipt {
        let invalid = InitialFailureEvidenceError.unsupportedNativeOutcome
        let machine = try OrderedOverflowModel.makeMachine()
        let before = try machine.formalProjection(of: machine.snapshot)
        var context = CheckingContext(registers: try machine.initialCheckingRegisters())
        context.startRecordingOrderedIntAssignmentFailures()
        var callbacks: [(FormalActionCall, NativeMachineEvaluationError)] = []
        var emittedSuccessor = false
        let found = try machine.visitValidationOutcomes(checking: &context, { _, _ in
            emittedSuccessor = true
            return true
        }, onEvaluationFailure: { action, reason in
            callbacks.append((try machine.formalCall(for: action), reason))
            return true
        })
        guard !found, !emittedSuccessor, callbacks.count == 1, let (call, reason) = callbacks.first,
              let failures = context.orderedIntAssignmentFailures, failures.count == 1, let failure = failures.first,
              failure.reason == reason, case .integerOverflow(.addition, let operands) = reason, operands.count == 2,
              failure.assignmentOrdinal > 0, failure.preceding.count == failure.assignmentOrdinal - 1,
              program.layout.actions.indices.contains(failure.actionOrdinal),
              call.arguments.isEmpty else { throw invalid }
        let action = program.layout.actions[failure.actionOrdinal]
        guard action.id.ordinal == failure.actionOrdinal, !action.isTermination, program.requiresOrderedIntOutput(action.id),
              action.renderedName.utf8.elementsEqual(call.name.utf8),
              before.entries.count == program.layout.variables.count,
              before.entries.allSatisfy({ entry in
                  program.layout.variables.contains(where: {
                      $0.formalName.utf8.elementsEqual(entry.token.description.utf8)
                  })
              }) else { throw invalid }
        return .init(label: action.declaration.name, actionOrdinal: failure.actionOrdinal, site: failure.assignmentOrdinal,
            completed: failure.preceding, kind: "integerOverflow", operation: "addition", operands: operands,
            before: before.entries.map { .init(name: $0.token.description, value: $0.value) })
    }
}
