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
        guard let check = try rendered.initialEvaluationFailureBundle(capturingRecord: true) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let module = rendered.tlaBundle.root
        let proof = try proofSource(module: module.name, tla: module.tla,
            site: site, operands: operands, before: failures[0].before,
            sourceInitializers: sourceInitializers, loweredInitializers: loweredInitializers)
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
            schema: "swifttla.initial-failure-proof-v6", sourceSHA: sourceSHA,
            module: module.name, moduleSHA256: SHA256.hex(Data(module.tla.utf8)),
            checkModule: check.root.name,
            checkModuleSHA256: SHA256.hex(Data(check.root.tla.utf8)),
            checkConfigurationSHA256: SHA256.hex(Data(check.cfg.utf8)),
            proofSHA256: SHA256.hex(proofBytes), nativeSHA256: SHA256.hex(nativeBytes),
            sourceCompilationIdentity: compilation.identity.description,
            sourceInitializersSHA256: SHA256.hex(Data(sourceInitializers.utf8)),
            loweredInitializersSHA256: SHA256.hex(Data(loweredInitializers.utf8)),
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

    private static func proofSource(module: String, tla: String, site: Int,
                                    operands: [Int], before: [NativeInitialBindingOutput],
                                    sourceInitializers: String, loweredInitializers: String) throws -> String {
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

        THEOREM SourceInitializersMatchLoweredIR ==
          SourceInitializers = LoweredInitializers
          BY SMT DEF SourceInitializers, LoweredInitializers

        ProofIntMin == \(binaryLiteral(Int.min))
        ProofIntMax == \(binaryLiteral(Int.max))
        ProofIntKeys == {SourceInitializers[row][1] : row \\in DOMAIN SourceInitializers}
        ProofBoundKeys(row) == {SourceInitializers[earlier][1] : earlier \\in 1..(row - 1)}
        ProofExpressions == INSTANCE OrderedIntExpressionRule WITH
          Keys <- ProofIntKeys, SwiftIntMin <- ProofIntMin, SwiftIntMax <- ProofIntMax

        THEOREM ProofIntegerBounds ==
          /\\ ProofIntMin \\in Int /\\ ProofIntMax \\in Int
          /\\ ProofIntMin <= -2000000000 /\\ 2000000000 <= ProofIntMax
          BY SMT DEF ProofIntMin, ProofIntMax

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
