import Foundation
import SwiftTLA
import SwiftTLACompilerSupport
import SwiftParser
import SwiftSyntax

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
    package let configurationSHA256: String?
    package let nativeActionSHA256: String?
    package let checkModule: String
    package let checkModuleSHA256: String
    package let checkConfigurationSHA256: String
    package let proofSHA256: String
    package let authoredSourceSHA256: String?
    package let actionSourceSHA256: String?
    package let sequentialControlProofSHA256: String?
    package let scalarCopyProofSHA256: [String: String]?
    package let nativeSHA256: String
    package let sourceCompilationIdentity: String
    package let sourceInitializersSHA256: String
    package let sourceInitialControlSHA256: String
    package let loweredInitializersSHA256: String
    package let resolvedInitializersSHA256: String
    package let nativeSourceSHA256: String
    package let nativeInitializersSHA256: String
    package let resolvedVariableTypesSHA256: String
    package let layoutSHA256: String
    package let initializationOrderSHA256: String
    package let nativeInitializationOrderSHA256: String
    package let prefixOrdersSHA256: String
    package let nativePrefixOrdersSHA256: String
    package let controlSeedsSHA256: String
    package let nativeControlSeedsSHA256: String
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

    package static func prepare(sourceSHA: String, authoredSource: Data, nativeSource: String,
                                to directory: URL) throws -> InitialFailureEvidenceReport {
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
        let (compilation, sequentialControl) = try source.compileRetainingSequentialControl(retainingScalarCopyRoutes: true)
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
        guard let sourceWitness = source.orderedIntSourceComponents,
              let sourceControl = sourceWitness.compactMap({ component -> String? in
                  guard case .step(let label, _) = component else { return nil }
                  return label
              }).first else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        guard let authoredText = String(data: authoredSource, encoding: .utf8) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let authoredSyntax = try AuthoredCopySyntax.select(source: authoredText,
            modelName: String(describing: CheckedAdditionPrefixInitialModel.self))
        let syntaxProof = try AuthoredCopySyntax.proofInputs(authoredSyntax)
        let authoredControl = try? AuthoredCopySyntax.controlMachine(authoredSyntax)
        guard let copyRoutes = compilation.scalarCopyRoutes[sourceControl] else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let actionSource = try authoredActionSource(sourceWitness, syntaxProof: syntaxProof, copyRoutes: copyRoutes)
        let scalarCopyProof = try ScalarCopyActionEvidence.proof(source: source,
            compilation: compilation, rendered: rendered, authoredSource: authoredSource,
            modelName: String(describing: CheckedAdditionPrefixInitialModel.self))
        let sourceInputs = try sourceInitializerInputs(sourceWitness)
        let sourceInitializers = sourceInputs.plans
        let sourceInitialControl = TLAValue.string(sourceControl).description
        let loweredInitializers = try initializerPlans(layout: compilation.layout,
            initializations: compilation.semantics.behavior.initializations, requireTypes: false)
        let resolvedInitializers = try initializerPlans(layout: resolvedProgram.layout,
            initializations: resolvedProgram.behavior.initializations, requireTypes: true)
        let nativeInitializers = try nativeInitializerPlans(nativeSource, program: resolvedProgram)
        let nativeAction = try nativeScalarActionEvidence(nativeSource, program: resolvedProgram)
        let controlProofBytes: Data?
        if let authoredControl, let controlProof = try sequentialControl?.proofSource(
            for: rendered, layout: resolvedProgram.layout, physicalAuthored: authoredControl
        ) {
            controlProofBytes = Data(controlProof.utf8)
        } else {
            controlProofBytes = nil
        }
        let recordInputs = try initialRecordInputs(resolvedProgram, nativeSeeds: nativeInitializers.seeds)
        guard let check = try rendered.initialEvaluationFailureBundle(capturingRecord: true) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let module = rendered.tlaBundle.root
        let proof = try proofSource(module: module.name, tla: module.tla,
            site: site, operands: operands, before: failures[0].before,
            sourceInitializers: sourceInitializers, sourceCompilerInputs: sourceInputs.compilerInputs,
            sourceCompilerInputDerivations: sourceInputs.compilerDerivations, sourceCompilerInputSizes: sourceInputs.compilerSizes,
            sourceAllocationReports: sourceInputs.allocationReports,
            sourceSyntaxViews: sourceInputs.views,
            sourceSyntaxOrigins: sourceInputs.origins, sourceSyntaxIndices: sourceInputs.indices,
            sourcePlanEmissions: sourceInputs.emissions, sourceCapturedNodeTuples: sourceInputs.capturedNodeTuples,
            sourceCertificateProofs: sourceInputs.proofs,
            sourceInitializerCount: sourceInputs.count,
            sourceInitialControl: sourceInitialControl,
            loweredInitializers: loweredInitializers,
            resolvedInitializers: resolvedInitializers, nativeInitializers: nativeInitializers.plans,
            nativePrefixOrders: nativeInitializers.prefixes, nativeInitializationOrder: nativeInitializers.order,
            recordInputs: recordInputs)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let generated = directory.appendingPathComponent("generated-tla")
        try GeneratedTLCOracle.retainGeneratedInputs(check, in: generated)
        try Data(generatedConfiguration.utf8).write(to: generated.appendingPathComponent("\(module.name).cfg"), options: .atomic)
        try nativeAction.write(to: generated.appendingPathComponent("SwiftTLANativeActions.tla"), options: .atomic)
        if let controlProofBytes {
            try controlProofBytes.write(to: generated.appendingPathComponent("SwiftTLASequentialControlProof.tla"), options: .atomic)
        }
        try actionSource.write(to: generated.appendingPathComponent("SwiftTLAStayActionSource.tla"), options: .atomic)
        var scalarCopyProofHashes: [String: String] = [:]
        if let scalarCopyProof {
            guard resolvedProgram.layout == compilation.layout else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            var proofModules = [(scalarCopyProof.sourceName, scalarCopyProof.source),
                                (scalarCopyProof.parentName, scalarCopyProof.parent)]
            if let configured = scalarCopyProof.configuredBehavior(for: rendered, layout: resolvedProgram.layout) {
                proofModules.append((configured.name, configured.bytes))
            }
            for (module, bytes) in proofModules {
                try bytes.write(to: generated.appendingPathComponent("\(module).tla"), options: .withoutOverwriting)
                scalarCopyProofHashes[module] = SHA256.hex(bytes)
            }
        }
        try authoredSource.write(to: directory.appendingPathComponent("authored-model.swift"), options: .atomic)
        let nativeURL = directory.appendingPathComponent("native-initial-failure.json")
        let proofURL = generated.appendingPathComponent("\(proofModule).tla")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let nativeBytes = try encoder.encode(NativeInitialFailureOutput(
            successfulInitialStates: 0, failures: failures, site: site, kind: failureKind, operands: operands))
        try nativeBytes.write(to: nativeURL, options: .atomic)
        try Data(nativeSource.utf8).write(to: directory.appendingPathComponent("native-initial-source.swift"), options: .atomic)
        let proofBytes = Data(proof.utf8)
        try proofBytes.write(to: proofURL, options: .atomic)
        let report = InitialFailureEvidenceReport(
            schema: "swifttla.initial-failure-proof-v14", sourceSHA: sourceSHA,
            module: module.name, moduleSHA256: SHA256.hex(Data(module.tla.utf8)),
            configurationSHA256: SHA256.hex(Data(generatedConfiguration.utf8)), nativeActionSHA256: SHA256.hex(nativeAction),
            checkModule: check.root.name,
            checkModuleSHA256: SHA256.hex(Data(check.root.tla.utf8)),
            checkConfigurationSHA256: SHA256.hex(Data(check.cfg.utf8)),
            proofSHA256: SHA256.hex(proofBytes), authoredSourceSHA256: SHA256.hex(authoredSource),
            actionSourceSHA256: SHA256.hex(actionSource), sequentialControlProofSHA256: controlProofBytes.map(SHA256.hex),
            scalarCopyProofSHA256: scalarCopyProofHashes.isEmpty ? nil : scalarCopyProofHashes,
            nativeSHA256: SHA256.hex(nativeBytes),
            sourceCompilationIdentity: compilation.identity.description,
            sourceInitializersSHA256: SHA256.hex(Data(sourceInitializers.utf8)),
            sourceInitialControlSHA256: SHA256.hex(Data(sourceInitialControl.utf8)),
            loweredInitializersSHA256: SHA256.hex(Data(loweredInitializers.utf8)),
            resolvedInitializersSHA256: SHA256.hex(Data(resolvedInitializers.utf8)),
            nativeSourceSHA256: SHA256.hex(Data(nativeSource.utf8)),
            nativeInitializersSHA256: SHA256.hex(Data(nativeInitializers.plans.utf8)),
            resolvedVariableTypesSHA256: SHA256.hex(Data(recordInputs.types.utf8)),
            layoutSHA256: SHA256.hex(Data(recordInputs.layout.utf8)),
            initializationOrderSHA256: SHA256.hex(Data(recordInputs.order.utf8)),
            nativeInitializationOrderSHA256: SHA256.hex(Data(nativeInitializers.order.utf8)),
            prefixOrdersSHA256: SHA256.hex(Data(recordInputs.prefixes.utf8)),
            nativePrefixOrdersSHA256: SHA256.hex(Data(nativeInitializers.prefixes.utf8)),
            controlSeedsSHA256: SHA256.hex(Data(recordInputs.seeds.utf8)),
            nativeControlSeedsSHA256: SHA256.hex(Data(recordInputs.nativeSeeds.utf8)),
            graphCompared: false, result: "prepared", site: site,
            kind: failureKind, operands: operands)
        try encoder.encode(report).write(
            to: directory.appendingPathComponent("preparation.json"), options: .atomic)
        return report
    }

    private static func authoredActionSource(
        _ components: [_OrderedIntSourceComponent], syntaxProof: String,
        copyRoutes: StraightLineAssignmentCheck.ScalarCopyReceipt
    ) throws -> Data {
        guard let authored = ScalarCopyActionEvidence.copyRows(components), !authored.fields.isEmpty,
              !authored.rows.isEmpty else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        let fields = authored.fields
        let rows = authored.rows.map(\.value)
        func reference(_ value: StraightLineAssignmentCheck.ScalarCopyReceipt.Reference) -> TLAValue {
            switch value {
            case .state(let key): .tuple([.string("state"), .string(key)])
            case .capture(let index): .tuple([.string("capture"), .int(index)])
            }
        }
        func routes(_ values: [String: StraightLineAssignmentCheck.ScalarCopyReceipt.Reference]) -> TLAValue {
            let fields = values.map { TLARecord.Field($0.key, reference($0.value)) }
            return .record(TLARecord(fields.sorted { $0.name < $1.name }))
        }
        let descriptor = """
        ---- MODULE SwiftTLAStayActionSource ----
        EXTENDS Sequences, TLAPS

        WitnessCopyFields == \(TLAValue.set(Set(fields.map(TLAValue.string))))
        WitnessCopyActionRows == \(TLAValue.tuple(rows))
        \(syntaxProof)
        StayReads == \(TLAValue.tuple(copyRoutes.reads.map(reference)))
        StayWrites == \(routes(copyRoutes.writes))
        ====

        """
        return Data(descriptor.utf8)
    }

    // Retain the existing macro witness, independently of the built Algorithm model.
    private static func sourceInitializerInputs(_ components: [_OrderedIntSourceComponent]) throws
        -> (compilerInputs: String, compilerDerivations: String, compilerSizes: String,
            allocationReports: String, plans: String, views: String, origins: String, indices: String, emissions: String,
            capturedNodeTuples: String, proofs: String, count: Int) {
        let states = components.compactMap { component -> (root: String, initialization: VariableInitialization)? in
            guard case .variable(let root, let initialization) = component else { return nil }
            return (root, initialization)
        }
        let reads = Set(states.map(\.root))
        let compilerReads = TLAValue.set(Set(reads.map { TLAValue.string($0) }))
        let rows = try states.enumerated().map { offset, state in
            let expression: StateExpr
            switch state.initialization {
            case .value(let value): expression = .value(value)
            case .expression(let value): expression = value
            case .memberOf: throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            let input = try sourceCompilerInput(expression, row: offset + 1)
            let compilerInput = "[root |-> \(input.term), reads |-> \(compilerReads)]"
            let compilerSizes = "<<\(input.sizes.map(String.init).joined(separator: ", "))>>"
            let allocationReport = try sourceAllocationReport(row: offset + 1, sizes: input.sizes)
            let (_, traversalCountOverflowed) = input.count.addingReportingOverflow(input.additions)
            guard !traversalCountOverflowed else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
            guard let certificate = StraightLineAssignmentCheck.orderedIntCertificate(expression, reads: reads) else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            let nodes = certificate.nodes
            let syntax = try sourceSyntaxView(certificate)
            let emissionPrefix = "[count |-> \(nodes.count), height |-> 1, indices |-> <<\(nodes.count)>>, "
                + "origins |-> SourceSyntaxOrigins[\(offset + 1)], nodes |-> "
            let capturedTuple = "<<\(syntax.nodes.joined(separator: ", "))>>"
            let emission = "\(emissionPrefix)\(capturedTuple)]"
            return (
                compilerInput: compilerInput, compilerDerivation: input.derivation,
                compilerSizes: compilerSizes, allocationReport: allocationReport.definition,
                plan: "<<\(TLAValue.string(state.root)), \(try initializerPlan(nodes, root: state.root))>>",
                view: "<<\(TLAValue.string(state.root)), \(syntax.view)>>",
                origins: syntax.origins, indices: syntax.indices,
                emission: emission,
                capturedNodeTuple: "LOCAL SourceCapturedNodeTuple\(offset + 1) == \(capturedTuple)",
                proof: initializerCertificateProof(row: offset + 1, view: syntax.view, rankView: syntax.rankView,
                    emissionPrefix: emissionPrefix, origins: syntax.origins, indices: syntax.indices,
                    scalars: input.scalars, reads: compilerReads.description, term: input.term,
                    sourceDerivation: input.derivation, constructorProof: input.proof, sourceSizes: compilerSizes,
                    sourceCount: input.count, sourceOccurrenceSizes: allocationReport.occurrenceSizes, emission: emission))
        }
        guard !rows.isEmpty else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        return ("<<\(rows.map(\.compilerInput).joined(separator: ", "))>>",
                "<<\(rows.map(\.compilerDerivation).joined(separator: ", "))>>",
                "<<\(rows.map(\.compilerSizes).joined(separator: ", "))>>",
                rows.map(\.allocationReport).joined(separator: "\n"),
                "<<\(rows.map(\.plan).joined(separator: ", "))>>",
                "<<\(rows.map(\.view).joined(separator: ", "))>>",
                "<<\(rows.map(\.origins).joined(separator: ", "))>>",
                "<<\(rows.map(\.indices).joined(separator: ", "))>>",
                "<<\(rows.map(\.emission).joined(separator: ", "))>>",
                rows.map(\.capturedNodeTuple).joined(separator: "\n"),
                rows.map(\.proof).joined(separator: "\n"), rows.count)
    }

    private static func sourceCompilerInput(_ expression: StateExpr, row: Int, branches: [Int] = []) throws
        -> (term: String, derivation: String, sizes: [Int], count: Int, additions: Int, scalars: [String], proof: String) {
        // shortcut: Scalar spellings are checked per packet; prove the general encoding before widening proof coverage.
        let expressions = "ProofInitialization!Expressions!"
        let bound = "ProofBoundKeys(\(row))"
        let label = "constructor" + branches.map(String.init).joined()
        let path = "SourceCompilerInputs[\(row)].root" + branches.map { "[\($0)]" }.joined()
        let term: String
        let scalar: String
        let leafFacts: String
        switch expression {
        case .value(.int(let value)):
            term = "<<\"literal\", \(binaryLiteral(value))>>"
            scalar = value == Int.max ? "ProofIntMax" : value == Int.min ? "ProofIntMin" : String(value)
            leafFacts = "ProofIntegerBounds, SMT DEF ProofIntMin, ProofIntMax, \(expressions)InRange,"
        case .variable(let name):
            term = "<<\"read\", \(TLAValue.string(name))>>"
            scalar = String(reflecting: name)
            leafFacts = "SMT DEF ProofBoundKeys, SourceInitializers,"
        case .add(let left, let right):
            let first = try sourceCompilerInput(left, row: row, branches: branches + [2])
            let second = try sourceCompilerInput(right, row: row, branches: branches + [3])
            let count = 1 + first.count + second.count
            let term = "<<\"add\", \(first.term), \(second.term)>>"
            let derivation = "\(expressions)AllocationAddDerivation(\(first.derivation), \(second.derivation))"
            let proof = """
            \(first.proof)
            \(second.proof)
                  <3>\(label). \(expressions)AllocationConstructorDerivation(\(term), \(bound), \(derivation))
                    BY ONLY <3>\(label)2, <3>\(label)3, ProofIntegerBounds, ProofInitialSentinels, \(expressions)AddingFiniteSourceDerivationsPreservesConstructorClosure, SMT
            """
            return (term, derivation, first.sizes + second.sizes + [count], count, 1 + first.additions + second.additions,
                    first.scalars + second.scalars, proof)
        default: throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let derivation = "\(expressions)AllocationLeafDerivation(\(term))"
        let proof = """
              <3>\(label). \(expressions)AllocationConstructorDerivation(\(term), \(bound), \(derivation))
                BY ONLY <2>keys, \(leafFacts)
                  \(expressions)AllocationLeafDerivation, \(expressions)AllocationConstructorDerivation
        """
        return (term, derivation, [1], 1, 0, ["\(path)[2] = \(scalar)"], proof)
    }

    private static func sourceAllocationReport(row: Int, sizes: [Int]) throws
        -> (definition: String, occurrenceSizes: String) {
        guard !sizes.isEmpty else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        var termPositions = [sizes.count]
        var frontier = [1]
        var slot = 0
        while slot < termPositions.count {
            let term = termPositions[slot]
            if sizes[term - 1] > 1 {
                let right = term - 1
                guard right > 0, termPositions.count <= sizes.count - 2 else {
                    throw InitialFailureEvidenceError.unsupportedGeneratedOutput
                }
                let rightSize = sizes[right - 1]
                guard (1..<right).contains(rightSize) else {
                    throw InitialFailureEvidenceError.unsupportedGeneratedOutput
                }
                // In postorder, the left root is directly before the right subtree.
                termPositions.append(right - rightSize)
                termPositions.append(right)
            }
            frontier.append(termPositions.count)
            slot += 1
        }
        guard termPositions.count == sizes.count else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        let positions = termPositions.map(String.init).joined(separator: ", ")
        let counts = frontier.map(String.init).joined(separator: ", ")
        let occurrenceSizes = termPositions.map { String(sizes[$0 - 1]) }.joined(separator: ", ")
        return ("LOCAL SourceAllocationReport\(row) == [terms |-> <<\(positions)>>, frontier |-> <<\(counts)>>]",
                "<<\(occurrenceSizes)>>")
    }

    static func sourceSyntaxView(_ certificate: StraightLineAssignmentCheck.OrderedIntCertificate) throws
        -> (view: String, rankView: String, origins: String, indices: String, nodes: [String]) {
        var kinds: [String] = [], literals: [String] = [], names: [String] = []
        var left: [Int] = [], right: [Int] = []
        for node in certificate.source {
            var literal = "0", name = "0"
            var lhs = 0, rhs = 0
            switch node {
            case .literal(let value):
                kinds.append("\"literal\""); literal = binaryLiteral(value)
            case .read(let variable):
                kinds.append("\"read\""); name = TLAValue.string(variable).description
            case .add(let first, let second):
                kinds.append("\"add\"")
                lhs = first; rhs = second
            default: throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            literals.append(literal); names.append(name)
            left.append(lhs); right.append(rhs)
        }
        let nodes = certificate.nodes
        let origins = certificate.origins
        let indices = certificate.indices
        func tuple(_ values: [String]) -> String { "<<\(values.joined(separator: ", "))>>" }
        let tags = "root |-> 1, kinds |-> \(tuple(kinds))"
        let edges = "left |-> \(tuple(left.map(String.init))), right |-> \(tuple(right.map(String.init)))"
        let view = "[\(tags), literals |-> \(tuple(literals)), reads |-> \(tuple(names)), \(edges)]"
        let rankView = "[\(tags), \(edges)]"
        let records = try nodes.map { node -> String in
            let kind: String, payload: String, lhs: Int, rhs: Int
            switch node {
            case .literal(let value):
                kind = "literal"; payload = binaryLiteral(value); lhs = 0; rhs = 0
            case .read(let name):
                kind = "read"; payload = TLAValue.string(name).description; lhs = 0; rhs = 0
            case .add(let first, let second):
                kind = "add"; payload = "0"; lhs = first; rhs = second
            default: throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            return "[kind |-> \(TLAValue.string(kind)), payload |-> \(payload), left |-> \(lhs), right |-> \(rhs)]"
        }
        return (view, rankView, tuple(origins.map(String.init)), tuple(indices.map(String.init)), records)
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

    // Syntax coverage is required here; semantic interpretation of the full function remains a separate proof obligation.
    private static func nativeInitializerPlans(_ source: String, program: CompiledProgram) throws
        -> (plans: String, prefixes: String, order: String, seeds: String) {
        guard !source.utf8.contains(0) else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        let file = Parser.parse(source: source)
        guard !file.hasError else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        let members = file.statements.compactMap { $0.item.as(DeclSyntax.self) }
        let declarations = members.compactMap { $0.as(FunctionDeclSyntax.self) }
            .filter { $0.name.text == "_initialStates" }
        guard declarations.count == 1, let declaration = declarations.first,
              let initialIndex = members.firstIndex(where: {
                  $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
              }) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let tokenTables = file.statements.compactMap { $0.item.as(VariableDeclSyntax.self) }.filter {
            $0.bindings.contains {
                $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "__swifttlaFormalProjectionTokens"
            }
        }
        guard tokenTables.count == 1, let tokenTable = tokenTables.first else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let visible = try program.layout.variables.filter { $0.declaration.origin == .source }.map {
            (id: $0.id, swiftIdentifier: try nativeSourceIdentifier($0.declaration.name))
        }
        let projections = file.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }
            .filter { $0.name.text == "formalProjection" }
        guard projections.count == 1, let projection = projections.first else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let slots = nativeVariableSlots(program.layout)
        let stateFields = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0.swiftIdentifier) })
        let fields = try program.layout.variables.map { variable in
            let route = stateFields[variable.id].map { "snapshot.state.\($0)" }
                ?? "snapshot.\(slots[variable.id]!)"
            guard let type = program.variableTypes[variable.id] else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            let value: String
            switch type {
            case .int: value = "SwiftTLA._nativeFormalInt(\(route))"
            case .controlLocation:
                let cases = program.layout.controlLocations.map {
                    "case .location\($0.id.ordinal): return SwiftTLA._nativeFormalString(\(String(reflecting: $0.formalName)))"
                }.joined(separator: "\n")
                value = "try { () throws -> SwiftTLA.TLAValue in switch \(route) {\n\(cases)\n} }()"
            default: throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            return (formalName: variable.formalName, route: route, type: type, value: value)
        }
        try verifyGeneratedFormalProjectionOutput([DeclSyntax(tokenTable), DeclSyntax(projection)], fields: fields)
        guard let decodedPlans = try verifyNativeIntInitialOutput(DeclSyntax(declaration),
            program: program, variables: visible) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        try verifyGeneratedInitialConstruction(Array(members.dropFirst(initialIndex)),
            configured: !program.layout.parameters.isEmpty)
        let names = Dictionary(uniqueKeysWithValues: program.layout.variables.map {
            (slots[$0.id]!, $0.declaration.name)
        })
        let variables = Dictionary(uniqueKeysWithValues: program.layout.variables.map { ($0.id, $0) })
        let rows = try program.behavior.initializations.compactMap { initialization -> String? in
            guard let variable = variables[initialization.variable] else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            guard variable.declaration.origin == .source else { return nil }
            guard let decoded = decodedPlans.expressions[initialization.variable] else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            let nodes = try decoded.map { step -> StraightLineAssignmentCheck.OrderedIntNode in
                switch step {
                case .integer(let value): return .literal(value)
                case .slot(let slot):
                    guard let name = names[slot] else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
                    return .read(name)
                case .add(let left, let right): return .add(left + 1, right + 1)
                }
            }
            return "<<\(TLAValue.string(variable.declaration.name)), \(try initializerPlan(nodes, root: variable.declaration.name))>>"
        }
        guard !rows.isEmpty else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        let prefixes = try decodedPlans.captures.map { capture in
            let captured = try capture.map { id in
                guard let variable = variables[id] else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
                return variable
            }
            let ordinals = captured.sorted {
                $0.formalName.utf8.lexicographicallyPrecedes($1.formalName.utf8)
            }.map { String($0.id.ordinal) }
            return "<<\(ordinals.joined(separator: ", "))>>"
        }
        let tokens = declaration.tokens(viewMode: .sourceAccurate).map(\.text)
        let seeds = try decodedPlans.sites.compactMap { id -> String? in
            guard let variable = variables[id], let slot = slots[id] else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            guard variable.declaration.origin == .programCounter else { return nil }
            let prefix = ["let", slot, ":", "_ControlLocation", "=", "_ControlLocation", "."]
            let matches = tokens.indices.filter { tokens[$0] == "let" && tokens[$0...].starts(with: prefix) }
            guard matches.count == 1, let index = matches.first,
                  let member = tokens.dropFirst(index + prefix.count).first,
                  let location = program.layout.controlLocations.first(where: { "location\($0.id.ordinal)" == member })
            else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
            // The complete projection switch above binds this exact enum case to its formal label.
            return "[ordinal |-> \(id.ordinal), value |-> \(TLAValue.string(location.formalName))]"
        }
        let order = decodedPlans.sites.map { String($0.ordinal) }.joined(separator: ", ")
        return ("<<\(rows.joined(separator: ", "))>>", "<<\(prefixes.joined(separator: ", "))>>", "<<\(order)>>", "<<\(seeds.joined(separator: ", "))>>")
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

    private static func initialRecordInputs(_ program: CompiledProgram, nativeSeeds: String) throws
        -> (layout: String, order: String, prefixes: String, seeds: String, nativeSeeds: String, types: String) {
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
        return (tuple(layout), tuple(ordered.map { String($0.id.ordinal) }), tuple(prefixes),
                tuple(seeds), nativeSeeds, tuple(types))
    }

    private static func initializerCertificateProof(row: Int, view: String, rankView: String, emissionPrefix: String,
                                                    origins: String, indices: String, scalars: [String], reads: String,
                                                    term: String, sourceDerivation: String, constructorProof: String,
                                                    sourceSizes: String, sourceCount: Int,
                                                    sourceOccurrenceSizes: String, emission: String) -> String {
        let expressions = "ProofInitialization!Expressions!"
        return """
          <1>\(row). InitializerExpressionCertificate(\(row))
            PROOF
            <2>. DEFINE input == SourceCompilerInputs[\(row)]
                        derivation == SourceCompilerInputDerivations[\(row)]
                        sizes == SourceCompilerInputSizes[\(row)]
            <2>data. /\\ SourceSyntaxViews[\(row)][2] = \(view)
                     /\\ SourcePlanEmission(\(row)) = \(emission)
                     /\\ SourceSyntaxOrigins[\(row)] = \(origins)
                     /\\ SourceSyntaxIndices[\(row)] = \(indices)
              BY ONLY SMT DEF SourceSyntaxViews, SourcePlanEmission, SourcePlanEmissions, SourceSyntaxOrigins, SourceSyntaxIndices
            <2>scalars. /\\ \(scalars.joined(separator: "\n                 /\\ "))
              BY ONLY ProofIntegerBounds, SMT DEF SourceCompilerInputs, ProofIntMin, ProofIntMax
            <2>slots. ProofIntSlots = ProofIntKeys
              BY ONLY ActualLayoutSuppliesInitializationDecoderInputs, SMT
            <2>keys. /\\ ProofBoundKeys(\(row)) \\subseteq ProofIntSlots
                     /\\ input.reads = ProofIntSlots
                     /\\ ProofBoundKeys(\(row)) \\subseteq input.reads
                     /\\ SourceInitializers[\(row)][1] \\in ProofIntSlots
              PROOF
              <3>rows. 1..\(row) \\subseteq DOMAIN SourceInitializers
                BY ONLY DEF SourceInitializers
              <3>range. /\\ \(row) \\in 1..\(row)
                        /\\ 1..(\(row) - 1) \\subseteq 1..\(row)
                BY ONLY SMT
              <3>indices. /\\ \(row) \\in DOMAIN SourceInitializers
                          /\\ 1..(\(row) - 1) \\subseteq DOMAIN SourceInitializers
                BY ONLY <3>range, <3>rows, SMT
              <3>source. /\\ ProofBoundKeys(\(row)) \\subseteq ProofIntKeys
                         /\\ SourceInitializers[\(row)][1] \\in ProofIntKeys
                BY ONLY <3>indices, SMT DEF ProofBoundKeys, ProofIntKeys
              <3>slots. ProofIntSlots = \(reads)
                BY ONLY DEF ProofIntSlots, ActualLayout
              <3>reads. input.reads = \(reads)
                BY ONLY DEF input, SourceCompilerInputs
              <3>. QED BY ONLY <2>slots, <3>source, <3>slots, <3>reads
            <2>constructors.
                /\\ ProofInitialization!Expressions!AllocationConstructorDerivation(input.root, ProofBoundKeys(\(row)), derivation)
                /\\ ProofInitialization!Expressions!AllocationConstructorSizes(derivation, sizes)
              PROOF
              <3>row. /\\ input = [root |-> \(term), reads |-> \(reads)]
                      /\\ derivation = \(sourceDerivation)
                      /\\ sizes = \(sourceSizes)
                BY ONLY DEF input, derivation, sizes, SourceCompilerInputs,
                  SourceCompilerInputDerivations, SourceCompilerInputSizes
        \(constructorProof)
              <3>derivation. ProofInitialization!Expressions!AllocationConstructorDerivation(
                               input.root, ProofBoundKeys(\(row)), derivation)
                BY ONLY <3>row, <3>constructor, SMT
              <3>sizes. ProofInitialization!Expressions!AllocationConstructorSizes(derivation, sizes)
                BY ONLY <3>row, SMT DEF ProofInitialization!Expressions!AllocationLeafDerivation,
                  ProofInitialization!Expressions!AllocationAddDerivation, ProofInitialization!Expressions!AllocationConstructorSizes
              <3>. QED BY ONLY <3>derivation, <3>sizes
            <2>canonical. PICK terms, weight :
                /\\ terms = {derivation.terms[index] : index \\in 1..derivation.count}
                /\\ ProofInitialization!Expressions!SupportedAllocationInput(input.root, terms,
                     ProofInitialization!Expressions!AllocationTermSyntax(terms), weight, ProofBoundKeys(\(row)))
                /\\ weight[input.root] = sizes[derivation.count]
              BY <2>constructors, ProofInitialization!Expressions!CheckedSourceSizesSupplyTheCanonicalAllocationInput
            <2>. DEFINE syntax == \(expressions)AllocationTermSyntax(terms)
                        capturedView == SourceSyntaxViews[\(row)][2]
                        expected == SourceCompilerResults(\(row))
                        fallback == SourceInitializers[\(row)][1]
                        bound == ProofBoundKeys(\(row))
                        report == SourceAllocationReport\(row)
                        termPositions == report.terms
                        occurrenceTerms == [slot \\in DOMAIN termPositions |-> derivation.terms[termPositions[slot]]]
                        frontier == [slot \\in 0..(Len(report.frontier) - 1) |-> report.frontier[slot + 1]]
                        observed == [count |-> Len(capturedView.kinds), position |-> Len(capturedView.kinds),
                            expressions |-> occurrenceTerms,
                            source |-> [slot \\in 1..Len(capturedView.kinds) |->
                                [kind |-> capturedView.kinds[slot], literal |-> capturedView.literals[slot],
                                 read |-> capturedView.reads[slot], left |-> capturedView.left[slot],
                                 right |-> capturedView.right[slot]]]]
                        size == [origin \\in DOMAIN capturedView.kinds |-> sizes[termPositions[origin]]]
                        captured == [emitted |-> SourcePlanEmission(\(row)), inverse |-> SourceSyntaxIndices[\(row)]]
                        emitted == captured.emitted
                        inverse == captured.inverse
            <2>constructorData. /\\ derivation = \(sourceDerivation) /\\ sizes = \(sourceSizes)
              BY ONLY DEF derivation, sizes, SourceCompilerInputDerivations, SourceCompilerInputSizes
            <2>constructorSize. /\\ derivation.count = \(sourceCount)
                                 /\\ sizes[derivation.count] = \(sourceCount)
              BY ONLY <2>constructorData, SMT DEF \(expressions)AllocationLeafDerivation,
                \(expressions)AllocationAddDerivation
            <2>capacity. weight[input.root] <= ProofIntMax
              BY ONLY <2>canonical, <2>constructorSize, ProofIntegerBounds, SMT
            <2>viewData. capturedView = \(view)
              BY ONLY <2>data DEF capturedView
            <2>candidateWidth.
                /\\ observed.count = \(sourceCount)
                /\\ observed.count \\in Nat \\ {0}
                /\\ DOMAIN capturedView.kinds = 1..observed.count
                /\\ observed.count = weight[input.root]
              PROOF
              <3>viewWidth. Len(capturedView.kinds) = \(sourceCount)
                BY ONLY <2>viewData, SMT
              <3>count. observed.count = \(sourceCount)
                BY ONLY <3>viewWidth DEF observed
              <3>domain. DOMAIN capturedView.kinds = 1..observed.count
                BY ONLY <2>viewData, <3>count, SMT
              <3>. QED BY ONLY <3>count, <3>domain, <2>canonical, <2>constructorSize, SMT
            <2>positions. /\\ termPositions \\in [1..\(sourceCount) -> 1..derivation.count]
                           /\\ termPositions[1] = derivation.count
              BY ONLY <2>constructorSize, SMT DEF termPositions, report, SourceAllocationReport\(row)
            <2>sourceReport. \(expressions)BreadthFirstSourceReport(input.root, syntax, observed, frontier)
              PROOF
              <3>syntaxDomain. DOMAIN syntax = terms
                BY ONLY DEF syntax, \(expressions)AllocationTermSyntax
              <3>root. derivation.terms[derivation.count] = input.root
                BY ONLY <2>constructors DEF \(expressions)AllocationConstructorDerivation
              <3>shape. /\\ observed.count \\in Nat \\ {0}
                         /\\ observed.position = observed.count
                         /\\ observed.expressions \\in [1..observed.count -> DOMAIN syntax]
                         /\\ observed.expressions[1] = input.root
                BY ONLY <2>canonical, <2>candidateWidth, <3>syntaxDomain, <3>root, <2>positions, SMT
                  DEF observed, occurrenceTerms
              <3>frontier. /\\ frontier \\in [0..observed.count -> 1..observed.count]
                            /\\ \\A slot \\in 1..observed.count : slot <= frontier[slot - 1]
                BY ONLY <2>candidateWidth, SMT DEF frontier, report, SourceAllocationReport\(row)
              <3>breadthFirst. \(expressions)BreadthFirstSourceAllocation(observed.source, observed.count, frontier)
                BY ONLY <2>viewData, <2>candidateWidth, SMT
                  DEF \(expressions)BreadthFirstSourceAllocation, observed, frontier, report, SourceAllocationReport\(row)
              <3>syntaxPayload. \\A term \\in DOMAIN syntax : syntax[term] =
                  [kind |-> term[1], literal |-> IF term[1] = "literal" THEN term[2] ELSE 0,
                   read |-> IF term[1] = "read" THEN term[2] ELSE 0,
                   left |-> IF term[1] = "add" THEN term[2] ELSE 0,
                   right |-> IF term[1] = "add" THEN term[3] ELSE 0]
                BY ONLY DEF syntax, \(expressions)AllocationTermSyntax
              <3>payload. \(expressions)CompilerAllocatedPayloadsMatch(syntax, observed)
                PROOF
                <4>. DEFINE sourceTerms == (\(sourceDerivation)).terms
                            selected(slot) == sourceTerms[termPositions[slot]]
                <4>position. observed.position = \(sourceCount)
                  BY ONLY <3>shape, <2>candidateWidth
                <4>inputTerms. derivation.terms = sourceTerms
                  BY ONLY <2>constructorData DEF sourceTerms
                <4>terms. \\A slot \\in 1..\(sourceCount) :
                    observed.expressions[slot] = selected(slot)
                  BY ONLY <2>positions, <4>inputTerms, SMT DEF observed, occurrenceTerms, selected
                <4>sourceWidth. Len(capturedView.kinds) = \(sourceCount)
                  BY ONLY <2>viewData, SMT
                <4>fields. \\A slot \\in 1..\(sourceCount) :
                    observed.source[slot] =
                      [kind |-> capturedView.kinds[slot], literal |-> capturedView.literals[slot],
                       read |-> capturedView.reads[slot], left |-> capturedView.left[slot],
                       right |-> capturedView.right[slot]]
                  PROOF
                  <5>. SUFFICES ASSUME NEW slot \\in 1..\(sourceCount)
                               PROVE observed.source[slot] =
                      [kind |-> capturedView.kinds[slot], literal |-> capturedView.literals[slot],
                       read |-> capturedView.reads[slot], left |-> capturedView.left[slot],
                       right |-> capturedView.right[slot]]
                      OBVIOUS
                  <5>index. slot \\in 1..Len(capturedView.kinds)
                      BY ONLY (slot \\in 1..\(sourceCount)), <4>sourceWidth
                  <5>. QED BY ONLY <5>index DEF observed
                <4>. HIDE DEF observed, occurrenceTerms, syntax
                <4>kind. \\A slot \\in 1..\(sourceCount) :
                    capturedView.kinds[slot] = selected(slot)[1]
                  BY ONLY <2>viewData, SMT DEF selected, sourceTerms, termPositions, report, SourceAllocationReport\(row),
                    \(expressions)AllocationLeafDerivation, \(expressions)AllocationAddDerivation
                <4>literals. \\A slot \\in 1..\(sourceCount) :
                    (IF capturedView.kinds[slot] = "literal" THEN capturedView.literals[slot] ELSE 0)
                      = (IF selected(slot)[1] = "literal" THEN selected(slot)[2] ELSE 0)
                  BY ONLY <2>viewData, SMT DEF selected, sourceTerms, termPositions, report, SourceAllocationReport\(row),
                    \(expressions)AllocationLeafDerivation, \(expressions)AllocationAddDerivation
                <4>reads. \\A slot \\in 1..\(sourceCount) :
                    (IF capturedView.kinds[slot] = "read" THEN capturedView.reads[slot] ELSE 0)
                      = (IF selected(slot)[1] = "read" THEN selected(slot)[2] ELSE 0)
                  BY ONLY <2>viewData, SMT DEF selected, sourceTerms, termPositions, report, SourceAllocationReport\(row),
                    \(expressions)AllocationLeafDerivation, \(expressions)AllocationAddDerivation
                <4>left. \\A slot \\in 1..\(sourceCount) : capturedView.kinds[slot] = "add" =>
                    /\\ capturedView.left[slot] \\in 1..\(sourceCount)
                    /\\ selected(capturedView.left[slot]) = selected(slot)[2]
                  BY ONLY <2>viewData, SMT DEF selected, sourceTerms, termPositions, report, SourceAllocationReport\(row),
                    \(expressions)AllocationLeafDerivation, \(expressions)AllocationAddDerivation
                <4>right. \\A slot \\in 1..\(sourceCount) : capturedView.kinds[slot] = "add" =>
                    /\\ capturedView.right[slot] \\in 1..\(sourceCount)
                    /\\ selected(capturedView.right[slot]) = selected(slot)[3]
                  BY ONLY <2>viewData, SMT DEF selected, sourceTerms, termPositions, report, SourceAllocationReport\(row),
                    \(expressions)AllocationLeafDerivation, \(expressions)AllocationAddDerivation
                <4>. HIDE DEF selected, sourceTerms, capturedView, termPositions, report, derivation
                <4>entries. \\A slot \\in 1..\(sourceCount) :
                    LET term == syntax[observed.expressions[slot]]
                        actual == observed.source[slot]
                    IN /\\ actual.kind = term.kind
                       /\\ (term.kind = "literal" => actual.literal = term.literal)
                       /\\ (term.kind = "read" => actual.read = term.read)
                       /\\ (term.kind = "add" =>
                              /\\ observed.expressions[actual.left] = term.left
                              /\\ observed.expressions[actual.right] = term.right)
                  PROOF
                  <5>. SUFFICES ASSUME NEW slot \\in 1..\(sourceCount)
                       PROVE LET term == syntax[observed.expressions[slot]]
                                 actual == observed.source[slot]
                             IN /\\ actual.kind = term.kind
                                /\\ (term.kind = "literal" => actual.literal = term.literal)
                                /\\ (term.kind = "read" => actual.read = term.read)
                                /\\ (term.kind = "add" =>
                                       /\\ observed.expressions[actual.left] = term.left
                                       /\\ observed.expressions[actual.right] = term.right)
                    OBVIOUS
                  <5>member. observed.expressions[slot] \\in DOMAIN syntax
                    BY ONLY <3>shape, <2>candidateWidth, (slot \\in 1..\(sourceCount)), SMT
                  <5>term. syntax[observed.expressions[slot]] =
                      [kind |-> selected(slot)[1],
                       literal |-> IF selected(slot)[1] = "literal" THEN selected(slot)[2] ELSE 0,
                       read |-> IF selected(slot)[1] = "read" THEN selected(slot)[2] ELSE 0,
                       left |-> IF selected(slot)[1] = "add" THEN selected(slot)[2] ELSE 0,
                       right |-> IF selected(slot)[1] = "add" THEN selected(slot)[3] ELSE 0]
                    BY ONLY <5>member, <3>syntaxPayload, <4>terms, (slot \\in 1..\(sourceCount)), SMT
                  <5>. QED BY ONLY <5>term, <4>fields, <4>terms, <4>kind, <4>literals, <4>reads,
                    <4>left, <4>right, (slot \\in 1..\(sourceCount)), SMT
                <4>. QED BY ONLY <4>position, <4>entries DEF \(expressions)CompilerAllocatedPayloadsMatch
              <3>. QED BY ONLY <3>shape, <3>frontier, <3>breadthFirst, <3>payload DEF \(expressions)BreadthFirstSourceReport
            <2>sourceCapture.
                /\\ \(expressions)AllocatedSwiftSource(observed) = expected.source
                /\\ \(expressions)SwiftSourceArrayAsView(expected.source) = capturedView
              PROOF
              <3>view. \(expressions)AllocatedSourceView(observed) = capturedView
                BY ONLY <2>viewData, SMT DEF observed, \(expressions)AllocatedSourceView
              <3>natural. observed.count \\in Nat
                BY ONLY <2>candidateWidth, SMT
              <3>packed. \(expressions)AllocatedSwiftSource(observed) =
                    \(expressions)SwiftSourceArray(\(expressions)AllocatedSourceView(observed), observed.count)
                BY ONLY <3>natural, ProofIntegerBounds, ProofInitialSentinels,
                  \(expressions)AllocatedEnumArrayIsTheTraversalSource
              <3>physical. expected.source = \(expressions)SwiftSourceArray(capturedView, observed.count)
                BY ONLY DEF expected, capturedView, observed, SourceCompilerResults
              <3>decoded. \(expressions)SwiftSourceArrayAsView(
                    \(expressions)SwiftSourceArray(\(expressions)AllocatedSourceView(observed), observed.count)) =
                    \(expressions)AllocatedSourceView(observed)
                BY ONLY <3>natural, ProofIntegerBounds, ProofInitialSentinels,
                  \(expressions)AllocatedSwiftSourceDecodesToSourceView
              <3>. QED BY ONLY <3>view, <3>packed, <3>physical, <3>decoded
            <2>emissionData.
                /\\ emitted = \(emissionPrefix)SourceCapturedNodeTuple\(row)]
                /\\ emitted.origins = SourceSyntaxOrigins[\(row)]
                /\\ SourceSyntaxOrigins[\(row)] = \(origins)
                /\\ inverse = \(indices)
                /\\ emitted.count \\in Nat \\ {0}
                /\\ emitted.count = Len(SourceSyntaxOrigins[\(row)])
                /\\ Len(SourceSyntaxIndices[\(row)]) = observed.count
              PROOF
              <3>record. emitted = \(emissionPrefix)SourceCapturedNodeTuple\(row)]
                BY ONLY <2>data DEF emitted, captured, SourceCapturedNodeTuple\(row)
              <3>origins. /\\ emitted.origins = SourceSyntaxOrigins[\(row)]
                           /\\ SourceSyntaxOrigins[\(row)] = \(origins)
                BY ONLY <3>record, <2>data
              <3>indices. inverse = \(indices)
                BY ONLY <2>data DEF inverse, captured
              <3>width. /\\ emitted.count \\in Nat \\ {0}
                         /\\ emitted.count = Len(SourceSyntaxOrigins[\(row)])
                         /\\ Len(SourceSyntaxIndices[\(row)]) = observed.count
                BY ONLY <3>record, <3>origins, <3>indices, <2>candidateWidth, SMT DEF inverse, captured
              <3>. QED BY ONLY <3>record, <3>origins, <3>indices, <3>width
            <2>emissionReport.
                /\\ \(expressions)CompilerOccurrenceSizes(capturedView, size)
                /\\ \(expressions)CanonicalEmissionData(capturedView, size, captured, fallback, bound)
              PROOF
              <3>records. /\\ \(expressions)NodeEmissionArrays(emitted)
                           /\\ \(expressions)ExactEmissionNodeRecords(emitted)
                PROOF
                <4>fields.
                    /\\ emitted.count = \(sourceCount) /\\ emitted.height = 1 /\\ emitted.indices = <<\(sourceCount)>>
                    /\\ emitted.nodes = SourceCapturedNodeTuple\(row) /\\ emitted.origins = \(origins)
                  BY ONLY <2>emissionData
                <4>. HIDE DEF emitted
                <4>stack.
                    /\\ emitted.count \\in Nat /\\ emitted.height \\in Nat
                    /\\ emitted.indices \\in [1..emitted.height -> 1..emitted.count]
                    /\\ (emitted.height > 0 => emitted.indices[emitted.height] = emitted.count)
                  BY ONLY <4>fields, SMT
                <4>nodeFunction. SourceCapturedNodeTuple\(row) =
                    [index \\in 1..\(sourceCount) |-> SourceCapturedNodeTuple\(row)[index]]
                  BY ONLY SMT DEF SourceCapturedNodeTuple\(row)
                <4>originFunction. (\(origins)) = [index \\in 1..\(sourceCount) |-> (\(origins))[index]]
                  BY ONLY SMT
                <4>arrays. \(expressions)NodeEmissionArrays(emitted)
                  BY ONLY <4>fields, <4>stack, <4>nodeFunction, <4>originFunction
                    DEF \(expressions)NodeEmissionArrays
                <4>nodeRecords. \\A index \\in 1..\(sourceCount) :
                    LET node == SourceCapturedNodeTuple\(row)[index]
                    IN node = [kind |-> node.kind, payload |-> node.payload, left |-> node.left, right |-> node.right]
                  BY ONLY SMT DEF SourceCapturedNodeTuple\(row)
                <4>exact. \(expressions)ExactEmissionNodeRecords(emitted)
                  BY ONLY <4>fields, <4>nodeRecords DEF \(expressions)ExactEmissionNodeRecords
                <4>. QED BY ONLY <4>arrays, <4>exact
              <3>maps.
                  /\\ inverse \\in [DOMAIN capturedView.kinds -> 1..emitted.count]
                  /\\ emitted.origins \\in [1..emitted.count -> DOMAIN capturedView.kinds]
                  /\\ \\A index \\in 1..emitted.count : inverse[emitted.origins[index]] = index
                  /\\ \\A origin \\in DOMAIN capturedView.kinds : emitted.origins[inverse[origin]] = origin
                  /\\ emitted.origins[emitted.count] = capturedView.root
                PROOF
                <4>. DEFINE originData == \(origins)
                            inverseData == \(indices)
                <4>view. /\\ DOMAIN capturedView.kinds = 1..\(sourceCount) /\\ capturedView.root = 1
                  BY ONLY <2>viewData, SMT
                <4>arrays. /\\ emitted.count = \(sourceCount) /\\ emitted.origins = originData /\\ inverse = inverseData
                  BY ONLY <2>emissionData DEF originData, inverseData
                <4>originType. originData \\in [1..\(sourceCount) -> 1..\(sourceCount)]
                  BY ONLY SMT DEF originData
                <4>inverseType. inverseData \\in [1..\(sourceCount) -> 1..\(sourceCount)]
                  BY ONLY SMT DEF inverseData
                <4>indexRoundTrip. \\A index \\in 1..\(sourceCount) : inverseData[originData[index]] = index
                  BY ONLY SMT DEF originData, inverseData
                <4>originRoundTrip. \\A origin \\in 1..\(sourceCount) : originData[inverseData[origin]] = origin
                  BY ONLY SMT DEF originData, inverseData
                <4>rootLast. originData[\(sourceCount)] = 1
                  BY ONLY DEF originData
                <4>. HIDE DEF emitted, inverse, capturedView, originData, inverseData
                <4>. QED BY ONLY <4>view, <4>arrays, <4>originType, <4>inverseType, <4>indexRoundTrip, <4>originRoundTrip, <4>rootLast, SMT
              <3>payload. \(expressions)AllNodePayloadsMatchSource(capturedView, emitted)
                PROOF
                <4>. DEFINE nodeData == SourceCapturedNodeTuple\(row)
                            originData == \(origins)
                            sourcePayload(origin) ==
                                IF capturedView.kinds[origin] = "literal" THEN capturedView.literals[origin]
                                ELSE IF capturedView.kinds[origin] = "read" THEN capturedView.reads[origin] ELSE 0
                <4>fields. /\\ emitted.count = \(sourceCount)
                            /\\ emitted.nodes = nodeData /\\ emitted.origins = originData
                  BY ONLY <2>emissionData DEF nodeData, originData
                <4>kinds. \\A index \\in 1..\(sourceCount) :
                    /\\ nodeData[index].kind \\in {"literal", "read", "add"}
                    /\\ nodeData[index].kind = capturedView.kinds[originData[index]]
                  BY ONLY <2>viewData, SMT DEF nodeData, originData, SourceCapturedNodeTuple\(row)
                <4>scalars. \\A index \\in 1..\(sourceCount) :
                    nodeData[index].payload = sourcePayload(originData[index])
                  BY ONLY <2>viewData, SMT DEF nodeData, originData, sourcePayload, SourceCapturedNodeTuple\(row)
                <4>children. \\A index \\in 1..\(sourceCount) :
                    LET node == nodeData[index]
                        origin == originData[index]
                    IN IF node.kind = "add"
                       THEN /\\ node.left \\in 1..(index - 1) /\\ node.right \\in 1..(index - 1)
                            /\\ originData[node.left] = capturedView.left[origin]
                            /\\ originData[node.right] = capturedView.right[origin]
                       ELSE /\\ node.left = 0 /\\ node.right = 0
                  BY ONLY <2>viewData, SMT DEF nodeData, originData, SourceCapturedNodeTuple\(row)
                <4>. HIDE DEF emitted, capturedView, nodeData, originData
                <4>. QED BY ONLY <4>fields, <4>kinds, <4>scalars, <4>children, SMT
                  DEF sourcePayload, \(expressions)AllNodePayloadsMatchSource, \(expressions)NodePayloadMatchesSource
              <3>typed.
                  /\\ \(expressions)TypedVisitedSourceInputs(capturedView, emitted)
                  /\\ \\A index \\in 1..emitted.count : emitted.nodes[index].kind = "read"
                         => emitted.nodes[index].payload \\in bound
                PROOF
                <4>allocation. /\\ observed.expressions \\in [1..observed.count -> DOMAIN syntax]
                                /\\ observed.position = observed.count
                                /\\ \(expressions)CompilerAllocatedPayloadsMatch(syntax, observed)
                  BY ONLY <2>sourceReport DEF \(expressions)BreadthFirstSourceReport
                <4>termTypes. \\A term \\in DOMAIN syntax :
                    /\\ syntax[term].kind = "literal" => \(expressions)InRange(syntax[term].literal)
                    /\\ syntax[term].kind = "read" => syntax[term].read \\in bound
                  BY ONLY <2>canonical, SMT DEF syntax, bound, \(expressions)SupportedAllocationInput
                <4>sourceTypes. \\A origin \\in DOMAIN capturedView.kinds :
                    /\\ capturedView.kinds[origin] = "literal" => \(expressions)InRange(capturedView.literals[origin])
                    /\\ capturedView.kinds[origin] = "read" => capturedView.reads[origin] \\in bound
                  PROOF
                  <5>. SUFFICES ASSUME NEW origin \\in DOMAIN capturedView.kinds
                       PROVE
                         /\\ capturedView.kinds[origin] = "literal" => \(expressions)InRange(capturedView.literals[origin])
                         /\\ capturedView.kinds[origin] = "read" => capturedView.reads[origin] \\in bound
                    OBVIOUS
                  <5>. DEFINE node == observed.source[origin]
                              term == syntax[observed.expressions[origin]]
                  <5>slot. /\\ origin \\in 1..observed.count /\\ origin \\in 1..observed.position
                    BY ONLY <2>candidateWidth, <4>allocation, origin \\in DOMAIN capturedView.kinds
                  <5>fields. /\\ node.kind = capturedView.kinds[origin]
                             /\\ node.literal = capturedView.literals[origin]
                             /\\ node.read = capturedView.reads[origin]
                    BY ONLY <5>slot, SMT DEF node, observed
                  <5>matches. /\\ node.kind = term.kind
                              /\\ (term.kind = "literal" => node.literal = term.literal)
                              /\\ (term.kind = "read" => node.read = term.read)
                    BY ONLY <4>allocation, <5>slot, SMT DEF node, term, \(expressions)CompilerAllocatedPayloadsMatch
                  <5>types. /\\ term.kind = "literal" => \(expressions)InRange(term.literal)
                            /\\ term.kind = "read" => term.read \\in bound
                    BY ONLY <4>allocation, <4>termTypes, <5>slot, SMT DEF term
                  <5>. QED BY ONLY <5>fields, <5>matches, <5>types, SMT
                <4>keys. bound \\subseteq ProofIntSlots
                  BY ONLY <2>keys DEF bound
                <4>origins. emitted.origins \\in [1..emitted.count -> DOMAIN capturedView.kinds]
                  BY ONLY <3>maps
                <4>visited. \(expressions)TypedVisitedSourceInputs(capturedView, emitted)
                  BY ONLY <4>sourceTypes, <4>keys, <4>origins, SMT DEF \(expressions)TypedVisitedSourceInputs
                <4>readPayloads. \\A index \\in 1..emitted.count : emitted.nodes[index].kind = "read"
                       => emitted.nodes[index].payload \\in bound
                  PROOF
                  <5>. SUFFICES ASSUME NEW index \\in 1..emitted.count, emitted.nodes[index].kind = "read"
                       PROVE emitted.nodes[index].payload \\in bound
                    OBVIOUS
                  <5>. DEFINE origin == emitted.origins[index]
                  <5>read. /\\ capturedView.kinds[origin] = "read"
                           /\\ emitted.nodes[index].payload = capturedView.reads[origin]
                    BY ONLY index \\in 1..emitted.count, emitted.nodes[index].kind = "read", <3>payload,
                      SMT DEF origin, \(expressions)AllNodePayloadsMatchSource, \(expressions)NodePayloadMatchesSource
                  <5>domain. origin \\in DOMAIN capturedView.kinds
                    BY ONLY <4>origins, index \\in 1..emitted.count, SMT DEF origin
                  <5>. QED BY ONLY <5>domain, <5>read, <4>sourceTypes, SMT
                <4>. QED BY ONLY <4>visited, <4>readPayloads
              <3>certificate. \(expressions)LiteralReadAddCertificate(capturedView, emitted, inverse, fallback, bound)
                BY ONLY <2>keys, <2>emissionData, <3>records, <3>maps, <3>payload, <3>typed, SMT
                  DEF fallback, bound, \(expressions)LiteralReadAddCertificate
              <3>. DEFINE reordered == \(sourceOccurrenceSizes)
              <3>sizes. /\\ \(expressions)CompilerOccurrenceSizes(capturedView, size)
                         /\\ size = reordered
                PROOF
                <4>domain. DOMAIN capturedView.kinds = 1..\(sourceCount)
                  BY ONLY <2>candidateWidth
                <4>input. sizes = \(sourceSizes)
                  BY ONLY <2>constructorData
                <4>projection. size = [origin \\in 1..\(sourceCount) |-> sizes[termPositions[origin]]]
                  BY ONLY <4>domain DEF size
                <4>entries. \\A origin \\in 1..\(sourceCount) :
                     sizes[termPositions[origin]] = reordered[origin]
                  BY ONLY <4>input, SMT DEF termPositions, report, SourceAllocationReport\(row), reordered
                <4>shape. reordered = [origin \\in 1..\(sourceCount) |-> reordered[origin]]
                  BY ONLY SMT DEF reordered
                <4>mapped. size = reordered
                  BY ONLY <4>projection, <4>entries, <4>shape, SMT
                <4>positive. reordered \\in [1..\(sourceCount) -> Nat \\ {0}]
                  BY ONLY SMT DEF reordered
                <4>recurrence. \\A origin \\in 1..\(sourceCount) :
                    reordered[origin] = IF capturedView.kinds[origin] = "add"
                        THEN 1 + reordered[capturedView.left[origin]] + reordered[capturedView.right[origin]]
                        ELSE 1
                  BY ONLY <2>viewData, SMT DEF reordered
                <4>. QED BY ONLY <4>domain, <4>mapped, <4>positive, <4>recurrence
                  DEF \(expressions)CompilerOccurrenceSizes
              <3>ranks.
                  /\\ inverse[capturedView.root] = size[capturedView.root]
                  /\\ \\A origin \\in DOMAIN capturedView.kinds : capturedView.kinds[origin] = "add" =>
                         \(expressions)AddEmissionRanks(capturedView, size, captured, origin)
                PROOF
                <4>. DEFINE rankView == \(rankView)
                            rankData == [inverse |-> \(indices)]
                <4>view. /\\ capturedView.root = rankView.root
                         /\\ capturedView.kinds = rankView.kinds
                         /\\ capturedView.left = rankView.left /\\ capturedView.right = rankView.right
                  BY ONLY <2>viewData DEF rankView
                <4>arrays. /\\ size = reordered
                           /\\ captured.inverse = rankData.inverse /\\ inverse = rankData.inverse
                  BY ONLY <3>sizes, <2>emissionData DEF inverse, rankData
                <4>root. rankData.inverse[rankView.root] = reordered[rankView.root]
                  BY ONLY SMT DEF rankView, rankData, reordered
                <4>children. \\A origin \\in DOMAIN rankView.kinds : rankView.kinds[origin] = "add" =>
                    \(expressions)AddEmissionRanks(rankView, reordered, rankData, origin)
                  BY ONLY SMT DEF rankView, rankData, reordered, \(expressions)AddEmissionRanks
                <4>. HIDE DEF capturedView, captured, inverse, size, rankView, rankData, reordered
                <4>. QED BY ONLY <4>view, <4>arrays, <4>root, <4>children, SMT
                  DEF \(expressions)AddEmissionRanks
              <3>. QED BY ONLY <3>sizes, <3>certificate, <3>records, <3>ranks
                DEF emitted, inverse, \(expressions)CanonicalEmissionData
            <2>packed.
                /\\ expected.nodes = \(expressions)SwiftIndexedArray(emitted.count, emitted.nodes)
                /\\ expected.origins = \(expressions)SwiftIndexedArray(emitted.count, emitted.origins)
                /\\ expected.indices = \(expressions)SwiftIndexedArray(observed.count, inverse)
              PROOF
              <3>nodes. expected.nodes = \(expressions)SwiftIndexedArray(emitted.count, emitted.nodes)
                BY ONLY DEF expected, emitted, captured, SourceCompilerResults
              <3>origins. expected.origins = \(expressions)SwiftIndexedArray(emitted.count, emitted.origins)
                BY ONLY <2>emissionData DEF expected, SourceCompilerResults
              <3>indices. expected.indices = \(expressions)SwiftIndexedArray(observed.count, inverse)
                BY ONLY <2>emissionData DEF expected, inverse, captured, SourceCompilerResults
              <3>. QED BY ONLY <3>nodes, <3>origins, <3>indices
            <2>invocation. \(expressions)ReviewedOrderedIntCertificateInvocation(input.root, input.reads, syntax, weight, expected)
              PROOF
              <3>reported.
                  LET decoded == \(expressions)SwiftSourceArrayAsView(\(expressions)AllocatedSwiftSource(observed))
                  IN /\\ \(expressions)CompilerOccurrenceSizes(decoded, size)
                     /\\ \(expressions)CanonicalEmissionData(decoded, size, captured, fallback, bound)
                BY ONLY <2>sourceCapture, <2>emissionReport
              <3>supported. \(expressions)SupportedAllocationInput(input.root, terms, syntax, weight, bound)
                BY ONLY <2>canonical DEF syntax, bound
              <3>reads. bound \\subseteq input.reads
                BY ONLY <2>keys DEF bound
              <3>fallback. fallback \\in ProofIntSlots
                BY ONLY <2>keys DEF fallback
              <3>count. observed.count = weight[input.root]
                BY ONLY <2>candidateWidth
              <3>record. expected = [source |-> expected.source, nodes |-> expected.nodes,
                                    origins |-> expected.origins, indices |-> expected.indices]
                BY ONLY DEF expected, SourceCompilerResults
              <3>matched. expected = [source |-> \(expressions)AllocatedSwiftSource(observed),
                  nodes |-> \(expressions)SwiftIndexedArray(captured.emitted.count, captured.emitted.nodes),
                  origins |-> \(expressions)SwiftIndexedArray(captured.emitted.count, captured.emitted.origins),
                  indices |-> \(expressions)SwiftIndexedArray(observed.count, captured.inverse)]
                BY ONLY <3>record, <2>sourceCapture, <2>packed DEF emitted, inverse
              <3>. HIDE DEF input, syntax, observed, frontier, size, captured, fallback, bound, expected
              <3>checked. \(expressions)ReviewedOrderedIntCertificateInvocation(input.root, input.reads, syntax, weight,
                  [source |-> \(expressions)AllocatedSwiftSource(observed),
                   nodes |-> \(expressions)SwiftIndexedArray(captured.emitted.count, captured.emitted.nodes),
                   origins |-> \(expressions)SwiftIndexedArray(captured.emitted.count, captured.emitted.origins),
                   indices |-> \(expressions)SwiftIndexedArray(observed.count, captured.inverse)])
                BY ONLY <3>supported, <3>reads, <3>fallback, <3>count, <2>capacity, <2>sourceReport, <3>reported,
                  ProofIntegerBounds, ProofInitialSentinels, \(expressions)CheckedReportsIdentifyReviewedCompilerInvocation, SMT
              <3>. QED BY ONLY <3>checked, <3>matched
            <2>derived. ProofInitialization!Expressions!LiteralReadAddCertificate(
                ProofInitialization!Expressions!SwiftSourceArrayAsView(expected.source),
                ProofInitialization!Expressions!SwiftCertificateArraysAsEmission(expected),
                ProofInitialization!Expressions!SwiftArrayAsHistory(expected.indices),
                SourceInitializers[\(row)][1], ProofBoundKeys(\(row)))
              BY ONLY <2>canonical, <2>capacity, <2>keys, <2>invocation, ProofIntegerBounds, ProofInitialSentinels,
                ProofInitialization!Expressions!ActualReviewedCompilerResultSuppliesInitializerCertificate DEF syntax
            <2>projections.
                /\\ \(expressions)SwiftSourceArrayAsView(expected.source) = SourceSyntaxViews[\(row)][2]
                /\\ \(expressions)SwiftCertificateArraysAsEmission(expected) = SourcePlanEmission(\(row))
                /\\ \(expressions)SwiftArrayAsHistory(expected.indices) = SourceSyntaxIndices[\(row)]
              PROOF
              <3>shapes. /\\ emitted.count \\in Nat
                           /\\ emitted.nodes = [index \\in 1..emitted.count |-> emitted.nodes[index]]
                           /\\ emitted.origins = [index \\in 1..emitted.count |-> emitted.origins[index]]
                           /\\ inverse \\in [1..observed.count -> 1..emitted.count]
                BY ONLY <2>candidateWidth, <2>emissionReport
                  DEF \(expressions)CanonicalEmissionData, \(expressions)LiteralReadAddCertificate,
                    \(expressions)NodeEmissionArrays, emitted, inverse
              <3>indexShape. inverse = [index \\in 1..observed.count |-> inverse[index]]
                BY ONLY <3>shapes, SMT
              <3>nodes. \(expressions)SwiftArrayAsHistory(expected.nodes) = emitted.nodes
                BY ONLY <2>packed, <3>shapes, ProofIntegerBounds, ProofInitialSentinels,
                  \(expressions)SwiftIndexedArrayDecodesToHistory
              <3>origins. \(expressions)SwiftArrayAsHistory(expected.origins) = emitted.origins
                BY ONLY <2>packed, <3>shapes, ProofIntegerBounds, ProofInitialSentinels,
                  \(expressions)SwiftIndexedArrayDecodesToHistory
              <3>indices. \(expressions)SwiftArrayAsHistory(expected.indices) = inverse
                BY ONLY <2>packed, <3>indexShape, <2>candidateWidth, ProofIntegerBounds, ProofInitialSentinels,
                  \(expressions)SwiftIndexedArrayDecodesToHistory
              <3>count. expected.nodes.count = emitted.count
                BY ONLY <2>packed DEF \(expressions)SwiftIndexedArray
              <3>surface. emitted = [count |-> emitted.count, height |-> 1, indices |-> <<emitted.count>>,
                                    nodes |-> emitted.nodes, origins |-> emitted.origins]
                BY ONLY <2>emissionData
              <3>. QED BY ONLY <2>sourceCapture, <3>nodes, <3>origins, <3>indices, <3>count, <3>surface
                DEF capturedView, emitted, inverse, captured, \(expressions)SwiftCertificateArraysAsEmission
            <2>plan. ProofInitialization!Expressions!ExtractedNodePlan(
                SourcePlanEmission(\(row)), SourceInitializers[\(row)][1]) = SourceInitializers[\(row)][2]
              BY ONLY ProofInitialSentinels, SMT DEF SourcePlanEmission, SourcePlanEmissions, SourceInitializers,
                ProofInitialization!Expressions!ExtractedNodePlan
            <2>. QED BY ONLY <2>derived, <2>projections, <2>plan DEF InitializerExpressionCertificate
        """
    }

    private static func proofSource(module: String, tla: String, site: Int,
                                    operands: [Int], before: [NativeInitialBindingOutput],
                                    sourceInitializers: String, sourceCompilerInputs: String,
                                    sourceCompilerInputDerivations: String, sourceCompilerInputSizes: String,
                                    sourceAllocationReports: String,
                                    sourceSyntaxViews: String,
                                    sourceSyntaxOrigins: String, sourceSyntaxIndices: String,
                                    sourcePlanEmissions: String, sourceCapturedNodeTuples: String, sourceCertificateProofs: String,
                                    sourceInitializerCount: Int, sourceInitialControl: String,
                                    loweredInitializers: String,
                                    resolvedInitializers: String, nativeInitializers: String, nativePrefixOrders: String,
                                    nativeInitializationOrder: String,
                                    recordInputs: (layout: String, order: String, prefixes: String, seeds: String, nativeSeeds: String, types: String)) throws -> String {
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
        let certificateRows = sourceCertificateProofs
        let certificateSteps = (1...sourceInitializerCount).map { "<1>\($0)" }.joined(separator: ", ")
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
        SourceCompilerInputs == \(sourceCompilerInputs)
        SourceSyntaxViews == \(sourceSyntaxViews)
        SourceSyntaxOrigins == \(sourceSyntaxOrigins)
        SourceSyntaxIndices == \(sourceSyntaxIndices)
        SourceInitialControl == \(sourceInitialControl)
        LoweredInitializers == \(loweredInitializers)
        ResolvedInitializers == \(resolvedInitializers)
        NativeInitializers == \(nativeInitializers)
        ResolvedVariableTypes == \(recordInputs.types)
        ActualLayout == \(recordInputs.layout)
        ActualInitializationOrder == \(recordInputs.order)
        NativeInitializationOrder == \(nativeInitializationOrder)
        ActualPrefixOrders == \(recordInputs.prefixes)
        NativePrefixOrders == \(nativePrefixOrders)
        ActualControlSeeds == \(recordInputs.seeds)
        NativeControlSeeds == \(recordInputs.nativeSeeds)

        THEOREM SourceInitializersMatchLoweredIR ==
          SourceInitializers = LoweredInitializers
          BY ONLY SMT DEF SourceInitializers, LoweredInitializers

        THEOREM SourceInitialControlMatchesResolvedIR ==
          /\\ Len(ActualControlSeeds) = 1
          /\\ ActualControlSeeds[1].value = SourceInitialControl
          /\\ ActualInitializationOrder[1] = ActualControlSeeds[1].ordinal
          /\\ \\A row \\in DOMAIN ActualLayout :
                 ActualLayout[row].ordinal = ActualControlSeeds[1].ordinal
                   => ActualLayout[row].origin = "programCounter"
          BY ONLY SMT DEF SourceInitialControl, ActualControlSeeds, ActualInitializationOrder, ActualLayout

        THEOREM LoweredInitializersMatchResolvedIR ==
          LoweredInitializers = ResolvedInitializers
          BY ONLY SMT DEF LoweredInitializers, ResolvedInitializers

        THEOREM NativeInitializersMatchResolvedIR ==
          NativeInitializers = ResolvedInitializers
          BY ONLY SMT DEF NativeInitializers, ResolvedInitializers

        THEOREM NativeInitializationOrderMatchesResolvedIR ==
          NativeInitializationOrder = ActualInitializationOrder
          BY ONLY SMT DEF NativeInitializationOrder, ActualInitializationOrder

        THEOREM NativePrefixOrdersMatchResolvedIR ==
          NativePrefixOrders = ActualPrefixOrders
          BY ONLY SMT DEF NativePrefixOrders, ActualPrefixOrders

        THEOREM NativeControlSeedsMatchResolvedIR ==
          NativeControlSeeds = ActualControlSeeds
          BY ONLY SMT DEF NativeControlSeeds, ActualControlSeeds

        THEOREM ResolvedVariableTypesMatchActualLayout ==
          /\\ DOMAIN ResolvedVariableTypes = DOMAIN ActualLayout
          /\\ \\A row \\in DOMAIN ActualLayout :
                 /\\ ResolvedVariableTypes[row].ordinal = ActualLayout[row].ordinal
                 /\\ ResolvedVariableTypes[row].type =
                        IF ActualLayout[row].origin = "source" THEN "Int" ELSE "_ControlLocation"
          BY ONLY SMT DEF ResolvedVariableTypes, ActualLayout

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
        ProofCount == Len(NativeInitializationOrder)
        ProofOrder == [position \\in 1..ProofCount |-> ProofOrdinalKey(NativeInitializationOrder[position])]
        ProofPrefixKeys(position) == {ProofOrder[earlier] : earlier \\in 1..(position - 1)}
        ProofPrefixIntNames(position) == ProofPrefixKeys(position) \\cap ProofIntSlots
        ProofPrefixOrder(position) == [index \\in DOMAIN NativePrefixOrders[position] |->
          ProofOrdinalKey(NativePrefixOrders[position][index])]
        ProofValues == Int \\cup STRING
        ProofFailureValues == {"integerOverflow"} \\X {"addition"} \\X
          ((ProofIntMin..ProofIntMax) \\X (ProofIntMin..ProofIntMax))
        ProofNoFailure == <<"none", 0, 0>>
        \\* Only the proof absence marker is freshened; actual ordinal payloads are unchanged.
        ProofNoInitialSite == CHOOSE absent : absent \\notin ProofAllKeys

        THEOREM ProofInitialSentinels ==
          /\\ ProofNoFailure \\notin ProofFailureValues
          /\\ ProofNoInitialSite \\notin ProofAllKeys
          PROOF
          <1>0. \\A failure \\in ProofFailureValues : failure[1] = "integerOverflow"
            BY ONLY SMT DEF ProofFailureValues
          <1>1. ProofNoFailure[1] = "none"
            BY ONLY SMT DEF ProofNoFailure
          <1>2. ProofNoFailure \\notin ProofFailureValues
            BY ONLY <1>0, <1>1, SMT
          <1>3. \\E absent : absent \\notin ProofAllKeys
            BY ONLY NoSetContainsEverything, SMT
          <1>4. ProofNoInitialSite \\notin ProofAllKeys
            BY ONLY <1>3, SMT DEF ProofNoInitialSite
          <1>. QED BY ONLY <1>2, <1>4, SMT

        USE ProofIntegerBounds, ProofInitialSentinels

        ProofInitialization == INSTANCE OrderedIntInitializationComposition WITH
          Keys <- ProofAllKeys, Values <- ProofValues, FailureValues <- ProofFailureValues,
          NoFailure <- ProofNoFailure, NoInitialSite <- ProofNoInitialSite,
          IntKeys <- ProofIntSlots, SwiftIntMin <- ProofIntMin, SwiftIntMax <- ProofIntMax

        USE DEF ProofInitialization!InitialSentinels, ProofInitialization!Expressions!IntegerDomain

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
                 /\\ ProofLayoutIndex(ActualLayout[row].declaration) = row
                 /\\ ProofOrdinalKey(ActualLayout[row].ordinal) = ActualLayout[row].declaration
                 /\\ \\A other \\in DOMAIN ActualLayout :
                        ActualLayout[row].ordinal = ActualLayout[other].ordinal => row = other
          /\\ ProofCount = 4
          /\\ ProofAllKeys = {"pc", "first", "second", "last"}
          /\\ ProofIntSlots = {"first", "second", "last"}
          /\\ ProofOrder = <<"pc", "first", "second", "last">>
          PROOF
          <1>0. /\\ \\A row, other \\in DOMAIN ActualLayout :
                       ActualLayout[row].declaration = ActualLayout[other].declaration => row = other
                /\\ \\A row, other \\in DOMAIN ActualLayout :
                       ActualLayout[row].name = ActualLayout[other].name => row = other
                /\\ \\A row, other \\in DOMAIN ActualLayout :
                       ActualLayout[row].ordinal = ActualLayout[other].ordinal => row = other
            BY ONLY SMT DEF ActualLayout
          <1>1. \\A row \\in DOMAIN ActualLayout :
                  /\\ ProofLayoutIndex(ActualLayout[row].declaration) = row
                  /\\ ProofOrdinalKey(ActualLayout[row].ordinal) = ActualLayout[row].declaration
            <2>. SUFFICES ASSUME NEW row \\in DOMAIN ActualLayout
                         PROVE /\\ ProofLayoutIndex(ActualLayout[row].declaration) = row
                               /\\ ProofOrdinalKey(ActualLayout[row].ordinal) = ActualLayout[row].declaration
              BY SMT
            <2>0. row \\in DOMAIN ActualLayout BY SMT
            <2>1. (CHOOSE selected \\in DOMAIN ActualLayout :
                       ActualLayout[selected].declaration = ActualLayout[row].declaration) = row
              BY ONLY <1>0, <2>0, SMT
            <2>2. (CHOOSE selected \\in DOMAIN ActualLayout :
                       ActualLayout[selected].ordinal = ActualLayout[row].ordinal) = row
              BY ONLY <1>0, <2>0, SMT
            <2>. QED BY ONLY <2>1, <2>2, SMT DEF ProofLayoutIndex, ProofOrdinalKey
          <1>2. ProofInitialization!RenderedInitialRecordLayout(ProofNames, ProofOrdinals)
            BY ONLY <1>0, <1>1, SetExtensionality, SMT
              DEF ProofNames, ProofOrdinals, ProofAllKeys, ActualLayout,
                ProofInitialization!RenderedInitialRecordLayout
          <1>3a. DOMAIN ActualLayout = 1..4 /\\ DOMAIN SourceInitializers = 1..3
            BY ONLY SMT DEF ActualLayout, SourceInitializers
          <1>3b. {entry \\in DOMAIN ActualLayout : ActualLayout[entry].origin = "source"} = {2, 3, 4}
            BY ONLY <1>3a, SetExtensionality, SMT DEF ActualLayout
          <1>3c. ProofIntKeys = {"first", "second", "last"}
            BY ONLY <1>3a, SetExtensionality, SMT DEF ProofIntKeys, SourceInitializers
          <1>3d. ProofIntSlots = {"first", "second", "last"}
            BY ONLY <1>3b, SetExtensionality, SMT DEF ProofIntSlots, ActualLayout
          <1>3e. ProofAllKeys = {"pc", "first", "second", "last"}
            BY ONLY <1>3a, SetExtensionality, SMT DEF ProofAllKeys, ActualLayout
          <1>3. ProofIntKeys = ProofIntSlots /\\ ProofIntSlots \\subseteq ProofAllKeys
            BY ONLY <1>3c, <1>3d, <1>3e, SMT
          <1>4a. DOMAIN ActualLayout = 1..ProofCount /\\ ProofCount \\in Nat /\\ ProofCount = 4
            BY ONLY NativeInitializationOrderMatchesResolvedIR, SMT DEF ActualLayout, ActualInitializationOrder, ProofCount
          <1>4b. \\A position \\in 1..ProofCount : ProofOrder[position] = ActualLayout[position].declaration
            BY ONLY <1>1, <1>4a, NativeInitializationOrderMatchesResolvedIR, SMT
              DEF ProofOrder, ActualInitializationOrder, ActualLayout, ProofCount
          <1>4c. ProofOrder = <<"pc", "first", "second", "last">>
            BY ONLY <1>4a, <1>4b, NativeInitializationOrderMatchesResolvedIR, SMT DEF ProofOrder, ActualLayout
          <1>4. ProofInitialization!InitializationOrder(ProofCount, ProofOrder)
            BY ONLY <1>0, <1>4a, <1>4b, NativeInitializationOrderMatchesResolvedIR, SetExtensionality, SMT
              DEF ProofOrder, ProofAllKeys, ProofInitialization!InitializationOrder,
                ProofInitialization!PrefixKeys
          <1>5. ProofInitialization!IntInitializationDomains
            BY ONLY <1>3, ProofIntegerBounds, ProofInitialSentinels, SMT
              DEF ProofInitialization!IntInitializationDomains, ProofValues, ProofFailureValues,
                ProofInitialization!Expressions!ArithmeticFailures
          <1>6. \\A row \\in DOMAIN ActualLayout :
                  /\\ ProofNames[ActualLayout[row].declaration] = ActualLayout[row].name
                  /\\ ProofOrdinals[ActualLayout[row].declaration] = ActualLayout[row].ordinal
            BY ONLY <1>1, SMT DEF ProofNames, ProofOrdinals, ProofAllKeys
          <1>. QED BY ONLY <1>0, <1>1, <1>2, <1>3, <1>3d, <1>3e, <1>4a, <1>4c, <1>4, <1>5, <1>6,
            ResolvedVariableTypesMatchActualLayout, SMT

        USE DEF ProofInitialization!IntInitializationDomains, ProofInitialization!InitializationOrder

        SourcePlanHistory(plan, state, history) ==
          ProofInitialization!Expressions!SourceExpressionHistory(plan.count, plan.kinds, plan.literals,
            plan.reads, plan.left, plan.right, state, history)
        ResolvedPlanHistory(plan, state, history) ==
          ProofInitialization!Expressions!GeneratedExpressionHistory(plan.count, plan.kinds, plan.literals,
            plan.reads, plan.left, plan.right, state, history)

        SourcePlanEmissions == \(sourcePlanEmissions)

        \(sourceCapturedNodeTuples)
        SourcePlanEmission(row) == SourcePlanEmissions[row]

        SourceCompilerInputDerivations == \(sourceCompilerInputDerivations)
        SourceCompilerInputSizes == \(sourceCompilerInputSizes)

        \(sourceAllocationReports)

        SourceCompilerResults(row) ==
            [source |-> ProofInitialization!Expressions!SwiftSourceArray(
                 SourceSyntaxViews[row][2], Len(SourceSyntaxViews[row][2].kinds)),
             nodes |-> ProofInitialization!Expressions!SwiftIndexedArray(
                 SourcePlanEmission(row).count, SourcePlanEmission(row).nodes),
             origins |-> ProofInitialization!Expressions!SwiftIndexedArray(
                 Len(SourceSyntaxOrigins[row]), SourceSyntaxOrigins[row]),
             indices |-> ProofInitialization!Expressions!SwiftIndexedArray(
                 Len(SourceSyntaxIndices[row]), SourceSyntaxIndices[row])]

        InitializerExpressionCertificate(row) ==
          /\\ ProofInitialization!Expressions!LiteralReadAddCertificate(
               SourceSyntaxViews[row][2], SourcePlanEmission(row), SourceSyntaxIndices[row],
               SourceInitializers[row][1], ProofBoundKeys(row))
          /\\ ProofInitialization!Expressions!ExtractedNodePlan(
               SourcePlanEmission(row), SourceInitializers[row][1]) = SourceInitializers[row][2]

        THEOREM ActualInitializerExpressionCertificates ==
          \\A row \\in DOMAIN SourceInitializers : InitializerExpressionCertificate(row)
          PROOF
        \(certificateRows)
          <1>. QED BY ONLY \(certificateSteps), SMT DEF SourceInitializers

        THEOREM InitializerPlansInvokeCheckedExpressionParent ==
          \\A row \\in DOMAIN SourceInitializers :
            \\A state \\in [ProofBoundKeys(row) -> ProofIntMin..ProofIntMax] :
              /\\ ProofInitialization!Expressions!PartialExpressionPlan(SourceInitializers[row][2].count,
                     SourceInitializers[row][2].kinds, SourceInitializers[row][2].literals, SourceInitializers[row][2].reads,
                     SourceInitializers[row][2].left, SourceInitializers[row][2].right, ProofBoundKeys(row), state)
              /\\ \\A history : SourcePlanHistory(SourceInitializers[row][2], state, history) =>
                     /\\ \\E meaning : ProofInitialization!Expressions!SourceSyntaxHistory(SourceSyntaxViews[row][2], state, meaning)
                     /\\ \\A meaning : ProofInitialization!Expressions!SourceSyntaxHistory(SourceSyntaxViews[row][2], state, meaning)
                            => history[SourceInitializers[row][2].count] = meaning[SourceSyntaxViews[row][2].root]
              /\\ \\E source, generated :
                  /\\ SourcePlanHistory(SourceInitializers[row][2], state, source)
                  /\\ ResolvedPlanHistory(ResolvedInitializers[row][2], state, generated)
                  /\\ \\A index \\in 0..SourceInitializers[row][2].count :
                         /\\ ProofInitialization!Expressions!OutcomeAgrees(source, generated, index)
                         /\\ source[index] \\in ProofInitialization!Expressions!ExpressionOutcomes
                         /\\ generated[index] \\in ProofInitialization!Expressions!ExpressionOutcomes
          BY ONLY ActualInitializerExpressionCertificates, ProofIntegerBounds, ProofInitialSentinels,
            SourceInitializersMatchLoweredIR, LoweredInitializersMatchResolvedIR,
            ProofInitialization!Expressions!LiteralReadAddCertificateSuppliesExpressionParent, SMT
            DEF InitializerExpressionCertificate, SourcePlanHistory, ResolvedPlanHistory, ProofInitialization!Expressions!IntegerDomain


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
          <1>0. /\\ ProofCount = 4
                /\\ ProofAllKeys = {"pc", "first", "second", "last"}
                /\\ ProofIntSlots = {"first", "second", "last"}
                /\\ ProofOrder = <<"pc", "first", "second", "last">>
                /\\ ProofOrdinalKey(0) = "pc" /\\ ProofOrdinalKey(1) = "first"
                /\\ ProofOrdinalKey(2) = "second" /\\ ProofOrdinalKey(3) = "last"
            BY ONLY ActualLayoutSuppliesInitializationDecoderInputs, SMT DEF ActualLayout
          <1>1. ProofInitialization!RenderedInitialRecordLayout(ProofNames, ProofOrdinals)
            BY ActualLayoutSuppliesInitializationDecoderInputs, SMT
          <1>2. \\A position \\in 1..ProofCount :
                  /\\ ProofPrefixKeys(position) \\subseteq ProofAllKeys /\\ position - 1 \\in Nat
                  /\\ ProofPrefixOrder(position) \\in [1..(position - 1) -> ProofPrefixKeys(position)]
                  /\\ {ProofPrefixOrder(position)[index] : index \\in 1..(position - 1)} = ProofPrefixKeys(position)
                  /\\ \\A prefixLeftIndex, prefixRightIndex \\in 1..(position - 1) :
                         ProofPrefixOrder(position)[prefixLeftIndex] = ProofPrefixOrder(position)[prefixRightIndex]
                           => prefixLeftIndex = prefixRightIndex
            <2>. SUFFICES ASSUME NEW position \\in 1..ProofCount
                         PROVE /\\ ProofPrefixKeys(position) \\subseteq ProofAllKeys /\\ position - 1 \\in Nat
                                         /\\ ProofPrefixOrder(position) \\in [1..(position - 1) -> ProofPrefixKeys(position)]
                                         /\\ {ProofPrefixOrder(position)[index] : index \\in 1..(position - 1)} = ProofPrefixKeys(position)
                                         /\\ \\A prefixLeftIndex, prefixRightIndex \\in 1..(position - 1) :
                                                ProofPrefixOrder(position)[prefixLeftIndex] = ProofPrefixOrder(position)[prefixRightIndex]
                                                  => prefixLeftIndex = prefixRightIndex
              BY SMT
            <2>1. CASE position = 1
              BY ONLY <2>1, <1>0, NativePrefixOrdersMatchResolvedIR, SetExtensionality, SMT
                DEF ProofPrefixKeys, ProofPrefixOrder, ActualPrefixOrders
            <2>2. CASE position = 2
              BY ONLY <2>2, <1>0, NativePrefixOrdersMatchResolvedIR, SetExtensionality, SMT
                DEF ProofPrefixKeys, ProofPrefixOrder, ActualPrefixOrders
            <2>3. CASE position = 3
              BY ONLY <2>3, <1>0, NativePrefixOrdersMatchResolvedIR, SetExtensionality, SMT
                DEF ProofPrefixKeys, ProofPrefixOrder, ActualPrefixOrders
            <2>4. CASE position = 4
              BY ONLY <2>4, <1>0, NativePrefixOrdersMatchResolvedIR, SetExtensionality, SMT
                DEF ProofPrefixKeys, ProofPrefixOrder, ActualPrefixOrders
            <2>. QED BY ONLY <1>0, <2>1, <2>2, <2>3, <2>4, SMT
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
            PROOF
            <2>. SUFFICES ASSUME NEW row \\in DOMAIN SourceInitializers
                         PROVE \\E position \\in 1..ProofCount :
                             /\\ ProofOrder[position] = SourceInitializers[row][1]
                             /\\ ProofPrefixIntNames(position) = ProofBoundKeys(row)
              BY SMT
            <2>0. row \\in {1, 2, 3} BY SMT DEF SourceInitializers
            <2>1. /\\ ProofOrder[row + 1] = SourceInitializers[row][1]
                  /\\ ProofPrefixIntNames(row + 1) = ProofBoundKeys(row)
              PROOF
              <3>1. CASE row = 1
                BY ONLY <3>1, <1>0, SetExtensionality, SMT
                  DEF SourceInitializers, ProofPrefixIntNames, ProofPrefixKeys, ProofBoundKeys
              <3>2. CASE row = 2
                BY ONLY <3>2, <1>0, SetExtensionality, SMT
                  DEF SourceInitializers, ProofPrefixIntNames, ProofPrefixKeys, ProofBoundKeys
              <3>3. CASE row = 3
                BY ONLY <3>3, <1>0, SetExtensionality, SMT
                  DEF SourceInitializers, ProofPrefixIntNames, ProofPrefixKeys, ProofBoundKeys
              <3>. QED BY ONLY <2>0, <3>1, <3>2, <3>3, SMT
            <2>2. row + 1 \\in 1..ProofCount
              BY ONLY <2>0, NativeInitializationOrderMatchesResolvedIR, SMT DEF ProofCount, ActualInitializationOrder
            <2>. QED BY <2>0, <2>1, <2>2, SMT
          <1>6. \\A row \\in DOMAIN SourceInitializers : \\E position \\in 1..ProofCount :
                /\\ ProofOrder[position] = SourceInitializers[row][1]
                /\\ ProofPrefixIntNames(position) = ProofBoundKeys(row)
                /\\ \\A state \\in [ProofPrefixIntNames(position) -> ProofIntMin..ProofIntMax] :
                       \\E source, generated :
                         /\\ SourcePlanHistory(SourceInitializers[row][2], state, source)
                         /\\ ResolvedPlanHistory(ResolvedInitializers[row][2], state, generated)
                         /\\ \\A index \\in 0..SourceInitializers[row][2].count :
                                ProofInitialization!Expressions!OutcomeAgrees(source, generated, index)
            <2>. SUFFICES ASSUME NEW row \\in DOMAIN SourceInitializers
                         PROVE \\E position \\in 1..ProofCount :
                             /\\ ProofOrder[position] = SourceInitializers[row][1]
                             /\\ ProofPrefixIntNames(position) = ProofBoundKeys(row)
                             /\\ \\A state \\in [ProofPrefixIntNames(position) -> ProofIntMin..ProofIntMax] :
                                    \\E source, generated :
                                      /\\ SourcePlanHistory(SourceInitializers[row][2], state, source)
                                      /\\ ResolvedPlanHistory(ResolvedInitializers[row][2], state, generated)
                                      /\\ \\A index \\in 0..SourceInitializers[row][2].count :
                                             ProofInitialization!Expressions!OutcomeAgrees(source, generated, index)
              BY SMT
            <2>0. row \\in DOMAIN SourceInitializers BY SMT
            <2>1. PICK position \\in 1..ProofCount :
                /\\ ProofOrder[position] = SourceInitializers[row][1]
                /\\ ProofPrefixIntNames(position) = ProofBoundKeys(row)
              BY <1>5, SMT
            <2>2. \\A state \\in [ProofPrefixIntNames(position) -> ProofIntMin..ProofIntMax] :
                    \\E source, generated :
                      /\\ SourcePlanHistory(SourceInitializers[row][2], state, source)
                      /\\ ResolvedPlanHistory(ResolvedInitializers[row][2], state, generated)
                      /\\ \\A index \\in 0..SourceInitializers[row][2].count :
                             ProofInitialization!Expressions!OutcomeAgrees(source, generated, index)
              BY ONLY <2>0, <2>1, InitializerPlansInvokeCheckedExpressionParent, SMT
            <2>. WITNESS position \\in 1..ProofCount
            <2>. QED BY ONLY <2>1, <2>2, SMT
          <1>. QED BY ONLY <1>3, <1>4, <1>6, SMT

        ProofIntPositions == {position \\in 1..ProofCount : ProofOrder[position] \\in ProofIntSlots}
        ProofSourceRow(position) == CHOOSE row \\in DOMAIN SourceInitializers : SourceInitializers[row][1] = ProofOrder[position]
        ProofPlans == [position \\in ProofIntPositions |-> SourceInitializers[ProofSourceRow(position)][2]]
        ProofResolvedPlans == [position \\in ProofIntPositions |-> ResolvedInitializers[ProofSourceRow(position)][2]]
        ProofNativePlans == [position \\in ProofIntPositions |-> NativeInitializers[ProofSourceRow(position)][2]]
        ProofSyntaxViews == [position \\in ProofIntPositions |-> SourceSyntaxViews[ProofSourceRow(position)][2]]
        ProofControlSeed(position) == (CHOOSE entry \\in {NativeControlSeeds[index] : index \\in DOMAIN NativeControlSeeds} :
          entry.ordinal = NativeInitializationOrder[position]).value
        \\* Totalize the proof input outside reached prefixes; the parent below proves no reached read uses a default.
        ProofReadState(position, prior) == [key \\in ProofPrefixIntNames(position) |->
          IF key \\in DOMAIN prior /\\ prior[key] \\in ProofIntMin..ProofIntMax THEN prior[key] ELSE 0]
        ProofSourceExpressions == [position \\in ProofIntPositions |-> [prior \\in ProofInitialization!PartialBindings |->
          CHOOSE history : SourcePlanHistory(ProofPlans[position], ProofReadState(position, prior), history)]]
        ProofGeneratedExpressions == [position \\in ProofIntPositions |-> [prior \\in ProofInitialization!PartialBindings |->
          CHOOSE history : ResolvedPlanHistory(ProofNativePlans[position], ProofReadState(position, prior), history)]]
        ProofEvaluate(generated) == [position \\in 1..ProofCount |-> [prior \\in ProofInitialization!PartialBindings |->
          IF position \\in ProofIntPositions
          THEN IF generated
               THEN ProofInitialization!GeneratedIntInitializerOutcome(ProofGeneratedExpressions[position][prior][ProofPlans[position].count])
               ELSE ProofInitialization!SourceIntInitializerOutcome(ProofSourceExpressions[position][prior][ProofPlans[position].count])
          ELSE IF generated THEN ProofInitialization!GeneratedFixed(ProofControlSeed(position))
               ELSE ProofInitialization!SourceFixed(SourceInitialControl)]]

        THEOREM ActualInitializerExpressionsSupplyTheirParents ==
          \\A position \\in ProofIntPositions : \\A prior \\in ProofInitialization!PartialBindings :
            /\\ ProofInitialization!Expressions!PartialExpressionPlan(ProofPlans[position].count,
                   ProofPlans[position].kinds, ProofPlans[position].literals, ProofPlans[position].reads,
                   ProofPlans[position].left, ProofPlans[position].right,
                   ProofPrefixIntNames(position), ProofReadState(position, prior))
            /\\ SourcePlanHistory(ProofPlans[position], ProofReadState(position, prior), ProofSourceExpressions[position][prior])
            /\\ ResolvedPlanHistory(ProofPlans[position], ProofReadState(position, prior), ProofGeneratedExpressions[position][prior])
            /\\ \\E meaning : ProofInitialization!Expressions!SourceSyntaxHistory(ProofSyntaxViews[position], ProofReadState(position, prior), meaning)
            /\\ \\A meaning : ProofInitialization!Expressions!SourceSyntaxHistory(ProofSyntaxViews[position], ProofReadState(position, prior), meaning)
                   => ProofSourceExpressions[position][prior][ProofPlans[position].count] = meaning[ProofSyntaxViews[position].root]
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
                             /\\ \\E meaning : ProofInitialization!Expressions!SourceSyntaxHistory(ProofSyntaxViews[position], ProofReadState(position, prior), meaning)
                             /\\ \\A meaning : ProofInitialization!Expressions!SourceSyntaxHistory(ProofSyntaxViews[position], ProofReadState(position, prior), meaning)
                                    => ProofSourceExpressions[position][prior][ProofPlans[position].count] = meaning[ProofSyntaxViews[position].root]
                             /\\ \\A index \\in 0..ProofPlans[position].count :
                                    /\\ ProofInitialization!Expressions!OutcomeAgrees(ProofSourceExpressions[position][prior], ProofGeneratedExpressions[position][prior], index)
                                    /\\ ProofSourceExpressions[position][prior][index] \\in ProofInitialization!Expressions!ExpressionOutcomes
                                    /\\ ProofGeneratedExpressions[position][prior][index] \\in ProofInitialization!Expressions!ExpressionOutcomes
            BY SMT
          <1>0a. /\\ ProofCount = 4 /\\ ProofIntPositions = {2, 3, 4}
                 /\\ ProofOrder = <<"pc", "first", "second", "last">>
                 /\\ ProofIntSlots = {"first", "second", "last"}
            BY ONLY ActualLayoutSuppliesInitializationDecoderInputs, SetExtensionality, SMT DEF ProofIntPositions
          <1>0. /\\ ProofSourceRow(position) \\in DOMAIN SourceInitializers
                /\\ ProofPlans[position] = SourceInitializers[ProofSourceRow(position)][2]
                /\\ ProofPrefixIntNames(position) = ProofBoundKeys(ProofSourceRow(position))
            PROOF
            <2>2. CASE position = 2
              BY ONLY <2>2, <1>0a, SetExtensionality, SMT
                DEF ProofSourceRow, ProofPlans, SourceInitializers, ProofPrefixIntNames, ProofPrefixKeys, ProofBoundKeys
            <2>3. CASE position = 3
              BY ONLY <2>3, <1>0a, SetExtensionality, SMT
                DEF ProofSourceRow, ProofPlans, SourceInitializers, ProofPrefixIntNames, ProofPrefixKeys, ProofBoundKeys
            <2>4. CASE position = 4
              BY ONLY <2>4, <1>0a, SetExtensionality, SMT
                DEF ProofSourceRow, ProofPlans, SourceInitializers, ProofPrefixIntNames, ProofPrefixKeys, ProofBoundKeys
            <2>. QED BY ONLY <1>0a, <2>2, <2>3, <2>4, SMT
          <1>1. ProofReadState(position, prior) \\in [ProofBoundKeys(ProofSourceRow(position)) -> ProofIntMin..ProofIntMax]
            BY <1>0, ProofIntegerBounds, SMT DEF ProofReadState
          <1>2. \\E source, generated :
                  /\\ SourcePlanHistory(ProofPlans[position], ProofReadState(position, prior), source)
                  /\\ ResolvedPlanHistory(ProofResolvedPlans[position], ProofReadState(position, prior), generated)
            BY <1>0, <1>1, InitializerPlansInvokeCheckedExpressionParent, SMT DEF ProofResolvedPlans
          <1>3. /\\ SourcePlanHistory(ProofPlans[position], ProofReadState(position, prior), ProofSourceExpressions[position][prior])
                /\\ ResolvedPlanHistory(ProofPlans[position], ProofReadState(position, prior), ProofGeneratedExpressions[position][prior])
            BY <1>2, SourceInitializersMatchLoweredIR, LoweredInitializersMatchResolvedIR,
              NativeInitializersMatchResolvedIR, SMT
              DEF ProofSourceExpressions, ProofGeneratedExpressions, ProofNativePlans, ProofResolvedPlans, ProofPlans
          <1>4. ProofInitialization!Expressions!PartialExpressionPlan(ProofPlans[position].count,
              ProofPlans[position].kinds, ProofPlans[position].literals, ProofPlans[position].reads,
              ProofPlans[position].left, ProofPlans[position].right,
              ProofPrefixIntNames(position), ProofReadState(position, prior))
            BY ONLY <1>0, <1>1, InitializerPlansInvokeCheckedExpressionParent, SMT
          <1>5. \\A index \\in 0..ProofPlans[position].count :
                  /\\ ProofInitialization!Expressions!OutcomeAgrees(ProofSourceExpressions[position][prior], ProofGeneratedExpressions[position][prior], index)
                  /\\ ProofSourceExpressions[position][prior][index] \\in ProofInitialization!Expressions!ExpressionOutcomes
                  /\\ ProofGeneratedExpressions[position][prior][index] \\in ProofInitialization!Expressions!ExpressionOutcomes
            BY <1>3, <1>4, ProofInitialization!Expressions!AnyPartialOrderedIntHistoriesPreserveValueAndFailure, SMT
              DEF SourcePlanHistory, ResolvedPlanHistory
          <1>6. /\\ \\E meaning : ProofInitialization!Expressions!SourceSyntaxHistory(ProofSyntaxViews[position], ProofReadState(position, prior), meaning)
                /\\ \\A meaning : ProofInitialization!Expressions!SourceSyntaxHistory(ProofSyntaxViews[position], ProofReadState(position, prior), meaning)
                       => ProofSourceExpressions[position][prior][ProofPlans[position].count] = meaning[ProofSyntaxViews[position].root]
            BY ONLY <1>0, <1>1, <1>3, InitializerPlansInvokeCheckedExpressionParent, SMT
              DEF ProofSyntaxViews
          <1>. QED BY <1>3, <1>4, <1>5, <1>6, SMT

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
          <1>0a. /\\ ProofCount = 4 /\\ ProofIntPositions = {2, 3, 4}
                 /\\ ProofOrder = <<"pc", "first", "second", "last">>
            BY ONLY ActualLayoutSuppliesInitializationDecoderInputs, SetExtensionality, SMT DEF ProofIntPositions
          <1>0b. ProofControlSeed(1) = SourceInitialControl
            BY ONLY <1>0a, SourceInitialControlMatchesResolvedIR, NativeInitializationOrderMatchesResolvedIR,
              NativeControlSeedsMatchResolvedIR, SMT
              DEF ProofControlSeed, ActualControlSeeds, ActualInitializationOrder
          <1>0c. SourceInitialControl \\in ProofValues
            BY ONLY SMT DEF SourceInitialControl, ProofValues
          <1>0d. /\\ ProofPlans[2].count = 1 /\\ ProofPlans[3].count = 3 /\\ ProofPlans[4].count = 3
            BY ONLY <1>0a, SetExtensionality, SMT DEF ProofPlans, ProofSourceRow, SourceInitializers, ProofIntPositions
          <1>0. /\\ ProofCount \\in Nat /\\ ProofIntPositions \\subseteq 1..ProofCount
                /\\ \\A position \\in (1..ProofCount) \\ ProofIntPositions : ProofControlSeed(position) \\in ProofValues
                /\\ \\A position \\in (1..ProofCount) \\ ProofIntPositions : ProofControlSeed(position) = SourceInitialControl
                /\\ \\A position \\in ProofIntPositions : ProofPlans[position].count \\in Nat
            BY ONLY <1>0a, <1>0b, <1>0c, <1>0d, SMT
          <1>0e. ProofInitialization!IntInitializationDomains
            BY ONLY ActualLayoutSuppliesInitializationDecoderInputs, SMT
          <1>1. \\A position \\in ProofIntPositions : \\A prior \\in ProofInitialization!PartialBindings :
                  /\\ ProofInitialization!SourceIntInitializerOutcome(ProofSourceExpressions[position][prior][ProofPlans[position].count])
                       = ProofInitialization!GeneratedIntInitializerOutcome(ProofGeneratedExpressions[position][prior][ProofPlans[position].count])
                  /\\ ProofInitialization!SourceIntInitializerOutcome(ProofSourceExpressions[position][prior][ProofPlans[position].count])
                       \\in ProofInitialization!InitializerOutcomes
            PROOF
            <2>. SUFFICES ASSUME NEW position \\in ProofIntPositions,
                                 NEW prior \\in ProofInitialization!PartialBindings
                         PROVE /\\ ProofInitialization!SourceIntInitializerOutcome(ProofSourceExpressions[position][prior][ProofPlans[position].count])
                                    = ProofInitialization!GeneratedIntInitializerOutcome(ProofGeneratedExpressions[position][prior][ProofPlans[position].count])
                               /\\ ProofInitialization!SourceIntInitializerOutcome(ProofSourceExpressions[position][prior][ProofPlans[position].count])
                                    \\in ProofInitialization!InitializerOutcomes
              BY SMT
            <2>0. /\\ position \\in ProofIntPositions /\\ prior \\in ProofInitialization!PartialBindings
                  /\\ ProofPlans[position].count \\in 0..ProofPlans[position].count
              BY <1>0, SMT
            <2>1. /\\ ProofSourceExpressions[position][prior][ProofPlans[position].count]
                        \\in ProofInitialization!Expressions!ExpressionOutcomes
                  /\\ ProofSourceExpressions[position][prior][ProofPlans[position].count]
                        = ProofGeneratedExpressions[position][prior][ProofPlans[position].count]
              BY ONLY <2>0, ActualInitializerExpressionsSupplyTheirParents, SMT
                DEF ProofInitialization!Expressions!OutcomeAgrees
            <2>2. /\\ ProofInitialization!SourceIntInitializerOutcome(ProofSourceExpressions[position][prior][ProofPlans[position].count])
                        = ProofInitialization!GeneratedIntInitializerOutcome(ProofSourceExpressions[position][prior][ProofPlans[position].count])
                  /\\ ProofInitialization!SourceIntInitializerOutcome(ProofSourceExpressions[position][prior][ProofPlans[position].count])
                        \\in ProofInitialization!InitializerOutcomes
              BY ONLY ProofInitialSentinels, <1>0e, <2>1, ProofInitialization!IntExpressionOutcomesSupplyInitializerOutcomes, SMT
            <2>. QED BY ONLY <2>1, <2>2, SMT
          <1>2. \\A position \\in (1..ProofCount) \\ ProofIntPositions :
                  /\\ ProofInitialization!SourceFixed(SourceInitialControl) = ProofInitialization!GeneratedFixed(ProofControlSeed(position))
                  /\\ ProofInitialization!SourceFixed(SourceInitialControl) \\in ProofInitialization!InitializerOutcomes
            BY <1>0, ProofInitialization!FixedInitializerRetainsItsOnlyCandidate, SMT
          <1>3. \\A position \\in ProofIntPositions : \\A prior \\in ProofInitialization!PartialBindings :
                  /\\ ProofEvaluate(FALSE)[position][prior].candidates \\subseteq ProofIntMin..ProofIntMax
                  /\\ (ProofEvaluate(FALSE)[position][prior].firstFailure = ProofNoFailure
                       => \\E value \\in ProofValues : ProofEvaluate(FALSE)[position][prior].candidates = {value})
            PROOF
            <2>. SUFFICES ASSUME NEW position \\in ProofIntPositions,
                                 NEW prior \\in ProofInitialization!PartialBindings
                         PROVE /\\ ProofEvaluate(FALSE)[position][prior].candidates \\subseteq ProofIntMin..ProofIntMax
                               /\\ (ProofEvaluate(FALSE)[position][prior].firstFailure = ProofNoFailure
                                    => \\E value \\in ProofValues : ProofEvaluate(FALSE)[position][prior].candidates = {value})
              BY SMT
            <2>. DEFINE result == ProofSourceExpressions[position][prior][ProofPlans[position].count]
            <2>0. result \\in ProofInitialization!Expressions!ExpressionOutcomes
              BY <1>0, ActualInitializerExpressionsSupplyTheirParents, SMT DEF result
            <2>0a. /\\ position \\in ProofIntPositions /\\ position \\in 1..ProofCount
                   /\\ prior \\in ProofInitialization!PartialBindings
              BY <1>0, SMT
            <2>1. ProofEvaluate(FALSE)[position][prior] = ProofInitialization!SourceIntInitializerOutcome(result)
              BY ONLY <2>0a, SMT DEF result, ProofEvaluate
            <2>0b. /\\ result.ok \\in BOOLEAN
                   /\\ (result.ok => result.value \\in ProofIntMin..ProofIntMax)
                   /\\ (~result.ok => result.failure \\in ProofInitialization!Expressions!ArithmeticFailures)
              BY ONLY <2>0, SMT DEF ProofInitialization!Expressions!ExpressionOutcomes
            <2>0c. /\\ ProofIntMin..ProofIntMax \\subseteq ProofValues
                   /\\ ProofNoFailure \\notin ProofInitialization!Expressions!ArithmeticFailures
              BY ONLY <1>0e, SMT DEF ProofInitialization!IntInitializationDomains
            <2>2. CASE result.ok
              <3>1. /\\ ProofEvaluate(FALSE)[position][prior].candidates = {result.value}
                    /\\ ProofEvaluate(FALSE)[position][prior].firstFailure = ProofNoFailure
                BY ONLY <2>1, <2>2, SMT
                  DEF ProofInitialization!SourceIntInitializerOutcome, ProofInitialization!SourceFixed
              <3>. QED BY ONLY <2>0b, <2>0c, <2>2, <3>1, SMT
            <2>3. CASE ~result.ok
              <3>1. /\\ ProofEvaluate(FALSE)[position][prior].candidates = {}
                    /\\ ProofEvaluate(FALSE)[position][prior].firstFailure = result.failure
                BY ONLY <2>1, <2>3, SMT
                  DEF ProofInitialization!SourceIntInitializerOutcome, ProofInitialization!SourceFailed
              <3>. QED BY ONLY <2>0b, <2>0c, <2>3, <3>1, SMT
            <2>. QED BY <2>2, <2>3, SMT DEF ProofInitialization!Expressions!ExpressionOutcomes
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
            /\\ \\A position \\in ProofIntPositions : \\A prior \\in source[position - 1].states :
                   /\\ \\E meaning : ProofInitialization!Expressions!SourceSyntaxHistory(
                          ProofSyntaxViews[position], ProofInitialization!PartialIntProjection(prior), meaning)
                   /\\ \\A meaning : ProofInitialization!Expressions!SourceSyntaxHistory(
                          ProofSyntaxViews[position], ProofInitialization!PartialIntProjection(prior), meaning)
                          => ProofEvaluate(FALSE)[position][prior] =
                               ProofInitialization!SourceIntInitializerOutcome(meaning[ProofSyntaxViews[position].root])
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
                PROOF
                <4>0. ProofInitialization!SourceRestriction(prior, ProofInitialization!PrefixKeys(ProofOrder, position - 1))
                    \\in [ProofInitialization!PrefixKeys(ProofOrder, position - 1) -> ProofValues]
                  BY ONLY <2>0, <3>2, SMT DEF ProofInitialization!SourceRestriction
                <4>1. ProofInitialization!PrefixKeys(ProofOrder, position - 1) \\in SUBSET ProofAllKeys
                  BY ONLY <1>0, <2>0, <3>1, <3>2, SetExtensionality, SMT
                    DEF ProofInitialization!InitializationOrder, ProofInitialization!PrefixKeys
                <4>2. \\E bound \\in SUBSET ProofAllKeys : ProofInitialization!SourceRestriction(prior, ProofInitialization!PrefixKeys(ProofOrder, position - 1)) \\in [bound -> ProofValues]
                  BY ONLY <4>0, <4>1, SMT
                <4>. QED BY ONLY <4>2, SMT DEF ProofInitialization!PartialBindings
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
          <1>6. \\A index \\in 0..ProofCount : source[index] = generated[index]
            BY ONLY <1>0, <1>1, <1>2, ActualInitializerEvaluatorsAreTypedAndAgree,
              ProofInitialSentinels, ProofInitialization!InitializationHistoriesNeedOnlyReachableChildAgreement, SMT
              DEF ProofInitialization!InitialSentinels
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
            PROOF
            <2>1. ProofInitialization!SingleBranchInitialObservationHistory(
                ProofCount, ProofOrder, ProofEvaluate(TRUE), observations)
              BY ONLY <1>7, ActualInitializerEvaluatorsAreTypedAndAgree, SMT
            <2>2. /\\ ProofCount \\in 0..ProofCount
                  /\\ ProofInitialization!InitializerEvaluators(ProofCount, ProofEvaluate(FALSE))
              BY <1>0, ActualInitializerEvaluatorsAreTypedAndAgree, SMT
                DEF ProofInitialization!InitializationOrder
            <2>3. \\A index \\in 0..ProofCount :
                    /\\ ProofInitialization!InitialObservationIsTyped(observations[index])
                    /\\ observations[index].stateCount <= 1 /\\ observations[index].failureCount <= 1
                    /\\ observations[index].stateCount + observations[index].failureCount = 1
              BY ONLY <1>0, <1>7, <2>2, ProofInitialSentinels,
                ProofInitialization!SingleBranchInitializationDerivesItsObservationBounds, SMT
            <2>. QED BY ONLY <2>1, <2>2, <2>3, SMT
          <1>9. source[ProofCount].failures
                  = ProofInitialization!SourceFailureConstraintPrefix(ProofOrder, ProofCount, ProofEvaluate(FALSE))
            BY <1>0, <1>1, ActualInitializerEvaluatorsAreTypedAndAgree,
              ProofInitialization!SourceHistoriesMatchEveryInitialFailurePrefix, SMT
              DEF ProofInitialization!InitializationOrder
          <1>10. \\A position \\in ProofIntPositions : \\A prior \\in source[position - 1].states :
               /\\ \\E meaning : ProofInitialization!Expressions!SourceSyntaxHistory(
                      ProofSyntaxViews[position], ProofInitialization!PartialIntProjection(prior), meaning)
               /\\ \\A meaning : ProofInitialization!Expressions!SourceSyntaxHistory(
                      ProofSyntaxViews[position], ProofInitialization!PartialIntProjection(prior), meaning)
                      => ProofEvaluate(FALSE)[position][prior] =
                           ProofInitialization!SourceIntInitializerOutcome(meaning[ProofSyntaxViews[position].root])
            BY ONLY <1>0, <1>1, <1>4, ActualInitializerExpressionsSupplyTheirParents, SMT
              DEF ProofEvaluate, ProofInitialization!InitializationHistory, ProofInitialization!InitializationResults,
                ProofInitialization!InitializationOrder, ProofIntPositions
          <1>. WITNESS source, generated, observations
          <1>. QED BY ONLY <1>1, <1>2, <1>4, <1>6, <1>7, <1>8, <1>9, <1>10, SMT

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
          /\\ ProofObservedBefore \\in [ProofPrefixKeys(ProofCount) -> ProofValues]
          PROOF
          <1>0c. /\\ ProofCount = 4 /\\ ProofOrder = <<"pc", "first", "second", "last">>
                 /\\ ProofAllKeys = {"pc", "first", "second", "last"}
                 /\\ ProofIntSlots = {"first", "second", "last"}
            BY ONLY ActualLayoutSuppliesInitializationDecoderInputs, SMT
          <1>0d. ProofIntPositions = {2, 3, 4}
            BY ONLY <1>0c, SetExtensionality, SMT DEF ProofIntPositions
          <1>0e. ProofOrdinals["last"] = 3
            BY ONLY ActualLayoutSuppliesInitializationDecoderInputs, SMT DEF ActualLayout
          <1>0. /\\ ProofCount = 4 /\\ ProofIntPositions = {2, 3, 4}
                /\\ ProofOrder = <<"pc", "first", "second", "last">>
                /\\ ExpectedFailure.site = ProofOrdinals[ProofOrder[ProofCount]]
            BY ONLY <1>0c, <1>0d, <1>0e, SMT DEF ExpectedFailure

          <1>0a. ProofIntSlots = {"first", "second", "last"}
            BY ONLY ActualLayoutSuppliesInitializationDecoderInputs, SMT
          <1>1. /\\ DOMAIN ProofObservedBefore = {"pc", "first", "second"}
                /\\ ProofObservedBefore["pc"] = "stay" /\\ ProofObservedBefore["first"] = 1
                /\\ ProofObservedBefore["second"] = 3
                /\\ ExpectedOperand0 = 3 /\\ ExpectedOperand1 = ProofIntMax
                /\\ ProofObservedBefore \\in [ProofPrefixKeys(ProofCount) -> ProofValues]
            PROOF
            <2>. DEFINE observed == [key \\in {"pc", "first", "second"} |->
                CASE key = "pc" -> "stay" [] key = "first" -> 1 [] OTHER -> 3]
            <2>0a. "stay" \\in STRING
              BY ONLY SMT
            <2>0b. ProofPrefixKeys(ProofCount) = {"pc", "first", "second"}
              BY ONLY <1>0, SetExtensionality, SMT DEF ProofPrefixKeys
            <2>0c. observed \\in [{"pc", "first", "second"} -> ProofValues]
              BY ONLY <2>0a, SMT DEF observed, ProofValues
            <2>0. /\\ observed \\in [ProofPrefixKeys(ProofCount) -> ProofValues]
                  /\\ ExpectedOperand0 = 3 /\\ ExpectedOperand1 = ProofIntMax
              BY ONLY <2>0b, <2>0c, SMT DEF ExpectedOperand0, ExpectedOperand1, ProofIntMax
            <2>1a0. /\\ \\A row \\in DOMAIN ActualLayout :
                           ProofNames[ActualLayout[row].declaration] = ActualLayout[row].name
                    /\\ \\A row \\in DOMAIN ActualLayout :
                           ProofOrdinalKey(ActualLayout[row].ordinal) = ActualLayout[row].declaration
              BY ONLY ActualLayoutSuppliesInitializationDecoderInputs, SMT
            <2>1a. /\\ ProofNames["first"] = "first" /\\ ProofNames["pc"] = "pc"
                   /\\ ProofNames["second"] = "second"
                   /\\ ProofOrdinalKey(0) = "pc" /\\ ProofOrdinalKey(1) = "first" /\\ ProofOrdinalKey(2) = "second"
              BY ONLY <2>1a0, SMT DEF ActualLayout
            <2>1b. ProofPrefixOrder(ProofCount) = <<"first", "pc", "second">>
              BY ONLY <1>0, <2>1a, NativePrefixOrdersMatchResolvedIR, SMT DEF ProofPrefixOrder, ActualPrefixOrders
            <2>1. ExpectedBefore = ProofInitialization!RenderedInitialPrefixEntries(
                ProofCount - 1, ProofPrefixOrder(ProofCount), ProofNames, observed)
              BY ONLY <1>0, <2>1a, <2>1b, SMT
                DEF ExpectedBefore, observed, ProofInitialization!RenderedInitialPrefixEntries
            <2>2. ProofObservedBefore = observed
              BY ONLY <1>0, <2>0, <2>1, ActualPrefixRecordsInvokeInitializationDecoder, SMT
                DEF ProofObservedBefore
            <2>. QED BY ONLY <2>0, <2>2, SMT DEF observed

          <1>1a. "stay" \\in STRING
            BY ONLY SMT
          <1>1c0. /\\ DOMAIN SourceInitializers = 1..3
                  /\\ \\A row, other \\in DOMAIN SourceInitializers :
                         SourceInitializers[row][1] = SourceInitializers[other][1] => row = other
            BY ONLY SMT DEF SourceInitializers
          <1>1c1. \\A row \\in DOMAIN SourceInitializers :
              (CHOOSE selected \\in DOMAIN SourceInitializers :
                 SourceInitializers[selected][1] = SourceInitializers[row][1]) = row
            <2>. SUFFICES ASSUME NEW row \\in DOMAIN SourceInitializers
                         PROVE (CHOOSE selected \\in DOMAIN SourceInitializers :
                                  SourceInitializers[selected][1] = SourceInitializers[row][1]) = row
              BY SMT
            <2>0. row \\in DOMAIN SourceInitializers BY SMT
            <2>. QED BY ONLY <1>1c0, <2>0, SMT
          <1>1c2. /\\ SourceInitializers[1][1] = ProofOrder[2]
                  /\\ SourceInitializers[2][1] = ProofOrder[3]
                  /\\ SourceInitializers[3][1] = ProofOrder[4]
            BY ONLY <1>0, SMT DEF SourceInitializers
          <1>1c. /\\ ProofSourceRow(2) = 1 /\\ ProofSourceRow(3) = 2 /\\ ProofSourceRow(4) = 3
            BY ONLY <1>1c0, <1>1c1, <1>1c2, SMT DEF ProofSourceRow
          <1>1b. /\\ ProofPlans[2] = SourceInitializers[1][2]
                 /\\ ProofPlans[3] = SourceInitializers[2][2]
                 /\\ ProofPlans[4] = SourceInitializers[3][2]
            BY ONLY <1>0, <1>1c, SMT DEF ProofPlans
          <1>1d. /\\ ProofPlans[2].count = 1
                 /\\ ProofPlans[3].count = 3 /\\ ProofPlans[4].count = 3
            PROOF
            <2>1. SourceInitializers[1][2].count = 1
              BY ONLY SMT DEF SourceInitializers
            <2>2. SourceInitializers[2][2].count = 3
              BY ONLY SMT DEF SourceInitializers
            <2>3. SourceInitializers[3][2].count = 3
              BY ONLY SMT DEF SourceInitializers
            <2>. QED BY ONLY <1>1b, <2>1, <2>2, <2>3, SMT
          <1>2. \\A position \\in 1..ProofCount :
                  /\\ ProofObservedPrior(position) \\in ProofInitialization!PartialBindings
                  /\\ DOMAIN ProofObservedPrior(position) = ProofPrefixKeys(position)
            PROOF
            <2>. SUFFICES ASSUME NEW position \\in 1..ProofCount
                         PROVE /\\ ProofObservedPrior(position) \\in ProofInitialization!PartialBindings
                               /\\ DOMAIN ProofObservedPrior(position) = ProofPrefixKeys(position)
              BY SMT
            <2>0. /\\ ProofPrefixKeys(position) \\subseteq ProofAllKeys
                  /\\ ProofPrefixKeys(position) \\subseteq DOMAIN ProofObservedBefore
              BY <1>0, <1>0c, <1>1, SetExtensionality, SMT DEF ProofPrefixKeys
            <2>1. ProofObservedBefore \\in [DOMAIN ProofObservedBefore -> ProofValues]
              BY ONLY <1>1, SMT

            <2>2. ProofObservedPrior(position) \\in [ProofPrefixKeys(position) -> ProofValues]
              BY ONLY <2>0, <2>1, SMT DEF ProofObservedPrior, ProofInitialization!SourceRestriction
            <2>2a. ProofPrefixKeys(position) \\in SUBSET ProofAllKeys
              BY ONLY <2>0, SMT
            <2>3. \\E bound \\in SUBSET ProofAllKeys : ProofObservedPrior(position) \\in [bound -> ProofValues]
              BY ONLY <2>2, <2>2a, SMT
            <2>4. ProofObservedPrior(position) \\in ProofInitialization!PartialBindings
              BY ONLY <2>3, SMT DEF ProofInitialization!PartialBindings
            <2>. QED BY ONLY <2>2, <2>4, SMT
          <1>3. \\A position \\in ProofIntPositions :
                  SourcePlanHistory(ProofPlans[position], ProofReadState(position, ProofObservedPrior(position)),
                      ProofSourceExpressions[position][ProofObservedPrior(position)])
            BY <1>2, ActualInitializerExpressionsSupplyTheirParents, SMT
              DEF ProofIntPositions
          <1>3b. \\A position \\in ProofIntPositions : \\A index \\in 1..ProofPlans[position].count :
              ProofSourceExpressions[position][ProofObservedPrior(position)][index]
                = ProofInitialization!Expressions!SourceNode(index, ProofPlans[position].kinds,
                    ProofPlans[position].literals, ProofPlans[position].reads, ProofPlans[position].left,
                    ProofPlans[position].right, ProofReadState(position, ProofObservedPrior(position)),
                    ProofSourceExpressions[position][ProofObservedPrior(position)])
            BY ONLY <1>3, SMT
              DEF SourcePlanHistory, ProofInitialization!Expressions!SourceExpressionHistory
          <1>3c. \\A position \\in ProofIntPositions :
              ProofEvaluate(FALSE)[position][ProofObservedPrior(position)]
                = ProofInitialization!SourceIntInitializerOutcome(
                    ProofSourceExpressions[position][ProofObservedPrior(position)][ProofPlans[position].count])
            BY ONLY <1>0, <1>2, SMT DEF ProofEvaluate
          <1>4a. ProofEvaluate(FALSE)[1][ProofObservedPrior(1)]
              = ProofInitialization!SourceFixed(SourceInitialControl)
            BY ONLY <1>0, <1>2, SMT DEF ProofEvaluate
          <1>4b. SourceInitialControl = ProofObservedBefore[ProofOrder[1]]
            BY ONLY <1>0, <1>1, SMT DEF SourceInitialControl
          <1>4. ProofEvaluate(FALSE)[1][ProofObservedPrior(1)]
              = ProofInitialization!SourceFixed(ProofObservedBefore[ProofOrder[1]])
            BY ONLY <1>4a, <1>4b, SMT
          <1>5. \\A position \\in {2, 3} :
              ProofEvaluate(FALSE)[position][ProofObservedPrior(position)]
                = ProofInitialization!SourceFixed(ProofObservedBefore[ProofOrder[position]])
            PROOF
            <2>. SUFFICES ASSUME NEW position \\in {2, 3}
                         PROVE ProofEvaluate(FALSE)[position][ProofObservedPrior(position)]
                                       = ProofInitialization!SourceFixed(ProofObservedBefore[ProofOrder[position]])
              BY SMT
            <2>1. CASE position = 2
              <3>1. ProofSourceExpressions[2][ProofObservedPrior(2)][1] = ProofInitialization!Expressions!Success(1)
                BY ONLY <1>0, <1>1b, <1>1d, <1>3b, SMT
                  DEF SourceInitializers, ProofInitialization!Expressions!SourceNode
              <3>. QED BY ONLY <2>1, <3>1, <1>0, <1>1, <1>1d, <1>3c, SMT
                DEF ProofInitialization!SourceIntInitializerOutcome, ProofInitialization!Expressions!Success
            <2>2. CASE position = 3
              <3>0. ProofReadState(3, ProofObservedPrior(3))["first"] = 1
                BY ONLY <1>0, <1>0a, <1>1, ProofIntegerBounds, SetExtensionality, SMT
                  DEF ProofReadState, ProofObservedPrior, ProofPrefixIntNames, ProofPrefixKeys,
                    ProofInitialization!SourceRestriction
              <3>1. ProofSourceExpressions[3][ProofObservedPrior(3)][1] = ProofInitialization!Expressions!Success(1)
                BY ONLY <1>0, <1>1b, <1>1d, <1>3b, <3>0, SMT
                  DEF SourceInitializers, ProofInitialization!Expressions!SourceNode
              <3>2. ProofSourceExpressions[3][ProofObservedPrior(3)][2] = ProofInitialization!Expressions!Success(2)
                BY ONLY <1>0, <1>1b, <1>1d, <1>3b, SMT
                  DEF SourceInitializers, ProofInitialization!Expressions!SourceNode
              <3>3. ProofSourceExpressions[3][ProofObservedPrior(3)][3] = ProofInitialization!Expressions!Success(3)
                BY ONLY <1>0, <1>1b, <1>1d, <1>3b, <3>1, <3>2, ProofIntegerBounds, SMT
                  DEF SourceInitializers, ProofInitialization!Expressions!SourceNode,
                    ProofInitialization!Expressions!SourceCombine, ProofInitialization!Expressions!SourceAdd,
                    ProofInitialization!Expressions!Success, ProofInitialization!Expressions!InRange
              <3>. QED BY ONLY <2>2, <3>3, <1>0, <1>1, <1>1d, <1>3c, SMT
                DEF ProofInitialization!SourceIntInitializerOutcome, ProofInitialization!Expressions!Success
            <2>. QED BY ONLY <2>1, <2>2, SMT
          <1>6. ProofEvaluate(FALSE)[ProofCount][ProofObservedPrior(ProofCount)]
              = ProofInitialization!SourceFailed(<<"integerOverflow", "addition", <<ExpectedOperand0, ExpectedOperand1>>>>)
            PROOF
            <2>0. ProofReadState(4, ProofObservedPrior(4))["second"] = 3
              BY ONLY <1>0, <1>0a, <1>1, ProofIntegerBounds, SetExtensionality, SMT
                DEF ProofReadState, ProofObservedPrior, ProofPrefixIntNames, ProofPrefixKeys,
                  ProofInitialization!SourceRestriction
            <2>1. ProofSourceExpressions[4][ProofObservedPrior(4)][1] = ProofInitialization!Expressions!Success(3)
              BY ONLY <1>0, <1>1b, <1>1d, <1>3b, <2>0, SMT
                DEF SourceInitializers, ProofInitialization!Expressions!SourceNode
            <2>2. ProofSourceExpressions[4][ProofObservedPrior(4)][2] = ProofInitialization!Expressions!Success(ProofIntMax)
              BY ONLY <1>0, <1>1b, <1>1d, <1>3b, SMT
                DEF SourceInitializers, ProofIntMax, ProofInitialization!Expressions!SourceNode
            <2>3. ProofSourceExpressions[4][ProofObservedPrior(4)][3] = ProofInitialization!Expressions!SourceOverflow(3, ProofIntMax)
              BY ONLY <1>0, <1>1b, <1>1d, <1>3b, <2>1, <2>2, ProofIntegerBounds, SMT
                DEF SourceInitializers, ProofInitialization!Expressions!SourceNode,
                  ProofInitialization!Expressions!SourceCombine, ProofInitialization!Expressions!SourceAdd,
                  ProofInitialization!Expressions!Success, ProofInitialization!Expressions!InRange
            <2>. QED BY ONLY <1>0, <1>1, <1>1d, <1>3c, <2>3, SMT
              DEF ProofInitialization!SourceIntInitializerOutcome,
                ProofInitialization!Expressions!SourceOverflow
          <1>7. /\\ ProofObservedBefore = ProofObservedPrior(ProofCount)
                /\\ ProofObservedBefore \\in [ProofPrefixKeys(ProofCount) -> ProofValues]
            PROOF
            <2>1. DOMAIN ProofObservedBefore = ProofPrefixKeys(ProofCount)
              BY ONLY <1>1, SMT
            <2>2. [name \\in ProofPrefixKeys(ProofCount) |-> ProofObservedBefore[name]] = ProofObservedBefore
              BY ONLY <1>1, <2>1, SMT
            <2>. QED BY ONLY <1>1, <2>2, SMT
              DEF ProofObservedPrior, ProofInitialization!SourceRestriction
          <1>8. ProofInitialization!DecodedRenderedInitializerSite(ExpectedFailure.site, ProofOrdinals) = ProofOrder[ProofCount]
            BY ONLY <1>0, <1>0c, <1>7, ActualLayoutSuppliesInitializationDecoderInputs,
              ActualPrefixRecordsInvokeInitializationDecoder, SMT
          <1>9. ProofObservedFailures = {[before |-> ProofObservedBefore, site |-> ProofOrder[ProofCount],
                                        payload |-> <<"integerOverflow", "addition", <<ExpectedOperand0, ExpectedOperand1>>>>]}
            BY <1>8, SMT DEF ProofObservedFailures, ExpectedFailures, ExpectedFailure, ProofObservedBefore,
              ProofInitialization!DecodedNamedRenderedAdditionEvents
          <1>. QED BY <1>0, <1>2, <1>4, <1>5, <1>6, <1>7, <1>9, SMT

        THEOREM ActualNativePrefixConstructsTheGeneratedInitializationHistory ==
          ProofInitialization!InitializationHistory(TRUE, ProofCount, ProofOrder, ProofEvaluate(TRUE), ProofObservedHistory)
          PROOF
          <1>. DEFINE failure == <<"integerOverflow", "addition", <<ExpectedOperand0, ExpectedOperand1>>>>
                      constructed == [length \\in 0..ProofCount |->
                        IF length < ProofCount
                        THEN [states |-> {ProofInitialization!SourceRestriction(ProofObservedBefore,
                                           ProofInitialization!PrefixKeys(ProofOrder, length))},
                              failures |-> {}]
                        ELSE [states |-> {},
                              failures |-> {[before |-> ProofObservedBefore,
                                             site |-> ProofOrder[ProofCount], payload |-> failure]}]]
          <1>. HIDE DEF failure, constructed
          <1>0. /\\ ProofCount \\in Nat /\\ ProofCount \\in 1..ProofCount
                /\\ ProofInitialization!InitializationOrder(ProofCount, ProofOrder)
                /\\ ProofObservedBefore \\in [ProofInitialization!PrefixKeys(ProofOrder, ProofCount - 1) -> ProofValues]
            BY ONLY ActualLayoutSuppliesInitializationDecoderInputs,
              ActualNativePrefixSuppliesTheSourceInitializerOutcomes, SetExtensionality, SMT
              DEF ProofPrefixKeys, ProofInitialization!PrefixKeys
          <1>1a. \\A position \\in 1..(ProofCount - 1) :
                  ProofEvaluate(TRUE)[position][ProofInitialization!SourceRestriction(
                      ProofObservedBefore, ProofInitialization!PrefixKeys(ProofOrder, position - 1))]
                    = ProofInitialization!SourceFixed(ProofObservedBefore[ProofOrder[position]])
            BY ONLY <1>0, ActualNativePrefixSuppliesTheSourceInitializerOutcomes,
              ActualInitializerEvaluatorsAreTypedAndAgree, SMT
              DEF ProofObservedPrior, ProofPrefixKeys, ProofInitialization!PrefixKeys
          <1>1b. ProofEvaluate(TRUE)[ProofCount][ProofObservedBefore]
                    = ProofInitialization!SourceFailed(failure)
            BY ONLY <1>0, ActualNativePrefixSuppliesTheSourceInitializerOutcomes,
              ActualInitializerEvaluatorsAreTypedAndAgree, SMT DEF failure
          <1>2. failure \\in ProofFailureValues
            BY ONLY ProofIntegerBounds, SMT
              DEF failure, ExpectedOperand0, ExpectedOperand1, ProofIntMax, ProofFailureValues
          <1>3. ProofInitialization!InitializationHistory(TRUE, ProofCount, ProofOrder,
                    ProofEvaluate(TRUE), constructed)
            BY ONLY <1>0, <1>1a, <1>1b, <1>2, ProofInitialSentinels,
              ProofInitialization!ObservedFailurePrefixConstructsTheGeneratedInitializationHistory, SMT
              DEF constructed, ProofInitialization!InitialSentinels
          <1>4a. \\A length \\in 0..ProofCount : constructed[length] = ProofObservedHistory[length]
            PROOF
            <2>. SUFFICES ASSUME NEW length \\in 0..ProofCount
                         PROVE constructed[length] = ProofObservedHistory[length]
              BY SMT
            <2>0. /\\ length \\in Int /\\ 0 <= length /\\ length <= ProofCount
                  /\\ ProofCount \\in Nat
              BY ONLY <1>0, SMT
            <2>1. CASE length < ProofCount
              <3>0. ProofPrefixKeys(length + 1) = ProofInitialization!PrefixKeys(ProofOrder, length)
                BY ONLY <2>0, SMT DEF ProofPrefixKeys, ProofInitialization!PrefixKeys
              <3>. QED BY ONLY <2>0, <2>1, <3>0, SMT
                DEF constructed, ProofObservedHistory, ProofObservedPrior
            <2>2. CASE length = ProofCount
              <3>0. ProofObservedFailures = {[before |-> ProofObservedBefore, site |-> ProofOrder[ProofCount],
                                            payload |-> failure]}
                BY ONLY ActualNativePrefixSuppliesTheSourceInitializerOutcomes, SMT DEF failure
              <3>1. constructed[length] = [states |-> {},
                  failures |-> {[before |-> ProofObservedBefore, site |-> ProofOrder[ProofCount], payload |-> failure]}]
                BY ONLY <2>0, <2>2, SMT DEF constructed
              <3>2. ProofObservedHistory[length] = ProofObservedResult
                BY ONLY <2>0, <2>2, SMT DEF ProofObservedHistory
              <3>3. ProofObservedResult = [states |-> {},
                  failures |-> {[before |-> ProofObservedBefore, site |-> ProofOrder[ProofCount], payload |-> failure]}]
                BY ONLY <3>0, SMT DEF ProofObservedResult
              <3>. QED BY ONLY <3>1, <3>2, <3>3, SMT
            <2>. QED BY ONLY <2>0, <2>1, <2>2, SMT
          <1>4. constructed = ProofObservedHistory
            BY ONLY <1>4a, SMT DEF constructed, ProofObservedHistory
          <1>. QED BY ONLY <1>3, <1>4, SMT

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
            /\\ \\A position \\in ProofIntPositions : \\A prior \\in source[position - 1].states :
                   /\\ \\E meaning : ProofInitialization!Expressions!SourceSyntaxHistory(
                          ProofSyntaxViews[position], ProofInitialization!PartialIntProjection(prior), meaning)
                   /\\ \\A meaning : ProofInitialization!Expressions!SourceSyntaxHistory(
                          ProofSyntaxViews[position], ProofInitialization!PartialIntProjection(prior), meaning)
                          => ProofEvaluate(FALSE)[position][prior] =
                               ProofInitialization!SourceIntInitializerOutcome(meaning[ProofSyntaxViews[position].root])
          PROOF
          <1>. DEFINE CompleteOutputRelation(source, generated, observations) ==
                /\\ ProofInitialization!InitializationHistory(FALSE, ProofCount, ProofOrder, ProofEvaluate(FALSE), source)
                /\\ ProofInitialization!InitializationHistory(TRUE, ProofCount, ProofOrder, ProofEvaluate(TRUE), generated)
                /\\ source[ProofCount] = generated[ProofCount]
                /\\ source[ProofCount].states = {}
                /\\ source[ProofCount].failures = ProofInitialization!DecodedNamedRenderedAdditionEvents(
                       __SwiftTLAInitialFailureEvents, ProofNames, ProofOrdinals)
                /\\ ProofInitialization!SingleBranchInitialObservationHistory(ProofCount, ProofOrder, ProofEvaluate(FALSE), observations)
                /\\ ProofInitialization!SingleBranchInitialObservationHistory(ProofCount, ProofOrder, ProofEvaluate(TRUE), observations)
                /\\ ProofInitialization!InitialSetProjection(observations[ProofCount]) = source[ProofCount]
                /\\ observations[ProofCount].stateCount = 0 /\\ observations[ProofCount].failureCount = 1
                /\\ {observations[ProofCount].failureHistory[1]} = ProofObservedFailures
                /\\ ~Init
                /\\ \\A position \\in ProofIntPositions : \\A prior \\in source[position - 1].states :
                       /\\ \\E meaning : ProofInitialization!Expressions!SourceSyntaxHistory(
                              ProofSyntaxViews[position], ProofInitialization!PartialIntProjection(prior), meaning)
                       /\\ \\A meaning : ProofInitialization!Expressions!SourceSyntaxHistory(
                              ProofSyntaxViews[position], ProofInitialization!PartialIntProjection(prior), meaning)
                              => ProofEvaluate(FALSE)[position][prior] =
                                   ProofInitialization!SourceIntInitializerOutcome(meaning[ProofSyntaxViews[position].root])
          <1>. HIDE DEF CompleteOutputRelation
          <1>0g. SUFFICES \\E source, generated, observations : CompleteOutputRelation(source, generated, observations)
            BY ONLY <1>0g, SMT DEF CompleteOutputRelation
          <1>0. ProofInitialization!InitializationOrder(ProofCount, ProofOrder)
            BY ActualLayoutSuppliesInitializationDecoderInputs, SMT
          <1>5. ProofCount \\in 0..ProofCount
            BY <1>0, SMT DEF ProofInitialization!InitializationOrder
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
                  /\\ \\A position \\in ProofIntPositions : \\A prior \\in source[position - 1].states :
                         /\\ \\E meaning : ProofInitialization!Expressions!SourceSyntaxHistory(
                                ProofSyntaxViews[position], ProofInitialization!PartialIntProjection(prior), meaning)
                         /\\ \\A meaning : ProofInitialization!Expressions!SourceSyntaxHistory(
                                ProofSyntaxViews[position], ProofInitialization!PartialIntProjection(prior), meaning)
                                => ProofEvaluate(FALSE)[position][prior] =
                                     ProofInitialization!SourceIntInitializerOutcome(meaning[ProofSyntaxViews[position].root])
            BY ONLY <1>5, ActualPlansInvokeCompleteInitializationAndObservationParents, SMT
          <1>2. \\A index \\in 0..ProofCount : source[index] = ProofObservedHistory[index]
            PROOF
            <2>1. \\A index \\in 0..ProofCount : generated[index] = ProofObservedHistory[index]
              BY ONLY <1>0, <1>1, ProofInitialSentinels, ActualNativePrefixConstructsTheGeneratedInitializationHistory,
                ProofInitialization!InitializationHistoryIsUnique, SMT
            <2>. QED BY ONLY <1>1, <2>1, SMT
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
          <1>. WITNESS source, generated, observations
          <1>. QED BY ONLY <1>1, <1>3, <1>4, <1>5, CompleteFailureEvents, InitialFailurePrecedesGraph, SMT
            DEF CompleteOutputRelation, ProofObservedFailures
        ====
        """
    }

    static func binaryLiteral(_ value: Int) -> String {
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
