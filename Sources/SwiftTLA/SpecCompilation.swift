import Foundation

/// Identifies the canonical formal interpretation consumed by SwiftTLA tools.
///
/// The identifier is deterministic for one semantic `TLASpec`; it deliberately
/// excludes Swift-only presentation facts such as generated type names.
public struct CompilationIdentity: Sendable, Hashable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public var description: String { value }
}

public struct CompilationDescription: Sendable, Equatable {
    public let identity: CompilationIdentity
    public let variables: [VariableDescription]
    public let actions: [ActionDescription]
    public let procedures: [ProcedureDescription]
    public let controlLocations: [ControlLocationDescription]
    public let imports: [ModuleDescription]
}

public struct VariableDescription: Sendable, Equatable {
    public let name: String
    public let sourceOffset: Int?
}

public struct ActionDescription: Sendable, Equatable {
    public let name: String
    public let sourceOffset: Int?
}

public struct ProcedureDescription: Sendable, Equatable {
    public let algorithm: String
    public let name: String
    public let sourceOffset: Int?
}

public enum ControlOwnerDescription: Sendable, Equatable {
    case sequential(algorithm: String)
    case process(algorithm: String, declarationOrder: Int, typeName: String)
    case procedure(algorithm: String, name: String)
    case generated(algorithm: String, purpose: String)
}

public struct ControlLocationDescription: Sendable, Equatable {
    public let owner: ControlOwnerDescription
    public let sourceName: String
    public let renderedName: String
    public let sourceOffset: Int?
}

public struct ModuleDescription: Sendable, Equatable {
    public let name: String
    public let owningRoot: String
    public let structuralPath: [String]
}

/// The legal direct-module declaration order, resolved before rendering.
public struct DirectModuleSectionPlan: Sendable, Equatable {
    let definitionsBeforeInstances: [DirectModuleDefinition]
    let definitionsAfterInstances: [DirectModuleDefinition]
    let actions: [NamedAction]
    let emittedActionNames: [String: String]
}

/// The point at which a formal specification becomes available to consumers.
///
/// A compiled specification owns the sole semantic `TLASpec` payload. Later
/// pipeline stages can attach validated module and generated-machine plans
/// without reparsing or rebuilding that payload.
public struct CompiledSpecification: Sendable {
    package let spec: TLASpec
    package let formalModuleClosure: FormalModuleClosure
    public let identity: CompilationIdentity
    let layout: CompiledLayout
    let bindings: CompiledBindingTable
    let semantics: CompiledSemantics
    let directModuleSections: DirectModuleSectionPlan
    let authoredPlusCalModule: AuthoredPlusCalModule?

    public var description: CompilationDescription {
        .init(
            identity: identity,
            variables: layout.variables.map {
                .init(name: $0.declaration.name, sourceOffset: $0.declaration.sourceOffset)
            },
            actions: layout.actions.map {
                .init(name: $0.declaration.name, sourceOffset: $0.declaration.sourceOffset)
            },
            procedures: layout.procedures.map {
                .init(
                    algorithm: $0.algorithm,
                    name: $0.name,
                    sourceOffset: $0.sourceOffset
                )
            },
            controlLocations: layout.controlLocations.map {
                .init(
                    owner: $0.owner.description,
                    sourceName: $0.sourceName,
                    renderedName: $0.renderedName,
                    sourceOffset: nil
                )
            },
            imports: formalModuleClosure.entries.map {
                .init(
                    name: $0.module.name,
                    owningRoot: $0.owningRoot,
                    structuralPath: $0.structuralPath
                )
            }
        )
    }

    public func initialStateProjections() throws -> [TLAStateProjection] {
        try CompiledRuntime(compilation: self).initialStates().map {
            try $0.projection(using: layout)
        }
    }

    package func actionID(named name: String) -> ActionID? {
        layout.actionID(named: name)
    }

    package func successors(
        for action: ActionID,
        arguments: [TLAValue],
        from state: TLAStateProjection
    ) throws -> [TLAStateProjection] {
        let formalState = try CompiledState(projection: state, compilation: self)
        return try CompiledRuntime(compilation: self)
            .successors(for: action, from: formalState)
            .filter { $0.arguments == arguments }
            .map { try $0.state.projection(using: layout) }
    }

