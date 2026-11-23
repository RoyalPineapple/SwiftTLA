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
        package let output: (name: String, bytes: Data)
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

    /// Composes the selected action certificates for one checked render in compiler action order.
    package static func catalogProof(
        for rendered: RenderedSpecification, translations: [Translation]
    ) throws -> (name: String, bytes: Data) {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        let ordered = translations.sorted { $0.actionOrdinal < $1.actionOrdinal }
        let root = rendered.tlaBundle.root
        let prefix = "AssignmentCatalog"
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
             history: "history\(index + 1)", physical: catalog.invocations[index].renderedName)
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
            <1>row\#(row.slot).
                /\ (\#(row.physical) <=> \#(row.instance)!RHSOutputHistoryAdvance(\#(row.history)))
                /\ \#(row.instance)!RHSOutputActualFailures = \#(row.instance)!RHSOutputHistoryFailures(\#(row.history))
                BY ONLY <1>pick\#(row.slot) DEF \#(row.instance)!RHSOutputHistoryObservation
            """#
        }.joined(separator: "\n")
        let picks = modules.map { "<1>pick\($0.slot)" }.joined(separator: ", ")
        let rows = modules.map { "<1>row\($0.slot)" }.joined(separator: ", ")
        let slots = (1...terminalSlot).map { slot in
            #"/\ (\#(prefix)ActualActionValues[\#(slot)] <=> \#(prefix)CertifiedActions(histories)[\#(slot)])"#
        }.joined(separator: "\n    ")
        let name = "SwiftTLAOrderedAssignmentCatalog" + root.name
        let actionCatalog = catalog.proofSource(prefix: prefix)
        let proof = #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(root.name), TLAPS

        \#(actionCatalog.dispatch)
        \#(actionCatalog.body)

        \#(instances)

        \#(prefix)InputType ==
            \#(types)

        \#(prefix)Terminal ==
            /\ \#(counter.formalName) = \#(last.instance)!RHSOutputExit
            /\ \#(prefix)ActualFrameAfter = \#(prefix)ActualFrameBefore

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
                /\ \#(prefix)ActualFailures = \#(prefix)CertifiedFailures(histories)
                /\ (\#(terminal.renderedName) <=> \#(prefix)Terminal)
                /\ (Next <=> \#(prefix)CertifiedNext(histories))
                /\ ([Next]_vars <=> (\#(prefix)CertifiedNext(histories)
                     \/ \#(prefix)ActualFrameAfter = \#(prefix)ActualFrameBefore))
        PROOF
        \#(historyProofs)
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
        <1>union. (\E slot \in DOMAIN \#(prefix)ActualActionValues : \#(prefix)ActualActionValues[slot])
            <=> \#(prefix)CertifiedNext(histories)
            BY ONLY <1>domains, <1>points, SMT DEF \#(prefix)CertifiedNext
        <1>next. Next <=> \#(prefix)CertifiedNext(histories)
            BY ONLY \#(prefix)ActualNextUsesTheCompleteLabeledActionCatalog, <1>union, PTL
        <1>stuttering. [Next]_vars <=> (\#(prefix)CertifiedNext(histories)
            \/ \#(prefix)ActualFrameAfter = \#(prefix)ActualFrameBefore)
            BY ONLY \#(prefix)ActualNextUsesTheCompleteLabeledActionCatalog, <1>union, PTL
        <1>. WITNESS histories
        <1>. QED BY ONLY <1>histories, <1>failures, <1>terminal, <1>next, <1>stuttering, PTL

        ====

        """#
        return (name, Data(proof.utf8))
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
