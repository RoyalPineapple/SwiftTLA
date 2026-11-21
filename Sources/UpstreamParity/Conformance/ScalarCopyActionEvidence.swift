import Foundation
import SwiftTLA

// The validator accepts any generated model through its ordinary compile and render outputs.
package enum ScalarCopyActionEvidence {
    package struct Proof: Sendable {
        package let prefix: String
        package let sourceName: String
        package let source: Data
        package let parentName: String
        package let parent: Data
    }

    package static func proof(
        source: TLASpec, compilation: CompiledSpecification, rendered: RenderedSpecification,
        authoredSource: Data, modelName: String
    ) throws -> Proof? {
        let layout = compilation.layout
        let output = rendered.tlaBundle
        guard source.sourceAlgorithms.count == 1, let model = source.sourceAlgorithms.first?.model,
              let frontend = model.directScalarCopyInput,
              layout.parameters.isEmpty, layout.checkingRegisters.isEmpty,
              output.imports.isEmpty, case .compiled(let id, _, _) = output.provenance,
              id == compilation.identity else { return nil }
        let checked = try compilation.render()
        guard checked.actions == rendered.actions,
              checked.tlaBundle.root.name == output.root.name,
              checked.tlaBundle.root.tla.utf8.elementsEqual(output.root.tla.utf8),
              let cfg = output.root.cfg, let checkedCFG = checked.tlaBundle.root.cfg,
              checkedCFG.utf8.elementsEqual(cfg.utf8) else { return nil }

        let variables = layout.variables.filter { $0.declaration.origin == .source }
        let counters = layout.variables.filter { $0.declaration.origin == .programCounter }
        let fields = Set(variables.map { $0.declaration.name })
        guard counters.count == 1, let counter = counters.first?.formalName,
              layout.variables.count == variables.count + 1, !variables.isEmpty,
              fields.count == variables.count, Set(variables.map(\.formalName)).count == variables.count else { return nil }
        let actualRows = frontend.rows.map { copyRow(label: $0.label, copies: $0.copies, fields: frontend.fields) }
        let labels = actualRows.map(\.label)
        let actions = layout.actions.filter { !$0.isTermination }
        let terminalActions = layout.actions.filter(\.isTermination)
        guard fields == frontend.fields, !labels.isEmpty, Set(labels).count == labels.count,
              actions.map({ $0.declaration.name }) == labels, terminalActions.count == 1,
              let terminating = terminalActions.first,
              terminating.declaration.name == CompilerControlSymbol.terminatingAction.rawValue,
              Set(compilation.scalarCopyRoutes.keys) == Set(labels),
              rendered.actions.map(\.renderedName) == layout.actions.map(\.renderedName),
              rendered.actions.allSatisfy({ $0.arguments.isEmpty }) else { return nil }

        func control(_ owner: ControlOwner, _ label: String) throws -> String? {
            let matches = layout.controlLocations.filter { $0.owner == owner && $0.sourceName == label }
            guard matches.count == 1, let location = matches.first else { return nil }
            return try CompiledValue.controlLocation(location.id).rendered(using: layout).description
        }
        let done = CompilerControlSymbol.done.rawValue
        let entryControls = try labels.compactMap { try control(.sequential(algorithm: model.name), $0) }
        guard labels.count == entryControls.count,
              let terminal = try control(.generated(algorithm: model.name, purpose: done), done),
              Set(entryControls + [terminal]).count == labels.count + 1 else { return nil }

        // Use a fresh prefix for generated operators and their temporary binders in the imported module's namespace.
        var prefix = "SwiftTLACopy"
        while output.root.tla.contains(prefix) || output.root.name.contains(prefix) { prefix += "_" }
        let before = prefix + "Before"
        let after = prefix + "After"
        let index = prefix + "Index"
        let key = prefix + "Key"
        let label = prefix + "Label"
        let rules = prefix + "Rules"
        let authoredModule = prefix + "Authored"
        let authoredInstance = prefix + "Source"
        let proofModule = prefix + "ActionProof"
        guard let inputText = String(data: authoredSource, encoding: .utf8), !inputText.utf8.contains(0),
              let selection = try? AuthoredCopySyntax.select(source: inputText, modelName: modelName),
              let independentProof = try? AuthoredCopySyntax.proofInputs(selection) else { return nil }
        let authoredProof = """
        ---- MODULE \(authoredModule) ----
        EXTENDS Naturals, Sequences, TLAPS

        WitnessCopyFields == \(TLAValue.set(Set(fields.map(TLAValue.string))))
        WitnessCopyActionRows == \(TLAValue.tuple(actualRows.map(\.value)))
        \(independentProof)
        ====

        """
        let rows = try actualRows.enumerated().map { offset, row in
            let number = offset + 1
            guard let receipt = compilation.scalarCopyRoutes[row.label],
                  receipt.reads.count == row.copyCount,
                  Set(receipt.writes.keys) == fields else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
            let entry = entryControls[offset]
            let next = number < labels.count ? entryControls[number] : terminal
            return try copyProofRow(number, count: row.copyCount, receipt: receipt,
                action: actions[offset].renderedName, entry: entry, next: next, counter: counter,
                prefix: prefix)
        }
        let stateNames = variables.map { ($0.declaration.name, $0.formalName) }
        let entries = "<<\(entryControls.joined(separator: ", "))>>"
        let nextControls = "<<\((Array(entryControls.dropFirst()) + [terminal]).joined(separator: ", "))>>"
        let selected = zip(labels, actions).map { item in
            "(\(label) = \(TLAValue.string(item.0)) /\\ \(item.1.renderedName))"
        } + ["(\(label) = \(TLAValue.string(terminating.declaration.name)) /\\ \(terminating.renderedName))"]
        let branch = prefix + "SourceBranch"
        let sourceLabeled = prefix + "SourceLabeled"
        let emittedLabeled = prefix + "EmittedLabeled"
        let terminatingRule = prefix + "SourceTermination"
        let labelsAt = prefix + "Labels"
        let entryAt = prefix + "Entries"
        let nextAt = prefix + "Destinations"
        let proof = #"""
        ---- MODULE \#(proofModule) ----
        EXTENDS \#(output.root.name), TLAPS

        \#(rules) == INSTANCE ScalarCopyOutputBinding
        \#(authoredInstance) == INSTANCE \#(authoredModule)

        \#(before) == [\#(key) \in \#(authoredInstance)!WitnessCopyFields |->
            \#(cases(stateNames, key: key))]
        \#(after) == [\#(key) \in \#(authoredInstance)!WitnessCopyFields |->
            \#(cases(stateNames.map { ($0.0, $0.1 + "'") }, key: key))]
        \#(entryAt) == \#(entries)
        \#(nextAt) == \#(nextControls)
        \#(labelsAt) == \#(TLAValue.tuple(labels.map(TLAValue.string)))
        \#(prefix)Keys == \#(authoredInstance)!AuthoredCopyFields
        \#(prefix)Rows == \#(authoredInstance)!AuthoredCopyActionRows
        \#(prefix)FormalNames == [\#(key) \in \#(prefix)Keys |->
            \#(cases(stateNames.map { ($0.0, TLAValue.string($0.1).description) }, key: key))]
        \#(prefix)ControlKey == \#(TLAValue.string(counter))
        \#(prefix)ControlBefore == \#(counter)
        \#(prefix)ControlAfter == \#(counter)'
        \#(prefix)TerminalControl == \#(terminal)
        \#(prefix)TerminalLabel == \#(TLAValue.string(terminating.declaration.name))

        \#(branch)(\#(index)) ==
            /\ \#(counter) = \#(entryAt)[\#(index)]
            /\ \#(counter)' = \#(nextAt)[\#(index)]
            /\ \#(rules)!SourceCopyBranch(\#(authoredInstance)!AuthoredCopyFields,
                \#(authoredInstance)!AuthoredCopyActionRows[\#(index)].copies, \#(before), \#(after))
        \#(terminatingRule) ==
            /\ \#(counter) = \#(terminal)
            /\ UNCHANGED \#(counter)
            /\ \#(before) = \#(after)

        \#(rows.joined(separator: "\n"))

        \#(sourceLabeled)(\#(label)) ==
            \/ \E \#(index) \in DOMAIN \#(authoredInstance)!AuthoredCopyActionRows :
                \#(authoredInstance)!AuthoredCopyActionRows[\#(index)].label = \#(label) /\ \#(branch)(\#(index))
            \/ \#(label) = \#(TLAValue.string(terminating.declaration.name)) /\ \#(terminatingRule)
        \#(emittedLabeled)(\#(label)) == \#(selected.joined(separator: " \\/ "))

        THEOREM \#(prefix)ActualLayoutKeys ==
            /\ \#(prefix)Keys = \#(TLAValue.set(Set(fields.map(TLAValue.string))))
            /\ \#(before) = [\#(key) \in \#(prefix)Keys |-> \#(before)[\#(key)]]
            /\ \#(after) = [\#(key) \in \#(prefix)Keys |-> \#(after)[\#(key)]]
            BY \#(authoredInstance)!AuthoredCopySyntaxBindsWitnessRows, SMT
                DEF \#(prefix)Keys, \#(before), \#(after), \#(authoredInstance)!WitnessCopyFields

        THEOREM \#(prefix)ActualTerminationRetainsTheCompleteFrame ==
            \#(terminating.renderedName) <=> \#(terminatingRule)
            BY SMT DEF \#(terminating.renderedName), \#(terminatingRule), \#(before), \#(after),
                \#(authoredInstance)!WitnessCopyFields

        THEOREM \#(prefix)ActualSourceLabelOrder ==
            /\ DOMAIN \#(prefix)Rows = DOMAIN \#(labelsAt)
            /\ \A \#(index) \in DOMAIN \#(labelsAt) :
                \#(prefix)Rows[\#(index)].label = \#(labelsAt)[\#(index)]
            BY \#(authoredInstance)!AuthoredCopySyntaxBindsWitnessRows, SMT
                DEF \#(prefix)Rows, \#(authoredInstance)!WitnessCopyActionRows, \#(labelsAt)

        THEOREM \#(prefix)ActualLabeledActionsAndNext ==
            /\ \A \#(label) : \#(emittedLabeled)(\#(label)) <=> \#(sourceLabeled)(\#(label))
            /\ (Next <=> (\E \#(label) : \#(sourceLabeled)(\#(label))))
        PROOF
        <1>selected. \A \#(label) : \#(emittedLabeled)(\#(label)) <=> \#(sourceLabeled)(\#(label))
            BY \#(prefix)ActualSourceLabelOrder, \#(prefix)ActualTerminationRetainsTheCompleteFrame,
                \#(labels.indices.map { prefix + "Row" + String($0 + 1) }.joined(separator: ", ")), SMT
                DEF \#(emittedLabeled), \#(sourceLabeled), \#(prefix)Rows, \#(labelsAt)
        <1>next. Next <=> (\E \#(label) : \#(emittedLabeled)(\#(label)))
            BY SMT DEF Next, \#(emittedLabeled)
        <1>. QED BY <1>selected, <1>next, SMT

        ====

        """#
        return .init(prefix: prefix, sourceName: authoredModule, source: Data(authoredProof.utf8),
                     parentName: proofModule, parent: Data(proof.utf8))
    }

    private static func copyProofRow(
        _ number: Int, count: Int,
        receipt: StraightLineAssignmentCheck.ScalarCopyReceipt, action: String,
        entry: String, next: String, counter: String, prefix: String
    ) throws -> String {
        let before = prefix + "Before"
        let after = prefix + "After"
        let source = prefix + "Source!"
        let rules = prefix + "Rules!"
        let key = prefix + "Key"
        let choice = prefix + "Choice"
        let reads = prefix + "Reads" + String(number)
        let writes = prefix + "Writes" + String(number)
        let captured = prefix + "Captured" + String(number)
        let compiledBranch = prefix + "CompiledBranch" + String(number)
        let fixedRead = TLAValue.tuple(receipt.reads.map(reference))
        let fixedWrite = cases(receipt.writes.sorted(by: { $0.key < $1.key }).map { ($0.key, reference($0.value).description) },
                               key: key)

        func capture(_ index: Int) -> String { prefix + "Capture" + String(index) }
        func binding(_ read: StraightLineAssignmentCheck.ScalarCopyReceipt.Reference, at index: Int) throws -> String {
            switch read {
            case .state(let field) where receipt.writes[field] != nil:
                return "\(before)[\(TLAValue.string(field))]"
            case .capture(let position) where (1..<index).contains(position):
                return capture(position)
            default: throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
        }
        let history = try receipt.reads.enumerated().map { offset, read in
            "LET \(capture(offset + 1)) == \(try binding(read, at: offset + 1)) IN"
        } + ["<<\((1...count).map(capture).joined(separator: ", "))>>"]

        return #"""
        \#(reads) == \#(fixedRead)
        \#(writes) == [\#(key) \in \#(source)WitnessCopyFields |-> \#(fixedWrite)]
        LOCAL \#(captured) ==
            \#(history.joined(separator: "\n    "))

        \#(compiledBranch) ==
            /\ \#(prefix)ControlBefore = \#(prefix)Entries[\#(number)]
            /\ \#(prefix)ControlAfter = \#(prefix)Destinations[\#(number)]
            /\ \#(rules)CompiledCopyBranch(\#(prefix)Keys, \#(before), \#(reads), \#(writes), \#(after))

        THEOREM \#(prefix)Row\#(number) ==
            /\ (\#(action) <=> \#(prefix)SourceBranch(\#(number)))
            /\ (\#(compiledBranch) <=> \#(prefix)SourceBranch(\#(number)))
        PROOF
        <1>. DEFINE fields == \#(source)WitnessCopyFields
                    copies == \#(source)WitnessCopyActionRows[\#(number)].copies
                    raw == \#(source)AuthoredCopySteps[\#(number)].copies
                    origins == \#(source)AuthoredCopyOrigins
                    routes == \#(rules)DirectCopyRoutes(fields, copies)
                    result(\#(choice)) == \#(rules)CopyMaterializedState(fields, \#(before), \#(choice), \#(writes))
        <1>shape. /\ Len(copies) \in Nat
                   /\ DOMAIN copies = 1..Len(copies)
                   /\ \A position \in DOMAIN copies :
                        copies[position].target \in fields /\ copies[position].read \in fields
            BY SMT DEF fields, copies, \#(source)WitnessCopyActionRows, \#(source)WitnessCopyFields
        <1>checked. \#(rules)ReceiptNamesLastWriters(fields, copies, \#(reads), \#(writes))
            BY SMT DEF \#(rules)ReceiptNamesLastWriters, \#(rules)CopyReceiptNamesWriter, \#(rules)CopyReceiptOrdinal,
                \#(rules)LastDirectCopy, \#(rules)DirectCopyReference, fields, copies,
                \#(source)WitnessCopyActionRows, \#(source)WitnessCopyFields, \#(reads), \#(writes)
        <1>receipt. /\ \#(reads) = \#(rules)DirectCopyScheduledReceipt(fields, copies).reads
                     /\ \#(writes) = \#(rules)DirectCopyScheduledReceipt(fields, copies).writes
            BY <1>shape, <1>checked, \#(rules)CheckedReceiptIsTheScheduledReceipt, SMT
        <1>frontend.
            /\ \#(rules)DirectCopyTypedSyntax(fields, origins, raw)
            /\ copies = \#(rules)DirectCopyResolvedSyntax(origins, raw)
            BY ONLY \#(source)AuthoredCopySyntaxSuppliesTypedSchedulerInput,
                \#(source)AuthoredCopySyntaxBindsWitnessRows, SMT
                DEF fields, copies, raw, origins, \#(source)AuthoredCopySteps,
                    \#(rules)DirectCopyTypedSyntax, \#(rules)DirectCopyResolvedSyntax
        <1>plan. \#(rules)CopyPlan(fields, copies, \#(reads), \#(writes), routes)
            BY ONLY <1>frontend, <1>receipt, \#(rules)DirectCopyTypedFrontendConstructsTheCompleteCapturePlan, SMT
                DEF routes
        <1>earlier.
            /\ Len(\#(reads)) \in Nat
            /\ DOMAIN \#(reads) = 1..Len(\#(reads))
            /\ \A position \in DOMAIN \#(reads) :
                 \#(reads)[position][1] = "capture" => \#(reads)[position][2] \in 1..(position - 1)
            BY SMT DEF \#(reads)
        <1>known. \#(rules)CopyCaptureHistory(\#(before), \#(reads), \#(captured))
            BY SMT DEF \#(reads), \#(captured), \#(rules)CopyCaptureHistory, \#(rules)CopyReferenceValue
        <1>writeReferences. \A key \in fields :
            \#(writes)[key][1] = "capture" => \#(writes)[key][2] \in DOMAIN \#(reads)
            BY SMT DEF \#(writes), \#(reads), fields, \#(source)WitnessCopyFields
        <1>materialized. \A \#(choice) :
            \#(rules)CopyCaptureHistory(\#(before), \#(reads), \#(choice)) =>
                result(\#(choice)) = result(\#(captured))
            PROOF
            <2>. SUFFICES ASSUME NEW \#(choice), \#(rules)CopyCaptureHistory(\#(before), \#(reads), \#(choice))
                         PROVE result(\#(choice)) = result(\#(captured))
                OBVIOUS
            <2>same. \A position \in DOMAIN \#(reads) : \#(choice)[position] = \#(captured)[position]
                BY <1>earlier, <1>known, \#(rules)CopyCaptureHistoryIsUnique, SMT
            <2>. QED BY <2>same, <1>writeReferences, SMT
                DEF result, \#(rules)CopyMaterializedState, \#(rules)CopyReferenceValue
        <1>physical. \#(action) <=>
            (/\ \#(counter) = \#(entry)
             /\ \#(counter)' = \#(next)
             /\ \#(after) = result(\#(captured)))
            BY SMT DEF \#(action), \#(before), \#(after), result, \#(captured), \#(writes), fields,
                \#(source)WitnessCopyFields, \#(rules)CopyMaterializedState, \#(rules)CopyReferenceValue
        <1>compiled. \#(rules)CompiledCopyBranch(fields, \#(before), \#(reads), \#(writes), \#(after)) <=>
                         \#(after) = result(\#(captured))
            BY <1>known, <1>materialized, SMT DEF result, \#(rules)CompiledCopyBranch
        <1>authored. \#(rules)CompiledCopyBranch(fields, \#(before), \#(reads), \#(writes), \#(after)) <=>
                     \#(rules)SourceCopyBranch(\#(source)AuthoredCopyFields,
                         \#(source)AuthoredCopyActionRows[\#(number)].copies, \#(before), \#(after))
            BY <1>plan, \#(source)AuthoredCopySyntaxBindsWitnessRows,
                \#(rules)OrderedScalarCopyPlanPreservesTheCompleteBranch, SMT DEF fields, copies
        <1>. QED BY <1>physical, <1>compiled, <1>authored, \#(source)AuthoredCopySyntaxBindsWitnessRows, SMT
            DEF \#(prefix)SourceBranch, \#(prefix)Entries, \#(prefix)Destinations, \#(compiledBranch),
                \#(prefix)Keys, \#(prefix)ControlBefore, \#(prefix)ControlAfter, fields

        """#
    }

    private static func reference(_ value: StraightLineAssignmentCheck.ScalarCopyReceipt.Reference) -> TLAValue {
        switch value {
        case .state(let field): .tuple([.string("state"), .string(field)])
        case .capture(let index): .tuple([.string("capture"), .int(index)])
        }
    }

    struct CopyRow {
        let label: String
        let copyCount: Int
        let value: TLAValue
    }

    static func copyRows(_ components: [_OrderedIntSourceComponent]) -> (fields: Set<String>, rows: [CopyRow])? {
        let declarations = components.prefix {
            if case .variable = $0 { return true }
            return false
        }
        let fields = Set(declarations.compactMap { component -> String? in
            guard case .variable(let root, _) = component else { return nil }
            return root
        })
        guard fields.count == declarations.count else { return nil }
        var rows: [CopyRow] = []
        for component in components.dropFirst(declarations.count) {
            guard case .step(let label, let assignments) = component, !assignments.isEmpty else { return nil }
            var copies: [(target: String, read: String)] = []
            for assignment in assignments {
                guard case .variable(let read) = assignment.value,
                      fields.contains(read), fields.contains(assignment.root) else { return nil }
                copies.append((assignment.root, read))
            }
            rows.append(copyRow(label: label, copies: copies, fields: fields))
        }
        return (fields, rows)
    }

    private static func copyRow(label: String, copies: [(target: String, read: String)], fields: Set<String>) -> CopyRow {
        let values = copies.map { copy in
            TLAValue.record(["target": .string(copy.target), "read": .string(copy.read)])
        }
        let frame = fields.subtracting(copies.map(\.target))
        return .init(label: label, copyCount: copies.count, value: .record([
            "label": .string(label), "copies": .tuple(values), "frame": .set(Set(frame.map(TLAValue.string)))
        ]))
    }

    private static func cases(_ values: [(String, String)], key: String) -> String {
        guard let fallback = values.last else { return "FALSE" }
        guard values.count > 1 else { return fallback.1 }
        let arms = values.dropLast().map { key + " = " + TLAValue.string($0.0).description + " -> " + $0.1 }
        return "CASE " + arms.joined(separator: " [] ") + " [] OTHER -> " + fallback.1
    }
}