    package func propertyOutcomes(
        in state: TLAStateProjection
    ) -> [CompiledPropertyOutcome] {
        let runtime = CompiledRuntime(compilation: self)
        let formalState: CompiledState
        do {
            formalState = try CompiledState(projection: state, compilation: self)
        } catch {
            return semantics.invariants.map {
                .evaluationFailed(
                    name: $0.name,
                    diagnostic: .init(code: .evaluationError, message: String(describing: error))
                )
            }
        }
        let invariants = semantics.invariants.map { invariant -> CompiledPropertyOutcome in
            do {
                return try runtime.invariantHolds(invariant, in: formalState)
                    ? .satisfied(name: invariant.name)
                    : .violated(name: invariant.name)
            } catch {
                return .evaluationFailed(
                    name: invariant.name,
                    diagnostic: .init(code: .evaluationError, message: String(describing: error))
                )
            }
        }
        return invariants + semantics.temporalProperties.map {
            .evaluationUnavailable(
                name: $0.name,
                diagnostic: .init(
                    code: .evaluatorUnavailable,
                    message: "Temporal properties require a complete graph evaluation"
                )
            )
        }
    }

    init(
        spec: TLASpec,
        formalModuleClosure: FormalModuleClosure,
        identity: CompilationIdentity,
        layout: CompiledLayout,
        bindings: CompiledBindingTable,
        semantics: CompiledSemantics,
        directModuleSections: DirectModuleSectionPlan,
        authoredPlusCalModule: AuthoredPlusCalModule? = nil
    ) {
        self.spec = spec
        self.formalModuleClosure = formalModuleClosure
        self.identity = identity
        self.layout = layout
        self.bindings = bindings
        self.semantics = semantics
        self.directModuleSections = directModuleSections
        self.authoredPlusCalModule = authoredPlusCalModule
    }

    /// Renders a complete TLA+/CFG bundle from the already-linked closure.
    public func renderedTLAModuleBundle(
        additionalImports: [TLAModuleFile] = []
    ) throws -> TLAModuleBundle {
        let expectedIdentity = spec.compilationFingerprint
        guard identity.value == expectedIdentity,
              formalModuleClosure.root.module.compilationFingerprint == expectedIdentity else {
            throw CompilationDiagnostic(
                code: .compilationIdentityMismatch,
                stage: .rendering,
                path: "compilation.identity",
                expected: expectedIdentity,
                actual: identity.value,
                nextSafeAction: "Compile the current source model again before rendering."
            )
        }

        let entries = formalModuleClosure.entries
        guard let root = entries.last, root.module.name == spec.name else {
            throw CompilationDiagnostic(
                code: .compilationIdentityMismatch,
                stage: .rendering,
                path: "formalModuleClosure.root",
                expected: "the compiled root module '\(spec.name)'",
                actual: entries.last?.module.name ?? "no rendered root module",
                nextSafeAction: "Compile the current source model again before rendering."
            )
        }

        let files = try entries.map { entry in
            let sectionPlan = entry.module.name == spec.name
                ? directModuleSections
                : try entry.module.directModuleSectionPlan(layout: .init(source: entry.module))
            return TLAModuleFile(
                name: entry.module.name,
                tla: entry.module.renderTLAModuleSource(sectionPlan: sectionPlan),
                cfg: entry.module.name == spec.name ? entry.module.renderTLCConfiguration() : nil
            )
        }
        let rootFile = files[files.count - 1]
        let imports = Array(files.dropLast()) + additionalImports
        let bundle: TLAModuleBundle
        if additionalImports.isEmpty {
            bundle = TLAModuleBundle(
                root: rootFile,
                imports: imports,
                provenance: .compiled(
                    identity: identity,
                    ownership: entries.map {
                        .init(
                            moduleName: $0.module.name,
                            owningRoot: $0.owningRoot,
                            structuralPath: $0.structuralPath
                        )
                    }
                )
            )
        } else {
            bundle = .untrusted(root: rootFile, imports: imports)
        }
        try bundle.validateRenderedBundleIntegrity()
        return bundle
    }

