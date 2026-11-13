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
            sourceInitializers: sourceInitializers, sourceSyntaxViews: sourceInputs.views,
            sourceSyntaxOrigins: sourceInputs.origins, sourceSyntaxIndices: sourceInputs.indices,
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
        -> (plans: String, views: String, origins: String, indices: String) {
        let states = components.compactMap { component -> (root: String, initialization: VariableInitialization)? in
            guard case .variable(let root, let initialization) = component else { return nil }
            return (root, initialization)
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
            let syntax = try sourceSyntaxView(expression, root: state.root, reads: reads, nodes: nodes)
            return (
                plan: "<<\(TLAValue.string(state.root)), \(try initializerPlan(nodes, root: state.root))>>",
                view: "<<\(TLAValue.string(state.root)), \(syntax.view)>>",
                origins: syntax.origins, indices: syntax.indices)
        }
        guard !rows.isEmpty else { throw InitialFailureEvidenceError.unsupportedGeneratedOutput }
        return ("<<\(rows.map(\.plan).joined(separator: ", "))>>",
                "<<\(rows.map(\.view).joined(separator: ", "))>>",
                "<<\(rows.map(\.origins).joined(separator: ", "))>>",
                "<<\(rows.map(\.indices).joined(separator: ", "))>>")
    }

    // Keep source-tree identities independent of postorder extraction and repeated subtrees distinct.
    private static func sourceSyntaxView(_ rootExpression: StateExpr, root: String,
                                         reads: Set<String>, nodes: [StraightLineAssignmentCheck.OrderedIntNode]) throws
        -> (view: String, origins: String, indices: String) {
        var expressions = [rootExpression]
        var kinds: [String] = [], literals: [String] = [], names: [String] = []
        var left: [Int] = [], right: [Int] = []
        var index = 0
        while index < expressions.count {
            var literal = "0", name = TLAValue.string(root).description
            var lhs = 0, rhs = 0
            switch expressions[index] {
            case .value(.int(let value)):
                kinds.append("\"literal\""); literal = binaryLiteral(value)
            case .variable(let variable) where reads.contains(variable):
                kinds.append("\"read\""); name = TLAValue.string(variable).description
            case .add(let first, let second):
                kinds.append("\"add\"")
                lhs = expressions.count + 1; rhs = lhs + 1
                expressions.append(first); expressions.append(second)
            default: throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            literals.append(literal); names.append(name)
            left.append(lhs); right.append(rhs)
            index += 1
        }
        // Propose occurrence identities only; the proof checks payloads and ordered children.
        var origins = Array(repeating: 0, count: nodes.count)
        var indices = Array(repeating: 0, count: expressions.count)
        var pending = [(source: 1, emitted: nodes.count)]
        while let (source, emitted) = pending.popLast() {
            guard source > 0, source <= expressions.count, emitted > 0, emitted <= nodes.count,
                  origins[emitted - 1] == 0, indices[source - 1] == 0 else {
                throw InitialFailureEvidenceError.unsupportedGeneratedOutput
            }
            origins[emitted - 1] = source
            indices[source - 1] = emitted
            if case .add(let lhs, let rhs) = nodes[emitted - 1] {
                pending.append((right[source - 1], rhs))
                pending.append((left[source - 1], lhs))
            }
        }
        guard !origins.contains(0), !indices.contains(0) else {
            throw InitialFailureEvidenceError.unsupportedGeneratedOutput
        }
        func tuple(_ values: [String]) -> String { "<<\(values.joined(separator: ", "))>>" }
        let view = "[root |-> 1, kinds |-> \(tuple(kinds)), literals |-> \(tuple(literals)), "
            + "reads |-> \(tuple(names)), left |-> \(tuple(left.map(String.init))), right |-> \(tuple(right.map(String.init)))]"
        return (view, tuple(origins.map(String.init)), tuple(indices.map(String.init)))
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

    private static func proofSource(module: String, tla: String, site: Int,
                                    operands: [Int], before: [NativeInitialBindingOutput],
                                    sourceInitializers: String, sourceSyntaxViews: String,
                                    sourceSyntaxOrigins: String, sourceSyntaxIndices: String, sourceInitialControl: String,
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

        SourcePlanEmission(row) ==
          LET plan == SourceInitializers[row][2]
          IN [count |-> plan.count, height |-> 1, indices |-> <<plan.count>>,
              origins |-> SourceSyntaxOrigins[row],
              nodes |-> [index \\in 1..plan.count |->
                [kind |-> plan.kinds[index],
                 payload |-> IF plan.kinds[index] = "literal" THEN plan.literals[index]
                            ELSE IF plan.kinds[index] = "read" THEN plan.reads[index] ELSE 0,
                 left |-> plan.left[index], right |-> plan.right[index]]]]

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
          PROOF
          <1>. SUFFICES ASSUME NEW row \\in DOMAIN SourceInitializers,
                              NEW state \\in [ProofBoundKeys(row) -> ProofIntMin..ProofIntMax]
                       PROVE /\\ ProofInitialization!Expressions!PartialExpressionPlan(SourceInitializers[row][2].count,
                                      SourceInitializers[row][2].kinds, SourceInitializers[row][2].literals,
                                      SourceInitializers[row][2].reads, SourceInitializers[row][2].left,
                                      SourceInitializers[row][2].right, ProofBoundKeys(row), state)
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
            BY SMT
          <1>. DEFINE plan == SourceInitializers[row][2]
                      bound == ProofBoundKeys(row)
                      view == SourceSyntaxViews[row][2]
                      completed == ProofInitialization!Expressions!CompleteIntBindings(bound, state)
                      emitted == SourcePlanEmission(row)
          <1>. HIDE DEF plan, bound, view, completed, emitted
          <1>0. bound \\subseteq ProofIntSlots
            BY ActualLayoutSuppliesInitializationDecoderInputs, SMT DEF bound, ProofBoundKeys, SourceInitializers, ProofIntKeys
          <1>1. completed \\in [ProofIntSlots -> ProofIntMin..ProofIntMax]
            BY <1>0, ProofIntegerBounds, ProofInitialization!Expressions!CompletingPartialBindingsRetainsEveryBoundValue, SMT
              DEF bound, completed, ProofInitialization!Expressions!IntegerDomain
          <1>1a. ProofIntSlots = {"first", "second", "last"}
            BY ONLY ActualLayoutSuppliesInitializationDecoderInputs, SetExtensionality, SMT
              DEF ProofIntKeys, SourceInitializers
          <1>2. ProofInitialization!Expressions!ExpressionPlan(plan.count, plan.kinds, plan.literals,
                  plan.reads, plan.left, plan.right, completed)
            PROOF
            <2>1. CASE row = 1
              BY ONLY <2>1, <1>1, <1>1a, ProofIntegerBounds, SMT
                DEF plan, SourceInitializers, ProofIntMin, ProofIntMax, ProofInitialization!Expressions!ExpressionPlan
            <2>2. CASE row = 2
              BY ONLY <2>2, <1>1, <1>1a, ProofIntegerBounds, SMT
                DEF plan, SourceInitializers, ProofIntMin, ProofIntMax, ProofInitialization!Expressions!ExpressionPlan
            <2>3. CASE row = 3
              BY ONLY <2>3, <1>1, <1>1a, ProofIntegerBounds, SMT
                DEF plan, SourceInitializers, ProofIntMin, ProofIntMax, ProofInitialization!Expressions!ExpressionPlan
            <2>. QED BY <2>1, <2>2, <2>3, SMT DEF SourceInitializers
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
          <1>6p. /\\ ProofInitialization!Expressions!NodeEmissionArrays(emitted)
                 /\\ emitted.count = plan.count /\\ plan.count > 0 /\\ plan.count \\in Nat
                 /\\ ProofInitialization!Expressions!AllNodePayloadsMatchSource(view, emitted)
                 /\\ {emitted.origins[index] : index \\in 1..emitted.count} = DOMAIN view.kinds
                 /\\ emitted.origins[plan.count] = view.root
                 /\\ SourceInitializers[row][1] \\in ProofIntSlots
                 /\\ ProofInitialization!Expressions!ExtractedNodePlan(emitted, SourceInitializers[row][1]) = plan
                 /\\ SourceSyntaxIndices[row] \\in [DOMAIN view.kinds -> 1..plan.count]
                 /\\ \\A index \\in 1..plan.count : SourceSyntaxIndices[row][emitted.origins[index]] = index
                 /\\ \\A node \\in DOMAIN view.kinds : emitted.origins[SourceSyntaxIndices[row][node]] = node
            PROOF
            <2>1. CASE row = 1
              BY ONLY <2>1, <1>1a, SetExtensionality, SMT
                DEF plan, view, emitted, SourcePlanEmission, SourceInitializers, SourceSyntaxViews,
                    SourceSyntaxOrigins, SourceSyntaxIndices, ProofInitialization!Expressions!NodeEmissionArrays,
                    ProofInitialization!Expressions!AllNodePayloadsMatchSource,
                    ProofInitialization!Expressions!NodePayloadMatchesSource,
                    ProofInitialization!Expressions!ExtractedNodePlan
            <2>2. CASE row = 2
              BY ONLY <2>2, <1>1a, SetExtensionality, SMT
                DEF plan, view, emitted, SourcePlanEmission, SourceInitializers, SourceSyntaxViews,
                    SourceSyntaxOrigins, SourceSyntaxIndices, ProofInitialization!Expressions!NodeEmissionArrays,
                    ProofInitialization!Expressions!AllNodePayloadsMatchSource,
                    ProofInitialization!Expressions!NodePayloadMatchesSource,
                    ProofInitialization!Expressions!ExtractedNodePlan
            <2>3. CASE row = 3
              BY ONLY <2>3, <1>1a, SetExtensionality, SMT
                DEF plan, view, emitted, SourcePlanEmission, SourceInitializers, SourceSyntaxViews,
                    SourceSyntaxOrigins, SourceSyntaxIndices, ProofInitialization!Expressions!NodeEmissionArrays,
                    ProofInitialization!Expressions!AllNodePayloadsMatchSource,
                    ProofInitialization!Expressions!NodePayloadMatchesSource,
                    ProofInitialization!Expressions!ExtractedNodePlan
            <2>. QED BY ONLY <2>1, <2>2, <2>3, SMT DEF SourceInitializers
          <1>6a. \\A history : SourcePlanHistory(plan, state, history) =>
              ProofInitialization!Expressions!SourceSyntaxHistory(view, state,
                [node \\in DOMAIN view.kinds |-> history[SourceSyntaxIndices[row][node]]])
            PROOF
            <2>1. CASE row = 1
              BY ONLY <2>1, SMT DEF plan, view, SourceInitializers, SourceSyntaxViews, SourceSyntaxIndices, SourcePlanHistory,
                ProofInitialization!Expressions!SourceExpressionHistory, ProofInitialization!Expressions!SourceNode,
                ProofInitialization!Expressions!SourceSyntaxHistory
            <2>2. CASE row = 2
              BY ONLY <2>2, SMT DEF plan, view, SourceInitializers, SourceSyntaxViews, SourceSyntaxIndices, SourcePlanHistory,
                ProofInitialization!Expressions!SourceExpressionHistory, ProofInitialization!Expressions!SourceNode,
                ProofInitialization!Expressions!SourceSyntaxHistory
            <2>3. CASE row = 3
              BY ONLY <2>3, SMT DEF plan, view, SourceInitializers, SourceSyntaxViews, SourceSyntaxIndices, SourcePlanHistory,
                ProofInitialization!Expressions!SourceExpressionHistory, ProofInitialization!Expressions!SourceNode,
                ProofInitialization!Expressions!SourceSyntaxHistory
            <2>. QED BY ONLY <2>1, <2>2, <2>3, SMT DEF SourceInitializers
          <1>6b. \\A history, meaning :
              (SourcePlanHistory(plan, state, history)
               /\\ ProofInitialization!Expressions!SourceSyntaxHistory(view, state, meaning))
                => history[plan.count] = meaning[view.root]
            PROOF
            <2>. SUFFICES ASSUME NEW history, NEW meaning,
                                 SourcePlanHistory(plan, state, history),
                                 ProofInitialization!Expressions!SourceSyntaxHistory(view, state, meaning)
                         PROVE history[plan.count] = meaning[view.root]
              BY SMT
            <2>0. /\\ SourcePlanHistory(plan, state, history)
                  /\\ ProofInitialization!Expressions!SourceSyntaxHistory(view, state, meaning)
              BY SMT
            <2>1. /\\ SourcePlanHistory(plan, state,
                         ProofInitialization!Expressions!EmittedSourceSyntaxHistory(emitted, meaning))
                  /\\ ProofInitialization!Expressions!EmittedSourceSyntaxHistory(emitted, meaning)[plan.count]
                         = meaning[view.root]
              BY ONLY <1>6p, <2>0, ProofInitialization!Expressions!MatchedPostorderNodesRetainIndependentSourceSyntaxMeaning, SMT
                DEF SourcePlanHistory
            <2>2. PICK generated : ResolvedPlanHistory(plan, state, generated)
              BY ONLY <1>5, SMT
            <2>3. history[plan.count] = generated[plan.count]
              BY ONLY <1>4, <1>6p, <2>0, <2>2, ProofIntegerBounds,
                ProofInitialization!Expressions!AnyPartialOrderedIntHistoriesPreserveValueAndFailure, SMT
                DEF SourcePlanHistory, ResolvedPlanHistory, ProofInitialization!Expressions!OutcomeAgrees,
                  ProofInitialization!Expressions!IntegerDomain
            <2>4. ProofInitialization!Expressions!EmittedSourceSyntaxHistory(emitted, meaning)[plan.count]
                = generated[plan.count]
              BY ONLY <1>4, <1>6p, <2>1, <2>2, ProofIntegerBounds,
                ProofInitialization!Expressions!AnyPartialOrderedIntHistoriesPreserveValueAndFailure, SMT
                DEF SourcePlanHistory, ResolvedPlanHistory, ProofInitialization!Expressions!OutcomeAgrees,
                  ProofInitialization!Expressions!IntegerDomain
            <2>. QED BY ONLY <2>1, <2>3, <2>4, SMT
          <1>6. \\A history : SourcePlanHistory(plan, state, history) =>
              /\\ \\E meaning : ProofInitialization!Expressions!SourceSyntaxHistory(view, state, meaning)
              /\\ \\A meaning : ProofInitialization!Expressions!SourceSyntaxHistory(view, state, meaning)
                     => history[plan.count] = meaning[view.root]
            BY ONLY <1>6a, <1>6b, SMT
          <1>. QED BY ONLY <1>4, <1>5, <1>6, SourceInitializersMatchLoweredIR, LoweredInitializersMatchResolvedIR, SMT DEF plan, bound, view

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
            <2>. QED BY <2>0, <2>1, <2>2, SMT
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
          <1>1. \\A position \\in ProofIntPositions : \\A prior \\in ProofInitialization!PartialBindings :
                  /\\ ProofInitialization!SourceIntInitializerOutcome(ProofSourceExpressions[position][prior][ProofPlans[position].count])
                       = ProofInitialization!GeneratedIntInitializerOutcome(ProofGeneratedExpressions[position][prior][ProofPlans[position].count])
                  /\\ ProofInitialization!SourceIntInitializerOutcome(ProofSourceExpressions[position][prior][ProofPlans[position].count])
                       \\in ProofInitialization!InitializerOutcomes
            BY <1>0, ActualInitializerExpressionsSupplyTheirParents, ActualLayoutSuppliesInitializationDecoderInputs,
              ProofInitialization!IntExpressionOutcomesSupplyInitializerOutcomes, SMT
              DEF ProofInitialization!Expressions!OutcomeAgrees
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
            <2>2. CASE result.ok
              BY ONLY <2>0, <2>1, <2>2, ActualLayoutSuppliesInitializationDecoderInputs, SMT
                DEF ProofInitialization!Expressions!ExpressionOutcomes, ProofInitialization!SourceIntInitializerOutcome,
                  ProofInitialization!SourceFixed, ProofInitialization!IntInitializationDomains
            <2>3. CASE ~result.ok
              BY ONLY <2>0, <2>1, <2>3, ProofInitialSentinels,
                ActualLayoutSuppliesInitializationDecoderInputs, SMT
                DEF ProofInitialization!Expressions!ExpressionOutcomes, ProofInitialization!SourceIntInitializerOutcome,
                  ProofInitialization!SourceFailed, ProofInitialization!IntInitializationDomains
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
            <2>1a. /\\ ProofNames["first"] = "first" /\\ ProofNames["pc"] = "pc"
                   /\\ ProofNames["second"] = "second"
                   /\\ ProofOrdinalKey(0) = "pc" /\\ ProofOrdinalKey(1) = "first" /\\ ProofOrdinalKey(2) = "second"
              BY ONLY ActualLayoutSuppliesInitializationDecoderInputs, SMT DEF ActualLayout
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
          <1>1c. /\\ ProofSourceRow(2) = 1 /\\ ProofSourceRow(3) = 2 /\\ ProofSourceRow(4) = 3
            BY ONLY <1>0, SMT DEF ProofSourceRow, SourceInitializers
          <1>1b. /\\ ProofPlans[2] = SourceInitializers[1][2]
                 /\\ ProofPlans[3] = SourceInitializers[2][2]
                 /\\ ProofPlans[4] = SourceInitializers[3][2]
            BY ONLY <1>0, <1>1c, SMT DEF ProofPlans
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
          <1>3a. /\\ SourcePlanHistory(SourceInitializers[1][2], ProofReadState(2, ProofObservedPrior(2)),
                         ProofSourceExpressions[2][ProofObservedPrior(2)])
                 /\\ SourcePlanHistory(SourceInitializers[2][2], ProofReadState(3, ProofObservedPrior(3)),
                         ProofSourceExpressions[3][ProofObservedPrior(3)])
                 /\\ SourcePlanHistory(SourceInitializers[3][2], ProofReadState(4, ProofObservedPrior(4)),
                         ProofSourceExpressions[4][ProofObservedPrior(4)])
            BY ONLY <1>0, <1>1b, <1>3, SMT
          <1>4. ProofEvaluate(FALSE)[1][ProofObservedPrior(1)]
              = ProofInitialization!SourceFixed(ProofObservedBefore[ProofOrder[1]])
            BY <1>0, <1>1, <1>2, NativeControlSeedsMatchResolvedIR, SMT
              DEF ProofEvaluate, SourceInitialControl, ProofControlSeed, ActualControlSeeds, ActualInitializationOrder
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
                BY ONLY <1>0, <1>1b, <1>2, <1>3a, SMT
                  DEF SourceInitializers, SourcePlanHistory,
                    ProofInitialization!Expressions!SourceExpressionHistory, ProofInitialization!Expressions!SourceNode
              <3>. QED BY ONLY <2>1, <3>1, <1>0, <1>0a, <1>1, <1>1b, <1>2, SMT
                DEF ProofEvaluate, ProofIntPositions, SourceInitializers,
                  ProofInitialization!SourceIntInitializerOutcome, ProofInitialization!SourceFixed,
                  ProofInitialization!Expressions!Success
            <2>2. CASE position = 3
              <3>0. ProofReadState(3, ProofObservedPrior(3))["first"] = 1
                BY ONLY <1>0, <1>0a, <1>1, ProofIntegerBounds, SetExtensionality, SMT
                  DEF ProofReadState, ProofObservedPrior, ProofPrefixIntNames, ProofPrefixKeys,
                    ProofInitialization!SourceRestriction
              <3>1. ProofSourceExpressions[3][ProofObservedPrior(3)][1] = ProofInitialization!Expressions!Success(1)
                BY ONLY <1>0, <1>1b, <1>2, <1>3a, <3>0, SMT
                  DEF SourceInitializers, SourcePlanHistory,
                    ProofInitialization!Expressions!SourceExpressionHistory, ProofInitialization!Expressions!SourceNode
              <3>2. ProofSourceExpressions[3][ProofObservedPrior(3)][2] = ProofInitialization!Expressions!Success(2)
                BY ONLY <1>0, <1>1b, <1>2, <1>3a, SMT
                  DEF SourceInitializers, SourcePlanHistory,
                    ProofInitialization!Expressions!SourceExpressionHistory, ProofInitialization!Expressions!SourceNode
              <3>3. ProofSourceExpressions[3][ProofObservedPrior(3)][3] = ProofInitialization!Expressions!Success(3)
                BY ONLY <1>0, <1>1b, <1>2, <1>3a, <3>1, <3>2, ProofIntegerBounds, SMT
                  DEF SourceInitializers, SourcePlanHistory,
                    ProofInitialization!Expressions!SourceExpressionHistory, ProofInitialization!Expressions!SourceNode,
                    ProofInitialization!Expressions!SourceCombine, ProofInitialization!Expressions!SourceAdd,
                    ProofInitialization!Expressions!Success, ProofInitialization!Expressions!InRange
              <3>. QED BY ONLY <2>2, <3>3, <1>0, <1>0a, <1>1, <1>1b, <1>2, SMT
                DEF ProofEvaluate, ProofIntPositions, SourceInitializers,
                  ProofInitialization!SourceIntInitializerOutcome, ProofInitialization!SourceFixed,
                  ProofInitialization!Expressions!Success
            <2>. QED BY ONLY <2>1, <2>2, SMT
          <1>6. ProofEvaluate(FALSE)[ProofCount][ProofObservedPrior(ProofCount)]
              = ProofInitialization!SourceFailed(<<"integerOverflow", "addition", <<ExpectedOperand0, ExpectedOperand1>>>>)
            PROOF
            <2>0. ProofReadState(4, ProofObservedPrior(4))["second"] = 3
              BY ONLY <1>0, <1>0a, <1>1, ProofIntegerBounds, SetExtensionality, SMT
                DEF ProofReadState, ProofObservedPrior, ProofPrefixIntNames, ProofPrefixKeys,
                  ProofInitialization!SourceRestriction
            <2>1. ProofSourceExpressions[4][ProofObservedPrior(4)][1] = ProofInitialization!Expressions!Success(3)
              BY ONLY <1>0, <1>1b, <1>2, <1>3a, <2>0, SMT
                DEF SourceInitializers, SourcePlanHistory,
                  ProofInitialization!Expressions!SourceExpressionHistory, ProofInitialization!Expressions!SourceNode
            <2>2. ProofSourceExpressions[4][ProofObservedPrior(4)][2] = ProofInitialization!Expressions!Success(ProofIntMax)
              BY ONLY <1>0, <1>1b, <1>2, <1>3a, SMT
                DEF SourceInitializers, SourcePlanHistory, ProofIntMax,
                  ProofInitialization!Expressions!SourceExpressionHistory, ProofInitialization!Expressions!SourceNode
            <2>3. ProofSourceExpressions[4][ProofObservedPrior(4)][3] = ProofInitialization!Expressions!SourceOverflow(3, ProofIntMax)
              BY ONLY <1>0, <1>1b, <1>2, <1>3a, <2>1, <2>2, ProofIntegerBounds, SMT
                DEF SourceInitializers, SourcePlanHistory,
                  ProofInitialization!Expressions!SourceExpressionHistory, ProofInitialization!Expressions!SourceNode,
                  ProofInitialization!Expressions!SourceCombine, ProofInitialization!Expressions!SourceAdd,
                  ProofInitialization!Expressions!Success, ProofInitialization!Expressions!InRange
            <2>. QED BY ONLY <1>0, <1>0a, <1>1, <1>1b, <1>2, <2>3, SMT
              DEF ProofEvaluate, ProofIntPositions, SourceInitializers,
                ProofInitialization!SourceIntInitializerOutcome, ProofInitialization!SourceFailed,
                ProofInitialization!Expressions!SourceOverflow
          <1>7. /\\ ProofObservedBefore = ProofObservedPrior(ProofCount)
                /\\ ProofObservedBefore \\in [ProofPrefixKeys(ProofCount) -> ProofValues]
            BY ONLY <1>0, <1>1, <1>1a, ProofIntegerBounds, SetExtensionality, SMT
              DEF ProofObservedPrior, ProofPrefixKeys, ProofInitialization!SourceRestriction, ProofValues
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
            BY ONLY <1>0, ActualNativePrefixSuppliesTheSourceInitializerOutcomes,
              SetExtensionality, SMT
              DEF constructed, failure, ProofObservedHistory, ProofObservedPrior,
                ProofPrefixKeys, ProofInitialization!PrefixKeys, ProofObservedResult
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
                  /\\ \\A position \\in ProofIntPositions : \\A prior \\in source[position - 1].states :
                         /\\ \\E meaning : ProofInitialization!Expressions!SourceSyntaxHistory(
                                ProofSyntaxViews[position], ProofInitialization!PartialIntProjection(prior), meaning)
                         /\\ \\A meaning : ProofInitialization!Expressions!SourceSyntaxHistory(
                                ProofSyntaxViews[position], ProofInitialization!PartialIntProjection(prior), meaning)
                                => ProofEvaluate(FALSE)[position][prior] =
                                     ProofInitialization!SourceIntInitializerOutcome(meaning[ProofSyntaxViews[position].root])
            BY ActualPlansInvokeCompleteInitializationAndObservationParents, SMT
              DEF ProofCount, ActualInitializationOrder
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
          <1>5. ProofCount \\in 0..ProofCount
            BY <1>0, SMT DEF ProofInitialization!InitializationOrder
          <1>. WITNESS source, generated, observations
          <1>. QED BY ONLY <1>1, <1>3, <1>4, <1>5, CompleteFailureEvents, InitialFailurePrecedesGraph, SMT
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
