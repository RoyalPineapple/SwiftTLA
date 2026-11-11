import Foundation
import SwiftTLA

private struct NativeInitialBindingOutput: Codable {
    let name: String
    let value: TLAValue
}

private struct NativeInitialEventOutput: Codable {
    let site: Int
    let kind: String
    let operands: [Int]
    let before: [NativeInitialBindingOutput]
}

private struct NativeInitialFailureOutput: Codable {
    let successfulInitialStates: Int
    let failures: [NativeInitialEventOutput]
    let site: Int
    let kind: String
    let operands: [Int]
}

package struct InitialFailureEvidenceReport: Codable, Sendable {
    package let schema: String
    package let sourceSHA: String
    package let module: String
    package let moduleSHA256: String
    package let checkModule: String
    package let checkModuleSHA256: String
    package let checkConfigurationSHA256: String
    package let proofSHA256: String
    package let nativeSHA256: String
    package let sourceCompilationIdentity: String
    package let sourceInitializersSHA256: String
    package let loweredInitializersSHA256: String
    package let resolvedInitializersSHA256: String
    package let resolvedVariableTypesSHA256: String
    package let layoutSHA256: String
    package let initializationOrderSHA256: String
    package let prefixOrdersSHA256: String
    package let controlSeedsSHA256: String
    package let graphCompared: Bool
    package let result: String
    package let site: Int
    package let kind: String
    package let operands: [Int]
}

package enum InitialFailureEvidenceError: Error, Equatable {
    case unsupportedNativeOutcome
    case unsupportedGeneratedOutput
    case invalidSourceSHA
}