    /// Materializes the validated bundle as a new sibling directory.
    ///
    /// Files are written only into an isolated staging directory. The staging
    /// directory becomes visible at `directory` in one rename, so a failed
    /// write or rename cannot leave a partial bundle at the destination.
    public func materializeModuleBundle(to directory: URL) throws {
        let bundle = try renderedTLAModuleBundle()
        let fileManager = FileManager.default
        let parent = directory.deletingLastPathComponent()
        var parentIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory),
              parentIsDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }

        let staging = parent.appendingPathComponent(
            ".\(directory.lastPathComponent).swifttla-staging-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            for file in bundle.files {
                try file.tla.write(
                    to: staging.appendingPathComponent("\(file.name).tla"),
                    atomically: true,
                    encoding: .utf8
                )
                if let cfg = file.cfg {
                    try cfg.write(
                        to: staging.appendingPathComponent("\(file.name).cfg"),
                        atomically: true,
                        encoding: .utf8
                    )
                }
            }
            try Self.writeBundleManifest(bundle, to: staging)
            try fileManager.moveItem(at: staging, to: directory)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private static func writeBundleManifest(_ bundle: TLAModuleBundle, to directory: URL) throws {
        struct Manifest: Encodable {
            let compilationIdentity: String
            let ownership: [TLAModuleBundle.OwnershipEntry]
        }
        guard case let .compiled(identity, ownership) = bundle.provenance else {
            throw CompilationDiagnostic(
                code: .compilationIdentityMismatch,
                stage: .rendering,
                path: "bundle.compilationIdentity",
                expected: "a compiler-produced bundle identity",
                actual: "no identity",
                nextSafeAction: "Render through a compiled specification."
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(
            Manifest(compilationIdentity: identity.value, ownership: ownership)
        )
        try data.write(to: directory.appendingPathComponent("bundle-manifest.json"), options: .atomic)
    }

    /// Renders the one source-faithful PlusCal module from this compilation.
    ///
    /// The bundle keeps the same linked imports and configuration as direct
    /// TLA+ export. It is the only supported PlusCal export path: callers do
    /// not reconstruct a second bundle around renderer strings.
    public func renderedPlusCalBundle(
        additionalImports: [TLAModuleFile] = []
    ) throws -> TLAModuleBundle {
        guard let authoredPlusCalModule else {
            throw AlgorithmPlusCalRenderDiagnostic(
                failedConcept: "authored PlusCal module root",
                path: "TLASpec.sourceAlgorithms",
                expected: "exactly one authored Algorithm",
                actual: "\(spec.sourceAlgorithms.count) authored Algorithms",
                nextSafeAction: "Compile one canonical Algorithm model per exported module."
            )
        }
        let directBundle = try renderedTLAModuleBundle(additionalImports: additionalImports)
        let root = TLAModuleFile(
            name: directBundle.root.name,
            tla: try AlgorithmPlusCalRenderer(model: authoredPlusCalModule.algorithm).render(authoredPlusCalModule),
            cfg: directBundle.root.cfg
        )
        let bundle: TLAModuleBundle
        switch directBundle.provenance {
        case .compiled(let identity, let ownership):
            bundle = TLAModuleBundle(
                root: root,
                imports: directBundle.imports,
                provenance: .compiled(identity: identity, ownership: ownership)
            )
        case .untrusted:
            bundle = .untrusted(root: root, imports: directBundle.imports)
        }
        try bundle.validateRenderedBundleIntegrity()
        return bundle
    }
}

/// A blocking, inspection-ready compiler failure.
public struct CompilationDiagnostic: Error, Sendable, Hashable, CustomStringConvertible {
    public enum Stage: String, Sendable, Hashable {
        case validation
        case lowering
        case binding
        case runtime
        case checking
        case rendering
        case linking
    }

    public enum Code: String, Sendable, Hashable {
        case emptySpecificationName
        case duplicateVariable
        case duplicateAction
        case duplicateInvariant
        case duplicateRecordField
        case compilationIdentityMismatch
        case cyclicFormalModule
        case conflictingFormalModuleSource
        case duplicateFormalModuleImport
        case invalidFormalModuleInstanceNamespace
        case duplicateFormalModuleInstanceNamespace
        case missingFormalModuleConfigurationTarget
        case duplicateFormalModuleConfiguration
        case duplicateFormalModuleReplacement
        case invalidFormalModuleArgument
        case duplicateFormalModuleArgument
        case duplicateFormalModuleSymbol
        case invalidFormalModuleParameter
        case duplicateFormalModuleParameter
        case unresolvedFormalModuleReplacement
        case unresolvedDirectModuleDependency
        case cyclicDirectModuleDependency
        case duplicateDirectModuleDefinition
        case unknownControlLocation
        case unknownReference
        case outOfScopeReference
        case assignmentToBinder
        case duplicateBinder
        case unresolvedImportedSymbol
    }

    public enum ChangeStatus: String, Sendable, Hashable {
        case noCompiledOutcome
    }

    public let code: Code
    public let stage: Stage
    public let path: String
    public let expected: String
    public let actual: String
    public let changeStatus: ChangeStatus
    public let nextSafeAction: String

    public init(
        code: Code,
        stage: Stage,
        path: String,
        expected: String,
        actual: String,
        nextSafeAction: String
    ) {
        self.code = code
        self.stage = stage
        self.path = path
        self.expected = expected
        self.actual = actual
        self.changeStatus = .noCompiledOutcome
        self.nextSafeAction = nextSafeAction
    }

    public var description: String {
        "Compilation failed [\(code.rawValue)] at \(stage.rawValue) \(path). "
            + "Expected: \(expected). Actual: \(actual). "
            + "Change status: \(changeStatus.rawValue). Next safe action: \(nextSafeAction)"
    }
}

public extension SpecParser.ParsedSpecComponents {
    /// Compiles parser output and generated-machine type facts.
    func compile(
        specificationName: String,
        additionalInvariants: [NamedInvariant] = []
    ) throws -> CompiledSpecification {
        let spec = TLASpec(
            name: specificationName,
            variables: variables.map(\.formal),
            constants: constants,
            formalParameters: formalParameters,
            actions: actions.map {
                NamedAction(name: $0.name, body: $0.body, bindings: $0.bindings)
            },
            invariants: invariants.map { NamedInvariant(name: $0.name, body: $0.body) } + additionalInvariants,
            temporalProperties: temporal.map { NamedTemporal(name: $0.name, expr: $0.expr) },
            fairness: fairness,
            definitions: definitions,
            constraint: constraint,
            formalOperatorDefinitions: formalOperatorDefinitions,
            imports: imports,
            importConfigurations: importConfigurations,
            moduleInstances: moduleInstances,
            symmetrySets: symmetrySets,
            symmetricCollections: symmetricCollections.map(\.declaration),
            algorithmFidelityTokens: algorithmFidelityTokens,
            sourceAlgorithms: sourceAlgorithms,
            authoredPlusCalDeclarations: authoredPlusCalDeclarations
        )
        return try spec.compile()
    }
}

public extension TLASpec {
    /// Validates and identifies this specification before it reaches a formal
    /// consumer. Structural module linking is added to this gate by the linker.
    func compile() throws -> CompiledSpecification {
        try loweredSourceModel().compileLowered()
    }

    private func compileLowered() throws -> CompiledSpecification {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CompilationDiagnostic(
                code: .emptySpecificationName,
                stage: .validation,
                path: "specification.name",
                expected: "a non-empty specification name",
                actual: name,
                nextSafeAction: "Give the specification a stable name, then compile again."
            )
        }

        try validateUnique(variables.map(\.name), code: .duplicateVariable, path: "variables")
        try validateUnique(actions.map(\.name), code: .duplicateAction, path: "actions")
        try validateUnique(invariants.map(\.name), code: .duplicateInvariant, path: "invariants")
        let closure = try FormalModuleClosure.resolve(root: self)
        let layout = CompiledLayout(spec: self, closure: closure)
        var validator = BindingValidator(spec: self, layout: layout, closure: closure)
        let bindings = try validator.validate(spec: self)
        let semantics = try CompiledLowerer(bindings: bindings, closure: closure, layout: layout).lower(spec: self)
        let directModuleSections = try directModuleSectionPlan(layout: layout)
        let authoredPlusCalModule = try authoredPlusCalModule()
        return CompiledSpecification(
            spec: self,
            formalModuleClosure: closure,
            identity: .init(value: compilationFingerprint),
            layout: layout,
            bindings: bindings,
            semantics: semantics,
            directModuleSections: directModuleSections,
            authoredPlusCalModule: authoredPlusCalModule
        )
    }

    internal func directModuleSectionPlan(layout: CompiledLayout) throws -> DirectModuleSectionPlan {
        let explicitDefinitions = definitions
        let explicitNames = Set(explicitDefinitions.compactMap(\.name))
        let formalDefinitions = formalOperatorDefinitions
            .filter { !explicitNames.contains($0.name) }
            .map {
                DirectModuleDefinition(
                    name: $0.name,
                    text: FormalOperatorDecl($0).tlaText,
                    dependencies: $0.plusCalDependencies
                )
            }
        let allDefinitions = explicitDefinitions + formalDefinitions
        try validateUnique(
            allDefinitions.compactMap(\.name),
            code: .duplicateDirectModuleDefinition,
            path: "definitions"
        )
        let instanceNames = Set(moduleInstances.map(\.name))
        let declaredNames = instanceNames
            .union(allDefinitions.compactMap(\.name))
        for definition in allDefinitions {
            for dependency in definition.dependencies where !declaredNames.contains(dependency) {
                throw CompilationDiagnostic(
                    code: .unresolvedDirectModuleDependency,
                    stage: .linking,
                    path: "definitions.\(definition.name ?? definition.text).dependencies.\(dependency)",
                    expected: "a definition or INSTANCE declared by this module",
                    actual: "no declaration named '\(dependency)'",
                    nextSafeAction: "Declare the dependency or remove it from dependsOn, then compile again."
                )
            }
        }
        let definitionsBeforeInstances = allDefinitions.filter {
            instanceNames.isDisjoint(with: $0.dependencies)
        }
        let definitionsAfterInstances = allDefinitions.filter {
            !instanceNames.isDisjoint(with: $0.dependencies)
        }
        let renderedControlNames = layout.directActionNames(actions: actions)
        let emittedActionNames = tlaActionNames(actions, preferredNames: renderedControlNames)
        return DirectModuleSectionPlan(
            definitionsBeforeInstances: try orderDirectDefinitions(
                definitionsBeforeInstances,
                declared: []
            ),
            definitionsAfterInstances: try orderDirectDefinitions(
                definitionsAfterInstances,
                declared: Set(definitionsBeforeInstances.compactMap(\.name)).union(instanceNames)
            ),
            actions: actions.map {
                .init(
                    name: $0.name,
                    body: renderControlReferences(in: $0.body, visibleNames: renderedControlNames),
                    bindings: $0.bindings
                )
            },
            emittedActionNames: emittedActionNames
        )
    }

    private func orderDirectDefinitions(
        _ definitions: [DirectModuleDefinition],
        declared: Set<String>
    ) throws -> [DirectModuleDefinition] {
        var pending = definitions
        var emitted = declared
        var ordered: [DirectModuleDefinition] = []
        while let index = pending.firstIndex(where: { definition in
            definition.dependencies.allSatisfy(emitted.contains)
        }) {
            let definition = pending.remove(at: index)
            ordered.append(definition)
            if let name = definition.name {
                emitted.insert(name)
            }
        }
        guard pending.isEmpty else {
            throw CompilationDiagnostic(
                code: .cyclicDirectModuleDependency,
                stage: .linking,
                path: "definitions",
                expected: "an acyclic declaration dependency graph",
                actual: pending.compactMap(\.name).joined(separator: ", "),
                nextSafeAction: "Break the declaration cycle, then compile again."
            )
        }
        return ordered
    }

    private func validateUnique(
        _ names: [String],
        code: CompilationDiagnostic.Code,
        path: String
    ) throws {
        var seen: Set<String> = []
        for name in names where !seen.insert(name).inserted {
            throw CompilationDiagnostic(
                code: code,
                stage: .validation,
                path: "\(path).\(name)",
                expected: "one declaration named '\(name)'",
                actual: "multiple declarations named '\(name)'",
                nextSafeAction: "Rename or remove the duplicate declaration, then compile again."
            )
        }
    }

    var compilationFingerprint: String {
        var encoder = CanonicalSpecificationEncoder()
        let source = encoder.encode(self)
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in source.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

private func tlaActionNames(
    _ actions: [NamedAction],
    preferredNames: [String: String] = [:]
) -> [String: String] {
    var emitted: [String: String] = [:]
    var used: Set<String> = []
    for action in actions where emitted[action.name] == nil {
        let raw = (preferredNames[action.name] ?? action.name).unicodeScalars.map { scalar -> String in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 95: String(scalar)
            default: "_"
            }
        }.joined()
        let stem = raw.first?.isNumber == true ? "_\(raw)" : raw
        var candidate = stem.isEmpty ? "Action" : stem
        var suffix = 2
        while used.contains(candidate) {
            candidate = "\(stem)__\(suffix)"
            suffix += 1
        }
        emitted[action.name] = candidate
        used.insert(candidate)
    }
    return emitted
}

private extension CompiledLayout {
    func directActionNames(actions: [NamedAction]) -> [String: String] {
    let actionNames = Set(actions.map(\.name))
    let candidates = controlLocations.compactMap { label -> (qualified: String, label: String)? in
        guard case .procedure = label.owner else { return nil }
        return (qualified: label.renderedName, label: label.sourceName)
    }

    let labelCounts = Dictionary(grouping: candidates, by: { $0.label }).mapValues { $0.count }
    let unqualifiedActions = Set(actions.map(\.name)).subtracting(Set(candidates.map { $0.qualified }))
    let usable = candidates.filter {
        actionNames.contains($0.qualified)
            && labelCounts[$0.label] == 1
            && !unqualifiedActions.contains($0.label)
    }
    return Dictionary(uniqueKeysWithValues: usable.map { ($0.qualified, $0.label) })
    }
}

private func renderControlReferences(
    in action: ActionExpr,
    visibleNames: [String: String]
) -> ActionExpr {
    func controlValue(_ expression: StateExpr) -> StateExpr {
        switch expression {
        case .value(.string(let value)):
            return .value(.string(visibleNames[value] ?? value))
        case .except(let function, let key, let value):
            return .except(function, key, controlValue(value))
        case .tupleLiteral(let values):
            return .tupleLiteral(values.map(controlValue))
        case .tupleConcatenate(let lhs, let rhs):
            return .tupleConcatenate(controlValue(lhs), controlValue(rhs))
        case .recordLiteral(let fields):
            return .recordLiteral(.init(fields.fields.map { .init(name: $0.name, value: controlValue($0.value)) }))
        default:
            return expression
        }
    }

    func isControlReference(_ expression: StateExpr) -> Bool {
        switch expression {
        case .variable("pc"), .functionApply(.variable("pc"), _):
            return true
        default:
            return false
        }
    }

    func controlGuard(_ expression: StateExpr) -> StateExpr {
        switch expression {
        case .equal(let lhs, let rhs) where isControlReference(lhs):
            return .equal(lhs, controlValue(rhs))
        case .equal(let lhs, let rhs) where isControlReference(rhs):
            return .equal(controlValue(lhs), rhs)
        case .notEqual(let lhs, let rhs) where isControlReference(lhs):
            return .notEqual(lhs, controlValue(rhs))
        case .notEqual(let lhs, let rhs) where isControlReference(rhs):
            return .notEqual(controlValue(lhs), rhs)
        default:
            return expression
        }
    }

    switch action {
    case .assign(let name, let value):
        return .assign(name, name == "pc" || name == "stack" ? controlValue(value) : value)
    case .unchanged, .chooseAction:
        return action
    case .guard_(let condition):
        return .guard_(controlGuard(condition))
    case .existsAction(let name, let set, let body):
        return .existsAction(name, set, renderControlReferences(in: body, visibleNames: visibleNames))
    case .ifElse(let condition, let then, let otherwise):
        return .ifElse(controlGuard(condition), renderControlReferences(in: then, visibleNames: visibleNames), renderControlReferences(in: otherwise, visibleNames: visibleNames))
    case .define(let name, let value, let body):
        return .define(name, value, renderControlReferences(in: body, visibleNames: visibleNames))
    case .and(let lhs, let rhs):
        return .and(renderControlReferences(in: lhs, visibleNames: visibleNames), renderControlReferences(in: rhs, visibleNames: visibleNames))
    case .or(let lhs, let rhs):
        return .or(renderControlReferences(in: lhs, visibleNames: visibleNames), renderControlReferences(in: rhs, visibleNames: visibleNames))
    }
}

/// Canonicalizes formal data with unambiguous field boundaries.
///
/// Do not substitute a display description here. The encoder deliberately
/// visits fields which presentation APIs omit, including action domains,
/// all initialisation forms, and the recursive contents of imported modules.
private struct CanonicalSpecificationEncoder {
    private var output = ""

    mutating func encode(_ spec: TLASpec) -> String {
        specification(spec)
        return output
    }

    private mutating func field(_ name: String, _ value: String) {
        output += "\(name.utf8.count):\(name)\(value.utf8.count):\(value)"
    }

    private mutating func list<T>(_ name: String, _ values: [T], _ encode: (T) -> String) {
        field("\(name).count", String(values.count))
        for (index, value) in values.enumerated() {
            field("\(name)[\(index)]", encode(value))
        }
    }

    private mutating func specification(_ spec: TLASpec) {
        field("spec.name", spec.name)
        field("declarationLayout", CompiledLayout(source: spec).canonicalEncoding)
        list("variables", spec.variables, canonicalVariable)
        let constants = spec.constants.sorted { $0.name < $1.name }.map {
            node("constant", [$0.name, canonicalValue($0.value)])
        }
        list("constants", constants) { $0 }
        let formalParameters = spec.formalParameters.map {
            node("formal-parameter", [$0.name, $0.kind.rawValue])
        }
        list("formalParameters", formalParameters) { $0 }
        list("actions", spec.actions, canonicalAction)
        let invariants = spec.invariants.map {
            node("invariant", [$0.name, canonicalExpression($0.body)])
        }
        list("invariants", invariants) { $0 }
        let temporalProperties = spec.temporalProperties.map {
            node("temporal", [$0.name, canonicalTemporal($0.expr)])
        }
        list("temporal", temporalProperties) { $0 }
        list("fairness", spec.fairness, canonicalFairness)
        field("assume", canonicalOptional(spec.assume.map(canonicalExpression)))
        field("checkDeadlock", node("bool", [String(spec.checkDeadlock)]))
        let definitions = spec.definitions.map {
            node("definition", [
                canonicalOptional($0.name),
                $0.text,
                canonicalList($0.dependencies)
            ])
        }
        list("definitions", definitions) { $0 }
        list("theorems", spec.theorems) { $0 }
        field("extendsModules", spec.extendsModules)
        field("constraint", canonicalOptional(spec.constraint.map(canonicalExpression)))
        list("recursiveDefs", spec.recursiveDefs) { $0 }
        let recursiveFunctions = spec.recursiveFuncs.map {
            node("recursive-function", [$0.name, canonicalList($0.params), canonicalExpression($0.body)])
        }
        list("recursiveFuncs", recursiveFunctions) { $0 }
        let formalOperators = spec.formalOperatorDefinitions.map {
            node("operator-definition", [$0.name, canonicalList($0.parameters.map(canonicalFormalParameter)), canonicalExpression($0.body)])
        }
        list("formalOperators", formalOperators) { $0 }
        list("imports", spec.imports) { imported in
            var nested = CanonicalSpecificationEncoder()
            return nested.encode(imported)
        }
        let importConfigurations = spec.importConfigurations.map { configuration in
            node("import-configuration", [
                configuration.moduleName,
                canonicalList(configuration.replacements.map {
                    node("replacement", [$0.operatorName, $0.definitionName, canonicalExpression($0.expression)])
                })
            ])
        }
        list("importConfigurations", importConfigurations) { $0 }
        let moduleInstances = spec.moduleInstances.map { instance in
            var nested = CanonicalSpecificationEncoder()
            return node("module-instance", [
                instance.name,
                nested.encode(instance.module),
                canonicalList(instance.arguments.map {
                    node("instance-argument", [$0.parameter, canonicalExpression($0.value)])
                })
            ])
        }
        list("moduleInstances", moduleInstances) { $0 }
        let symmetrySets = spec.symmetrySets.map { set in
            node("symmetry-set", [set.variableName, canonicalList(set.values.map(canonicalValue).sorted())])
        }
        list("symmetrySets", symmetrySets) { $0 }
        let symmetricCollections = spec.symmetricCollections.map {
            node("symmetric-collection", [$0.name, String($0.verificationScope), canonicalValue($0.initial)])
        }
        list("symmetricCollections", symmetricCollections) { $0 }
        list("algorithmTokens", spec.algorithmFidelityTokens) { $0.encodedCanonicalForm }
    }

    private func canonicalVariable(_ variable: NamedVar) -> String {
        let collection: String
        switch variable.collectionType {
        case .scalar: collection = node("scalar-collection", [])
        case .set: collection = node("set-collection", [])
        case .array(let scope): collection = node("array-collection", [String(scope)])
        case .dictionary(let scope): collection = node("dictionary-collection", [String(scope)])
        }
        return node("variable", [
            variable.name,
            canonicalValue(variable.initial),
            canonicalOptional(variable.initialSet.map(canonicalExpression)),
            canonicalOptional(variable.initExpr.map(canonicalExpression)),
            canonicalOptional(variable.lazySet.map(canonicalExpression)),
            collection
        ])
    }

    private func canonicalAction(_ action: NamedAction) -> String {
        node("action", [
            action.name,
            canonicalActionExpression(action.body),
            canonicalList(action.bindings.map {
                node("action-binding", [$0.name, canonicalList($0.values.map(canonicalValue))])
            })
        ])
    }

    private func canonicalValue(_ value: TLAValue) -> String {
        switch value {
        case .int(let value): return node("int", [String(value)])
        case .bool(let value): return node("bool", [String(value)])
        case .string(let value): return node("string", [value])
        case .constant(let value): return node("constant", [value])
        case .set(let values): return node("set", [canonicalList(values.map(canonicalValue).sorted())])
        case .tuple(let values): return node("tuple", [canonicalList(values.map(canonicalValue))])
        case .record(let values):
            return node("record", [canonicalList(values.fields.map {
                node("record-entry", [$0.name, canonicalValue($0.value)])
            })])
        case .function(let values):
            return node("function", [canonicalList(values.map {
                node("function-entry", [canonicalValue($0.key), canonicalValue($0.value)])
            }.sorted())])
        }
    }

    private func canonicalExpression(_ expression: StateExpr) -> String {
        node("expression", [alphaKey(expression)])
    }

    private func canonicalActionExpression(_ expression: ActionExpr) -> String {
        node("action", [alphaKey(expression)])
    }

    private func canonicalTemporal(_ expression: TemporalExpr) -> String {
        node("temporal", [alphaKey(expression)])
    }

    private func canonicalFairness(_ value: FairnessCondition) -> String {
        switch value {
        case .weakFairness(let action): return node("weakFairness", [action])
        case .strongFairness(let action): return node("strongFairness", [action])
        case .weakFairnessActionCall(let action): return node("weakFairnessActionCall", [canonicalActionCall(action)])
        case .strongFairnessActionCall(let action): return node("strongFairnessActionCall", [canonicalActionCall(action)])
        }
    }

    private func canonicalFormalParameter(_ value: FormalParameter) -> String {
        switch value {
        case .value(let name): return node("valueParameter", [name])
        case .operator(let name, let arity): return node("operatorParameter", [name, String(arity)])
        }
    }
    private func canonicalActionCall(_ value: FormalActionCall) -> String { node("actionCall", [value.name, canonicalList(value.arguments.map(canonicalValue))]) }
    private func canonicalList(_ values: [String]) -> String { node("list", values) }
    private func canonicalOptional(_ value: String?) -> String {
        value.map { node("some", [$0]) } ?? node("none", [])
    }
    private func node(_ tag: String, _ fields: [String]) -> String {
        ([tag, String(fields.count)] + fields).map { "\($0.utf8.count):\($0)" }.joined()
    }
}
