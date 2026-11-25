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

    /// Bind each arm’s checked integer assignments and its trailing Boolean literals.
    /// The original rendered module stays an import of the returned proof.
    static func arithmeticHistoryProof(authoredSource: String, modelName: String, parsed: TLASpec,
                                       program: CompiledProgram, rendered: RenderedModule,
                                       nativeSource: String, operations: String, checking: String)
        throws -> (name: String, bytes: Data, configuration: String, configured: (name: String, bytes: Data),
                   arms: [(name: String, bytes: Data)], domain: (name: String, bytes: Data)) {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        let (compilation, continuations) = try parsed.compileRetainingAtomicBranchContinuations(checkingBodyBinderOrdinals: true)
        guard compilation.identity == program.identity,
              modelName.utf8.elementsEqual(program.moduleName.utf8),
              modelName.utf8.elementsEqual(rendered.moduleName.utf8), rendered.imports.isEmpty,
              program.behavior.actions.count == 1, let action = program.behavior.actions.first,
              program.layout.actions.count == 1, let actionLayout = program.layout.actions.first,
              actionLayout.id == action.id,
              let continuation = continuations[actionLayout.declaration.name], continuation.prefix.isEmpty,
              continuation.suffixLength == 0,
              let bodyBinderOrdinals = compilation.orderedActionBodyBinderOrdinals[action.id],
              let source = try AuthoredCopySyntax.conditionalProofInput(source: authoredSource, modelName: modelName),
              source.label == .string(actionLayout.declaration.name),
              let physical = OrderedRHSPhysicalAction.decodeConditional(in: rendered.renderedModuleSource,
                  action: action, program: program), source.arms.count == 2,
              case .tuple(let predicate) = source.predicate, predicate.count == 3,
              predicate[0] == .string("lessThan"),
              physical.condition == .tuple([.tuple([predicate[0]]), predicate[1], predicate[2]])
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
        let swiftLeft = try nativeSourceIdentifier(lhs.declaration.name)
        let swiftRight = try nativeSourceIdentifier(rhs.declaration.name)
        let conditionWords = Parser.parse(source: "(state.state.\(swiftLeft) < state.state.\(swiftRight))")
            .tokens(viewMode: .sourceAccurate).filter { $0.tokenKind != .endOfFile }.map(\.text)
        try verifyConditionalHistoryHelpers(operations: operations, checking: checking)
        let native = try nativeConditionalActionPlans(nativeSource, program: program, predicate: conditionWords)
        let nativeComparison = try conditionalNativeComparison(native.predicate, integers: integers)
        let integerFields = Set(zip(source.declarations, roles).compactMap { declaration, role in
            role == .int ? declaration.name : nil
        })
        let integerModule = "SwiftTLAArithmeticAssignmentSource" + modelName
        let integerDomain = integerModule + "Domain"
        let regions = action.body.orderedAlternativeFailureRegions
        guard regions.count == source.arms.count else { throw invalid }
        let sourceFieldOrdinals = Dictionary(uniqueKeysWithValues: zip(source.fieldOrder, source.fieldOrder.indices))
        var expectedBinders = bodyBinderOrdinals.makeIterator()
        let descriptors = try zip(source.arms, regions).enumerated().map { arm, pair -> ConditionalOverflowArm in
            let (writes, region) = pair
            let emitted = arm == 0 ? physical.ifTrue.action : physical.ifFalse.action
            let scheduled = arm == 0 ? continuation.first : continuation.second
            guard writes.map(\.target).elementsEqual(scheduled.targets, by: { $0.utf8.elementsEqual($1.utf8) }),
                  writes.map(\.terms) == scheduled.sourceCaptures,
                  writes.count == region.bindings.count, writes.count == emitted.captures.count,
                  arm == region.armOrdinal else { throw invalid }
            let ordered = try zip(writes, region.bindings).map { write, binding in
                guard let expectedBinder = expectedBinders.next(), expectedBinder == binding.binder.ordinal,
                      let field = sourceFieldOrdinals[write.target], field == binding.target.ordinal else { throw invalid }
                return (write: write, field: field, type: roles[field])
            }
            let count = ordered.prefix { $0.type == .int }.count
            guard count > 0 else { throw invalid }
            let sourceName = integerModule + "Arm" + String(arm + 1)
            let sourceModule = try source.integerPrefixProof(arm: arm, through: count - 1, parsed: parsed,
                integerFields: integerFields, name: sourceName, domain: integerDomain, prefix: integerSourcePrefixes[arm])
            let integerCaptures = Array(emitted.captures.prefix(count))
            let suffix = try ordered.indices.dropFirst(count).map { index in
                let plan = emitted.captures[index].plan
                guard ordered[index].type == .bool, let value = conditionalLiteral(ordered[index].write.terms),
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
            let physicalRoutes = TLAValue.function(Dictionary(uniqueKeysWithValues: emitted.writes.map {
                (.string($0.key), $0.value)
            }))
            let targets = ordered.map { TLAValue.record(["target": .string($0.write.target), "field": .int($0.field)]) }
            let finalRoutes = TLAValue.function(authoredRoutes)
            return .init(integerInput: (sourceName, Data(sourceModule.utf8)), integerCaptures: integerCaptures,
                         physicalRoutes: physicalRoutes, suffix: .tuple(suffix), targets: .tuple(targets), finalRoutes: finalRoutes)
        }
        guard expectedBinders.next() == nil else { throw invalid }
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
        let history = try name("__SwiftTLAActionFailureHistory\(ordinal)")
        guard let evidence = physical.overflowProbes(in: rendered, actionOrdinal: ordinal, namedHistory: history,
            regions: regions, program: program),
              evidence.sites.allSatisfy({ $0.row <= descriptors[$0.arm].integerCaptures.count })
        else { throw invalid }
        let configuration = try rendered.configuration.render(usesSymmetryReduction: false)
        guard let selection = OrderedRHSCFGProof.normalSelection(cfg: configuration,
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
        let proof = conditionalOverflowProof(name: proofName, model: rendered.moduleName, integerDomain: integerDomain,
            history: history, probes: evidence.sites, aggregate: evidence.aggregate,
            evaluationCheck: selection.checking, ordinal: ordinal, firstBodyBinder: bodyBinderOrdinals.lowerBound,
            keys: .set(keys), before: stateCases(integers), state: state,
            typed: types.joined(separator: " /\\ "), predicate: source.predicate,
            actionName: actionLayout.renderedName, stateKeys: .set(source.fields),
            fullBefore: stateCases(fields), after: stateCases(fields, primed: true),
            nativeComparison: nativeComparison, nativeRows: .tuple(nativeRows),
            nativeWriteOrders: [native.ifTrue.writeOrder, native.ifFalse.writeOrder],
            comparison: "\(lhs.formalName) < \(rhs.formalName)", descriptors: descriptors)
        let initialClauses = initialFields.compactMap { field, sourceField in sourceField.initializer?.predicate(for: field.formalName) }
        let initialPredicate = initialClauses.count == fields.count ? initialClauses.joined(separator: " /\\ ") : nil
        let configuredName = proofName + (initialPredicate == nil ? "ActionOnlyConfiguredProof" : "ConfiguredProof")
        let configured = conditionalConfiguredProof(name: configuredName, actionProof: proofName, cfgProof: selection.proof,
                                                     initialPredicate: initialPredicate)
        return (proofName, Data(proof.utf8), configuration, (configuredName, Data(configured.utf8)),
                descriptors.map(\.integerInput),
                (integerDomain, Data(AuthoredCopySyntax.conditionalIntegerDomain(name: integerDomain, fields: integerFields).utf8)))
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

    private struct ConditionalOverflowArm {
        let integerInput: (name: String, bytes: Data)
        let integerCaptures: [OrderedRHSPhysicalAction.Capture]
        let physicalRoutes: TLAValue
        let suffix: TLAValue
        let targets: TLAValue
        let finalRoutes: TLAValue
        var row: TLAValue {
            .record(["suffix": suffix, "targets": targets, "finalRoutes": finalRoutes])
        }
    }

    private static func conditionalOverflowProof(
        name: String, model: String, integerDomain: String, history: String, probes: [OrderedRHSPhysicalAction.OverflowProbe],
        aggregate: String, evaluationCheck: String, ordinal: Int, firstBodyBinder: Int, keys: TLAValue,
        before: String, state: String, typed: String, predicate: TLAValue, actionName: String,
        stateKeys: TLAValue, fullBefore: String, after: String, nativeComparison: TLAValue, nativeRows: TLAValue,
        nativeWriteOrders: [[String]], comparison: String, descriptors: [ConditionalOverflowArm]
    ) -> String {
        let tables = ["ConditionalFirstIntegerTable", "ConditionalSecondIntegerTable"]
        let planNames = zip(tables, descriptors).map { table, arm in
            arm.integerCaptures.indices.map { "\(table)Plan\($0 + 1)" }
        }
        let native = conditionalNativeOutputProof(
            writeOrders: nativeWriteOrders, integerDefinitions: tables + planNames.flatMap { $0 })
        let certified = conditionalIntegerHistoryProof(
            descriptors, firstBodyBinder: firstBodyBinder, probes: probes, history: history,
            tables: tables, planNames: planNames, native: native)
        let sourceModules = ([integerDomain] + descriptors.map { $0.integerInput.name }).joined(separator: ", ")
        let guards = probes.map(\.failed.name).joined(separator: ", ")
        let stepCases = tables.indices.map { arm in
            #"""
            <2>arm\#(arm + 1). CASE ConditionalSelectedArm = \#(arm + 1)
                BY ONLY <2>arm\#(arm + 1), <2>select, SMT DEF ConditionalPhysicalStep, \#(actionName),
                    ConditionalTableStep, ConditionalIntegerTable, \#(tables[arm]), \#(tables[arm])Values,
                    \#(planNames[arm].joined(separator: ", ")), ConditionalStateKeys, ConditionalStateBefore, ConditionalStateAfter, ConditionalSourceRows,
                    ConditionalPhysicalRoutes, ConditionalPhysicalRouteTable, Arithmetic!CopyMaterializedState, Arithmetic!CopyReferenceValue,
                    Arithmetic!RenderedAssignmentsPass, Arithmetic!EveryRenderedGuardPasses
            """#
        }.joined(separator: "\n    ")
        let noSuccessorFacts = probes.enumerated().map { index, probe in
            #"""
            <2>probe\#(index + 1). \#(probe.failed.name) => ~ENABLED Next
                BY ONLY ExpandENABLED, SMT DEF Next, \#(actionName), \#(probe.failed.name)
            """#
        }.joined(separator: "\n    ")
        let noSuccessorLabels = probes.indices.map { "<2>probe\($0 + 1)" }.joined(separator: ", ")
        return #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(model), TLAPS, Sequences, \#(sourceModules)
        LOCAL INSTANCE SequenceTheorems

        LOCAL ConditionalLayoutIntKeys == \#(keys)
        ConditionalIntValues == \#(TLAValue.int(Int.min))..\#(TLAValue.int(Int.max))
        ConditionalTypedState == \#(typed)
        ConditionalBefore == [key \in ConditionalLayoutIntKeys |-> CASE \#(before) [] OTHER -> 0]
        ConditionalEntry == <<\#(state)>>
        ConditionalStateKeys == \#(stateKeys)
        ConditionalStateBefore == [key \in ConditionalStateKeys |-> CASE \#(fullBefore) [] OTHER -> 0]
        ConditionalStateAfter == [key \in ConditionalStateKeys |-> CASE \#(after) [] OTHER -> 0]
        ConditionalSourceRows == \#(TLAValue.tuple(descriptors.map(\.row)))
        ConditionalSourceComparison == \#(predicate)
        ConditionalNativeComparison == \#(nativeComparison)
        ConditionalNativeRows == \#(nativeRows)
        ConditionalActionOrdinal == \#(ordinal)
        ConditionalArms == 1..Len(ConditionalSourceRows)

        ConditionalArmFor(comparison) ==
            LET operand(pair) == Arithmetic!CopyReferenceValue(ConditionalBefore, <<>>, pair)
            IN IF operand(comparison[2]) < operand(comparison[3]) THEN 1 ELSE 2
        ConditionalSelectedArm == ConditionalArmFor(ConditionalSourceComparison)

        ActualConditionalHistory == \#(history)
        ConditionalSelectedEvaluationCheck == \#(evaluationCheck)
        ConditionalPhysicalStep == \#(actionName)
        \#(certified.definitions)

        THEOREM ActualConditionalHistoryMatchesTheAuthoredArms ==
            ASSUME ConditionalTypedState
            PROVE /\ ActualConditionalHistory = ConditionalSourceHistory
                  /\ ConditionalNativeHistory(TRUE) = ConditionalSourceHistory
                  /\ (ConditionalSelectedEvaluationCheck <=> ConditionalSourceHistory = <<>>)
                  /\ (ConditionalPhysicalStep <=> ConditionalSourceStep)
                  /\ (ConditionalNativeStep <=> ConditionalSourceStep)
                  /\ (Next <=> ConditionalSourceStep)
                  /\ vars = ConditionalEntry
                  /\ (ConditionalSourceHistory # <<>> => ~ENABLED Next)
                  /\ ConditionalObservationUsesOrderedRows
        PROOF
        <1>shape. ConditionalArms = 1..2
            BY ONLY SMT DEF ConditionalArms, ConditionalSourceRows
        <1>selector. ConditionalSelectedArm \in ConditionalArms
            BY ONLY <1>shape, SMT DEF ConditionalSelectedArm, ConditionalArmFor
        <1>comparison. ConditionalNativeComparison = ConditionalSourceComparison
            BY ONLY SMT DEF ConditionalNativeComparison, ConditionalSourceComparison
        <1>selected. ConditionalNativeSelectedArm = ConditionalSelectedArm
            BY ONLY <1>comparison, SMT DEF ConditionalNativeSelectedArm, ConditionalSelectedArm
        <1>layout. /\ vars = ConditionalEntry
                   /\ (Next <=> ConditionalPhysicalStep)
            BY ONLY SMT DEF vars, ConditionalEntry, Next, ConditionalPhysicalStep
        <1>tableStep. ConditionalPhysicalStep <=> ConditionalTableStep(ConditionalSelectedArm)
            <2>select. (ConditionalSelectedArm = 1) <=> \#(comparison)
                BY ONLY SMT DEF ConditionalSelectedArm, ConditionalArmFor, ConditionalSourceComparison,
                    ConditionalBefore, ConditionalLayoutIntKeys, Arithmetic!CopyReferenceValue
            \#(stepCases)
            <2>. QED BY ONLY <1>shape, <1>selector, <2>arm1, <2>arm2, SMT
        \#(certified.steps)
        <1>checking. ConditionalSelectedEvaluationCheck <=>
                (\A p \in DOMAIN ConditionalProbePositions : ~ConditionalProbeGuards[p])
            BY ONLY <1>probeSlots, SMT DEF ConditionalSelectedEvaluationCheck,
                \#(evaluationCheck), \#(aggregate), ConditionalProbeGuards, \#(guards)
        <1>empty. ActualConditionalHistory = <<>> <=>
                (\A p \in DOMAIN ConditionalProbePositions : ~ConditionalProbeGuards[p])
            BY ONLY <1>probeOne, <1>probeNone, SMT DEF ConditionalExportedProbe
        <1>noSuccessor. ConditionalSourceHistory # <<>> => ~ENABLED Next
            \#(noSuccessorFacts)
            <2>. QED BY ONLY \#(noSuccessorLabels), <1>physicalHistory, <1>empty, <1>probeSlots, SMT
                DEF ConditionalProbeGuards, \#(guards)
        <1>. QED BY ONLY <1>physicalHistory, <1>nativeHistory, <1>checking, <1>empty, <1>layout,
            <1>step, <1>nativeSuccess, <1>noSuccessor, <1>certified, PTL DEF ConditionalSourceHistory, ConditionalSourceStep

        ====
        """#
    }

    private static func conditionalIntegerHistoryProof(
        _ arms: [ConditionalOverflowArm], firstBodyBinder: Int, probes: [OrderedRHSPhysicalAction.OverflowProbe],
        history: String, tables: [String], planNames: [[String]], native: (definitions: String, steps: String)
    ) -> (definitions: String, steps: String) {
        func tuple(_ values: [String]) -> String { "<<\(values.joined(separator: ", "))>>" }
        func raw(_ name: String, _ captures: [OrderedRHSPhysicalAction.Capture], _ plans: [String]) -> String {
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
        let coordinates = tuple(probes.map { "<<\($0.arm + 1), \($0.row), \($0.node)>>" })
        let beforeFrames = tuple(probes.map { probe in
            let arm = arms[probe.arm]
            let prefix = arm.integerCaptures.prefix(probe.row - 1)
            let frame = tuple(prefix.enumerated().map { index, capture in
                let origin = "ConditionalAssignmentOrigins(\(probe.arm + 1))[\(index + 1)]"
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
        let exportedNames = probes.flatMap { [$0.failed.name, $0.operation.name, $0.operands.name] }
            .joined(separator: ", ")
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
        let actual = tables.indices.map { raw(tables[$0], arms[$0].integerCaptures, planNames[$0]) }
        let tableDefinitions = tables + planNames.flatMap { $0 }
        let physicalTables = tableDefinitions.joined(separator: ", ")
        let evaluatedTables = (tableDefinitions + tables.map { $0 + "Values" }).joined(separator: ", ")
        let sourceDefinitions = sources.flatMap { name in
            ["Rows", "Nodes", "NodeCounts", "NodeKinds", "NodeLiterals",
             "NodeReadKeys", "NodeLeft", "NodeRight", "Targets"].map { "\(name)\($0)" }
        }.joined(separator: ",\n                ")
        let supported = sources.map { "\($0)AssignmentsAreSupported" }.joined(separator: ", ")
        let operandCases = sources.indices.map { index in
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
        let routedReads = sources.indices.map { arm -> (prefixes: [String], proof: String) in
            let source = sources[arm]
            let table = tables[arm]
            let names = arms[arm].integerCaptures.indices.map { "\(table)SourcePrefix\($0)" }
            let prefixes = names.enumerated().map { count, name in
                count == 0
                    ? "LOCAL \(name) == Arithmetic!CopyEntryRoutes(ConditionalIntKeys)"
                    : "LOCAL \(name) == Arithmetic!CopyReplace(ConditionalIntKeys, \(names[count - 1]), "
                        + "\(source)Targets[\(count)], <<\"capture\", \(count)>>)"
            }
            let physicalPlans = tuple(planNames[arm])
            let physicalPlanDefinitions = planNames[arm].joined(separator: ", ")
            return (prefixes, #"""
            <3>arm\#(arm + 1). CASE arm = \#(arm + 1)
                <4>range. Len(rows) = \#(names.count) /\ index \in 1..\#(names.count)
                    BY ONLY <3>arm\#(arm + 1), <1>integerRows, <2>shape, (arm \in ConditionalArms),
                        (index \in DOMAIN rows), SMT DEF rows
                <4>targets. \A position \in 1..Len(rows) : rows[position].target = \#(source)Targets[position]
                    BY ONLY <3>arm\#(arm + 1), <2>shape, \#(source)RowsProjectEmittedColumns, SMT
                        DEF rows, ConditionalIntegerRows
                <4>. DEFINE maps == \#(tuple(names))
                <4>transitions. /\ maps[1] = Arithmetic!CopyEntryRoutes(ConditionalIntKeys)
                                /\ \A position \in 1..prefixCount :
                                    maps[position + 1] = Arithmetic!CopyReplace(ConditionalIntKeys, maps[position],
                                        \#(source)Targets[position], <<"capture", position>>)
                    BY ONLY <4>range, IsaM("simp"), SMT DEF maps, prefixCount, \#(names.joined(separator: ", "))
                <4>indexed. routes[index - 1] = maps[index]
                    <5>table. routeTable(maps)
                        BY ONLY <4>range, <4>transitions, <4>targets, SMT DEF routeTable, prefixCount
                    <5>. QED BY ONLY <3>aligned, <5>table
                <4>columns. /\ rows[index].emitted.count = \#(source)NodeCounts[index]
                             /\ rows[index].emitted.nodes = \#(source)Nodes(index)
                    BY ONLY <3>arm\#(arm + 1), (index \in DOMAIN rows),
                        \#(source)RowsProjectEmittedColumns, SMT DEF rows, ConditionalIntegerRows
                <4>sourceReads. /\ expected.count = \#(source)NodeCounts[index]
                                 /\ \A node \in 1..expected.count : expected.kinds[node] = "read" =>
                                       /\ \#(source)NodeKinds[index][node] = "read"
                                       /\ expected.reads[node] = \#(source)NodeReadKeys[index][node]
                    BY ONLY <4>columns, SMT DEF expected, Arithmetic!AssignmentRhsPlan,
                        Arithmetic!ExtractedNodePlan, \#(source)Nodes
                <4>physicalReads. plan.reads = \#(physicalPlans)[index].reads
                    BY ONLY <3>arm\#(arm + 1), <4>range, IsaM("simp"), SMT
                        DEF plan, raw, ConditionalIntegerTable, \#(table)
                <4>lookup. \A node \in 1..\#(source)NodeCounts[index] : \#(source)NodeKinds[index][node] = "read" =>
                    LET key == \#(source)NodeReadKeys[index][node]
                    IN /\ key \in ConditionalIntKeys
                       /\ \#(physicalPlans)[index].reads[node] = maps[index][key]
                    BY ONLY <4>range, IsaM("simp"), SMT DEF maps, \#(physicalPlanDefinitions), ConditionalIntKeys, Arithmetic!CopyEntryRoutes,
                        Arithmetic!CopyReplace, \#(source)NodeKinds, \#(source)NodeCounts,
                        \#(source)NodeReadKeys, \#(source)Targets, \#(names.joined(separator: ", "))
                <4>. QED BY ONLY <4>indexed, <4>sourceReads, <4>physicalReads, <4>lookup, SMT
            """#)
        }
        let ranges = arms.map { "1..\($0.integerCaptures.count)" }
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
        return (#"""
        \#(actual.joined(separator: "\n"))
        \#(routedReads.flatMap(\.prefixes).joined(separator: "\n"))
        ConditionalIntegerRows(arm) ==
            IF arm = 1 THEN \#(sources[0])Rows ELSE \#(sources[1])Rows
        ConditionalIntegerTable(arm) ==
            IF arm = 1 THEN \#(tables[0]) ELSE \#(tables[1])
        ConditionalAssignmentOrigins(arm) ==
            LET writes == ConditionalSourceRows[arm].targets
                start == \#(firstBodyBinder) + (IF arm = 1 THEN 0 ELSE Len(ConditionalSourceRows[1].targets))
            IN [i \in DOMAIN writes |-> [binding |-> start + (i - 1), field |-> writes[i].field]]
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

        LOCAL ConditionalProbePositions == \#(coordinates)
        LOCAL ConditionalProbeGuards == \#(tuple(guardNames))
        LOCAL ConditionalProbePayloads == \#(payloads)
        LOCAL ConditionalProbeBefore == \#(beforeFrames)
        LOCAL ConditionalExportedProbe(p) ==
            LET place == ConditionalProbePositions[p]
                arm == place[1]
                origin == ConditionalAssignmentOrigins(arm)[place[2]]
            IN IF ConditionalProbeGuards[p] THEN
                <<[source |-> ConditionalEntry, action |-> ConditionalActionOrdinal, branch |-> arm - 1,
                  site |-> origin.binding, target |-> origin.field, payload |-> ConditionalProbePayloads[p],
                  before |-> ConditionalProbeBefore[p]]>>
               ELSE <<>>
        LOCAL ConditionalExportedHistory == \#(events)
        ConditionalOrderedStep(arm, terminal) ==
            /\ terminal.failure = <<>>
            /\ LET row == ConditionalSourceRows[arm]
               IN ConditionalStateAfter = Arithmetic!CopyMaterializedState(ConditionalStateKeys, ConditionalStateBefore,
                      terminal.completed \o row.suffix, row.finalRoutes)
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
        ConditionalSourceHistory == ConditionalOrderedFailure(ConditionalSelectedArm, ConditionalIntegerTerminal(ConditionalSelectedArm))
        ConditionalSourceStep == ConditionalOrderedStep(ConditionalSelectedArm, ConditionalIntegerTerminal(ConditionalSelectedArm))
        ConditionalObservationUsesOrderedRows ==
            LET arm == ConditionalSelectedArm
                rows == ConditionalIntegerRows(arm)
            IN \E history :
                LET terminal == history[Len(rows)]
                IN /\ Arithmetic!AssignmentListHistory(FALSE, ConditionalBefore, rows, history)
                   /\ Arithmetic!AssignmentListHistory(TRUE, ConditionalBefore, rows, history)
                   /\ ActualConditionalHistory = ConditionalOrderedFailure(arm, terminal)
                   /\ ConditionalNativeHistory(TRUE) = ConditionalOrderedFailure(arm, terminal)
                   /\ (ConditionalPhysicalStep <=> ConditionalOrderedStep(arm, terminal))
                   /\ (ConditionalNativeStep <=> ConditionalOrderedStep(arm, terminal))
        """#, #"""
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
                BY ONLY DEF rows, raw, Arithmetic!RenderedAssignmentInventory
            <2>. TAKE index \in DOMAIN rows
            <2>. DEFINE plan == raw.plans[index]
                        expected == Arithmetic!AssignmentRhsPlan(rows[index])
                        completed == Arithmetic!HistoryPrefix(raw.roots, index - 1)
            <2>operands. Arithmetic!PhysicalAssignmentOperandsMatch(rows[index], plan)
                \#(operandCases)
                <3>. QED BY ONLY <2>cases, <3>arm1, <3>arm2
            <2>. DEFINE routes == Arithmetic!DirectCopyRoutes(ConditionalIntKeys, rows)
            <2>reads. \A node \in 1..expected.count : expected.kinds[node] = "read" =>
                /\ expected.reads[node] \in ConditionalIntKeys
                /\ plan.reads[node] = routes[index - 1][expected.reads[node]]
                <3>. DEFINE prefixCount == Len(rows) - 1
                            routeTable(maps) ==
                                /\ maps[1] = Arithmetic!CopyEntryRoutes(ConditionalIntKeys)
                                /\ \A position \in 1..prefixCount :
                                    maps[position + 1] = Arithmetic!CopyReplace(ConditionalIntKeys, maps[position],
                                        rows[position].target, <<"capture", position>>)
                <3>bounds. /\ prefixCount \in 0..Len(rows) /\ index \in 1..(prefixCount + 1)
                    BY ONLY <2>shape, (index \in DOMAIN rows), SMT DEF prefixCount
                <3>aligned. ASSUME NEW maps, routeTable(maps)
                            PROVE routes[index - 1] = maps[index]
                    BY ONLY <2>shape, <3>bounds, routeTable(maps), Arithmetic!DirectCopyRoutesAgreeWithRecordedPrefixes,
                        SMT DEF routes, routeTable
                \#(routedReads.map(\.proof).joined(separator: "\n        "))
                <3>. QED BY ONLY <2>cases, <3>arm1, <3>arm2, SMT
            <2>matches. Arithmetic!PhysicalAssignmentReadsMatchRoutes(rows, index, plan)
                BY ONLY <2>operands, <2>reads DEF expected, routes, Arithmetic!PhysicalAssignmentReadsMatchRoutes
            <2>terms. Arithmetic!RenderedRhsTerms(plan, ConditionalBefore, completed, raw.starts[index], raw.terms[index])
                BY ONLY <2>cases, <2>shape, (index \in DOMAIN rows), <1>integerEntry, SMT
                    DEF plan, raw, completed, ConditionalIntegerTable, \#(evaluatedTables),
                        ConditionalBefore, ConditionalLayoutIntKeys, Arithmetic!AssignmentBindings, Arithmetic!AssignmentIntValues,
                        Arithmetic!RenderedRhsTerms, Arithmetic!PhysicalRhsBindings, Arithmetic!CopyReferenceValue,
                        Arithmetic!HistoryPrefix
            <2>guards. Arithmetic!RenderedRhsGuards(plan, raw.terms[index], raw.guards[index])
                BY ONLY <2>cases, <2>shape, (index \in DOMAIN rows), SMT
                    DEF plan, raw, ConditionalIntegerTable, \#(evaluatedTables),
                        Arithmetic!RenderedRhsGuards, Arithmetic!GeneratedAddDefined, Arithmetic!SmallAddOperands
            <2>roots. raw.roots[index] = raw.terms[index][plan.count]
                BY ONLY <2>cases, <2>shape, (index \in DOMAIN rows), SMT
                    DEF plan, raw, ConditionalIntegerTable, \#(evaluatedTables)
            <2>. QED BY ONLY <2>matches, <2>terms, <2>guards, <2>roots DEF plan, completed
        <1>probeSlots. /\ DOMAIN ConditionalProbePositions = 1..\#(probes.count)
                        /\ DOMAIN ConditionalProbeGuards = DOMAIN ConditionalProbePositions
                        /\ \A p, q \in DOMAIN ConditionalProbePositions :
                                ConditionalProbePositions[p] = ConditionalProbePositions[q] => p = q
            BY ONLY SMT DEF ConditionalProbePositions, ConditionalProbeGuards
        <1>probeInventory. \A arm \in ConditionalArms :
            LET raw == ConditionalIntegerTable(arm)
                count == Len(ConditionalIntegerRows(arm))
            IN \A row \in 1..count : \A node \in 1..raw.plans[row].count :
               raw.plans[row].kinds[node] = "add" =>
                   \E p \in DOMAIN ConditionalProbePositions : ConditionalProbePositions[p] = <<arm, row, node>>
            BY ONLY <1>shape, <1>integerRows, <1>probeSlots, SMT DEF ConditionalProbePositions,
                ConditionalIntegerTable, ConditionalIntegerRows, Arithmetic!SupportedAssignmentList,
                \#(physicalTables), \#(sourceDefinitions)
        <1>probeReach. \A p \in DOMAIN ConditionalProbePositions :
            LET place == ConditionalProbePositions[p]
                arm == place[1]
                raw == ConditionalIntegerTable(arm)
                count == Len(ConditionalIntegerRows(arm))
            IN /\ arm \in ConditionalArms
               /\ place[2] \in 1..count /\ place[3] \in 1..raw.plans[place[2]].count
               /\ (ConditionalProbeGuards[p] <=> arm = ConditionalSelectedArm /\
                   Arithmetic!RenderedAssignmentFailsAt(raw, count, place[2], place[3]))
            BY ONLY <1>shape, <1>integerRows, <1>probeSlots, SMT DEF
                ConditionalProbePositions, ConditionalProbeGuards, ConditionalIntegerTable, ConditionalIntegerRows,
                ConditionalSelectedArm, ConditionalArmFor, ConditionalSourceComparison, ConditionalBefore, ConditionalLayoutIntKeys,
                Arithmetic!CopyReferenceValue, Arithmetic!RenderedAssignmentFailsAt, Arithmetic!RenderedAssignmentsPass,
                Arithmetic!FirstRejectedRenderedGuard, Arithmetic!EveryRenderedGuardPasses,
                \#(evaluatedTables), \#(sourceDefinitions), \#(guardNames.joined(separator: ", "))
        <1>probeValues. \A p \in DOMAIN ConditionalProbePositions :
            ConditionalProbeGuards[p] =>
                LET place == ConditionalProbePositions[p]
                    arm == place[1]
                    row == place[2]
                    node == place[3]
                    raw == ConditionalIntegerTable(arm)
                    rows == ConditionalIntegerRows(arm)
                    completed == Arithmetic!HistoryPrefix(raw.roots, row - 1)
                    failure == Arithmetic!RenderedAssignmentFailure(rows, ConditionalBefore, raw, row, node)
                IN /\ ConditionalProbePayloads[p] = failure.payload
                   /\ ConditionalProbeBefore[p] = ConditionalFailurePrefix(arm, completed)
            BY ONLY <1>probeSlots, <1>probeReach, SMT DEF ConditionalProbePositions, ConditionalProbePayloads,
                ConditionalProbeBefore, ConditionalFailurePrefix, ConditionalAssignmentOrigins, ConditionalSourceRows, ConditionalIntegerTable,
                Arithmetic!RenderedAssignmentFailure, Arithmetic!RenderedTermOverflow, Arithmetic!GeneratedOverflow, Arithmetic!HistoryPrefix,
                \#(evaluatedTables), \#(exportedNames)
        <1>probeUnique. \A p, q \in DOMAIN ConditionalProbePositions :
                          ConditionalProbeGuards[p] /\ ConditionalProbeGuards[q] => p = q
            BY ONLY <1>probeSlots, <1>probeReach, SMT
                DEF Arithmetic!RenderedAssignmentFailsAt, Arithmetic!RenderedAssignmentsPass,
                    Arithmetic!FirstRejectedRenderedGuard, Arithmetic!EveryRenderedGuardPasses
        <1>probeWire. ActualConditionalHistory = ConditionalExportedHistory
            BY ONLY SMT DEF ActualConditionalHistory, ConditionalExportedHistory, ConditionalExportedProbe,
                ConditionalProbePositions, ConditionalProbeGuards, ConditionalProbePayloads, ConditionalProbeBefore,
                ConditionalAssignmentOrigins, ConditionalSourceRows, ConditionalEntry, ConditionalActionOrdinal, \#(history), \#(exportedNames)
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
        \#(native.steps)
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
            <2>physical. ActualConditionalHistory = ConditionalSourceHistory
                <3>pass. CASE Arithmetic!RenderedAssignmentsPass(raw, last)
                    <4>empty. terminal.failure = <<>>
                        BY ONLY <3>pass, <2>reached, SMT DEF Arithmetic!RenderedAssignmentHistoryAt, ConditionalIntegerTerminal, rows, last, terminal
                    <4>disabled. \A p \in DOMAIN ConditionalProbePositions : ~ConditionalProbeGuards[p]
                        BY ONLY <3>pass, <1>probeReach, SMT DEF arm, rows, raw, last,
                            Arithmetic!RenderedAssignmentsPass, Arithmetic!RenderedAssignmentFailsAt,
                            Arithmetic!FirstRejectedRenderedGuard, Arithmetic!EveryRenderedGuardPasses
                    <4>. QED BY ONLY <4>empty, <4>disabled, <1>probeNone DEF ConditionalOrderedFailure, ConditionalSourceHistory, arm, terminal
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
                    <4>probe. PICK p \in DOMAIN ConditionalProbePositions :
                                       ConditionalProbePositions[p] = <<arm, row, node>>
                        BY ONLY <4>row, <4>node, <4>result, <1>selector, <1>probeInventory, SMT DEF arm, rows, raw, last
                    <4>fires. ConditionalProbeGuards[p]
                        BY ONLY <4>probe, <4>node, <1>probeReach, SMT DEF arm, rows, raw, last
                    <4>label. ActualConditionalHistory = ConditionalExportedProbe(p)
                        BY ONLY <4>probe, <4>fires, <1>probeOne
                    <4>data. /\ ConditionalProbePayloads[p] = terminal.failure.payload
                               /\ ConditionalProbeBefore[p] = ConditionalFailurePrefix(arm, terminal.completed)
                        BY ONLY <4>probe, <4>fires, <4>result, <1>probeValues, SMT DEF rows, raw
                    <4>. QED BY ONLY <4>label, <4>data, <4>fires, <4>probe, <4>result, SMT
                        DEF ConditionalExportedProbe, ConditionalSourceHistory, arm, terminal, ConditionalOrderedFailure, ConditionalLabeledFailure,
                            Arithmetic!RenderedAssignmentFailure
                <3>. QED BY ONLY <3>pass, <3>fail, SMT
            <2>. QED BY ONLY <2>physical
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
                BY ONLY <2>pass, <2>reached, <2>length, <1>tableStep, <1>selector, <1>shape, <1>finalRoutes, SMT
                    DEF ConditionalTableStep, ConditionalSourceStep, ConditionalOrderedStep, ConditionalIntegerTerminal,
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
                <3>. QED BY ONLY <2>fail, <3>failure, <2>length, <1>tableStep, SMT
                    DEF ConditionalTableStep, ConditionalSourceStep, ConditionalOrderedStep, arm, last, terminal, raw
            <2>. QED BY ONLY <2>pass, <2>fail, SMT
        <1>certified. ConditionalObservationUsesOrderedRows
            <2>. DEFINE arm == ConditionalSelectedArm
                        rows == ConditionalIntegerRows(arm)
            <2>. WITNESS ConditionalIntegerRun(arm)
            <2>. QED BY ONLY <1>selector, <1>integerRuns, <1>physicalHistory, <1>nativeHistory, <1>step, <1>nativeSuccess, SMT
                DEF ConditionalObservationUsesOrderedRows, ConditionalIntegerTerminal, ConditionalSourceHistory, ConditionalSourceStep, arm, rows
        """#)
    }

    private static func conditionalConfiguredProof(name: String, actionProof: String, cfgProof: String,
                                                   initialPredicate: String?) -> String {
        let initName = initialPredicate == nil ? "Init" : "ConditionalSourceInit"
        let initDefinition = initialPredicate.map { "ConditionalSourceInit == \($0)\n" } ?? ""
        let initClaim = initialPredicate == nil ? "" : "    /\\ (Init <=> ConditionalSourceInit)\n"
        let initProof = initialPredicate == nil ? "" : "<1>initial. Init <=> ConditionalSourceInit\n    BY ONLY SMT DEF Init, ConditionalSourceInit\n"
        let initFact = initialPredicate == nil ? "" : "<1>initial, "
        return #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(actionProof), CallerInputPageBlock1

        \#(cfgProof)

        \#(initDefinition)ConditionalConfiguredBehavior == \#(initName) /\ [][ConditionalSourceStep]_vars

        THEOREM NormalConditionalConfigurationUsesTheAuthoredArms ==
            /\ LocalOrderedRHSActualCFG = LocalOrderedRHSExpectedCFG
        \#(initClaim)    /\ (ConditionalTypedState =>
                  /\ (Next <=> ConditionalSourceStep)
                  /\ (ConditionalNativeStep <=> ConditionalSourceStep)
                  /\ (ConditionalSelectedEvaluationCheck <=> ConditionalSourceHistory = <<>>)
                  /\ (ConditionalSelectedEvaluationCheck <=> ActualConditionalHistory = <<>>)
                  /\ (ConditionalSelectedEvaluationCheck <=> ConditionalNativeHistory(TRUE) = <<>>)
                  /\ ConditionalObservationUsesOrderedRows)
            /\ ([]ConditionalTypedState => (Spec <=> ConditionalConfiguredBehavior))
        PROOF
        \#(initProof)<1>checked. ConditionalTypedState =>
                  /\ (Next <=> ConditionalSourceStep)
                  /\ (ConditionalNativeStep <=> ConditionalSourceStep)
                  /\ (ConditionalSelectedEvaluationCheck <=> ConditionalSourceHistory = <<>>)
                  /\ (ConditionalSelectedEvaluationCheck <=> ActualConditionalHistory = <<>>)
                  /\ (ConditionalSelectedEvaluationCheck <=> ConditionalNativeHistory(TRUE) = <<>>)
                  /\ ConditionalObservationUsesOrderedRows
            BY ONLY ActualConditionalHistoryMatchesTheAuthoredArms, SMT
        <1>stuttering. ConditionalTypedState => ([Next]_vars <=> [ConditionalSourceStep]_vars)
            BY ONLY <1>checked, PTL
        <1>always. []ConditionalTypedState => (([][Next]_vars) <=> ([][ConditionalSourceStep]_vars))
            BY ONLY <1>stuttering, PTL
        <1>spec. Spec <=> Init /\ [][Next]_vars
            BY ONLY DEF Spec, vars
        <1>behavior. []ConditionalTypedState => (Spec <=> ConditionalConfiguredBehavior)
            BY ONLY \#(initFact)<1>spec, <1>always, PTL DEF ConditionalConfiguredBehavior
        <1>. QED BY ONLY NormalOrderedRHSCFGSelectsSpecDeadlockAndEvaluationChecking, \#(initFact)<1>checked, <1>behavior, PTL

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
