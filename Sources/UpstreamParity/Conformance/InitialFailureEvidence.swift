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
    package let checkModule: String
    package let checkModuleSHA256: String
    package let checkConfigurationSHA256: String
    package let proofSHA256: String
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

    package static func prepare(sourceSHA: String, nativeSource: String, to directory: URL) throws -> InitialFailureEvidenceReport {
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
        guard let sourceWitness = source.orderedIntSourceComponents,
              let sourceControl = sourceWitness.compactMap({ component -> String? in
                  guard case .step(let label, _) = component else { return nil }
                  return label
              }).first else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let sourceInputs = try sourceInitializerInputs(sourceWitness)
        let sourceInitializers = sourceInputs.plans
        let sourceInitialControl = TLAValue.string(sourceControl).description
        let loweredInitializers = try initializerPlans(layout: compilation.layout,
            initializations: compilation.semantics.behavior.initializations, requireTypes: false)
        let resolvedInitializers = try initializerPlans(layout: resolvedProgram.layout,
            initializations: resolvedProgram.behavior.initializations, requireTypes: true)
        let nativeInitializers = try nativeInitializerPlans(nativeSource, program: resolvedProgram)
        let recordInputs = try initialRecordInputs(resolvedProgram, before: failures[0].before)
        guard let check = try rendered.initialEvaluationFailureBundle(capturingRecord: true) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        let module = rendered.tlaBundle.root
        let proof = try proofSource(module: module.name, tla: module.tla,
            site: site, operands: operands, before: failures[0].before,
            sourceInitializers: sourceInitializers, sourceCompilerInputs: sourceInputs.compilerInputs,
            sourceCompilerInputDerivations: sourceInputs.compilerDerivations, sourceCompilerInputSizes: sourceInputs.compilerSizes,
            sourceCompilerInvocationWitnesses: sourceInputs.compilerWitnesses,
            sourceSyntaxViews: sourceInputs.views,
            sourceSyntaxOrigins: sourceInputs.origins, sourceSyntaxIndices: sourceInputs.indices,
            sourcePlanEmissions: sourceInputs.emissions, sourceCertificateProofs: sourceInputs.proofs,
            sourceInitializerCount: sourceInputs.count,
            sourceInitialControl: sourceInitialControl,
            loweredInitializers: loweredInitializers,
            resolvedInitializers: resolvedInitializers, nativeInitializers: nativeInitializers.plans,
            nativePrefixOrders: nativeInitializers.prefixes, nativeInitializationOrder: nativeInitializers.order,
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
        try Data(nativeSource.utf8).write(to: directory.appendingPathComponent("native-initial-source.swift"), options: .atomic)
        let proofBytes = Data(proof.utf8)
        try proofBytes.write(to: proofURL, options: .atomic)
        let report = InitialFailureEvidenceReport(
            schema: "swifttla.initial-failure-proof-v14", sourceSHA: sourceSHA,
            module: module.name, moduleSHA256: SHA256.hex(Data(module.tla.utf8)),
            checkModule: check.root.name,
            checkModuleSHA256: SHA256.hex(Data(check.root.tla.utf8)),
            checkConfigurationSHA256: SHA256.hex(Data(check.cfg.utf8)),
            proofSHA256: SHA256.hex(proofBytes), nativeSHA256: SHA256.hex(nativeBytes),
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

    // Retain the existing macro witness, independently of the built Algorithm model.
    private static func sourceInitializerInputs(_ components: [_OrderedIntSourceComponent]) throws
        -> (compilerInputs: String, compilerDerivations: String, compilerSizes: String, compilerWitnesses: String,
            plans: String, views: String, origins: String, indices: String, emissions: String, proofs: String, count: Int) {
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
            let input = try sourceCompilerInput(expression, path: "SourceCompilerInputs[\(offset + 1)].root")
            let compilerInput = "[root |-> \(input.term), reads |-> \(compilerReads)]"
            let compilerSizes = "<<\(input.sizes.map(String.init).joined(separator: ", "))>>"
            let (traversalCount, traversalCountOverflowed) = input.count.addingReportingOverflow(input.additions)
            guard !traversalCountOverflowed else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
            let compilerWitness = sourceCompilerInvocationWitness(row: offset + 1,
                allocationCount: input.count, traversalCount: traversalCount)
            guard let certificate = StraightLineAssignmentCheck.orderedIntCertificate(expression, reads: reads) else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            let nodes = certificate.nodes
            let syntax = try sourceSyntaxView(certificate)
            let emission = "[count |-> \(nodes.count), height |-> 1, indices |-> <<\(nodes.count)>>, "
                + "origins |-> SourceSyntaxOrigins[\(offset + 1)], nodes |-> \(syntax.nodes)]"
            return (
                compilerInput: compilerInput, compilerDerivation: input.derivation,
                compilerSizes: compilerSizes, compilerWitness: compilerWitness,
                plan: "<<\(TLAValue.string(state.root)), \(try initializerPlan(nodes, root: state.root))>>",
                view: "<<\(TLAValue.string(state.root)), \(syntax.view)>>",
                origins: syntax.origins, indices: syntax.indices,
                emission: emission,
                proof: try initializerCertificateProof(row: offset + 1, view: syntax.view, kinds: syntax.kinds,
                    emission: emission, origins: syntax.origins, indices: syntax.indices,
                    scalars: input.scalars, reads: compilerReads.description, term: input.term,
                    sourceDerivation: input.derivation, sourceSizes: compilerSizes,
                    sourceExpression: expression, sourceCount: input.count,
                    source: certificate.source, traversalCount: traversalCount))
        }
        guard !rows.isEmpty else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        return ("<<\(rows.map(\.compilerInput).joined(separator: ", "))>>",
                "<<\(rows.map(\.compilerDerivation).joined(separator: ", "))>>",
                "<<\(rows.map(\.compilerSizes).joined(separator: ", "))>>",
                rows.map(\.compilerWitness).joined(separator: "\n\n"),
                "<<\(rows.map(\.plan).joined(separator: ", "))>>",
                "<<\(rows.map(\.view).joined(separator: ", "))>>",
                "<<\(rows.map(\.origins).joined(separator: ", "))>>",
                "<<\(rows.map(\.indices).joined(separator: ", "))>>",
                "<<\(rows.map(\.emission).joined(separator: ", "))>>", rows.map(\.proof).joined(separator: "\n"), rows.count)
    }

    private static func sourceCompilerInput(_ expression: StateExpr, path: String) throws
        -> (term: String, derivation: String, sizes: [Int], count: Int, additions: Int, scalars: [String]) {
        // shortcut: Scalar spellings are checked per packet; prove the general encoding before widening proof coverage.
        let expressions = "ProofInitialization!Expressions!"
        switch expression {
        case .value(.int(let value)):
            let term = "<<\"literal\", \(binaryLiteral(value))>>"
            let scalar = value == Int.max ? "ProofIntMax" : value == Int.min ? "ProofIntMin" : String(value)
            return (term, "\(expressions)AllocationLeafDerivation(\(term))", [1], 1, 0,
                    ["\(path)[2] = \(scalar)"])
        case .variable(let name):
            let term = "<<\"read\", \(TLAValue.string(name))>>"
            return (term, "\(expressions)AllocationLeafDerivation(\(term))", [1], 1, 0,
                    ["\(path)[2] = \(String(reflecting: name))"])
        case .add(let left, let right):
            let first = try sourceCompilerInput(left, path: "\(path)[2]")
            let second = try sourceCompilerInput(right, path: "\(path)[3]")
            let count = 1 + first.count + second.count
            return (
                "<<\"add\", \(first.term), \(second.term)>>",
                "\(expressions)AllocationAddDerivation(\(first.derivation), \(second.derivation))",
                first.sizes + second.sizes + [count], count, 1 + first.additions + second.additions,
                first.scalars + second.scalars)
        default: throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
    }

    private static func sourceCompilerInvocationWitness(
        row: Int, allocationCount: Int, traversalCount: Int
    ) -> String {
        let expressions = "ProofInitialization!Expressions!"
        let allocationBindings = (0...allocationCount).map { step in
            step == 0
                ? "allocation0 == \(expressions)InitialCompilerAllocation(SourceCompilerInputs[\(row)].root, weight)"
                : "allocation\(step) == \(expressions)ReviewedSwiftAllocationIteration(syntax, weight, allocation\(step - 1))"
        }
        let traversalBindings = (0...traversalCount).map { step in
            step == 0
                ? "traversal0 == \(expressions)InitialCompilerTraversal(view)"
                : "traversal\(step) == \(expressions)CompilerTraversalNext(view, traversal\(step - 1))"
        }
        let allocationCases = (0...allocationCount).map { "step = \($0) -> allocation\($0)" }
            .joined(separator: " [] ")
        let traversalCases = (0...traversalCount).map { "step = \($0) -> traversal\($0)" }
            .joined(separator: " [] ")
        let bindings = allocationBindings + [
            "allocated == allocation\(allocationCount)",
            "view == \(expressions)AllocatedSourceView(allocated)",
        ] + traversalBindings + [
            "allocationHistory == [step \\in 0..\(allocationCount) |-> CASE \(allocationCases)]",
            "traversalHistory == [step \\in 0..\(traversalCount) |-> CASE \(traversalCases)]",
            "execution == [step \\in 0..\(traversalCount) |-> \(expressions)SwiftCompilerStorage(view, allocated.count, traversalHistory[step])]",
        ]
        return """
        SourceCompilerInvocationWitness\(row)(syntax, weight) ==
          LET \(bindings.joined(separator: "\n      "))
          IN [allocationSteps |-> \(allocationCount), allocationHistory |-> allocationHistory,
              traversalSteps |-> \(traversalCount), traversalHistory |-> traversalHistory, execution |-> execution,
              result |-> \(expressions)ReviewedSwiftCertificateReturn(
                \(expressions)SwiftSourceArray(view, allocated.count), execution[\(traversalCount)]).certificate]
        """
    }

    private static func sourceSyntaxView(_ certificate: StraightLineAssignmentCheck.OrderedIntCertificate) throws
        -> (view: String, kinds: String, origins: String, indices: String, nodes: String) {
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
        let kindTuple = tuple(kinds)
        let view = "[root |-> 1, kinds |-> \(kindTuple), literals |-> \(tuple(literals)), "
            + "reads |-> \(tuple(names)), left |-> \(tuple(left.map(String.init))), right |-> \(tuple(right.map(String.init)))]"
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
        return (view, kindTuple, tuple(origins.map(String.init)), tuple(indices.map(String.init)), tuple(records))
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
        -> (plans: String, prefixes: String, order: String) {
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
        let order = decodedPlans.sites.map { String($0.ordinal) }.joined(separator: ", ")
        return ("<<\(rows.joined(separator: ", "))>>", "<<\(prefixes.joined(separator: ", "))>>", "<<\(order)>>")
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

    private static func initialRecordInputs(_ program: CompiledProgram, before: [NativeInitialBindingOutput]) throws
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
        let nativeSeeds = try ordered.compactMap { variable -> String? in
            guard variable.declaration.origin == .programCounter else { return nil }
            let matching = before.filter { $0.name.utf8.elementsEqual(variable.formalName.utf8) }
            guard matching.count == 1, case .string = matching[0].value else {
                throw InitialFailureEvidenceError.unsupportedNativeOutcome
            }
            return "[ordinal |-> \(variable.id.ordinal), value |-> \(matching[0].value)]"
        }
        let types = try variables.map { variable in
            let expected: CompiledValueType = variable.declaration.origin == .source ? .int : .controlLocation
            guard let type = program.variableTypes[variable.id], type == expected else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            return "[ordinal |-> \(variable.id.ordinal), type |-> \(TLAValue.string(type.swiftType))]"
        }
        return (tuple(layout), tuple(ordered.map { String($0.id.ordinal) }), tuple(prefixes),
                tuple(seeds), tuple(nativeSeeds), tuple(types))
    }

    private static func initializerCertificateProof(row: Int, view: String, kinds: String, emission: String,
                                                    origins: String, indices: String, scalars: [String], reads: String,
                                                    term: String, sourceDerivation: String, sourceSizes: String,
                                                    sourceExpression: StateExpr, sourceCount: Int,
                                                    source: [StraightLineAssignmentCheck.OrderedIntNode], traversalCount: Int) throws -> String {
        let allocationProgress = (1...sourceCount).map { step in
            let previous = step - 1
            let priorInvariant = step == 1 ? "<3>initialInvariant" : "<3>advance\(previous)"
            let priorFuel = step == 1 ? "<3>initialFuel" : "<3>fuel\(previous)"
            return """
                  <3>types\(step). /\\ history[\(previous)].position \\in Nat /\\ history[\(previous)].count \\in Nat
                                /\\ history[\(previous)].position <= history[\(previous)].count
                    BY ONLY \(priorInvariant) DEF ProofInitialization!Expressions!CompilerAllocationInvariant
                  <3>fits\(step). history[\(previous)].position = history[\(previous)].count <=>
                                   weight[input.root] - history[\(previous)].position = 0
                    BY ONLY <2>canonical, \(priorInvariant), ProofInitialSentinels, ProofIntegerBounds,
                      ProofInitialization!Expressions!CompilerAllocationFitsItsFiniteInputSize
                      DEF syntax
                  <3>guard\(step). history[\(previous)].position < history[\(previous)].count
                    BY ONLY <3>types\(step), <3>fits\(step), \(priorFuel), SMT
                  <3>advance\(step). /\\ ProofInitialization!Expressions!CompilerAllocationInvariant(input.root, terms,
                                       syntax, weight, ProofBoundKeys(\(row)), history[\(step)])
                                 /\\ weight[input.root] - history[\(step)].position =
                                      weight[input.root] - history[\(previous)].position - 1
                    BY ONLY <2>canonical, \(priorInvariant), <3>guard\(step), <3>projection,
                      ProofInitialSentinels, ProofIntegerBounds,
                      ProofInitialization!Expressions!CompilerAllocationPreservesMassAndMakesProgress, SMT
                      DEF syntax, history
                  <3>fuel\(step). weight[input.root] - history[\(step)].position = \(sourceCount - step)
                    BY ONLY <3>advance\(step), \(priorFuel), SMT
            """
        }.joined(separator: "\n")
        let allocationGuards = (1...sourceCount).map { "<3>guard\($0)" }.joined(separator: ", ")
        let remainingSourceProof: String
        let remainingSourceFacts: String
        let returnedSourceProof: String
        if sourceCount > 1 {
            let sourcePrefix = """
                  <3>sourceSteps. witness.allocationSteps = \(sourceCount)
                    BY ONLY DEF witness, SourceCompilerInvocationWitness\(row)
                  <3>sourceStart. ProofInitialization!Expressions!CompilerAllocationInvariant(input.root, terms, syntax, weight, ProofBoundKeys(\(row)),
                      ProofInitialization!Expressions!InitialCompilerAllocation(input.root, weight))
                    BY ONLY <2>canonical, ProofIntegerBounds, ProofInitialSentinels,
                      ProofInitialization!Expressions!CompilerAllocationStartsWithItsLoopInvariant DEF syntax
                  <3>sourceInvariants. \\A stage \\in 0..\(sourceCount) :
                      ProofInitialization!Expressions!CompilerAllocationInvariant(input.root, terms, syntax, weight, ProofBoundKeys(\(row)), history[stage])
                    BY ONLY <2>canonical, <2>allocation, <3>sourceSteps, <3>sourceStart, ProofIntegerBounds, ProofInitialSentinels,
                      ProofInitialization!Expressions!AllocationCompletionRetainsEveryLoopInvariant DEF syntax, history
                  <3>firstExpressions. history[1].expressions = IF input.root[1] = "add"
                      THEN [index \\in 1..3 |-> IF index = 3 THEN input.root[3] ELSE IF index = 2 THEN input.root[2] ELSE input.root]
                      ELSE history[0].expressions
                    BY ONLY <3>firstFields, <3>initialFields, <3>lookup, SMT DEF ProofInitialization!Expressions!HistoryAppend
            """
            var queue = [(expression: sourceExpression, path: "input.root", appendedAt: 0)]
            let sourceSteps = (1...sourceCount).compactMap { step -> String? in
                let selected = queue[step - 1]
                let priorCount = queue.count
                let isAdd: Bool
                if case .add(let left, let right) = selected.expression {
                    isAdd = true
                    queue.append((left, "\(selected.path)[2]", step))
                    queue.append((right, "\(selected.path)[3]", step))
                } else {
                    isAdd = false
                }
                guard step > 1 else { return nil }

                let previous = step - 1
                let priorFields = step == 2 ? "<3>firstFields" : "<3>fields\(previous)"
                let priorCountFact = step == 2 ? "<3>firstCount, <3>root" : "<3>count\(previous)"
                let introduced = selected.appendedAt
                let introductionFacts = introduced == 1
                    ? "<3>firstExpressions, <3>root"
                    : "<3>queueEntries\(introduced), <3>selectedChild\(introduced)"
                let retentionFacts = ((introduced + 1)..<step).map { "<3>queueEntries\($0)" }
                let selectionFacts = (["<3>selectedValue\(step)", introductionFacts] + retentionFacts).joined(separator: ", ")
                let queueProof: String
                if step == sourceCount {
                    queueProof = ""
                } else if isAdd {
                    queueProof = """

                          <3>queueShape\(step). history[\(step)].expressions =
                              ProofInitialization!Expressions!HistoryAppend(
                                  ProofInitialization!Expressions!HistoryAppend(history[\(previous)].expressions, \(priorCount), selected\(step)[2]),
                                  \(priorCount + 1), selected\(step)[3])
                            BY ONLY <3>fields\(step), <3>lookup\(step), <3>tag\(step), \(priorCountFact), SMT
                          <3>queueEntries\(step).
                              /\\ \\A index \\in 1..\(priorCount) : history[\(step)].expressions[index] = history[\(previous)].expressions[index]
                              /\\ history[\(step)].expressions[\(priorCount + 1)] = selected\(step)[2]
                              /\\ history[\(step)].expressions[\(priorCount + 2)] = selected\(step)[3]
                            BY ONLY <3>queueShape\(step), SMT DEF ProofInitialization!Expressions!HistoryAppend
                    """
                } else {
                    queueProof = """

                          <3>queueEntries\(step).
                              \\A index \\in 1..\(priorCount) : history[\(step)].expressions[index] = history[\(previous)].expressions[index]
                            BY ONLY <3>fields\(step), <3>lookup\(step), <3>tag\(step), SMT
                    """
                }
                let tagRelation = isAdd ? "=" : "#"
                let count = queue.count
                return """
                      <3>. DEFINE selected\(step) == history[\(previous)].expressions[history[\(previous)].position + 1]
                      <3>priorInvariant\(step). ProofInitialization!Expressions!CompilerAllocationInvariant(input.root, terms, syntax, weight, ProofBoundKeys(\(row)), history[\(previous)])
                        BY ONLY <3>sourceInvariants, SMT
                      <3>priorGuard\(step). history[\(previous)].position < history[\(previous)].count
                        BY ONLY \(priorFields), \(priorCountFact), SMT
                      <3>selectedValue\(step). selected\(step) = history[\(previous)].expressions[\(step)]
                        BY ONLY \(priorFields), SMT DEF selected\(step)
                      <3>selectedChild\(step). selected\(step) = \(selected.path)
                        BY ONLY \(selectionFacts), SMT
                      <3>tag\(step). selected\(step)[1] \(tagRelation) "add"
                        BY ONLY <3>selectedChild\(step), <3>root, SMT
                      <3>queueType\(step). /\\ history[\(previous)].position \\in Nat /\\ history[\(previous)].count \\in Nat
                          /\\ history[\(previous)].expressions \\in [1..history[\(previous)].count -> terms]
                        BY ONLY <3>priorInvariant\(step) DEF ProofInitialization!Expressions!CompilerAllocationInvariant
                      <3>queueIndex\(step). history[\(previous)].position + 1 \\in 1..history[\(previous)].count
                        BY ONLY <3>queueType\(step), <3>priorGuard\(step), SMT
                      <3>selectedMember\(step). selected\(step) \\in terms
                        BY ONLY <3>queueType\(step), <3>queueIndex\(step), SMT DEF selected\(step)
                      <3>lookup\(step). syntax[selected\(step)] =
                          [kind |-> selected\(step)[1], literal |-> IF selected\(step)[1] = "literal" THEN selected\(step)[2] ELSE 0,
                           read |-> IF selected\(step)[1] = "read" THEN selected\(step)[2] ELSE 0,
                           left |-> IF selected\(step)[1] = "add" THEN selected\(step)[2] ELSE 0,
                           right |-> IF selected\(step)[1] = "add" THEN selected\(step)[3] ELSE 0]
                        BY ONLY <3>selectedMember\(step) DEF syntax, ProofInitialization!Expressions!AllocationTermSyntax
                      <3>edge\(step). history[\(step)] = ProofInitialization!Expressions!ReviewedSwiftAllocationIteration(syntax, weight, history[\(previous)])
                        BY ONLY <3>projection, SMT
                      <3>fields\(step).
                          /\\ history[\(step)].position = \(step)
                          /\\ history[\(step)].count = IF syntax[selected\(step)].kind = "add" THEN history[\(previous)].count + 2 ELSE history[\(previous)].count
                          /\\ history[\(step)].source = ProofInitialization!Expressions!HistoryAppend(history[\(previous)].source, \(previous),
                               ProofInitialization!Expressions!CompilerAllocationSourceNode(syntax, history[\(previous)]))
                          /\\ history[\(step)].expressions = IF syntax[selected\(step)].kind = "add"
                               THEN ProofInitialization!Expressions!HistoryAppend(ProofInitialization!Expressions!HistoryAppend(history[\(previous)].expressions, history[\(previous)].count, syntax[selected\(step)].left),
                                      history[\(previous)].count + 1, syntax[selected\(step)].right)
                               ELSE history[\(previous)].expressions
                        BY ONLY <3>edge\(step), \(priorFields), ProofIntegerBounds, ProofInitialSentinels,
                          ProofInitialization!Expressions!ReviewedAllocationIterationProjectsStoredFields, SMT DEF selected\(step)
                      <3>node\(step). ProofInitialization!Expressions!CompilerAllocationSourceNode(syntax, history[\(previous)]) =
                          IF syntax[selected\(step)].kind = "add"
                          THEN [kind |-> "add", literal |-> 0, read |-> 0, left |-> history[\(previous)].count + 1, right |-> history[\(previous)].count + 2]
                          ELSE syntax[selected\(step)]
                        BY ONLY DEF selected\(step), ProofInitialization!Expressions!CompilerAllocationSourceNode
                      <3>sourceAppend\(step). history[\(step)].source = ProofInitialization!Expressions!HistoryAppend(history[\(previous)].source, \(previous),
                          ProofInitialization!Expressions!CompilerAllocationSourceNode(syntax, history[\(previous)]))
                        BY ONLY <3>fields\(step)
                      <3>source\(step). history[\(step)].source = [index \\in 1..\(step) |-> IF index = \(step)
                          THEN IF syntax[selected\(step)].kind = "add"
                               THEN [kind |-> "add", literal |-> 0, read |-> 0, left |-> history[\(previous)].count + 1, right |-> history[\(previous)].count + 2]
                               ELSE syntax[selected\(step)]
                          ELSE history[\(previous)].source[index]]
                        BY ONLY <3>sourceAppend\(step), <3>node\(step), SMT DEF ProofInitialization!Expressions!HistoryAppend
                      <3>count\(step). history[\(step)].count = \(count)
                        BY ONLY <3>fields\(step), <3>lookup\(step), <3>tag\(step), \(priorCountFact), SMT\(queueProof)
                """
            }.joined(separator: "\n")
            remainingSourceProof = "\n" + sourcePrefix + "\n" + sourceSteps
            remainingSourceFacts = ", " + (2...sourceCount).flatMap { step in
                ["selectedChild", "lookup", "source", "count"].map { "<3>\($0)\(step)" }
            }.joined(separator: ", ")
            let returned = "SourceSyntaxViews[\(row)][2]"
            let sourceFields = [
                (field: "kinds", nodeField: "kind", kind: ""),
                (field: "literals", nodeField: "literal", kind: "literal"),
                (field: "reads", nodeField: "read", kind: "read"),
                (field: "left", nodeField: "left", kind: "add"),
                (field: "right", nodeField: "right", kind: "add"),
            ]
            let viewFields = sourceFields.map { field, nodeField, kind in
                let column = "\(returned).\(field)"
                let actual = "allocated.source[index].\(nodeField)"
                let actualValue = kind.isEmpty ? actual
                    : "IF allocated.source[index].kind = \"\(kind)\" THEN \(actual) ELSE 0"
                let normalization = kind.isEmpty ? "" : """

                        <4>normalized. \\A index \\in 1..\(sourceCount) :
                            (IF \(returned).kinds[index] = "\(kind)" THEN \(column)[index] ELSE 0) = \(column)[index]
                          BY ONLY <3>returnedView, SMT
                """
                let normalizationFact = kind.isEmpty ? "" : ", <4>normalized"
                return """
                      <3>view\(field). allocatedView.\(field) = \(column)
                        PROOF
                        <4>actual. allocatedView.\(field) = [index \\in 1..\(sourceCount) |-> \(actualValue)]
                          BY ONLY <3>viewOfAllocation, <3>finalFields, SMT DEF ProofInitialization!Expressions!AllocatedSourceView\(normalization)
                        <4>matches. \\A index \\in 1..\(sourceCount) : (\(actualValue)) = \(column)[index]
                          BY ONLY <3>finalFields\(normalizationFact), SMT
                        <4>column. \(column) = [index \\in 1..\(sourceCount) |-> \(column)[index]]
                          BY ONLY <3>returnedView, SMT
                        <4>. QED BY ONLY <4>actual, <4>matches, <4>column, SMT
                """
            }.joined(separator: "\n")
            let viewFacts = sourceFields.map { "<3>view\($0.field)" }.joined(separator: ", ")
            returnedSourceProof = """

                  <3>viewOfAllocation. allocatedView = ProofInitialization!Expressions!AllocatedSourceView(allocated)
                    BY ONLY <3>projection, SMT
                  <3>viewRecord. allocatedView = [root |-> 1, kinds |-> allocatedView.kinds,
                      literals |-> allocatedView.literals, reads |-> allocatedView.reads,
                      left |-> allocatedView.left, right |-> allocatedView.right]
                    BY ONLY <3>viewOfAllocation, SMT DEF ProofInitialization!Expressions!AllocatedSourceView
            \(viewFields)
                  <3>. QED BY ONLY <3>viewRecord, <3>returnedView, \(viewFacts), SMT
            """
        } else {
            remainingSourceProof = ""
            remainingSourceFacts = ""
            returnedSourceProof = """

                  <3>. QED BY ONLY <3>returnedView, <3>projection, <3>finalFields, SMT
                    DEF ProofInitialization!Expressions!AllocatedSourceView
            """
        }
        let expressions = "ProofInitialization!Expressions!"
        var pending = [(origin: 1, expanded: false)]
        var visits: [(origin: Int, expanded: Bool, height: Int, expands: Bool)] = []
        var traversalSourceFacts = ["allocatedView.root = 1", "allocatedView.kinds = \(kinds)"]
        var traversalFrames: [String] = []
        for previous in 0..<traversalCount {
            guard let frame = pending.popLast(), frame.origin > 0, frame.origin <= source.count else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            let next = previous + 1
            let height = pending.count + 1
            let expands: Bool
            if !frame.expanded, case let .add(left, right) = source[frame.origin - 1] {
                guard left > frame.origin, right > frame.origin, left <= source.count, right <= source.count,
                      pending.count <= traversalCount - next - 3 else {
                    throw InitialFailureEvidenceError.unsupportedGeneratedOutput
                }
                traversalSourceFacts.append("allocatedView.left[\(frame.origin)] = \(left)")
                traversalSourceFacts.append("allocatedView.right[\(frame.origin)] = \(right)")
                pending.append(contentsOf: [(frame.origin, true), (right, false), (left, false)])
                expands = true
            } else {
                expands = false
            }
            visits.append((frame.origin, frame.expanded, height, expands))
            let definitions: String
            if expands {
                definitions = "\n        DEF \(expressions)ReplaceTopVisitFrame,\n          \(expressions)ExpandedVisitFrames,\n          \(expressions)VisitFrame"
            } else {
                definitions = pending.isEmpty ? "" : "\n        DEF \(expressions)HistoryPrefix"
            }
            let sourceFact = pending.isEmpty && frame.expanded ? "" : ", <2>traversalSource"
            let nextHeight = "traversal[\(next)].height = \(pending.count)"
            let label = pending.isEmpty ? "terminalHeight" : "frame\(next)"
            let fields = pending.indices.reversed().flatMap { offset in
                let saved = pending[offset]
                let target = "traversal[\(next)].pending[\(offset + 1)]"
                return ["\(target).node = \(saved.origin)", saved.expanded ? "\(target).expanded" : "~\(target).expanded"]
            }
            let claim = pending.isEmpty ? nextHeight : "/\\ " + ([nextHeight] + fields).joined(separator: "\n               /\\ ")
            traversalFrames.append("""
                <2>edge\(next). traversal[\(next)] =
                    \(expressions)CompilerTraversalNext(allocatedView, traversal[\(previous)])
                  BY ONLY SMT DEF traversal, witness, allocatedView, allocated, SourceCompilerInvocationWitness\(row)
                <2>\(label). \(claim)
                  BY ONLY <2>edge\(next)\(sourceFact), <2>frame\(previous), ProofIntegerBounds, ProofInitialSentinels,
                    \(expressions)CompilerTraversalNextProjectsStoredFields, SMT\(definitions)
            """)
        }
        guard pending.isEmpty else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        let edgeFacts = (1...traversalCount).map { "<2>edge\($0)" }.joined(separator: ", ")
        let frameFacts = (0..<traversalCount).map { "<2>frame\($0)" }.joined(separator: ", ")
        var emissionCount = 0
        let currentUpdates = visits.enumerated().map { prior, visit in
            let step = prior + 1
            let origin = visit.origin
            let before = "traversal[\(prior)].current"
            let update = visit.expands ? before :
                "\(expressions)AppendCertificateConstructor(allocatedView, \(before), \(origin))"
            let current = """
                  <3>current\(step). traversal[\(step)].current = \(update)
                    BY ONLY <2>edge\(step), <2>traversalSource, <2>frame\(prior), ProofIntegerBounds, ProofInitialSentinels,
                      ProofInitialization!Expressions!CompilerTraversalNextProjectsStoredFields, SMT
            """
            if visit.expands {
                let matches = """
                      <3>matches\(step). traversal[\(step)].current = claimedPrefix(\(emissionCount))
                        BY ONLY <3>current\(step), <3>matches\(prior)
                """
                return current + "\n" + matches
            }
            emissionCount += 1
            let matches = """
                  <3>matches\(step). traversal[\(step)].current = claimedPrefix(\(emissionCount))
                    PROOF
                    <4>origin. claimed.origins[\(emissionCount)] = \(origin)
                      BY ONLY <2>data, SMT DEF claimed
                    <4>node. claimed.nodes[\(emissionCount)] = appended(\(emissionCount)).emitted.nodes[\(emissionCount)]
                      BY ONLY <2>data, <3>view, <4>origin, SMT
                        DEF claimed, claimedIndices, appended, claimedPrefix,
                          ProofInitialization!Expressions!CompilerCertificatePrefix,
                          ProofInitialization!Expressions!AppendCertificateConstructor, ProofInitialization!Expressions!HistoryAppend
                    <4>inverse. \\A origin \\in DOMAIN allocatedView.kinds :
                        claimedPrefix(\(emissionCount)).inverse[origin] = appended(\(emissionCount)).inverse[origin]
                      BY ONLY <2>data, <3>domain, <4>origin, SMT
                        DEF claimedIndices, appended, claimedPrefix,
                          ProofInitialization!Expressions!CompilerCertificatePrefix,
                          ProofInitialization!Expressions!AppendCertificateConstructor
                    <4>transition. claimedPrefix(\(emissionCount)) = appended(\(emissionCount))
                      BY ONLY <4>node, <4>inverse, ProofIntegerBounds, ProofInitialSentinels,
                        ProofInitialization!Expressions!CompilerCertificatePrefixesRealizeTheConstructor, SMT
                        DEF claimedPrefix, appended
                    <4>. QED BY ONLY <3>current\(step), <3>matches\(prior), <4>origin, <4>transition DEF appended
            """
            return current + "\n" + matches
        }.joined(separator: "\n")
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
              <3>source. /\\ ProofBoundKeys(\(row)) \\subseteq ProofIntKeys
                         /\\ SourceInitializers[\(row)][1] \\in ProofIntKeys
                BY ONLY <3>rows, SMT DEF ProofBoundKeys, ProofIntKeys
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
              <3>derivation. ProofInitialization!Expressions!AllocationConstructorDerivation(
                               input.root, ProofBoundKeys(\(row)), derivation)
                BY ONLY <3>row, <2>scalars, <2>keys, ProofIntegerBounds, SMT
                  DEF ProofBoundKeys, SourceInitializers, ProofIntMin, ProofIntMax,
                    ProofInitialization!Expressions!AllocationLeafDerivation,
                    ProofInitialization!Expressions!AllocationAddDerivation,
                    ProofInitialization!Expressions!AllocationConstructorDerivation, ProofInitialization!Expressions!InRange
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
            <2>. DEFINE syntax == ProofInitialization!Expressions!AllocationTermSyntax(terms)
                        witness == SourceCompilerInvocationWitness\(row)(syntax, weight)
                        allocated == witness.allocationHistory[witness.allocationSteps]
                        allocatedView == ProofInitialization!Expressions!AllocatedSourceView(allocated)
                        final == witness.traversalHistory[witness.traversalSteps]
            <2>capacity. weight[input.root] <= ProofIntMax
              PROOF
              <3>row. /\\ derivation = \(sourceDerivation) /\\ sizes = \(sourceSizes)
                BY ONLY DEF derivation, sizes, SourceCompilerInputDerivations, SourceCompilerInputSizes
              <3>end. sizes[derivation.count] = \(sourceCount)
                BY ONLY <3>row DEF ProofInitialization!Expressions!AllocationLeafDerivation,
                  ProofInitialization!Expressions!AllocationAddDerivation
              <3>. QED BY ONLY <2>canonical, <3>end, ProofIntegerBounds, SMT
            <2>allocation. ProofInitialization!Expressions!CompilerAllocationCompletion(syntax, weight,
                ProofInitialization!Expressions!InitialCompilerAllocation(input.root, weight),
                witness.allocationSteps, witness.allocationHistory)
              PROOF
              <3>root. input.root = \(term)
                BY ONLY DEF input, SourceCompilerInputs
              <3>projection. /\\ witness.allocationSteps = \(sourceCount)
                             /\\ DOMAIN witness.allocationHistory = 0..\(sourceCount)
                             /\\ witness.allocationHistory[0] = ProofInitialization!Expressions!InitialCompilerAllocation(input.root, weight)
                             /\\ \\A step \\in 1..\(sourceCount) : witness.allocationHistory[step] =
                                  ProofInitialization!Expressions!ReviewedSwiftAllocationIteration(syntax, weight,
                                    witness.allocationHistory[step - 1])
                BY ONLY DEF witness, SourceCompilerInvocationWitness\(row), input
              <3>. DEFINE history == witness.allocationHistory
              <3>sourceSize. weight[input.root] = \(sourceCount)
                PROOF
                <4>row. /\\ derivation = \(sourceDerivation) /\\ sizes = \(sourceSizes)
                  BY ONLY DEF derivation, sizes, SourceCompilerInputDerivations, SourceCompilerInputSizes
                <4>end. sizes[derivation.count] = \(sourceCount)
                  BY ONLY <4>row DEF ProofInitialization!Expressions!AllocationLeafDerivation,
                    ProofInitialization!Expressions!AllocationAddDerivation
                <4>. QED BY ONLY <2>canonical, <4>end
              <3>initialInvariant. ProofInitialization!Expressions!CompilerAllocationInvariant(input.root, terms,
                  syntax, weight, ProofBoundKeys(\(row)), history[0])
                BY <2>canonical, <3>projection, ProofInitialization!Expressions!CompilerAllocationStartsWithItsLoopInvariant
                  DEF syntax, history
              <3>initialPosition. history[0].position = 0
                BY ONLY <3>projection DEF history, ProofInitialization!Expressions!InitialCompilerAllocation
              <3>initialFuel. weight[input.root] - history[0].position = \(sourceCount)
                BY ONLY <3>sourceSize, <3>initialPosition, SMT
        \(allocationProgress)
              <3>lastFits. history[\(sourceCount)].position = history[\(sourceCount)].count <=>
                              weight[input.root] - history[\(sourceCount)].position = 0
                BY ONLY <2>canonical, <3>advance\(sourceCount), ProofInitialSentinels, ProofIntegerBounds,
                  ProofInitialization!Expressions!CompilerAllocationFitsItsFiniteInputSize DEF syntax
              <3>terminal. history[\(sourceCount)].position = history[\(sourceCount)].count
                BY ONLY <3>lastFits, <3>fuel\(sourceCount), SMT
              <3>. QED BY ONLY <3>projection, \(allocationGuards), <3>terminal, SMT
                DEF history, ProofInitialization!Expressions!CompilerAllocationCompletion
            <2>allocatedSource. allocatedView = SourceSyntaxViews[\(row)][2]
              PROOF
              <3>. DEFINE history == witness.allocationHistory
              <3>projection. /\\ allocated = history[\(sourceCount)]
                             /\\ allocatedView = ProofInitialization!Expressions!AllocatedSourceView(history[\(sourceCount)])
                             /\\ history[0] = ProofInitialization!Expressions!InitialCompilerAllocation(input.root, weight)
                             /\\ \\A step \\in 1..\(sourceCount) : history[step] =
                                  ProofInitialization!Expressions!ReviewedSwiftAllocationIteration(syntax, weight, history[step - 1])
                BY ONLY DEF history, allocatedView, allocated, witness, SourceCompilerInvocationWitness\(row), input
              <3>root. input.root = \(term)
                BY ONLY DEF input, SourceCompilerInputs
              <3>member. input.root \\in terms
                BY ONLY <2>canonical DEF ProofInitialization!Expressions!SupportedAllocationInput
              <3>lookup. syntax[input.root] =
                  [kind |-> input.root[1],
                   literal |-> IF input.root[1] = "literal" THEN input.root[2] ELSE 0,
                   read |-> IF input.root[1] = "read" THEN input.root[2] ELSE 0,
                   left |-> IF input.root[1] = "add" THEN input.root[2] ELSE 0,
                   right |-> IF input.root[1] = "add" THEN input.root[3] ELSE 0]
                BY ONLY <3>member DEF syntax, ProofInitialization!Expressions!AllocationTermSyntax
              <3>initialFields. /\\ history[0].position = 0 /\\ history[0].count = 1
                                /\\ history[0].expressions = [index \\in 1..1 |-> input.root]
                                /\\ history[0].source = [index \\in 1..0 |-> index]
                BY ONLY <3>projection DEF ProofInitialization!Expressions!InitialCompilerAllocation
              <3>firstEdge. history[1] = ProofInitialization!Expressions!ReviewedSwiftAllocationIteration(syntax, weight, history[0])
                BY ONLY <3>projection, SMT
              <3>firstFields.
                  /\\ history[1].position = 1
                  /\\ history[1].count = IF syntax[input.root].kind = "add" THEN 3 ELSE 1
                  /\\ history[1].source = ProofInitialization!Expressions!HistoryAppend(history[0].source, 0,
                       ProofInitialization!Expressions!CompilerAllocationSourceNode(syntax, history[0]))
                  /\\ history[1].expressions = IF syntax[input.root].kind = "add"
                       THEN ProofInitialization!Expressions!HistoryAppend(
                         ProofInitialization!Expressions!HistoryAppend(history[0].expressions, 1, syntax[input.root].left),
                         2, syntax[input.root].right)
                       ELSE history[0].expressions
                BY ONLY <3>firstEdge, <3>initialFields, ProofIntegerBounds, ProofInitialSentinels,
                  ProofInitialization!Expressions!ReviewedAllocationIterationProjectsStoredFields, SMT
              <3>firstNode. ProofInitialization!Expressions!CompilerAllocationSourceNode(syntax, history[0]) =
                  IF syntax[input.root].kind = "add"
                  THEN [kind |-> "add", literal |-> 0, read |-> 0, left |-> 2, right |-> 3]
                  ELSE syntax[input.root]
                BY ONLY <3>initialFields, SMT DEF ProofInitialization!Expressions!CompilerAllocationSourceNode
              <3>returnedView. SourceSyntaxViews[\(row)][2] = \(view)
                BY ONLY <2>data
              <3>sourceAppend. history[1].source = ProofInitialization!Expressions!HistoryAppend(history[0].source, 0,
                  ProofInitialization!Expressions!CompilerAllocationSourceNode(syntax, history[0]))
                BY ONLY <3>firstFields
              <3>firstSource. history[1].source = [index \\in 1..1 |->
                  IF syntax[input.root].kind = "add"
                  THEN [kind |-> "add", literal |-> 0, read |-> 0, left |-> 2, right |-> 3]
                  ELSE syntax[input.root]]
                BY ONLY <3>sourceAppend, <3>initialFields, <3>firstNode, SMT
                  DEF ProofInitialization!Expressions!HistoryAppend
              <3>firstCount. history[1].count = IF input.root[1] = "add" THEN 3 ELSE 1
                BY ONLY <3>firstFields, <3>lookup, SMT\(remainingSourceProof)
              <3>finalFields.
                  /\\ allocated.count = \(sourceCount)
                  /\\ allocated.source = [index \\in 1..\(sourceCount) |->
                       [kind |-> SourceSyntaxViews[\(row)][2].kinds[index],
                        literal |-> SourceSyntaxViews[\(row)][2].literals[index],
                        read |-> SourceSyntaxViews[\(row)][2].reads[index],
                        left |-> SourceSyntaxViews[\(row)][2].left[index],
                        right |-> SourceSyntaxViews[\(row)][2].right[index]]]
                BY ONLY <3>returnedView, <3>projection, <3>root, <3>lookup, <3>firstCount, <3>firstSource\(remainingSourceFacts), SMT\(returnedSourceProof)
            <2>tree. /\\ ProofInitialization!Expressions!CompilerOccurrenceTree(allocatedView, allocated.count)
                     /\\ allocated.count <= ProofIntMax
                     /\\ allocated.count = \(sourceCount)
              PROOF
              <3>supported. ProofInitialization!Expressions!SupportedAllocationInput(input.root, terms,
                                syntax, weight, ProofBoundKeys(\(row)))
                BY ONLY <2>canonical DEF syntax
              <3>initial. ProofInitialization!Expressions!CompilerAllocationInvariant(input.root, terms,
                              syntax, weight, ProofBoundKeys(\(row)),
                              ProofInitialization!Expressions!InitialCompilerAllocation(input.root, weight))
                BY ONLY <3>supported, ProofIntegerBounds, ProofInitialSentinels,
                  ProofInitialization!Expressions!CompilerAllocationStartsWithItsLoopInvariant
              <3>terminal. /\\ witness.allocationSteps \\in 0..witness.allocationSteps
                           /\\ allocated.position = allocated.count
                BY ONLY <2>allocation, SMT DEF allocated, ProofInitialization!Expressions!CompilerAllocationCompletion
              <3>invariants. \\A step \\in 0..witness.allocationSteps :
                  ProofInitialization!Expressions!CompilerAllocationInvariant(input.root, terms,
                      syntax, weight, ProofBoundKeys(\(row)), witness.allocationHistory[step])
                BY ONLY <3>supported, <3>initial, <2>allocation, ProofIntegerBounds, ProofInitialSentinels,
                  ProofInitialization!Expressions!AllocationCompletionRetainsEveryLoopInvariant
              <3>last. ProofInitialization!Expressions!CompilerAllocationInvariant(input.root, terms,
                           syntax, weight, ProofBoundKeys(\(row)), allocated)
                BY ONLY <3>terminal, <3>invariants DEF allocated
              <3>source. /\\ ProofInitialization!Expressions!CompilerOccurrenceTree(allocatedView, allocated.count)
                         /\\ allocated.count = weight[input.root]
                BY ONLY <3>supported, <3>terminal, <3>last, ProofIntegerBounds, ProofInitialSentinels,
                  ProofInitialization!Expressions!CompletedAllocationSuppliesOccurrenceTreeAndSource
                  DEF allocatedView
              <3>sizes. /\\ derivation = \(sourceDerivation) /\\ sizes = \(sourceSizes)
                BY ONLY DEF derivation, sizes, SourceCompilerInputDerivations, SourceCompilerInputSizes
              <3>weight. weight[input.root] = \(sourceCount)
                BY ONLY <2>canonical, <3>sizes, SMT DEF ProofInitialization!Expressions!AllocationLeafDerivation,
                  ProofInitialization!Expressions!AllocationAddDerivation
              <3>. QED BY ONLY <3>source, <2>capacity, <3>weight, SMT
            <2>. DEFINE traversal == witness.traversalHistory
            <2>traversalSteps. /\\ witness.traversalSteps = \(traversalCount)
                              /\\ final = traversal[\(traversalCount)]
              BY ONLY SMT DEF witness, final, traversal, SourceCompilerInvocationWitness\(row)
            <2>traversalInitial. traversal[0] = \(expressions)InitialCompilerTraversal(allocatedView)
              BY ONLY SMT DEF traversal, witness, allocatedView, allocated, SourceCompilerInvocationWitness\(row)
            <2>traversalSource. /\\ \(traversalSourceFacts.joined(separator: "\n                        /\\ "))
              BY ONLY <2>data, <2>allocatedSource, SMT
            <2>frame0. /\\ traversal[0].height = 1
                       /\\ traversal[0].pending[1].node = 1
                       /\\ ~traversal[0].pending[1].expanded
              BY ONLY <2>traversalInitial, <2>traversalSource, SMT
                DEF \(expressions)InitialCompilerTraversal, \(expressions)VisitFrame
        \(traversalFrames.joined(separator: "\n"))
            <2>traversalHistory. /\\ traversal[0] = \(expressions)InitialCompilerTraversal(allocatedView)
                                /\\ \\A step \\in 1..\(traversalCount) : traversal[step] =
                                     \(expressions)CompilerTraversalNext(allocatedView, traversal[step - 1])
              BY ONLY <2>traversalInitial, \(edgeFacts), SMT
            <2>prefix. /\\ \(expressions)CompilerTraversalPrefix(allocatedView,
                              witness.traversalSteps, witness.traversalHistory)
                       /\\ final.height = 0
              BY ONLY <2>traversalSteps, <2>traversalHistory, \(frameFacts), <2>terminalHeight, SMT
                DEF traversal, \(expressions)CompilerTraversalPrefix
            <2>. DEFINE steps == witness.traversalSteps
                        storage == witness.execution
                        swiftSource == ProofInitialization!Expressions!SwiftSourceArray(allocatedView, allocated.count)
                        actualReturn == ProofInitialization!Expressions!ReviewedSwiftCertificateReturn(swiftSource, storage[steps])
                        expected == SourceCompilerResults(\(row))
                        emitted == final.current.emitted
                        inverse == final.current.inverse
            <2>domain. /\\ steps \\in Nat /\\ steps \\in 0..steps
              BY ONLY <2>prefix, SMT DEF steps, traversal, ProofInitialization!Expressions!CompilerTraversalPrefix
            <2>storage. \\A step \\in 0..steps : storage[step] =
                ProofInitialization!Expressions!SwiftCompilerStorage(allocatedView, allocated.count, traversal[step])
              BY ONLY SMT DEF storage, traversal, steps, allocated, allocatedView, witness, SourceCompilerInvocationWitness\(row)
            <2>loop. /\\ storage[0] = ProofInitialization!Expressions!ReviewedSwiftTraversalInitialization(swiftSource)
                     /\\ \\A step \\in 1..steps :
                        /\\ storage[step - 1].pending.count > 0
                        /\\ storage[step] = ProofInitialization!Expressions!ReviewedSwiftCompilerIteration(swiftSource, storage[step - 1])
              PROOF
              <3>direct.
                  /\\ ProofInitialization!Expressions!SwiftCompilerStorage(allocatedView, allocated.count, traversal[0]) =
                       ProofInitialization!Expressions!ReviewedSwiftTraversalInitialization(swiftSource)
                  /\\ \\A step \\in 1..steps :
                       /\\ ProofInitialization!Expressions!SwiftCompilerStorage(allocatedView, allocated.count, traversal[step - 1]).pending.count > 0
                       /\\ ProofInitialization!Expressions!SwiftCompilerStorage(allocatedView, allocated.count, traversal[step]) =
                            ProofInitialization!Expressions!ReviewedSwiftCompilerIteration(swiftSource,
                              ProofInitialization!Expressions!SwiftCompilerStorage(allocatedView, allocated.count, traversal[step - 1]))
                BY ONLY <2>tree, <2>prefix, ProofIntegerBounds, ProofInitialSentinels,
                  ProofInitialization!Expressions!CompilerTraversalPrefixesExecuteTheReviewedSwiftLoop
                  DEF swiftSource, traversal, steps
              <3>ranges. /\\ 0 \\in 0..steps
                         /\\ \\A step \\in 1..steps : step \\in 0..steps /\\ step - 1 \\in 0..steps
                BY ONLY <2>domain, SMT
              <3>. QED BY ONLY <2>storage, <3>direct, <3>ranges, SMT
            <2>final. ProofInitialization!Expressions!CompilerTraversalInvariant(allocatedView, final)
              PROOF
              <3>invariants. \\A step \\in 0..steps :
                  ProofInitialization!Expressions!CompilerTraversalInvariant(allocatedView, traversal[step])
                BY ONLY <2>tree, <2>prefix, ProofIntegerBounds, ProofInitialSentinels,
                  ProofInitialization!Expressions!CompilerTraversalPrefixesDeriveStorageBounds
                  DEF traversal, steps
              <3>. QED BY ONLY <2>domain, <3>invariants, SMT DEF final, traversal, steps
            <2>returned. ProofInitialization!Expressions!ReviewedReturnMatchesCertificate(allocatedView, allocated.count, final)
              BY ONLY <2>tree, <2>prefix, <2>final, ProofIntegerBounds, ProofInitialSentinels,
                ProofInitialization!Expressions!TerminatedCompilerInvariantDerivesEveryReturnGuard
            <2>last. storage[steps] = ProofInitialization!Expressions!SwiftCompilerStorage(allocatedView, allocated.count, final)
              BY ONLY <2>domain, <2>storage, SMT DEF final, traversal, steps
            <2>exit. ProofInitialization!Expressions!ReviewedSwiftCompilerIteration(swiftSource, storage[steps]).control = "exit"
              PROOF
              <3>empty. /\\ storage[steps].pending.count = 0
                         /\\ "control" \\in DOMAIN storage[steps]
                BY ONLY <2>last, <2>prefix
                  DEF ProofInitialization!Expressions!SwiftCompilerStorage, ProofInitialization!Expressions!SwiftPendingArray
              <3>stopped. ProofInitialization!Expressions!ReviewedSwiftCompilerIteration(swiftSource, storage[steps]) =
                  [storage[steps] EXCEPT !.control = "exit"]
                BY ONLY <3>empty DEF ProofInitialization!Expressions!ReviewedSwiftCompilerIteration
              <3>. QED BY ONLY <3>empty, <3>stopped, SMT
            <2>returnFields. actualReturn =
                [control |-> "return", certificate |->
                    [source |-> swiftSource,
                     nodes |-> ProofInitialization!Expressions!SwiftIndexedArray(emitted.count, emitted.nodes),
                     origins |-> ProofInitialization!Expressions!SwiftIndexedArray(emitted.count, emitted.origins),
                     indices |-> ProofInitialization!Expressions!SwiftIndexedArray(allocated.count, inverse)]]
              BY ONLY <2>last, <2>returned
                DEF actualReturn, swiftSource, emitted, inverse, ProofInitialization!Expressions!ReviewedReturnMatchesCertificate
            <2>execution. ProofInitialization!Expressions!ReviewedCompilerTraversalExecution(allocatedView,
                              allocated.count, steps, storage)
              BY ONLY <2>domain, <2>loop, <2>exit, <2>returnFields
                DEF actualReturn, swiftSource, ProofInitialization!Expressions!ReviewedCompilerTraversalExecution
            <2>finalArrays.
                /\\ emitted.count = SourcePlanEmission(\(row)).count
                /\\ emitted.nodes = SourcePlanEmission(\(row)).nodes
                /\\ emitted.origins = SourceSyntaxOrigins[\(row)]
                /\\ inverse = SourceSyntaxIndices[\(row)]
              PROOF
              <3>. DEFINE claimed == SourcePlanEmission(\(row))
                          claimedIndices == SourceSyntaxIndices[\(row)]
                          claimedPrefix(count) == ProofInitialization!Expressions!CompilerCertificatePrefix(
                              allocatedView, claimed, claimedIndices, count)
                          appended(count) == ProofInitialization!Expressions!AppendCertificateConstructor(
                              allocatedView, claimedPrefix(count - 1), claimed.origins[count])
              <3>initial. traversal[0].current =
                  ProofInitialization!Expressions!EmptyCertificateConstruction(allocatedView)
                BY ONLY <2>traversalHistory DEF ProofInitialization!Expressions!InitialCompilerTraversal
              <3>view. allocatedView = \(view)
                BY ONLY <2>data, <2>allocatedSource
              <3>domain. DOMAIN allocatedView.kinds = 1..\(sourceCount)
                BY ONLY <2>tree DEF ProofInitialization!Expressions!CompilerOccurrenceTree
              <3>indexBounds. \\A origin \\in 1..\(sourceCount) : claimedIndices[origin] \\in 1..\(sourceCount)
                BY ONLY <2>data, SMT DEF claimedIndices
              <3>matches0. traversal[0].current = claimedPrefix(0)
                BY ONLY <3>initial, <3>domain, <3>indexBounds, SMT
                  DEF claimedPrefix, ProofInitialization!Expressions!CompilerCertificatePrefix,
                    ProofInitialization!Expressions!EmptyCertificateConstruction, ProofInitialization!Expressions!EmptyNodeEmission
        \(currentUpdates)
              <3>last. final.current = claimedPrefix(\(sourceCount))
                BY ONLY <2>traversalSteps, <3>matches\(traversalCount)
              <3>count. emitted.count = SourcePlanEmission(\(row)).count
                BY ONLY <3>last, <2>data DEF emitted, claimedPrefix, ProofInitialization!Expressions!CompilerCertificatePrefix
              <3>nodes. emitted.nodes = SourcePlanEmission(\(row)).nodes
                PROOF
                <4>stored. emitted.nodes = [index \\in 1..\(sourceCount) |-> claimed.nodes[index]]
                  BY ONLY <3>last DEF emitted, claimedPrefix, ProofInitialization!Expressions!CompilerCertificatePrefix
                <4>shape. claimed.nodes = [index \\in 1..\(sourceCount) |-> claimed.nodes[index]]
                  BY ONLY <2>data, SMT DEF claimed
                <4>. QED BY ONLY <4>stored, <4>shape DEF claimed
              <3>origins. emitted.origins = SourceSyntaxOrigins[\(row)]
                PROOF
                <4>stored. emitted.origins = [index \\in 1..\(sourceCount) |-> claimed.origins[index]]
                  BY ONLY <3>last DEF emitted, claimedPrefix, ProofInitialization!Expressions!CompilerCertificatePrefix
                <4>shape. SourceSyntaxOrigins[\(row)] = [index \\in 1..\(sourceCount) |-> claimed.origins[index]]
                  BY ONLY <2>data, SMT DEF claimed
                <4>. QED BY ONLY <4>stored, <4>shape
              <3>indices. inverse = SourceSyntaxIndices[\(row)]
                PROOF
                <4>stored. inverse = [origin \\in 1..\(sourceCount) |-> claimedIndices[origin]]
                  BY ONLY <3>last, <3>domain, <3>indexBounds, SMT
                    DEF inverse, claimedPrefix, ProofInitialization!Expressions!CompilerCertificatePrefix
                <4>shape. claimedIndices = [origin \\in 1..\(sourceCount) |-> claimedIndices[origin]]
                  BY ONLY <2>data, SMT DEF claimedIndices
                <4>. QED BY ONLY <4>stored, <4>shape DEF claimedIndices
              <3>. QED BY ONLY <3>count, <3>nodes, <3>origins, <3>indices
            <2>lengths.
                /\\ Len(SourceSyntaxViews[\(row)][2].kinds) = allocated.count
                /\\ Len(SourceSyntaxOrigins[\(row)]) = emitted.count
                /\\ Len(SourceSyntaxIndices[\(row)]) = allocated.count
              BY ONLY <2>tree, <2>data, <2>finalArrays, SMT
            <2>result. expected = actualReturn.certificate
              PROOF
              <3>source. expected.source = actualReturn.certificate.source
                BY ONLY <2>lengths, <2>allocatedSource, <2>returnFields
                  DEF expected, swiftSource, SourceCompilerResults
              <3>nodes. expected.nodes = actualReturn.certificate.nodes
                BY ONLY <2>finalArrays, <2>returnFields DEF expected, SourceCompilerResults
              <3>origins. expected.origins = actualReturn.certificate.origins
                BY ONLY <2>lengths, <2>finalArrays, <2>returnFields DEF expected, SourceCompilerResults
              <3>indices. expected.indices = actualReturn.certificate.indices
                BY ONLY <2>lengths, <2>finalArrays, <2>returnFields DEF expected, SourceCompilerResults
              <3>. QED BY ONLY <3>source, <3>nodes, <3>origins, <3>indices, <2>returnFields, SMT
                DEF expected, SourceCompilerResults
            <2>invocation. ProofInitialization!Expressions!ReviewedOrderedIntCertificateInvocation(input.root, input.reads,
                              syntax, weight, expected)
              PROOF
              <3>reads. \\A term \\in DOMAIN syntax : syntax[term].kind = "read" => syntax[term].read \\in input.reads
                BY ONLY <2>canonical, <2>keys, SMT
                  DEF syntax, ProofInitialization!Expressions!SupportedAllocationInput
              <3>actual. \\E allocationSteps, allocationHistory, traversalSteps, execution :
                  /\\ ProofInitialization!Expressions!CompilerAllocationCompletion(syntax, weight,
                       ProofInitialization!Expressions!InitialCompilerAllocation(input.root, weight),
                       allocationSteps, allocationHistory)
                  /\\ LET state == allocationHistory[allocationSteps]
                         view == ProofInitialization!Expressions!AllocatedSourceView(state)
                     IN /\\ ProofInitialization!Expressions!ReviewedCompilerTraversalExecution(view, state.count,
                              traversalSteps, execution)
                        /\\ expected = ProofInitialization!Expressions!ReviewedSwiftCertificateReturn(
                             ProofInitialization!Expressions!SwiftSourceArray(view, state.count),
                             execution[traversalSteps]).certificate
                PROOF
                <4>. WITNESS witness.allocationSteps, witness.allocationHistory, steps, storage
                <4>. QED BY ONLY <2>allocation, <2>execution, <2>result
                  DEF allocated, allocatedView, swiftSource, actualReturn
              <3>. QED BY ONLY <3>reads, <3>actual DEF ProofInitialization!Expressions!ReviewedOrderedIntCertificateInvocation
            <2>derived. ProofInitialization!Expressions!LiteralReadAddCertificate(
                ProofInitialization!Expressions!SwiftSourceArrayAsView(expected.source),
                ProofInitialization!Expressions!SwiftCertificateArraysAsEmission(expected),
                ProofInitialization!Expressions!SwiftArrayAsHistory(expected.indices),
                SourceInitializers[\(row)][1], ProofBoundKeys(\(row)))
              BY ONLY <2>canonical, <2>capacity, <2>keys, <2>invocation, ProofIntegerBounds, ProofInitialSentinels,
                ProofInitialization!Expressions!ActualReviewedCompilerResultSuppliesInitializerCertificate DEF syntax
            <2>projections.
                /\\ ProofInitialization!Expressions!SwiftSourceArrayAsView(expected.source) = SourceSyntaxViews[\(row)][2]
                /\\ ProofInitialization!Expressions!SwiftCertificateArraysAsEmission(expected) = SourcePlanEmission(\(row))
                /\\ ProofInitialization!Expressions!SwiftArrayAsHistory(expected.indices) = SourceSyntaxIndices[\(row)]
              PROOF
              <3>source. ProofInitialization!Expressions!SwiftSourceArrayAsView(expected.source) = SourceSyntaxViews[\(row)][2]
                PROOF
                <4>packed. expected.source = swiftSource
                  BY ONLY <2>lengths, <2>allocatedSource DEF expected, swiftSource, SourceCompilerResults
                <4>count. allocated.count \\in Nat
                  BY ONLY <2>tree DEF ProofInitialization!Expressions!CompilerOccurrenceTree
                <4>roundTrip. ProofInitialization!Expressions!SwiftSourceArrayAsView(swiftSource) = allocatedView
                  BY ONLY <4>count, ProofIntegerBounds, ProofInitialSentinels, ProofInitialization!Expressions!AllocatedSwiftSourceDecodesToSourceView DEF swiftSource, allocatedView
                <4>. QED BY ONLY <4>packed, <4>roundTrip, <2>allocatedSource
              <3>emission. ProofInitialization!Expressions!SwiftCertificateArraysAsEmission(expected) = SourcePlanEmission(\(row))
                PROOF
                <4>encoded. /\\ expected.nodes = ProofInitialization!Expressions!SwiftIndexedArray(emitted.count, emitted.nodes)
                            /\\ expected.origins = ProofInitialization!Expressions!SwiftIndexedArray(emitted.count, emitted.origins)
                  BY ONLY <2>result, <2>returnFields
                <4>shapes. /\\ emitted.count \\in Nat
                           /\\ emitted.nodes = [index \\in 1..emitted.count |-> emitted.nodes[index]]
                           /\\ emitted.origins = [index \\in 1..emitted.count |-> emitted.origins[index]]
                  BY ONLY <2>final DEF emitted, ProofInitialization!Expressions!CompilerTraversalInvariant,
                    ProofInitialization!Expressions!CertificateConstructionInvariant, ProofInitialization!Expressions!NodeEmissionArrays
                <4>nodes. ProofInitialization!Expressions!SwiftArrayAsHistory(expected.nodes) = emitted.nodes
                  BY ONLY <4>encoded, <4>shapes, ProofIntegerBounds, ProofInitialSentinels,
                    ProofInitialization!Expressions!SwiftIndexedArrayDecodesToHistory
                <4>origins. ProofInitialization!Expressions!SwiftArrayAsHistory(expected.origins) = emitted.origins
                  BY ONLY <4>encoded, <4>shapes, ProofIntegerBounds, ProofInitialSentinels,
                    ProofInitialization!Expressions!SwiftIndexedArrayDecodesToHistory
                <4>count. expected.nodes.count = emitted.count
                  BY ONLY <4>encoded DEF ProofInitialization!Expressions!SwiftIndexedArray
                <4>plan. SourcePlanEmission(\(row)) =
                    [count |-> emitted.count, height |-> 1, indices |-> <<emitted.count>>,
                     nodes |-> emitted.nodes, origins |-> emitted.origins]
                  BY ONLY <2>data, <2>finalArrays, SMT
                <4>. QED BY ONLY <4>nodes, <4>origins, <4>count, <4>plan DEF ProofInitialization!Expressions!SwiftCertificateArraysAsEmission
              <3>indices. ProofInitialization!Expressions!SwiftArrayAsHistory(expected.indices) = SourceSyntaxIndices[\(row)]
                PROOF
                <4>encoded. expected.indices = ProofInitialization!Expressions!SwiftIndexedArray(allocated.count, inverse)
                  BY ONLY <2>result, <2>returnFields
                <4>domain. /\\ allocated.count \\in Nat
                           /\\ DOMAIN allocatedView.kinds = 1..allocated.count
                  BY ONLY <2>tree, SMT DEF ProofInitialization!Expressions!CompilerOccurrenceTree
                <4>typed. inverse \\in [1..allocated.count -> 0..emitted.count]
                  BY ONLY <2>final, <4>domain DEF inverse, emitted, ProofInitialization!Expressions!CompilerTraversalInvariant,
                    ProofInitialization!Expressions!CertificateConstructionInvariant
                <4>shape. inverse = [index \\in 1..allocated.count |-> inverse[index]]
                  BY ONLY <4>typed, SMT
                <4>decoded. ProofInitialization!Expressions!SwiftArrayAsHistory(expected.indices) = inverse
                  BY ONLY <4>encoded, <4>domain, <4>shape, ProofIntegerBounds, ProofInitialSentinels,
                    ProofInitialization!Expressions!SwiftIndexedArrayDecodesToHistory
                <4>. QED BY ONLY <4>decoded, <2>finalArrays
              <3>. QED BY ONLY <3>source, <3>emission, <3>indices
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
                                    sourceCompilerInvocationWitnesses: String, sourceSyntaxViews: String,
                                    sourceSyntaxOrigins: String, sourceSyntaxIndices: String,
                                    sourcePlanEmissions: String, sourceCertificateProofs: String, sourceInitializerCount: Int, sourceInitialControl: String,
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

        SourcePlanEmission(row) == SourcePlanEmissions[row]

        SourceCompilerInputDerivations == \(sourceCompilerInputDerivations)
        SourceCompilerInputSizes == \(sourceCompilerInputSizes)

        \(sourceCompilerInvocationWitnesses)

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
