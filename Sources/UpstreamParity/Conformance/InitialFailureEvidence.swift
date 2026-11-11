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
    package let layoutSHA256: String
    package let initializationOrderSHA256: String
    package let prefixOrdersSHA256: String
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
        let rendered = try CheckedAdditionPrefixInitialModel.render()
        let loweredOutput = try compilation.render().tlaBundle
        guard case .compiled(let identity, _, _) = rendered.tlaBundle.provenance,
              identity == compilation.identity,
              let generatedConfiguration = rendered.tlaBundle.root.cfg,
              let loweredConfiguration = loweredOutput.root.cfg,
              rendered.tlaBundle.imports.isEmpty, loweredOutput.imports.isEmpty,
              rendered.tlaBundle.root.tla.utf8.elementsEqual(loweredOutput.root.tla.utf8),
              generatedConfiguration.utf8.elementsEqual(loweredConfiguration.utf8) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let sourceInitializers = try sourceInitializerPlans(source)
        let loweredInitializers = try loweredInitializerPlans(compilation)
        let recordInputs = try initialRecordInputs(compilation)
        guard let check = try rendered.initialEvaluationFailureBundle(capturingRecord: true) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let module = rendered.tlaBundle.root
        let proof = try proofSource(module: module.name, tla: module.tla,
            site: site, operands: operands, before: failures[0].before,
            sourceInitializers: sourceInitializers, loweredInitializers: loweredInitializers,
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
            schema: "swifttla.initial-failure-proof-v7", sourceSHA: sourceSHA,
            module: module.name, moduleSHA256: SHA256.hex(Data(module.tla.utf8)),
            checkModule: check.root.name,
            checkModuleSHA256: SHA256.hex(Data(check.root.tla.utf8)),
            checkConfigurationSHA256: SHA256.hex(Data(check.cfg.utf8)),
            proofSHA256: SHA256.hex(proofBytes), nativeSHA256: SHA256.hex(nativeBytes),
            sourceCompilationIdentity: compilation.identity.description,
            sourceInitializersSHA256: SHA256.hex(Data(sourceInitializers.utf8)),
            loweredInitializersSHA256: SHA256.hex(Data(loweredInitializers.utf8)),
            layoutSHA256: SHA256.hex(Data(recordInputs.layout.utf8)),
            initializationOrderSHA256: SHA256.hex(Data(recordInputs.order.utf8)),
            prefixOrdersSHA256: SHA256.hex(Data(recordInputs.prefixes.utf8)),
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

    private static func loweredInitializerPlans(_ compilation: CompiledSpecification) throws -> String {
        let variables = Dictionary(uniqueKeysWithValues: compilation.layout.variables.map { ($0.id, $0) })
        let names = variables.mapValues { $0.declaration.name }
        let rows = try compilation.semantics.behavior.initializations.compactMap { initialization -> String? in
            guard let variable = variables[initialization.variable] else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            guard variable.declaration.origin == .source else { return nil }
            guard case .value(let expression) = initialization.initialization,
                  let nodes = StraightLineAssignmentCheck.orderedIntPlan(expression, names: names) else {
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

    private static func initialRecordInputs(_ compilation: CompiledSpecification) throws
        -> (layout: String, order: String, prefixes: String) {
        let variables = compilation.layout.variables
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
        let ordered = try compilation.semantics.behavior.initializations.map { initialization in
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
        return (tuple(layout), tuple(ordered.map { String($0.id.ordinal) }), tuple(prefixes))
    }

    private static func proofSource(module: String, tla: String, site: Int,
                                    operands: [Int], before: [NativeInitialBindingOutput],
                                    sourceInitializers: String, loweredInitializers: String,
                                    recordInputs: (layout: String, order: String, prefixes: String)) throws -> String {
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
        ActualLayout == \(recordInputs.layout)
        ActualInitializationOrder == \(recordInputs.order)
        ActualPrefixOrders == \(recordInputs.prefixes)

        THEOREM SourceInitializersMatchLoweredIR ==
          SourceInitializers = LoweredInitializers
          BY SMT DEF SourceInitializers, LoweredInitializers

        ProofIntMin == \(binaryLiteral(Int.min))
        ProofIntMax == \(binaryLiteral(Int.max))
        ProofIntKeys == {SourceInitializers[row][1] : row \\in DOMAIN SourceInitializers}
        ProofBoundKeys(row) == {SourceInitializers[earlier][1] : earlier \\in 1..(row - 1)}
        THEOREM ProofIntegerBounds ==
          /\\ ProofIntMin \\in Int /\\ ProofIntMax \\in Int
          /\\ ProofIntMin <= -2000000000 /\\ 2000000000 <= ProofIntMax
          BY SMT DEF ProofIntMin, ProofIntMax

        ProofExpressions == INSTANCE OrderedIntExpressionRule WITH
          Keys <- ProofIntKeys, SwiftIntMin <- ProofIntMin, SwiftIntMax <- ProofIntMax

        SourcePlanHistory(plan, state, history) ==
          ProofExpressions!SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
            plan.reads, plan.left, plan.right, state, history)
        LoweredPlanHistory(plan, state, history) ==
          ProofExpressions!GeneratedExpressionHistory(plan.count, plan.kinds, plan.literals,
            plan.reads, plan.left, plan.right, state, history)

        THEOREM InitializerPlansInvokeCheckedExpressionParent ==
          \\A row \\in DOMAIN SourceInitializers :
            \\A state \\in [ProofBoundKeys(row) -> ProofIntMin..ProofIntMax] :
              \\E source, generated :
                /\\ SourcePlanHistory(SourceInitializers[row][2], state, source)
                /\\ LoweredPlanHistory(LoweredInitializers[row][2], state, generated)
                /\\ \\A index \\in 0..SourceInitializers[row][2].count :
                       /\\ ProofExpressions!OutcomeAgrees(source, generated, index)
                       /\\ source[index] \\in ProofExpressions!ExpressionOutcomes
                       /\\ generated[index] \\in ProofExpressions!ExpressionOutcomes
          PROOF
          <1>. SUFFICES ASSUME NEW row \\in DOMAIN SourceInitializers,
                              NEW state \\in [ProofBoundKeys(row) -> ProofIntMin..ProofIntMax]
                       PROVE \\E source, generated :
                         /\\ SourcePlanHistory(SourceInitializers[row][2], state, source)
                         /\\ LoweredPlanHistory(LoweredInitializers[row][2], state, generated)
                         /\\ \\A index \\in 0..SourceInitializers[row][2].count :
                                /\\ ProofExpressions!OutcomeAgrees(source, generated, index)
                                /\\ source[index] \\in ProofExpressions!ExpressionOutcomes
                                /\\ generated[index] \\in ProofExpressions!ExpressionOutcomes
            BY SMT
          <1>. DEFINE plan == SourceInitializers[row][2]
                      bound == ProofBoundKeys(row)
                      completed == ProofExpressions!CompleteIntBindings(bound, state)
          <1>0. bound \\subseteq ProofIntKeys
            BY SMT DEF bound, ProofBoundKeys, SourceInitializers, ProofIntKeys
          <1>1. completed \\in [ProofIntKeys -> ProofIntMin..ProofIntMax]
            BY <1>0, ProofExpressions!CompletingPartialBindingsRetainsEveryBoundValue, SMT
              DEF bound, completed
          <1>2. ProofExpressions!ExpressionPlan(plan.count, plan.kinds, plan.literals,
                  plan.reads, plan.left, plan.right, completed)
            BY <1>1, ProofIntegerBounds, SMT DEF plan, SourceInitializers, ProofIntKeys,
              ProofIntMin, ProofIntMax, ProofExpressions!ExpressionPlan
          <1>3. ProofExpressions!ExpressionReadKeys(plan.count, plan.kinds, plan.reads) \\subseteq bound
            BY SMT DEF plan, bound, ProofBoundKeys, SourceInitializers, ProofExpressions!ExpressionReadKeys
          <1>4. ProofExpressions!PartialExpressionPlan(plan.count, plan.kinds, plan.literals,
                  plan.reads, plan.left, plan.right, bound, state)
            BY <1>0, <1>2, <1>3, SMT DEF bound, completed, ProofExpressions!PartialExpressionPlan
          <1>5. \\E source, generated :
                  /\\ SourcePlanHistory(plan, state, source)
                  /\\ LoweredPlanHistory(plan, state, generated)
                  /\\ \\A index \\in 0..plan.count :
                         /\\ ProofExpressions!OutcomeAgrees(source, generated, index)
                         /\\ source[index] \\in ProofExpressions!ExpressionOutcomes
                         /\\ generated[index] \\in ProofExpressions!ExpressionOutcomes
            BY <1>4, ProofExpressions!PartialOrderedIntExpressionsPreserveValueAndFailure, SMT
              DEF SourcePlanHistory, LoweredPlanHistory
          <1>. QED BY <1>5, SourceInitializersMatchLoweredIR, SMT DEF plan

        ProofAllKeys == {ActualLayout[row].ordinal : row \\in DOMAIN ActualLayout}
        ProofLayoutIndex(key) == CHOOSE row \\in DOMAIN ActualLayout : ActualLayout[row].ordinal = key
        ProofNames == [key \\in ProofAllKeys |-> ActualLayout[ProofLayoutIndex(key)].name]
        ProofOrdinals == [key \\in ProofAllKeys |-> ActualLayout[ProofLayoutIndex(key)].ordinal]
        ProofIntSlots == {ActualLayout[row].ordinal :
          row \\in {entry \\in DOMAIN ActualLayout : ActualLayout[entry].origin = "source"}}
        ProofPrefixKeys(position) ==
          {ActualInitializationOrder[earlier] : earlier \\in 1..(position - 1)}
        ProofPrefixIntNames(position) ==
          {ActualLayout[ProofLayoutIndex(key)].declaration : key \\in ProofPrefixKeys(position) \\cap ProofIntSlots}
        ProofValues == Int \\cup STRING
        ProofFailureValues == ProofExpressions!ArithmeticFailures
        ProofNoFailure == <<"none", 0, 0>>
        ProofNoInitialSite == -1

        THEOREM ProofInitialSentinels ==
          /\\ ProofNoFailure \\notin ProofFailureValues
          /\\ ProofNoInitialSite \\notin ProofAllKeys
          BY SMT DEF ProofNoFailure, ProofFailureValues, ProofExpressions!ArithmeticFailures,
            ProofNoInitialSite, ProofAllKeys, ActualLayout

        ProofInitialization == INSTANCE OrderedIntInitializationComposition WITH
          Keys <- ProofAllKeys, Values <- ProofValues, FailureValues <- ProofFailureValues,
          NoFailure <- ProofNoFailure, NoInitialSite <- ProofNoInitialSite,
          IntKeys <- ProofIntSlots, SwiftIntMin <- ProofIntMin, SwiftIntMax <- ProofIntMax

        THEOREM ActualLayoutSuppliesInitializationDecoderInputs ==
          /\\ ProofInitialization!RenderedInitialRecordLayout(ProofNames, ProofOrdinals)
          /\\ \\A row \\in DOMAIN ActualLayout :
                 /\\ ProofNames[ActualLayout[row].ordinal] = ActualLayout[row].name
                 /\\ ProofOrdinals[ActualLayout[row].ordinal] = ActualLayout[row].ordinal
                 /\\ \\A other \\in DOMAIN ActualLayout :
                        ActualLayout[row].ordinal = ActualLayout[other].ordinal => row = other
          /\\ ProofIntKeys = {ActualLayout[ProofLayoutIndex(key)].declaration : key \\in ProofIntSlots}
          BY SMT DEF ActualLayout, ProofAllKeys, ProofLayoutIndex, ProofNames, ProofOrdinals,
            ProofIntSlots, ProofIntKeys, SourceInitializers, ProofInitialization!RenderedInitialRecordLayout

        THEOREM ActualPrefixRecordsInvokeInitializationDecoder ==
          /\\ \\A position \\in DOMAIN ActualInitializationOrder :
                \\A prior \\in [ProofPrefixKeys(position) -> ProofValues] :
                  /\\ ProofInitialization!RenderedInitialPrefixOrder(
                         position - 1, ActualPrefixOrders[position], prior)
                  /\\ ProofInitialization!DecodedRenderedPrefixEntries(
                         ProofInitialization!RenderedInitialPrefixEntries(
                           position - 1, ActualPrefixOrders[position], ProofNames, prior), ProofNames) = prior
                  /\\ \\A target \\in ProofAllKeys :
                         ProofInitialization!DecodedRenderedInitializerSite(ProofOrdinals[target], ProofOrdinals) = target
          /\\ \\A row \\in DOMAIN SourceInitializers :
                \\E position \\in DOMAIN ActualInitializationOrder :
                  /\\ ActualLayout[ProofLayoutIndex(ActualInitializationOrder[position])].declaration
                         = SourceInitializers[row][1]
                  /\\ ProofPrefixIntNames(position) = ProofBoundKeys(row)
                  /\\ \\A state \\in [ProofPrefixIntNames(position) -> ProofIntMin..ProofIntMax] :
                         \\E source, generated :
                           /\\ SourcePlanHistory(SourceInitializers[row][2], state, source)
                           /\\ LoweredPlanHistory(LoweredInitializers[row][2], state, generated)
                           /\\ \\A index \\in 0..SourceInitializers[row][2].count :
                                  ProofExpressions!OutcomeAgrees(source, generated, index)
          PROOF
          <1>1. ProofInitialization!RenderedInitialRecordLayout(ProofNames, ProofOrdinals)
            BY ActualLayoutSuppliesInitializationDecoderInputs, SMT
          <1>2. \\A position \\in DOMAIN ActualInitializationOrder :
                  /\\ ProofPrefixKeys(position) \\subseteq ProofAllKeys
                  /\\ position - 1 \\in Nat
                  /\\ ActualPrefixOrders[position] \\in [1..(position - 1) -> ProofPrefixKeys(position)]
                  /\\ {ActualPrefixOrders[position][index] : index \\in 1..(position - 1)} = ProofPrefixKeys(position)
                  /\\ \\A prefixLeftIndex, prefixRightIndex \\in 1..(position - 1) :
                         ActualPrefixOrders[position][prefixLeftIndex] = ActualPrefixOrders[position][prefixRightIndex]
                           => prefixLeftIndex = prefixRightIndex
            BY SMT DEF ActualInitializationOrder, ActualPrefixOrders, ProofPrefixKeys, ProofAllKeys, ActualLayout
          <1>3. \\A position \\in DOMAIN ActualInitializationOrder :
                  \\A prior \\in [ProofPrefixKeys(position) -> ProofValues] :
                    /\\ prior \\in ProofInitialization!PartialBindings
                    /\\ ProofInitialization!RenderedInitialPrefixOrder(position - 1, ActualPrefixOrders[position], prior)
            BY <1>2, SMT DEF ProofInitialization!PartialBindings, ProofInitialization!RenderedInitialPrefixOrder
          <1>4. \\A position \\in DOMAIN ActualInitializationOrder :
                  \\A prior \\in [ProofPrefixKeys(position) -> ProofValues] :
                    /\\ ProofInitialization!DecodedRenderedPrefixEntries(
                           ProofInitialization!RenderedInitialPrefixEntries(
                             position - 1, ActualPrefixOrders[position], ProofNames, prior), ProofNames) = prior
                    /\\ \\A target \\in ProofAllKeys :
                           ProofInitialization!DecodedRenderedInitializerSite(ProofOrdinals[target], ProofOrdinals) = target
            BY <1>1, <1>3, ProofInitialization!RenderedInitialPrefixAndSiteDecodingRetainsEveryIdentity, SMT
          <1>5. \\A row \\in DOMAIN SourceInitializers :
                  \\E position \\in DOMAIN ActualInitializationOrder :
                    /\\ ActualLayout[ProofLayoutIndex(ActualInitializationOrder[position])].declaration
                           = SourceInitializers[row][1]
                    /\\ ProofPrefixIntNames(position) = ProofBoundKeys(row)
            BY SMT DEF ActualLayout, ActualInitializationOrder, SourceInitializers, ProofLayoutIndex,
              ProofPrefixIntNames, ProofPrefixKeys, ProofIntSlots, ProofBoundKeys
          <1>. QED BY <1>3, <1>4, <1>5, InitializerPlansInvokeCheckedExpressionParent, SMT

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