/// shortcut: one deterministic corpus case; extend after generic branch correspondence is established.
package enum InitialFailureEvidence {
    private static let proofModule = "SwiftTLAInitialFailureProof"
    private static let failureKind = "integerOverflow.addition"

    package static func prepare(sourceSHA: String, to directory: URL) throws -> InitialFailureEvidenceReport {
        guard TLCReferencePin.isRevision(sourceSHA) else {
            throw InitialFailureEvidenceError.invalidSourceSHA
        }
        let native = try CheckedAdditionPrefixInitialModel.initialOutcomes()
        guard native.states.isEmpty, let site = native.firstFailureInitializerOrdinal,
              case .integerOverflow(.addition, let operands)? = native.firstFailure,
              operands.count == 2 else {
            throw InitialFailureEvidenceError.unsupportedNativeOutcome
        }
        let failures = try native.failures.map { event -> NativeInitialEventOutput in
            guard case .initializer(let ordinal) = event.site,
                  case .integerOverflow(.addition, let operands) = event.failure,
                  operands.count == 2 else { throw InitialFailureEvidenceError.unsupportedNativeOutcome }
            let before = try event.formalBindingsBeforeFailure().entries.map {
                NativeInitialBindingOutput(name: $0.token.description, value: $0.value)
            }
            return .init(site: ordinal, kind: failureKind, operands: operands, before: before)
        }
        guard failures.count == 1 else { throw InitialFailureEvidenceError.unsupportedNativeOutcome }
        let source = CheckedAdditionPrefixInitialModel.spec
        let compilation = try source.compile()
        let typeInputs = try CompiledTypeInputs(compilation: compilation,
            types: CompiledTypeContext(enums: .init(), formalNames: [:])) { spelling in
            guard ["Int", "Swift.Int"].contains(spelling) else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            return .int
        }
        let resolvedProgram = try CompiledProgram(inputs: typeInputs)
        let resolvedModule = try resolvedProgram.renderModule()
        let resolvedConfiguration = try resolvedModule.configuration.render(usesSymmetryReduction: false)
        let rendered = try CheckedAdditionPrefixInitialModel.render()
        let loweredOutput = try compilation.render().tlaBundle
        guard case .compiled(let identity, _, _) = rendered.tlaBundle.provenance,
              identity == compilation.identity,
              resolvedProgram.identity == compilation.identity,
              let generatedConfiguration = rendered.tlaBundle.root.cfg,
              let loweredConfiguration = loweredOutput.root.cfg,
              rendered.tlaBundle.imports.isEmpty, loweredOutput.imports.isEmpty,
              resolvedModule.imports.isEmpty,
              rendered.tlaBundle.root.tla.utf8.elementsEqual(loweredOutput.root.tla.utf8),
              rendered.tlaBundle.root.tla.utf8.elementsEqual(resolvedModule.renderedModuleSource.utf8),
              generatedConfiguration.utf8.elementsEqual(loweredConfiguration.utf8),
              generatedConfiguration.utf8.elementsEqual(resolvedConfiguration.utf8) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let sourceInitializers = try sourceInitializerPlans(source)
        let loweredInitializers = try initializerPlans(layout: compilation.layout,
            initializations: compilation.semantics.behavior.initializations, requireTypes: false)
        let resolvedInitializers = try initializerPlans(layout: resolvedProgram.layout,
            initializations: resolvedProgram.behavior.initializations, requireTypes: true)
        let recordInputs = try initialRecordInputs(resolvedProgram)
        guard let check = try rendered.initialEvaluationFailureBundle(capturingRecord: true) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let module = rendered.tlaBundle.root
        let proof = try proofSource(module: module.name, tla: module.tla,
            site: site, operands: operands, before: failures[0].before,
            sourceInitializers: sourceInitializers, loweredInitializers: loweredInitializers,
            resolvedInitializers: resolvedInitializers,
            recordInputs: recordInputs)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let generated = directory.appendingPathComponent("generated-tla")
        try GeneratedTLCOracle.retainGeneratedInputs(check, in: generated)
        let nativeURL = directory.appendingPathComponent("native-initial-failure.json")
        let proofURL = generated.appendingPathComponent("\(proofModule).tla")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let nativeBytes = try encoder.encode(NativeInitialFailureOutput(
            successfulInitialStates: 0, failures: failures, site: site, kind: failureKind, operands: operands))
        try nativeBytes.write(to: nativeURL, options: .atomic)
        let proofBytes = Data(proof.utf8)
        try proofBytes.write(to: proofURL, options: .atomic)
        let report = InitialFailureEvidenceReport(
            schema: "swifttla.initial-failure-proof-v9", sourceSHA: sourceSHA,
            module: module.name, moduleSHA256: SHA256.hex(Data(module.tla.utf8)),
            checkModule: check.root.name,
            checkModuleSHA256: SHA256.hex(Data(check.root.tla.utf8)),
            checkConfigurationSHA256: SHA256.hex(Data(check.cfg.utf8)),
            proofSHA256: SHA256.hex(proofBytes), nativeSHA256: SHA256.hex(nativeBytes),
            sourceCompilationIdentity: compilation.identity.description,
            sourceInitializersSHA256: SHA256.hex(Data(sourceInitializers.utf8)),
            loweredInitializersSHA256: SHA256.hex(Data(loweredInitializers.utf8)),
            resolvedInitializersSHA256: SHA256.hex(Data(resolvedInitializers.utf8)),
            resolvedVariableTypesSHA256: SHA256.hex(Data(recordInputs.types.utf8)),
            layoutSHA256: SHA256.hex(Data(recordInputs.layout.utf8)),
            initializationOrderSHA256: SHA256.hex(Data(recordInputs.order.utf8)),
            prefixOrdersSHA256: SHA256.hex(Data(recordInputs.prefixes.utf8)),
            controlSeedsSHA256: SHA256.hex(Data(recordInputs.seeds.utf8)),
            graphCompared: false, result: "prepared", site: site,
            kind: failureKind, operands: operands)
        try encoder.encode(report).write(
            to: directory.appendingPathComponent("preparation.json"), options: .atomic)
        return report
    }

    // These retain existing checker plans; raw Swift parsing and builder meaning remain separate.
    private static func sourceInitializerPlans(_ source: TLASpec) throws -> String {
        guard source.sourceAlgorithms.count == 1 else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let states = source.sourceAlgorithms[0].model.components.compactMap { component -> AlgorithmStateModel? in
            guard case .shared(let state) = component else { return nil }
            return state
        }
        let reads = Set(states.map(\.root))
        let rows = try states.map { state in
            let expression: StateExpr
            switch state.initialization {
            case .value(let value): expression = .value(value)
            case .expression(let value): expression = value
            case .memberOf: throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            guard let nodes = StraightLineAssignmentCheck.orderedIntPlan(expression, reads: reads) else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            return "<<\(TLAValue.string(state.root)), \(try initializerPlan(nodes, root: state.root))>>"
        }
        guard !rows.isEmpty else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        return "<<\(rows.joined(separator: ", "))>>"
    }

    private static func initializerPlans(layout: CompiledLayout,
                                        initializations: [(variable: VariableID, initialization: CompiledVariableInitialization)],
                                        requireTypes: Bool) throws -> String {
        let variables = Dictionary(uniqueKeysWithValues: layout.variables.map { ($0.id, $0) })
        let names = variables.mapValues { $0.declaration.name }
        let rows = try initializations.compactMap { initialization -> String? in
            guard let variable = variables[initialization.variable] else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            guard variable.declaration.origin == .source else { return nil }
            guard case .value(let expression) = initialization.initialization,
                  let nodes = StraightLineAssignmentCheck.orderedIntPlan(expression, names: names,
                      requireTypes: requireTypes) else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            let root = variable.declaration.name
            return "<<\(TLAValue.string(root)), \(try initializerPlan(nodes, root: root))>>"
        }
        guard !rows.isEmpty else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        return "<<\(rows.joined(separator: ", "))>>"
    }

    private static func initializerPlan(_ nodes: [StraightLineAssignmentCheck.OrderedIntNode],
                                        root: String) throws -> String {
        var kinds: [String] = [], literals: [String] = [], reads: [String] = []
        var left: [String] = [], right: [String] = []
        for node in nodes {
            var literal = "0", read = TLAValue.string(root).description
            var lhs = 0, rhs = 0
            switch node {
            case .literal(let value): kinds.append("\"literal\""); literal = binaryLiteral(value)
            case .read(let name): kinds.append("\"read\""); read = TLAValue.string(name).description
            case .add(let first, let second): kinds.append("\"add\""); lhs = first; rhs = second
            default: throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            literals.append(literal); reads.append(read)
            left.append(String(lhs)); right.append(String(rhs))
        }
        func tuple(_ values: [String]) -> String { "<<\(values.joined(separator: ", "))>>" }
        return "[count |-> \(nodes.count), kinds |-> \(tuple(kinds)), literals |-> \(tuple(literals)), "
            + "reads |-> \(tuple(reads)), left |-> \(tuple(left)), right |-> \(tuple(right))]"
    }

    private static func initialRecordInputs(_ program: CompiledProgram) throws
        -> (layout: String, order: String, prefixes: String, seeds: String, types: String) {
        let variables = program.layout.variables
        let byID = Dictionary(uniqueKeysWithValues: variables.map { ($0.id, $0) })
        let layout = variables.map { variable in
            let origin: String = switch variable.declaration.origin {
            case .source: "source"
            case .compiler: "compiler"
            case .programCounter: "programCounter"
            case .procedureStack: "procedureStack"
            }
            return "[declaration |-> \(TLAValue.string(variable.declaration.name)), "
                + "name |-> \(TLAValue.string(variable.formalName)), ordinal |-> \(variable.id.ordinal), "
                + "origin |-> \(TLAValue.string(origin))]"
        }
        let ordered = try program.behavior.initializations.map { initialization in
            guard let variable = byID[initialization.variable] else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            return variable
        }
        func tuple(_ entries: [String]) -> String { "<<\(entries.joined(separator: ", "))>>" }
        let prefixes = ordered.indices.map { index in
            tuple(ordered.prefix(index).sorted {
                $0.formalName.utf8.lexicographicallyPrecedes($1.formalName.utf8)
            }.map { String($0.id.ordinal) })
        }
        let seeds = try program.behavior.initializations.compactMap { initialization -> String? in
            guard let variable = byID[initialization.variable] else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            guard variable.declaration.origin != .source else { return nil }
            guard variable.declaration.origin == .programCounter,
                  case .value(let expression) = initialization.initialization,
                  case .controlLocation(let location) = expression.operation,
                  expression.resultType == .controlLocation,
                  expression.children.isEmpty else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            let value = try CompiledValue.controlLocation(location).rendered(using: program.layout)
            return "[ordinal |-> \(variable.id.ordinal), value |-> \(value)]"
        }
        let types = try variables.map { variable in
            let expected: CompiledValueType = variable.declaration.origin == .source ? .int : .controlLocation
            guard let type = program.variableTypes[variable.id], type == expected else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            return "[ordinal |-> \(variable.id.ordinal), type |-> \(TLAValue.string(type.swiftType))]"
        }
        return (tuple(layout), tuple(ordered.map { String($0.id.ordinal) }), tuple(prefixes), tuple(seeds), tuple(types))
    }

    private static func proofSource(module: String, tla: String, site: Int,
                                    operands: [Int], before: [NativeInitialBindingOutput],
                                    sourceInitializers: String, loweredInitializers: String,
                                    resolvedInitializers: String,
                                    recordInputs: (layout: String, order: String, prefixes: String, seeds: String, types: String)) throws -> String {
        guard isIdentifier(module), tla.contains("\nInit ==") else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let definitions = tla.split(separator: "\n").compactMap { line -> String? in
            guard let equals = line.range(of: " =="), line.startIndex == line.firstIndex(where: { !$0.isWhitespace }) else {
                return nil
            }
            let left = line[..<equals.lowerBound]
            return String(left.prefix(while: { $0 != "(" && !$0.isWhitespace }))
        }
        let selected = definitions.filter { $0.hasPrefix("__SwiftTLASelectedInitialFailureRecord") }
        let aggregate = definitions.filter { $0.hasPrefix("__SwiftTLAAnyInitialEvaluationFailure") }
        let events = definitions.filter { $0.hasPrefix("__SwiftTLAInitialFailureEvents") }
        let failures = definitions.filter { $0.hasPrefix("__SwiftTLAInitialOverflowFailure") }
        guard selected.count == 1, aggregate.count == 1, events.count == 1, !failures.isEmpty,
              (selected + aggregate + events + failures).allSatisfy(isIdentifier) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let failureDefs = failures.joined(separator: ", ")
        let bindings = try before.map { binding in
            let value: String
            switch binding.value {
            case .int(let integer): value = binaryLiteral(integer)
            case .string: value = binding.value.description
            default: throw InitialFailureEvidenceError.unsupportedNativeOutcome
            }
            return "[name |-> \(TLAValue.string(binding.name)), value |-> \(value)]"
        }.joined(separator: ", ")
        return """
        ---- MODULE \(proofModule) ----
        EXTENDS \(module), TLAPS

        SourceInitializers == \(sourceInitializers)
        LoweredInitializers == \(loweredInitializers)
        ResolvedInitializers == \(resolvedInitializers)
        ResolvedVariableTypes == \(recordInputs.types)
        ActualLayout == \(recordInputs.layout)
        ActualInitializationOrder == \(recordInputs.order)
        ActualPrefixOrders == \(recordInputs.prefixes)
        ActualControlSeeds == \(recordInputs.seeds)

        THEOREM SourceInitializersMatchLoweredIR ==
          SourceInitializers = LoweredInitializers
          BY SMT DEF SourceInitializers, LoweredInitializers

        THEOREM LoweredInitializersMatchResolvedIR ==
          LoweredInitializers = ResolvedInitializers
          BY SMT DEF LoweredInitializers, ResolvedInitializers

        THEOREM ResolvedVariableTypesMatchActualLayout ==
          /\\ DOMAIN ResolvedVariableTypes = DOMAIN ActualLayout
          /\\ \\A row \\in DOMAIN ActualLayout :
                 /\\ ResolvedVariableTypes[row].ordinal = ActualLayout[row].ordinal
                 /\\ ResolvedVariableTypes[row].type =
                        IF ActualLayout[row].origin = "source" THEN "Int" ELSE "_ControlLocation"
          BY SMT DEF ResolvedVariableTypes, ActualLayout

        ProofIntMin == \(binaryLiteral(Int.min))
        ProofIntMax == \(binaryLiteral(Int.max))
        ProofIntKeys == {SourceInitializers[row][1] : row \\in DOMAIN SourceInitializers}
        ProofBoundKeys(row) == {SourceInitializers[earlier][1] : earlier \\in 1..(row - 1)}
        THEOREM ProofIntegerBounds ==
          /\\ ProofIntMin \\in Int /\\ ProofIntMax \\in Int
          /\\ ProofIntMin <= -2000000000 /\\ 2000000000 <= ProofIntMax
          BY SMT DEF ProofIntMin, ProofIntMax

        ProofAllKeys == {ActualLayout[row].declaration : row \\in DOMAIN ActualLayout}
        ProofLayoutIndex(key) == CHOOSE row \\in DOMAIN ActualLayout : ActualLayout[row].declaration = key
        ProofOrdinalKey(ordinal) == ActualLayout[CHOOSE row \\in DOMAIN ActualLayout : ActualLayout[row].ordinal = ordinal].declaration
        ProofNames == [key \\in ProofAllKeys |-> ActualLayout[ProofLayoutIndex(key)].name]
        ProofOrdinals == [key \\in ProofAllKeys |-> ActualLayout[ProofLayoutIndex(key)].ordinal]
        ProofIntSlots == {ActualLayout[row].declaration :
          row \\in {entry \\in DOMAIN ActualLayout : ActualLayout[entry].origin = "source"}}
        ProofCount == Len(ActualInitializationOrder)
        ProofOrder == [position \\in 1..ProofCount |-> ProofOrdinalKey(ActualInitializationOrder[position])]
        ProofPrefixKeys(position) == {ProofOrder[earlier] : earlier \\in 1..(position - 1)}
        ProofPrefixIntNames(position) == ProofPrefixKeys(position) \\cap ProofIntSlots
        ProofPrefixOrder(position) == [index \\in DOMAIN ActualPrefixOrders[position] |->
          ProofOrdinalKey(ActualPrefixOrders[position][index])]
        ProofValues == Int \\cup STRING
        ProofFailureValues == {"integerOverflow"} \\X {"addition"} \\X
          ((ProofIntMin..ProofIntMax) \\X (ProofIntMin..ProofIntMax))
        ProofNoFailure == <<"none", 0, 0>>
        ProofNoInitialSite == -1

        THEOREM ProofInitialSentinels ==
          /\\ ProofNoFailure \\notin ProofFailureValues
          /\\ ProofNoInitialSite \\notin ProofAllKeys
          BY SMT DEF ProofNoFailure, ProofFailureValues, ProofNoInitialSite, ProofAllKeys, ActualLayout

        ProofInitialization == INSTANCE OrderedIntInitializationComposition WITH
          Keys <- ProofAllKeys, Values <- ProofValues, FailureValues <- ProofFailureValues,
          NoFailure <- ProofNoFailure, NoInitialSite <- ProofNoInitialSite,
          IntKeys <- ProofIntSlots, SwiftIntMin <- ProofIntMin, SwiftIntMax <- ProofIntMax

        THEOREM ActualLayoutSuppliesInitializationDecoderInputs ==
          /\\ ProofInitialization!RenderedInitialRecordLayout(ProofNames, ProofOrdinals)
          /\\ ProofIntKeys = ProofIntSlots
          /\\ \\A row \\in DOMAIN ActualLayout : ActualLayout[row].origin = "source"
                 => ResolvedVariableTypes[row].type = "Int"
          /\\ ProofInitialization!IntInitializationDomains
          /\\ ProofInitialization!InitializationOrder(ProofCount, ProofOrder)
          /\\ \\A row \\in DOMAIN ActualLayout :
                 /\\ ProofNames[ActualLayout[row].declaration] = ActualLayout[row].name
                 /\\ ProofOrdinals[ActualLayout[row].declaration] = ActualLayout[row].ordinal
                 /\\ \\A other \\in DOMAIN ActualLayout :
                        ActualLayout[row].ordinal = ActualLayout[other].ordinal => row = other
          BY ProofIntegerBounds, ProofInitialSentinels, ResolvedVariableTypesMatchActualLayout, SMT
            DEF ActualLayout, ActualInitializationOrder, ProofCount, ProofOrder, ProofOrdinalKey,
              ProofAllKeys, ProofLayoutIndex, ProofNames, ProofOrdinals, ProofIntSlots, ProofIntKeys,
              SourceInitializers, ProofValues, ProofFailureValues,
              ProofInitialization!RenderedInitialRecordLayout, ProofInitialization!IntInitializationDomains,
              ProofInitialization!InitializationOrder, ProofInitialization!PrefixKeys,
              ProofInitialization!Expressions!ArithmeticFailures

        SourcePlanHistory(plan, state, history) ==
          ProofInitialization!Expressions!SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
            plan.reads, plan.left, plan.right, state, history)
        ResolvedPlanHistory(plan, state, history) ==
          ProofInitialization!Expressions!GeneratedExpressionHistory(plan.count, plan.kinds, plan.literals,
            plan.reads, plan.left, plan.right, state, history)

        THEOREM InitializerPlansInvokeCheckedExpressionParent ==
          \\A row \\in DOMAIN SourceInitializers :
            \\A state \\in [ProofBoundKeys(row) -> ProofIntMin..ProofIntMax] :
              \\E source, generated :
                /\\ SourcePlanHistory(SourceInitializers[row][2], state, source)
                /\\ ResolvedPlanHistory(ResolvedInitializers[row][2], state, generated)
                /\\ \\A index \\in 0..SourceInitializers[row][2].count :
                       /\\ ProofInitialization!Expressions!OutcomeAgrees(source, generated, index)
                       /\\ source[index] \\in ProofInitialization!Expressions!ExpressionOutcomes
                       /\\ generated[index] \\in ProofInitialization!Expressions!ExpressionOutcomes
          PROOF
          <1>. SUFFICES ASSUME NEW row \\in DOMAIN SourceInitializers,
                              NEW state \\in [ProofBoundKeys(row) -> ProofIntMin..ProofIntMax]
                       PROVE \\E source, generated :
                         /\\ SourcePlanHistory(SourceInitializers[row][2], state, source)
                         /\\ ResolvedPlanHistory(ResolvedInitializers[row][2], state, generated)
                         /\\ \\A index \\in 0..SourceInitializers[row][2].count :
                                /\\ ProofInitialization!Expressions!OutcomeAgrees(source, generated, index)
                                /\\ source[index] \\in ProofInitialization!Expressions!ExpressionOutcomes
                                /\\ generated[index] \\in ProofInitialization!Expressions!ExpressionOutcomes
            BY SMT
          <1>. DEFINE plan == SourceInitializers[row][2]
                      bound == ProofBoundKeys(row)
                      completed == ProofInitialization!Expressions!CompleteIntBindings(bound, state)
          <1>0. bound \\subseteq ProofIntSlots
            BY ActualLayoutSuppliesInitializationDecoderInputs, SMT DEF bound, ProofBoundKeys, SourceInitializers, ProofIntKeys
          <1>1. completed \\in [ProofIntSlots -> ProofIntMin..ProofIntMax]
            BY <1>0, ProofInitialization!Expressions!CompletingPartialBindingsRetainsEveryBoundValue, SMT
              DEF bound, completed
          <1>2. ProofInitialization!Expressions!ExpressionPlan(plan.count, plan.kinds, plan.literals,
                  plan.reads, plan.left, plan.right, completed)
            BY <1>1, ProofIntegerBounds, SMT DEF plan, SourceInitializers, ProofIntKeys, ProofIntSlots, ActualLayout,
              ProofIntMin, ProofIntMax, ProofInitialization!Expressions!ExpressionPlan
          <1>3. ProofInitialization!Expressions!ExpressionReadKeys(plan.count, plan.kinds, plan.reads) \\subseteq bound
            BY SMT DEF plan, bound, ProofBoundKeys, SourceInitializers, ProofInitialization!Expressions!ExpressionReadKeys
          <1>4. ProofInitialization!Expressions!PartialExpressionPlan(plan.count, plan.kinds, plan.literals,
                  plan.reads, plan.left, plan.right, bound, state)
            BY <1>0, <1>2, <1>3, SMT DEF bound, completed, ProofInitialization!Expressions!PartialExpressionPlan
          <1>5. \\E source, generated :
                  /\\ SourcePlanHistory(plan, state, source)
                  /\\ ResolvedPlanHistory(plan, state, generated)
                  /\\ \\A index \\in 0..plan.count :
                         /\\ ProofInitialization!Expressions!OutcomeAgrees(source, generated, index)
                         /\\ source[index] \\in ProofInitialization!Expressions!ExpressionOutcomes
                         /\\ generated[index] \\in ProofInitialization!Expressions!ExpressionOutcomes
            BY <1>4, ProofInitialization!Expressions!PartialOrderedIntExpressionsPreserveValueAndFailure, SMT
              DEF SourcePlanHistory, ResolvedPlanHistory
          <1>. QED BY <1>5, SourceInitializersMatchLoweredIR, LoweredInitializersMatchResolvedIR, SMT DEF plan

        THEOREM ActualPrefixRecordsInvokeInitializationDecoder ==
          /\\ \\A position \\in 1..ProofCount : \\A prior \\in [ProofPrefixKeys(position) -> ProofValues] :
                /\\ ProofInitialization!RenderedInitialPrefixOrder(position - 1, ProofPrefixOrder(position), prior)
                /\\ ProofInitialization!DecodedRenderedPrefixEntries(
                       ProofInitialization!RenderedInitialPrefixEntries(
                         position - 1, ProofPrefixOrder(position), ProofNames, prior), ProofNames) = prior
                /\\ \\A target \\in ProofAllKeys :
                       ProofInitialization!DecodedRenderedInitializerSite(ProofOrdinals[target], ProofOrdinals) = target
          /\\ \\A row \\in DOMAIN SourceInitializers : \\E position \\in 1..ProofCount :
                /\\ ProofOrder[position] = SourceInitializers[row][1]
                /\\ ProofPrefixIntNames(position) = ProofBoundKeys(row)
                /\\ \\A state \\in [ProofPrefixIntNames(position) -> ProofIntMin..ProofIntMax] :
                       \\E source, generated :
                         /\\ SourcePlanHistory(SourceInitializers[row][2], state, source)
                         /\\ ResolvedPlanHistory(ResolvedInitializers[row][2], state, generated)
                         /\\ \\A index \\in 0..SourceInitializers[row][2].count :
                                ProofInitialization!Expressions!OutcomeAgrees(source, generated, index)
          PROOF
          <1>1. ProofInitialization!RenderedInitialRecordLayout(ProofNames, ProofOrdinals)
            BY ActualLayoutSuppliesInitializationDecoderInputs, SMT
          <1>2. \\A position \\in 1..ProofCount :
                  /\\ ProofPrefixKeys(position) \\subseteq ProofAllKeys /\\ position - 1 \\in Nat
                  /\\ ProofPrefixOrder(position) \\in [1..(position - 1) -> ProofPrefixKeys(position)]
                  /\\ {ProofPrefixOrder(position)[index] : index \\in 1..(position - 1)} = ProofPrefixKeys(position)
                  /\\ \\A prefixLeftIndex, prefixRightIndex \\in 1..(position - 1) :
                         ProofPrefixOrder(position)[prefixLeftIndex] = ProofPrefixOrder(position)[prefixRightIndex]
                           => prefixLeftIndex = prefixRightIndex
            BY SMT DEF ActualInitializationOrder, ActualPrefixOrders, ActualLayout, ProofCount, ProofOrder,
              ProofOrdinalKey, ProofPrefixOrder, ProofPrefixKeys, ProofAllKeys
          <1>3. \\A position \\in 1..ProofCount : \\A prior \\in [ProofPrefixKeys(position) -> ProofValues] :
                  /\\ prior \\in ProofInitialization!PartialBindings
                  /\\ ProofInitialization!RenderedInitialPrefixOrder(position - 1, ProofPrefixOrder(position), prior)
            BY <1>2, SMT DEF ProofInitialization!PartialBindings, ProofInitialization!RenderedInitialPrefixOrder
          <1>4. \\A position \\in 1..ProofCount : \\A prior \\in [ProofPrefixKeys(position) -> ProofValues] :
                  /\\ ProofInitialization!DecodedRenderedPrefixEntries(
                         ProofInitialization!RenderedInitialPrefixEntries(
                           position - 1, ProofPrefixOrder(position), ProofNames, prior), ProofNames) = prior
                  /\\ \\A target \\in ProofAllKeys :
                         ProofInitialization!DecodedRenderedInitializerSite(ProofOrdinals[target], ProofOrdinals) = target
            BY <1>1, <1>3, ProofInitialization!RenderedInitialPrefixAndSiteDecodingRetainsEveryIdentity, SMT
          <1>5. \\A row \\in DOMAIN SourceInitializers : \\E position \\in 1..ProofCount :
                  /\\ ProofOrder[position] = SourceInitializers[row][1]
                  /\\ ProofPrefixIntNames(position) = ProofBoundKeys(row)
            BY SMT DEF ActualLayout, ActualInitializationOrder, ProofCount, ProofOrder, ProofOrdinalKey,
              SourceInitializers, ProofPrefixIntNames, ProofPrefixKeys, ProofIntSlots, ProofBoundKeys
          <1>. QED BY <1>3, <1>4, <1>5, InitializerPlansInvokeCheckedExpressionParent, SMT

        ProofIntPositions == {position \\in 1..ProofCount : ProofOrder[position] \\in ProofIntSlots}
        ProofSourceRow(position) == CHOOSE row \\in DOMAIN SourceInitializers : SourceInitializers[row][1] = ProofOrder[position]
        ProofPlans == [position \\in ProofIntPositions |-> SourceInitializers[ProofSourceRow(position)][2]]
        ProofResolvedPlans == [position \\in ProofIntPositions |-> ResolvedInitializers[ProofSourceRow(position)][2]]
        ProofControlSeed(position) == (CHOOSE entry \\in {ActualControlSeeds[index] : index \\in DOMAIN ActualControlSeeds} :
          entry.ordinal = ActualInitializationOrder[position]).value
        \\* Totalize the proof input outside reached prefixes; the parent below proves no reached read uses a default.
        ProofReadState(position, prior) == [key \\in ProofPrefixIntNames(position) |->
          IF key \\in DOMAIN prior /\\ prior[key] \\in ProofIntMin..ProofIntMax THEN prior[key] ELSE 0]
        ProofSourceExpressions == [position \\in ProofIntPositions |-> [prior \\in ProofInitialization!PartialBindings |->
          CHOOSE history : SourcePlanHistory(ProofPlans[position], ProofReadState(position, prior), history)]]
        ProofGeneratedExpressions == [position \\in ProofIntPositions |-> [prior \\in ProofInitialization!PartialBindings |->
          CHOOSE history : ResolvedPlanHistory(ProofResolvedPlans[position], ProofReadState(position, prior), history)]]
        ProofEvaluate(generated) == [position \\in 1..ProofCount |-> [prior \\in ProofInitialization!PartialBindings |->
          IF position \\in ProofIntPositions
          THEN IF generated
               THEN ProofInitialization!GeneratedIntInitializerOutcome(ProofGeneratedExpressions[position][prior][ProofPlans[position].count])
               ELSE ProofInitialization!SourceIntInitializerOutcome(ProofSourceExpressions[position][prior][ProofPlans[position].count])
          ELSE IF generated THEN ProofInitialization!GeneratedFixed(ProofControlSeed(position))
               ELSE ProofInitialization!SourceFixed(ProofControlSeed(position))]]

        THEOREM ActualInitializerExpressionsSupplyTheirParents ==
          \\A position \\in ProofIntPositions : \\A prior \\in ProofInitialization!PartialBindings :
            /\\ ProofInitialization!Expressions!PartialExpressionPlan(ProofPlans[position].count,
                   ProofPlans[position].kinds, ProofPlans[position].literals, ProofPlans[position].reads,
                   ProofPlans[position].left, ProofPlans[position].right,
                   ProofPrefixIntNames(position), ProofReadState(position, prior))
            /\\ SourcePlanHistory(ProofPlans[position], ProofReadState(position, prior), ProofSourceExpressions[position][prior])
            /\\ ResolvedPlanHistory(ProofPlans[position], ProofReadState(position, prior), ProofGeneratedExpressions[position][prior])
            /\\ \\A index \\in 0..ProofPlans[position].count :
                   /\\ ProofInitialization!Expressions!OutcomeAgrees(ProofSourceExpressions[position][prior], ProofGeneratedExpressions[position][prior], index)
                   /\\ ProofSourceExpressions[position][prior][index] \\in ProofInitialization!Expressions!ExpressionOutcomes
                   /\\ ProofGeneratedExpressions[position][prior][index] \\in ProofInitialization!Expressions!ExpressionOutcomes
          PROOF
          <1>. SUFFICES ASSUME NEW position \\in ProofIntPositions, NEW prior \\in ProofInitialization!PartialBindings
                       PROVE /\\ ProofInitialization!Expressions!PartialExpressionPlan(ProofPlans[position].count,
                                    ProofPlans[position].kinds, ProofPlans[position].literals, ProofPlans[position].reads,
                                    ProofPlans[position].left, ProofPlans[position].right,
                                    ProofPrefixIntNames(position), ProofReadState(position, prior))
                             /\\ SourcePlanHistory(ProofPlans[position], ProofReadState(position, prior), ProofSourceExpressions[position][prior])
                             /\\ ResolvedPlanHistory(ProofPlans[position], ProofReadState(position, prior), ProofGeneratedExpressions[position][prior])
                             /\\ \\A index \\in 0..ProofPlans[position].count :
                                    /\\ ProofInitialization!Expressions!OutcomeAgrees(ProofSourceExpressions[position][prior], ProofGeneratedExpressions[position][prior], index)
                                    /\\ ProofSourceExpressions[position][prior][index] \\in ProofInitialization!Expressions!ExpressionOutcomes
                                    /\\ ProofGeneratedExpressions[position][prior][index] \\in ProofInitialization!Expressions!ExpressionOutcomes
            BY SMT
          <1>0. /\\ ProofSourceRow(position) \\in DOMAIN SourceInitializers
                /\\ ProofPlans[position] = SourceInitializers[ProofSourceRow(position)][2]
                /\\ ProofPrefixIntNames(position) = ProofBoundKeys(ProofSourceRow(position))
            BY SMT DEF ProofSourceRow, ProofPlans, ProofIntPositions, ProofOrder, ProofCount,
              ProofOrdinalKey, ActualInitializationOrder, ActualLayout, SourceInitializers,
              ProofPrefixIntNames, ProofPrefixKeys, ProofIntSlots, ProofBoundKeys
          <1>1. ProofReadState(position, prior) \\in [ProofBoundKeys(ProofSourceRow(position)) -> ProofIntMin..ProofIntMax]
            BY <1>0, ProofIntegerBounds, SMT DEF ProofReadState
          <1>2. \\E source, generated :
                  /\\ SourcePlanHistory(ProofPlans[position], ProofReadState(position, prior), source)
                  /\\ ResolvedPlanHistory(ProofResolvedPlans[position], ProofReadState(position, prior), generated)
            BY <1>0, <1>1, InitializerPlansInvokeCheckedExpressionParent, SMT DEF ProofResolvedPlans
          <1>3. /\\ SourcePlanHistory(ProofPlans[position], ProofReadState(position, prior), ProofSourceExpressions[position][prior])
                /\\ ResolvedPlanHistory(ProofPlans[position], ProofReadState(position, prior), ProofGeneratedExpressions[position][prior])
            BY <1>2, SourceInitializersMatchLoweredIR, LoweredInitializersMatchResolvedIR, SMT
              DEF ProofSourceExpressions, ProofGeneratedExpressions, ProofResolvedPlans, ProofPlans
          <1>4. ProofInitialization!Expressions!PartialExpressionPlan(ProofPlans[position].count,
              ProofPlans[position].kinds, ProofPlans[position].literals, ProofPlans[position].reads,
              ProofPlans[position].left, ProofPlans[position].right,
              ProofPrefixIntNames(position), ProofReadState(position, prior))
            BY <1>0, <1>1, ActualLayoutSuppliesInitializationDecoderInputs, ProofIntegerBounds, SMT
              DEF ProofPlans, ProofSourceRow, SourceInitializers, ProofBoundKeys, ProofIntKeys,
                ProofInitialization!Expressions!PartialExpressionPlan, ProofInitialization!Expressions!ExpressionPlan,
                ProofInitialization!Expressions!ExpressionReadKeys, ProofInitialization!Expressions!CompleteIntBindings
          <1>5. \\A index \\in 0..ProofPlans[position].count :
                  /\\ ProofInitialization!Expressions!OutcomeAgrees(ProofSourceExpressions[position][prior], ProofGeneratedExpressions[position][prior], index)
                  /\\ ProofSourceExpressions[position][prior][index] \\in ProofInitialization!Expressions!ExpressionOutcomes
                  /\\ ProofGeneratedExpressions[position][prior][index] \\in ProofInitialization!Expressions!ExpressionOutcomes
            BY <1>3, <1>4, ProofInitialization!Expressions!AnyPartialOrderedIntHistoriesPreserveValueAndFailure, SMT
              DEF SourcePlanHistory, ResolvedPlanHistory
          <1>. QED BY <1>3, <1>4, <1>5, SMT

        THEOREM ActualInitializerEvaluatorsAreTypedAndAgree ==
          /\\ ProofInitialization!InitializerEvaluators(ProofCount, ProofEvaluate(FALSE))
          /\\ ProofInitialization!InitializerEvaluators(ProofCount, ProofEvaluate(TRUE))
          /\\ ProofEvaluate(FALSE) = ProofEvaluate(TRUE)
          /\\ \\A position \\in ProofIntPositions : \\A prior \\in ProofInitialization!PartialBindings :
                 ProofEvaluate(FALSE)[position][prior].candidates \\subseteq ProofIntMin..ProofIntMax
          /\\ \\A position \\in 1..ProofCount : \\A prior \\in ProofInitialization!PartialBindings :
                 ProofEvaluate(FALSE)[position][prior].firstFailure = ProofNoFailure
                   => \\E value \\in ProofValues : ProofEvaluate(FALSE)[position][prior].candidates = {value}
          PROOF
          <1>0. /\\ ProofCount \\in Nat /\\ ProofIntPositions \\subseteq 1..ProofCount
                /\\ \\A position \\in (1..ProofCount) \\ ProofIntPositions : ProofControlSeed(position) \\in ProofValues
                /\\ \\A position \\in ProofIntPositions : ProofPlans[position].count \\in Nat
            BY SMT DEF ProofCount, ActualInitializationOrder, ProofIntPositions, ProofControlSeed,
              ActualControlSeeds, ActualLayout, ProofOrdinalKey, ProofOrder, ProofIntSlots, ProofValues,
              ProofPlans, ProofSourceRow, SourceInitializers
          <1>1. \\A position \\in ProofIntPositions : \\A prior \\in ProofInitialization!PartialBindings :
                  /\\ ProofInitialization!SourceIntInitializerOutcome(ProofSourceExpressions[position][prior][ProofPlans[position].count])
                       = ProofInitialization!GeneratedIntInitializerOutcome(ProofGeneratedExpressions[position][prior][ProofPlans[position].count])
                  /\\ ProofInitialization!SourceIntInitializerOutcome(ProofSourceExpressions[position][prior][ProofPlans[position].count])
                       \\in ProofInitialization!InitializerOutcomes
            BY <1>0, ActualInitializerExpressionsSupplyTheirParents, ActualLayoutSuppliesInitializationDecoderInputs,
              ProofInitialization!IntExpressionOutcomesSupplyInitializerOutcomes, SMT
              DEF ProofInitialization!Expressions!OutcomeAgrees
          <1>2. \\A position \\in (1..ProofCount) \\ ProofIntPositions :
                  /\\ ProofInitialization!SourceFixed(ProofControlSeed(position)) = ProofInitialization!GeneratedFixed(ProofControlSeed(position))
                  /\\ ProofInitialization!SourceFixed(ProofControlSeed(position)) \\in ProofInitialization!InitializerOutcomes
            BY <1>0, ProofInitialization!FixedInitializerRetainsItsOnlyCandidate, SMT
          <1>3. \\A position \\in ProofIntPositions : \\A prior \\in ProofInitialization!PartialBindings :
                  /\\ ProofEvaluate(FALSE)[position][prior].candidates \\subseteq ProofIntMin..ProofIntMax
                  /\\ (ProofEvaluate(FALSE)[position][prior].firstFailure = ProofNoFailure
                       => \\E value \\in ProofValues : ProofEvaluate(FALSE)[position][prior].candidates = {value})
            BY <1>0, <1>1, ActualInitializerExpressionsSupplyTheirParents, ProofInitialSentinels,
              ActualLayoutSuppliesInitializationDecoderInputs, SMT
              DEF ProofEvaluate, ProofInitialization!SourceIntInitializerOutcome, ProofInitialization!SourceFixed,
                ProofInitialization!SourceFailed, ProofInitialization!Expressions!ExpressionOutcomes, ProofValues,
                ProofInitialization!IntInitializationDomains
          <1>. QED BY <1>0, <1>1, <1>2, <1>3, SMT
            DEF ProofEvaluate, ProofInitialization!InitializerEvaluators, ProofInitialization!SourceFixed

        THEOREM ActualPlansInvokeCompleteInitializationAndObservationParents ==
          \\E source, generated, observations :
            /\\ ProofInitialization!InitializationHistory(FALSE, ProofCount, ProofOrder, ProofEvaluate(FALSE), source)
            /\\ ProofInitialization!InitializationHistory(TRUE, ProofCount, ProofOrder, ProofEvaluate(TRUE), generated)
            /\\ \\A index \\in 0..ProofCount : source[index] = generated[index]
            /\\ ProofInitialization!SingleBranchInitialObservationHistory(ProofCount, ProofOrder, ProofEvaluate(FALSE), observations)
            /\\ ProofInitialization!SingleBranchInitialObservationHistory(ProofCount, ProofOrder, ProofEvaluate(TRUE), observations)
            /\\ \\A index \\in 0..ProofCount : ProofInitialization!InitialSetProjection(observations[index]) = source[index]
            /\\ ProofInitialization!InitialObservationIsTyped(observations[ProofCount])
            /\\ observations[ProofCount].stateCount + observations[ProofCount].failureCount = 1
            /\\ observations[ProofCount].stateCount <= 1 /\\ observations[ProofCount].failureCount <= 1
            /\\ source[ProofCount].failures = ProofInitialization!SourceFailureConstraintPrefix(ProofOrder, ProofCount, ProofEvaluate(FALSE))
            /\\ \\A position \\in ProofIntPositions : \\A prior \\in source[position - 1].states :
                   ProofReadState(position, prior) = ProofInitialization!PartialIntProjection(prior)
          PROOF
          <1>0. /\\ ProofInitialization!InitializationOrder(ProofCount, ProofOrder)
                /\\ ProofInitialization!IntInitializationDomains
            BY ActualLayoutSuppliesInitializationDecoderInputs, SMT
          <1>1. PICK source : ProofInitialization!InitializationHistory(FALSE, ProofCount, ProofOrder, ProofEvaluate(FALSE), source)
            BY <1>0, ActualInitializerEvaluatorsAreTypedAndAgree, ProofInitialization!InitializationHistoriesExist, SMT
          <1>2. PICK generated : ProofInitialization!InitializationHistory(TRUE, ProofCount, ProofOrder, ProofEvaluate(TRUE), generated)
            BY <1>0, ActualInitializerEvaluatorsAreTypedAndAgree, ProofInitialization!InitializationHistoriesExist, SMT
          <1>3. \\A length \\in 0..ProofCount : \\A prior \\in source[length].states :
                  ProofInitialization!PartialIntProjection(prior)
                    \\in [(DOMAIN prior) \\cap ProofIntSlots -> ProofIntMin..ProofIntMax]
            <2>. SUFFICES ASSUME NEW length \\in 0..ProofCount, NEW prior \\in source[length].states
                         PROVE ProofInitialization!PartialIntProjection(prior)
                           \\in [(DOMAIN prior) \\cap ProofIntSlots -> ProofIntMin..ProofIntMax]
              BY SMT
            <2>0. /\\ DOMAIN prior = ProofInitialization!PrefixKeys(ProofOrder, length)
                  /\\ prior \\in [DOMAIN prior -> ProofValues]
                  /\\ prior \\in ProofInitialization!SourceConstraintPrefix(ProofOrder, length, ProofEvaluate(FALSE))
              BY <1>0, <1>1, ActualInitializerEvaluatorsAreTypedAndAgree,
                ProofInitialization!SourceHistoriesBindEveryPrefixKey,
                ProofInitialization!SourceHistoriesMatchEveryInitializerPrefix, SMT
                DEF ProofInitialization!InitializationOrder
            <2>1. \\A key \\in (DOMAIN prior) \\cap ProofIntSlots : prior[key] \\in ProofIntMin..ProofIntMax
              <3>. SUFFICES ASSUME NEW key \\in (DOMAIN prior) \\cap ProofIntSlots
                           PROVE prior[key] \\in ProofIntMin..ProofIntMax
                BY SMT
              <3>1. PICK position \\in 1..length : ProofOrder[position] = key
                BY <2>0, SMT DEF ProofInitialization!PrefixKeys
              <3>2. /\\ position \\in ProofIntPositions
                    /\\ ProofInitialization!PrefixKeys(ProofOrder, position - 1) \\subseteq DOMAIN prior
                BY <1>0, <2>0, <3>1, ProofInitialization!PrefixKeySetsAreContained, SMT
                  DEF ProofIntPositions, ProofInitialization!InitializationOrder
              <3>3. ProofInitialization!SourceRestriction(prior, ProofInitialization!PrefixKeys(ProofOrder, position - 1))
                  \\in ProofInitialization!PartialBindings
                BY <2>0, <3>2, ProofInitialization!SourceRestrictionIsTyped, SMT
                  DEF ProofInitialization!PartialBindings, ProofInitialization!InitializationOrder
              <3>4. prior[key] \\in ProofEvaluate(FALSE)[position][ProofInitialization!SourceRestriction(
                  prior, ProofInitialization!PrefixKeys(ProofOrder, position - 1))].candidates
                BY <2>0, <3>1, SMT DEF ProofInitialization!SourceConstraintPrefix
              <3>. QED BY <3>2, <3>3, <3>4, ActualInitializerEvaluatorsAreTypedAndAgree, SMT
            <2>. QED BY <2>1, SMT DEF ProofInitialization!PartialIntProjection
          <1>4. \\A position \\in ProofIntPositions : \\A prior \\in source[position - 1].states :
                  /\\ ProofReadState(position, prior) = ProofInitialization!PartialIntProjection(prior)
                  /\\ ProofPrefixIntNames(position) = (DOMAIN prior) \\cap ProofIntSlots
            BY <1>0, <1>1, <1>3, ActualInitializerEvaluatorsAreTypedAndAgree,
              ProofInitialization!SourceHistoriesBindEveryPrefixKey, SMT
              DEF ProofReadState, ProofPrefixIntNames, ProofPrefixKeys, ProofIntPositions,
                ProofInitialization!PartialIntProjection, ProofInitialization!PrefixKeys, ProofInitialization!InitializationOrder
          <1>5. \\A position \\in 1..ProofCount : \\A prior \\in source[position - 1].states :
                  IF position \\in ProofIntPositions
                  THEN /\\ ProofOrder[position] \\in ProofIntSlots
                       /\\ ProofInitialization!IntInitializerChildren(ProofPlans[position], prior,
                              ProofSourceExpressions[position][prior], ProofGeneratedExpressions[position][prior])
                       /\\ ProofEvaluate(FALSE)[position][prior] = ProofInitialization!SourceIntInitializerOutcome(
                              ProofSourceExpressions[position][prior][ProofPlans[position].count])
                       /\\ ProofEvaluate(TRUE)[position][prior] = ProofInitialization!GeneratedIntInitializerOutcome(
                              ProofGeneratedExpressions[position][prior][ProofPlans[position].count])
                  ELSE ProofEvaluate(FALSE)[position][prior] = ProofEvaluate(TRUE)[position][prior]
            BY <1>0, <1>1, <1>4, ActualInitializerExpressionsSupplyTheirParents, ActualInitializerEvaluatorsAreTypedAndAgree, SMT
              DEF ProofIntPositions, ProofEvaluate, ProofInitialization!IntInitializerChildren,
                SourcePlanHistory, ResolvedPlanHistory, ProofInitialization!InitializationHistory,
                ProofInitialization!InitializationResults
          <1>6. \\A index \\in 0..ProofCount : source[index] = generated[index]
            BY <1>0, <1>1, <1>2, <1>5, ActualInitializerEvaluatorsAreTypedAndAgree,
              ProofInitialization!OrderedIntInitializerChildrenComposeAllReachableStatesAndFailures, SMT
          <1>7. PICK observations :
                  /\\ ProofInitialization!SingleBranchInitialObservationHistory(ProofCount, ProofOrder, ProofEvaluate(FALSE), observations)
                  /\\ \\A index \\in 0..ProofCount : ProofInitialization!InitialSetProjection(observations[index]) = source[index]
            BY <1>0, <1>1, ActualInitializerEvaluatorsAreTypedAndAgree,
              ProofInitialization!DeterministicReachableInitializersConstructTheirOrderedObservations, SMT
              DEF ProofInitialization!InitializationHistory, ProofInitialization!InitializationResults
          <1>8. /\\ ProofInitialization!SingleBranchInitialObservationHistory(ProofCount, ProofOrder, ProofEvaluate(TRUE), observations)
                /\\ ProofInitialization!InitialObservationIsTyped(observations[ProofCount])
                /\\ observations[ProofCount].stateCount + observations[ProofCount].failureCount = 1
                /\\ observations[ProofCount].stateCount <= 1 /\\ observations[ProofCount].failureCount <= 1
            BY <1>0, <1>7, ActualInitializerEvaluatorsAreTypedAndAgree,
              ProofInitialization!SingleBranchInitializationDerivesItsObservationBounds, SMT
              DEF ProofInitialization!InitializationOrder
          <1>9. source[ProofCount].failures
                  = ProofInitialization!SourceFailureConstraintPrefix(ProofOrder, ProofCount, ProofEvaluate(FALSE))
            BY <1>0, <1>1, ActualInitializerEvaluatorsAreTypedAndAgree,
              ProofInitialization!SourceHistoriesMatchEveryInitialFailurePrefix, SMT
              DEF ProofInitialization!InitializationOrder
          <1>. QED BY <1>1, <1>2, <1>4, <1>6, <1>7, <1>8, <1>9, SMT

        ExpectedOperand0 == \(binaryLiteral(operands[0]))
        ExpectedOperand1 == \(binaryLiteral(operands[1]))
        ExpectedBefore == <<\(bindings)>>

        ExpectedFailure ==
          [site |-> \(site), kind |-> "\(failureKind)",
           operands |-> <<ExpectedOperand0, ExpectedOperand1>>, before |-> ExpectedBefore]
        ExpectedFailures == {ExpectedFailure}

        THEOREM SelectedFailurePayload ==
          \(selected[0]) = ExpectedFailure
          BY SMT DEF ExpectedFailure, ExpectedOperand0, ExpectedOperand1, ExpectedBefore, \(selected[0]), \(failureDefs)

        THEOREM CompleteFailureEvents ==
          \(events[0]) = ExpectedFailures
          BY SMT DEF ExpectedFailures, ExpectedFailure, ExpectedOperand0, ExpectedOperand1, ExpectedBefore, \(events[0])

        THEOREM InitialFailurePrecedesGraph ==
          /\\ \(aggregate[0])
          /\\ ~Init
          BY SMT DEF \(aggregate[0]), Init, \(failureDefs)
        ProofObservedBefore == ProofInitialization!DecodedRenderedPrefixEntries(ExpectedBefore, ProofNames)
        ProofObservedPrior(position) == ProofInitialization!SourceRestriction(ProofObservedBefore, ProofPrefixKeys(position))
        ProofObservedFailures == ProofInitialization!DecodedNamedRenderedAdditionEvents(ExpectedFailures, ProofNames, ProofOrdinals)
        ProofObservedResult == [states |-> {}, failures |-> ProofObservedFailures]
        ProofObservedHistory == [length \\in 0..ProofCount |->
          IF length = ProofCount THEN ProofObservedResult
          ELSE [states |-> {ProofObservedPrior(length + 1)}, failures |-> {}]]

        THEOREM ActualNativePrefixSuppliesTheSourceInitializerOutcomes ==
          /\\ \\A position \\in 1..ProofCount :
                 /\\ ProofObservedPrior(position) \\in ProofInitialization!PartialBindings
                 /\\ DOMAIN ProofObservedPrior(position) = ProofPrefixKeys(position)
                 /\\ ProofEvaluate(FALSE)[position][ProofObservedPrior(position)] =
                      IF position = ProofCount
                      THEN ProofInitialization!SourceFailed(<<"integerOverflow", "addition", <<ExpectedOperand0, ExpectedOperand1>>>>)
                      ELSE ProofInitialization!SourceFixed(ProofObservedBefore[ProofOrder[position]])
          /\\ ProofObservedBefore = ProofObservedPrior(ProofCount)
          /\\ ProofObservedFailures = {[before |-> ProofObservedBefore, site |-> ProofOrder[ProofCount],
                                      payload |-> <<"integerOverflow", "addition", <<ExpectedOperand0, ExpectedOperand1>>>>]}
          PROOF
          <1>0. /\\ ProofCount = 4 /\\ ProofIntPositions = {2, 3, 4}
                /\\ ProofOrder = <<"pc", "first", "second", "last">>
                /\\ ExpectedFailure.site = ProofOrdinals[ProofOrder[ProofCount]]
            BY SMT DEF ProofCount, ActualInitializationOrder, ProofOrder, ProofOrdinalKey,
              ProofIntPositions, ProofIntSlots, ActualLayout, ExpectedFailure, ProofOrdinals, ProofLayoutIndex
          <1>1. /\\ DOMAIN ProofObservedBefore = {"pc", "first", "second"}
                /\\ ProofObservedBefore["pc"] = "stay" /\\ ProofObservedBefore["first"] = 1
                /\\ ProofObservedBefore["second"] = 3
                /\\ ExpectedOperand0 = 3 /\\ ExpectedOperand1 = ProofIntMax
            BY SMT DEF ProofObservedBefore, ExpectedBefore, ExpectedOperand0, ExpectedOperand1,
              ProofIntMax, ProofNames, ProofAllKeys, ProofLayoutIndex, ActualLayout,
              ProofInitialization!DecodedRenderedPrefixEntries
          <1>2. \\A position \\in 1..ProofCount :
                  /\\ ProofObservedPrior(position) \\in ProofInitialization!PartialBindings
                  /\\ DOMAIN ProofObservedPrior(position) = ProofPrefixKeys(position)
            BY <1>0, <1>1, ProofIntegerBounds, SMT
              DEF ProofObservedPrior, ProofPrefixKeys, ProofValues, ProofInitialization!PartialBindings,
                ProofInitialization!SourceRestriction
          <1>3. \\A position \\in ProofIntPositions :
                  SourcePlanHistory(ProofPlans[position], ProofReadState(position, ProofObservedPrior(position)),
                      ProofSourceExpressions[position][ProofObservedPrior(position)])
            BY <1>2, ActualInitializerExpressionsSupplyTheirParents, SMT
              DEF ProofIntPositions
          <1>4. ProofEvaluate(FALSE)[1][ProofObservedPrior(1)]
              = ProofInitialization!SourceFixed(ProofObservedBefore[ProofOrder[1]])
            BY <1>0, <1>1, <1>2, SMT
              DEF ProofEvaluate, ProofControlSeed, ActualControlSeeds, ActualInitializationOrder
          <1>5. \\A position \\in {2, 3} :
              ProofEvaluate(FALSE)[position][ProofObservedPrior(position)]
                = ProofInitialization!SourceFixed(ProofObservedBefore[ProofOrder[position]])
            BY <1>0, <1>1, <1>2, <1>3, ProofIntegerBounds, SMT
              DEF ProofEvaluate, ProofPlans, ProofSourceRow, SourceInitializers,
                ProofReadState, ProofPrefixIntNames, ProofPrefixKeys, ProofObservedPrior,
                ProofInitialization!SourceRestriction, SourcePlanHistory,
                ProofInitialization!Expressions!SourceExpressionHistory, ProofInitialization!Expressions!SourceNode,
                ProofInitialization!Expressions!SourceCombine, ProofInitialization!Expressions!SourceAdd,
                ProofInitialization!Expressions!Success, ProofInitialization!Expressions!SourceOverflow,
                ProofInitialization!Expressions!InRange, ProofInitialization!SourceIntInitializerOutcome
          <1>6. ProofEvaluate(FALSE)[ProofCount][ProofObservedPrior(ProofCount)]
              = ProofInitialization!SourceFailed(<<"integerOverflow", "addition", <<ExpectedOperand0, ExpectedOperand1>>>>)
            BY <1>0, <1>1, <1>2, <1>3, ProofIntegerBounds, SMT
              DEF ProofEvaluate, ProofPlans, ProofSourceRow, SourceInitializers,
                ProofReadState, ProofPrefixIntNames, ProofPrefixKeys, ProofObservedPrior,
                ProofInitialization!SourceRestriction, SourcePlanHistory,
                ProofInitialization!Expressions!SourceExpressionHistory, ProofInitialization!Expressions!SourceNode,
                ProofInitialization!Expressions!SourceCombine, ProofInitialization!Expressions!SourceAdd,
                ProofInitialization!Expressions!Success, ProofInitialization!Expressions!SourceOverflow,
                ProofInitialization!Expressions!InRange, ProofInitialization!SourceIntInitializerOutcome
          <1>7. /\\ ProofObservedBefore = ProofObservedPrior(ProofCount)
                /\\ ProofObservedBefore \\in [ProofPrefixKeys(ProofCount) -> ProofValues]
            BY <1>0, <1>1, ProofIntegerBounds, SMT
              DEF ProofObservedPrior, ProofPrefixKeys, ProofInitialization!SourceRestriction, ProofValues
          <1>8. ProofInitialization!DecodedRenderedInitializerSite(ExpectedFailure.site, ProofOrdinals) = ProofOrder[ProofCount]
            BY <1>0, <1>7, ActualPrefixRecordsInvokeInitializationDecoder, SMT
              DEF ProofAllKeys, ActualLayout
          <1>9. ProofObservedFailures = {[before |-> ProofObservedBefore, site |-> ProofOrder[ProofCount],
                                        payload |-> <<"integerOverflow", "addition", <<ExpectedOperand0, ExpectedOperand1>>>>]}
            BY <1>8, SMT DEF ProofObservedFailures, ExpectedFailures, ExpectedFailure, ProofObservedBefore,
              ProofInitialization!DecodedNamedRenderedAdditionEvents
          <1>. QED BY <1>0, <1>2, <1>4, <1>5, <1>6, <1>7, <1>9, SMT

        THEOREM ActualNativePrefixConstructsTheGeneratedInitializationHistory ==
          ProofInitialization!InitializationHistory(TRUE, ProofCount, ProofOrder, ProofEvaluate(TRUE), ProofObservedHistory)
          PROOF
          <1>0. /\\ ProofCount \\in Nat /\\ ProofCount > 0
                /\\ ProofInitialization!InitializationOrder(ProofCount, ProofOrder)
                /\\ ProofInitialization!InitializerEvaluators(ProofCount, ProofEvaluate(TRUE))
            BY ActualLayoutSuppliesInitializationDecoderInputs, ActualInitializerEvaluatorsAreTypedAndAgree, SMT
              DEF ProofCount, ActualInitializationOrder
          <1>1. \\A position \\in 1..(ProofCount - 1) :
                  ProofObservedPrior(position + 1) = ProofInitialization!GeneratedExtension(
                      ProofObservedPrior(position), ProofOrder[position], ProofObservedBefore[ProofOrder[position]])
            BY <1>0, ActualNativePrefixSuppliesTheSourceInitializerOutcomes,
              ProofInitialization!PrefixKeysGrowByOne, SMT
              DEF ProofObservedPrior, ProofPrefixKeys, ProofInitialization!SourceRestriction,
                ProofInitialization!GeneratedExtension, ProofInitialization!InitializationOrder
          <1>2. ProofObservedHistory[0] = ProofInitialization!InitialSeed
            BY <1>0, SMT DEF ProofObservedHistory, ProofObservedPrior, ProofPrefixKeys,
              ProofInitialization!SourceRestriction, ProofInitialization!InitialSeed
          <1>3. \\A position \\in 1..ProofCount :
                  ProofObservedHistory[position] = ProofInitialization!GeneratedAdvance(
                      ProofObservedHistory[position - 1], ProofOrder[position], ProofEvaluate(TRUE)[position])
            BY <1>0, <1>1, ActualNativePrefixSuppliesTheSourceInitializerOutcomes,
              ActualInitializerEvaluatorsAreTypedAndAgree, ProofInitialSentinels, SMT
              DEF ProofObservedHistory, ProofObservedResult, ProofInitialization!GeneratedAdvance,
                ProofInitialization!GeneratedInitialStates, ProofInitialization!GeneratedInitialFailures,
                ProofInitialization!SourceFixed, ProofInitialization!SourceFailed
          <1>4. ProofObservedHistory \\in [0..ProofCount -> ProofInitialization!InitializationResults]
            BY <1>0, ActualNativePrefixSuppliesTheSourceInitializerOutcomes, ProofIntegerBounds,
              ActualLayoutSuppliesInitializationDecoderInputs, ActualInitializerEvaluatorsAreTypedAndAgree, SMT
              DEF ProofObservedHistory, ProofObservedResult, ProofObservedFailures,
                ProofInitialization!InitializationResults, ProofInitialization!InitialFailureEvents,
                ProofInitialization!IntInitializationDomains, ProofInitialization!InitializerEvaluators,
                ProofInitialization!InitializerOutcomes, ProofInitialization!SourceFailed, ProofNoFailure
          <1>. QED BY <1>0, <1>2, <1>3, <1>4, SMT
            DEF ProofInitialization!InitializationHistory, ProofInitialization!InitializationAdvance

        THEOREM CompleteInitializationMatchesActualOutputs ==
          \\E source, generated, observations :
            /\\ ProofInitialization!InitializationHistory(FALSE, ProofCount, ProofOrder, ProofEvaluate(FALSE), source)
            /\\ ProofInitialization!InitializationHistory(TRUE, ProofCount, ProofOrder, ProofEvaluate(TRUE), generated)
            /\\ source[ProofCount] = generated[ProofCount]
            /\\ source[ProofCount].states = {}
            /\\ source[ProofCount].failures = ProofInitialization!DecodedNamedRenderedAdditionEvents(
                   \(events[0]), ProofNames, ProofOrdinals)
            /\\ ProofInitialization!SingleBranchInitialObservationHistory(ProofCount, ProofOrder, ProofEvaluate(FALSE), observations)
            /\\ ProofInitialization!SingleBranchInitialObservationHistory(ProofCount, ProofOrder, ProofEvaluate(TRUE), observations)
            /\\ ProofInitialization!InitialSetProjection(observations[ProofCount]) = source[ProofCount]
            /\\ observations[ProofCount].stateCount = 0 /\\ observations[ProofCount].failureCount = 1
            /\\ {observations[ProofCount].failureHistory[1]} = ProofObservedFailures
            /\\ ~Init
          PROOF
          <1>0. ProofInitialization!InitializationOrder(ProofCount, ProofOrder)
            BY ActualLayoutSuppliesInitializationDecoderInputs, SMT
          <1>1. PICK source, generated, observations :
                  /\\ ProofInitialization!InitializationHistory(FALSE, ProofCount, ProofOrder, ProofEvaluate(FALSE), source)
                  /\\ ProofInitialization!InitializationHistory(TRUE, ProofCount, ProofOrder, ProofEvaluate(TRUE), generated)
                  /\\ \\A index \\in 0..ProofCount : source[index] = generated[index]
                  /\\ ProofInitialization!SingleBranchInitialObservationHistory(ProofCount, ProofOrder, ProofEvaluate(FALSE), observations)
                  /\\ ProofInitialization!SingleBranchInitialObservationHistory(ProofCount, ProofOrder, ProofEvaluate(TRUE), observations)
                  /\\ ProofInitialization!InitialSetProjection(observations[ProofCount]) = source[ProofCount]
                  /\\ ProofInitialization!InitialObservationIsTyped(observations[ProofCount])
                  /\\ observations[ProofCount].stateCount <= 1 /\\ observations[ProofCount].failureCount <= 1
                  /\\ observations[ProofCount].stateCount + observations[ProofCount].failureCount = 1
            BY ActualPlansInvokeCompleteInitializationAndObservationParents, SMT
              DEF ProofCount, ActualInitializationOrder
          <1>2. \\A index \\in 0..ProofCount : source[index] = ProofObservedHistory[index]
            BY <1>0, <1>1, ActualNativePrefixConstructsTheGeneratedInitializationHistory,
              ActualInitializerEvaluatorsAreTypedAndAgree, ProofInitialization!InitializationHistoriesRetainAllStatesAndFailures, SMT
              DEF ProofInitialization!InitializationHistory, ProofInitialization!InitializationResults
          <1>3. /\\ source[ProofCount].states = {}
                /\\ source[ProofCount].failures = ProofObservedFailures
                /\\ ProofObservedFailures # {}
            BY <1>0, <1>2, ActualNativePrefixSuppliesTheSourceInitializerOutcomes, SMT
              DEF ProofObservedHistory, ProofObservedResult, ProofInitialization!InitializationOrder
          <1>4. /\\ observations[ProofCount].stateCount = 0 /\\ observations[ProofCount].failureCount = 1
                /\\ {observations[ProofCount].failureHistory[1]} = ProofObservedFailures
            BY <1>1, <1>3, SMT DEF ProofInitialization!InitialSetProjection,
              ProofInitialization!InitialFailureSet, ProofInitialization!InitialObservationIsTyped,
              ProofInitialization!InitialFailureHistory
          <1>. QED BY <1>0, <1>1, <1>3, <1>4, CompleteFailureEvents, InitialFailurePrecedesGraph, SMT
            DEF ProofObservedFailures
        ====
        """
    }

    private static func binaryLiteral(_ value: Int) -> String {
        let radix: UInt = 1_073_741_824
        var magnitude = value.magnitude
        var digits: [UInt] = []
        repeat {
            digits.append(magnitude % radix)
            magnitude /= radix
        } while magnitude != 0
        var expression = String(digits.removeLast())
        while let digit = digits.popLast() {
            expression = "(\(expression) * \(radix) + \(digit))"
        }
        return value < 0 ? "-(\(expression))" : expression
    }

    private static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.first, first.isLetter || first == "_" else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
