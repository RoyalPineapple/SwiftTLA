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

        let occupied = Set(fields.map(\.formalName)).union([actionLayout.renderedName])
        func proofBinding(_ preferred: String) -> String {
            var name = preferred
            while occupied.contains(name) { name += "_" }
            return name
        }

        let regions = action.body.orderedAlternativeFailureRegions
        guard regions.count == source.arms.count else { throw invalid }
        let descriptors = try zip(source.arms, regions).enumerated().map { arm, pair -> ConditionalOverflowArm in
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
            let latestBeforeAddition = latest
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

            let position = arm + 1
            let prefixExpression = "ConditionalPrefix(\(position))"
            let completed = "ConditionalCompleted(\(position))"
            var facts = ConditionalArmProofFacts()
            facts.targets.append("Len(\(prefixExpression)) = \(addition)")
            for index in prefix.indices {
                facts.targets.append("\(prefixExpression)[\(index + 1)].target = \(TLAValue.string(writes[index].target))")
            }
            for field in integers {
                let key = field.declaration.name
                guard let reference = latestBeforeAddition[key] else { throw invalid }
                facts.routes.append("ConditionalWriter(\(position), \(TLAValue.string(key))) = \(reference)")
            }
            facts.readInputs.append("ConditionalSourceRows[\(position)].inputs = \(TLAValue.tuple(operands))")
            for operand in operands {
                if let literal = conditionalLiteral([operand]) {
                    facts.operands.append(literal)
                    continue
                }
                guard let field = try sourceRead(operand, fields: names) else { throw invalid }
                let root = field.declaration.name
                let key = TLAValue.string(root)
                guard let route = latestBeforeAddition[root] else { throw invalid }
                let routeFact = "Arithmetic!DirectCopyRoutes(ConditionalIntKeys, \(prefixExpression))[Len(\(completed))][\(key)] = \(route)"
                if !facts.readRoutes.contains(routeFact) { facts.readRoutes.append(routeFact) }
                let value: TLAValue
                if let index = prefix.indices.last(where: { writes[$0].target == root }) {
                    value = prefix[index].value
                    let inputFact = "\(completed)[\(index + 1)] = \(value)"
                    if !facts.readInputs.contains(inputFact) { facts.readInputs.append(inputFact) }
                } else {
                    value = .constant(field.formalName)
                }
                let readFact = "ConditionalLatest(\(position))[\(key)] = \(value)"
                if !facts.readValues.contains(readFact) { facts.readValues.append(readFact) }
                facts.operands.append(value)
            }
            let captures = prefix.map { String(describing: $0.value) } + [proofBinding("result")]
                + suffix.map { String(describing: $0) }
            let outputs = try fields.map { field -> ConditionalOverflowOutput in
                let fieldName = field.declaration.name
                guard let reference = latest[fieldName] else { throw invalid }
                let key = TLAValue.string(fieldName)
                if reference == .tuple([.string("state"), key]) {
                    return .init(key: key, reference: reference, slot: nil, expression: field.formalName)
                }
                guard case .tuple(let pair) = reference, pair.count == 2, pair[0] == .string("capture"),
                      case .int(let slot) = pair[1], slot > 0, captures.indices.contains(slot - 1)
                else { throw invalid }
                return .init(key: key, reference: reference, slot: slot, expression: captures[slot - 1])
            }
            let row = TLAValue.record(["prefix": .tuple(prefix.map(\.row)), "inputs": .tuple(operands),
                                       "routes": routes, "values": .tuple(prefix.map(\.value)),
                                       "suffix": .tuple(suffix), "finalRoutes": finalRoutes, "targets": .tuple(targets),
                                       "site": .int(failed.binding.binder.ordinal),
                                       "target": .int(failed.binding.target.ordinal)])
            let beforeFields = prefix.enumerated().map { index, capture in
                let binding = ordered[index].binding
                return TLAValue.record(["binding": .int(binding.binder.ordinal), "target": .int(binding.target.ordinal),
                                        "value": capture.value])
            }
            let nativeBefore = prefix.indices.map { index in
                let binding = ordered[index].binding
                return TLAValue.record(["binding": .int(binding.binder.ordinal), "target": .int(binding.target.ordinal),
                                        "slot": .int(index + 1)])
            }
            return .init(row: row, prefixRows: .tuple(prefix.map(\.row)), beforeFields: .tuple(beforeFields),
                         nativeBefore: .tuple(nativeBefore),
                         site: failed.binding.binder.ordinal, target: failed.binding.target.ordinal, targets: writes.map { .string($0.target) },
                         prefix: prefix.map(\.value), suffix: suffix, outputs: outputs, proof: facts)
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
            keys: .set(keys), before: stateCases(integers), state: state,
            typed: types.joined(separator: " /\\ "), predicate: source.predicate,
            actionName: actionLayout.renderedName, stateKeys: .set(source.fields),
            fullBefore: stateCases(fields), after: stateCases(fields, primed: true),
            nativeComparison: nativeComparison, nativeRows: .tuple(nativeRows.map { conditionalProofRow($0.row) }),
            nativeInputs: nativeRows.map(\.inputs), nativeWriteOrders: [native.ifTrue.writeOrder, native.ifFalse.writeOrder],
            comparison: "\(lhs.formalName) < \(rhs.formalName)",
            primedState: fields.map { "\($0.formalName)'" }.joined(separator: ", "),
            descriptors: descriptors, proofBinding: proofBinding)
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

    private static func conditionalNativeFailureRow(_ arm: NativeConditionalArmOutput) throws -> (row: TLAValue, inputs: TLAValue) {
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
        let inputs = TLAValue.tuple(operands)
        return (.record(["action": .int(call.action), "branch": .int(call.branch), "site": .int(call.site),
                        "target": .int(call.target), "before": .tuple(before), "values": .tuple(values),
                        "inputs": inputs, "suffix": materialization.suffix, "writes": materialization.writes]), inputs)
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

    private static func conditionalProofRow(_ row: TLAValue) -> TLAValue {
        guard case .record(let record) = row,
              case .tuple(let values)? = record.value(named: "values") else { return row }
        // Keep large numerals opaque when proving structural facts about the row.
        let proofValues = values.map { value in
            value == .int(Int.max) ? TLAValue.constant("ConditionalRowMaximum") : value
        }
        return .record(record.replacing(.tuple(proofValues), for: "values"))
    }

    private struct ConditionalArmProofFacts {
        var targets: [String] = []
        var routes: [String] = []
        var readInputs: [String] = []
        var readRoutes: [String] = []
        var readValues: [String] = []
        var operands: [TLAValue] = []
    }

    private static func conditionalOperandProof(_ arms: [ConditionalArmProofFacts], operands: [String])
        -> (writers: String, values: String) {
        func step(_ name: String, _ facts: [String], _ by: String) -> String {
            "<1>\(name). /\\ " + facts.joined(separator: "\n    /\\ ") + "\n    " + by
        }
        let writers = [
            step("prefixTargets", arms.flatMap(\.targets), "BY ONLY SMT DEF ConditionalPrefix, ConditionalSourceRows"),
            step("receiptRoutes", arms.flatMap(\.routes), "BY ONLY SMT DEF ConditionalWriter, ConditionalSourceRows")
        ].joined(separator: "\n")

        let readRoutes = arms.flatMap(\.readRoutes)
        let readValues = arms.flatMap(\.readValues)
        let sourceOperands = arms.enumerated().map { index, arm in "ConditionalOperands(\(index + 1)) = \(TLAValue.tuple(arm.operands))" }
        let physicalOperands = arms.enumerated().map { index, arm in
            "ConditionalPhysicalOperands(\(index + 1)) = \(TLAValue.tuple(arm.operands))"
        }
        let bounds = arms.flatMap(\.operands).reduce(into: [TLAValue]()) { terms, value in
            if case .int = value, !terms.contains(value) { terms.append(value) }
        }.map { "\($0) \\in ConditionalIntValues" }
        var steps = [
            step("readInputs", arms.flatMap(\.readInputs),
                 "BY ONLY SMT DEF ConditionalSourceRows, ConditionalCompleted, ConditionalRowMaximum")
        ]
        if !readRoutes.isEmpty {
            steps.append(step("readRoutes", readRoutes, #"""
            BY ONLY <1>shape, <1>routes, <1>receiptRoutes, SMT DEF ConditionalIntKeys
            """#))
            steps.append(step("readValues", readValues, #"""
            BY ONLY <1>readInputs, <1>readRoutes, SMT
                DEF ConditionalLatest, ConditionalBefore, ConditionalIntKeys, Arithmetic!CompletedAssignmentBindings,
                    Arithmetic!CopyMaterializedState, Arithmetic!CopyReferenceValue
            """#))
        }
        let readBindings = readValues.isEmpty ? "" : ", <1>readValues"
        steps.append(step("readOperands", sourceOperands,
            "BY ONLY <1>readInputs\(readBindings), SMT DEF ConditionalOperands, Arithmetic!CopyReferenceValue"))
        steps.append(step("physicalOperands", physicalOperands,
            "BY ONLY SMT DEF ConditionalPhysicalOperands, \(operands.joined(separator: ", "))"))
        if !bounds.isEmpty {
            steps.append(step("operandBounds", bounds, "BY ONLY SMT DEF ConditionalIntValues"))
        }
        let operandBounds = bounds.isEmpty ? "" : ", <1>operandBounds"
        steps.append(#"""
        <1>values. \A arm \in ConditionalArms :
            /\ ConditionalPhysicalOperands(arm) = ConditionalOperands(arm)
            /\ ConditionalOperands(arm)[1] \in ConditionalIntValues
            /\ ConditionalOperands(arm)[2] \in ConditionalIntValues
            BY ONLY <1>shape, <1>readOperands, <1>physicalOperands\#(operandBounds), ConditionalTypedState, SMT
                DEF ConditionalTypedState
        """#)
        return (writers, steps.joined(separator: "\n"))
    }

    private struct ConditionalOverflowOutput {
        let key: TLAValue
        let reference: TLAValue
        let slot: Int?
        let expression: String
    }

    private struct ConditionalOverflowArm {
        let row: TLAValue
        let prefixRows: TLAValue
        let beforeFields: TLAValue
        let nativeBefore: TLAValue
        let site: Int
        let target: Int
        let targets: [TLAValue]
        let prefix: [TLAValue]
        let suffix: [TLAValue]
        let outputs: [ConditionalOverflowOutput]
        let proof: ConditionalArmProofFacts
    }

    private static func conditionalOverflowProof(
        name: String, model: String, history: String, operation: [String], operands: [String],
        failures: [String], aggregate: String, evaluationCheck: String, ordinal: Int,
        keys: TLAValue, before: String,
        state: String, typed: String, predicate: TLAValue, actionName: String,
        stateKeys: TLAValue, fullBefore: String, after: String, nativeComparison: TLAValue, nativeRows: TLAValue,
        nativeInputs: [TLAValue], nativeWriteOrders: [[String]],
        comparison: String, primedState: String, descriptors: [ConditionalOverflowArm], proofBinding: (String) -> String
    ) -> String {
        let physicalArm = proofBinding("arm")
        let physicalResult = proofBinding("result")
        let postState = proofBinding("after")
        let writes = proofBinding("writes")
        let defined = proofBinding("defined")
        let total = proofBinding("total")
        let routes = proofBinding("finalRef")
        let targets = proofBinding("targetKeys")
        let slotValue = proofBinding("value")
        let writtenRef = proofBinding("writtenRef")
        func byArm(_ first: String, _ second: String, arm: String = "arm") -> String {
            first == second ? first : "(IF \(arm) = 1 THEN \(first) ELSE \(second))"
        }
        func lengths(_ selector: (ConditionalOverflowArm) -> [TLAValue]) -> String {
            byArm(String(selector(descriptors[0]).count), String(selector(descriptors[1]).count))
        }
        func asTuple(_ selector: (ConditionalOverflowArm) -> [TLAValue]) -> String {
            byArm(String(describing: TLAValue.tuple(selector(descriptors[0]))),
                  String(describing: TLAValue.tuple(selector(descriptors[1]))))
        }
        func conjuncts(_ formulas: [String], indentation: Int) -> String {
            formulas.map { "/\\ " + $0 }.joined(separator: "\n" + String(repeating: " ", count: indentation))
        }

        let writerIntervals = descriptors.map { descriptor in
            "{\(descriptor.targets.indices.map { String($0 + 1) }.joined(separator: ", "))}"
        }
        let keyBinding = proofBinding("key")
        let finalRoutes = zip(descriptors[0].outputs, descriptors[1].outputs).map { first, second in
            "\(keyBinding) = \(first.key) -> " + byArm(String(describing: first.reference),
                String(describing: second.reference), arm: physicalArm)
        }.joined(separator: " [] ")
        let writtenValues = descriptors.map { $0.outputs.map(\.expression).joined(separator: ", ") }
        let result = "ConditionalSourceAdd(arm).value"
        func materialized(_ expression: String) -> String { expression == physicalResult ? result : expression }
        let captureSlots = descriptors.enumerated().map { index, descriptor in
            let equations = descriptor.outputs.compactMap { output -> String? in
                guard let slot = output.slot else { return nil }
                return "ConditionalSuccessfulCaptures(arm)[\(slot)] = \(materialized(output.expression))"
            }
            return "(arm = \(index + 1) => (\(equations.joined(separator: " /\\ "))))"
        }
        let lookupRefs = zip(descriptors[0].outputs, descriptors[1].outputs).map { first, second in
            "\(writtenRef)(\(first.key)) = " + byArm(String(describing: first.reference), String(describing: second.reference))
        }
        let lookupValues = zip(descriptors[0].outputs, descriptors[1].outputs).map { first, second in
            "\(slotValue)(\(first.key)) = " + byArm(materialized(first.expression), materialized(second.expression))
        }
        let nativeSuccess = conditionalNativeSuccessProof(writeOrders: nativeWriteOrders)
        let operandProof = conditionalOperandProof(descriptors.map(\.proof), operands: operands)
        let first = descriptors[0]
        let second = descriptors[1]
        let wireEquations = descriptors.enumerated().flatMap { index, descriptor in
            let name = index == 0 ? "firstBefore" : "secondBefore"
            return descriptor.prefix.indices.map { slot in
                "ConditionalBeforeFields(\(index + 1))[\(slot + 1)] = \(name)[\(slot + 1)]"
            }
        }
        let wireFields = wireEquations.isEmpty ? "" : #"""
            <2>fields. \#(conjuncts(wireEquations, indentation: 15))
                BY ONLY <2>prefix, <2>completed, SMT DEF ConditionalBeforeFields, firstBefore, secondBefore

        """#
        let wireFieldFacts = wireEquations.isEmpty ? "" : ", <2>fields"
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
        ConditionalRowMaximum == \#(TLAValue.int(Int.max))
        ConditionalSourceRows == \#(TLAValue.tuple(descriptors.map { conditionalProofRow($0.row) }))
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
        \#(operandProof.writers)
        <1>writers. \A arm \in ConditionalArms : \A key \in ConditionalIntKeys :
            Arithmetic!CopyReceiptNamesWriter(ConditionalPrefix(arm), Len(ConditionalPrefix(arm)), key,
                                               ConditionalWriter(arm, key))
            BY ONLY <1>shape, <1>prefixTargets, <1>receiptRoutes, SMT
                DEF ConditionalIntKeys, Arithmetic!CopyReceiptNamesWriter, Arithmetic!CopyReceiptOrdinal,
                    Arithmetic!LastDirectCopy, Arithmetic!DirectCopyReference
        <1>routes. \A arm \in ConditionalArms : \A key \in ConditionalIntKeys :
            ConditionalWriter(arm, key) =
                Arithmetic!DirectCopyRoutes(ConditionalIntKeys, ConditionalPrefix(arm))[Len(ConditionalPrefix(arm))][key]
            BY ONLY <1>shape, <1>writers, Arithmetic!NamedReceiptReferenceUsesTheLastWriter, SMT
        \#(operandProof.values)
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
            <2>actual. ConditionalSelectedEvaluationCheck <=> ~(ConditionalPhysicalFailure(1) \/ ConditionalPhysicalFailure(2))
                <3>then. CASE \#(comparison)
                    BY ONLY <3>then, SMT
                        DEF ConditionalSelectedEvaluationCheck, \#(evaluationCheck), \#(aggregate),
                            ConditionalPhysicalFailure, \#(failures.joined(separator: ", "))
                <3>else. CASE ~(\#(comparison))
                    BY ONLY <3>else, SMT
                        DEF ConditionalSelectedEvaluationCheck, \#(evaluationCheck), \#(aggregate),
                            ConditionalPhysicalFailure, \#(failures.joined(separator: ", "))
                <3>. QED BY ONLY <3>then, <3>else, SMT
            <2>. QED BY ONLY <2>actual, <1>shape, SMT DEF ConditionalPhysicalFailure
        <1>evaluationOutcome. ConditionalSelectedEvaluationCheck <=> ConditionalSourceAdd(ConditionalSelectedArm).ok
            BY ONLY <1>evaluationSites, <1>selector, <1>probes, <1>addition, SMT
                DEF Arithmetic!GeneratedAdd, Arithmetic!Success, Arithmetic!GeneratedOverflow
        <1>evaluation. ConditionalSelectedEvaluationCheck <=> ConditionalSourceHistory = <<>>
            BY ONLY <1>evaluationOutcome, SMT DEF ConditionalSourceHistory
        <1>wire. ActualConditionalHistory = ConditionalPhysicalEvent(1) \o ConditionalPhysicalEvent(2)
            <2>. DEFINE firstBefore == \#(first.beforeFields)
                        secondBefore == \#(second.beforeFields)
            <2>prefix. /\ ConditionalPrefix(1) = \#(first.prefixRows)
                        /\ ConditionalPrefix(2) = \#(second.prefixRows)
                BY ONLY SMT DEF ConditionalPrefix, ConditionalSourceRows
            <2>completed. /\ ConditionalCompleted(1) = \#(TLAValue.tuple(first.prefix))
                           /\ ConditionalCompleted(2) = \#(TLAValue.tuple(second.prefix))
                BY ONLY SMT DEF ConditionalCompleted, ConditionalSourceRows, ConditionalRowMaximum
            <2>domain. /\ DOMAIN ConditionalBeforeFields(1) = 1..\#(first.prefix.count)
                        /\ DOMAIN ConditionalBeforeFields(2) = 1..\#(second.prefix.count)
                BY ONLY <2>prefix, SMT DEF ConditionalBeforeFields
        \#(wireFields)    <2>before. /\ ConditionalBeforeFields(1) = firstBefore /\ ConditionalBeforeFields(2) = secondBefore
                BY ONLY <2>domain\#(wireFieldFacts), SMT DEF ConditionalBeforeFields, firstBefore, secondBefore
            <2>. DEFINE firstRecord == [source |-> ConditionalEntry, action |-> \#(ordinal), branch |-> 0,
                            site |-> \#(first.site), target |-> \#(first.target),
                            payload |-> <<"integerOverflow", "addition", \#(operands[0])>>, before |-> firstBefore]
                        secondRecord == [source |-> ConditionalEntry, action |-> \#(ordinal), branch |-> 1,
                            site |-> \#(second.site), target |-> \#(second.target),
                            payload |-> <<"integerOverflow", "addition", \#(operands[1])>>, before |-> secondBefore]
            <2>site. /\ ConditionalSourceRows[1].site = \#(first.site) /\ ConditionalSourceRows[1].target = \#(first.target)
                      /\ ConditionalSourceRows[2].site = \#(second.site) /\ ConditionalSourceRows[2].target = \#(second.target)
                BY ONLY SMT DEF ConditionalSourceRows
            <2>record. /\ ConditionalPhysicalRecord(1) = firstRecord /\ ConditionalPhysicalRecord(2) = secondRecord
                BY ONLY <2>before, <2>site, SMT DEF ConditionalPhysicalRecord, ConditionalPhysicalOperands, ConditionalPhysicalOperation,
                    ConditionalFailureRecord, ConditionalActionOrdinal, \#(operation.joined(separator: ", ")), firstRecord, secondRecord
            <2>raw. ActualConditionalHistory =
                    (IF \#(failures[0]) THEN <<firstRecord>> ELSE <<>>) \o
                    (IF \#(failures[1]) THEN <<secondRecord>> ELSE <<>>)
                BY ONLY SMT DEF ActualConditionalHistory, \#(history), firstRecord, secondRecord,
                    firstBefore, secondBefore, ConditionalEntry, \#((failures + operands).joined(separator: ", "))
            <2>. QED BY ONLY <2>raw, <2>record, SMT DEF ConditionalPhysicalEvent, ConditionalPhysicalFailure
        <1>typed. \A arm \in ConditionalArms :
            ConditionalPhysicalEvent(arm) \in Seq({ConditionalPhysicalRecord(arm)})
            BY ONLY EmptySeq, SMT DEF ConditionalPhysicalEvent, Seq
        <1>empty. \A arm \in ConditionalArms :
            /\ ConditionalPhysicalEvent(arm) \o <<>> = ConditionalPhysicalEvent(arm)
            /\ <<>> \o ConditionalPhysicalEvent(arm) = ConditionalPhysicalEvent(arm)
            BY ONLY <1>typed, ConcatEmptySeq, SMT
        <1>rendered. ActualConditionalHistory = ConditionalSourceHistory
            <2>gates. \A arm \in ConditionalArms :
                ConditionalPhysicalFailure(arm) <=> arm = ConditionalSelectedArm /\ ~ConditionalSourceAdd(arm).ok
                BY ONLY <1>probes, <1>addition, SMT DEF Arithmetic!GeneratedAdd, Arithmetic!Success, Arithmetic!GeneratedOverflow
            <2>pairs. \A arm \in ConditionalArms :
                ConditionalPhysicalOperands(arm) = <<ConditionalPhysicalOperands(arm)[1], ConditionalPhysicalOperands(arm)[2]>>
                BY ONLY <1>shape, SMT DEF ConditionalPhysicalOperands, \#(operands.joined(separator: ", "))
            <2>payload. ~ConditionalSourceAdd(ConditionalSelectedArm).ok =>
                ConditionalSourceAdd(ConditionalSelectedArm).failure =
                    <<"integerOverflow", "addition", ConditionalPhysicalOperands(ConditionalSelectedArm)>>
                BY ONLY <1>selector, <1>addition, <2>pairs, SMT
                    DEF Arithmetic!GeneratedAdd, Arithmetic!Success, Arithmetic!GeneratedOverflow
            <2>selectedEvent. ConditionalPhysicalEvent(ConditionalSelectedArm) = ConditionalSourceHistory
                BY ONLY <1>selector, <1>probes, <2>gates, <2>payload, SMT
                    DEF ConditionalSourceHistory, ConditionalPhysicalEvent, ConditionalPhysicalRecord
            <2>inactive. \A arm \in ConditionalArms :
                arm # ConditionalSelectedArm => ConditionalPhysicalEvent(arm) = <<>>
                BY ONLY <2>gates, SMT DEF ConditionalPhysicalEvent
            <2>left. CASE ConditionalSelectedArm = 1
                BY ONLY <2>left, <1>shape, <1>wire, <1>empty, <2>inactive, <2>selectedEvent, SMT
            <2>right. CASE ConditionalSelectedArm = 2
                BY ONLY <2>right, <1>shape, <1>wire, <1>empty, <2>inactive, <2>selectedEvent, SMT
            <2>. QED BY ONLY <1>shape, <1>selector, <2>left, <2>right, SMT
        <1>comparison. ConditionalNativeComparison = ConditionalSourceComparison
            BY ONLY SMT DEF ConditionalNativeComparison, ConditionalSourceComparison
        <1>selected. ConditionalNativeSelectedArm = ConditionalSelectedArm
            BY ONLY <1>comparison, SMT DEF ConditionalNativeSelectedArm, ConditionalSelectedArm
        <1>nativePrefix. \A arm \in ConditionalArms : ConditionalNativeRows[arm].values = ConditionalCompleted(arm)
            <2>columns. /\ ConditionalNativeRows[1].values = ConditionalCompleted(1)
                        /\ ConditionalNativeRows[2].values = ConditionalCompleted(2)
                BY ONLY IsaM("auto") DEF ConditionalNativeRows, ConditionalCompleted, ConditionalSourceRows
            <2>. QED BY ONLY <2>columns, <1>shape, SMT
        <1>nativeRoutes. \A arm \in ConditionalArms : \A position \in 1..2 :
            LET input == ConditionalSourceRows[arm].inputs[position]
            IN /\ input[1] \in {"literal", "state"}
               /\ (input[1] = "state" => input[2] \in ConditionalIntKeys)
               /\ ConditionalNativeRows[arm].inputs[position] =
                    IF input[1] = "state" THEN ConditionalWriter(arm, input[2]) ELSE input
            <2>. DEFINE agrees(a, p) ==
                        LET input == ConditionalSourceRows[a].inputs[p]
                        IN /\ input[1] \in {"literal", "state"}
                           /\ (input[1] = "state" => input[2] \in ConditionalIntKeys)
                           /\ ConditionalNativeRows[a].inputs[p] =
                                   IF input[1] = "state" THEN ConditionalWriter(a, input[2]) ELSE input
            <2>inputs. \#(conjuncts(nativeInputs.enumerated().map { "ConditionalNativeRows[\($0.offset + 1)].inputs = \($0.element)" }, indentation: 17))
                BY ONLY IsaM("simp") DEF ConditionalNativeRows
            <2>columns. /\ agrees(1, 1) /\ agrees(1, 2) /\ agrees(2, 1) /\ agrees(2, 2)
                BY ONLY <1>readInputs, <1>receiptRoutes, <2>inputs, SMT DEF agrees, ConditionalIntKeys
            <2>all. \A arm \in ConditionalArms : \A position \in 1..2 : agrees(arm, position)
                BY ONLY <1>shape, <2>columns, SMT
            <2>. QED BY ONLY <2>all DEF agrees
        <1>nativeOperands. \A arm \in ConditionalArms :
            ConditionalNativeOperands(arm) = ConditionalOperands(arm)
            <2>. TAKE arm \in ConditionalArms
            <2>latest. \A key \in ConditionalIntKeys :
                ConditionalLatest(arm)[key] = Arithmetic!CopyReferenceValue(
                    ConditionalBefore, ConditionalCompleted(arm), ConditionalWriter(arm, key))
                BY ONLY (arm \in ConditionalArms), <1>shape, <1>routes, SMT
                    DEF ConditionalLatest, Arithmetic!CompletedAssignmentBindings, Arithmetic!CopyMaterializedState
            <2>pointwise. \A position \in 1..2 :
                ConditionalNativeOperand(arm, position) = ConditionalOperands(arm)[position]
                <3>. TAKE position \in 1..2
                <3>. DEFINE input == ConditionalSourceRows[arm].inputs[position]
                            native == ConditionalNativeRows[arm].inputs[position]
                            value == Arithmetic!CopyReferenceValue(ConditionalLatest(arm), <<>>, input)
                <3>source. ConditionalOperands(arm)[position] = value
                    BY ONLY (position \in 1..2), SMT DEF ConditionalOperands, value, input
                <3>role. /\ input[1] \in {"literal", "state"}
                         /\ (input[1] = "state" => input[2] \in ConditionalIntKeys)
                         /\ native = IF input[1] = "state" THEN ConditionalWriter(arm, input[2]) ELSE input
                    BY ONLY (arm \in ConditionalArms), (position \in 1..2), <1>nativeRoutes, SMT DEF input, native
                <3>raw. ConditionalNativeOperand(arm, position) =
                    Arithmetic!CopyReferenceValue(ConditionalBefore, ConditionalCompleted(arm), native)
                    BY ONLY (arm \in ConditionalArms), <1>nativePrefix, SMT DEF ConditionalNativeOperand, native
                <3>literal. CASE input[1] = "literal"
                    BY ONLY <3>literal, <3>role, <3>raw, <3>source, SMT DEF value, Arithmetic!CopyReferenceValue
                <3>read. CASE input[1] = "state"
                    <4>bound. ConditionalLatest(arm)[input[2]] =
                        Arithmetic!CopyReferenceValue(ConditionalBefore, ConditionalCompleted(arm), native)
                        BY ONLY <3>role, <3>read, <2>latest, SMT
                    <4>. QED BY ONLY <3>read, <4>bound, <3>raw, <3>source, SMT DEF value, Arithmetic!CopyReferenceValue
                <3>. QED BY ONLY <3>role, <3>literal, <3>read, SMT
            <2>. QED BY ONLY <2>pointwise, SMT DEF ConditionalNativeOperands, ConditionalOperands
        <1>nativeAdd. \A arm \in ConditionalArms : ConditionalNativeAdd(arm) = ConditionalSourceAdd(arm)
            <2>. TAKE arm \in ConditionalArms
            <2>. DEFINE a == ConditionalOperands(arm)[1]
                        b == ConditionalOperands(arm)[2]
                        sum == a + b
            <2>bounds. /\ a \in Int /\ b \in Int /\ sum \in Int
                BY ONLY (arm \in ConditionalArms), <1>values, SMT DEF a, b, sum, ConditionalIntValues
            <2>inputs. ConditionalNativeOperands(arm) = ConditionalOperands(arm)
                BY ONLY (arm \in ConditionalArms), <1>nativeOperands, SMT
            <2>adequate. Arithmetic!InRange(sum) <=>
                ~(sum < \#(TLAValue.int(Int.min)) \/
                  sum > \#(TLAValue.int(Int.max)))
                BY ONLY <2>bounds, SMT DEF Arithmetic!InRange
            <2>. QED BY ONLY <2>adequate, <2>inputs, SMT DEF a, b, sum, ConditionalNativeAdd, ConditionalSourceAdd,
                    Arithmetic!SourceAdd, Arithmetic!GeneratedOverflow, Arithmetic!SourceOverflow
        <1>nativeWire. \A arm \in ConditionalArms : \A payload :
            ConditionalNativeRecord(arm, payload) = ConditionalFailureRecord(arm, payload)
            <2>. DEFINE matches(a) ==
                    LET row == ConditionalNativeRows[a]
                        src == ConditionalSourceRows[a]
                    IN /\ row.action = ConditionalActionOrdinal /\ row.branch = a-1
                       /\ row.site = src.site /\ row.target = src.target
                       /\ DOMAIN row.before = DOMAIN ConditionalPrefix(a)
                       /\ \A i \in DOMAIN row.before :
                              /\ row.before[i].binding = ConditionalPrefix(a)[i].binding
                              /\ row.before[i].target = ConditionalPrefix(a)[i].field
                              /\ row.before[i].slot = i
            <2>sourceHeader. /\ <<ConditionalSourceRows[1].site, ConditionalSourceRows[1].target>> = <<\#(first.site), \#(first.target)>>
                              /\ <<ConditionalSourceRows[2].site, ConditionalSourceRows[2].target>> = <<\#(second.site), \#(second.target)>>
                BY ONLY SMT DEF ConditionalSourceRows
            <2>nativeHeader. /\ LET row == ConditionalNativeRows[1]
                                IN <<row.action, row.branch, row.site, row.target>> = <<ConditionalActionOrdinal, 0, \#(first.site), \#(first.target)>>
                              /\ LET row == ConditionalNativeRows[2]
                                 IN <<row.action, row.branch, row.site, row.target>> = <<ConditionalActionOrdinal, 1, \#(second.site), \#(second.target)>>
                BY ONLY SMT DEF ConditionalNativeRows, ConditionalActionOrdinal
            <2>prefix. /\ ConditionalPrefix(1) = \#(first.prefixRows)
                        /\ ConditionalPrefix(2) = \#(second.prefixRows)
                BY ONLY IsaM("simp") DEF ConditionalPrefix, ConditionalSourceRows
            <2>recorded. /\ ConditionalNativeRows[1].before = \#(first.nativeBefore)
                          /\ ConditionalNativeRows[2].before = \#(second.nativeBefore)
                BY ONLY IsaM("simp") DEF ConditionalNativeRows
            <2>both. matches(1) /\ matches(2)
                BY ONLY <2>sourceHeader, <2>nativeHeader, <2>prefix, <2>recorded, SMT DEF matches
            <2>every. \A a \in ConditionalArms : matches(a)
                BY ONLY <1>shape, <2>both, SMT
            <2>. TAKE arm \in ConditionalArms
            <2>. TAKE payload
            <2>. DEFINE row == ConditionalNativeRows[arm]
                        obs == [i \in DOMAIN row.before |->
                                LET capture == row.before[i]
                                IN [binding |-> capture.binding, target |-> capture.target, value |-> row.values[capture.slot]]]
            <2>columns. matches(arm)
                BY ONLY (arm \in ConditionalArms), <2>every, SMT
            <2>frames. obs = ConditionalBeforeFields(arm)
                BY ONLY (arm \in ConditionalArms), <2>columns, <1>nativePrefix, SMT
                    DEF matches, row, obs, ConditionalBeforeFields
            <2>. QED BY ONLY <2>columns, <2>frames, SMT DEF matches, row, obs, ConditionalNativeRecord, ConditionalFailureRecord
        <1>native. ConditionalNativeHistory(TRUE) = ConditionalSourceHistory
            BY ONLY <1>selector, <1>selected, <1>nativeAdd, <1>nativeWire, SMT
                DEF ConditionalNativeHistory, ConditionalSourceHistory
        <1>finalWriters. \A arm \in ConditionalArms : \A key \in ConditionalStateKeys :
            LET row == ConditionalSourceRows[arm]
            IN /\ Len(row.targets) \in Nat
               /\ Arithmetic!CopyReceiptNamesWriter(row.targets, Len(row.targets), key, row.finalRoutes[key])
            <2>. TAKE arm \in ConditionalArms
            <2>. TAKE key \in ConditionalStateKeys
            <2>. DEFINE row == ConditionalSourceRows[arm]
                          \#(routes)(\#(physicalArm), \#(keyBinding)) == CASE \#(finalRoutes) [] OTHER -> 0
                          \#(targets) == \#(asTuple(\.targets))
            <2>cases. arm = 1 \/ arm = 2
                BY ONLY <1>shape, (arm \in ConditionalArms), SMT
            <2>length. Len(row.targets) = \#(lengths(\.targets))
                BY ONLY <2>cases, SMT DEF row, ConditionalSourceRows
            <2>interval. 1..Len(row.targets) = \#(byArm(writerIntervals[0], writerIntervals[1]))
                BY ONLY <2>cases, <2>length, SMT
            <2>route. row.finalRoutes[key] = \#(routes)(arm, key)
                BY ONLY <2>cases, (key \in ConditionalStateKeys), SMT
                    DEF row, ConditionalSourceRows, ConditionalStateKeys, \#(routes)
            <2>targets. \A i \in 1..Len(row.targets) : row.targets[i].target = \#(targets)[i]
                BY ONLY <2>cases, <2>interval, SMT DEF row, ConditionalSourceRows, \#(targets)
            <2>. QED BY ONLY <2>cases, <2>length, <2>interval, <2>route, <2>targets,
                (key \in ConditionalStateKeys), SMT
                DEF row, ConditionalStateKeys, \#(routes), \#(targets), Arithmetic!CopyReceiptNamesWriter,
                    Arithmetic!CopyReceiptOrdinal, Arithmetic!LastDirectCopy, Arithmetic!DirectCopyReference
        <1>routesAreComplete. \A arm \in ConditionalArms : \A key \in ConditionalStateKeys :
            LET row == ConditionalSourceRows[arm]
            IN row.finalRoutes[key] = Arithmetic!DirectCopyRoutes(ConditionalStateKeys, row.targets)[Len(row.targets)][key]
            BY ONLY <1>finalWriters, Arithmetic!NamedReceiptReferenceUsesTheLastWriter, SMT
        <1>captureTypes. \A arm \in ConditionalArms :
            /\ ConditionalCompleted(arm) \in Seq(Int \cup BOOLEAN)
            /\ <<ConditionalSourceAdd(arm).value>> \in Seq(Int \cup BOOLEAN)
            /\ ConditionalSourceRows[arm].suffix \in Seq(Int \cup BOOLEAN)
            <2>. TAKE arm \in ConditionalArms
            <2>slots. /\ ConditionalCompleted(arm) \in [1..\#(lengths(\.prefix)) -> (Int \cup BOOLEAN)]
                      /\ ConditionalSourceRows[arm].suffix \in [1..\#(lengths(\.suffix)) -> (Int \cup BOOLEAN)]
                BY ONLY <1>shape, (arm \in ConditionalArms), SMT
                    DEF ConditionalSourceRows, ConditionalCompleted, ConditionalRowMaximum
            <2>sum. ConditionalSourceAdd(arm).value \in Int
                BY ONLY (arm \in ConditionalArms), <1>values, <1>addition, SMT
                    DEF ConditionalIntValues, Arithmetic!GeneratedAdd,
                        Arithmetic!Success, Arithmetic!GeneratedOverflow
            <2>middle. <<ConditionalSourceAdd(arm).value>> \in [1..1 -> (Int \cup BOOLEAN)]
                BY ONLY <2>sum, SMT
            <2>. QED BY ONLY <2>slots, <2>middle, SeqDef, SMT
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
            <2>. DEFINE \#(postState) == <<\#(primedState)>>
                          \#(writes)(\#(physicalArm), \#(physicalResult)) ==
                              IF \#(physicalArm) = 1 THEN \#(postState) = <<\#(writtenValues[0])>>
                                         ELSE \#(postState) = <<\#(writtenValues[1])>>
                          \#(defined)(\#(physicalArm)) == Arithmetic!GeneratedAddDefined(
                              ConditionalPhysicalOperands(\#(physicalArm))[1], ConditionalPhysicalOperands(\#(physicalArm))[2])
                          \#(total)(\#(physicalArm)) == ConditionalPhysicalOperands(\#(physicalArm))[1] + ConditionalPhysicalOperands(\#(physicalArm))[2]
            <2>select. (ConditionalSelectedArm = 1) <=> \#(comparison)
                BY ONLY SMT DEF ConditionalSelectedArm, ConditionalArmFor, ConditionalSourceComparison,
                    ConditionalBefore, ConditionalIntKeys, Arithmetic!CopyReferenceValue
            <2>physical. ConditionalPhysicalStep <=>
                             \#(defined)(ConditionalSelectedArm) /\ \#(writes)(ConditionalSelectedArm, \#(total)(ConditionalSelectedArm))
                BY ONLY <1>shape, <1>selector, <2>select, SMT DEF ConditionalPhysicalStep, \#(actionName),
                    \#(postState), \#(writes), \#(defined), \#(total), ConditionalPhysicalOperands, \#(operands.joined(separator: ", ")),
                    Arithmetic!GeneratedAddDefined, Arithmetic!SmallAddOperands
            <2>result. \A arm \in ConditionalArms :
                /\ (ConditionalSourceAdd(arm).ok <=> \#(defined)(arm))
                /\ (\#(defined)(arm) => ConditionalSourceAdd(arm).value = \#(total)(arm))
                BY ONLY <1>addition, SMT DEF \#(defined), \#(total), Arithmetic!GeneratedAdd,
                    Arithmetic!Success, Arithmetic!GeneratedOverflow
            <2>state. \A arm \in ConditionalArms :
                (ConditionalStateAfter = ConditionalSuccessfulState(arm)) <=> \#(writes)(arm, ConditionalSourceAdd(arm).value)
                <3>. TAKE arm \in ConditionalArms
                <3>cases. arm = 1 \/ arm = 2
                    BY ONLY (arm \in ConditionalArms), <1>shape, SMT
                <3>geometry. /\ ConditionalCompleted(arm) = \#(asTuple(\.prefix))
                             /\ ConditionalSourceRows[arm].suffix = \#(asTuple(\.suffix))
                    BY ONLY <3>cases, SMT DEF ConditionalCompleted, ConditionalSourceRows, ConditionalRowMaximum
                <3>slots. \#(conjuncts(captureSlots, indentation: 18))
                    BY ONLY (arm \in ConditionalArms), <3>cases, <3>geometry, <1>captureValues, SMT
                <3>. DEFINE \#(writtenRef)(\#(keyBinding)) == ConditionalSourceRows[arm].finalRoutes[\#(keyBinding)]
                              \#(slotValue)(\#(keyBinding)) == Arithmetic!CopyReferenceValue(
                                  ConditionalStateBefore, ConditionalSuccessfulCaptures(arm), \#(writtenRef)(\#(keyBinding)))
                <3>refs. \#(conjuncts(lookupRefs, indentation: 17))
                    BY ONLY <3>cases, SMT DEF \#(writtenRef), ConditionalSourceRows
                <3>values. \#(conjuncts(lookupValues, indentation: 19))
                    BY ONLY <3>cases, <3>refs, <3>slots, SMT DEF \#(slotValue), ConditionalStateBefore, ConditionalStateKeys,
                        Arithmetic!CopyReferenceValue
                <3>. QED BY ONLY <3>values, SMT DEF \#(writes), \#(postState), ConditionalStateKeys, ConditionalStateAfter,
                    ConditionalSuccessfulState, Arithmetic!CopyMaterializedState, \#(slotValue), \#(writtenRef)
            <2>. QED BY ONLY <1>selector, <2>physical, <2>result, <2>state, SMT
                DEF ConditionalSourceStep
        <1>noSuccessor. ~ConditionalSourceAdd(ConditionalSelectedArm).ok => ~ENABLED Next
            <2>then. ConditionalPhysicalFailure(1) => ~ENABLED Next
                BY ONLY ExpandENABLED, SMT DEF Next, \#(actionName), ConditionalPhysicalFailure, \#(failures[0])
            <2>else. ConditionalPhysicalFailure(2) => ~ENABLED Next
                BY ONLY ExpandENABLED, SMT DEF Next, \#(actionName), ConditionalPhysicalFailure, \#(failures[1])
            <2>. QED BY ONLY <1>evaluationOutcome, <1>evaluationSites, <1>shape, <2>then, <2>else, SMT
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
            BY ONLY DEF Spec, vars
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
