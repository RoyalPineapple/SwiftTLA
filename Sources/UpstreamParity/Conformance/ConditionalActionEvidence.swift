import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA
import SwiftTLACompilerSupport

package enum ConditionalActionEvidence {
    package static func prepare(sourceSHA: String, authoredSource: Data, nativeSource: Data,
        proofSource: Data, helpers: (operations: Data, checking: Data)? = nil, to directory: URL) throws {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        guard TLCReferencePin.isRevision(sourceSHA) else { throw InitialFailureEvidenceError.invalidSourceSHA }
        guard !nativeSource.contains(0), let native = String(data: nativeSource, encoding: .utf8),
              let proof = String(data: proofSource, encoding: .utf8),
              let authored = String(data: authoredSource, encoding: .utf8),
              let physical = try AuthoredCopySyntax.conditionalProofInput(
                  source: authored, modelName: String(describing: GeneratedScalarConditionalProofModel.self))?.scalarProof
        else { throw invalid }
        let parsed = GeneratedScalarConditionalProofModel.spec
        let (compilation, continuations) = try parsed.compileRetainingAtomicBranchContinuations()
        let inputs = try CompiledTypeInputs(compilation: compilation,
            types: CompiledTypeContext(enums: .init(), formalNames: [:])) {
            switch $0 {
            case "Int", "Swift.Int": .int
            case "Bool", "Swift.Bool": .bool
            default: throw invalid
            }
        }
        let program = try CompiledProgram(inputs: inputs)
        let compiledRender = try program.renderModule()
        let rendered = try GeneratedScalarConditionalProofModel.render().tlaBundle
        guard case .compiled(let identity, _, _) = rendered.provenance,
              identity == program.identity, rendered.imports.isEmpty,
              rendered.root.tla.utf8.elementsEqual(compiledRender.renderedModuleSource.utf8),
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
        var receipt = [
            "sourceSHA": sourceSHA,
            "sourceCompilationIdentity": identity.description,
            "authoredSourceSHA256": SHA256.hex(authoredSource),
            "nativeSourceSHA256": SHA256.hex(nativeSource),
            "proofTemplateSHA256": SHA256.hex(proofSource),
            "modelSHA256": SHA256.hex(model),
            "proofSHA256": SHA256.hex(generatedProof)
        ]
        var files = [
            ("authored-conditional-source.swift", authoredSource), ("native-conditional-source.swift", nativeSource),
            ("GeneratedScalarConditionalProofModel.tla", model), ("GeneratedScalarConditionalNative.tla", generatedProof)
        ]
        if let helpers {
            guard let operations = String(data: helpers.operations, encoding: .utf8),
                  let checking = String(data: helpers.checking, encoding: .utf8),
                  let cfg = rendered.root.cfg else { throw invalid }
            let sendBindingModule = "SwiftTLA\(compiledRender.moduleName)PublicSendBinding"
            let shared = try arithmeticHistoryProof(authoredSource: authored, modelName: compiledRender.moduleName,
                parsed: parsed, program: program, rendered: compiledRender, nativeSource: native,
                operations: operations, checking: checking, sendBindingModule: sendBindingModule)
            guard shared.configuration.utf8.elementsEqual(cfg.utf8),
                  shared.configured.name == shared.name + "ConfiguredProof" else { throw invalid }
            let sendBinding = try nativePublicSendBinding(native, operations: operations, checking: checking,
                module: sendBindingModule, binding: "CatalogSendBinding")
            let sharedFiles = [
                ("\(compiledRender.moduleName).cfg", Data(cfg.utf8)),
                ("\(sendBindingModule).tla", sendBinding),
                ("\(shared.name).tla", shared.bytes),
                ("\(shared.configured.name).tla", shared.configured.bytes)
            ] + ([shared.domain] + shared.arms).map { ("\($0.name).tla", $0.bytes) }
            receipt["operationsSHA256"] = SHA256.hex(helpers.operations)
            receipt["checkingSHA256"] = SHA256.hex(helpers.checking)
            for (name, data) in sharedFiles { receipt[name] = SHA256.hex(data) }
            files += sharedFiles
        }
        files.append(("conditional-preparation.json", try JSONEncoder().encode(receipt)))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in files {
            try data.write(to: directory.appendingPathComponent(name), options: .withoutOverwriting)
        }
    }

    struct ConditionalAssignmentOrigin {
        let binder: BinderID
        let target: VariableID
    }

    struct ConditionalFailureOutput {
        let history: String
        let probes: [OrderedRHSPhysicalAction.OverflowProbe]
        let historyEvents: [OrderedRHSPhysicalAction.HistoryCell]
        let aggregate: String
        let evaluationCheck: String
    }

    struct ConditionalHistoryInput {
        struct Shared {
            let integerInput: (name: String, bytes: Data)
            let scheduledReads: [AuthoredCopySyntax.ScheduledIntReads]
            let captures: [OrderedRHSPhysicalAction.Capture]
            let origins: [ConditionalAssignmentOrigin]
        }

        let shared: Shared?
        let arms: [ConditionalOverflowArm]
        let source: AuthoredCopySyntax.ConditionalInput
        let routedSelector: TLAValue
        let physical: OrderedRHSPhysicalAction.Conditional
        let native: NativeConditionalActionOutput
        let nativeComparison: TLAValue
        let nativeRows: TLAValue
        let failureOutput: ConditionalFailureOutput?
        let fields: [CompiledVariableLayout]
        let integers: [CompiledVariableLayout]
        let booleans: [CompiledVariableLayout]
        let integerKeys: Set<TLAValue>
        let integerFields: Set<String>
        let integerDomain: String
        let actionLayout: CompiledActionLayout
        let firstBodyBinder: Int
        let entryComparison: String
        let initialPredicate: String?
        let configuration: String
        let cfgProof: String
    }

    static func conditionalHistoryInput(authoredSource: String, modelName: String, parsed: TLASpec,
                                        program: CompiledProgram, rendered: RenderedModule,
                                        nativeSource: String, operations: String, checking: String) throws -> ConditionalHistoryInput {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        let (compilation, continuations) = try parsed.compileRetainingAtomicBranchContinuations(checkingBodyBinderOrdinals: true)
        guard compilation.identity == program.identity,
              modelName.utf8.elementsEqual(program.moduleName.utf8),
              modelName.utf8.elementsEqual(rendered.moduleName.utf8), rendered.imports.isEmpty,
              program.behavior.actions.count == 1, let action = program.behavior.actions.first,
              program.layout.actions.count == 1, let actionLayout = program.layout.actions.first,
              actionLayout.id == action.id,
              let continuation = continuations[actionLayout.declaration.name],
              continuation.suffixLength == 0,
              let bodyBinderOrdinals = compilation.orderedActionBodyBinderOrdinals[action.id],
              let source = try AuthoredCopySyntax.conditionalProofInput(source: authoredSource, modelName: modelName),
              source.sharedWrites.count == continuation.prefix.count,
              source.label == .string(actionLayout.declaration.name),
              let physical = OrderedRHSPhysicalAction.decodeConditional(in: rendered.renderedModuleSource,
                  action: action, program: program, retainingDefinitions: true), source.arms.count == 2,
              case .tuple(let predicate) = source.predicate, predicate.count == 3,
              predicate[0] == .string("lessThan"), let shared = physical.sharedDefinitions,
              shared.count == source.sharedWrites.count
        else { throw invalid }

        let fields = program.layout.variables
        guard source.fieldOrder.elementsEqual(parsed.variables.map(\.name), by: { $0.utf8.elementsEqual($1.utf8) }),
              parsed.variables.map(\.name).elementsEqual(fields.map(\.declaration.name), by: { $0.utf8.elementsEqual($1.utf8) }),
              Set(fields.map { $0.declaration.name }).count == fields.count,
              zip(parsed.variables, source.declarations).allSatisfy({ parsedField, sourceField in
                  sourceField.initializer?.matches(parsedField.initialization) ?? true
              }),
              zip(fields, source.declarations).allSatisfy({ field, sourceField in
                  sourceField.initializer.map { program.variableTypes[field.id] == $0.type } ?? true
              })
        else { throw invalid }
        let initialFields = zip(fields, source.declarations)
        let roles = initialFields.map { field, sourceField in sourceField.initializer?.type ?? program.variableTypes[field.id] }
        let integers = zip(fields, roles).compactMap { field, role in role == .int ? field : nil }
        let booleans = zip(fields, roles).compactMap { field, role in role == .bool ? field : nil }
        let names = Dictionary(uniqueKeysWithValues: fields.map { ($0.declaration.name, $0) })
        let keys = Set(fields.filter { program.variableTypes[$0.id] == .int }
            .map { TLAValue.string($0.declaration.name) })
        guard fields.enumerated().allSatisfy({ index, field in
                  field.id.ordinal == index && field.declaration.origin == .source
              }),
              integers.count + booleans.count == fields.count,
              let lhs = try sourceRead(predicate[1], fields: names),
              let rhs = try sourceRead(predicate[2], fields: names),
              keys.contains(.string(lhs.declaration.name)), keys.contains(.string(rhs.declaration.name))
        else { throw invalid }
        let sharedNames = try shared.map { definition in
            guard let name = program.binderNames[definition.binder], definition.rhs.resultType == .int else { throw invalid }
            return "_\(name)_\(definition.binder.ordinal)"
        }
        func selectorOperand(_ field: CompiledVariableLayout) throws -> (route: TLAValue, tokens: [String]) {
            let name = field.declaration.name
            if let i = source.sharedWrites.lastIndex(where: { $0.target.utf8.elementsEqual(name.utf8) }) {
                return (.tuple([.string("capture"), .int(i + 1)]), [sharedNames[i]])
            }
            return (.tuple([.string("state"), .string(name)]), ["state", ".", "state", ".", try nativeSourceIdentifier(name)])
        }
        let left = try selectorOperand(lhs), right = try selectorOperand(rhs)
        let routed = [TLAValue.tuple([predicate[0]]), left.route, right.route]
        guard continuation.condition == routed, physical.condition == .tuple(routed) else { throw invalid }
        let conditionWords = ["("] + left.tokens + ["<"] + right.tokens + [")"]
        try verifyConditionalHistoryHelpers(operations: operations, checking: checking,
                                            requiresSharedPrefix: !shared.isEmpty)
        let native = try nativeConditionalActionPlans(nativeSource, program: program, predicate: conditionWords)
        guard native.selectorCaptures.elementsEqual(sharedNames, by: { $0.utf8.elementsEqual($1.utf8) }) else { throw invalid }
        let nativeComparison = try conditionalNativeComparison(native.predicate, integers: integers, captures: native.selectorCaptures)
        guard nativeComparison == .tuple([predicate[0], left.route, right.route]) else { throw invalid }
        let integerFields = Set(zip(source.declarations, roles).compactMap { declaration, role in
            role == .int ? declaration.name : nil
        })
        let integerModule = "SwiftTLAArithmeticAssignmentSource" + modelName
        let integerDomain = integerModule + "Domain"
        let sharedCount = source.sharedWrites.count
        let observesFailures = [physical.sharedCaptures, physical.ifTrue.action.captures, physical.ifFalse.action.captures]
            .contains { captures in captures.contains { !$0.additionNodes.isEmpty } }
        let regions = action.body.orderedAlternativeFailureRegions
        if observesFailures {
            guard regions.count == source.arms.count,
                  regions.enumerated().allSatisfy({ arm, region in
                      region.armOrdinal == arm && region.sharedBindingCount == sharedCount
                          && region.bindings.count == sharedCount + source.arms[arm].count
                  }),
                  regions[0].bindings.prefix(sharedCount).elementsEqual(regions[1].bindings.prefix(sharedCount), by: {
                      $0.binder == $1.binder && $0.target == $1.target
                  }) else { throw invalid }
        } else {
            guard regions.isEmpty else { throw invalid }
        }
        guard physical.sharedCaptures.count == sharedCount, native.sharedPrefix.capturePlans.count == sharedCount,
              let firstDefinitions = continuation.first.definitions, firstDefinitions.count >= sharedCount else { throw invalid }
        let sourceFieldOrdinals = Dictionary(uniqueKeysWithValues: zip(source.fieldOrder, source.fieldOrder.indices))
        var expectedBinders = bodyBinderOrdinals.makeIterator()

        func bind(_ writes: [AuthoredCopySyntax.ConditionalInput.Write],
                  _ scheduled: ArraySlice<StraightLineAssignmentCheck.AtomicBranchContinuationReceipt.Definition>,
                  _ compiled: [OrderedRHSPhysicalAction.Conditional.Definition],
                  _ failureBindings: ArraySlice<(binder: BinderID, target: VariableID)>?)
            throws -> [ConditionalAssignmentOrigin] {
            guard writes.count == compiled.count, writes.count == scheduled.count,
                  failureBindings.map({ $0.count == writes.count }) ?? true else { throw invalid }
            return try zip(zip(writes, scheduled), compiled).enumerated().map { offset, entry in
                let ((write, scheduled), definition) = entry
                guard let expected = expectedBinders.next(), expected == definition.binder.ordinal,
                      scheduled.target.utf8.elementsEqual(write.target.utf8),
                      let name = program.binderNames[definition.binder], scheduled.name.utf8.elementsEqual(name.utf8),
                      let field = sourceFieldOrdinals[write.target], definition.rhs.resultType == roles[field] else { throw invalid }
                let target = fields[field].id
                if let failureBindings {
                    let binding = failureBindings[failureBindings.startIndex + offset]
                    guard binding.binder == definition.binder, binding.target == target else { throw invalid }
                }
                return .init(binder: definition.binder, target: target)
            }
        }

        let sharedOrigins = try bind(source.sharedWrites, firstDefinitions.prefix(sharedCount), shared,
                                     regions.first?.bindings.prefix(sharedCount))
        guard sharedOrigins.allSatisfy({ roles[$0.target.ordinal] == .int }) else { throw invalid }
        let sharedInput: ConditionalHistoryInput.Shared?
        if sharedCount == 0 {
            sharedInput = nil
        } else {
            let scheduled = (0..<sharedCount).map { index in
                AuthoredCopySyntax.ScheduledRHS(definition: firstDefinitions[index], compiled: shared[index],
                    target: sharedOrigins[index].target, terms: continuation.prefix[index])
            }
            let name = integerModule + "Shared"
            let rows = try source.integerPrefixProof(arm: 0, count: sharedCount, parsed: parsed,
                integerFields: integerFields, scheduled: scheduled, name: name, domain: integerDomain,
                prefix: "ConditionalSharedIntegerSource")
            sharedInput = .init(integerInput: (name, Data(rows.module.utf8)), scheduledReads: rows.scheduledReads,
                                captures: physical.sharedCaptures, origins: sharedOrigins)
        }

        let descriptors = try source.arms.enumerated().map { arm, localWrites -> ConditionalOverflowArm in
            let writes = source.sharedWrites + localWrites
            let decoded = arm == 0 ? physical.ifTrue : physical.ifFalse
            let physicalCaptures = physical.captures(in: decoded)
            let scheduled = arm == 0 ? continuation.first : continuation.second
            guard let definitions = scheduled.definitions, let localDefinitions = decoded.definitions,
                  writes.map(\.target).elementsEqual(scheduled.targets, by: { $0.utf8.elementsEqual($1.utf8) }),
                  writes.map(\.terms) == scheduled.sourceCaptures,
                  writes.count == physicalCaptures.count, writes.count == definitions.count,
                  writes.count == scheduled.captures.count,
                  scheduled.captures.prefix(sharedCount).elementsEqual(continuation.prefix),
                  definitions.prefix(sharedCount).elementsEqual(firstDefinitions.prefix(sharedCount), by: {
                      $0.name.utf8.elementsEqual($1.name.utf8) && $0.rhs == $1.rhs
                          && $0.target.utf8.elementsEqual($1.target.utf8)
                  }) else { throw invalid }
            let failureBindings = observesFailures ? regions[arm].bindings.dropFirst(sharedCount) : nil
            let localOrigins = try bind(localWrites, definitions.dropFirst(sharedCount), localDefinitions, failureBindings)
            let origins = sharedOrigins + localOrigins
            let compiled = shared + localDefinitions
            let count = origins.prefix { roles[$0.target.ordinal] == .int }.count
            let scheduledPrefix = (0..<count).map { index in
                AuthoredCopySyntax.ScheduledRHS(definition: definitions[index], compiled: compiled[index],
                    target: origins[index].target, terms: scheduled.captures[index])
            }
            let sourceName = integerModule + "Arm" + String(arm + 1)
            let sourceModule = try source.integerPrefixProof(arm: arm, count: count, parsed: parsed,
                integerFields: integerFields, scheduled: scheduledPrefix, name: sourceName, domain: integerDomain,
                prefix: integerSourcePrefixes[arm])
            let integerCaptures = Array(physicalCaptures.prefix(count))
            let suffix = try writes.indices.dropFirst(count).map { index in
                let plan = physicalCaptures[index].plan
                guard roles[origins[index].target.ordinal] == .bool, let value = conditionalLiteral(writes[index].terms),
                      case .bool = value, plan.kinds == [.string("literal")], plan.literals == [value]
                else { throw invalid }
                return value
            }
            var authoredRoutes = Dictionary(uniqueKeysWithValues: source.fields.map {
                ($0, TLAValue.tuple([.string("state"), $0]))
            })
            for (index, write) in writes.enumerated() {
                authoredRoutes[.string(write.target)] = .tuple([.string("capture"), .int(index + 1)])
            }
            let physicalRoutes = TLAValue.function(Dictionary(uniqueKeysWithValues: decoded.action.writes.map {
                (.string($0.key), $0.value)
            }))
            let targets = zip(writes, origins).map { write, origin in
                TLAValue.record(["target": .string(write.target), "field": .int(origin.target.ordinal)])
            }
            let finalRoutes = TLAValue.function(authoredRoutes)
            return .init(integerInput: (sourceName, Data(sourceModule.module.utf8)), integerCaptures: integerCaptures,
                         scheduledReads: sourceModule.scheduledReads, physicalRoutes: physicalRoutes,
                         suffix: .tuple(suffix), targets: .tuple(targets), finalRoutes: finalRoutes,
                         origins: origins)
        }
        guard expectedBinders.next() == nil,
              zip([native.ifTrue, native.ifFalse], [physical.ifTrue, physical.ifFalse]).allSatisfy({ nativeArm, physicalArm in
                  nativeArm.capturePlans.count == physical.captures(in: physicalArm).count
              }) else { throw invalid }

        let nativeRows = try zip([native.ifTrue, native.ifFalse], descriptors).map { arm, descriptor in
            try arm.integerTrace(count: descriptor.integerCaptures.count)
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
        let configuration = try rendered.configuration.render(usesSymmetryReduction: false)
        let intrinsicInvariants = Set(rendered.configuration.intrinsicInvariants)
        let failureOutput: ConditionalFailureOutput?
        let cfgProof: String
        if observesFailures {
            let history = try name("__SwiftTLAActionFailureHistory\(ordinal)")
            guard let evidence = physical.overflowProbes(in: rendered, actionOrdinal: ordinal, namedHistory: history,
                      regions: regions, program: program),
                  !evidence.sites.isEmpty, evidence.events.count == evidence.sites.count,
                  evidence.sites.allSatisfy({ probe in
                      switch probe.owner {
                      case .sharedPrefix: return probe.row > 0 && probe.row <= sharedCount
                      case .arm(let arm):
                          return descriptors.indices.contains(arm) && probe.row > sharedCount
                              && probe.row <= descriptors[arm].integerCaptures.count
                      }
                  }),
                  let selection = OrderedRHSCFGProof.normalSelection(cfg: configuration, intrinsicInvariants: intrinsicInvariants),
                  try name("__SwiftTLAEvaluationOK") == selection.checking else { throw invalid }
            failureOutput = .init(history: history, probes: evidence.sites, historyEvents: evidence.events,
                                  aggregate: evidence.aggregate, evaluationCheck: selection.checking)
            cfgProof = selection.proof
        } else {
            guard rendered.evaluationFailureDeclarations.isEmpty,
                  let selection = OrderedRHSCFGProof.normalTotalSelection(cfg: configuration,
                      intrinsicInvariants: intrinsicInvariants) else { throw invalid }
            failureOutput = nil
            cfgProof = selection
        }

        let initialClauses = initialFields.compactMap { field, sourceField in sourceField.initializer?.predicate(for: field.formalName) }
        let initialPredicate = initialClauses.count == fields.count ? initialClauses.joined(separator: " /\\ ") : nil
        return .init(shared: sharedInput, arms: descriptors, source: source,
                     routedSelector: .tuple([predicate[0], left.route, right.route]), physical: physical,
                     native: native, nativeComparison: nativeComparison, nativeRows: .tuple(nativeRows),
                     failureOutput: failureOutput, fields: fields, integers: integers, booleans: booleans,
                     integerKeys: keys, integerFields: integerFields, integerDomain: integerDomain,
                     actionLayout: actionLayout, firstBodyBinder: bodyBinderOrdinals.lowerBound,
                     entryComparison: "\(lhs.formalName) < \(rhs.formalName)", initialPredicate: initialPredicate,
                     configuration: configuration, cfgProof: cfgProof)
    }

    /// Bind the checked shared captures and each arm's integer assignments and trailing Boolean literals.
    static func arithmeticHistoryProof(authoredSource: String, modelName: String, parsed: TLASpec,
                                       program: CompiledProgram, rendered: RenderedModule,
                                       nativeSource: String, operations: String, checking: String,
                                       sendBindingModule: String = "SwiftTLAConditionalPublicSendBinding")
        throws -> (name: String, bytes: Data, configuration: String, configured: (name: String, bytes: Data),
                   arms: [(name: String, bytes: Data)], domain: (name: String, bytes: Data)) {
        let input = try conditionalHistoryInput(authoredSource: authoredSource, modelName: modelName, parsed: parsed,
            program: program, rendered: rendered, nativeSource: nativeSource, operations: operations, checking: checking)
        let proofName = "SwiftTLA" + rendered.moduleName + "ConditionalOverflowHistory"
        let proof = try conditionalAssignmentProof(name: proofName, model: rendered.moduleName, input: input)
        let configuredName = proofName + (input.initialPredicate == nil ? "ActionOnlyConfiguredProof" : "ConfiguredProof")
        let configured = conditionalConfiguredProof(name: configuredName, actionProof: proofName, cfgProof: input.cfgProof,
            initialPredicate: input.initialPredicate, actionLayout: input.actionLayout, authoredLabel: input.source.label,
            nativeAction: input.native, sendBindingModule: sendBindingModule, observesFailures: input.failureOutput != nil,
            sharedPrefix: input.shared != nil, descriptors: input.arms)
        let companions = [input.shared?.integerInput].compactMap { $0 } + input.arms.map(\.integerInput)
        return (proofName, Data(proof.utf8), input.configuration, (configuredName, Data(configured.utf8)), companions,
                (input.integerDomain, Data(AuthoredCopySyntax.conditionalIntegerDomain(
                    name: input.integerDomain, fields: input.integerFields).utf8)))
    }

    private static func conditionalNativeComparison(_ tokens: [String], integers: [CompiledVariableLayout], captures: [String]) throws
        -> TLAValue {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        let members = try integers.map { field in
            (try nativeSourceIdentifier(field.declaration.name), field.declaration.name)
        }
        func operand(_ words: ArraySlice<String>) throws -> TLAValue {
            if words.count == 1, let name = words.first,
               let slot = captures.firstIndex(where: { $0.utf8.elementsEqual(name.utf8) }) {
                return .tuple([.string("capture"), .int(slot + 1)])
            }
            guard words.count == 5, words.dropLast().elementsEqual(["state", ".", "state", "."]),
                  let token = words.last, let field = members.first(where: { $0.0.utf8.elementsEqual(token.utf8) })
            else { throw invalid }
            return .tuple([.string("state"), .string(field.1)])
        }
        guard tokens.first == "(", tokens.last == ")", let split = tokens.firstIndex(of: "<") else { throw invalid }
        return try .tuple([.string("lessThan"), operand(tokens[1..<split]), operand(tokens[(split + 1)..<(tokens.count - 1)])])
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

    private static let integerSourcePrefixes = ["ConditionalFirstIntegerSource", "ConditionalSecondIntegerSource"]

    struct ConditionalOverflowArm {
        let integerInput: (name: String, bytes: Data)
        let integerCaptures: [OrderedRHSPhysicalAction.Capture]
        let scheduledReads: [AuthoredCopySyntax.ScheduledIntReads]
        let physicalRoutes: TLAValue
        let suffix: TLAValue
        let targets: TLAValue
        let finalRoutes: TLAValue
        let origins: [ConditionalAssignmentOrigin]
        var row: TLAValue {
            .record(["suffix": suffix, "targets": targets, "finalRoutes": finalRoutes])
        }
    }

    private typealias ArmOverflowProbe = (arm: Int, site: OrderedRHSPhysicalAction.OverflowProbe)

    private static func conditionalAssignmentProof(name: String, model: String, input: ConditionalHistoryInput) throws -> String {
        let descriptors = input.arms
        let failureOutput = input.failureOutput
        let physical = input.physical
        let actionName = input.actionLayout.renderedName
        let entryIntegerTypes = input.integers.map { "\($0.formalName) \\in Int" }.joined(separator: " /\\ ")
        let state = input.fields.map(\.formalName).joined(separator: ", ")
        let integerFieldNames = TLAValue.function(Dictionary(uniqueKeysWithValues: input.integers.map {
            (TLAValue.int($0.id.ordinal), TLAValue.string($0.declaration.name))
        }))
        let types = input.integers.map { "\($0.formalName) \\in ConditionalIntValues" }
            + input.booleans.map { "\($0.formalName) \\in BOOLEAN" }
        func stateCases(_ fields: [CompiledVariableLayout], primed: Bool = false) -> String {
            fields.map { field in
                "key = \(TLAValue.string(field.declaration.name)) -> \(field.formalName)\(primed ? "'" : "")"
            }.joined(separator: " [] ")
        }
        let tables = ["ConditionalFirstIntegerTable", "ConditionalSecondIntegerTable"]
        let planNames = zip(tables, descriptors).map { table, arm in
            arm.integerCaptures.indices.map { "\(table)Plan\($0 + 1)" }
        }
        let hasPrefix = input.shared != nil
        let certified = try conditionalIntegerHistoryProof(input, tables: tables, planNames: planNames,
                                                          entryIntegerTypes: entryIntegerTypes)
        let sourceModules = ([input.integerDomain] + [input.shared?.integerInput.name].compactMap { $0 }
            + descriptors.map { $0.integerInput.name }).joined(separator: ", ")
        let probes = failureOutput?.probes ?? []
        let guards = probes.map(\.failed.name).joined(separator: ", ")
        let tableStep = conditionalTableStepProof(physical, descriptors: descriptors,
                                                 tables: tables, plans: planNames, actionName: actionName)
        let noSuccessorFacts = probes.enumerated().map { index, probe in
            #"""
            <2>probe\#(index + 1). \#(probe.failed.name) => ~ENABLED Next
                BY ONLY ExpandENABLED, SMT DEF Next, \#(actionName), \#(probe.failed.name)
            """#
        }.joined(separator: "\n    ")
        let noSuccessorLabels = probes.indices.map { "<2>probe\($0 + 1)" }.joined(separator: ", ")
        let observationDefinitions = failureOutput.map { observation in #"""
        ActualConditionalHistory == \#(observation.history)
        ConditionalSelectedEvaluationCheck == \#(observation.evaluationCheck)
        """# + "\n" } ?? ""
        let observationSteps = failureOutput.map { observation in #"""
        <1>checking. ConditionalSelectedEvaluationCheck <=>
                (\A p \in DOMAIN ConditionalProbePositions : ~ConditionalProbeGuards[p])
            BY ONLY <1>probeSlots, SMT DEF ConditionalSelectedEvaluationCheck,
                \#(observation.evaluationCheck), \#(observation.aggregate), ConditionalProbeGuards, \#(guards)
        <1>empty. ActualConditionalHistory = <<>> <=>
                (\A p \in DOMAIN ConditionalProbePositions : ~ConditionalProbeGuards[p])
            BY ONLY <1>probeOne, <1>probeNone, SMT DEF ConditionalExportedProbe
        <1>noSuccessor. ConditionalSourceHistory # <<>> => ~ENABLED Next
            \#(noSuccessorFacts)
            <2>. QED BY ONLY \#(noSuccessorLabels), <1>physicalHistory, <1>empty, <1>probeSlots, SMT
                DEF ConditionalProbeGuards, \#(guards)
        <1>sourceCheck. ConditionalSelectedEvaluationCheck <=> ConditionalSourceHistory = <<>>
            BY ONLY <1>checking, <1>empty, <1>physicalHistory, SMT
        """# + "\n" } ?? ""
        let observations = failureOutput != nil ? #"""
        ActualConditionalHistory = ConditionalSourceHistory
                  /\ ConditionalNativeHistory(TRUE) = ConditionalSourceHistory
                  /\ (ConditionalSelectedEvaluationCheck <=> ConditionalSourceHistory = <<>>)
                  /\
        """# + " " : #"""
        ConditionalSourceHistory = <<>>
                  /\ ConditionalNativeHistory(TRUE) = <<>>
                  /\
        """# + " "
        let terminal = failureOutput != nil
            ? #"          /\ (ConditionalSourceHistory # <<>> => ~ENABLED Next)"#
            : #"          /\ ConditionalIntegerTerminal(ConditionalSelectedArm).failure = <<>>"#
        let conclusion = failureOutput != nil ? #"""
        <1>. QED BY ONLY <1>physicalHistory, <1>nativeHistory, <1>sourceCheck, <1>layout,
            <1>step, <1>nativeSuccess, <1>nativeQueue, <1>noSuccessor, <1>certified, PTL
            DEF ConditionalSourceHistory, ConditionalSourceStep
        """# : #"""
        <1>. QED BY ONLY <1>layout, <1>step, <1>nativeSuccess, <1>nativeQueue,
            <1>total, <1>totalHistories, <1>certified, PTL DEF ConditionalSourceStep
        """#
        let claim = #"""
        /\ \#(observations)(ConditionalPhysicalStep <=> ConditionalSourceStep)
                  /\ (ConditionalNativeStep <=> ConditionalSourceStep)
                  /\ ConditionalNativeVisitorOutput[ConditionalSendVisitor] = ConditionalCertifiedVisitorOutput
                  /\ (Next <=> ConditionalSourceStep)
                  /\ vars = ConditionalEntry
        \#(terminal)
                  /\ ConditionalObservationUsesOrderedRows
        """#
        let entrySelector = hasPrefix ? "" : #"""
        ConditionalArmFor(comparison) ==
            LET operand(pair) == Arithmetic!CopyReferenceValue(ConditionalBefore, <<>>, pair)
            IN IF operand(comparison[2]) < operand(comparison[3]) THEN 1 ELSE 2
        ConditionalSelectedArm == ConditionalArmFor(ConditionalSourceComparison)
        """# + "\n"
        let failedPrefixResult = failureOutput == nil ? #"""
            <2>. QED BY ONLY <2>failed DEF ConditionalSharedFailureObservations
        """# : #"""
            <2>observations. ConditionalObservationUsesOrderedRows
                BY ONLY <2>failed, <1>sharedRun, (ConditionalSharedTerminal.failure # <<>>), SMT
                    DEF ConditionalObservationUsesOrderedRows
            <2>event. ConditionalSourceHistory = ConditionalSharedEvent(ConditionalSharedTerminal)
                      /\ ConditionalSourceHistory # <<>>
                BY ONLY (ConditionalSharedTerminal.failure # <<>>), SMT DEF ConditionalSourceHistory, ConditionalSharedEvent
            <2>queue. ConditionalNativeVisitorOutput[ConditionalSendVisitor] = ConditionalCertifiedVisitorOutput
                BY ONLY <2>failed, (ConditionalSharedTerminal.failure # <<>>), SMT
                    DEF ConditionalSharedFailureObservations, ConditionalCertifiedVisitorOutput
            <2>. QED BY ONLY <2>failed, <2>event, <2>queue, <2>observations, <1>layout,
                (ConditionalSharedTerminal.failure # <<>>), SMT DEF ConditionalSharedFailureObservations, ConditionalSourceStep
        """#
        let selecting = hasPrefix ? #"""
        <1>prefixFailed. ASSUME ConditionalSharedTerminal.failure # <<>>
                         PROVE \#(claim)
            <2>failed. ConditionalSharedFailureObservations
                BY ONLY <1>sharedFailure, (ConditionalSharedTerminal.failure # <<>>)
        \#(failedPrefixResult)
        <1>. SUFFICES ASSUME ConditionalSharedTerminal.failure = <<>> PROVE \#(claim)
            BY <1>prefixFailed, SMT
        <1>prefixPass. ConditionalSharedTerminal.failure = <<>> OBVIOUS
        <1>selectedPhysical. /\ ConditionalPhysicalDecision = <<ConditionalSelectedArm>>
                             /\ ConditionalNativeDecision = <<ConditionalSelectedArm>>
            BY ONLY <1>sharedDecision, <1>prefixPass, SMT DEF ConditionalSourceDecision, ConditionalSelectedArm
        <1>selector. ConditionalSelectedArm \in ConditionalArms
            BY ONLY <1>shape, <1>prefixPass, SMT DEF ConditionalSelectedArm, ConditionalSourceDecision, ConditionalArmAt
        <1>selected. ConditionalNativeSelectedArm = ConditionalSelectedArm
            BY ONLY <1>selectedPhysical, <1>prefixPass, <1>nativePrefixReach, SMT DEF ConditionalNativeSelectedArm
        """# : #"""
        <1>selector. ConditionalSelectedArm \in ConditionalArms
            BY ONLY <1>shape, SMT DEF ConditionalSelectedArm, ConditionalArmFor
        <1>comparison. ConditionalNativeComparison = ConditionalSourceComparison
            BY ONLY SMT DEF ConditionalNativeComparison, ConditionalSourceComparison
        <1>selected. ConditionalNativeSelectedArm = ConditionalSelectedArm
            BY ONLY <1>comparison, SMT DEF ConditionalNativeSelectedArm, ConditionalSelectedArm
        """#
        let comparison = hasPrefix ? physical.sharedScope(physical.predicate) : input.entryComparison
        let physicalSelector = hasPrefix ? #"""
                BY ONLY <1>selectedPhysical, <1>prefixPass, <1>sharedPasses, SMT DEF ConditionalPhysicalDecision
        """# : #"""
                BY ONLY SMT DEF ConditionalSelectedArm, ConditionalArmFor, ConditionalSourceComparison,
                    ConditionalBefore, ConditionalLayoutIntKeys, Arithmetic!CopyReferenceValue
        """#
        let readReceiptProof = descriptors.contains { !$0.scheduledReads.isEmpty } ? #"""
        THEOREM ConditionalReceiptSuppliesPhysicalRoutes ==
            \A receipt : Arithmetic!ReturnedRootAssignmentReceiptInput(receipt) =>
                Arithmetic!PhysicalAssignmentReadsMatchRoutes(receipt.rows, receipt.index, receipt.physical)
        PROOF
        <1>. TAKE receipt
        <1>. SUFFICES ASSUME Arithmetic!ReturnedRootAssignmentReceiptInput(receipt)
                      PROVE Arithmetic!PhysicalAssignmentReadsMatchRoutes(receipt.rows, receipt.index, receipt.physical)
            OBVIOUS
        <1>output. Arithmetic!ReturnedRootAssignmentReceiptOutput(receipt)
            BY ONLY (Arithmetic!ReturnedRootAssignmentReceiptInput(receipt)),
                Arithmetic!ReturnedRootAssignmentReceiptRecordSuppliesScheduledReadRoutes, SMT
        <1>. QED BY ONLY <1>output, SMT DEF Arithmetic!ReturnedRootAssignmentReceiptOutput
        """# + "\n\n" : ""
        return #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(model), TLAPS, Sequences, \#(sourceModules)
        LOCAL INSTANCE SequenceTheorems

        \#(readReceiptProof)ConditionalLayoutIntKeys == \#(TLAValue.set(input.integerKeys))
        LOCAL ConditionalIntegerFieldNames == \#(integerFieldNames)
        ConditionalIntValues == \#(TLAValue.int(Int.min))..\#(TLAValue.int(Int.max))
        ConditionalTypedState == \#(types.joined(separator: " /\\ "))
        ConditionalBefore == [key \in ConditionalLayoutIntKeys |-> CASE \#(stateCases(input.integers)) [] OTHER -> 0]
        ConditionalEntry == <<\#(state)>>
        ConditionalStateKeys == \#(TLAValue.set(input.source.fields))
        ConditionalStateBefore == [key \in ConditionalStateKeys |-> CASE \#(stateCases(input.fields)) [] OTHER -> 0]
        ConditionalStateAfter == [key \in ConditionalStateKeys |-> CASE \#(stateCases(input.fields, primed: true)) [] OTHER -> 0]
        ConditionalSourceRows == \#(TLAValue.tuple(descriptors.map(\.row)))
        ConditionalSourceComparison == \#(input.source.predicate)
        ConditionalNativeComparison == \#(input.nativeComparison)
        \#(certified.rowDefinitions)
        ConditionalSendVisitor == \#(input.native.visitor)
        ConditionalActionOrdinal == \#(input.actionLayout.id.ordinal)
        ConditionalArms == 1..Len(ConditionalSourceRows)

        \#(entrySelector)
        \#(observationDefinitions)ConditionalPhysicalStep == \#(actionName)
        \#(certified.definitions)
        \#(tableStep.definitions)

        THEOREM ActualConditionalHistoryMatchesTheAuthoredArms ==
            ASSUME ConditionalTypedState
            PROVE \#(claim)
        PROOF
        <1>shape. ConditionalArms = 1..2
            BY ONLY SMT DEF ConditionalArms, ConditionalSourceRows
        <1>layout. /\ vars = ConditionalEntry
                   /\ (Next <=> ConditionalPhysicalStep)
            BY ONLY SMT DEF vars, ConditionalEntry, Next, ConditionalPhysicalStep
        \#(certified.beforeSelection)\#(selecting)
        <1>tableStep. ConditionalPhysicalStep <=> ConditionalTableStep(ConditionalSelectedArm)
            <2>select. (ConditionalSelectedArm = 1) <=> \#(comparison)
        \#(physicalSelector)
            \#(tableStep.steps)
            <2>. QED BY ONLY <1>shape, <1>selector, <2>arm1, <2>arm2, SMT
        \#(certified.steps)
        \#(observationSteps)\#(conclusion)

        ====
        """#
    }

    private static func conditionalTableStepProof(
        _ physical: OrderedRHSPhysicalAction.Conditional, descriptors: [ConditionalOverflowArm],
        tables: [String], plans: [[String]], actionName: String
    ) -> (definitions: String, steps: String) {
        let arms = [physical.ifTrue, physical.ifFalse].enumerated().map { index, local -> (definitions: String, steps: String) in
            let arm = index + 1
            let table = tables[index]
            let name = table + "Physical"
            let captures = physical.captures(in: local)
            let integers = descriptors[index].integerCaptures
            let count = integers.count
            func scoped(_ captures: [OrderedRHSPhysicalAction.Capture], _ expression: String) -> String {
                captures.reversed().reduce(expression) { body, capture in
                    "(LET \(capture.binding) == \(capture.rhs) IN \(body))"
                }
            }
            func tuple(_ values: [String]) -> String { "<<\(values.joined(separator: ", "))>>" }
            let checked = integers.flatMap { capture in
                capture.additionNodes.map { "(\(capture.guards[$0 - 1]))" }
            }
            let passed = checked.isEmpty ? "TRUE" : "(" + checked.joined(separator: " /\\ ") + ")"
            let guards = tuple(integers.map { tuple($0.guards) })
            let widths = TLAValue.tuple(integers.map { .int($0.plan.kinds.count) })
            let physicalPlans = tuple(plans[index])
            let physicalCounts = tuple(plans[index].map { "\($0).count" })
            let countDefinitions = (["physicalCounts", name + "Widths"] + plans[index]).joined(separator: ", ")
            let prefixFacts = physical.sharedCaptures.isEmpty ? "" : "<1>prefixPass, <1>sharedPasses, "
            let prefixTable = physical.sharedCaptures.isEmpty ? "" :
                ", ConditionalSharedTable, ConditionalSharedTableValues, Arithmetic!RenderedAssignmentsPass, Arithmetic!EveryRenderedGuardPasses, "
                + physical.sharedCaptures.indices.map { "ConditionalSharedTablePlan\($0 + 1)" }.joined(separator: ", ")
            let actualIntegers = Array(captures.prefix(count))
            let actualSuffix = Array(captures.dropFirst(count))
            let integerTuple = scoped(actualIntegers, tuple(actualIntegers.map(\.binding)))
            let suffixTuple = scoped(actualSuffix, tuple(actualSuffix.map(\.binding)))
            let orderedTuple = tuple(actualIntegers.indices.map { "integerRoots[\($0 + 1)]" }
                + actualSuffix.indices.map { "booleanSuffix[\($0 + 1)]" })
            let definitions = #"""
            LOCAL \#(name)Body == \#(physical.sharedScope(local.body))
            LOCAL \#(name)Pass == \#(scoped(integers, passed))
            LOCAL \#(name)Guards == \#(scoped(integers, guards))
            LOCAL \#(name)Widths == \#(widths)
            LOCAL \#(name)Captures == \#(scoped(captures, tuple(captures.map(\.binding))))
            LOCAL \#(name)Frame == \#(scoped(captures, local.frame))
            """#
            let steps = #"""
            <2>arm\#(arm). CASE ConditionalSelectedArm = \#(arm)
                <3>selected. ConditionalPhysicalStep <=> \#(name)Body
                    BY ONLY <2>arm\#(arm), <2>select, \#(prefixFacts)SMT DEF ConditionalPhysicalStep, \#(actionName), \#(name)Body\#(prefixTable)
                <3>body. \#(name)Body <=> \#(name)Pass /\ \#(name)Frame
                    BY ONLY \#(prefixFacts)SMT DEF \#(name)Body, \#(name)Pass, \#(name)Frame\#(prefixTable)
                <3>guards. \#(name)Pass <=> Arithmetic!RenderedAssignmentsPass(\#(table), \#(count))
                    <4>column. \#(table).guards = \#(name)Guards
                        BY ONLY SMT DEF \#(table), \#(table)Values, \#(name)Guards
                    <4>widths. \A row \in 1..\#(count) : \#(table).plans[row].count = \#(name)Widths[row]
                        <5>. DEFINE physicalPlans == \#(physicalPlans)
                                    physicalCounts == \#(physicalCounts)
                        <5>plans. \#(table).plans = physicalPlans
                            BY ONLY SMT DEF \#(table), physicalPlans
                        <5>counts. physicalCounts = \#(name)Widths
                            BY ONLY SMT DEF \#(countDefinitions)
                        <5>index. \A row \in 1..\#(count) : physicalPlans[row].count = physicalCounts[row]
                            BY ONLY SMT DEF physicalPlans, physicalCounts
                        <5>. QED BY ONLY <5>plans, <5>counts, <5>index, SMT
                    <4>checked. \#(name)Pass <=>
                        \A row \in 1..\#(count) : \A node \in 1..\#(name)Widths[row] : \#(name)Guards[row][node]
                        BY ONLY SMT DEF \#(name)Pass, \#(name)Widths, \#(name)Guards
                    <4>. QED BY ONLY <4>column, <4>widths, <4>checked, SMT
                        DEF Arithmetic!RenderedAssignmentsPass, Arithmetic!EveryRenderedGuardPasses
                <3>frame. \#(name)Frame <=>
                    ConditionalStateAfter = Arithmetic!CopyMaterializedState(ConditionalStateKeys, ConditionalStateBefore,
                        \#(table).roots \o ConditionalSourceRows[\#(arm)].suffix, ConditionalPhysicalRoutes(\#(arm)))
                    <4>captures. \#(name)Captures = \#(table).roots \o ConditionalSourceRows[\#(arm)].suffix
                        <5>. DEFINE integerRoots == \#(integerTuple)
                                    booleanSuffix == \#(suffixTuple)
                                    orderedValues == \#(orderedTuple)
                                    captureValues == {orderedValues[i] : i \in 1..\#(captures.count)}
                        <5>physicalOrder. \#(name)Captures = orderedValues
                            BY ONLY SMT DEF \#(name)Captures, orderedValues, integerRoots, booleanSuffix
                        <5>rootValues. integerRoots = \#(table)Values.roots
                            BY ONLY SMT DEF integerRoots, \#(table)Values
                        <5>rootColumn. \#(table).roots = \#(table)Values.roots
                            BY ONLY DEF \#(table)
                        <5>suffixValues. booleanSuffix = ConditionalSourceRows[\#(arm)].suffix
                            BY ONLY SMT DEF booleanSuffix, ConditionalSourceRows
                        <5>integers. /\ integerRoots \in Seq(captureValues) /\ Len(integerRoots) = \#(count)
                            BY ONLY SeqDef, LenProperties, EmptySeq, SMT DEF integerRoots, captureValues, orderedValues
                        <5>booleans. /\ booleanSuffix \in Seq(captureValues) /\ Len(booleanSuffix) = \#(actualSuffix.count)
                            BY ONLY SeqDef, LenProperties, EmptySeq, SMT DEF booleanSuffix, captureValues, orderedValues
                        <5>ordered. /\ orderedValues \in Seq(captureValues) /\ Len(orderedValues) = \#(captures.count)
                            BY ONLY SeqDef, LenProperties, EmptySeq, SMT DEF orderedValues, captureValues
                        <5>concat. orderedValues = integerRoots \o booleanSuffix
                            BY ONLY <5>integers, <5>booleans, <5>ordered, ConcatProperties, SeqEqual, SMT DEF orderedValues
                        <5>. QED BY ONLY <5>physicalOrder, <5>rootValues, <5>rootColumn, <5>suffixValues, <5>concat, SMT
                    <4>physical. \#(name)Frame <=>
                        ConditionalStateAfter = Arithmetic!CopyMaterializedState(ConditionalStateKeys, ConditionalStateBefore,
                            \#(name)Captures, ConditionalPhysicalRoutes(\#(arm)))
                        BY ONLY SMT DEF \#(name)Frame, \#(name)Captures, ConditionalStateKeys, ConditionalStateBefore,
                            ConditionalStateAfter, ConditionalPhysicalRoutes, ConditionalPhysicalRouteTable,
                            Arithmetic!CopyMaterializedState, Arithmetic!CopyReferenceValue
                    <4>. QED BY ONLY <4>captures, <4>physical, SMT
                <3>. QED BY ONLY <2>arm\#(arm), <3>selected, <3>body, <3>guards, <3>frame, SMT
                    DEF ConditionalTableStep, ConditionalIntegerTable
            """#
            return (definitions, steps)
        }
        return (arms.map(\.definitions).joined(separator: "\n"), arms.map(\.steps).joined(separator: "\n    "))
    }

    private static func conditionalRawTable(_ name: String, _ captures: [OrderedRHSPhysicalAction.Capture], _ plans: [String]) -> String {
        func tuple(_ values: [String]) -> String { "<<\(values.joined(separator: ", "))>>" }
        let definitions = zip(plans, captures).map { "LOCAL \($0) == \($1.plan.integerRecord)" }
        let starts = TLAValue.tuple(captures.map { .tuple($0.starts.map(TLAValue.int)) })
        let scoped = captures.map { "(LET \($0.binding) == \($0.rhs) IN " }.joined()
        let terms = tuple(captures.map { tuple($0.terms) })
        let guards = tuple(captures.map { tuple($0.guards) })
        let roots = tuple(captures.map(\.binding))
        let closing = String(repeating: ")", count: captures.count)
        let values = name + "Values"
        return definitions.joined(separator: "\n") + "\n"
            + "LOCAL \(values) == \(scoped)[terms |-> \(terms), guards |-> \(guards), roots |-> \(roots)]\(closing)\n"
            + "\(name) == [plans |-> \(tuple(plans)), starts |-> \(starts), terms |-> \(values).terms, "
            + "guards |-> \(values).guards, roots |-> \(values).roots]"
    }

    static func conditionalSharedSelectorProof(_ input: ConditionalHistoryInput)
        -> (definitions: String, runSteps: String, decisionSteps: String) {
        let definitions = #"""
        ConditionalSharedRun ==
            CHOOSE h : /\ Arithmetic!AssignmentListHistory(FALSE, ConditionalBefore, ConditionalSharedRows, h)
                       /\ Arithmetic!AssignmentListHistory(TRUE, ConditionalBefore, ConditionalSharedRows, h)
                       /\ \A i \in 0..ConditionalSharedCount :
                             Arithmetic!AssignmentPrefixMeaning(ConditionalBefore, ConditionalSharedRows, h, i)
        ConditionalSharedTerminal == ConditionalSharedRun[ConditionalSharedCount]
        ConditionalRoutedComparison == \#(input.routedSelector)
        ConditionalArmAt(comparison, before, completed) ==
            LET operand(i) == Arithmetic!CopyReferenceValue(before, completed, comparison[i])
            IN IF operand(2) < operand(3) THEN 1 ELSE 2
        ConditionalSourceDecision ==
            IF ConditionalSharedTerminal.failure # <<>> THEN <<>>
            ELSE <<ConditionalArmAt(ConditionalSourceComparison, ConditionalSharedTerminal.bindings, <<>>)>>
        ConditionalPhysicalDecision ==
            IF Arithmetic!RenderedAssignmentsPass(ConditionalSharedTable, ConditionalSharedCount)
            THEN <<IF \#(input.physical.sharedScope(input.physical.predicate)) THEN 1 ELSE 2>>
            ELSE <<>>
        ConditionalNativeDecision ==
            IF ConditionalNativeSharedResult.failure # <<>> THEN <<>>
            ELSE <<ConditionalArmAt(ConditionalNativeComparison, ConditionalBefore, ConditionalNativeSharedResult.completed)>>
        """#
        let runSteps = #"""
        <1>sharedRun. /\ Arithmetic!AssignmentListHistory(FALSE, ConditionalBefore, ConditionalSharedRows, ConditionalSharedRun)
                      /\ Arithmetic!AssignmentListHistory(TRUE, ConditionalBefore, ConditionalSharedRows, ConditionalSharedRun)
                      /\ \A i \in 0..ConditionalSharedCount :
                            Arithmetic!AssignmentPrefixMeaning(ConditionalBefore, ConditionalSharedRows, ConditionalSharedRun, i)
            BY ONLY <1>integerEntry, <1>sharedRows, Arithmetic!CertifiedOrderedAssignmentListConstructsCompleteActionOutcome,
                SMT DEF ConditionalSharedRun
        <1>sharedReached. Arithmetic!RenderedAssignmentHistoryAt(ConditionalSharedRows, ConditionalBefore,
                              ConditionalSharedTable, ConditionalSharedRun, ConditionalSharedCount)
            BY ONLY <1>sharedRows, <1>sharedRun, <1>integerEntry, <1>sharedInventory,
                Arithmetic!PhysicalGuardedAssignmentTablesDetermineTheCompleteOutcome, SMT
        <1>sharedPasses. Arithmetic!RenderedAssignmentsPass(ConditionalSharedTable, ConditionalSharedCount) <=>
                             ConditionalSharedTerminal.failure = <<>>
            <2>bad. ~Arithmetic!RenderedAssignmentsPass(ConditionalSharedTable, ConditionalSharedCount) =>
                         \E i \in 1..ConditionalSharedCount : \E j \in 1..ConditionalSharedTable.plans[i].count :
                             Arithmetic!RenderedAssignmentFailsAt(ConditionalSharedTable, ConditionalSharedCount, i, j)
                BY ONLY <1>sharedRows, <1>sharedInventory, Arithmetic!WholeGuardTableHasAnExactFirstFailureSite, SMT
            <2>. QED BY ONLY <2>bad, <1>sharedReached, SMT
                DEF ConditionalSharedTerminal, Arithmetic!RenderedAssignmentHistoryAt, Arithmetic!RenderedAssignmentFailure
        """#
        let decisionSteps = #"""
        <1>sharedDecision. /\ ConditionalNativeDecision = ConditionalSourceDecision
                           /\ ConditionalPhysicalDecision = ConditionalSourceDecision
            <2>. DEFINE k == ConditionalSharedCount
                        rows == ConditionalSharedRows
                        raw == ConditionalSharedTable
                        t == ConditionalSharedTerminal
                        key(i) == ConditionalSourceComparison[i][2]
                        ref(i) == ConditionalRoutedComparison[i]
                        writer(i) == IF ref(i)[1] = "capture" THEN ref(i)[2] ELSE 0
            <2>cases. t.failure = <<>> =>
                /\ Len(t.completed) = k
                /\ t.bindings = Arithmetic!CompletedAssignmentBindings(ConditionalBefore, rows, t.completed)
                /\ t.completed = Arithmetic!HistoryPrefix(raw.roots, k)
                BY ONLY <1>sharedRows, <1>sharedRun, <1>sharedReached, <1>sharedPasses, SMT
                    DEF k, rows, raw, t, ConditionalSharedTerminal, Arithmetic!AssignmentPrefixMeaning,
                        Arithmetic!RenderedAssignmentHistoryAt
            <2>routes. \A i \in 2..3 :
                /\ key(i) \in ConditionalIntKeys
                /\ Arithmetic!DirectCopyRoutes(ConditionalIntKeys, rows)[k][key(i)] = ref(i)
                /\ (ref(i)[1] = "capture" => ref(i)[2] \in 1..k)
                <3>. TAKE i \in 2..3
                <3>keys. key(i) \in ConditionalIntKeys
                    BY ONLY (i \in 2..3), <1>integerKeys, SMT
                        DEF key, ConditionalSourceComparison, ConditionalLayoutIntKeys
                <3>last. Arithmetic!LastDirectCopy(rows, k, key(i), writer(i))
                    BY ONLY (i \in 2..3), <1>sharedTargets, <1>sharedRows, SMT DEF rows, k, key, ref, writer,
                        Arithmetic!LastDirectCopy, ConditionalSharedCount, ConditionalSourceComparison,
                        ConditionalRoutedComparison, ConditionalSharedIntegerSourceTargets
                <3>choice. Arithmetic!LastDirectCopy(rows, k, key(i), Arithmetic!DirectCopyWriter(rows, k, key(i)))
                    BY ONLY <3>last, SMT DEF Arithmetic!DirectCopyWriter, Arithmetic!LastDirectCopy
                <3>equal. Arithmetic!DirectCopyWriter(rows, k, key(i)) = writer(i)
                    BY ONLY <3>choice, <3>last, <1>sharedRows, Arithmetic!TwoLastDirectCopiesHaveTheSamePosition,
                        SMT DEF k
                <3>. QED BY ONLY <1>sharedRows, (i \in 2..3), <3>keys, <3>equal, <3>last, SMT
                    DEF k, rows, writer, key, ref, ConditionalSourceComparison, ConditionalRoutedComparison,
                        Arithmetic!DirectCopyRoutes, Arithmetic!DirectCopyReference, Arithmetic!LastDirectCopy
            <2>operands. t.failure = <<>> => \A i \in 2..3 :
                /\ t.bindings[key(i)] = Arithmetic!CopyReferenceValue(ConditionalBefore, t.completed, ref(i))
                /\ t.bindings[key(i)] = Arithmetic!CopyReferenceValue(ConditionalBefore, raw.roots, ref(i))
                BY ONLY <2>routes, <2>cases, <1>integerKeys, SMT DEF t, k, rows, raw,
                    Arithmetic!CompletedAssignmentBindings, Arithmetic!CopyMaterializedState,
                    Arithmetic!CopyReferenceValue, Arithmetic!HistoryPrefix
            <2>physical. (\#(input.physical.sharedScope(input.physical.predicate))) <=>
                ConditionalArmAt(ConditionalRoutedComparison, ConditionalBefore, raw.roots) = 1
                BY ONLY SMT DEF raw, ConditionalSharedTable, ConditionalSharedTableValues, ConditionalArmAt,
                    ConditionalRoutedComparison, ConditionalBefore, ConditionalLayoutIntKeys, Arithmetic!CopyReferenceValue
            <2>. QED BY ONLY <2>cases, <1>sharedPasses, <2>operands, <2>physical, <1>sharedNativeReplay, SMT
                DEF k, rows, raw, t, key, ref, ConditionalSourceDecision, ConditionalNativeDecision,
                    ConditionalPhysicalDecision, ConditionalArmAt, ConditionalRoutedComparison,
                    ConditionalNativeComparison, ConditionalSourceComparison, Arithmetic!NativeAssignmentPrefix,
                    Arithmetic!CopyReferenceValue
        """#
        return (definitions, runSteps, decisionSteps)
    }

    static func conditionalSharedInventory(_ input: ConditionalHistoryInput, nativePlanNames: [String]) throws
        -> (definitions: String, renderedSteps: String, nativeSteps: String) {
        guard let shared = input.shared, let first = input.arms.first else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }

        let sharedTable = "ConditionalSharedTable"
        let joinedTable = "ConditionalFirstIntegerTable"
        let sharedPlans = shared.captures.indices.map { "\(sharedTable)Plan\($0 + 1)" }
        let joinedPlans = first.integerCaptures.indices.map { "\(joinedTable)Plan\($0 + 1)" }
        let planDefinitions = (sharedPlans + joinedPlans).joined(separator: ", ")
        let source = "ConditionalSharedIntegerSource"
        let joinedSource = integerSourcePrefixes[0]
        let planColumns = [source, joinedSource].flatMap { name in
            ["InventoryPlan", "InventoryLiterals", "NodeCounts", "NodeKinds", "NodeLiterals",
             "NodeReadKeys", "NodeLeft", "NodeRight"].map { name + $0 }
        }.joined(separator: ", ")
        let sourceCount = shared.captures.count
        let definitions = #"""
        ConditionalSharedRows == ConditionalSharedIntegerSourceRows
        ConditionalSharedCount == \#(sourceCount)
        \#(conditionalRawTable(sharedTable, shared.captures, sharedPlans))
        """#
        let projectedColumns = ["plans", "starts", "terms", "guards", "roots"].map { column in
            let definitions: String = switch column {
            case "plans": planDefinitions
            case "starts": ""
            default: "\(sharedTable)Values, \(joinedTable)Values"
            }
            let additional = definitions.isEmpty ? "" : ", " + definitions
            return #"""
            <2>\#(column). \A i \in DOMAIN ConditionalSharedRows :
                ConditionalSharedTable.\#(column)[i] = ConditionalIntegerTable(1).\#(column)[i]
                BY ONLY <1>sharedRows, IsaM("simp"), SMT
                    DEF ConditionalIntegerTable, ConditionalSharedTable, ConditionalFirstIntegerTable\#(additional)
            """#
        }.joined(separator: "\n")

        let guardColumns = input.arms.enumerated().map { offset, path in
            let arm = offset + 1
            let table = offset == 0 ? "ConditionalFirstIntegerTable" : "ConditionalSecondIntegerTable"
            let plans = sharedPlans + path.integerCaptures.indices.prefix(sourceCount).map { "\(table)Plan\($0 + 1)" }
            return #"""
            <2>arm\#(arm). CASE arm = \#(arm)
                BY ONLY <2>arm\#(arm), <1>sharedRows, (slot \in 1..ConditionalSharedCount), SMT
                    DEF ConditionalIntegerTable, ConditionalSharedCount, ConditionalSharedTable,
                        ConditionalSharedTableValues, \#(table), \#(table)Values, \#(plans.joined(separator: ", "))
            """#
        }.joined(separator: "\n")
        let renderedSteps = #"""
        <1>sharedRows. /\ Arithmetic!SupportedAssignmentList(ConditionalSharedRows)
                       /\ ConditionalSharedCount \in Nat
                       /\ Len(ConditionalSharedRows) = ConditionalSharedCount
                       /\ DOMAIN ConditionalSharedRows = 1..ConditionalSharedCount
                       /\ DOMAIN ConditionalSharedTable.plans = DOMAIN ConditionalSharedRows
            <2>source. /\ Arithmetic!SupportedAssignmentList(ConditionalSharedRows)
                       /\ DOMAIN ConditionalSharedRows = 1..ConditionalSharedCount
                BY ONLY \#(source)AssignmentsAreSupported, \#(source)RowsProjectEmittedColumns,
                    SMT DEF ConditionalSharedRows, ConditionalSharedCount, \#(source)NodeCounts
            <2>length. /\ Len(ConditionalSharedRows) = ConditionalSharedCount /\ ConditionalSharedCount \in Nat
                BY ONLY \#(source)AssignmentsAreSupported, SMT DEF ConditionalSharedRows, ConditionalSharedCount
            <2>plans. DOMAIN ConditionalSharedTable.plans = 1..ConditionalSharedCount
                BY ONLY SMT DEF ConditionalSharedTable, ConditionalSharedCount
            <2>. QED BY ONLY <2>source, <2>length, <2>plans
        <1>sharedTargets. \A i \in DOMAIN ConditionalSharedRows :
            ConditionalSharedRows[i].target = ConditionalSharedIntegerSourceTargets[i]
            BY ONLY \#(source)RowsProjectInventoryPlans, SMT DEF ConditionalSharedRows
        <1>sharedPrefix. Arithmetic!AssignmentRhsRowsArePrefix(ConditionalIntegerRows(1), ConditionalSharedRows)
            <2>lengths. /\ Len(ConditionalIntegerRows(1)) \in Nat
                        /\ DOMAIN ConditionalIntegerRows(1) = 1..Len(ConditionalIntegerRows(1))
                        /\ ConditionalSharedCount \in 0..Len(ConditionalIntegerRows(1))
                BY ONLY <1>shape, <1>integerRows, SMT DEF ConditionalArms, ConditionalSharedCount,
                    Arithmetic!SupportedAssignmentList
            <2>projections. \A i \in DOMAIN ConditionalSharedRows :
                /\ Arithmetic!AssignmentRhsPlan(ConditionalSharedRows[i]) = \#(source)InventoryPlan(i)
                /\ Arithmetic!AssignmentRhsPlan(ConditionalIntegerRows(1)[i]) = \#(joinedSource)InventoryPlan(i)
                /\ ConditionalIntegerRows(1)[i].target = \#(joinedSource)Targets[i]
                BY ONLY <1>sharedRows, <2>lengths, \#(source)RowsProjectInventoryPlans,
                    \#(joinedSource)RowsProjectInventoryPlans, SMT DEF ConditionalSharedRows, ConditionalIntegerRows
            <2>targets. \A i \in DOMAIN ConditionalSharedRows :
                ConditionalSharedIntegerSourceTargets[i] = \#(joinedSource)Targets[i]
                BY ONLY <1>sharedRows, IsaM("simp"), SMT DEF ConditionalSharedIntegerSourceTargets, \#(joinedSource)Targets
            <2>plans. \A i \in DOMAIN ConditionalSharedRows :
                \#(source)InventoryPlan(i) = \#(joinedSource)InventoryPlan(i)
                BY ONLY <1>sharedRows, IsaM("simp"), SMT DEF \#(planColumns)
            <2>. QED BY ONLY <1>sharedRows, <1>sharedTargets, <2>lengths, <2>projections, <2>targets, <2>plans,
                SMT DEF Arithmetic!AssignmentRhsRowsArePrefix
        <1>sharedTablePrefix. Arithmetic!RenderedAssignmentTablesAgreeOnPrefix(
                ConditionalSharedRows, ConditionalIntegerTable(1), ConditionalSharedTable)
        \#(projectedColumns)
            <2>. QED BY ONLY <2>plans, <2>starts, <2>terms, <2>guards, <2>roots
                DEF Arithmetic!RenderedAssignmentTablesAgreeOnPrefix
        <1>sharedInventory. Arithmetic!RenderedAssignmentInventory(ConditionalSharedRows, ConditionalBefore, ConditionalSharedTable)
            <2>joined. Arithmetic!RenderedAssignmentInventory(ConditionalIntegerRows(1), ConditionalBefore, ConditionalIntegerTable(1))
                BY ONLY <1>shape, <1>integerInventory, SMT DEF ConditionalArms
            <2>. QED BY ONLY <1>sharedPrefix, <1>sharedTablePrefix, <2>joined,
                Arithmetic!RenderedAssignmentInventoryRestrictsToPrefix
        <1>sharedGuardColumns. \A arm \in ConditionalArms : \A slot \in 1..ConditionalSharedCount :
            /\ ConditionalIntegerTable(arm).plans[slot].count = ConditionalSharedTable.plans[slot].count
            /\ ConditionalIntegerTable(arm).guards[slot] = ConditionalSharedTable.guards[slot]
            <2>. TAKE arm \in ConditionalArms, slot \in 1..ConditionalSharedCount
            \#(guardColumns)
            <2>. QED BY ONLY <1>shape, (arm \in ConditionalArms), <2>arm1, <2>arm2, SMT
        """#
        let nativeSteps = #"""
        <1>sharedNativeInventory. \A i \in 1..Len(ConditionalSharedRows) :
            Arithmetic!PhysicalAssignmentReadsMatchRoutes(ConditionalSharedRows, i, ConditionalNativeSharedPlan.captures[i])
            <2>joined. \A i \in DOMAIN ConditionalIntegerRows(1) : Arithmetic!PhysicalAssignmentReadsMatchRoutes(
                ConditionalIntegerRows(1), i, ConditionalNativeRows[1].captures[i])
                BY ONLY <1>shape, <1>nativePlans, <1>integerInventory, SMT
                    DEF ConditionalArms, Arithmetic!RenderedAssignmentInventory
            <2>captures. \A i \in DOMAIN ConditionalSharedRows :
                ConditionalNativeSharedPlan.captures[i] = ConditionalNativeRows[1].captures[i]
                BY ONLY <1>sharedRows, IsaM("simp"), SMT DEF ConditionalNativeSharedPlan, ConditionalNativeRows,
                    \#(nativePlanNames.joined(separator: ", "))
            <2>. QED BY ONLY <2>joined, <2>captures, <1>sharedPrefix, <1>sharedRows, Arithmetic!PhysicalAssignmentReadsRestrictToPrefix
        """#
        return (definitions, renderedSteps, nativeSteps)
    }


    private static func conditionalIntegerHistoryProof(
        _ input: ConditionalHistoryInput, tables: [String], planNames: [[String]], entryIntegerTypes: String
    ) throws -> (rowDefinitions: String, definitions: String, beforeSelection: String, steps: String) {
        let arms = input.arms
        let firstBodyBinder = input.firstBodyBinder
        let failureOutput = input.failureOutput
        let probes = failureOutput?.probes ?? []
        let native = try conditionalNativeOutputProof(writeOrders: [input.native.ifTrue.writeOrder, input.native.ifFalse.writeOrder],
            nativeRows: input.nativeRows, tables: tables, planNames: planNames, sharedPrefix: input.shared != nil)
        func tuple(_ values: [String]) -> String { "<<\(values.joined(separator: ", "))>>" }

        let coordinates = tuple(probes.map { probe in
            let owner: String = switch probe.owner {
            case .sharedPrefix: "<<>>"
            case .arm(let arm): String(arm + 1)
            }
            return "<<\(owner), \(probe.row), \(probe.node)>>"
        })
        let beforeFrames = tuple(probes.map { probe in
            let captures: [OrderedRHSPhysicalAction.Capture]
            let origins: String
            switch probe.owner {
            case .sharedPrefix:
                captures = input.physical.sharedCaptures
                origins = "ConditionalSharedOrigins"
            case .arm(let arm):
                captures = arms[arm].integerCaptures
                origins = "ConditionalAssignmentOrigins(\(arm + 1))"
            }
            let prefix = captures.prefix(probe.row - 1)
            let frame = tuple(prefix.enumerated().map { index, capture in
                let origin = "\(origins)[\(index + 1)]"
                return "[binding |-> \(origin).binding, target |-> \(origin).field, value |-> \(capture.binding)]"
            })
            return prefix.reversed().reduce(frame) { body, capture in
                "(LET \(capture.binding) == \(capture.rhs) IN \(body))"
            }
        })
        let guardNames = probes.map(\.failed.name)
        let payloads = tuple(probes.map {
            #"<<"integerOverflow", \#($0.operation.name), \#($0.operands.name)>>"#
        })
        let indices = probes.indices.map { String($0 + 1) }
        let events = indices.map { "ConditionalExportedProbe(\($0))" }.joined(separator: " \\o ")
        let inactive = indices.map { "~ConditionalProbeGuards[\($0)]" }.joined(separator: " /\\ ")
        let cases = indices.map { probe in
            #"""
            <2>probe\#(probe). CASE p = \#(probe)
                BY ONLY <2>probe\#(probe), ConditionalProbeGuards[p], <1>probeUnique, <1>probeSlots, <1>probeWire,
                    <1>probeEmpty, SMT DEF ConditionalExportedHistory
            """#
        }.joined(separator: "\n    ")
        let sources = integerSourcePrefixes
        let actual = tables.indices.map { conditionalRawTable(tables[$0], arms[$0].integerCaptures, planNames[$0]) }
        let tableDefinitions = tables + planNames.flatMap { $0 }
        let evaluatedTables = (tableDefinitions + tables.map { $0 + "Values" }).joined(separator: ", ")
        let supported = sources.map { "\($0)AssignmentsAreSupported" }.joined(separator: ", ")
        func emptyArm(_ index: Int) -> String {
            #"""
            <3>arm\#(index + 1). CASE arm = \#(index + 1)
                BY ONLY <3>arm\#(index + 1), (index \in DOMAIN rows), SMT
                    DEF rows, ConditionalIntegerRows, \#(sources[index])Rows
            """#
        }
        let operandCases = sources.indices.map { index in
            guard !planNames[index].isEmpty else { return emptyArm(index) }
            let arm = index + 1
            let source = sources[index]
            let table = tables[index]
            let count = arms[index].integerCaptures.count
            let physicalPlans = tuple(planNames[index])
            let physicalPlanDefinitions = planNames[index].joined(separator: ", ")
            let columnProofs = [("count", "Counts"), ("kinds", "Kinds"), ("literals", "Literals"),
                                ("left", "Left"), ("right", "Right")].map { field, column in
                #"""
                    <4>\#(field). plan.\#(field) = \#(source)Node\#(column)[index]
                        BY ONLY <4>range, <4>physical, SMT DEF \#(physicalPlanDefinitions), \#(source)Node\#(column)
                """#
            }.joined(separator: "\n")
            return #"""
            <3>arm\#(arm). CASE arm = \#(arm)
                <4>range. index \in 1..\#(count)
                    BY ONLY <3>arm\#(arm), (index \in DOMAIN rows), \#(source)RowsProjectEmittedColumns, SMT
                        DEF rows, ConditionalIntegerRows, \#(source)NodeCounts
                <4>row. /\ rows[index].emitted.count = \#(source)NodeCounts[index]
                         /\ rows[index].emitted.nodes = \#(source)Nodes(index)
                    BY ONLY <3>arm\#(arm), (index \in DOMAIN rows), \#(source)RowsProjectEmittedColumns, SMT
                        DEF rows, ConditionalIntegerRows
                <4>physical. plan = \#(physicalPlans)[index]
                    BY ONLY <3>arm\#(arm), SMT DEF plan, raw, ConditionalIntegerTable, \#(table)
            \#(columnProofs)
                <4>. QED BY ONLY <4>row, <4>count, <4>kinds, <4>literals, <4>left, <4>right, SMT
                    DEF Arithmetic!PhysicalAssignmentOperandsMatch, Arithmetic!AssignmentRhsPlan,
                        Arithmetic!ExtractedNodePlan, \#(source)Nodes
            """#
        }.joined(separator: "\n        ")
        let routedReads = sources.indices.map { arm -> (prefixes: [String], receipt: String, proof: String) in
            let source = sources[arm]
            let table = tables[arm]
            let scheduled = arms[arm].scheduledReads
            guard !scheduled.isEmpty else { return ([], "", emptyArm(arm)) }
            let definitionNames = TLAValue.tuple(scheduled.map { .string($0.definitionName) })
            let definitionBinders = TLAValue.tuple(scheduled.map { .int($0.definitionBinder.ordinal) })
            let definitionTargets = TLAValue.tuple(scheduled.map { .int($0.definitionTarget.ordinal) })
            let loweredNames = TLAValue.tuple(scheduled.map { .tuple($0.loweredNames) })
            let loweredReadIDs = TLAValue.tuple(scheduled.map { .tuple($0.loweredReadIDs) })
            let targetColumn = table + "DefinitionTargets"
            let names = scheduled.indices.map { "\(table)SourcePrefix\($0)" }
            let prefixes = ["LOCAL \(targetColumn) == \(definitionTargets)"] + names.enumerated().map { count, name in
                count == 0
                    ? "LOCAL \(name) == Arithmetic!CopyEntryRoutes(ConditionalIntKeys)"
                    : "LOCAL \(name) == Arithmetic!CopyReplace(ConditionalIntKeys, \(names[count - 1]), "
                        + "ConditionalIntegerFieldNames[\(targetColumn)[\(count)]], <<\"capture\", \(count)>>)"
            }
            let physicalPlans = tuple(planNames[arm])
            let physicalPlanDefinitions = planNames[arm].joined(separator: ", ")
            let scheduledByOrigin = TLAValue.tuple(scheduled.map { .tuple($0.byOrigin) })
            let origins = TLAValue.tuple(scheduled.map { .tuple($0.origins.map(TLAValue.int)) })
            let readColumn = TLAValue.tuple(scheduled.map { row in
                .tuple(row.origins.map { row.byOrigin[$0 - 1] })
            })
            let receiptName = "ConditionalReturnedReceipt\(arm + 1)"
            let mapsColumn = "ConditionalReturnedMaps\(arm + 1)"
            let namesColumn = "ConditionalReturnedDefinitionNames\(arm + 1)"
            let bindersColumn = "ConditionalReturnedDefinitionBinders\(arm + 1)"
            let loweredNamesColumn = "ConditionalReturnedLoweredNames\(arm + 1)"
            let loweredIDsColumn = "ConditionalReturnedLoweredIDs\(arm + 1)"
            let scheduledColumn = "ConditionalReturnedScheduled\(arm + 1)"
            let receipt = #"""
            LOCAL \#(mapsColumn) == \#(tuple(names))
            LOCAL \#(namesColumn) == \#(definitionNames)
            LOCAL \#(bindersColumn) == \#(definitionBinders)
            LOCAL \#(loweredNamesColumn) == \#(loweredNames)
            LOCAL \#(loweredIDsColumn) == \#(loweredReadIDs)
            LOCAL \#(scheduledColumn) == \#(scheduledByOrigin)
            LOCAL \#(receiptName)(rows, index, plan) ==
                [rows |-> rows, index |-> index, physical |-> plan,
                 maps |-> \#(mapsColumn), definitionNames |-> \#(namesColumn),
                 definitionBinders |-> \#(bindersColumn), loweredNames |-> \#(loweredNamesColumn)[index],
                 loweredIDs |-> \#(loweredIDsColumn)[index], scheduled |-> \#(scheduledColumn)[index]]
            """#
            return (prefixes, receipt, #"""
            <3>arm\#(arm + 1). CASE arm = \#(arm + 1)
                <4>. DEFINE compilerReceipt == \#(receiptName)(rows, index, plan)
                <4>geometry. /\ compilerReceipt.rows = rows /\ compilerReceipt.index = index
                             /\ compilerReceipt.physical = plan
                    BY ONLY SMT DEF compilerReceipt, \#(receiptName)
                <4>input. Arithmetic!ReturnedRootAssignmentReceiptInput(compilerReceipt)
                    <5>range. Len(rows) = \#(names.count) /\ index \in 1..\#(names.count)
                        BY ONLY <3>arm\#(arm + 1), <1>integerRows, <2>shape, (arm \in ConditionalArms),
                            (index \in DOMAIN rows), SMT DEF rows
                    <5>targets. \A position \in 1..Len(rows) :
                        rows[position].target = ConditionalIntegerFieldNames[\#(targetColumn)[position]]
                        <6>source. \A position \in 1..Len(rows) : rows[position].target = \#(source)Targets[position]
                            BY ONLY <3>arm\#(arm + 1), <2>shape, \#(source)RowsProjectEmittedColumns, SMT
                                DEF rows, ConditionalIntegerRows
                        <6>compiled. \A position \in 1..Len(rows) :
                            /\ \#(targetColumn)[position] = ConditionalSourceRows[arm].targets[position].field
                            /\ ConditionalIntegerFieldNames[\#(targetColumn)[position]] = \#(source)Targets[position]
                            BY ONLY <3>arm\#(arm + 1), <5>range, SMT
                                DEF \#(targetColumn), ConditionalIntegerFieldNames, ConditionalSourceRows, \#(source)Targets
                        <6>. QED BY ONLY <6>source, <6>compiled, SMT
                    <5>. DEFINE maps == \#(mapsColumn)
                    <5>transitions. /\ maps[1] = Arithmetic!CopyEntryRoutes(ConditionalIntKeys)
                                    /\ \A position \in 1..prefixCount :
                                        maps[position + 1] = Arithmetic!CopyReplace(ConditionalIntKeys, maps[position],
                                            ConditionalIntegerFieldNames[\#(targetColumn)[position]], <<"capture", position>>)
                        BY ONLY <5>range, IsaM("simp"), SMT DEF maps, \#(mapsColumn), prefixCount, \#(names.joined(separator: ", "))
                    <5>. DEFINE scheduled == \#(scheduledColumn)
                                origins == \#(origins)
                                readColumn == \#(readColumn)
                                definitionNames == \#(namesColumn)
                                definitionBinders == \#(bindersColumn)
                                loweredNames == \#(loweredNamesColumn)
                                loweredReadIDs == \#(loweredIDsColumn)
                                kinds == \#(source)SourceOccurrenceKinds[index]
                                readKeys == \#(source)SourceOccurrenceReadKeys[index]
                                resolved == [origin \in DOMAIN kinds |->
                                    LET id == loweredReadIDs[index][origin]
                                    IN IF kinds[origin] # "read" THEN <<>>
                                       ELSE IF id[1] = "state" THEN <<"state", ConditionalIntegerFieldNames[id[2]]>>
                                       ELSE <<"capture", 1 + id[2] - definitionBinders[1]>>]
                    <5>certificate. Arithmetic!AssignmentRhsCertificate(rows[index])
                        BY ONLY <1>integerRows, (arm \in ConditionalArms), (index \in DOMAIN rows), SMT
                            DEF rows, Arithmetic!SupportedAssignmentList
                    <5>source. /\ rows[index].view.kinds = \#(source)SourceOccurrenceKinds[index]
                               /\ rows[index].view.reads = \#(source)SourceOccurrenceReadKeys[index]
                               /\ rows[index].emitted.origins = \#(source)SourceOccurrenceOrigins[index]
                               /\ Arithmetic!CompilerOccurrenceTree(rows[index].view, rows[index].emitted.count)
                        BY ONLY <3>arm\#(arm + 1), (index \in DOMAIN rows),
                            \#(source)RowsProjectSourceOccurrences, SMT DEF rows, ConditionalIntegerRows
                    <5>returnedReads. \A origin \in DOMAIN kinds :
                        LET id == loweredReadIDs[index][origin]
                            name == loweredNames[index][origin]
                            slot == 1 + id[2] - definitionBinders[1]
                        IN IF kinds[origin] # "read" THEN scheduled[index][origin] = <<>>
                           ELSE \/ /\ id[1] = "state" /\ id[2] \in DOMAIN ConditionalIntegerFieldNames
                                   /\ name = ConditionalIntegerFieldNames[id[2]] /\ name = readKeys[origin]
                                   /\ scheduled[index][origin] = <<"state", name>>
                                \/ /\ id[1] = "binding" /\ slot \in 1..(index - 1)
                                   /\ id[2] = definitionBinders[slot] /\ name = definitionNames[slot]
                                   /\ scheduled[index][origin] = <<"capture", slot>>
                        BY ONLY <5>range, SMT DEF kinds, scheduled, \#(scheduledColumn), definitionNames, \#(namesColumn), definitionBinders, \#(bindersColumn),
                            loweredNames, \#(loweredNamesColumn), loweredReadIDs, \#(loweredIDsColumn), readKeys, \#(source)SourceOccurrenceKinds, \#(source)SourceOccurrenceReadKeys,
                            ConditionalIntegerFieldNames
                    <5>readProjection. \A origin \in DOMAIN kinds : resolved[origin] = scheduled[index][origin]
                        BY ONLY <5>returnedReads, SMT DEF resolved
                    <5>acceptedReads. \A origin \in DOMAIN kinds : kinds[origin] = "read" =>
                        scheduled[index][origin] = maps[index][readKeys[origin]]
                        BY ONLY <5>range, SMT DEF scheduled, \#(scheduledColumn), kinds, readKeys, maps, \#(mapsColumn),
                            \#(source)SourceOccurrenceKinds, \#(source)SourceOccurrenceReadKeys,
                            ConditionalIntKeys, Arithmetic!CopyEntryRoutes, Arithmetic!CopyReplace,
                            ConditionalIntegerFieldNames, \#(targetColumn), \#(names.joined(separator: ", "))
                    <5>lexicalScope. /\ \A a, b \in 1..(index - 1) : definitionNames[a] = definitionNames[b] => a = b
                                      /\ \A origin \in DOMAIN kinds : kinds[origin] = "read" =>
                                             \A p \in 1..(index - 1) : definitionNames[p] # readKeys[origin]
                        <6>fresh. \A origin \in DOMAIN kinds : kinds[origin] = "read" =>
                            \A p \in 1..(index - 1) : definitionNames[p] # readKeys[origin]
                            BY ONLY <5>range, SMT DEF definitionNames, \#(namesColumn), kinds, readKeys, \#(source)SourceOccurrenceKinds,
                                \#(source)SourceOccurrenceReadKeys
                        <6>distinct. \A a, b \in 1..(index - 1) : definitionNames[a] = definitionNames[b] => a = b
                            BY ONLY <5>range, SMT DEF definitionNames, \#(namesColumn)
                        <6>. QED BY ONLY <6>fresh, <6>distinct
                    <5>physicalReads. plan.reads = \#(physicalPlans)[index].reads
                        BY ONLY <3>arm\#(arm + 1), <5>range, IsaM("simp"), SMT
                            DEF plan, raw, ConditionalIntegerTable, \#(table)
                    <5>readColumn. \#(physicalPlans)[index].reads = readColumn[index]
                        BY ONLY <5>range, SMT DEF readColumn, \#(physicalPlanDefinitions)
                    <5>originOrder. origins[index] = \#(source)SourceOccurrenceOrigins[index]
                        BY ONLY <5>range, SMT DEF origins, \#(source)SourceOccurrenceOrigins
                    <5>count. rows[index].emitted.count = \#(source)NodeCounts[index]
                        BY ONLY <3>arm\#(arm + 1), (index \in DOMAIN rows),
                            \#(source)RowsProjectEmittedColumns, SMT DEF rows, ConditionalIntegerRows
                    <5>projected. \A node \in 1..\#(source)NodeCounts[index] :
                        /\ origins[index][node] \in DOMAIN kinds
                        /\ readColumn[index][node] = scheduled[index][origins[index][node]]
                        BY ONLY <5>range, SMT DEF readColumn, scheduled, \#(scheduledColumn), origins, kinds,
                            \#(source)SourceOccurrenceKinds, \#(source)NodeCounts
                    <5>physicalOrder. \A node \in 1..rows[index].emitted.count :
                        plan.reads[node] = resolved[rows[index].emitted.origins[node]]
                        BY ONLY <5>physicalReads, <5>readColumn, <5>originOrder, <5>source, <5>count, <5>projected,
                            <5>readProjection, SMT
                    <5>. DEFINE selectedNames == loweredNames[index]
                                selectedIDs == loweredReadIDs[index]
                                selectedRoutes == scheduled[index]
                    <5>routeInput.
                        /\ Len(rows) \in Nat /\ index \in 1..Len(rows)
                        /\ maps[1] = Arithmetic!CopyEntryRoutes(ConditionalIntKeys)
                        /\ \A position \in 1..(Len(rows) - 1) :
                            maps[position + 1] = Arithmetic!CopyReplace(ConditionalIntKeys, maps[position],
                                rows[position].target, <<"capture", position>>)
                        BY ONLY <2>shape, <5>range, <5>targets, <5>transitions, SMT DEF prefixCount
                    <5>lookupInput. \A origin \in DOMAIN rows[index].view.kinds : rows[index].view.kinds[origin] = "read" =>
                        selectedRoutes[origin] = maps[index][rows[index].view.reads[origin]]
                        BY ONLY <5>acceptedReads, <5>source, SMT DEF kinds, readKeys, selectedRoutes
                    <5>scopeInput. \A origin \in DOMAIN rows[index].view.kinds : rows[index].view.kinds[origin] = "read" =>
                        LET key == rows[index].view.reads[origin]
                            name == selectedNames[origin]
                            id == selectedIDs[origin]
                            slot == 1 + id[2] - definitionBinders[1]
                        IN /\ \A p \in 1..(index - 1) : definitionNames[p] # key
                           /\ (\/ /\ id[1] = "state" /\ name = key /\ selectedRoutes[origin] = <<"state", key>>
                               \/ /\ id[1] = "binding" /\ slot \in 1..(index - 1)
                                  /\ id[2] = definitionBinders[slot] /\ name = definitionNames[slot]
                                  /\ selectedRoutes[origin] = <<"capture", slot>>)
                        BY ONLY <5>returnedReads, <5>lexicalScope, <5>source, SMT DEF kinds, readKeys, selectedNames, selectedIDs, selectedRoutes
                    <5>physicalInput. \A node \in 1..rows[index].emitted.count : rows[index].emitted.nodes[node].kind = "read" =>
                        plan.reads[node] = selectedRoutes[rows[index].emitted.origins[node]]
                        BY ONLY <5>physicalOrder, <5>readProjection, <5>projected, <5>originOrder, <5>source, <5>count,
                            SMT DEF selectedRoutes
                    <5>tableFields. /\ compilerReceipt.maps = maps
                                     /\ compilerReceipt.definitionNames = definitionNames
                                     /\ compilerReceipt.definitionBinders = definitionBinders
                        BY ONLY SMT DEF compilerReceipt, \#(receiptName), maps, definitionNames, definitionBinders
                    <5>rowFields. /\ compilerReceipt.loweredNames = selectedNames /\ compilerReceipt.loweredIDs = selectedIDs
                                   /\ compilerReceipt.scheduled = selectedRoutes
                        BY ONLY SMT DEF compilerReceipt, \#(receiptName),
                            selectedNames, selectedIDs, selectedRoutes, loweredNames, loweredReadIDs, scheduled
                    <5>geometryInput.
                        /\ Len(compilerReceipt.rows) \in Nat
                        /\ compilerReceipt.index \in 1..Len(compilerReceipt.rows)
                        /\ compilerReceipt.index \in DOMAIN compilerReceipt.rows
                        /\ Arithmetic!AssignmentRhsCertificate(compilerReceipt.rows[compilerReceipt.index])
                        /\ Arithmetic!CompilerOccurrenceTree(compilerReceipt.rows[compilerReceipt.index].view, compilerReceipt.rows[compilerReceipt.index].emitted.count)
                        /\ Arithmetic!PhysicalAssignmentOperandsMatch(compilerReceipt.rows[compilerReceipt.index], compilerReceipt.physical)
                        BY ONLY (index \in DOMAIN rows), <2>operands, <5>certificate, <5>source, <5>routeInput, <4>geometry, SMT
                    <5>routesInput.
                        /\ compilerReceipt.maps[1] = Arithmetic!CopyEntryRoutes(ConditionalIntKeys)
                        /\ \A position \in 1..(Len(compilerReceipt.rows) - 1) :
                                compilerReceipt.maps[position + 1] =
                                    Arithmetic!CopyReplace(ConditionalIntKeys, compilerReceipt.maps[position], compilerReceipt.rows[position].target, <<"capture", position>>)
                        BY ONLY <5>routeInput, <4>geometry, <5>tableFields, SMT
                    <5>freshNamesInput.
                        \A a, b \in 1..(compilerReceipt.index - 1) : compilerReceipt.definitionNames[a] = compilerReceipt.definitionNames[b] => a = b
                        BY ONLY <5>lexicalScope, <4>geometry, <5>tableFields, SMT
                    <5>lookupFieldInput.
                        \A origin \in DOMAIN compilerReceipt.rows[compilerReceipt.index].view.kinds : compilerReceipt.rows[compilerReceipt.index].view.kinds[origin] = "read" =>
                                compilerReceipt.scheduled[origin] = compilerReceipt.maps[compilerReceipt.index][compilerReceipt.rows[compilerReceipt.index].view.reads[origin]]
                        BY ONLY <5>lookupInput, <4>geometry, <5>tableFields, <5>rowFields, SMT
                    <5>scopeFieldInput.
                        \A origin \in DOMAIN compilerReceipt.rows[compilerReceipt.index].view.kinds : compilerReceipt.rows[compilerReceipt.index].view.kinds[origin] = "read" =>
                                LET key == compilerReceipt.rows[compilerReceipt.index].view.reads[origin]
                                    name == compilerReceipt.loweredNames[origin]
                                    id == compilerReceipt.loweredIDs[origin]
                                    slot == 1 + id[2] - compilerReceipt.definitionBinders[1]
                                IN /\ \A p \in 1..(compilerReceipt.index - 1) : compilerReceipt.definitionNames[p] # key
                                   /\ (\/ /\ id[1] = "state" /\ name = key /\ compilerReceipt.scheduled[origin] = <<"state", key>>
                                       \/ /\ id[1] = "binding" /\ slot \in 1..(compilerReceipt.index - 1)
                                          /\ id[2] = compilerReceipt.definitionBinders[slot] /\ name = compilerReceipt.definitionNames[slot]
                                          /\ compilerReceipt.scheduled[origin] = <<"capture", slot>>)
                        BY ONLY <5>scopeInput, <4>geometry, <5>tableFields, <5>rowFields, SMT
                    <5>physicalFieldInput.
                        \A node \in 1..compilerReceipt.rows[compilerReceipt.index].emitted.count : compilerReceipt.rows[compilerReceipt.index].emitted.nodes[node].kind = "read" =>
                                compilerReceipt.physical.reads[node] = compilerReceipt.scheduled[compilerReceipt.rows[compilerReceipt.index].emitted.origins[node]]
                        BY ONLY <5>physicalInput, <4>geometry, <5>rowFields, SMT
                    <5>. QED BY ONLY <5>geometryInput, <5>routesInput, <5>freshNamesInput,
                        <5>lookupFieldInput, <5>scopeFieldInput, <5>physicalFieldInput, PTL
                        DEF Arithmetic!ReturnedRootAssignmentReceiptInput
                <4>physical. Arithmetic!PhysicalAssignmentReadsMatchRoutes(compilerReceipt.rows, compilerReceipt.index, compilerReceipt.physical)
                    BY ONLY <4>input, ConditionalReceiptSuppliesPhysicalRoutes, SMT
                <4>. QED BY ONLY <4>physical, <4>geometry, SMT
            """#)
        }
        let ranges = arms.map { "1..\($0.integerCaptures.count)" }
        let rootCases = tables.indices.map { index in
            guard !planNames[index].isEmpty else { return emptyArm(index) }
            let arm = index + 1
            let table = tables[index]
            let range = ranges[index]
            let source = sources[index]
            let counts = tuple(arms[index].integerCaptures.map { String($0.plan.kinds.count) })
            let terminalTerms = tuple(arms[index].integerCaptures.enumerated().map { offset, capture in
                "\(table)Values.terms[\(offset + 1)][\(capture.plan.kinds.count)]"
            })
            return #"""
            <3>arm\#(arm). CASE arm = \#(arm)
                <4>range. index \in \#(range)
                    BY ONLY <3>arm\#(arm), <1>integerRows, <2>shape, (arm \in ConditionalArms), (index \in DOMAIN rows), SMT DEF rows
                <4>width. plan.count = \#(counts)[index]
                    <5>certified. plan.count = rows[index].emitted.count
                        BY ONLY <2>operands DEF Arithmetic!PhysicalAssignmentOperandsMatch, Arithmetic!AssignmentRhsPlan, Arithmetic!ExtractedNodePlan
                    <5>project. rows[index].emitted.count = \#(source)NodeCounts[index]
                        BY ONLY <3>arm\#(arm), (index \in DOMAIN rows), \#(source)RowsProjectEmittedColumns, SMT DEF rows, ConditionalIntegerRows
                    <5>. QED BY ONLY <5>certified, <5>project, SMT DEF \#(source)NodeCounts
                <4>value. \#(table)Values.roots[index] = \#(table)Values.terms[index][\#(counts)[index]]
                    <5>. DEFINE terminalTerms == \#(terminalTerms)
                    <5>tuple. \#(table)Values.roots = terminalTerms
                        BY ONLY SMT DEF terminalTerms, \#(table)Values
                    <5>index. terminalTerms[index] = \#(table)Values.terms[index][\#(counts)[index]]
                        BY ONLY <4>range, SMT DEF terminalTerms
                    <5>. QED BY ONLY <5>tuple, <5>index, SMT
                <4>. QED BY ONLY <3>arm\#(arm), <4>width, <4>value, SMT DEF raw, ConditionalIntegerTable, \#(table)
            """#
        }.joined(separator: "\n        ")
        let domainProofs = sources.indices.map { index in
            let arm = index + 1
            let source = sources[index]
            let table = tables[index]
            let range = ranges[index]
            return #"""
            <3>source\#(arm). DOMAIN \#(source)Rows = \#(range)
                BY ONLY \#(source)RowsProjectEmittedColumns, IsaM("simp"), SMT
                    DEF \#(source)NodeCounts
            <3>plans\#(arm). DOMAIN \#(table).plans = \#(range)
                BY ONLY SMT DEF \#(table)
            """#
        }.joined(separator: "\n        ")
        let renderedTermProofs = tables.indices.map { index in
            guard !planNames[index].isEmpty else { return emptyArm(index) }
            let arm = index + 1
            let table = tables[index]
            let values = table + "Values"
            let range = ranges[index]
            let captures = arms[index].integerCaptures
            let captureScope = captures.map { "(LET \($0.binding) == \($0.rhs) IN " }.joined()
            let capturedTerms = captureScope + tuple(captures.map { tuple($0.terms) })
                + String(repeating: ")", count: captures.count)
            let physicalPlans = planNames[index].joined(separator: ", ")
            func projection(_ field: String) -> String { tuple(planNames[index].map { "\($0).\(field)" }) }
            func column(_ field: KeyPath<OrderedRHSPhysicalAction.Plan, [TLAValue]>) -> TLAValue {
                .tuple(captures.map { .tuple($0.plan[keyPath: field]) })
            }
            let widths = TLAValue.tuple(captures.map { .int($0.plan.kinds.count) })
            let offsets = TLAValue.tuple(captures.map { .tuple($0.starts.map(TLAValue.int)) })
            let kinds = column(\.kinds)
            let lhs = column(\.left)
            let rhs = column(\.right)
            let literals = column(\.literals)
            let reads = column(\.reads)
            return #"""
            <3>arm\#(arm). CASE arm = \#(arm)
                <4>. DEFINE plans == \#(tuple(planNames[index]))
                            counts == \#(projection("count"))
                            tags == \#(projection("kinds"))
                            lefts == \#(projection("left"))
                            rights == \#(projection("right"))
                            literalValues == \#(projection("literals"))
                            references == \#(projection("reads"))
                            widths == \#(widths)
                            offsets == \#(offsets)
                            kinds == \#(kinds)
                            lhs == \#(lhs)
                            rhs == \#(rhs)
                            literals == \#(literals)
                            reads == \#(reads)
                <4>index. index \in \#(range)
                    BY ONLY <3>arm\#(arm), <2>shape, (index \in DOMAIN rows), IsaM("simp"), SMT
                        DEF raw, ConditionalIntegerTable, \#(table)
                <4>selected. /\ plan = plans[index]
                             /\ starts = \#(table).starts[index]
                    BY ONLY <3>arm\#(arm), SMT DEF plan, starts, raw, ConditionalIntegerTable, \#(table), plans
                <4>count. plan.count = counts[index]
                    BY ONLY <4>index, <4>selected, SMT DEF plans, counts
                <4>widths. counts = widths
                    BY ONLY SMT DEF counts, widths, \#(physicalPlans)
                <4>offsets. \#(table).starts = offsets
                    BY ONLY SMT DEF \#(table), offsets
                <4>root. /\ plan.count \in Nat \ {0}
                         /\ starts[plan.count] = 1
                    <5>geometry. /\ widths[index] \in Nat \ {0}
                                  /\ offsets[index][widths[index]] = 1
                        BY ONLY <4>index, SMT DEF widths, offsets
                    <5>. QED BY ONLY <4>selected, <4>count, <4>widths, <4>offsets, <5>geometry, SMT
                <4>planColumns. /\ plan.kinds = kinds[index]
                                /\ plan.left = lhs[index] /\ plan.right = rhs[index]
                                /\ plan.literals = literals[index] /\ plan.reads = reads[index]
                    <5>project. /\ plan.kinds = tags[index]
                                /\ plan.left = lefts[index] /\ plan.right = rights[index]
                                /\ plan.literals = literalValues[index] /\ plan.reads = references[index]
                        BY ONLY <4>index, <4>selected, SMT DEF plans, tags, lefts, rights, literalValues, references
                    <5>columns. /\ tags = kinds /\ lefts = lhs /\ rights = rhs
                                /\ literalValues = literals /\ references = reads
                        BY ONLY SMT DEF tags, lefts, rights, literalValues, references, kinds, lhs, rhs,
                            literals, reads, \#(physicalPlans)
                    <5>. QED BY ONLY <5>project, <5>columns, SMT
                <4>tree. \A node \in 1..plan.count :
                    /\ starts[node] \in 1..node
                    /\ plan.kinds[node] \in {"literal", "read", "add"}
                    /\ (plan.kinds[node] # "add" => starts[node] = node)
                    /\ (plan.kinds[node] = "add" =>
                          /\ plan.left[node] \in 1..(node - 1)
                          /\ plan.right[node] = node - 1
                          /\ starts[node] = starts[plan.left[node]]
                          /\ starts[plan.right[node]] = plan.left[node] + 1)
                    <5>geometry. \A node \in 1..widths[index] :
                        LET start == offsets[index]
                            kind == kinds[index][node]
                            leftChild == lhs[index][node]
                            rightChild == rhs[index][node]
                        IN /\ start[node] \in 1..node
                           /\ kind \in {"literal", "read", "add"}
                           /\ (kind # "add" => start[node] = node)
                           /\ (kind = "add" =>
                                  /\ leftChild \in 1..(node - 1)
                                  /\ rightChild = node - 1
                                  /\ start[node] = start[leftChild]
                                  /\ start[rightChild] = leftChild + 1)
                        BY ONLY <4>index, SMT DEF widths, offsets, kinds, lhs, rhs
                    <5>. QED BY ONLY <4>selected, <4>count, <4>widths, <4>offsets, <4>planColumns, <5>geometry, SMT
                <4>values. \A node \in 1..plan.count :
                    /\ terms[node] \in Int
                    /\ (plan.kinds[node] = "literal" => terms[node] = plan.literals[node])
                    /\ (plan.kinds[node] = "read" =>
                          terms[node] = Arithmetic!PhysicalRhsBindings(plan, ConditionalBefore, completed)[node])
                    /\ (plan.kinds[node] = "add" => terms[node] = terms[plan.left[node]] + terms[plan.right[node]])
                    <5>terms. /\ terms = \#(values).terms[index]
                              /\ completed = Arithmetic!HistoryPrefix(\#(values).roots, index - 1)
                        BY ONLY <3>arm\#(arm), SMT DEF terms, completed, raw, ConditionalIntegerTable, \#(table)
                    <5>. TAKE node \in 1..plan.count
                    <5>bound. node \in 1..widths[index]
                        BY ONLY (node \in 1..plan.count), <4>count, <4>widths
                    <5>integer. \#(values).terms[index][node] \in Int
                        <6>. DEFINE capturedTerms == \#(capturedTerms)
                        <6>projected. \#(values).terms = capturedTerms
                            BY ONLY SMT DEF \#(values), capturedTerms
                        <6>entry. \#(entryIntegerTypes)
                            BY ONLY ConditionalTypedState, SMT DEF ConditionalTypedState, ConditionalIntValues
                        <6>typed. capturedTerms[index][node] \in Int
                            BY ONLY <4>index, <5>bound, <6>entry, SMT DEF capturedTerms, widths
                        <6>. QED BY ONLY <6>projected, <6>typed, SMT
                    <5>literal. kinds[index][node] = "literal" =>
                        \#(values).terms[index][node] = literals[index][node]
                        BY ONLY <4>index, <5>bound, SMT DEF \#(values), widths, kinds, literals
                    <5>reference. kinds[index][node] = "read" =>
                        \#(values).terms[index][node] = Arithmetic!CopyReferenceValue(ConditionalBefore,
                            Arithmetic!HistoryPrefix(\#(values).roots, index - 1), reads[index][node])
                        BY ONLY <4>index, <5>bound, SMT DEF \#(values), widths, kinds, reads,
                            ConditionalBefore, ConditionalLayoutIntKeys, Arithmetic!HistoryPrefix, Arithmetic!CopyReferenceValue
                    <5>read. plan.kinds[node] = "read" =>
                        terms[node] = Arithmetic!PhysicalRhsBindings(plan, ConditionalBefore, completed)[node]
                        BY ONLY <5>reference, <5>terms, <4>planColumns, (node \in 1..plan.count), SMT
                            DEF Arithmetic!PhysicalRhsBindings
                    <5>sum. kinds[index][node] = "add" =>
                        LET actual == \#(values).terms[index]
                        IN actual[node] = actual[lhs[index][node]] + actual[rhs[index][node]]
                        BY ONLY <4>index, <5>bound, SMT DEF \#(values), widths, kinds, lhs, rhs
                    <5>. QED BY ONLY <4>planColumns, <5>terms, <5>integer, <5>literal, <5>read, <5>sum, SMT
                <4>. QED BY ONLY <4>root, <4>tree, <4>values, SMT DEF Arithmetic!RenderedRhsTerms, starts, terms
            """#
        }.joined(separator: "\n        ")
        let targetsProofs = sources.indices.map { index in
            let arm = index + 1
            let source = sources[index]
            let range = ranges[index]
            return #"""
            <3>authored\#(arm). /\ DOMAIN \#(source)Rows = \#(range)
                            /\ \A i \in DOMAIN \#(source)Rows :
                                   \#(source)Rows[i].target = \#(source)Targets[i]
                BY ONLY \#(source)RowsProjectEmittedColumns, IsaM("simp"), SMT
                    DEF \#(source)NodeCounts
            <3>. DEFINE writes\#(arm) == \#(arms[index].targets)
            <3>project\#(arm). ConditionalSourceRows[\#(arm)].targets = writes\#(arm)
                BY ONLY IsaM("simp") DEF ConditionalSourceRows, writes\#(arm)
            <3>keys\#(arm). \A i \in \#(range) : writes\#(arm)[i].target = \#(source)Targets[i]
                BY ONLY SMT DEF writes\#(arm), \#(source)Targets
            <3>arm\#(arm). CASE arm = \#(arm)
                BY ONLY <3>arm\#(arm), <3>authored\#(arm), <3>project\#(arm), <3>keys\#(arm), SMT
                    DEF rows, ConditionalIntegerRows
            """#
        }.joined(separator: "\n        ")
        let probeSites = tables.indices.map { index in
            probes.indices.filter { probes[$0].owner == .sharedPrefix || probes[$0].owner == .arm(index) }
        }
        let probeWitnesses = probeSites.enumerated().map { index, sites in
            let probeByCoordinate = Dictionary(uniqueKeysWithValues: sites.map {
                ([probes[$0].row, probes[$0].node], $0 + 1)
            })
            return TLAValue.tuple(arms[index].integerCaptures.enumerated().map { row, capture in
                .tuple(capture.plan.kinds.indices.map { node in .int(probeByCoordinate[[row + 1, node + 1]] ?? 0) })
            })
        }
        let guardProofs = tables.indices.map { index in
            guard !planNames[index].isEmpty else { return emptyArm(index) }
            let arm = index + 1
            let source = sources[index]
            let table = tables[index]
            let plans = planNames[index]
            let values = table + "Values"
            let planDefinitions = plans.joined(separator: ", ")
            let sites = probeSites[index]
            let addCase: String
            if sites.isEmpty {
                addCase = #"""
                            <6>add. CASE actualPlan.kinds[node] = "add"
                                BY ONLY <6>add, <4>range, (node \in 1..actualPlan.count), SMT
                                    DEF actualPlan, \#(planDefinitions)
                """#
            } else {
                let places = sites.map { String($0 + 1) }.joined(separator: ", ")
                let operandDefinitions = sites.map { ", " + probes[$0].operands.name }.joined()
                let position = input.shared == nil ? "<<arm, index, node>>" : "ConditionalJoinedProbePosition(arm, index, node)"
                let positionDefinitions = input.shared == nil ? "" : ", ConditionalJoinedProbePosition, ConditionalSharedCount"
                addCase = #"""
                            <6>add. CASE actualPlan.kinds[node] = "add"
                                <7>location. /\ node \in 1..\#(source)NodeCounts[index]
                                             /\ \#(source)NodeKinds[index][node] = "add"
                                    BY ONLY <6>add, (node \in 1..actualPlan.count), <2>operands, <4>project, <4>sourceColumns, SMT
                                        DEF expected, Arithmetic!PhysicalAssignmentOperandsMatch
                                <7>. DEFINE p == \#(probeWitnesses[index])[index][node]
                                <7>site. /\ p \in {\#(places)} /\ p \in DOMAIN ConditionalProbePositions
                                          /\ ConditionalProbePositions[p] = \#(position)
                                    BY ONLY <7>location, <3>arm\#(arm), <4>range, SMT
                                        DEF p, \#(source)NodeCounts, \#(source)NodeKinds, ConditionalProbePositions\#(positionDefinitions)
                                <7>. DEFINE operands == ConditionalProbePayloads[p][3]
                                <7>left. operands[1] = actualTerms[\#(source)NodeLeft[index][node]]
                                    BY ONLY <7>site, SMT DEF operands, actualTerms, \#(source)NodeLeft,
                                        ConditionalProbePositions, ConditionalProbePayloads, \#(values)\#(operandDefinitions)
                                <7>right. operands[2] = actualTerms[\#(source)NodeRight[index][node]]
                                    BY ONLY <7>site, SMT DEF operands, actualTerms, \#(source)NodeRight,
                                        ConditionalProbePositions, ConditionalProbePayloads, \#(values)\#(operandDefinitions)
                                <7>indices. /\ actualPlan.left[node] = \#(source)NodeLeft[index][node]
                                            /\ actualPlan.right[node] = \#(source)NodeRight[index][node]
                                    BY ONLY <7>location, <2>operands, <4>project, <4>sourceColumns, SMT
                                        DEF expected, Arithmetic!PhysicalAssignmentOperandsMatch
                                <7>physical. actualGuards[node] = physicalBounds(operands[1], operands[2])
                                    BY ONLY <7>site, SMT DEF operands, actualGuards, ConditionalProbePositions, ConditionalProbePayloads,
                                        \#(values), physicalBounds\#(operandDefinitions)
                                <7>. QED BY ONLY <6>add, <7>indices, <7>left, <7>right, <7>physical, <3>bound, SMT
                """#
            }
            return #"""
            <3>arm\#(arm). CASE arm = \#(arm)
                <4>range. index \in 1..\#(plans.count)
                    BY ONLY <3>arm\#(arm), (arm \in ConditionalArms), (index \in DOMAIN rows),
                        <1>integerRows, <2>shape, SMT DEF rows
                <4>. DEFINE actualPlan == \#(tuple(plans))[index]
                            actualTerms == \#(values).terms[index]
                            actualGuards == \#(values).guards[index]
                <4>project. /\ plan = actualPlan
                            /\ raw.terms[index] = actualTerms /\ raw.guards[index] = actualGuards
                    BY ONLY <3>arm\#(arm), IsaM("simp"), SMT
                        DEF plan, raw, actualPlan, actualTerms, actualGuards, ConditionalIntegerTable, \#(table)
                <4>sourceColumns. /\ expected.count = \#(source)NodeCounts[index]
                                  /\ \A j \in 1..expected.count :
                                         /\ expected.kinds[j] = \#(source)NodeKinds[index][j]
                                         /\ expected.left[j] = \#(source)NodeLeft[index][j]
                                         /\ expected.right[j] = \#(source)NodeRight[index][j]
                    <5>row. /\ rows[index].emitted.count = \#(source)NodeCounts[index]
                            /\ rows[index].emitted.nodes = \#(source)Nodes(index)
                        BY ONLY <3>arm\#(arm), (index \in DOMAIN rows), \#(source)RowsProjectEmittedColumns, SMT
                            DEF rows, ConditionalIntegerRows
                    <5>. QED BY ONLY <5>row, SMT DEF expected, Arithmetic!AssignmentRhsPlan,
                        Arithmetic!ExtractedNodePlan, \#(source)Nodes
                <4>checked. Arithmetic!RenderedRhsGuards(actualPlan, actualTerms, actualGuards)
                    <5>nodes. \A node \in 1..actualPlan.count :
                             actualGuards[node] =
                                (IF actualPlan.kinds[node] = "add"
                                 THEN Arithmetic!GeneratedAddDefined(actualTerms[actualPlan.left[node]],
                                                                      actualTerms[actualPlan.right[node]])
                                 ELSE TRUE)
                        <6>. TAKE node \in 1..actualPlan.count
                        <6>other. CASE actualPlan.kinds[node] # "add"
                            <7>coordinate. /\ node \in 1..\#(source)NodeCounts[index]
                                           /\ \#(source)NodeKinds[index][node] # "add"
                                BY ONLY <6>other, (node \in 1..actualPlan.count), <2>operands, <4>project, <4>sourceColumns, SMT
                                    DEF expected, Arithmetic!PhysicalAssignmentOperandsMatch
                            <7>guardValue. actualGuards[node] = TRUE
                                BY ONLY <4>range, <7>coordinate, SMT DEF actualGuards, \#(values),
                                    \#(source)NodeCounts, \#(source)NodeKinds
                            <7>. QED BY ONLY <6>other, <7>guardValue, SMT
            \#(addCase)
                        <6>. QED BY ONLY <6>other, <6>add
                    <5>. QED BY ONLY <5>nodes DEF Arithmetic!RenderedRhsGuards
                <4>. QED BY ONLY <4>project, <4>checked
            """#
        }.joined(separator: "\n        ")
        let selectedObservation = failureOutput != nil
            ? #"           /\ ActualConditionalHistory = ConditionalOrderedFailure(arm, terminal)"# + "\n"
            : #"           /\ terminal.failure = <<>>"# + "\n"
        func origins(_ bindings: [ConditionalAssignmentOrigin]) -> TLAValue {
            .tuple(bindings.map { .record(["binding": .int($0.binder.ordinal), "field": .int($0.target.ordinal)]) })
        }
        let originDefinitions = input.shared.map { shared in #"""
        ConditionalSharedOrigins == \#(origins(shared.origins))
        ConditionalAssignmentOrigins(arm) == \#(TLAValue.tuple(arms.map { origins($0.origins) }))[arm]
        """# } ?? #"""
        ConditionalAssignmentOrigins(arm) ==
            LET writes == ConditionalSourceRows[arm].targets
                start == \#(firstBodyBinder) + (IF arm = 1 THEN 0 ELSE Len(ConditionalSourceRows[1].targets))
            IN [i \in DOMAIN writes |-> [binding |-> start + (i - 1), field |-> writes[i].field]]
        """#
        let rowDefinitions = #"""
        \#(actual.joined(separator: "\n"))
        \#(routedReads.flatMap(\.prefixes).joined(separator: "\n"))
        \#(routedReads.map(\.receipt).filter { !$0.isEmpty }.joined(separator: "\n"))
        ConditionalIntegerRows(arm) ==
            IF arm = 1 THEN \#(sources[0])Rows ELSE \#(sources[1])Rows
        ConditionalIntegerTable(arm) ==
            IF arm = 1 THEN \#(tables[0]) ELSE \#(tables[1])
        \#(originDefinitions)
        ConditionalFailurePrefix(arm, completed) ==
            [i \in DOMAIN completed |->
                LET origin == ConditionalAssignmentOrigins(arm)[i]
                IN [binding |-> origin.binding, target |-> origin.field, value |-> completed[i]]]
        ConditionalLabeledFailure(arm, row, payload, completed) ==
            LET origin == ConditionalAssignmentOrigins(arm)[row]
            IN <<[source |-> ConditionalEntry, action |-> ConditionalActionOrdinal, branch |-> arm - 1,
                  site |-> origin.binding, target |-> origin.field, payload |-> payload,
                  before |-> ConditionalFailurePrefix(arm, completed)]>>
        ConditionalOrderedFailure(arm, terminal) ==
            IF terminal.failure = <<>> THEN <<>>
            ELSE ConditionalLabeledFailure(arm, terminal.failure.site, terminal.failure.payload, terminal.completed)

        """# + "\n"
        let physicalCellNames = indices.map { "ConditionalPhysicalHistoryCell\($0)" }
        let physicalEventNames = indices.map { "ConditionalPhysicalEvent\($0)" }
        let physicalEvents = failureOutput?.historyEvents ?? []
        let physicalCellDefinitions = zip(physicalCellNames, physicalEvents).map {
            "LOCAL \($0) == \($1.body)"
        } + zip(physicalEventNames, physicalEvents).map {
            "LOCAL \($0) == \($1.event)"
        }
        let physicalHistory = physicalCellNames.joined(separator: " \\o ")
        let entry = tuple(input.fields.map(\.formalName))
        let wireCells = try zip(probes, physicalEvents).enumerated().map { offset, pair in
            let (probe, physicalEvent) = pair
            let index = offset + 1
            let cell = physicalCellNames[offset]
            let event = physicalEventNames[offset]
            let owner: String
            let origins: [ConditionalAssignmentOrigin]
            let originOperator: String
            switch probe.owner {
            case .sharedPrefix:
                owner = "<<>>"
                guard let shared = input.shared else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
                origins = shared.origins
                originOperator = "ConditionalSharedOrigins"
            case .arm(let arm):
                owner = String(arm + 1)
                origins = arms[arm].origins
                originOperator = "ConditionalAssignmentOrigins(\(owner))"
            }
            let originDefinitions = input.shared == nil
                ? "ConditionalAssignmentOrigins, ConditionalSourceRows" : "ConditionalSharedOrigins, ConditionalAssignmentOrigins"
            let ownerName = input.shared == nil ? "arm" : "owner"
            let selectedOrigin = input.shared == nil ? "ConditionalAssignmentOrigins(arm)" : "ConditionalProbeOrigins(owner)"
            let branch = input.shared == nil ? "arm - 1" : #"IF owner = <<>> THEN <<>> ELSE owner - 1"#
            let branchDefinition = input.shared == nil ? "" : "\n            branch == \(branch)"
            let branchValue = input.shared == nil ? branch : "branch"
            let joinDefinitions = input.shared == nil ? "" : ", ConditionalProbeOrigins"
            let originFacts = origins.prefix(probe.row).enumerated().map { position, origin in
                "\(originOperator)[\(position + 1)] = [binding |-> \(origin.binder.ordinal), field |-> \(origin.target.ordinal)]"
            }
            guard originFacts.count == probe.row, let siteOrigin = originFacts.last else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            let priorOrigins = originFacts.dropLast()
            let beforeOrigins: String
            if priorOrigins.isEmpty {
                beforeOrigins = ""
            } else {
                let claim = priorOrigins.count == 1 ? priorOrigins[priorOrigins.startIndex] :
                    priorOrigins.map { "/\\ " + $0 }.joined(separator: "\n                    ")
                beforeOrigins = #"""
                        <4>origins. \#(claim)
                            BY ONLY SMT DEF \#(originDefinitions)

                """#
            }
            let beforeFacts = priorOrigins.isEmpty ? "" : "<4>origins, "
            let block = #"""
            <2>cell\#(index). \#(cell) = ConditionalExportedProbe(\#(index))
                <3>physical. \#(cell) =
                    IF \#(probe.failed.name) THEN \#(event) ELSE <<>>
                    BY ONLY SMT DEF \#(cell), \#(probe.failed.name), \#(event)
                <3>payload. \#(event) =
                    LET place == ConditionalProbePositions[\#(index)]
                        \#(ownerName) == place[1]
                        origin == \#(selectedOrigin)[place[2]]\#(branchDefinition)
                    IN <<[source |-> ConditionalEntry, action |-> ConditionalActionOrdinal, branch |-> \#(branchValue),
                          site |-> origin.binding, target |-> origin.field, payload |-> ConditionalProbePayloads[\#(index)],
                          before |-> ConditionalProbeBefore[\#(index)]]>>
                    <4>position. ConditionalProbePositions[\#(index)] = <<\#(owner), \#(probe.row), \#(probe.node)>>
                        BY ONLY SMT DEF ConditionalProbePositions
                    <4>labels. /\ ConditionalEntry = \#(entry)
                               /\ ConditionalActionOrdinal = \#(input.actionLayout.id.ordinal)
                               /\ \#(siteOrigin)
                        BY ONLY SMT DEF ConditionalEntry, ConditionalActionOrdinal, \#(originDefinitions)
                    <4>operands. ConditionalProbePayloads[\#(index)] = \#(physicalEvent.payload)
                        BY ONLY SMT DEF ConditionalProbePayloads, \#(probe.operation.name), \#(probe.operands.name)
            \#(beforeOrigins)        <4>before. ConditionalProbeBefore[\#(index)] = \#(physicalEvent.before)
                        BY ONLY \#(beforeFacts)SMT DEF ConditionalProbeBefore
                    <4>. QED BY ONLY <4>position, <4>labels, <4>operands, <4>before, SMT DEF \#(event)\#(joinDefinitions)
                <3>. QED BY ONLY <3>physical, <3>payload, SMT DEF ConditionalExportedProbe, ConditionalProbeGuards
            """#
            return "    " + block.replacingOccurrences(of: "\n", with: "\n    ")
        }.joined(separator: "\n")
        let wireCellFacts = indices.map { "<2>cell\($0)" }.joined(separator: ", ")
        let probeWire = failureOutput.map { observation in #"""
        <1>probeWire. ActualConditionalHistory = ConditionalExportedHistory
            <2>actual. ActualConditionalHistory = \#(physicalHistory)
                BY ONLY SMT DEF ActualConditionalHistory, \#(observation.history), \#(physicalCellNames.joined(separator: ", "))
        \#(wireCells)
            <2>. QED BY ONLY <2>actual, \#(wireCellFacts), SMT DEF ConditionalExportedHistory
        """# } ?? ""
        let exportedProbe = input.shared == nil ? #"""
        LOCAL ConditionalExportedProbe(p) ==
            LET place == ConditionalProbePositions[p]
                arm == place[1]
                origin == ConditionalAssignmentOrigins(arm)[place[2]]
            IN IF ConditionalProbeGuards[p] THEN
                <<[source |-> ConditionalEntry, action |-> ConditionalActionOrdinal, branch |-> arm - 1,
                  site |-> origin.binding, target |-> origin.field, payload |-> ConditionalProbePayloads[p],
                  before |-> ConditionalProbeBefore[p]]>>
               ELSE <<>>
        """# : #"""
        LOCAL ConditionalJoinedProbePosition(arm, row, node) ==
            <<IF row <= ConditionalSharedCount THEN <<>> ELSE arm, row, node>>
        LOCAL ConditionalProbeTable(owner) ==
            IF owner = <<>> THEN ConditionalSharedTable ELSE ConditionalIntegerTable(owner)
        LOCAL ConditionalProbeCount(owner) ==
            IF owner = <<>> THEN ConditionalSharedCount ELSE Len(ConditionalIntegerRows(owner))
        LOCAL ConditionalProbeOrigins(owner) ==
            IF owner = <<>> THEN ConditionalSharedOrigins ELSE ConditionalAssignmentOrigins(owner)
        LOCAL ConditionalProbeFailurePrefix(owner, completed) ==
            LET origins == ConditionalProbeOrigins(owner)
            IN [i \in DOMAIN completed |->
                LET origin == origins[i]
                IN [binding |-> origin.binding, target |-> origin.field, value |-> completed[i]]]
        LOCAL ConditionalExportedProbe(p) ==
            LET place == ConditionalProbePositions[p]
                owner == place[1]
                origin == ConditionalProbeOrigins(owner)[place[2]]
                branch == IF owner = <<>> THEN <<>> ELSE owner - 1
            IN IF ConditionalProbeGuards[p] THEN
                <<[source |-> ConditionalEntry, action |-> ConditionalActionOrdinal, branch |-> branch,
                  site |-> origin.binding, target |-> origin.field, payload |-> ConditionalProbePayloads[p],
                  before |-> ConditionalProbeBefore[p]]>>
               ELSE <<>>
        """#
        let probeDefinitions = failureOutput != nil ? #"""
        LOCAL ConditionalProbePositions == \#(coordinates)
        LOCAL ConditionalProbeGuards == \#(tuple(guardNames))
        LOCAL ConditionalProbePayloads == \#(payloads)
        LOCAL ConditionalProbeBefore == \#(beforeFrames)
        \#(exportedProbe)
        LOCAL ConditionalExportedHistory == \#(events)
        \#(physicalCellDefinitions.joined(separator: "\n"))
        """# + "\n" : ""
        var sharedFailureSteps = ""
        var prefixDefinitions = ""
        var failureObservation = ""
        var beforeSelection = ""
        if let shared = input.shared {
            let inventory = try conditionalSharedInventory(input, nativePlanNames: Array(native.captureNames[0].prefix(shared.captures.count)))
            let selector = conditionalSharedSelectorProof(input)
            let failure = try conditionalSharedFailureProof(native: input.native, sharedCount: shared.captures.count,
                guardNames: probes.map(\.failed.name),
                overflow: failureOutput.map { (aggregate: $0.aggregate, evaluationCheck: $0.evaluationCheck) },
                actionName: input.actionLayout.renderedName,
                tableDefinitions: ["ConditionalSharedTableValues"] + shared.captures.indices.map { "ConditionalSharedTablePlan\($0 + 1)" })
            prefixDefinitions = [inventory.definitions, failure.planDefinitions, selector.definitions,
                "ConditionalSelectedArm == ConditionalSourceDecision[1]", failure.collectorDefinitions].joined(separator: "\n") + "\n"
            failureObservation = failure.observationDefinition + "\n"
            beforeSelection = [inventory.renderedSteps, selector.runSteps, native.inventorySteps, inventory.nativeSteps,
                failure.inventorySteps, selector.decisionSteps].joined(separator: "\n") + "\n"
            // The shared failure case consumes the same single emitted probe sequence as the selected-arm case.
            sharedFailureSteps = failure.failureSteps
        }
        let sourceHistoryGate = input.shared == nil ? "" :
            "IF ConditionalSharedTerminal.failure # <<>> THEN ConditionalSharedEvent(ConditionalSharedTerminal) ELSE "
        let sourceStepGate = input.shared == nil ? "" :
            "IF ConditionalSharedTerminal.failure # <<>> THEN FALSE ELSE "
        let historyGate = input.shared == nil ? "" : #"""
            IF ConditionalSharedTerminal.failure # <<>> THEN
                /\ Arithmetic!AssignmentListHistory(FALSE, ConditionalBefore, ConditionalSharedRows, ConditionalSharedRun)
                /\ Arithmetic!AssignmentListHistory(TRUE, ConditionalBefore, ConditionalSharedRows, ConditionalSharedRun)
                /\ ConditionalSharedFailureObservations
            ELSE
        """# + "\n"
        let routeDefinitions = #"""
        LOCAL ConditionalPhysicalRouteTable == \#(TLAValue.tuple(arms.map(\.physicalRoutes)))
        LOCAL ConditionalPhysicalRoutes(arm) == ConditionalPhysicalRouteTable[arm]
        ConditionalTableStep(arm) ==
            LET raw == ConditionalIntegerTable(arm)
                row == ConditionalSourceRows[arm]
            IN /\ Arithmetic!RenderedAssignmentsPass(raw,
                      IF arm = 1 THEN \#(arms[0].integerCaptures.count) ELSE \#(arms[1].integerCaptures.count))
               /\ ConditionalStateAfter = Arithmetic!CopyMaterializedState(ConditionalStateKeys, ConditionalStateBefore,
                      raw.roots \o row.suffix, ConditionalPhysicalRoutes(arm))
        \#(native.definitions)
        \#(failureObservation)ConditionalOrderedStep(arm, terminal) ==
            terminal.failure = <<>> /\ ConditionalStateAfter = ConditionalSourceSuccessor(arm, terminal)
        ConditionalSourceHistory == \#(sourceHistoryGate)ConditionalOrderedFailure(ConditionalSelectedArm, ConditionalIntegerTerminal(ConditionalSelectedArm))
        ConditionalSourceStep == \#(sourceStepGate)ConditionalOrderedStep(ConditionalSelectedArm, ConditionalIntegerTerminal(ConditionalSelectedArm))
        ConditionalObservationUsesOrderedRows ==
        \#(historyGate)    LET arm == ConditionalSelectedArm
                rows == ConditionalIntegerRows(arm)
            IN \E history :
                LET terminal == history[Len(rows)]
                IN /\ Arithmetic!AssignmentListHistory(FALSE, ConditionalBefore, rows, history)
                   /\ Arithmetic!AssignmentListHistory(TRUE, ConditionalBefore, rows, history)
        \#(selectedObservation)           /\ ConditionalNativeHistory(TRUE) = ConditionalOrderedFailure(arm, terminal)
                   /\ (ConditionalPhysicalStep <=> ConditionalOrderedStep(arm, terminal))
                   /\ (ConditionalNativeStep <=> ConditionalOrderedStep(arm, terminal))
        """#
        let rowSteps = #"""
        <1>integerKeys. /\ ConditionalIntKeys = ConditionalLayoutIntKeys
                         /\ \#(sources[0])Fields = ConditionalLayoutIntKeys
                         /\ \#(sources[1])Fields = ConditionalLayoutIntKeys
            BY ONLY SMT DEF ConditionalIntKeys, ConditionalLayoutIntKeys,
                \#(sources[0])Fields, \#(sources[1])Fields
        <1>integerEntry. ConditionalBefore \in Arithmetic!AssignmentBindings
            BY ONLY ConditionalTypedState, <1>integerKeys, SMT DEF ConditionalTypedState, ConditionalBefore,
                ConditionalLayoutIntKeys, ConditionalIntValues, Arithmetic!AssignmentBindings, Arithmetic!AssignmentIntValues
        <1>integerRows. \A arm \in ConditionalArms :
            LET rows == ConditionalIntegerRows(arm)
                raw == ConditionalIntegerTable(arm)
            IN /\ Arithmetic!SupportedAssignmentList(rows)
               /\ Len(rows) = IF arm = 1 THEN \#(arms[0].integerCaptures.count) ELSE \#(arms[1].integerCaptures.count)
               /\ DOMAIN rows = DOMAIN raw.plans
               /\ \A i \in DOMAIN rows : rows[i].target = ConditionalSourceRows[arm].targets[i].target
            <2>. TAKE arm \in ConditionalArms
            <2>. DEFINE rows == ConditionalIntegerRows(arm)
                        raw == ConditionalIntegerTable(arm)
            <2>cases. arm = 1 \/ arm = 2
                BY ONLY <1>shape, (arm \in ConditionalArms), SMT
            <2>support. Arithmetic!SupportedAssignmentList(rows)
                BY ONLY <2>cases, \#(supported), SMT DEF rows, ConditionalIntegerRows
            <2>length. Len(rows) = IF arm = 1 THEN \#(arms[0].integerCaptures.count) ELSE \#(arms[1].integerCaptures.count)
                BY ONLY <2>cases, \#(supported), SMT DEF rows, ConditionalIntegerRows
            <2>domains. DOMAIN rows = DOMAIN raw.plans
                \#(domainProofs)
                <3>source. DOMAIN rows = IF arm = 1 THEN \#(ranges[0]) ELSE \#(ranges[1])
                    BY ONLY <2>cases, <3>source1, <3>source2, SMT DEF rows, ConditionalIntegerRows
                <3>physical. DOMAIN raw.plans = IF arm = 1 THEN \#(ranges[0]) ELSE \#(ranges[1])
                    BY ONLY <2>cases, <3>plans1, <3>plans2, SMT DEF raw, ConditionalIntegerTable
                <3>. QED BY ONLY <3>source, <3>physical
            <2>targets. \A i \in DOMAIN rows : rows[i].target = ConditionalSourceRows[arm].targets[i].target
                \#(targetsProofs)
                <3>. QED BY ONLY <2>cases, <3>arm1, <3>arm2, SMT
            <2>. QED BY ONLY <2>support, <2>length, <2>domains, <2>targets
        <1>integerInventory. \A arm \in ConditionalArms :
            Arithmetic!RenderedAssignmentInventory(ConditionalIntegerRows(arm), ConditionalBefore,
                                                    ConditionalIntegerTable(arm))
            <2>. TAKE arm \in ConditionalArms
            <2>. DEFINE rows == ConditionalIntegerRows(arm)
                        raw == ConditionalIntegerTable(arm)
            <2>cases. arm = 1 \/ arm = 2
                BY ONLY <1>shape, (arm \in ConditionalArms), SMT
            <2>shape. /\ Len(rows) \in Nat /\ DOMAIN rows = 1..Len(rows)
                      /\ DOMAIN rows = DOMAIN raw.plans
                BY ONLY <1>integerRows, (arm \in ConditionalArms), SMT DEF rows, raw, Arithmetic!SupportedAssignmentList
            <2>. SUFFICES \A index \in DOMAIN rows :
                 LET plan == raw.plans[index]
                 IN /\ Arithmetic!PhysicalAssignmentReadsMatchRoutes(rows, index, plan)
                    /\ Arithmetic!RenderedRhsTerms(plan, ConditionalBefore, Arithmetic!HistoryPrefix(raw.roots, index - 1),
                                                   raw.starts[index], raw.terms[index])
                    /\ Arithmetic!RenderedRhsGuards(plan, raw.terms[index], raw.guards[index])
                    /\ raw.roots[index] = raw.terms[index][plan.count]
                BY DEF rows, raw, Arithmetic!RenderedAssignmentInventory
            <2>. TAKE index \in DOMAIN rows
            <2>. DEFINE plan == raw.plans[index]
                        expected == Arithmetic!AssignmentRhsPlan(rows[index])
                        completed == Arithmetic!HistoryPrefix(raw.roots, index - 1)
            <2>operands. Arithmetic!PhysicalAssignmentOperandsMatch(rows[index], plan)
                \#(operandCases)
                <3>. QED BY ONLY <2>cases, <3>arm1, <3>arm2
            <2>matches. Arithmetic!PhysicalAssignmentReadsMatchRoutes(rows, index, plan)
                <3>. DEFINE prefixCount == Len(rows) - 1
                \#(routedReads.map(\.proof).joined(separator: "\n        "))
                <3>. QED BY ONLY <2>cases, <3>arm1, <3>arm2, SMT
            <2>terms. Arithmetic!RenderedRhsTerms(plan, ConditionalBefore, completed, raw.starts[index], raw.terms[index])
                <3>. DEFINE starts == raw.starts[index]
                            terms == raw.terms[index]
                \#(renderedTermProofs)
                <3>. QED BY ONLY <2>cases, <3>arm1, <3>arm2, SMT
            <2>guards. Arithmetic!RenderedRhsGuards(plan, raw.terms[index], raw.guards[index])
                <3>. DEFINE physicalBounds(lhs, rhs) ==
                    IF (lhs >= -1000000000 /\ lhs <= 1000000000 /\ rhs >= -1000000000 /\ rhs <= 1000000000)
                    THEN TRUE
                    ELSE IF rhs > 0 THEN lhs <= \#(TLAValue.int(Int.max)) - rhs
                    ELSE IF rhs < 0 THEN lhs >= \#(TLAValue.int(Int.min)) - rhs ELSE TRUE
                <3>bound. \A lhs, rhs : physicalBounds(lhs, rhs) = Arithmetic!GeneratedAddDefined(lhs, rhs)
                    BY ONLY SMT DEF physicalBounds, Arithmetic!GeneratedAddDefined, Arithmetic!SmallAddOperands
                \#(guardProofs)
                <3>. QED BY ONLY <2>cases, <3>arm1, <3>arm2
            <2>roots. raw.roots[index] = raw.terms[index][plan.count]
                \#(rootCases)
                <3>. QED BY ONLY <2>cases, <3>arm1, <3>arm2
            <2>. QED BY ONLY <2>matches, <2>terms, <2>guards, <2>roots DEF plan, completed
        """# + "\n"
        let sharedPlanNames = input.physical.sharedCaptures.indices.map { "ConditionalSharedTablePlan\($0 + 1)" }
        let sharedPhysicalTables = (["ConditionalSharedTable"] + sharedPlanNames + tableDefinitions)
            .joined(separator: ", ")
        let sharedEvaluatedTables = sharedPhysicalTables + ", ConditionalSharedTableValues, "
            + tables.map { $0 + "Values" }.joined(separator: ", ")
        let hasPrefix = input.shared != nil
        let probePosition = hasPrefix ? "ConditionalJoinedProbePosition(arm, row, node)" : "<<arm, row, node>>"
        let inventoryClaim = #"""
        \A arm \in ConditionalArms :
            LET raw == ConditionalIntegerTable(arm)
                count == Len(ConditionalIntegerRows(arm))
            IN \A row \in 1..count : \A node \in 1..raw.plans[row].count :
               raw.plans[row].kinds[node] = "add" =>
                   \E p \in DOMAIN ConditionalProbePositions : ConditionalProbePositions[p] = \#(probePosition)
        """#
        let inventoryLevel = hasPrefix ? "<3>" : "<2>"
        let columnLevel = hasPrefix ? "<4>" : "<3>"
        let witnessLevel = hasPrefix ? "<5>" : "<4>"
        let probeInventoryCases = tables.indices.map { index in
            let arm = index + 1
            let table = tables[index]
            let plans = planNames[index]
            let captures = arms[index].integerCaptures
            let widthColumn = TLAValue.tuple(captures.map { .int($0.plan.kinds.count) })
            let kindColumn = TLAValue.tuple(captures.map { .tuple($0.plan.kinds) })
            let planDefinitions = (["actualPlans", "widths", "kinds"] + plans).joined(separator: ", ")
            let position = hasPrefix ? "ConditionalJoinedProbePosition(\(arm), row, node)" : "<<\(arm), row, node>>"
            let positionDefinitions = hasPrefix ? ", ConditionalJoinedProbePosition, ConditionalSharedCount" : ""
            if captures.isEmpty {
                return #"""
                    \#(inventoryLevel)arm\#(arm). CASE arm = \#(arm)
                        BY ONLY \#(inventoryLevel)arm\#(arm), \#(inventoryLevel)length, SMT
                """#
            }
            return #"""
                \#(inventoryLevel)arm\#(arm). CASE arm = \#(arm)
                    \#(columnLevel). DEFINE actualPlans == \#(tuple(plans))
                                widths == \#(widthColumn)
                                kinds == \#(kindColumn)
                                witnesses == \#(probeWitnesses[index])
                    \#(columnLevel)physical. raw.plans = actualPlans
                        BY ONLY \#(inventoryLevel)arm\#(arm), IsaM("simp"), SMT
                            DEF raw, ConditionalIntegerTable, \#(table), actualPlans
                    \#(columnLevel)columns. \A row \in 1..\#(captures.count) :
                                  /\ actualPlans[row].count = widths[row]
                                  /\ actualPlans[row].kinds = kinds[row]
                        BY ONLY SMT DEF \#(planDefinitions)
                    \#(columnLevel)coverage. \A row \in 1..\#(captures.count) : \A node \in 1..widths[row] :
                        kinds[row][node] = "add" =>
                           \E p \in DOMAIN ConditionalProbePositions :
                              ConditionalProbePositions[p] = \#(position)
                        \#(witnessLevel). TAKE row \in 1..\#(captures.count)
                        \#(witnessLevel). TAKE node \in 1..widths[row]
                        \#(witnessLevel). SUFFICES ASSUME kinds[row][node] = "add" PROVE
                            \E p \in DOMAIN ConditionalProbePositions :
                               ConditionalProbePositions[p] = \#(position)
                            BY SMT
                        \#(witnessLevel). DEFINE p == witnesses[row][node]
                        \#(witnessLevel)site. /\ p \in 1..\#(probes.count)
                                 /\ ConditionalProbePositions[p] = \#(position)
                            BY ONLY (row \in 1..\#(captures.count)), (node \in 1..widths[row]),
                                (kinds[row][node] = "add"), SMT
                                DEF p, widths, kinds, witnesses, ConditionalProbePositions\#(positionDefinitions)
                        \#(witnessLevel). QED BY ONLY <1>probeSlots, \#(witnessLevel)site, SMT
                    \#(columnLevel). QED BY ONLY \#(inventoryLevel)arm\#(arm), \#(inventoryLevel)length, \#(columnLevel)physical, \#(columnLevel)columns, \#(columnLevel)coverage, SMT
            """#
        }.joined(separator: "\n")
        let inventoryProof = #"""
            \#(inventoryLevel). TAKE arm \in ConditionalArms
            \#(inventoryLevel). DEFINE raw == ConditionalIntegerTable(arm)
                        count == Len(ConditionalIntegerRows(arm))
            \#(inventoryLevel)cases. arm = 1 \/ arm = 2
                BY ONLY <1>shape, (arm \in ConditionalArms), SMT
            \#(inventoryLevel)length. count = IF arm = 1 THEN \#(arms[0].integerCaptures.count) ELSE \#(arms[1].integerCaptures.count)
                BY ONLY (arm \in ConditionalArms), <1>integerRows, SMT DEF count
        \#(probeInventoryCases)
            \#(inventoryLevel). QED BY ONLY \#(inventoryLevel)cases, \#(inventoryLevel)arm1, \#(inventoryLevel)arm2, SMT
        """#
        let probeValues = failureOutput.map { _ in
            let shared = input.shared != nil
            let owner = shared ? "owner" : "arm"
            let rawTable = shared ? "ConditionalProbeTable(owner)" : "ConditionalIntegerTable(arm)"
            let sourceRows = shared
                ? "IF owner = <<>> THEN ConditionalSharedRows ELSE ConditionalIntegerRows(owner)"
                : "ConditionalIntegerRows(arm)"
            let frame = shared ? "ConditionalProbeFailurePrefix(owner, completed)" : "ConditionalFailurePrefix(arm, completed)"
            let tableSelectors = shared ? "ConditionalProbeTable, ConditionalIntegerTable" : "ConditionalIntegerTable"
            let frameDefinitions = shared
                ? "ConditionalProbeFailurePrefix, ConditionalProbeOrigins, ConditionalSharedOrigins, ConditionalAssignmentOrigins"
                : "ConditionalFailurePrefix, ConditionalAssignmentOrigins, ConditionalSourceRows"
            let payloadCases = probes.enumerated().map { index, probe in
                let position = index + 1
                let ownerValue: String
                let table: String
                let plan: String
                let capture: OrderedRHSPhysicalAction.Capture
                let row = probe.row
                let node = probe.node
                switch probe.owner {
                case .sharedPrefix:
                    ownerValue = "<<>>"
                    table = "ConditionalSharedTable"
                    plan = sharedPlanNames[row - 1]
                    capture = input.physical.sharedCaptures[row - 1]
                case .arm(let arm):
                    ownerValue = String(arm + 1)
                    table = tables[arm]
                    plan = planNames[arm][row - 1]
                    capture = arms[arm].integerCaptures[row - 1]
                }
                let values = table + "Values"
                let left = capture.plan.left[node - 1]
                let right = capture.plan.right[node - 1]
                return #"""
                <3>probe\#(position). CASE p = \#(position)
                    <4>coordinate. /\ \#(owner) = \#(ownerValue) /\ row = \#(row) /\ node = \#(node)
                        BY ONLY <3>probe\#(position), SMT DEF place, \#(owner), row, node, ConditionalProbePositions
                    <4>columns. /\ raw.plans[row] = \#(plan)
                                 /\ raw.terms[row] = \#(values).terms[\#(row)]
                        BY ONLY <4>coordinate, SMT DEF raw, \#(tableSelectors), \#(table)
                    <4>indices. /\ raw.plans[row].left[node] = \#(left)
                                 /\ raw.plans[row].right[node] = \#(right)
                        BY ONLY <4>coordinate, <4>columns, SMT DEF \#(plan)
                    <4>pair. \#(probe.operands.name) =
                        <<\#(values).terms[\#(row)][\#(left)], \#(values).terms[\#(row)][\#(right)]>>
                        <5>scope. \#(probe.operands.name) = <<\#(probe.operands.name)[1], \#(probe.operands.name)[2]>>
                            BY ONLY SMT DEF \#(probe.operands.name)
                        <5>left. \#(probe.operands.name)[1] = \#(values).terms[\#(row)][\#(left)]
                            BY ONLY SMT DEF \#(probe.operands.name), \#(values)
                        <5>right. \#(probe.operands.name)[2] = \#(values).terms[\#(row)][\#(right)]
                            BY ONLY SMT DEF \#(probe.operands.name), \#(values)
                        <5>. QED BY ONLY <5>scope, <5>left, <5>right, SMT
                    <4>header. ConditionalProbePayloads[p] = <<"integerOverflow", "addition", \#(probe.operands.name)>>
                        BY ONLY <3>probe\#(position), SMT DEF ConditionalProbePayloads, \#(probe.operation.name)
                    <4>. QED BY ONLY <4>columns, <4>indices, <4>pair, <4>header, SMT
                        DEF failure, Arithmetic!RenderedAssignmentFailure, Arithmetic!RenderedTermOverflow, Arithmetic!GeneratedOverflow
                """#
            }.joined(separator: "\n        ")
            let payloadFacts = indices.map { "<3>probe\($0)" }.joined(separator: ", ")
            return #"""
            <1>probeValues. \A p \in DOMAIN ConditionalProbePositions :
                ConditionalProbeGuards[p] =>
                    LET place == ConditionalProbePositions[p]
                        \#(owner) == place[1]
                        row == place[2]
                        node == place[3]
                        raw == \#(rawTable)
                        rows == \#(sourceRows)
                        completed == Arithmetic!HistoryPrefix(raw.roots, row - 1)
                        failure == Arithmetic!RenderedAssignmentFailure(rows, ConditionalBefore, raw, row, node)
                    IN /\ ConditionalProbePayloads[p] = failure.payload
                       /\ ConditionalProbeBefore[p] = \#(frame)
                <2>. TAKE p \in DOMAIN ConditionalProbePositions
                <2>. DEFINE place == ConditionalProbePositions[p]
                            \#(owner) == place[1]
                            row == place[2]
                            node == place[3]
                            raw == \#(rawTable)
                            rows == \#(sourceRows)
                            completed == Arithmetic!HistoryPrefix(raw.roots, row - 1)
                            failure == Arithmetic!RenderedAssignmentFailure(rows, ConditionalBefore, raw, row, node)
                <2>payload. ConditionalProbePayloads[p] = failure.payload
                    <3>domain. p \in 1..\#(probes.count)
                        BY ONLY <1>probeSlots, (p \in DOMAIN ConditionalProbePositions), SMT
                \#(payloadCases)
                    <3>. QED BY ONLY <3>domain, \#(payloadFacts), SMT
                <2>before. ConditionalProbeGuards[p] => ConditionalProbeBefore[p] = \#(frame)
                    BY ONLY <1>probeSlots, <1>probeReach, (p \in DOMAIN ConditionalProbePositions), SMT
                        DEF completed, raw, row, \#(owner), place, ConditionalProbePositions, ConditionalProbeBefore,
                            \#(tableSelectors), \#(frameDefinitions), Arithmetic!HistoryPrefix,
                            \#(shared ? sharedEvaluatedTables : evaluatedTables)
                <2>. QED BY ONLY <2>payload, <2>before, SMT DEF failure, completed, rows, raw, node, row, \#(owner), place
            """#
        } ?? ""
        func armProbeReachSteps() throws -> String {
            let rowCounts = tuple(arms.map { String($0.integerCaptures.count) })
            let widths = tuple(arms.map { tuple($0.integerCaptures.map { String($0.plan.kinds.count) }) })
            let widthCases = sources.enumerated().map { index, source in
                let arm = index + 1
                return #"""
                            <4>arm\#(arm). CASE a = \#(arm)
                                BY ONLY <4>arm\#(arm), (i \in DOMAIN rows), \#(source)RowsProjectEmittedColumns, SMT
                                    DEF rows, ConditionalIntegerRows, widths, \#(source)NodeCounts
                """#
            }.joined(separator: "\n")
            let reachCases = try probes.enumerated().map { index, probe in
                guard case .arm(let armIndex) = probe.owner else {
                    throw InitialFailureEvidenceError.unsupportedGeneratedOutput
                }
                let place = index + 1
                let arm = armIndex + 1
                let row = probe.row
                let node = probe.node
                let captures = arms[armIndex].integerCaptures
                let table = tables[armIndex]
                let values = table + "Values"
                func guardCell(_ row: Int, _ node: Int) -> String { "\(values).guards[\(row)][\(node)]" }
                let priorGuards = captures.prefix(row - 1).enumerated().flatMap { index, capture in
                    capture.guards.indices.map { guardCell(index + 1, $0 + 1) }
                }
                let earlierNodes = captures[row - 1].guards.indices.prefix(node - 1).map { guardCell(row, $0 + 1) }
                let prior = priorGuards.isEmpty ? "TRUE" : priorGuards.joined(separator: " /\\ ")
                let rejected = (earlierNodes + ["~" + guardCell(row, node)]).joined(separator: " /\\ ")
                return #"""
                    <2>probe\#(place). CASE p = \#(place)
                    <3>. DEFINE earlierRows == \#(prior)
                                rejectedNode == \#(rejected)
                    <3>coordinates. /\ place = <<\#(arm), \#(row), \#(node)>>
                                     /\ arm \in ConditionalArms /\ raw = \#(table)
                        BY ONLY <2>probe\#(place), <1>shape, SMT DEF place, arm, raw, ConditionalProbePositions, ConditionalIntegerTable
                    <3>columns. /\ count = rowCounts[\#(arm)]
                                 /\ raw.guards = \#(values).guards
                                 /\ \A i \in 1..rowCounts[\#(arm)] : raw.plans[i].count = widths[\#(arm)][i]
                        BY ONLY <3>coordinates, <2>dimensions, SMT DEF arm, raw, count, \#(table)
                    <3>bounds. /\ \#(row) \in 1..count /\ \#(node) \in 1..raw.plans[\#(row)].count
                        BY ONLY <3>columns, SMT DEF rowCounts, widths
                    <3>prior. Arithmetic!RenderedAssignmentsPass(raw, \#(row - 1)) <=> earlierRows
                        BY ONLY <3>columns, SMT DEF rowCounts, widths, earlierRows,
                            Arithmetic!RenderedAssignmentsPass, Arithmetic!EveryRenderedGuardPasses
                    <3>first. Arithmetic!FirstRejectedRenderedGuard(raw.guards[\#(row)], raw.plans[\#(row)].count, \#(node)) <=> rejectedNode
                        BY ONLY <3>columns, <3>bounds, SMT DEF rowCounts, widths, rejectedNode,
                            Arithmetic!FirstRejectedRenderedGuard, Arithmetic!EveryRenderedGuardPasses
                    <3>observed. ConditionalProbeGuards[p] <=> (arm = ConditionalSelectedArm /\ earlierRows /\ rejectedNode)
                        BY ONLY <2>probe\#(place), <2>selection, <3>coordinates, SMT DEF arm, ConditionalProbeGuards,
                            earlierRows, rejectedNode, \#(values), \#(probe.failed.name)
                    <3>. QED BY ONLY <3>coordinates, <3>bounds, <3>prior, <3>first, <3>observed, SMT
                        DEF arm, Arithmetic!RenderedAssignmentFailsAt
                """#
            }.joined(separator: "\n")
            let reachLabels = indices.map { "<2>probe" + $0 }.joined(separator: ", ")
            return #"""
            <1>probeReach. \A p \in DOMAIN ConditionalProbePositions :
                LET place == ConditionalProbePositions[p]
                    arm == place[1]
                    raw == ConditionalIntegerTable(arm)
                    count == Len(ConditionalIntegerRows(arm))
                IN /\ arm \in ConditionalArms
                   /\ place[2] \in 1..count /\ place[3] \in 1..raw.plans[place[2]].count
                   /\ (ConditionalProbeGuards[p] <=> arm = ConditionalSelectedArm /\
                       Arithmetic!RenderedAssignmentFailsAt(raw, count, place[2], place[3]))
                <2>. TAKE p \in DOMAIN ConditionalProbePositions
                <2>. DEFINE place == ConditionalProbePositions[p]
                            arm == place[1]
                            raw == ConditionalIntegerTable(arm)
                            count == Len(ConditionalIntegerRows(arm))
                            rowCounts == \#(rowCounts)
                            widths == \#(widths)
                <2>selection. ConditionalSelectedArm = (IF \#(input.entryComparison) THEN 1 ELSE 2)
                    BY ONLY SMT DEF ConditionalSelectedArm, ConditionalArmFor, ConditionalSourceComparison,
                        ConditionalBefore, ConditionalLayoutIntKeys, Arithmetic!CopyReferenceValue
                <2>dimensions. \A a \in ConditionalArms :
                    LET table == ConditionalIntegerTable(a)
                    IN /\ Len(ConditionalIntegerRows(a)) = rowCounts[a]
                       /\ \A i \in 1..rowCounts[a] : table.plans[i].count = widths[a][i]
                    <3>. TAKE a \in ConditionalArms
                    <3>. DEFINE rows == ConditionalIntegerRows(a)
                                table == ConditionalIntegerTable(a)
                    <3>shape. /\ Len(rows) = rowCounts[a] /\ DOMAIN rows = 1..rowCounts[a]
                        BY ONLY <1>shape, (a \in ConditionalArms), <1>integerRows, SMT
                            DEF rows, rowCounts, Arithmetic!SupportedAssignmentList
                    <3>inventory. Arithmetic!RenderedAssignmentInventory(rows, ConditionalBefore, table)
                        BY ONLY (a \in ConditionalArms), <1>integerInventory, SMT DEF rows, table
                    <3>physicalCounts. \A i \in DOMAIN rows : table.plans[i].count = rows[i].emitted.count
                        <4>. TAKE i \in DOMAIN rows
                        <4>operands. Arithmetic!PhysicalAssignmentOperandsMatch(rows[i], table.plans[i])
                            BY ONLY (i \in DOMAIN rows), <3>inventory, SMT
                                DEF Arithmetic!RenderedAssignmentInventory, Arithmetic!PhysicalAssignmentReadsMatchRoutes
                        <4>. QED BY ONLY <4>operands DEF Arithmetic!PhysicalAssignmentOperandsMatch,
                            Arithmetic!AssignmentRhsPlan, Arithmetic!ExtractedNodePlan
                    <3>sourceCounts. \A i \in DOMAIN rows : rows[i].emitted.count = widths[a][i]
                        <4>. TAKE i \in DOMAIN rows
            \#(widthCases)
                        <4>. QED BY ONLY (a \in ConditionalArms), <1>shape, <4>arm1, <4>arm2, SMT
                    <3>. QED BY ONLY <3>shape, <3>physicalCounts, <3>sourceCounts, SMT DEF rows, table
            \#(reachCases)
                <2>. QED BY ONLY (p \in DOMAIN ConditionalProbePositions), <1>probeSlots, \#(reachLabels), SMT
                    DEF place, arm, raw, count
            """#
        }
        let ownerSteps = try failureOutput.map { _ in
            if input.shared != nil {
                return #"""
                <1>probeInventory.
                    /\ \A row \in 1..ConditionalSharedCount : \A node \in 1..ConditionalSharedTable.plans[row].count :
                        ConditionalSharedTable.plans[row].kinds[node] = "add" =>
                           \E p \in DOMAIN ConditionalProbePositions : ConditionalProbePositions[p] = <<<<>>, row, node>>
                    /\ \#(inventoryClaim.replacingOccurrences(of: "\n", with: "\n    "))
                    <2>joined. \#(inventoryClaim.replacingOccurrences(of: "\n", with: "\n    "))
                    \#(inventoryProof.replacingOccurrences(of: "\n", with: "\n    "))
                    <2>prefix. \A row \in 1..ConditionalSharedCount : \A node \in 1..ConditionalSharedTable.plans[row].count :
                        ConditionalSharedTable.plans[row].kinds[node] = "add" =>
                           \E p \in DOMAIN ConditionalProbePositions : ConditionalProbePositions[p] = <<<<>>, row, node>>
                        <3>. TAKE row \in 1..ConditionalSharedCount
                        <3>. TAKE node \in 1..ConditionalSharedTable.plans[row].count
                        <3>range. row \in 1..Len(ConditionalIntegerRows(1))
                            BY ONLY (row \in 1..ConditionalSharedCount), <1>sharedRows, <1>sharedPrefix, SMT
                                DEF Arithmetic!AssignmentRhsRowsArePrefix
                        <3>physical. ConditionalSharedTable.plans[row] = ConditionalIntegerTable(1).plans[row]
                            BY ONLY (row \in 1..ConditionalSharedCount), <1>sharedRows, <1>sharedTablePrefix, SMT
                                DEF Arithmetic!RenderedAssignmentTablesAgreeOnPrefix
                        <3>. QED BY ONLY (row \in 1..ConditionalSharedCount),
                            (node \in 1..ConditionalSharedTable.plans[row].count), <1>shape,
                            <2>joined, <3>range, <3>physical, SMT DEF ConditionalJoinedProbePosition
                    <2>. QED BY ONLY <2>joined, <2>prefix
                <1>probeReach. \A p \in DOMAIN ConditionalProbePositions :
                    LET place == ConditionalProbePositions[p]
                        owner == place[1]
                        row == place[2]
                        node == place[3]
                        raw == ConditionalProbeTable(owner)
                        count == ConditionalProbeCount(owner)
                        falls == Arithmetic!RenderedAssignmentFailsAt(raw, count, row, node)
                    IN /\ (owner = <<>> \/ owner \in ConditionalArms)
                       /\ (owner = <<>> <=> row <= ConditionalSharedCount)
                       /\ row \in 1..count /\ node \in 1..raw.plans[row].count
                       /\ (ConditionalProbeGuards[p] <=> IF owner = <<>> THEN falls
                            ELSE /\ Arithmetic!RenderedAssignmentsPass(ConditionalSharedTable, ConditionalSharedCount)
                                 /\ ConditionalPhysicalDecision = <<owner>>
                                 /\ falls)
                    BY ONLY <1>shape, <1>integerRows, <1>probeSlots, SMT DEF ConditionalProbePositions, ConditionalProbeGuards,
                        ConditionalProbeTable, ConditionalProbeCount, ConditionalIntegerTable, ConditionalIntegerRows,
                        ConditionalSharedCount, ConditionalPhysicalDecision, Arithmetic!RenderedAssignmentFailsAt,
                        Arithmetic!RenderedAssignmentsPass, Arithmetic!FirstRejectedRenderedGuard,
                        Arithmetic!EveryRenderedGuardPasses, \#(sharedEvaluatedTables), \#(guardNames.joined(separator: ", "))
                \#(probeValues)
                <1>probeUnique. \A p, q \in DOMAIN ConditionalProbePositions :
                                  ConditionalProbeGuards[p] /\ ConditionalProbeGuards[q] => p = q
                    <2>triples. \A p \in DOMAIN ConditionalProbePositions :
                        LET pos == ConditionalProbePositions[p]
                        IN pos = <<pos[1], pos[2], pos[3]>>
                        BY ONLY <1>probeSlots, IsaM("simp"), SMT DEF ConditionalProbePositions
                    <2>. TAKE p, q \in DOMAIN ConditionalProbePositions
                    <2>. SUFFICES ASSUME ConditionalProbeGuards[p], ConditionalProbeGuards[q] PROVE p = q BY Zenon
                    <2>. DEFINE point == ConditionalProbePositions[p]
                                other == ConditionalProbePositions[q]
                                passes == Arithmetic!RenderedAssignmentsPass(ConditionalSharedTable, ConditionalSharedCount)
                    <2>left. /\ Arithmetic!RenderedAssignmentFailsAt(ConditionalProbeTable(point[1]), ConditionalProbeCount(point[1]),
                                                                   point[2], point[3])
                             /\ (point[1] # <<>> => passes /\ ConditionalPhysicalDecision = <<point[1]>>)
                        BY ONLY <1>probeReach, (p \in DOMAIN ConditionalProbePositions), ConditionalProbeGuards[p], SMT DEF point, passes
                    <2>right. /\ Arithmetic!RenderedAssignmentFailsAt(ConditionalProbeTable(other[1]), ConditionalProbeCount(other[1]),
                                                                    other[2], other[3])
                              /\ (other[1] # <<>> => passes /\ ConditionalPhysicalDecision = <<other[1]>>)
                        BY ONLY <1>probeReach, (q \in DOMAIN ConditionalProbePositions), ConditionalProbeGuards[q], SMT DEF other, passes
                    <2>sharedRejects. ASSUME NEW pos, pos[1] = <<>>,
                                            Arithmetic!RenderedAssignmentFailsAt(ConditionalProbeTable(pos[1]), ConditionalProbeCount(pos[1]),
                                                                                 pos[2], pos[3])
                                      PROVE ~passes
                        <3>failure. Arithmetic!RenderedAssignmentFailsAt(ConditionalSharedTable, ConditionalSharedCount, pos[2], pos[3])
                            BY ONLY (pos[1] = <<>>),
                                Arithmetic!RenderedAssignmentFailsAt(ConditionalProbeTable(pos[1]), ConditionalProbeCount(pos[1]), pos[2], pos[3]),
                                SMT DEF ConditionalProbeTable, ConditionalProbeCount
                        <3>. QED BY ONLY <3>failure, SMT DEF passes, Arithmetic!RenderedAssignmentFailsAt,
                            Arithmetic!FirstRejectedRenderedGuard, Arithmetic!RenderedAssignmentsPass, Arithmetic!EveryRenderedGuardPasses
                    <2>owners. point[1] = other[1]
                        <3>mixed. (point[1] = <<>>) <=> (other[1] = <<>>)
                            BY ONLY <2>left, <2>right, <2>sharedRejects, SMT
                        <3>selected. point[1] # <<>> /\ other[1] # <<>> => point[1] = other[1]
                            BY ONLY <2>left, <2>right, SMT
                        <3>. QED BY ONLY <3>mixed, <3>selected, SMT
                    <2>same. /\ point[2] = other[2] /\ point[3] = other[3]
                        <3>sameTable. Arithmetic!RenderedAssignmentFailsAt(ConditionalProbeTable(point[1]), ConditionalProbeCount(point[1]),
                                                                          other[2], other[3])
                            BY ONLY <2>owners, <2>right, SMT
                        <3>. QED BY ONLY <2>left, <3>sameTable, Arithmetic!RenderedAssignmentFailurePositionIsUnique
                    <2>coordinate. point = other
                        BY ONLY <2>owners, <2>same, <2>triples,
                            (p \in DOMAIN ConditionalProbePositions), (q \in DOMAIN ConditionalProbePositions), SMT DEF point, other
                    <2>. QED BY ONLY <2>coordinate, <1>probeSlots, (p \in DOMAIN ConditionalProbePositions),
                        (q \in DOMAIN ConditionalProbePositions), SMT DEF point, other
                \#(probeWire)
                """#
            }
            let reachSteps = try armProbeReachSteps()
            return #"""
            <1>probeInventory. \#(inventoryClaim)
            \#(inventoryProof)
            \#(reachSteps)
            \#(probeValues)
            <1>probeUnique. \A p, q \in DOMAIN ConditionalProbePositions :
                              ConditionalProbeGuards[p] /\ ConditionalProbeGuards[q] => p = q
                <2>triples. \A p \in DOMAIN ConditionalProbePositions :
                    LET pos == ConditionalProbePositions[p]
                    IN pos = <<pos[1], pos[2], pos[3]>>
                    BY ONLY <1>probeSlots, IsaM("simp"), SMT DEF ConditionalProbePositions
                <2>. TAKE p, q \in DOMAIN ConditionalProbePositions
                <2>. SUFFICES ASSUME ConditionalProbeGuards[p], ConditionalProbeGuards[q] PROVE p = q BY Zenon
                <2>. DEFINE point == ConditionalProbePositions[p]
                            other == ConditionalProbePositions[q]
                            raw == ConditionalIntegerTable(ConditionalSelectedArm)
                            end == Len(ConditionalIntegerRows(ConditionalSelectedArm))
                <2>left. /\ point[1] = ConditionalSelectedArm
                         /\ Arithmetic!RenderedAssignmentFailsAt(raw, end, point[2], point[3])
                    BY ONLY <1>probeReach, (p \in DOMAIN ConditionalProbePositions), ConditionalProbeGuards[p], SMT DEF point, raw, end
                <2>right. /\ other[1] = ConditionalSelectedArm
                          /\ Arithmetic!RenderedAssignmentFailsAt(raw, end, other[2], other[3])
                    BY ONLY <1>probeReach, (q \in DOMAIN ConditionalProbePositions), ConditionalProbeGuards[q], SMT DEF other, raw, end
                <2>same. /\ point[2] = other[2] /\ point[3] = other[3]
                    BY ONLY <2>left, <2>right, Arithmetic!RenderedAssignmentFailurePositionIsUnique
                <2>coordinate. point = other
                    BY ONLY <2>left, <2>right, <2>same, <2>triples,
                        (p \in DOMAIN ConditionalProbePositions), (q \in DOMAIN ConditionalProbePositions), SMT DEF point, other
                <2>. QED BY ONLY <2>coordinate, <1>probeSlots, (p \in DOMAIN ConditionalProbePositions),
                    (q \in DOMAIN ConditionalProbePositions), SMT DEF point, other
            \#(probeWire)
            """#
        } ?? ""
        let probeSteps = failureOutput == nil ? "" : #"""
        <1>probeSlots. /\ DOMAIN ConditionalProbePositions = 1..\#(probes.count)
                        /\ DOMAIN ConditionalProbeGuards = DOMAIN ConditionalProbePositions
                        /\ \A p, q \in DOMAIN ConditionalProbePositions :
                                ConditionalProbePositions[p] = ConditionalProbePositions[q] => p = q
            BY ONLY SMT DEF ConditionalProbePositions, ConditionalProbeGuards
        \#(ownerSteps)
        <1>probeEmpty. \A p \in DOMAIN ConditionalProbePositions :
                          /\ ConditionalExportedProbe(p) \o <<>> = ConditionalExportedProbe(p)
                          /\ <<>> \o ConditionalExportedProbe(p) = ConditionalExportedProbe(p)
                          /\ (~ConditionalProbeGuards[p] => ConditionalExportedProbe(p) = <<>>)
            BY ONLY EmptySeq, ConcatEmptySeq, SMT DEF ConditionalExportedProbe, Seq
        <1>probeOne. \A p \in DOMAIN ConditionalProbePositions :
                         ConditionalProbeGuards[p] => ActualConditionalHistory = ConditionalExportedProbe(p)
            <2>. TAKE p \in DOMAIN ConditionalProbePositions
            <2>. SUFFICES ASSUME ConditionalProbeGuards[p]
                 PROVE ActualConditionalHistory = ConditionalExportedProbe(p)
                OBVIOUS
            \#(cases)
            <2>. QED BY ONLY <1>probeSlots, \#(indices.map { "<2>probe" + $0 }.joined(separator: ", ")), SMT
        <1>probeNone. (\A p \in DOMAIN ConditionalProbePositions : ~ConditionalProbeGuards[p]) =>
                          ActualConditionalHistory = <<>>
            <2>inactive. (\A p \in DOMAIN ConditionalProbePositions : ~ConditionalProbeGuards[p]) => (\#(inactive))
                BY ONLY <1>probeSlots, SMT
            <2>. QED BY ONLY <1>probeSlots, <1>probeWire, <1>probeEmpty, <2>inactive, ConcatEmptySeq, EmptySeq, SMT
                DEF ConditionalExportedHistory
        """# + "\n"
        let prefixPassed = input.shared == nil ? "" : "<1>prefixPass, "
        let selectedPrefix = input.shared == nil ? "" : #"""
            <2>prefix. /\ Arithmetic!RenderedAssignmentsPass(ConditionalSharedTable, ConditionalSharedCount)
                       /\ ConditionalPhysicalDecision = <<arm>>
                       /\ arm \in ConditionalArms /\ arm # <<>>
                BY ONLY <1>prefixPass, <1>sharedPasses, <1>selectedPhysical, <1>selector, <1>shape, SMT DEF arm
            <2>joinedPrefix. Arithmetic!RenderedAssignmentsPass(raw, ConditionalSharedCount)
                BY ONLY <2>prefix, <1>selector, <1>shape, SMT DEF arm, raw, ConditionalIntegerTable, ConditionalSharedCount,
                    Arithmetic!RenderedAssignmentsPass, Arithmetic!EveryRenderedGuardPasses, \#(sharedEvaluatedTables)
        """# + "\n"
        let localFailure = input.shared == nil ? "" : #"""
                    <4>local. row > ConditionalSharedCount
                        BY ONLY <4>node, <2>joinedPrefix, SMT DEF Arithmetic!RenderedAssignmentFailsAt,
                            Arithmetic!RenderedAssignmentsPass, Arithmetic!FirstRejectedRenderedGuard, Arithmetic!EveryRenderedGuardPasses
        """# + "\n"
        let prefixMatch = input.shared == nil ? "" : "<2>prefix, "
        let localMatch = input.shared == nil ? "" : "<4>local, "
        let positionMatch = input.shared == nil ? "" : ", ConditionalJoinedProbePosition, ConditionalSharedCount"
        let probePath = input.shared == nil ? "" : ", ConditionalProbeTable, ConditionalProbeCount"
        let probePrefix = input.shared == nil ? "" : ", ConditionalProbeFailurePrefix, ConditionalProbeOrigins, ConditionalFailurePrefix"
        let probeOrigin = input.shared == nil ? "" : ", ConditionalProbeOrigins, ConditionalAssignmentOrigins"
        let physicalSteps = failureOutput != nil ? #"""
        <1>physicalHistory. ActualConditionalHistory = ConditionalSourceHistory
            <2>. DEFINE arm == ConditionalSelectedArm
                        rows == ConditionalIntegerRows(arm)
                        raw == ConditionalIntegerTable(arm)
                        last == Len(rows)
                        terminal == ConditionalIntegerTerminal(arm)
            <2>input. /\ Arithmetic!SupportedAssignmentList(rows)
                      /\ Arithmetic!RenderedAssignmentInventory(rows, ConditionalBefore, raw)
                BY ONLY <1>selector, <1>integerRows, <1>integerInventory, SMT DEF arm, rows, raw
            <2>reached. Arithmetic!RenderedAssignmentHistoryAt(rows, ConditionalBefore, raw, ConditionalIntegerRun(arm), last)
                BY ONLY <1>selector, <1>integerOutcomes DEF arm, rows, raw, last
        \#(selectedPrefix)    <2>physical. ActualConditionalHistory = ConditionalSourceHistory
                <3>pass. CASE Arithmetic!RenderedAssignmentsPass(raw, last)
                    <4>empty. terminal.failure = <<>>
                        BY ONLY <3>pass, <2>reached, SMT DEF Arithmetic!RenderedAssignmentHistoryAt, ConditionalIntegerTerminal, rows, last, terminal
                    <4>disabled. \A p \in DOMAIN ConditionalProbePositions : ~ConditionalProbeGuards[p]
                        BY ONLY <3>pass, \#(prefixMatch)<1>probeReach, SMT DEF arm, rows, raw, last,
                            Arithmetic!RenderedAssignmentsPass, Arithmetic!RenderedAssignmentFailsAt,
                            Arithmetic!FirstRejectedRenderedGuard, Arithmetic!EveryRenderedGuardPasses\#(probePath)
                    <4>. QED BY ONLY \#(prefixPassed)<4>empty, <4>disabled, <1>probeNone DEF ConditionalOrderedFailure, ConditionalSourceHistory, arm, terminal
                <3>fail. CASE ~Arithmetic!RenderedAssignmentsPass(raw, last)
                    <4>first. \E row \in 1..last : \E node \in 1..raw.plans[row].count :
                                      Arithmetic!RenderedAssignmentFailsAt(raw, last, row, node)
                        BY ONLY <3>fail, <2>input, Arithmetic!WholeGuardTableHasAnExactFirstFailureSite, SMT DEF last
                    <4>row. PICK row \in 1..last : \E node \in 1..raw.plans[row].count :
                                    Arithmetic!RenderedAssignmentFailsAt(raw, last, row, node)
                        BY ONLY <4>first, Zenon
                    <4>node. PICK node \in 1..raw.plans[row].count :
                                    Arithmetic!RenderedAssignmentFailsAt(raw, last, row, node)
                        BY ONLY <4>row, Zenon
                    <4>result. /\ raw.plans[row].kinds[node] = "add"
                                /\ terminal.failure = Arithmetic!RenderedAssignmentFailure(rows, ConditionalBefore, raw, row, node)
                                /\ terminal.completed = Arithmetic!HistoryPrefix(raw.roots, row - 1)
                        BY ONLY <4>row, <4>node, <2>reached, SMT DEF Arithmetic!RenderedAssignmentHistoryAt, ConditionalIntegerTerminal, rows, last, terminal
        \#(localFailure)            <4>probe. PICK p \in DOMAIN ConditionalProbePositions :
                                       ConditionalProbePositions[p] = <<arm, row, node>>
                        BY ONLY <4>row, <4>node, <4>result, \#(localMatch)<1>selector, <1>probeInventory, SMT DEF arm, rows, raw, last\#(positionMatch)
                    <4>fires. ConditionalProbeGuards[p]
                        BY ONLY <4>probe, <4>node, \#(prefixMatch)<1>probeReach, SMT DEF arm, rows, raw, last\#(probePath)
                    <4>label. ActualConditionalHistory = ConditionalExportedProbe(p)
                        BY ONLY <4>probe, <4>fires, <1>probeOne
                    <4>data. /\ ConditionalProbePayloads[p] = terminal.failure.payload
                               /\ ConditionalProbeBefore[p] = ConditionalFailurePrefix(arm, terminal.completed)
                        BY ONLY <4>probe, <4>fires, <4>result, \#(prefixMatch)<1>probeValues, SMT DEF rows, raw\#(probePath)\#(probePrefix)
                    <4>. QED BY ONLY \#(prefixPassed)\#(prefixMatch)<4>label, <4>data, <4>fires, <4>probe, <4>result, SMT
                        DEF ConditionalExportedProbe, ConditionalSourceHistory, arm, terminal, ConditionalOrderedFailure, ConditionalLabeledFailure,
                            Arithmetic!RenderedAssignmentFailure\#(probeOrigin)
                <3>. QED BY ONLY <3>pass, <3>fail, SMT
            <2>. QED BY ONLY <2>physical
        """# + "\n" : #"""
        <1>totalArms. \A arm \in ConditionalArms : ConditionalIntegerTerminal(arm).failure = <<>>
            <2>. TAKE arm \in ConditionalArms
            <2>. DEFINE rows == ConditionalIntegerRows(arm)
                        raw == ConditionalIntegerTable(arm)
                        last == Len(rows)
            <2>count. last = IF arm = 1 THEN \#(arms[0].integerCaptures.count) ELSE \#(arms[1].integerCaptures.count)
                BY ONLY (arm \in ConditionalArms), <1>integerRows, SMT DEF last, rows
            <2>pass. Arithmetic!RenderedAssignmentsPass(raw, last)
                BY ONLY (arm \in ConditionalArms), <1>shape, <2>count, SMT
                    DEF raw, ConditionalIntegerTable, \#(evaluatedTables),
                        Arithmetic!RenderedAssignmentsPass, Arithmetic!EveryRenderedGuardPasses
            <2>. QED BY ONLY (arm \in ConditionalArms), <1>integerOutcomes, <2>pass, SMT
                DEF rows, raw, last, ConditionalIntegerTerminal, Arithmetic!RenderedAssignmentHistoryAt
        <1>total. ConditionalIntegerTerminal(ConditionalSelectedArm).failure = <<>>
            BY ONLY <1>selector, <1>totalArms
        <1>totalHistories. /\ ConditionalSourceHistory = <<>>
                           /\ ConditionalNativeHistory(TRUE) = <<>>
            BY ONLY \#(prefixPassed)<1>total, <1>nativeHistory, SMT DEF ConditionalSourceHistory, ConditionalOrderedFailure
        """# + "\n"
        let successorSteps = #"""
        <1>finalRoutes. \A arm \in ConditionalArms :
                          ConditionalPhysicalRoutes(arm) = ConditionalSourceRows[arm].finalRoutes
            BY ONLY <1>shape, IsaM("simp"), SMT DEF ConditionalPhysicalRoutes, ConditionalPhysicalRouteTable, ConditionalSourceRows
        <1>step. ConditionalPhysicalStep <=> ConditionalSourceStep
            <2>. DEFINE arm == ConditionalSelectedArm
                        rows == ConditionalIntegerRows(arm)
                        raw == ConditionalIntegerTable(arm)
                        last == Len(rows)
                        terminal == ConditionalIntegerTerminal(arm)
            <2>reached. Arithmetic!RenderedAssignmentHistoryAt(rows, ConditionalBefore, raw, ConditionalIntegerRun(arm), last)
                BY ONLY <1>selector, <1>integerOutcomes DEF arm, rows, raw, last
            <2>input. /\ Arithmetic!SupportedAssignmentList(rows)
                      /\ Arithmetic!RenderedAssignmentInventory(rows, ConditionalBefore, raw)
                BY ONLY <1>selector, <1>integerRows, <1>integerInventory, SMT DEF arm, rows, raw
            <2>length. last = IF arm = 1 THEN \#(arms[0].integerCaptures.count) ELSE \#(arms[1].integerCaptures.count)
                BY ONLY <1>selector, <1>integerRows, SMT DEF arm, last, rows
            <2>pass. CASE Arithmetic!RenderedAssignmentsPass(raw, last)
                BY ONLY \#(prefixPassed)<2>pass, <2>reached, <2>length, <1>tableStep, <1>selector, <1>shape, <1>finalRoutes, SMT
                    DEF ConditionalTableStep, ConditionalSourceStep, ConditionalOrderedStep, ConditionalIntegerTerminal,
                        ConditionalSourceSuccessor,
                        arm, rows, raw, last, terminal, Arithmetic!RenderedAssignmentHistoryAt, Arithmetic!HistoryPrefix,
                        ConditionalIntegerTable, \#(evaluatedTables)
            <2>fail. CASE ~Arithmetic!RenderedAssignmentsPass(raw, last)
                <3>position. PICK row \in 1..last : \E node \in 1..raw.plans[row].count :
                                      Arithmetic!RenderedAssignmentFailsAt(raw, last, row, node)
                    BY ONLY <2>fail, <2>input, Arithmetic!WholeGuardTableHasAnExactFirstFailureSite, SMT DEF last
                <3>node. PICK node \in 1..raw.plans[row].count : Arithmetic!RenderedAssignmentFailsAt(raw, last, row, node)
                    BY ONLY <3>position, Zenon
                <3>failure. terminal.failure # <<>>
                    BY ONLY <3>position, <3>node, <2>reached, SMT DEF terminal, rows, last, ConditionalIntegerTerminal,
                        Arithmetic!RenderedAssignmentHistoryAt, Arithmetic!RenderedAssignmentFailure
                <3>. QED BY ONLY \#(prefixPassed)<2>fail, <3>failure, <2>length, <1>tableStep, SMT
                    DEF ConditionalTableStep, ConditionalSourceStep, ConditionalOrderedStep, arm, last, terminal, raw
            <2>. QED BY ONLY \#(prefixPassed)<2>pass, <2>fail, SMT
        <1>certified. ConditionalObservationUsesOrderedRows
            <2>. DEFINE arm == ConditionalSelectedArm
                        rows == ConditionalIntegerRows(arm)
            <2>. WITNESS ConditionalIntegerRun(arm)
        """# + "\n"
        let certification = failureOutput != nil ? #"""
            <2>. QED BY ONLY \#(prefixPassed)<1>selector, <1>integerRuns, <1>physicalHistory, <1>nativeHistory, <1>step, <1>nativeSuccess, SMT
                DEF ConditionalObservationUsesOrderedRows, ConditionalIntegerTerminal, ConditionalSourceHistory, ConditionalSourceStep, arm, rows
        """# : #"""
            <2>. QED BY ONLY \#(prefixPassed)<1>selector, <1>integerRuns, <1>total, <1>nativeHistory, <1>step, <1>nativeSuccess, SMT
                DEF ConditionalObservationUsesOrderedRows, ConditionalIntegerTerminal, ConditionalSourceStep, arm, rows
        """#
        let definitions = rowDefinitions + prefixDefinitions + probeDefinitions + routeDefinitions
        if input.shared != nil {
            return (native.rowDefinitions, definitions, rowSteps + beforeSelection + probeSteps + sharedFailureSteps + "\n",
                    native.selectedSteps + "\n" + physicalSteps + successorSteps + certification)
        }
        return (native.rowDefinitions, definitions, "", rowSteps + probeSteps + native.steps + "\n" + physicalSteps + successorSteps + certification)
    }

    private static func conditionalTypePreservationProof(_ arms: [ConditionalOverflowArm], sharedPrefix: Bool) -> String {
        let counts = arms.map { $0.integerCaptures.count }
        let roleCases = arms.indices.map { index in
            let arm = index + 1
            return #"""
            <2>arm\#(arm). CASE arm = \#(arm)
                BY ONLY <2>arm\#(arm), <1>count, EmptySeq, SeqDef, IsaM("auto"), SMT
                    DEF suffix, routes, row, ConditionalSourceRows, ConditionalStateKeys, ConditionalLayoutIntKeys
            """#
        }.joined(separator: "\n        ")
        let roleFacts = arms.indices.map { "<2>arm\($0 + 1)" }.joined(separator: ", ")
        let reachedArm = sharedPrefix ? #"""
        <1>prefixPass. ConditionalSharedTerminal.failure = <<>>
            BY ONLY ConditionalSourceStep, SMT DEF ConditionalSourceStep
        """# + "\n" : ""
        let armDefinitions = sharedPrefix
            ? "ConditionalSourceDecision, ConditionalArmAt"
            : "ConditionalArmFor"
        let reach = sharedPrefix ? "<1>prefixPass, " : ""
        return #"""
        LOCAL THEOREM ConditionalSourceStepPreservesType ==
            ASSUME ConditionalTypedState, ConditionalSourceStep
            PROVE ConditionalTypedState'
        PROOF
        <1>. DEFINE arm == ConditionalSelectedArm
                    rows == ConditionalIntegerRows(arm)
                    last == Len(rows)
                    history == ConditionalIntegerRun(arm)
                    terminal == ConditionalIntegerTerminal(arm)
                    row == ConditionalSourceRows[arm]
                    completed == terminal.completed
                    suffix == row.suffix
                    routes == row.finalRoutes
                    captures == completed \o suffix
                    values(key) == IF key \in ConditionalLayoutIntKeys THEN ConditionalIntValues ELSE BOOLEAN
        \#(reachedArm)<1>arm. arm = 1 \/ arm = 2
            BY ONLY \#(reach)SMT DEF arm, ConditionalSelectedArm, \#(armDefinitions)
        <1>count. last = IF arm = 1 THEN \#(counts[0]) ELSE \#(counts[1])
            BY ONLY <1>arm, ConditionalFirstIntegerSourceAssignmentsAreSupported,
                ConditionalSecondIntegerSourceAssignmentsAreSupported, SMT DEF rows, last, ConditionalIntegerRows
        <1>supported. Arithmetic!SupportedAssignmentList(rows)
            BY ONLY <1>arm, ConditionalFirstIntegerSourceAssignmentsAreSupported,
                ConditionalSecondIntegerSourceAssignmentsAreSupported, SMT DEF rows, ConditionalIntegerRows
        <1>history. Arithmetic!AssignmentListHistory(FALSE, ConditionalBefore, rows, history)
            BY ONLY ConditionalTypedState, \#(reach)ConditionalSelectedSourceHistoryIsCertified DEF arm, rows, history
        <1>keys. ConditionalIntKeys = ConditionalLayoutIntKeys
            BY ONLY SMT DEF ConditionalIntKeys, ConditionalLayoutIntKeys
        <1>entry. ConditionalBefore \in Arithmetic!AssignmentBindings
            BY ONLY ConditionalTypedState, <1>keys, SMT DEF ConditionalTypedState, ConditionalBefore,
                ConditionalLayoutIntKeys, ConditionalIntValues, Arithmetic!AssignmentBindings, Arithmetic!AssignmentIntValues
        <1>transition. /\ terminal.failure = <<>>
                       /\ ConditionalStateAfter = Arithmetic!CopyMaterializedState(
                              ConditionalStateKeys, ConditionalStateBefore, captures, routes)
            BY ONLY ConditionalSourceStep DEF ConditionalSourceStep, ConditionalOrderedStep, ConditionalSourceSuccessor,
                arm, terminal, row, completed, suffix, routes, captures
        <1>terminal. terminal \in Arithmetic!AssignmentPrefixStates
            BY ONLY <1>count, <1>history, SMT DEF terminal, history, last, ConditionalIntegerTerminal,
                Arithmetic!AssignmentListHistory
        <1>completed. completed \in Seq(ConditionalIntValues)
            BY ONLY <1>terminal, SMT DEF completed, Arithmetic!AssignmentPrefixStates,
                Arithmetic!AssignmentIntValues, ConditionalIntValues
        <1>prefix. Arithmetic!AssignmentPrefixMeaning(ConditionalBefore, rows, history, last)
            BY ONLY <1>supported, <1>entry, <1>history, <1>count,
                Arithmetic!OrderedAssignmentHistoriesRetainTheExactFirstFailurePrefix, SMT DEF last
        <1>length. Len(completed) = last
            BY ONLY <1>prefix, <1>transition, SMT DEF Arithmetic!AssignmentPrefixMeaning,
                terminal, history, last, ConditionalIntegerTerminal, completed
        <1>roles. /\ suffix \in Seq(BOOLEAN)
                  /\ \A key \in ConditionalStateKeys :
                         routes[key] = <<"state", key>> \/
                         (IF key \in ConditionalLayoutIntKeys
                          THEN \E i \in 1..last : routes[key] = <<"capture", i>>
                          ELSE \E i \in 1..Len(suffix) : routes[key] = <<"capture", last + i>>)
            \#(roleCases)
            <2>. QED BY ONLY <1>arm, \#(roleFacts), SMT
        <1>concatInputs. /\ completed \in Seq(ConditionalIntValues \cup BOOLEAN)
                         /\ suffix \in Seq(ConditionalIntValues \cup BOOLEAN)
            BY ONLY <1>completed, <1>roles, SeqMonotonic, SMT
        <1>concat. \A i \in 1..(Len(completed) + Len(suffix)) :
            captures[i] = IF i <= Len(completed) THEN completed[i] ELSE suffix[i - Len(completed)]
            BY ONLY <1>concatInputs, ConcatProperties, SMT DEF captures
        <1>captured. /\ \A i \in 1..last : captures[i] \in ConditionalIntValues
                     /\ \A i \in 1..Len(suffix) : captures[last + i] \in BOOLEAN
            BY ONLY <1>concat, <1>length, <1>completed, <1>roles, ElementOfSeq, LenProperties, SMT
        <1>before. \A key \in ConditionalStateKeys : ConditionalStateBefore[key] \in values(key)
            BY ONLY ConditionalTypedState, SMT DEF values, ConditionalTypedState, ConditionalStateBefore,
                ConditionalLayoutIntKeys, ConditionalStateKeys
        <1>after. \A key \in ConditionalStateKeys : ConditionalStateAfter[key] \in values(key)
            <2>. TAKE key \in ConditionalStateKeys
            <2>field. ConditionalStateAfter[key] =
                Arithmetic!CopyReferenceValue(ConditionalStateBefore, captures, routes[key])
                BY ONLY (key \in ConditionalStateKeys), <1>transition, SMT DEF Arithmetic!CopyMaterializedState
            <2>. QED BY ONLY (key \in ConditionalStateKeys), <2>field, <1>roles, <1>before,
                <1>captured, SMT DEF values, Arithmetic!CopyReferenceValue
        <1>. QED BY ONLY <1>after, SMT DEF values, ConditionalTypedState, ConditionalStateAfter,
            ConditionalLayoutIntKeys, ConditionalStateKeys
        """#
    }

    private static func conditionalConfiguredProof(name: String, actionProof: String, cfgProof: String,
                                                   initialPredicate: String?, actionLayout: CompiledActionLayout,
                                                   authoredLabel: TLAValue, nativeAction: NativeConditionalActionOutput,
                                                   sendBindingModule: String, observesFailures: Bool, sharedPrefix: Bool,
                                                   descriptors: [ConditionalOverflowArm]) -> String {
        let initName = initialPredicate == nil ? "Init" : "ConditionalSourceInit"
        let initDefinition = initialPredicate.map { "ConditionalSourceInit == \($0)\n" } ?? ""
        let initClaim = initialPredicate == nil ? "" : "    /\\ (Init <=> ConditionalSourceInit)\n"
        let initProof = initialPredicate == nil ? "" : "<1>initial. Init <=> ConditionalSourceInit\n    BY ONLY SMT DEF Init, ConditionalSourceInit\n"
        let initFact = initialPredicate == nil ? "" : "<1>initial, "
        let typedClaims = initialPredicate == nil ? "" : #"""
            /\ (Spec => []ConditionalTypedState)
            /\ (ConditionalConfiguredBehavior => []ConditionalTypedState)

        """#
        let typeFacts = initialPredicate == nil ? "" : "<1>modelTyped, <1>sourceTyped, "
        let behaviorStatement = initialPredicate == nil
            ? "[]ConditionalTypedState => (Spec <=> ConditionalConfiguredBehavior)"
            : "Spec <=> ConditionalConfiguredBehavior"
        let typeProof = initialPredicate == nil ? "" : conditionalTypePreservationProof(descriptors, sharedPrefix: sharedPrefix) + "\n\n"
        let invariantProof = initialPredicate == nil ? "" : #"""
        <1>initialType. ConditionalSourceInit => ConditionalTypedState
            BY ONLY SMT DEF ConditionalSourceInit, ConditionalTypedState, ConditionalIntValues
        <1>stutterType. ConditionalTypedState /\ UNCHANGED vars => ConditionalTypedState'
            BY ONLY SMT DEF ConditionalTypedState, vars
        <1>sourceStepType. ConditionalTypedState /\ [ConditionalSourceStep]_vars => ConditionalTypedState'
            BY ONLY <1>stutterType, ConditionalSourceStepPreservesType, PTL
        <1>modelStepType. ConditionalTypedState /\ [Next]_vars => ConditionalTypedState'
            BY ONLY <1>stuttering, <1>sourceStepType, PTL
        <1>modelTyped. Spec => []ConditionalTypedState
            BY ONLY <1>initial, <1>initialType, <1>spec, <1>modelStepType, PTL
        <1>sourceTyped. ConditionalConfiguredBehavior => []ConditionalTypedState
            BY ONLY <1>initialType, <1>sourceStepType, PTL DEF ConditionalConfiguredBehavior

        """#
        let observations = observesFailures ? #"""
                  /\ (ConditionalSelectedEvaluationCheck <=> ConditionalSourceHistory = <<>>)
                  /\ (ConditionalSelectedEvaluationCheck <=> ActualConditionalHistory = <<>>)
                  /\ (ConditionalSelectedEvaluationCheck <=> ConditionalNativeHistory(TRUE) = <<>>)
        """# + "\n" : #"""
                  /\ ConditionalSourceHistory = <<>>
                  /\ ConditionalNativeHistory(TRUE) = <<>>
        """# + "\n"
        let selection = observesFailures
            ? "NormalOrderedRHSCFGSelectsSpecDeadlockAndEvaluationChecking"
            : "NormalOrderedRHSCFGSelectsSpecAndDeadlock"
        let failedBeforeChoice = sharedPrefix ? #"""
            IF ConditionalSharedTerminal.failure # <<>> THEN
                [kind |-> "evaluationFailure", current |-> ConditionalSnapshot(ConditionalStateBefore),
                 value |-> ConditionalSharedTerminal.failure.payload]
            ELSE
        """# + "\n" : ""
        let reachedPremise = sharedPrefix ? ", ConditionalSharedTerminal.failure = <<>>" : ""
        let reachedFact = sharedPrefix ? "(ConditionalSharedTerminal.failure = <<>>), " : ""
        let armFacts = sharedPrefix ? "<2>prefixPass, " : ""
        let armDefinitions = sharedPrefix ? "ConditionalSourceDecision, ConditionalArmAt" : "ConditionalArmFor"
        let sharedSend = sharedPrefix ? #"""
            <2>shared. CASE ConditionalSharedTerminal.failure # <<>>
                <3>observed. ConditionalSharedFailureObservations
                    BY ONLY ConditionalTypedState, <2>shared, ActualConditionalHistoryMatchesTheAuthoredArms, SMT
                        DEF ConditionalObservationUsesOrderedRows
                <3>sourceRun. Arithmetic!AssignmentListHistory(FALSE, ConditionalBefore, ConditionalSharedRows, ConditionalSharedRun)
                    BY ONLY ConditionalTypedState, <2>shared, ActualConditionalHistoryMatchesTheAuthoredArms, SMT
                        DEF ConditionalObservationUsesOrderedRows
                <3>length. /\ Len(ConditionalSharedRows) = ConditionalSharedCount /\ ConditionalSharedCount \in Nat
                    BY ONLY ConditionalSharedIntegerSourceAssignmentsAreSupported, SMT
                        DEF ConditionalSharedRows, ConditionalSharedCount
                <3>reason. ConditionalSharedTerminal.failure.payload \in Arithmetic!ArithmeticFailures
                    BY ONLY <3>sourceRun, <3>length, <2>shared, SMT
                        DEF ConditionalSharedTerminal, Arithmetic!AssignmentListHistory,
                            Arithmetic!AssignmentPrefixStates, Arithmetic!AssignmentFailureEvents
                <3>queue. /\ queue.callbacks = <<>>
                          /\ queue.reasons = <<ConditionalSharedTerminal.failure.payload>>
                    BY ONLY <1>nativeQueue, <3>observed, SMT DEF queue, ConditionalSharedFailureObservations
                <3>sequences. /\ queue.callbacks \in Seq({prior})
                              /\ queue.reasons \in Seq(Arithmetic!ArithmeticFailures)
                              /\ <<>> \notin Arithmetic!ArithmeticFailures
                    BY ONLY <3>queue, <3>reason, EmptySeq, SeqDef, LenProperties, SMT
                        DEF Arithmetic!ArithmeticFailures
                <3>send. ConditionalPublicSend = outcome
                    BY ONLY <1>nativeQueue, <1>sendRoute, <3>sequences,
                        ConditionalSend!DecodedSendUsesTheFirstErrorOrCommitsExactlyOneCallback
                        DEF ConditionalPublicSend, queue, outcome, prior, binding
                <3>. QED BY ONLY <2>shared, <3>queue, <3>send,
                    ConditionalSend!PublicSendOutcomeUsesTheEmptyAndSingletonQueues, SMT
                    DEF outcome, prior, ConditionalSourcePublicSend
            <2>. SUFFICES ASSUME ConditionalSharedTerminal.failure = <<>>
                          PROVE ConditionalPublicSend = ConditionalSourcePublicSend
                BY <2>shared, SMT
            <2>prefixPass. ConditionalSharedTerminal.failure = <<>> OBVIOUS
        """# + "\n" : ""
        return #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(actionProof), CallerInputPageBlock1
        LOCAL INSTANCE SequenceTheorems
        LOCAL ConditionalSend == INSTANCE \#(sendBindingModule)

        \#(cfgProof)

        \#(initDefinition)ConditionalConfiguredBehavior == \#(initName) /\ [][ConditionalSourceStep]_vars

        ConditionalSendHandle == \#(TLAValue.string(nativeAction.handle))
        ConditionalAuthoredActionLabel == \#(authoredLabel)
        ConditionalCompiledActionLabels ==
            [name \in {\#(TLAValue.string(actionLayout.renderedName))} |-> \#(TLAValue.string(actionLayout.declaration.name))]
        ConditionalNativeFormalNames ==
            [handle \in {ConditionalSendHandle} |-> \#(TLAValue.string(nativeAction.formalLabel))]

        ConditionalPublicSend ==
            LET binding == ConditionalSend!CatalogSendBinding
                route == ConditionalSend!DecodedSendReceiver(binding, ConditionalSendHandle)
                queue == ConditionalNativeVisitorOutput[route.visitor]
            IN ConditionalSend!DecodedPublicSend(binding, ConditionalSnapshot(ConditionalStateBefore),
                    ConditionalSendHandle, queue.callbacks, queue.reasons)
        ConditionalSourcePublicSend ==
        \#(failedBeforeChoice)    LET arm == ConditionalSelectedArm
                terminal == ConditionalIntegerTerminal(arm)
                after == ConditionalSourceSuccessor(arm, terminal)
            IN IF terminal.failure # <<>>
               THEN [kind |-> "evaluationFailure", current |-> ConditionalSnapshot(ConditionalStateBefore),
                     value |-> terminal.failure.payload]
               ELSE [kind |-> "success", current |-> ConditionalSnapshot(after),
                     value |-> [action |-> ConditionalSendHandle, before |-> ConditionalStateBefore, after |-> after]]

        ConditionalPublicSendNamesTheAuthoredAction ==
            LET sent == ConditionalPublicSend
                handle == sent.value.action
                name == ConditionalNativeFormalNames[handle]
            IN sent.kind = "success" =>
                /\ handle \in DOMAIN ConditionalNativeFormalNames
                /\ name \in DOMAIN ConditionalCompiledActionLabels
                /\ ConditionalCompiledActionLabels[name] = ConditionalAuthoredActionLabel

        LOCAL THEOREM ConditionalSelectedSourceHistoryIsCertified ==
            ASSUME ConditionalTypedState\#(reachedPremise)
            PROVE Arithmetic!AssignmentListHistory(FALSE, ConditionalBefore,
                      ConditionalIntegerRows(ConditionalSelectedArm), ConditionalIntegerRun(ConditionalSelectedArm))
        PROOF
        <1>exists. \E history : Arithmetic!AssignmentListHistory(FALSE, ConditionalBefore,
                                 ConditionalIntegerRows(ConditionalSelectedArm), history)
            BY ONLY ConditionalTypedState, \#(reachedFact)ActualConditionalHistoryMatchesTheAuthoredArms, SMT
                DEF ConditionalObservationUsesOrderedRows
        <1>. QED BY ONLY <1>exists, SMT DEF ConditionalIntegerRun

        THEOREM ConditionalPublicSendUsesTheAuthoredVisitor ==
            ASSUME ConditionalTypedState
            PROVE /\ ConditionalPublicSend = ConditionalSourcePublicSend
                  /\ ConditionalPublicSendNamesTheAuthoredAction
        PROOF
        <1>nativeQueue. ConditionalNativeVisitorOutput[ConditionalSendVisitor] = ConditionalCertifiedVisitorOutput
            BY ONLY ActualConditionalHistoryMatchesTheAuthoredArms, ConditionalTypedState
        <1>sendRoute. /\ ConditionalSend!DecodedSendOperands(ConditionalSend!CatalogSendBinding, ConditionalSendHandle)
                       /\ ConditionalSend!DecodedSendReceiver(ConditionalSend!CatalogSendBinding, ConditionalSendHandle).visitor
                              = ConditionalSendVisitor
            <2>receivers. ConditionalSend!CatalogSendBinding.receivers =
                <<[handle |-> ConditionalSendHandle, slot |-> "_execution", visitor |-> ConditionalSendVisitor]>>
                BY ONLY ConditionalSend!CatalogSendBindingReceivers, SMT DEF ConditionalSendHandle, ConditionalSendVisitor
            <2>picked. (CHOOSE index \in DOMAIN ConditionalSend!CatalogSendBinding.receivers :
                            ConditionalSend!CatalogSendBinding.receivers[index].handle = ConditionalSendHandle) = 1
                BY ONLY <2>receivers, SMT
            <2>. QED BY ONLY <2>receivers, <2>picked, ConditionalSend!CatalogSendBindingDecodesReceiverOperands, SMT
                DEF ConditionalSendHandle, ConditionalSend!DecodedSendReceiver
        <1>nativeSend. ConditionalPublicSend = ConditionalSourcePublicSend
            <2>. DEFINE arm == ConditionalSelectedArm
                        rows == ConditionalIntegerRows(arm)
                        terminal == ConditionalIntegerTerminal(arm)
                        prior == ConditionalSnapshot(ConditionalStateBefore)
                        next == ConditionalSnapshot(ConditionalSourceSuccessor(arm, terminal))
                        queue == ConditionalCertifiedVisitorOutput
                        binding == ConditionalSend!CatalogSendBinding
                        outcome == ConditionalSend!PublicSendOutcome(binding, prior, ConditionalSendHandle,
                                                                   queue.callbacks, queue.reasons)
            \#(sharedSend)<2>count. Len(rows) \in Nat
                BY ONLY \#(armFacts)ConditionalFirstIntegerSourceAssignmentsAreSupported,
                    ConditionalSecondIntegerSourceAssignmentsAreSupported, SMT
                    DEF arm, rows, ConditionalSelectedArm, \#(armDefinitions), ConditionalIntegerRows
            <2>terminal. terminal \in Arithmetic!AssignmentPrefixStates
                BY ONLY ConditionalTypedState, \#(armFacts)ConditionalSelectedSourceHistoryIsCertified, <2>count, SMT
                    DEF arm, rows, terminal, ConditionalIntegerTerminal, Arithmetic!AssignmentListHistory
            <2>failure. terminal.failure # <<>> => terminal.failure.payload \in Arithmetic!ArithmeticFailures
                BY ONLY <2>terminal, SMT DEF Arithmetic!AssignmentPrefixStates, Arithmetic!AssignmentFailureEvents
            <2>callbacks. queue.callbacks \in Seq({next})
                BY ONLY \#(armFacts)EmptySeq, SeqDef, LenProperties, SMT DEF queue, next, arm, terminal, ConditionalCertifiedVisitorOutput
            <2>reasons. /\ queue.reasons \in Seq(Arithmetic!ArithmeticFailures)
                         /\ <<>> \notin Arithmetic!ArithmeticFailures
                BY ONLY \#(armFacts)<2>failure, EmptySeq, SeqDef, LenProperties, SMT
                    DEF queue, arm, terminal, ConditionalCertifiedVisitorOutput, Arithmetic!ArithmeticFailures
            <2>send. ConditionalPublicSend = outcome
                BY ONLY <1>nativeQueue, <1>sendRoute, <2>callbacks, <2>reasons,
                    ConditionalSend!DecodedSendUsesTheFirstErrorOrCommitsExactlyOneCallback
                    DEF ConditionalPublicSend, queue, outcome, prior, binding
            <2>source. outcome = ConditionalSourcePublicSend
                BY ONLY \#(armFacts)ConditionalSend!PublicSendOutcomeUsesTheEmptyAndSingletonQueues, SMT
                    DEF outcome, queue, prior, next, arm, terminal, ConditionalSnapshot,
                        ConditionalCertifiedVisitorOutput, ConditionalSourcePublicSend
            <2>. QED BY ONLY <2>send, <2>source
        <1>returnedLabel. ConditionalPublicSendNamesTheAuthoredAction
            <2>handle. ConditionalPublicSend.kind = "success" =>
                       ConditionalPublicSend.value.action = ConditionalSendHandle
                BY ONLY <1>nativeSend, SMT DEF ConditionalSourcePublicSend
            <2>. QED BY ONLY <2>handle, SMT DEF ConditionalPublicSendNamesTheAuthoredAction,
                ConditionalNativeFormalNames, ConditionalCompiledActionLabels,
                ConditionalSendHandle, ConditionalAuthoredActionLabel
        <1>. QED BY ONLY <1>nativeSend, <1>returnedLabel

        \#(typeProof)THEOREM NormalConditionalConfigurationUsesTheAuthoredArms ==
            /\ LocalOrderedRHSActualCFG = LocalOrderedRHSExpectedCFG
        \#(initClaim)    /\ (ConditionalTypedState =>
                  /\ (Next <=> ConditionalSourceStep)
                  /\ (ConditionalNativeStep <=> ConditionalSourceStep)
        \#(observations)          /\ ConditionalPublicSend = ConditionalSourcePublicSend
                  /\ ConditionalPublicSendNamesTheAuthoredAction
                  /\ ConditionalObservationUsesOrderedRows)
        \#(typedClaims)    /\ (\#(behaviorStatement))
        PROOF
        \#(initProof)<1>checked. ConditionalTypedState =>
                  /\ (Next <=> ConditionalSourceStep)
                  /\ (ConditionalNativeStep <=> ConditionalSourceStep)
        \#(observations)          /\ ConditionalPublicSend = ConditionalSourcePublicSend
                  /\ ConditionalPublicSendNamesTheAuthoredAction
                  /\ ConditionalObservationUsesOrderedRows
            BY ONLY ActualConditionalHistoryMatchesTheAuthoredArms, ConditionalPublicSendUsesTheAuthoredVisitor, SMT
        <1>stuttering. ConditionalTypedState => ([Next]_vars <=> [ConditionalSourceStep]_vars)
            BY ONLY <1>checked, PTL
        <1>always. []ConditionalTypedState => (([][Next]_vars) <=> ([][ConditionalSourceStep]_vars))
            BY ONLY <1>stuttering, PTL
        <1>spec. Spec <=> Init /\ [][Next]_vars
            BY ONLY DEF Spec, vars
        \#(invariantProof)<1>behavior. \#(behaviorStatement)
            BY ONLY \#(initFact)\#(typeFacts)<1>spec, <1>always, PTL DEF ConditionalConfiguredBehavior
        <1>. QED BY ONLY \#(selection), \#(initFact)\#(typeFacts)<1>checked, <1>behavior, PTL

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
