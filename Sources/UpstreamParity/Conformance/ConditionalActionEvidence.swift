import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA
import SwiftTLACompilerSupport

package enum ConditionalActionEvidence {
    package static func prepare(sourceSHA: String, authoredSource: Data, nativeSource: Data,
        proofSource: Data, to directory: URL) throws {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        guard TLCReferencePin.isRevision(sourceSHA) else { throw InitialFailureEvidenceError.invalidSourceSHA }
        guard !nativeSource.contains(0), let native = String(data: nativeSource, encoding: .utf8),
              let proof = String(data: proofSource, encoding: .utf8),
              let authored = String(data: authoredSource, encoding: .utf8),
              let physical = try AuthoredCopySyntax.conditionalProofInput(
                  source: authored, modelName: String(describing: GeneratedScalarConditionalProofModel.self))?.scalarProof
        else { throw invalid }
        let (compilation, continuations) = try GeneratedScalarConditionalProofModel.spec.compileRetainingAtomicBranchContinuations()
        let inputs = try CompiledTypeInputs(compilation: compilation,
            types: CompiledTypeContext(enums: .init(), formalNames: [:])) {
            switch $0 {
            case "Int", "Swift.Int": .int
            case "Bool", "Swift.Bool": .bool
            default: throw invalid
            }
        }
        let program = try CompiledProgram(inputs: inputs)
        let rendered = try GeneratedScalarConditionalProofModel.render().tlaBundle
        guard case .compiled(let identity, _, _) = rendered.provenance,
              identity == program.identity, rendered.imports.isEmpty,
              rendered.root.tla.utf8.elementsEqual(try program.renderModule().renderedModuleSource.utf8),
              program.behavior.actions.count == 1, let action = program.behavior.actions.first,
              case .ifElse(let predicate, _, _) = action.body,
              predicate.resultType == .bool, predicate.operation == .lessThan,
              predicate.children.count == 2,
              let label = program.layout.actions.first(where: { $0.id == action.id })?.declaration.name,
              let continuation = continuations[label], continuation.prefix.isEmpty,
              let condition = continuation.condition,
              let actualTLA = OrderedRHSPhysicalAction.decodeConditional(in: rendered.root.tla,
                  action: action, program: program),
              let tlaTrue = actualTLA.ifTrue.scalarPlan(), let tlaFalse = actualTLA.ifFalse.scalarPlan()
        else { throw invalid }
        let renderedConditional = TLAValue.record([
            "fields": .set(Set(program.layout.variables.map { .string($0.declaration.name) })),
            "condition": actualTLA.condition,
            "plans": .tuple([tlaTrue, tlaFalse])
        ])

        func plan(_ branch: StraightLineAssignmentCheck.AtomicBranchContinuationReceipt.Branch) throws -> TLAValue {
            let captures = branch.captures.compactMap { $0.count == 1 ? $0.first : nil }
            guard captures.count == branch.captures.count else { throw invalid }
            let writes = branch.writes.map { TLAValue.tuple([.string($0.root), $0.reference]) }
            return .record(["captures": .tuple(captures), "guards": .tuple([]), "writes": .tuple(writes)])
        }
        let scheduled = TLAValue.record([
            "fields": .set(Set(continuation.fields.map(TLAValue.string))),
            "condition": .tuple(condition),
            "plans": .tuple(try [plan(continuation.first), plan(continuation.second)])
        ])

        func read(_ expression: CompiledExpression) throws -> String {
            guard expression.resultType == .int, expression.children.isEmpty,
                  case .stateVariable(let id) = expression.operation,
                  let field = program.layout.variables.first(where: { $0.id == id && $0.declaration.origin == .source }) else {
                throw invalid
            }
            return try nativeSourceIdentifier(field.declaration.name)
        }
        let left = try read(predicate.children[0]), right = try read(predicate.children[1])
        let conditionWords = Parser.parse(source: "(state.state.\(left) < state.state.\(right))")
            .tokens(viewMode: .sourceAccurate).filter { $0.tokenKind != .endOfFile }.map(\.text)

        let actual = try nativeConditionalActionPlans(native, program: program, predicate: conditionWords)
        let nativeOperands = TLAValue.tuple(try [actual.ifTrue.operands(), actual.ifFalse.operands()])
        let renderedOperands = TLAValue.tuple(try [actualTLA.ifTrue, actualTLA.ifFalse].map { arm in
            let captures = arm.action.captures
            let sites = captures.enumerated().compactMap { $0.element.additionNodes.isEmpty ? nil : $0.offset + 1 }
            return try conditionalArmOperands(captures.map(\.plan), writeOrder: arm.writeOrder,
                writes: arm.action.writes, failureAppendSites: sites)
        })
        let header = "MODULE GeneratedScalarConditionalProof"
        let input = "CONSTANT NativeChooseChildren, NativeChoosePlans, NativeChooseFields"
        guard proof.components(separatedBy: header).count == 2,
              proof.components(separatedBy: input).count == 2,
              let footer = proof.split(separator: "\n").last, footer.allSatisfy({ $0 == "=" }),
              let terminal = proof.range(of: String(footer), options: .backwards) else { throw invalid }
        let concrete = String(proof[..<terminal.lowerBound])
            .replacingOccurrences(of: header, with: "MODULE GeneratedScalarConditionalNative")
            .replacingOccurrences(of: input, with: """
                NativeChooseChildren == \(actual.children)
                NativeChoosePlans == \(actual.plans)
                NativeChooseFields == \(actual.fields)
                """)
            + """

        PhysicalConditional == \(physical)
        ScheduledConditional == \(scheduled)
        RenderedConditional == \(renderedConditional)
        NativeScopedConditionalOperands == \(nativeOperands)
        RenderedScopedConditionalOperands == \(renderedOperands)
        PhysicalOperand(term) == CopyReferenceValue(NativeChooseBefore, <<>>, term)
        PhysicalGuard ==
            LET term == PhysicalConditional.predicate IN
            CASE term[1] = "lessThan" -> PhysicalOperand(term[2]) < PhysicalOperand(term[3])
              [] term[1] = "equal" -> PhysicalOperand(term[2]) = PhysicalOperand(term[3])
              [] OTHER -> FALSE
        PhysicalArm(update) ==
            /\\ NativeChooseAfter[update[1]] = PhysicalOperand(update[2])
            /\\ \\A field \\in PhysicalConditional.fields \\ {update[1]} :
                   NativeChooseAfter[field] = NativeChooseBefore[field]
        PhysicalSourceLabeledStep(label) ==
            /\\ label = PhysicalConditional.label
            /\\ SourceConditionalStep(TRUE, PhysicalGuard,
                    PhysicalArm(PhysicalConditional.ifTrue), PhysicalArm(PhysicalConditional.ifFalse))

        THEOREM PhysicalSourceMatchesTheSourceRule ==
            ASSUME ModelStateType, NEW label
            PROVE PhysicalSourceLabeledStep(label) <=> SourceLabeledStep(label)
        PROOF
        <1>predicate. PhysicalGuard = (left < right)
            BY ONLY SMT DEF PhysicalGuard, PhysicalConditional, PhysicalOperand, CopyReferenceValue, NativeChooseBefore
        <1>yes. PhysicalArm(PhysicalConditional.ifTrue) <=> (UNCHANGED <<left, right>> /\\ selected' = TRUE)
            BY ONLY SMT DEF PhysicalArm, PhysicalConditional, PhysicalOperand,
                            CopyReferenceValue, NativeChooseBefore, NativeChooseAfter
        <1>no. PhysicalArm(PhysicalConditional.ifFalse) <=> (UNCHANGED <<left, right>> /\\ selected' = FALSE)
            BY ONLY SMT DEF PhysicalArm, PhysicalConditional, PhysicalOperand,
                            CopyReferenceValue, NativeChooseBefore, NativeChooseAfter
        <1>label. PhysicalConditional.label = "choose"
            BY ONLY SMT DEF PhysicalConditional
        <1>. QED BY <1>predicate, <1>yes, <1>no, <1>label, SMT
                    DEF PhysicalSourceLabeledStep, SourceLabeledStep, SourceChoose, SourceConditionalStep, ModelStateType

        THEOREM ActualConditionalPreservesCompleteLabeledStep ==
            ASSUME ModelStateType, NEW label
            PROVE /\\ (RenderedLabeledStep(label) <=> PhysicalSourceLabeledStep(label))
                  /\\ (NativeChooseLabeledStep(label) <=> PhysicalSourceLabeledStep(label))
                  /\\ RenderedConditional = ScheduledConditional
                  /\\ NativeScopedConditionalOperands = RenderedScopedConditionalOperands
            PROOF
            <1>operands. NativeScopedConditionalOperands = RenderedScopedConditionalOperands
                BY ONLY SMT DEF NativeScopedConditionalOperands, RenderedScopedConditionalOperands
            <1>rendered. RenderedConditional = ScheduledConditional
                BY ONLY SMT DEF RenderedConditional, ScheduledConditional
            <1>scheduler.
                /\\ ScheduledConditional.fields = PhysicalConditional.fields
                /\\ ScheduledConditional.condition =
                    <<<<PhysicalConditional.predicate[1]>>,
                      PhysicalConditional.predicate[2], PhysicalConditional.predicate[3]>>
                /\\ ExpectedNativeChoosePlan(ScheduledConditional.plans[1], TRUE)
                /\\ ExpectedNativeChoosePlan(ScheduledConditional.plans[2], FALSE)
                BY ONLY SMT DEF ScheduledConditional, PhysicalConditional, ExpectedNativeChoosePlan
            <1>physical.
                /\\ NativeChooseFields = ScheduledConditional.fields
                /\\ NativeChoosePlans[NativeChooseChildren[1]] = ScheduledConditional.plans[1]
                /\\ NativeChoosePlans[NativeChooseChildren[2]] = ScheduledConditional.plans[2]
                BY ONLY SMT DEF NativeChooseFields, NativeChoosePlans, NativeChooseChildren, ScheduledConditional
            <1>fields. NativeChooseFields = {"left", "right", "selected"}
                BY ONLY <1>scheduler, <1>physical, SMT DEF PhysicalConditional
            <1>arms. /\\ ExpectedNativeChoosePlan(NativeChoosePlans[NativeChooseChildren[1]], TRUE)
                      /\\ ExpectedNativeChoosePlan(NativeChoosePlans[NativeChooseChildren[2]], FALSE)
                BY ONLY <1>scheduler, <1>physical, SMT
            <1>backends. /\\ (RenderedLabeledStep(label) <=> SourceLabeledStep(label))
                         /\\ (NativeChooseLabeledStep(label) <=> SourceLabeledStep(label))
                BY <1>fields, <1>arms, ConditionalPreservesCompleteLabeledStep, SMT
            <1>. QED BY <1>operands, <1>rendered, <1>backends, PhysicalSourceMatchesTheSourceRule, SMT

        ====

        """
        let model = Data(rendered.root.tla.utf8)
        let generatedProof = Data(concrete.utf8)
        let receipt = [
            "sourceSHA": sourceSHA,
            "sourceCompilationIdentity": identity.description,
            "authoredSourceSHA256": SHA256.hex(authoredSource),
            "nativeSourceSHA256": SHA256.hex(nativeSource),
            "proofTemplateSHA256": SHA256.hex(proofSource),
            "modelSHA256": SHA256.hex(model),
            "proofSHA256": SHA256.hex(generatedProof)
        ]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in [
            ("authored-conditional-source.swift", authoredSource), ("native-conditional-source.swift", nativeSource),
            ("GeneratedScalarConditionalProofModel.tla", model), ("GeneratedScalarConditionalNative.tla", generatedProof),
            ("conditional-preparation.json", try JSONEncoder().encode(receipt))
        ] {
            try data.write(to: directory.appendingPathComponent(name), options: .withoutOverwriting)
        }
    }

    /// Bind one checked addition per arm, after a total literal prefix.
    /// The original rendered module stays an import of the returned proof.
    static func arithmeticHistoryProof(authoredSource: String, modelName: String,
                                       program: CompiledProgram, rendered: RenderedModule,
                                       nativeSource: String, operations: String, checking: String)
        throws -> (name: String, bytes: Data, configuration: String, configured: (name: String, bytes: Data)) {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        guard modelName.utf8.elementsEqual(program.moduleName.utf8),
              modelName.utf8.elementsEqual(rendered.moduleName.utf8), rendered.imports.isEmpty,
              program.behavior.actions.count == 1, let action = program.behavior.actions.first,
              program.layout.actions.count == 1, let actionLayout = program.layout.actions.first,
              actionLayout.id == action.id,
              let source = try AuthoredCopySyntax.conditionalProofInput(source: authoredSource, modelName: modelName),
              source.label == .string(actionLayout.declaration.name),
              let physical = OrderedRHSPhysicalAction.decodeConditional(in: rendered.renderedModuleSource,
                  action: action, program: program), source.arms.count == 2,
              case .tuple(let predicate) = source.predicate, predicate.count == 3,
              predicate[0] == .string("lessThan"),
              physical.condition == .tuple([.tuple([predicate[0]]), predicate[1], predicate[2]])
        else { throw invalid }

        let fields = program.layout.variables
        let integers = fields.filter { program.variableTypes[$0.id] == .int }
        let booleans = fields.filter { program.variableTypes[$0.id] == .bool }
        guard Set(fields.map { $0.declaration.name }).count == fields.count else { throw invalid }
        let names = Dictionary(uniqueKeysWithValues: fields.map { ($0.declaration.name, $0) })
        let keys = Set(integers.map { TLAValue.string($0.declaration.name) })
        guard fields.allSatisfy({ $0.declaration.origin == .source }),
              integers.count + booleans.count == fields.count, source.fields == Set(names.keys.map(TLAValue.string)),
              let lhs = try sourceRead(predicate[1], fields: names),
              let rhs = try sourceRead(predicate[2], fields: names),
              keys.contains(.string(lhs.declaration.name)), keys.contains(.string(rhs.declaration.name))
        else { throw invalid }
        let swiftLeft = try nativeSourceIdentifier(lhs.declaration.name)
        let swiftRight = try nativeSourceIdentifier(rhs.declaration.name)
        let conditionWords = Parser.parse(source: "(state.state.\(swiftLeft) < state.state.\(swiftRight))")
            .tokens(viewMode: .sourceAccurate).filter { $0.tokenKind != .endOfFile }.map(\.text)
        try verifyConditionalHistoryHelpers(operations: operations, checking: checking)
        let native = try nativeConditionalActionPlans(nativeSource, program: program, predicate: conditionWords)
        let nativeComparison = try conditionalNativeComparison(native.predicate, integers: integers)
        let nativeRows = try [native.ifTrue, native.ifFalse].map(conditionalNativeFailureRow)

        let regions = action.body.orderedAlternativeFailureRegions
        guard regions.count == source.arms.count else { throw invalid }
        let descriptors = try zip(source.arms, regions).enumerated().map { arm, pair -> TLAValue in
            let (writes, region) = pair
            let emitted = arm == 0 ? physical.ifTrue.action : physical.ifFalse.action
            guard writes.count == region.bindings.count, writes.count == emitted.captures.count,
                  arm == region.armOrdinal else { throw invalid }
            let ordered = try zip(writes, region.bindings).map { write, binding in
                guard let field = names[write.target], field.id == binding.target else { throw invalid }
                return (write: write, binding: binding, type: program.variableTypes[field.id])
            }
            guard let addition = ordered.firstIndex(where: { $0.write.terms.first == .tuple([.string("add")]) }),
                  ordered[addition].type == .int, ordered[addition].write.terms.count == 3
            else { throw invalid }
            var latest = Dictionary(uniqueKeysWithValues: fields.map { field in
                (field.declaration.name, TLAValue.tuple([.string("state"), .string(field.declaration.name)]))
            })
            func retainLiteral(at index: Int, in type: CompiledValueType) throws -> TLAValue {
                let item = ordered[index]
                let plan = emitted.captures[index].plan
                guard item.type == type, let literal = conditionalLiteral(item.write.terms),
                      plan.kinds == [.string("literal")], plan.literals == [literal] else { throw invalid }
                latest[item.write.target] = .tuple([.string("capture"), .int(index + 1)])
                return literal
            }
            let prefix = try (0..<addition).map { index -> (row: TLAValue, value: TLAValue) in
                let item = ordered[index]
                let literal = try retainLiteral(at: index, in: .int)
                guard case .int = literal else { throw invalid }
                return (.record(["target": .string(item.write.target), "binding": .int(item.binding.binder.ordinal),
                                 "field": .int(item.binding.target.ordinal)]), literal)
            }

            let failed = ordered[addition]
            let operands = Array(failed.write.terms.dropFirst())
            let plan = emitted.captures[addition].plan
            guard plan.kinds.count == 3, plan.kinds[2] == .string("add"),
                  plan.left[2] == .int(1), plan.right[2] == .int(2),
                  region.index(of: failed.binding.binder) == addition else { throw invalid }
            for (node, term) in operands.enumerated() {
                if let literal = conditionalLiteral([term]), case .int = literal {
                    guard plan.kinds[node] == .string("literal"), plan.literals[node] == literal else { throw invalid }
                } else {
                    guard let read = try sourceRead(term, fields: names),
                          keys.contains(.string(read.declaration.name)), let reference = latest[read.declaration.name],
                          plan.kinds[node] == .string("read"), plan.reads[node] == reference else { throw invalid }
                }
            }
            let routes = TLAValue.function(Dictionary(uniqueKeysWithValues: latest.compactMap { root, reference in
                let key = TLAValue.string(root)
                return keys.contains(key) ? (key, reference) : nil
            }))
            latest[failed.write.target] = .tuple([.string("capture"), .int(addition + 1)])
            let suffix = try ((addition + 1)..<ordered.count).map { index in
                let literal = try retainLiteral(at: index, in: .bool)
                guard case .bool = literal else { throw invalid }
                return literal
            }
            guard latest == emitted.writes else { throw invalid }
            let finalRoutes = TLAValue.function(Dictionary(uniqueKeysWithValues: latest.map {
                (TLAValue.string($0.key), $0.value)
            }))
            let targets = writes.map { TLAValue.record(["target": .string($0.target)]) }

            return .record(["prefix": .tuple(prefix.map(\.row)), "inputs": .tuple(operands),
                            "routes": routes, "values": .tuple(prefix.map(\.value)),
                            "suffix": .tuple(suffix), "finalRoutes": finalRoutes, "targets": .tuple(targets),
                            "site": .int(failed.binding.binder.ordinal), "target": .int(failed.binding.target.ordinal)])
        }

        // Names come from the actual output. Reserved names may have collision suffixes.
        let ordinal = action.id.ordinal
        func name(_ base: String) throws -> String {
            let matches = rendered.renderedModuleSource.split(separator: "\n").compactMap { line -> String? in
                guard let separator = line.range(of: " == ") else { return nil }
                let declaration = line[..<separator.lowerBound]
                guard declaration.hasPrefix(base), declaration.dropFirst(base.count).allSatisfy({ $0 == "_" })
                else { return nil }
                return String(declaration)
            }
            guard matches.count == 1, let match = matches.first else { throw invalid }
            return match
        }
        guard try name("vars") == "vars", try name("Next") == "Next" else { throw invalid }
        let history = try name("__SwiftTLAActionFailureHistory\(ordinal)")
        let operation = try [name("__SwiftTLAOverflowOperation\(ordinal)"),
                             name("__SwiftTLAOverflowOperation\(ordinal)_1")]
        let operands = try [name("__SwiftTLAOverflowOperands\(ordinal)"),
                            name("__SwiftTLAOverflowOperands\(ordinal)_1")]
        let failures = try [name("__SwiftTLAOverflowFailure\(ordinal)"),
                            name("__SwiftTLAOverflowFailure\(ordinal)_1")]
        let siteDeclarations = rendered.evaluationFailureDeclarations.map { $0.prefix { $0 != " " } }
            .filter { $0.hasPrefix("__SwiftTLAOverflowFailure\(ordinal)") }
        let aggregate = try name("__SwiftTLAAnyEvaluationFailure\(ordinal)")
        let configuration = try rendered.configuration.render(usesSymmetryReduction: false)
        guard siteDeclarations.map(String.init) == failures,
              let selection = OrderedRHSCFGProof.normalSelection(cfg: configuration,
                  intrinsicInvariants: Set(rendered.configuration.intrinsicInvariants)),
              try name("__SwiftTLAEvaluationOK") == selection.checking else { throw invalid }

        // A map over actual Int layout names leaves the Boolean suffix out of arithmetic evaluation.
        let proofName = "SwiftTLA" + rendered.moduleName + "ConditionalOverflowHistory"
        func stateCases(_ fields: [CompiledVariableLayout], primed: Bool = false) -> String {
            fields.map { field in
                "key = \(TLAValue.string(field.declaration.name)) -> \(field.formalName)\(primed ? "'" : "")"
            }.joined(separator: " [] ")
        }
        let state = fields.map(\.formalName).joined(separator: ", ")
        let types = integers.map { "\($0.formalName) \\in ConditionalIntValues" }
            + booleans.map { "\($0.formalName) \\in BOOLEAN" }
        let proof = conditionalOverflowProof(name: proofName, model: rendered.moduleName,
            history: history, operation: operation, operands: operands, failures: failures,
            aggregate: aggregate, evaluationCheck: selection.checking, ordinal: ordinal,
            arms: .tuple(descriptors), keys: .set(keys), before: stateCases(integers), state: state,
            typed: types.joined(separator: " /\\ "), predicate: source.predicate,
            actionName: actionLayout.renderedName, stateKeys: .set(source.fields),
            fullBefore: stateCases(fields), after: stateCases(fields, primed: true),
            nativeComparison: nativeComparison, nativeRows: .tuple(nativeRows))
        let configuredName = proofName + "ConfiguredProof"
        let configured = conditionalConfiguredProof(name: configuredName, actionProof: proofName, cfgProof: selection.proof)
        return (proofName, Data(proof.utf8), configuration, (configuredName, Data(configured.utf8)))
    }

    private static func conditionalNativeComparison(_ tokens: [String], integers: [CompiledVariableLayout]) throws
        -> TLAValue {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        let members = try integers.map { field in
            (try nativeSourceIdentifier(field.declaration.name), field.declaration.name)
        }
        guard tokens.count == 13,
              tokens[0..<5].elementsEqual(["(", "state", ".", "state", "."]),
              tokens[6..<11].elementsEqual(["<", "state", ".", "state", "."]), tokens[12] == ")",
              let lhs = members.first(where: { $0.0.utf8.elementsEqual(tokens[5].utf8) })?.1,
              let rhs = members.first(where: { $0.0.utf8.elementsEqual(tokens[11].utf8) })?.1 else { throw invalid }
        return .tuple([.string("lessThan"), .tuple([.string("state"), .string(lhs)]),
                       .tuple([.string("state"), .string(rhs)])])
    }

    private static func conditionalNativeFailureRow(_ arm: NativeConditionalArmOutput) throws -> TLAValue {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        guard arm.failureCalls.count == 1, let call = arm.failureCalls.first,
              arm.failureAppendSites.count == 1, let slot = arm.failureAppendSites.first,
              slot > 0, slot <= arm.capturePlans.count, call.before.count == slot - 1
        else { throw invalid }
        let values = try arm.capturePlans.prefix(slot - 1).map { plan -> TLAValue in
            guard plan.kinds == [.string("literal")], let value = plan.literals.first, case .int = value
            else { throw invalid }
            return value
        }
        let plan = arm.capturePlans[slot - 1]
        guard plan.kinds.count == 3, plan.kinds[2] == .string("add"),
              plan.left[2] == .int(1), plan.right[2] == .int(2) else { throw invalid }
        let operands = try (0..<2).map { node -> TLAValue in
            if plan.kinds[node] == .string("read") { return plan.reads[node] }
            guard plan.kinds[node] == .string("literal"), case .int = plan.literals[node] else { throw invalid }
            return .tuple([.string("literal"), plan.literals[node]])
        }
        let materialization = try arm.materialization(after: slot)
        // The visitor decoder has bound each parsed callback value to this physical local capture.
        let before = call.before.enumerated().map { index, binding in
            TLAValue.record(["binding": .int(binding.binding), "target": .int(binding.target), "slot": .int(index + 1)])
        }
        return .record(["action": .int(call.action), "branch": .int(call.branch), "site": .int(call.site),
                        "target": .int(call.target), "before": .tuple(before), "values": .tuple(values),
                        "inputs": .tuple(operands), "suffix": materialization.suffix, "writes": materialization.writes])
    }

    private static func conditionalLiteral(_ terms: [TLAValue]) -> TLAValue? {
        guard terms.count == 1, case .tuple(let term) = terms[0], term.count == 2,
              term[0] == .string("literal") else { return nil }
        return term[1]
    }

    private static func sourceRead(_ value: TLAValue, fields: [String: CompiledVariableLayout]) throws
        -> CompiledVariableLayout? {
        guard case .tuple(let ref) = value, ref.count == 2,
              ref[0] == .string("state"), case .string(let root) = ref[1] else { return nil }
        guard let declared = fields[root], declared.declaration.name.utf8.elementsEqual(root.utf8) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        return declared
    }

    private static func conditionalOverflowProof(
        name: String, model: String, history: String, operation: [String], operands: [String],
        failures: [String], aggregate: String, evaluationCheck: String, ordinal: Int,
        arms: TLAValue, keys: TLAValue, before: String,
        state: String, typed: String, predicate: TLAValue, actionName: String,
        stateKeys: TLAValue, fullBefore: String, after: String, nativeComparison: TLAValue, nativeRows: TLAValue
    ) -> String {
        let nativeSuccess = conditionalNativeSuccessProof()
        return #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(model), TLAPS, Sequences
        LOCAL INSTANCE SequenceTheorems

        ConditionalIntKeys == \#(keys)
        ConditionalIntValues == \#(TLAValue.int(Int.min))..\#(TLAValue.int(Int.max))
        ConditionalTypedState == \#(typed)
        ConditionalBefore == [key \in ConditionalIntKeys |-> CASE \#(before) [] OTHER -> 0]
        ConditionalEntry == <<\#(state)>>
        ConditionalStateKeys == \#(stateKeys)
        ConditionalStateBefore == [key \in ConditionalStateKeys |-> CASE \#(fullBefore) [] OTHER -> 0]
        ConditionalStateAfter == [key \in ConditionalStateKeys |-> CASE \#(after) [] OTHER -> 0]
        ConditionalSourceRows == \#(arms)
        ConditionalSourceComparison == \#(predicate)
        ConditionalNativeComparison == \#(nativeComparison)
        ConditionalNativeRows == \#(nativeRows)
        ConditionalActionOrdinal == \#(ordinal)
        ConditionalArms == 1..Len(ConditionalSourceRows)
        Arithmetic == INSTANCE PhysicalIntAssignmentRhsRule WITH Keys <- ConditionalIntKeys,
            SwiftIntMin <- \#(TLAValue.int(Int.min)), SwiftIntMax <- \#(TLAValue.int(Int.max))

        ConditionalArmFor(comparison) ==
            LET operand(pair) == Arithmetic!CopyReferenceValue(ConditionalBefore, <<>>, pair)
            IN IF operand(comparison[2]) < operand(comparison[3]) THEN 1 ELSE 2
        ConditionalSelectedArm == ConditionalArmFor(ConditionalSourceComparison)

        ConditionalPrefix(arm) == ConditionalSourceRows[arm].prefix
        ConditionalCompleted(arm) == ConditionalSourceRows[arm].values
        ConditionalWriter(arm, key) == ConditionalSourceRows[arm].routes[key]
        ConditionalLatest(arm) ==
            Arithmetic!CompletedAssignmentBindings(ConditionalBefore, ConditionalPrefix(arm), ConditionalCompleted(arm))
        ConditionalOperands(arm) ==
            LET row == ConditionalSourceRows[arm]
                operand(position) == Arithmetic!CopyReferenceValue(ConditionalLatest(arm), <<>>, row.inputs[position])
            IN <<operand(1), operand(2)>>
        ConditionalSourceAdd(arm) ==
            Arithmetic!SourceAdd(ConditionalOperands(arm)[1], ConditionalOperands(arm)[2])
        ConditionalBeforeFields(arm) ==
            [i \in DOMAIN ConditionalPrefix(arm) |->
                LET write == ConditionalPrefix(arm)[i]
                IN [binding |-> write.binding, target |-> write.field, value |-> ConditionalCompleted(arm)[i]]]
        ConditionalFailureRecord(arm, payload) ==
            LET row == ConditionalSourceRows[arm]
            IN [source |-> ConditionalEntry, action |-> ConditionalActionOrdinal, branch |-> arm - 1,
                site |-> row.site, target |-> row.target, payload |-> payload, before |-> ConditionalBeforeFields(arm)]
        ConditionalSourceHistory ==
            LET arm == ConditionalSelectedArm
                outcome == ConditionalSourceAdd(arm)
            IN IF outcome.ok THEN <<>> ELSE <<ConditionalFailureRecord(arm, outcome.failure)>>

        ConditionalSuccessfulCaptures(arm) ==
            ConditionalCompleted(arm) \o <<ConditionalSourceAdd(arm).value>> \o ConditionalSourceRows[arm].suffix
        ConditionalSuccessfulState(arm) ==
            Arithmetic!CopyMaterializedState(ConditionalStateKeys, ConditionalStateBefore,
                ConditionalSuccessfulCaptures(arm), ConditionalSourceRows[arm].finalRoutes)
        ConditionalSourceStep ==
            /\ ConditionalSourceAdd(ConditionalSelectedArm).ok
            /\ ConditionalStateAfter = ConditionalSuccessfulState(ConditionalSelectedArm)
        ConditionalPhysicalStep == \#(actionName)

        ConditionalNativeSelectedArm == ConditionalArmFor(ConditionalNativeComparison)
        ConditionalNativeOperand(arm, position) ==
            LET row == ConditionalNativeRows[arm]
            IN Arithmetic!CopyReferenceValue(ConditionalBefore, row.values, row.inputs[position])
        ConditionalNativeOperands(arm) == <<ConditionalNativeOperand(arm, 1), ConditionalNativeOperand(arm, 2)>>
        \* The checked helper returns the reported sum or throws with the evaluated operands in order.
        \* The overflow flag of Swift.Int addingReportingOverflow is interpreted on representable inputs.
        ConditionalNativeAdd(arm) ==
            LET left == ConditionalNativeOperands(arm)[1]
                right == ConditionalNativeOperands(arm)[2]
                sum == left + right
            IN IF sum < \#(TLAValue.int(Int.min)) \/ sum > \#(TLAValue.int(Int.max))
                THEN Arithmetic!GeneratedOverflow(left, right) ELSE Arithmetic!Success(sum)
        ConditionalNativeRecord(arm, payload) ==
            LET row == ConditionalNativeRows[arm]
                before == [i \in DOMAIN row.before |->
                    LET capture == row.before[i]
                    IN [binding |-> capture.binding, target |-> capture.target, value |-> row.values[capture.slot]]]
            IN [source |-> ConditionalEntry, action |-> row.action, branch |-> row.branch,
                site |-> row.site, target |-> row.target, payload |-> payload, before |-> before]
        \* A collecting checker visit enables the recorder and associates the event with its entry state.
        ConditionalNativeHistory(recording) ==
            LET arm == ConditionalNativeSelectedArm
                outcome == ConditionalNativeAdd(arm)
            IN IF recording /\ ~outcome.ok
                THEN <<ConditionalNativeRecord(arm, outcome.failure)>> ELSE <<>>

        \#(nativeSuccess.definitions)

        ActualConditionalHistory == \#(history)
        ConditionalSelectedEvaluationCheck == \#(evaluationCheck)
        ConditionalPhysicalFailure(arm) == IF arm = 1 THEN \#(failures[0]) ELSE \#(failures[1])
        ConditionalPhysicalOperands(arm) == IF arm = 1 THEN \#(operands[0]) ELSE \#(operands[1])
        ConditionalPhysicalOperation(arm) == IF arm = 1 THEN \#(operation[0]) ELSE \#(operation[1])
        ConditionalPhysicalRecord(arm) ==
            ConditionalFailureRecord(arm,
                <<"integerOverflow", ConditionalPhysicalOperation(arm), ConditionalPhysicalOperands(arm)>>)
        ConditionalPhysicalEvent(arm) ==
            IF ConditionalPhysicalFailure(arm) THEN <<ConditionalPhysicalRecord(arm)>> ELSE <<>>

        THEOREM ActualConditionalHistoryMatchesTheAuthoredArms ==
            ASSUME ConditionalTypedState
            PROVE /\ ActualConditionalHistory = ConditionalSourceHistory
                  /\ ConditionalNativeHistory(TRUE) = ConditionalSourceHistory
                  /\ (ConditionalSelectedEvaluationCheck <=> ConditionalSourceHistory = <<>>)
                  /\ (ConditionalPhysicalStep <=> ConditionalSourceStep)
                  /\ (ConditionalNativeStep <=> ConditionalSourceStep)
                  /\ (Next <=> ConditionalSourceStep)
                  /\ vars = ConditionalEntry
                  /\ (~ConditionalSourceAdd(ConditionalSelectedArm).ok => ~ENABLED Next)
        PROOF
        <1>shape. /\ ConditionalArms = 1..2
                  /\ \A arm \in ConditionalArms :
                         /\ Len(ConditionalPrefix(arm)) \in Nat
                         /\ Len(ConditionalPrefix(arm)) = Len(ConditionalCompleted(arm))
                         /\ DOMAIN ConditionalPrefix(arm) = DOMAIN ConditionalCompleted(arm)
            BY ONLY SMT DEF ConditionalArms, ConditionalPrefix, ConditionalCompleted, ConditionalSourceRows
        <1>writers. \A arm \in ConditionalArms : \A key \in ConditionalIntKeys :
            Arithmetic!CopyReceiptNamesWriter(ConditionalPrefix(arm), Len(ConditionalPrefix(arm)), key,
                                               ConditionalWriter(arm, key))
            BY ONLY <1>shape, SMT DEF ConditionalIntKeys, ConditionalPrefix, ConditionalWriter, ConditionalSourceRows,
                Arithmetic!CopyReceiptNamesWriter, Arithmetic!CopyReceiptOrdinal,
                Arithmetic!LastDirectCopy, Arithmetic!DirectCopyReference
        <1>routes. \A arm \in ConditionalArms : \A key \in ConditionalIntKeys :
            ConditionalWriter(arm, key) =
                Arithmetic!DirectCopyRoutes(ConditionalIntKeys, ConditionalPrefix(arm))[Len(ConditionalPrefix(arm))][key]
            BY ONLY <1>shape, <1>writers, Arithmetic!NamedReceiptReferenceUsesTheLastWriter, SMT
        <1>values. \A arm \in ConditionalArms :
            /\ ConditionalPhysicalOperands(arm) = ConditionalOperands(arm)
            /\ ConditionalOperands(arm)[1] \in ConditionalIntValues
            /\ ConditionalOperands(arm)[2] \in ConditionalIntValues
            BY ONLY ConditionalTypedState, <1>shape, <1>routes, SMT
                DEF ConditionalTypedState, ConditionalIntKeys, ConditionalIntValues, ConditionalBefore,
                    ConditionalOperands, ConditionalLatest, ConditionalWriter, ConditionalPrefix, ConditionalCompleted,
                    ConditionalPhysicalOperands, ConditionalSourceRows, \#(operands.joined(separator: ", ")),
                    Arithmetic!CompletedAssignmentBindings, Arithmetic!CopyMaterializedState, Arithmetic!CopyReferenceValue
        <1>selector. ConditionalSelectedArm \in ConditionalArms
            BY ONLY <1>shape, SMT DEF ConditionalSelectedArm, ConditionalArmFor
        <1>probes. \A arm \in ConditionalArms :
            /\ ConditionalPhysicalOperation(arm) = "addition"
            /\ (ConditionalPhysicalFailure(arm) <=> arm = ConditionalSelectedArm
                 /\ ~Arithmetic!GeneratedAddDefined(ConditionalPhysicalOperands(arm)[1], ConditionalPhysicalOperands(arm)[2]))
            BY ONLY <1>shape, SMT DEF ConditionalPhysicalOperation, ConditionalPhysicalFailure, ConditionalPhysicalOperands,
                ConditionalSelectedArm, ConditionalArmFor, ConditionalSourceComparison, ConditionalBefore, ConditionalIntKeys,
                \#((failures + operands + operation).joined(separator: ", ")),
                Arithmetic!CopyReferenceValue, Arithmetic!GeneratedAddDefined, Arithmetic!SmallAddOperands
        <1>addition. \A arm \in ConditionalArms :
            ConditionalSourceAdd(arm) =
                Arithmetic!GeneratedAdd(ConditionalPhysicalOperands(arm)[1], ConditionalPhysicalOperands(arm)[2])
            BY ONLY <1>values, Arithmetic!CheckedAdditionRule, SMT DEF ConditionalSourceAdd, ConditionalIntValues,
                Arithmetic!InRange
        <1>evaluationSites. ConditionalSelectedEvaluationCheck <=>
                ~(\E arm \in ConditionalArms : ConditionalPhysicalFailure(arm))
            BY ONLY <1>shape, SMT DEF ConditionalSelectedEvaluationCheck, \#(evaluationCheck), \#(aggregate),
                ConditionalPhysicalFailure, \#(failures.joined(separator: ", "))
        <1>evaluationOutcome. ConditionalSelectedEvaluationCheck <=> ConditionalSourceAdd(ConditionalSelectedArm).ok
            BY ONLY <1>evaluationSites, <1>selector, <1>probes, <1>addition, SMT
                DEF Arithmetic!GeneratedAdd, Arithmetic!Success, Arithmetic!GeneratedOverflow
        <1>evaluation. ConditionalSelectedEvaluationCheck <=> ConditionalSourceHistory = <<>>
            BY ONLY <1>evaluationOutcome, SMT DEF ConditionalSourceHistory
        <1>wire. ActualConditionalHistory = ConditionalPhysicalEvent(1) \o ConditionalPhysicalEvent(2)
            BY ONLY <1>shape, SMT
                DEF ActualConditionalHistory, \#(history), ConditionalPhysicalEvent, ConditionalPhysicalRecord,
                    ConditionalPhysicalFailure,
                    ConditionalPhysicalOperands, ConditionalPhysicalOperation, ConditionalFailureRecord,
                    ConditionalBeforeFields, ConditionalEntry, ConditionalActionOrdinal, ConditionalPrefix,
                    ConditionalCompleted, ConditionalSourceRows, \#((failures + operands + operation).joined(separator: ", "))
        <1>typed. \A arm \in ConditionalArms :
            ConditionalPhysicalEvent(arm) \in Seq({ConditionalPhysicalRecord(arm)})
            BY ONLY EmptySeq, SMT DEF ConditionalPhysicalEvent, Seq
        <1>empty. \A arm \in ConditionalArms :
            /\ ConditionalPhysicalEvent(arm) \o <<>> = ConditionalPhysicalEvent(arm)
            /\ <<>> \o ConditionalPhysicalEvent(arm) = ConditionalPhysicalEvent(arm)
            BY ONLY <1>typed, ConcatEmptySeq, SMT
        <1>rendered. ActualConditionalHistory = ConditionalSourceHistory
            BY ONLY <1>shape, <1>selector, <1>wire, <1>probes, <1>addition, <1>empty, SMT
                DEF ConditionalSourceHistory, ConditionalPhysicalEvent, ConditionalPhysicalRecord,
                    Arithmetic!GeneratedAdd, Arithmetic!Success, Arithmetic!GeneratedOverflow
        <1>comparison. ConditionalNativeComparison = ConditionalSourceComparison
            BY ONLY SMT DEF ConditionalNativeComparison, ConditionalSourceComparison
        <1>selected. ConditionalNativeSelectedArm = ConditionalSelectedArm
            BY ONLY <1>comparison, SMT DEF ConditionalNativeSelectedArm, ConditionalSelectedArm
        <1>nativePrefix. \A arm \in ConditionalArms : ConditionalNativeRows[arm].values = ConditionalCompleted(arm)
            BY ONLY <1>shape, SMT DEF ConditionalNativeRows, ConditionalCompleted, ConditionalSourceRows
        <1>nativeRoutes. \A arm \in ConditionalArms : \A position \in 1..2 :
            LET input == ConditionalSourceRows[arm].inputs[position]
            IN /\ input[1] \in {"literal", "state"}
               /\ (input[1] = "state" => input[2] \in ConditionalIntKeys)
               /\ ConditionalNativeRows[arm].inputs[position] =
                    IF input[1] = "state" THEN ConditionalWriter(arm, input[2]) ELSE input
            BY ONLY <1>shape, SMT DEF ConditionalNativeRows, ConditionalSourceRows, ConditionalIntKeys, ConditionalWriter
        <1>nativeOperands. \A arm \in ConditionalArms :
            ConditionalNativeOperands(arm) = ConditionalOperands(arm)
            <2>. TAKE arm \in ConditionalArms
            <2>pointwise. \A position \in 1..2 :
                ConditionalNativeOperand(arm, position) = ConditionalOperands(arm)[position]
                BY ONLY (arm \in ConditionalArms), <1>shape, <1>nativePrefix, <1>nativeRoutes, <1>routes, SMT
                    DEF ConditionalNativeOperand, ConditionalOperands, ConditionalLatest, ConditionalSourceRows,
                        Arithmetic!CompletedAssignmentBindings, Arithmetic!CopyMaterializedState,
                        Arithmetic!CopyReferenceValue
            <2>. QED BY ONLY <2>pointwise, SMT DEF ConditionalNativeOperands, ConditionalOperands
        <1>nativeAdd. \A arm \in ConditionalArms : ConditionalNativeAdd(arm) = ConditionalSourceAdd(arm)
            BY ONLY <1>nativeOperands, <1>values, SMT
                DEF ConditionalNativeAdd, ConditionalSourceAdd, ConditionalIntValues,
                    Arithmetic!InRange, Arithmetic!GeneratedOverflow, Arithmetic!SourceOverflow
        <1>nativeWire. \A arm \in ConditionalArms : \A payload :
            ConditionalNativeRecord(arm, payload) = ConditionalFailureRecord(arm, payload)
            BY ONLY <1>shape, SMT DEF ConditionalNativeRecord, ConditionalFailureRecord, ConditionalBeforeFields,
                ConditionalNativeRows, ConditionalSourceRows, ConditionalPrefix, ConditionalCompleted,
                ConditionalActionOrdinal
        <1>native. ConditionalNativeHistory(TRUE) = ConditionalSourceHistory
            BY ONLY <1>selector, <1>selected, <1>nativeAdd, <1>nativeWire, SMT
                DEF ConditionalNativeHistory, ConditionalSourceHistory
        <1>finalWriters. \A arm \in ConditionalArms : \A key \in ConditionalStateKeys :
            LET row == ConditionalSourceRows[arm]
            IN /\ Len(row.targets) \in Nat
               /\ Arithmetic!CopyReceiptNamesWriter(row.targets, Len(row.targets), key, row.finalRoutes[key])
            BY ONLY <1>shape, SMT DEF ConditionalSourceRows, ConditionalStateKeys,
                Arithmetic!CopyReceiptNamesWriter, Arithmetic!CopyReceiptOrdinal,
                Arithmetic!LastDirectCopy, Arithmetic!DirectCopyReference
        <1>routesAreComplete. \A arm \in ConditionalArms : \A key \in ConditionalStateKeys :
            LET row == ConditionalSourceRows[arm]
            IN row.finalRoutes[key] = Arithmetic!DirectCopyRoutes(ConditionalStateKeys, row.targets)[Len(row.targets)][key]
            BY ONLY <1>finalWriters, Arithmetic!NamedReceiptReferenceUsesTheLastWriter, SMT
        <1>captureTypes. \A arm \in ConditionalArms :
            /\ ConditionalCompleted(arm) \in Seq(Int \cup BOOLEAN)
            /\ <<ConditionalSourceAdd(arm).value>> \in Seq(Int \cup BOOLEAN)
            /\ ConditionalSourceRows[arm].suffix \in Seq(Int \cup BOOLEAN)
            BY ONLY <1>shape, <1>values, <1>addition, SeqDef, SMT
                DEF ConditionalSourceRows, ConditionalCompleted, ConditionalIntValues,
                    Arithmetic!GeneratedAdd, Arithmetic!Success, Arithmetic!GeneratedOverflow
        <1>captureValues. \A arm \in ConditionalArms :
            LET prefix == ConditionalCompleted(arm)
                suffix == ConditionalSourceRows[arm].suffix
                captures == ConditionalSuccessfulCaptures(arm)
                middle == Len(prefix) + 1
            IN /\ Len(captures) = middle + Len(suffix)
               /\ \A i \in 1..Len(prefix) : captures[i] = prefix[i]
               /\ captures[middle] = ConditionalSourceAdd(arm).value
               /\ \A i \in 1..Len(suffix) : captures[middle + i] = suffix[i]
            BY ONLY <1>captureTypes, LenProperties, ConcatProperties, SMT DEF ConditionalSuccessfulCaptures
        <1>layout. /\ vars = ConditionalEntry
                   /\ (Next <=> ConditionalPhysicalStep)
            BY ONLY SMT DEF vars, ConditionalEntry, Next, ConditionalPhysicalStep
        <1>step. ConditionalPhysicalStep <=> ConditionalSourceStep
            BY ONLY ConditionalTypedState, <1>shape, <1>values, <1>addition, <1>probes,
                <1>selector, <1>routesAreComplete, <1>captureValues, SMT
                DEF ConditionalPhysicalStep, \#(actionName), ConditionalSourceStep,
                    ConditionalSelectedArm, ConditionalArmFor, ConditionalSourceComparison,
                    ConditionalStateKeys, ConditionalStateBefore, ConditionalStateAfter, ConditionalBefore, ConditionalIntKeys,
                    ConditionalSuccessfulState, ConditionalCompleted, ConditionalSourceRows,
                    ConditionalPhysicalOperands, \#(operands.joined(separator: ", ")),
                    Arithmetic!CopyMaterializedState, Arithmetic!CopyReferenceValue,
                    Arithmetic!GeneratedAdd, Arithmetic!GeneratedAddDefined, Arithmetic!SmallAddOperands,
                    Arithmetic!Success, Arithmetic!GeneratedOverflow
        <1>noSuccessor. ~ConditionalSourceAdd(ConditionalSelectedArm).ok => ~ENABLED Next
            BY ONLY <1>step, <1>layout, ExpandENABLED, SMT
                DEF Next, \#(actionName), ConditionalPhysicalStep, ConditionalSourceStep,
                    ConditionalStateAfter, ConditionalSuccessfulState
        \#(nativeSuccess.steps)
        <1>. QED BY ONLY <1>rendered, <1>native, <1>evaluation, <1>layout, <1>step, <1>nativeSuccess, <1>noSuccessor, PTL

        ====
        """#
    }

    private static func conditionalConfiguredProof(name: String, actionProof: String, cfgProof: String) -> String {
        #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(actionProof), CallerInputPageBlock1

        \#(cfgProof)

        ConditionalConfiguredBehavior == Init /\ [][ConditionalSourceStep]_vars

        THEOREM NormalConditionalConfigurationUsesTheAuthoredArms ==
            /\ LocalOrderedRHSActualCFG = LocalOrderedRHSExpectedCFG
            /\ (ConditionalTypedState =>
                  /\ (Next <=> ConditionalSourceStep)
                  /\ (ConditionalNativeStep <=> ConditionalSourceStep)
                  /\ (ConditionalSelectedEvaluationCheck <=> ConditionalSourceHistory = <<>>)
                  /\ (ConditionalSelectedEvaluationCheck <=> ActualConditionalHistory = <<>>)
                  /\ (ConditionalSelectedEvaluationCheck <=> ConditionalNativeHistory(TRUE) = <<>>))
            /\ ([]ConditionalTypedState => (Spec <=> ConditionalConfiguredBehavior))
        PROOF
        <1>checked. ConditionalTypedState =>
                  /\ (Next <=> ConditionalSourceStep)
                  /\ (ConditionalNativeStep <=> ConditionalSourceStep)
                  /\ (ConditionalSelectedEvaluationCheck <=> ConditionalSourceHistory = <<>>)
                  /\ (ConditionalSelectedEvaluationCheck <=> ActualConditionalHistory = <<>>)
                  /\ (ConditionalSelectedEvaluationCheck <=> ConditionalNativeHistory(TRUE) = <<>>)
            BY ONLY ActualConditionalHistoryMatchesTheAuthoredArms, SMT
        <1>stuttering. ConditionalTypedState => ([Next]_vars <=> [ConditionalSourceStep]_vars)
            BY ONLY <1>checked, PTL
        <1>always. []ConditionalTypedState => (([][Next]_vars) <=> ([][ConditionalSourceStep]_vars))
            BY ONLY <1>stuttering, PTL
        <1>spec. Spec <=> Init /\ [][Next]_vars
            BY ONLY DEF Spec
        <1>behavior. []ConditionalTypedState => (Spec <=> ConditionalConfiguredBehavior)
            BY ONLY <1>spec, <1>always, PTL DEF ConditionalConfiguredBehavior
        <1>. QED BY ONLY NormalOrderedRHSCFGSelectsSpecDeadlockAndEvaluationChecking, <1>checked, <1>behavior, PTL

        ====
        """#
    }
}

struct NativeConditionalVisit {
    struct Continuation {
        let id: Int
        let arguments: [String]
    }

    let predicate: [String]
    let ifTrue: Continuation
    let ifFalse: Continuation
}

// Check the labels and closures of the actual call before interpreting their children.
func nativeConditionalVisit(_ syntax: Syntax?) -> NativeConditionalVisit? {
    func words(_ syntax: some SyntaxProtocol) -> [String] {
        syntax.tokens(viewMode: .sourceAccurate).map(\.text)
    }
    func directCall(_ attempt: TryExprSyntax) -> FunctionCallExprSyntax? {
        guard attempt.questionOrExclamationMark == nil,
              let call = attempt.expression.as(FunctionCallExprSyntax.self),
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else { return nil }
        return call
    }
    func closure(_ argument: LabeledExprSyntax, label: String?) -> ClosureExprSyntax? {
        guard argument.label?.text == label,
              let value = argument.expression.as(ClosureExprSyntax.self),
              value.signature == nil, value.statements.count == 1 else { return nil }
        return value
    }
    func branch(_ argument: LabeledExprSyntax, label: String) -> NativeConditionalVisit.Continuation? {
        guard let body = closure(argument, label: label)?.statements.first?.item,
              let attempt = body.as(TryExprSyntax.self)
                ?? body.as(ExpressionStmtSyntax.self)?.expression.as(TryExprSyntax.self),
              let call = directCall(attempt),
              let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let id = Int(name.dropFirst("_actionPart".count)), name == "_actionPart\(id)" else { return nil }
        let arguments = call.arguments.compactMap { argument -> String? in
            guard argument.label == nil,
                  let reference = argument.expression.as(DeclReferenceExprSyntax.self),
                  reference.argumentNames == nil else { return nil }
            return reference.baseName.text
        }
        guard arguments.count == call.arguments.count else { return nil }
        return .init(id: id, arguments: arguments)
    }
    guard let attempt = syntax?.as(TryExprSyntax.self), !attempt.hasError,
          let call = directCall(attempt),
          words(call.calledExpression) == ["SwiftTLA", ".", "_NativeMachineOperations", ".", "visitConditional"],
          call.arguments.count == 3 else { return nil }
    let arguments = Array(call.arguments)
    guard let predicate = closure(arguments[0], label: nil),
          let ifTrue = branch(arguments[1], label: "ifTrue"),
          let ifFalse = branch(arguments[2], label: "ifFalse"),
          ifTrue.id != ifFalse.id else { return nil }
    return .init(predicate: words(predicate.statements), ifTrue: ifTrue, ifFalse: ifFalse)
}
