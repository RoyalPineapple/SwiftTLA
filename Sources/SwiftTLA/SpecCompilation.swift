import Foundation
import CryptoKit

private func isTLAModuleIdentifier(_ name: String) -> Bool {
    func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    guard let first = name.unicodeScalars.first, first == "_" || isLetter(first) else { return false }
    return name.unicodeScalars.dropFirst().allSatisfy {
        $0 == "_" || isLetter($0) || (48...57).contains($0.value)
    }
}

/// Identifies one canonical compiled specification.
public struct CompilationIdentity: Sendable, Hashable, CustomStringConvertible {
    public let value: String

    init(value: String) {
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
    public let renderedName: String
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
struct DirectModuleSectionPlan: Sendable, Equatable {
    let renderedModuleSource: String
    let renderedConfiguration: String
}

struct DirectModuleAction: Sendable, Equatable {
    let declaration: NamedAction
    let renderedName: String
    let renderedParameters: [String]
    let renderedBody: String
}

struct CompiledRefinement: Sendable {
    let name: String
    let instance: ModuleInstanceID
    let `operator`: RefinementDecl.Operator
    let abstract: CompiledSpecification
    let variableMappings: [CompiledStateExpr]
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
    let refinements: [CompiledRefinement]
    let moduleSectionPlans: [String: DirectModuleSectionPlan]
    let authoredPlusCalModule: AuthoredPlusCalModule?

    public var description: CompilationDescription {
        .init(
            identity: identity,
            variables: layout.variables.map {
                .init(name: $0.declaration.name, sourceOffset: $0.declaration.sourceOffset)
            },
            actions: layout.actions.map {
                .init(
                    name: $0.declaration.name,
                    renderedName: $0.renderedName,
                    sourceOffset: $0.declaration.sourceOffset
                )
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

    package func initialStateProjections() throws -> [TLAStateProjection] {
        try CompiledRuntime(compilation: self).initialStates().map {
            try $0.projection(using: layout)
        }
    }

    package func actionID(named name: String) -> ActionID? {
        layout.actionID(named: name)
    }

    package func actionRequest(
        ordinal: Int,
        formalArguments: [TLAValue]
    ) throws -> CompiledActionRequest {
        guard layout.actions.indices.contains(ordinal) else {
            throw GeneratedMachineError.noMatchingSuccessor
        }
        return try actionRequest(
            action: layout.actions[ordinal].id,
            formalArguments: formalArguments
        )
    }

    func actionRequest(
        action: ActionID,
        formalArguments: [TLAValue]
    ) throws -> CompiledActionRequest {
        guard semantics.actions.contains(where: { $0.id == action }) else {
            throw GeneratedMachineError.noMatchingSuccessor
        }
        return .init(
            action: action,
            arguments: try formalArguments.map { try .init(formal: $0, using: layout) }
        )
    }

    func matches(_ arguments: [CompiledValue], request: CompiledActionRequest) -> Bool {
        arguments == request.arguments
    }

    package func generatedActionLabelInput(
        for request: CompiledActionRequest
    ) throws -> (ordinal: Int, formalArguments: [TLAValue]) {
        guard let action = layout.actions.first(where: { $0.id == request.action }) else {
            throw GeneratedMachineError.noMatchingSuccessor
        }
        return (
            ordinal: action.id.ordinal,
            formalArguments: try request.arguments.map { try $0.rendered(using: layout) }
        )
    }

    package func successors(
        for action: ActionID,
        arguments: [TLAValue],
        from state: TLAStateProjection
    ) throws -> [TLAStateProjection] {
        let formalState = try CompiledState(projection: state, compilation: self)
        return try CompiledRuntime(compilation: self)
            .successors(for: action, from: formalState)
            .filter { try $0.arguments.map { try $0.rendered(using: layout) } == arguments }
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
        refinements: [CompiledRefinement],
        moduleSectionPlans: [String: DirectModuleSectionPlan],
        authoredPlusCalModule: AuthoredPlusCalModule? = nil
    ) {
        self.spec = spec
        self.formalModuleClosure = formalModuleClosure
        self.identity = identity
        self.layout = layout
        self.bindings = bindings
        self.semantics = semantics
        self.refinements = refinements
        self.moduleSectionPlans = moduleSectionPlans
        self.authoredPlusCalModule = authoredPlusCalModule
    }

    /// Renders a complete TLA+/CFG bundle from the already-linked closure.
    public func renderedTLAModuleBundle() throws -> TLAModuleBundle {
        let entries = formalModuleClosure.entries
        let files = try entries.map { entry in
            guard let sectionPlan = moduleSectionPlans[entry.module.name] else {
                throw CompilationDiagnostic(
                    code: .compilationIdentityMismatch,
                    stage: .rendering,
                    path: "formalModuleClosure.\(entry.module.name)",
                    expected: "a compiled module section plan",
                    actual: "no module section plan",
                    nextSafeAction: "Compile the source model again."
                )
            }
            return TLAModuleFile(
                name: entry.module.name,
                tla: sectionPlan.renderedModuleSource,
                cfg: entry.module.name == spec.name
                    ? sectionPlan.renderedConfiguration
                    : nil
            )
        }
        guard let rootFile = files.last else {
            throw CompilationDiagnostic(
                code: .compilationIdentityMismatch,
                stage: .rendering,
                path: "formalModuleClosure",
                expected: "a root module",
                actual: "an empty module closure",
                nextSafeAction: "Compile the source model again."
            )
        }
        let bundle = TLAModuleBundle(
            root: rootFile,
            imports: Array(files.dropLast()),
            provenance: .compiled(
                identity: identity,
                ownership: entries.map {
                    .init(
                        moduleName: $0.module.name,
                        owningRoot: $0.owningRoot,
                        structuralPath: $0.structuralPath
                    )
                },
                dependencies: formalModuleClosure.edges.map {
                    .init(
                        importingModule: $0.fromModule,
                        importedModule: $0.toModule,
                        structuralPath: $0.structuralPath
                    )
                }
            )
        )
        try bundle.validateDeclaredClosure()
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
            let dependencies: [TLAModuleBundle.ModuleDependency]
        }
        guard case let .compiled(identity, ownership, dependencies) = bundle.provenance else {
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
            Manifest(
                compilationIdentity: identity.value,
                ownership: ownership,
                dependencies: dependencies
            )
        )
        try data.write(to: directory.appendingPathComponent("bundle-manifest.json"), options: .atomic)
    }

    /// Renders the one source-faithful PlusCal module from this compilation.
    ///
    /// The bundle keeps the same linked imports and configuration as direct
    /// TLA+ export. It is the only supported PlusCal export path: callers do
    /// not reconstruct a second bundle around renderer strings.
    public func renderedPlusCalBundle() throws -> TLAModuleBundle {
        guard let authoredPlusCalModule else {
            throw AlgorithmPlusCalRenderDiagnostic(
                failedConcept: "authored PlusCal module root",
                path: "TLASpec.sourceAlgorithms",
                expected: "exactly one authored Algorithm",
                actual: "\(spec.sourceAlgorithms.count) authored Algorithms",
                nextSafeAction: "Compile one canonical Algorithm model per exported module."
            )
        }
        let directBundle = try renderedTLAModuleBundle()
        let root = TLAModuleFile(
            name: directBundle.root.name,
            tla: try AlgorithmPlusCalRenderer(module: authoredPlusCalModule).render(),
            cfg: directBundle.root.cfg
        )
        let bundle = TLAModuleBundle(
            root: root,
            imports: directBundle.imports,
            provenance: directBundle.provenance
        )
        try bundle.validateDeclaredClosure()
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
        case invalidTypedRecordField
        case invalidTypedRecordLiteral
        case invalidTypedFunctionLiteral
        case invalidStaticSelection
        case invalidSequenceElementDomain
        case invalidSequenceLength
        case invalidFiniteDomain
        case invalidFiniteDomainValue
        case invalidActionBinding
        case invalidFormalDeclaration
        case invalidSymmetricMember
        case emptySpecificationName
        case invalidSpecificationName
        case duplicateVariable
        case duplicateAction
        case duplicateInvariant
        case invalidSymmetricCollection
        case duplicateRecordField
        case compilationIdentityMismatch
        case emptyFormalModuleClosure
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
        case invalidRefinementName
        case duplicateRefinement
        case unresolvedRefinementInstance
        case unresolvedRefinementTarget
        case duplicateRefinementMapping
        case incompleteRefinementMapping
        case unknownRefinementMappingTarget
        case invalidRefinementParameterMapping
        case unsupportedRefinementTarget
        case stateDependentRefinementParameter
        case invalidFormalModuleParameter
        case duplicateFormalModuleParameter
        case unresolvedFormalModuleReplacement
        case unresolvedDirectModuleDependency
        case cyclicDirectModuleDependency
        case duplicateRenderedModuleDefinition
        case unknownControlLocation
        case unknownReference
        case outOfScopeReference
        case assignmentToBinder
        case duplicateBinder
        case unresolvedImportedSymbol
    }

    public let code: Code
    public let stage: Stage
    public let path: String
    public let expected: String
    public let actual: String
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
        self.nextSafeAction = nextSafeAction
    }

    public var description: String {
        "Compilation failed [\(code.rawValue)] at \(stage.rawValue) \(path). "
            + "Expected: \(expected). Actual: \(actual). "
            + "Next safe action: \(nextSafeAction)"
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
            constraint: constraint,
            formalOperatorDefinitions: formalOperatorDefinitions,
            imports: imports,
            importConfigurations: importConfigurations,
            moduleInstances: moduleInstances,
            refinements: refinements,
            symmetrySets: symmetrySets,
            symmetricCollections: symmetricCollections.map(\.declaration),
            algorithmFidelityTokens: algorithmFidelityTokens,
            sourceAlgorithms: sourceAlgorithms
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
        guard isTLAModuleIdentifier(name) else {
            throw CompilationDiagnostic(
                code: .invalidSpecificationName,
                stage: .validation,
                path: "specification.name",
                expected: "a TLA+ module identifier",
                actual: name,
                nextSafeAction: "Use letters, digits, and underscores, beginning with a letter or underscore."
            )
        }

        try validateUnique(variables.map(\.name), code: .duplicateVariable, path: "variables")
        try validateUnique(actions.map(\.name), code: .duplicateAction, path: "actions")
        try validateUnique(invariants.map(\.name), code: .duplicateInvariant, path: "invariants")
        try validateSymmetricCollectionDeclarations()
        try validateRefinements()
        let closure = try FormalModuleClosure.resolve(root: self)
        let layout = CompiledLayout(spec: self, closure: closure)
        var validator = BindingValidator(spec: self, layout: layout, closure: closure)
        _ = try validator.validate(spec: self)
        try validator.validateRefinementMappings(refinements)
        let bindings = validator.bindingTable()
        let semantics = try CompiledLowerer(bindings: bindings, closure: closure, layout: layout).lower(spec: self)
        let compiledRefinements = try compiledRefinements(bindings: bindings, closure: closure, layout: layout)
        let directModuleSections = try directModuleSectionPlan(
            layout: layout,
            bindings: bindings,
            semantics: semantics,
            refinements: compiledRefinements
        )
        var moduleSectionPlans: [String: DirectModuleSectionPlan] = [:]
        for entry in closure.entries {
            if entry.module.name == name {
                moduleSectionPlans[entry.module.name] = directModuleSections
                continue
            }
            moduleSectionPlans[entry.module.name] = try entry.module.directModuleSectionPlan(
                in: closure.planContext(for: entry)
            )
        }
        let formalRenderer = CompiledTLARenderer(layout: layout, bindings: bindings)
        let renderedRefinements = try compiledRefinements.map { try formalRenderer.refinement($0) }
        let authoredPlusCalModule = try authoredPlusCalModule(
            semantics: semantics,
            layout: layout,
            bindings: bindings,
            formalRenderer: formalRenderer,
            renderedRefinements: renderedRefinements
        )
        return CompiledSpecification(
            spec: self,
            formalModuleClosure: closure,
            identity: compilationIdentity,
            layout: layout,
            bindings: bindings,
            semantics: semantics,
            refinements: compiledRefinements,
            moduleSectionPlans: moduleSectionPlans,
            authoredPlusCalModule: authoredPlusCalModule
        )
    }

    private func directModuleSectionPlan(
        layout: CompiledLayout,
        bindings: CompiledBindingTable,
        semantics: CompiledSemantics,
        refinements: [CompiledRefinement]
    ) throws -> DirectModuleSectionPlan {
        guard actions.count == semantics.actions.count,
              formalOperatorDefinitions.count <= semantics.formalOperatorDefinitions.count,
              recursiveFuncs.count <= semantics.recursiveFunctions.count else {
            throw CompilationDiagnostic(
                code: .compilationIdentityMismatch,
                stage: .rendering,
                path: "directModuleSectionPlan",
                expected: "compiled declarations aligned with this source model",
                actual: "actions \(semantics.actions.count)/\(actions.count), definitions \(semantics.formalOperatorDefinitions.count)/\(formalOperatorDefinitions.count), recursive functions \(semantics.recursiveFunctions.count)/\(recursiveFuncs.count)",
                nextSafeAction: "Compile the model again from its current source."
            )
        }
        let renderer = CompiledTLARenderer(layout: layout, bindings: bindings)
        let renderedRefinements = try refinements.map(renderer.refinement)
        let renderedTheorems = try semantics.theorems.map(renderer.theorem)
        let renderedFormalModuleReplacements = try semantics.formalModuleReplacements.map(renderer.formalModuleReplacement)
        let formalDefinitions = try formalOperatorDefinitions.enumerated()
            .map { index, definition in
                RenderedModuleDefinition(
                    name: definition.name,
                    text: try renderer.formalDefinition(semantics.formalOperatorDefinitions[index]),
                    dependencies: definition.plusCalDependencies
                )
            }
        let allDefinitions = formalDefinitions
        try validateUnique(
            allDefinitions.compactMap(\.name),
            code: .duplicateRenderedModuleDefinition,
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
        let emittedActionNamesByID = Dictionary(
            uniqueKeysWithValues: layout.actions.map { ($0.id, $0.renderedName) }
        )
        let emittedActionCallNames = try directActionCallNames(
            semantics.actions,
            emittedActionNames: emittedActionNamesByID
        )
        let orderedDefinitionsBeforeInstances = try orderDirectDefinitions(
            definitionsBeforeInstances,
            declared: []
        )
        let orderedDefinitionsAfterInstances = try orderDirectDefinitions(
            definitionsAfterInstances,
            declared: Set(definitionsBeforeInstances.compactMap(\.name)).union(instanceNames)
        )
        let renderedActions: [DirectModuleAction] = try actions.enumerated().map { index, declaration in
            let compiled = semantics.actions[index]
            guard let renderedName = emittedActionNamesByID[compiled.id] else {
                throw CompilationDiagnostic(
                    code: .compilationIdentityMismatch,
                    stage: .rendering,
                    path: "actions[\(compiled.id.ordinal)]",
                    expected: "a rendered action name",
                    actual: "the compiled action identity is outside the compiled layout",
                    nextSafeAction: "Compile the model again from its current source."
                )
            }
            return DirectModuleAction(
                declaration: declaration,
                renderedName: renderedName,
                renderedParameters: try compiled.bindings.map { try renderer.binderName($0.binder) },
                renderedBody: try renderer.action(compiled.body)
            )
        }
        return DirectModuleSectionPlan(
            renderedModuleSource: try renderedDirectModuleSource(
                definitionsBeforeInstances: orderedDefinitionsBeforeInstances,
                definitionsAfterInstances: orderedDefinitionsAfterInstances,
                renderedActions: renderedActions,
                emittedActionNamesByID: emittedActionNamesByID,
                emittedActionCallNames: emittedActionCallNames,
                renderedRefinements: renderedRefinements,
                renderedTheorems: renderedTheorems,
                renderedFormalModuleReplacements: renderedFormalModuleReplacements,
                renderer: renderer,
                layout: layout,
                semantics: semantics
            ),
            renderedConfiguration: renderedTLCConfiguration(semantics: semantics)
        )
    }

    private func directModuleSectionPlan(
        in context: FormalModuleClosure.ModulePlanContext
    ) throws -> DirectModuleSectionPlan {
        let source = try loweredSourceModel()
        try source.validateUnique(source.variables.map(\.name), code: .duplicateVariable, path: "variables")
        try source.validateUnique(source.actions.map(\.name), code: .duplicateAction, path: "actions")
        try source.validateUnique(source.invariants.map(\.name), code: .duplicateInvariant, path: "invariants")
        try source.validateSymmetricCollectionDeclarations()
        try source.validateRefinements()
        let layout = CompiledLayout(spec: source, closure: context.closure)
        var validator = BindingValidator(
            spec: source,
            layout: layout,
            closure: context.closure,
            incomingModuleParameters: context.incomingModuleParameters
        )
        _ = try validator.validate(spec: source)
        try validator.validateRefinementMappings(source.refinements)
        let bindings = validator.bindingTable()
        let semantics = try CompiledLowerer(
            bindings: bindings,
            closure: context.closure,
            layout: layout
        ).lower(spec: source)
        let refinements = try source.compiledRefinements(
            bindings: bindings,
            closure: context.closure,
            layout: layout
        )
        return try source.directModuleSectionPlan(
            layout: layout,
            bindings: bindings,
            semantics: semantics,
            refinements: refinements
        )
    }

    private func validateSymmetricCollectionDeclarations() throws {
        guard let error = symmetricCollectionValidationError(permutationProductBudget: .max) else {
            return
        }
        throw CompilationDiagnostic(
            code: .invalidSymmetricCollection,
            stage: .validation,
            path: "symmetricCollections",
            expected: "a valid symmetric collection declaration",
            actual: error.description,
            nextSafeAction: "Correct the symmetric collection declaration, then compile again."
        )
    }

    private func renderedDirectModuleSource(
        definitionsBeforeInstances: [RenderedModuleDefinition],
        definitionsAfterInstances: [RenderedModuleDefinition],
        renderedActions: [DirectModuleAction],
        emittedActionNamesByID: [ActionID: String],
        emittedActionCallNames: [CompiledActionCall: String],
        renderedRefinements: [String],
        renderedTheorems: [String],
        renderedFormalModuleReplacements: [String],
        renderer: CompiledTLARenderer,
        layout: CompiledLayout,
        semantics: CompiledSemantics
    ) throws -> String {
        let varNames = variables.map(\.name)
        let renderedActionDeclarations = renderedActions.map(\.declaration)
        let varsTuple = varNames.count == 1 ? varNames[0] : "<<\(varNames.joined(separator: ", "))>>"
        let isLibraryModule = variables.isEmpty && renderedActionDeclarations.isEmpty
        var lines: [String] = []

        lines.append("---- MODULE \(name) ----")

        let symmetryModule: [StandardModule] = symmetrySets.isEmpty && symmetricCollections.isEmpty ? [] : [.tlc]
        let importedNames = imports.map(\.name)
        let modules = ((extendsModules + [.finiteSets, .sequences] + symmetryModule)
            .map(\.rawValue)
            + importedNames)
            .reduce(into: [String]()) { names, module in
                if !names.contains(module) { names.append(module) }
            }
        lines.append("EXTENDS \(modules.joined(separator: ", "))")
        lines.append("")

        let generatedMemberSymbols = symmetricCollections.flatMap { collection in
            collection.metadata.generatedSymbols.filter { symbol in
                collection.metadata.members.contains(.constant(symbol))
            }
        }
        let formalConstantSymbols = formalParameters
            .filter { $0.kind == .constant }
            .map(\.name)
        let formalVariableSymbols = formalParameters
            .filter { $0.kind == .variable }
            .map(\.name)
        let allConstantSymbols = (constants.map(\.name) + formalConstantSymbols + generatedMemberSymbols).sorted()
        if !allConstantSymbols.isEmpty {
            lines.append("CONSTANTS \(allConstantSymbols.joined(separator: ", "))")
            for constant in constants.sorted(by: { $0.name < $1.name }) {
                lines.append("ASSUME \(constant.name) = \(constant.value)")
            }
            lines.append("")
        }

        for collection in symmetricCollections {
            let metadata = collection.metadata
            lines.append("\(metadata.domainSymbol) == {\(metadata.members.map(\.description).joined(separator: ", "))}")
            lines.append("\(metadata.symmetrySymbol) == Permutations(\(metadata.domainSymbol))")
        }
        for symmetry in symmetrySets {
            let values = Array(symmetry.values).sorted()
            lines.append("Symm\(symmetry.variableName) == Permutations({\(values.map(\.description).joined(separator: ", "))})")
        }
        if !symmetricCollections.isEmpty || !symmetrySets.isEmpty { lines.append("") }

        if let assume = semantics.assume {
            lines.append("ASSUME \(try renderer.state(assume))")
            lines.append("")
        }

        if !isLibraryModule || !formalVariableSymbols.isEmpty {
            lines.append("VARIABLES \((varNames + formalVariableSymbols).joined(separator: ", "))")
            lines.append("")
        }

        for replacement in renderedFormalModuleReplacements {
            lines.append(replacement)
            lines.append("")
        }
        for definition in definitionsBeforeInstances {
            lines.append(definition.text)
            lines.append("")
        }
        for function in semantics.recursiveFunctions.prefix(recursiveFuncs.count) {
            let rendered = try renderer.recursiveFunction(function)
            lines.append(rendered.declaration)
            lines.append(rendered.body)
            lines.append("")
        }
        for instance in moduleInstances {
            let arguments = instanceArguments(for: instance).map { argument in
                "\(argument.parameter) <- \(argument.value)"
            }.joined(separator: ", ")
            let withClause = arguments.isEmpty ? "" : " WITH \(arguments)"
            lines.append("\(instance.name) == INSTANCE \(instance.module.name)\(withClause)")
            lines.append("")
        }
        for definition in definitionsAfterInstances {
            lines.append(definition.text)
            lines.append("")
        }
        for refinement in renderedRefinements {
            lines.append(refinement)
            lines.append("")
        }

        if !isLibraryModule, varNames.count > 1 {
            lines.append("vars == \(varsTuple)")
            lines.append("")
        }
        for invariant in semantics.invariants {
            lines.append("\(invariant.name) == \(try renderer.state(invariant.body))")
        }
        if !semantics.invariants.isEmpty { lines.append("") }
        if let constraint = semantics.constraint {
            lines.append("StateConstraint == \(try renderer.state(constraint))")
            lines.append("")
        }
        guard !isLibraryModule else {
            lines.append("====")
            return lines.joined(separator: "\n") + "\n"
        }

        let initialPredicates = try layout.variables.map { variable -> String in
            let name = variable.declaration.name
            guard let initializer = semantics.variableInitializers[variable.id],
                  let initialValue = semantics.initialValues[variable.id] else {
                throw CompilationDiagnostic(
                    code: .compilationIdentityMismatch,
                    stage: .rendering,
                    path: "variables.\(name).initialization",
                    expected: "a compiled initializer for this declared variable",
                    actual: "the compiled layout has no matching initializer",
                    nextSafeAction: "Compile the model again from its current source."
                )
            }
            if let collection = semantics.symmetricCollections.first(where: { $0.variable == variable.id }) {
                return "\(name) = [member \\in \(collection.domainSymbol) |-> \(try initialValue.rendered(using: layout))]"
            }
            if let set = initializer.lazySet { return "\(name) \\in \(try renderer.state(set))" }
            if let set = initializer.initialSet { return "\(name) \\in \(try renderer.state(set))" }
            if let expression = initializer.initExpr { return "\(name) = \(try renderer.state(expression))" }
            return "\(name) = \(try renderer.state(.value(initialValue.rendered(using: layout))))"
        }
        if initialPredicates.count == 1 {
            lines.append("Init == \(initialPredicates[0])")
        } else {
            lines.append("Init ==")
            for predicate in initialPredicates { lines.append("  /\\ \(predicate)") }
        }
        lines.append("")

        for renderedAction in renderedActions where !renderedAction.declaration.name.isEmpty {
            let action = renderedAction.declaration
            let parameters = renderedAction.renderedParameters.joined(separator: ", ")
            let emittedName = renderedAction.renderedName
            let header = parameters.isEmpty ? emittedName : "\(emittedName)(\(parameters))"
            lines.append("\(header) == \(renderedAction.renderedBody)")
            for variant in actionVariants(action) where !variant.indices.isEmpty {
                let suffix = variant.indices.map(String.init).joined(separator: "_")
                lines.append("\(emittedName)__\(suffix) == \(formalActionCall(named: emittedName, arguments: variant.arguments))")
            }
        }
        lines.append("")

        let invocations = renderedActions.filter { !$0.declaration.name.isEmpty }.flatMap { renderedAction in
            actionVariants(renderedAction.declaration).map { variant -> String in
                let emittedName = renderedAction.renderedName
                guard !variant.indices.isEmpty else { return emittedName }
                return "\(emittedName)__\(variant.indices.map(String.init).joined(separator: "_"))"
            }
        }
        if invocations.count != 1 || invocations[0] != "Next" {
            if invocations.count == 1 {
                lines.append("Next == \(invocations[0])")
            } else {
                lines.append("Next ==")
                for invocation in invocations { lines.append("  \\/ \(invocation)") }
            }
        }
        lines.append("")

        lines.append("Spec ==")
        lines.append("  /\\ Init")
        lines.append("  /\\ [][Next]_\(varsTuple)")
        for condition in semantics.fairness {
            lines.append("  /\\ \(try renderer.fairness(condition, vars: varsTuple, actionNames: emittedActionNamesByID, actionCalls: emittedActionCallNames))")
        }
        lines.append("")
        for temporal in semantics.temporalProperties {
            lines.append("\(temporal.name) == \(try renderer.temporal(temporal.expression))")
        }
        if !semantics.temporalProperties.isEmpty { lines.append("") }
        for theorem in renderedTheorems {
            lines.append("THEOREM \(theorem)")
            lines.append("")
        }
        lines.append("====")
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderedTLCConfiguration(semantics: CompiledSemantics) -> String {
        var lines: [String] = []
        lines.append("SPECIFICATION Spec")
        lines.append(checkDeadlock ? "CHECK_DEADLOCK TRUE" : "CHECK_DEADLOCK FALSE")
        for constant in constants.sorted(by: { $0.name < $1.name }) {
            lines.append("CONSTANT \(constant.name) = \(constant.value)")
        }
        for replacement in semantics.formalModuleReplacements {
            lines.append(
                "CONSTANT \(replacement.operatorName) <- [\(replacement.moduleName)]\(replacement.definitionName)"
            )
        }
        for collection in symmetricCollections {
            for member in collection.metadata.members {
                lines.append("CONSTANT \(member) = \(member)")
            }
        }
        if constraint != nil { lines.append("CONSTRAINT StateConstraint") }
        for invariant in invariants { lines.append("INVARIANT \(invariant.name)") }
        for temporal in temporalProperties { lines.append("PROPERTY \(temporal.name)") }
        for symmetry in symmetrySets { lines.append("SYMMETRY Symm\(symmetry.variableName)") }
        for collection in symmetricCollections {
            lines.append("SYMMETRY \(collection.metadata.symmetrySymbol)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func orderDirectDefinitions(
        _ definitions: [RenderedModuleDefinition],
        declared: Set<String>
    ) throws -> [RenderedModuleDefinition] {
        var pending = definitions
        var emitted = declared
        var ordered: [RenderedModuleDefinition] = []
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

    private func validateRefinements() throws {
        try validateUnique(refinements.map(\.name), code: .duplicateRefinement, path: "refinements")
        var linkedInstances: Set<String> = []
        let declarationNames = Set(formalOperatorDefinitions.map(\.name))
            .union(invariants.map(\.name))
            .union(temporalProperties.map(\.name))
            .union(recursiveFuncs.map(\.name))
        for refinement in refinements {
            guard linkedInstances.insert(refinement.instance.namespace).inserted else {
                throw CompilationDiagnostic(
                    code: .duplicateRefinement,
                    stage: .linking,
                    path: "refinements.\(refinement.name).instance",
                    expected: "one refinement declaration for each module instance",
                    actual: "a second refinement for \(refinement.instance.namespace)",
                    nextSafeAction: "Keep one refinement mapping for that instance."
                )
            }
            guard !refinement.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CompilationDiagnostic(
                    code: .invalidRefinementName,
                    stage: .validation,
                    path: "refinements",
                    expected: "a non-empty refinement name",
                    actual: "an empty name",
                    nextSafeAction: "Name the refinement, then compile again."
                )
            }
            guard !declarationNames.contains(refinement.name) else {
                throw CompilationDiagnostic(
                    code: .duplicateRefinement,
                    stage: .validation,
                    path: "refinements.\(refinement.name)",
                    expected: "a refinement name distinct from other module declarations",
                    actual: "a duplicate declaration named \(refinement.name)",
                    nextSafeAction: "Rename the refinement or the conflicting declaration, then compile again."
                )
            }
            guard let instance = moduleInstances.first(where: refinement.instance.resolves) else {
                throw CompilationDiagnostic(
                    code: .unresolvedRefinementInstance,
                    stage: .linking,
                    path: "refinements.\(refinement.name).instance",
                    expected: "a directly declared module instance",
                    actual: "no matching instance",
                    nextSafeAction: "Declare the referenced Instance in this specification, then compile again."
                )
            }
            let target: String
            switch refinement.operator {
            case .spec: target = "Spec"
            case .liveSpec, .liveSpecEquals:
                throw CompilationDiagnostic(
                    code: .unsupportedRefinementTarget,
                    stage: .validation,
                    path: "refinements.\(refinement.name).target",
                    expected: "a locally checked refinement target",
                    actual: "\(refinement.operator) requires temporal refinement checking",
                    nextSafeAction: "Use .spec or implement the named temporal refinement capability."
                )
            }
            let targetModel = try instance.module.loweredSourceModel()
            let targetClosure = try FormalModuleClosure.resolve(root: targetModel)
            let exportsTarget: Bool
            switch refinement.operator {
            case .spec:
                exportsTarget = !targetModel.variables.isEmpty || !targetModel.actions.isEmpty
                    || targetClosure.linkedOperators.formalOperatorDefinitions.contains(where: { $0.name == target })
            case .liveSpec, .liveSpecEquals:
                exportsTarget = false
            }
            guard exportsTarget else {
                throw CompilationDiagnostic(
                    code: .unresolvedRefinementTarget,
                    stage: .linking,
                    path: "refinements.\(refinement.name).target",
                    expected: "the instance module to export \(target)",
                    actual: "\(instance.module.name) does not export \(target)",
                    nextSafeAction: "Declare a typed Spec target in \(instance.module.name), then compile again."
                )
            }
            let targets = targetModel.formalParameters.map(\.name) + targetModel.variables.map(\.name)
            let mapped = refinement.mappings.map(\.target)
            var seenMappings: Set<String> = []
            if let duplicate = mapped.first(where: { !seenMappings.insert($0).inserted }) {
                throw CompilationDiagnostic(
                    code: .duplicateRefinementMapping,
                    stage: .validation,
                    path: "refinements.\(refinement.name).mappings.\(duplicate)",
                    expected: "one mapping for each abstract declaration",
                    actual: "multiple mappings for \(duplicate)",
                    nextSafeAction: "Keep one mapping for that abstract declaration, then compile again."
                )
            }
            if let unknown = mapped.first(where: { !targets.contains($0) }) {
                throw CompilationDiagnostic(
                    code: .unknownRefinementMappingTarget,
                    stage: .binding,
                    path: "refinements.\(refinement.name).mappings.\(unknown)",
                    expected: "a variable or parameter declared by \(targetModel.name)",
                    actual: "an undeclared refinement target",
                    nextSafeAction: "Map a declaration exported by the abstract module, then compile again."
                )
            }
            if Set(mapped) != Set(targets) {
                let missing = targets.filter { !mapped.contains($0) }
                throw CompilationDiagnostic(
                    code: .incompleteRefinementMapping,
                    stage: .binding,
                    path: "refinements.\(refinement.name).mappings",
                    expected: "mappings for \(targets.joined(separator: ", "))",
                    actual: missing.isEmpty ? "a non-total mapping" : "missing \(missing.joined(separator: ", "))",
                    nextSafeAction: "Map every abstract variable and formal parameter, then compile again."
                )
            }
            guard instance.arguments.isEmpty else {
                throw CompilationDiagnostic(
                    code: .invalidRefinementParameterMapping,
                    stage: .linking,
                    path: "refinements.\(refinement.name).instance",
                    expected: "an Instance without substitutions",
                    actual: "INSTANCE substitutions duplicate the refinement mapping",
                    nextSafeAction: "Move every substitution into Refinement."
                )
            }
        }
    }

    private func compiledRefinements(
        bindings: CompiledBindingTable,
        closure: FormalModuleClosure,
        layout: CompiledLayout
    ) throws -> [CompiledRefinement] {
        let lowerer = CompiledLowerer(bindings: bindings, closure: closure, layout: layout)
        return try refinements.map { refinement in
            guard let instanceOffset = moduleInstances.firstIndex(where: refinement.instance.resolves) else {
                throw CompilationDiagnostic(
                    code: .unresolvedRefinementInstance,
                    stage: .linking,
                    path: "refinements.\(refinement.name).instance",
                    expected: "a directly declared module instance",
                    actual: "no matching instance",
                    nextSafeAction: "Declare the referenced Instance in this specification, then compile again."
                )
            }
            let instance = moduleInstances[instanceOffset]
            guard let instanceID = layout.moduleInstanceID(named: instance.name) else {
                throw CompilationDiagnostic(
                    code: .unresolvedRefinementInstance,
                    stage: .linking,
                    path: "refinements.\(refinement.name).instance",
                    expected: "the compiled instance identity",
                    actual: "no compiled instance identity",
                    nextSafeAction: "Compile the source model again."
                )
            }
            let abstractModule = try instance.module.loweredSourceModel()
            let mappings = Dictionary(uniqueKeysWithValues: refinement.mappings.map { ($0.target, $0.source) })
            let parameters = Dictionary(uniqueKeysWithValues: try abstractModule.formalParameters.map { parameter in
                guard let source = mappings[parameter.name] else {
                    throw CompilationDiagnostic(
                        code: .incompleteRefinementMapping,
                        stage: .binding,
                        path: "refinements.\(refinement.name).mappings.\(parameter.name)",
                        expected: "an explicit mapping",
                        actual: "no mapping",
                        nextSafeAction: "Map every abstract declaration, then compile again."
                    )
                }
                let compiled = try lowerer.refinementExpression(
                    source,
                    at: "refinements.\(refinement.name).mappings.\(parameter.name)"
                )
                guard compiled.isStateIndependent else {
                    throw CompilationDiagnostic(
                        code: .stateDependentRefinementParameter,
                        stage: .binding,
                        path: "refinements.\(refinement.name).mappings.\(parameter.name)",
                        expected: "a state-independent module parameter",
                        actual: "a mapping that reads concrete state",
                        nextSafeAction: "Use a constant mapping for the abstract module parameter."
                    )
                }
                return (parameter.name, source)
            })
            let specialized = abstractModule.specializing(parameters: parameters)
            return .init(
                name: refinement.name,
                instance: instanceID,
                operator: refinement.operator,
                abstract: try specialized.compile(),
                variableMappings: try abstractModule.variables.map { variable in
                    guard let source = mappings[variable.name] else {
                        throw CompilationDiagnostic(
                            code: .incompleteRefinementMapping,
                            stage: .binding,
                            path: "refinements.\(refinement.name).mappings.\(variable.name)",
                            expected: "an explicit mapping",
                            actual: "no mapping",
                            nextSafeAction: "Map every abstract declaration, then compile again."
                        )
                    }
                    return try lowerer.refinementExpression(
                        source,
                        at: "refinements.\(refinement.name).mappings.\(variable.name)"
                    )
                }
            )
        }
    }

    var compilationIdentity: CompilationIdentity {
        var encoder = CanonicalSpecificationEncoder()
        let source = encoder.encode(self)
        let value = SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return .init(value: value)
    }
}

private func directActionCallNames(
    _ actions: [CompiledAction],
    emittedActionNames: [ActionID: String]
) throws -> [CompiledActionCall: String] {
    var names: [CompiledActionCall: String] = [:]
    for action in actions {
        guard let emittedName = emittedActionNames[action.id] else {
            throw CompilationDiagnostic(
                code: .compilationIdentityMismatch,
                stage: .rendering,
                path: "actions[\(action.id.ordinal)]",
                expected: "a rendered action name",
                actual: "no rendered name",
                nextSafeAction: "Compile the model again from its current source."
            )
        }
        func addCalls(_ position: Int, arguments: [TLAValue], indices: [Int]) {
            guard position < action.bindings.count else {
                let suffix = indices.isEmpty ? "" : "__\(indices.map(String.init).joined(separator: "_"))"
                names[.init(action: action.id, arguments: arguments)] = "\(emittedName)\(suffix)"
                return
            }
            for (index, value) in action.bindings[position].values.enumerated() {
                addCalls(position + 1, arguments: arguments + [value], indices: indices + [index])
            }
        }
        addCalls(0, arguments: [], indices: [])
    }
    return names
}

/// Encodes the complete source model with unambiguous field boundaries.
///
/// Compilation identity includes action domains, every initialisation form,
/// and the recursive contents of imported modules.
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
        let theorems = spec.theorems.map { theorem in
            if let temporal = theorem.temporalBody {
                return node("temporal-theorem", [theorem.name, canonicalTemporal(temporal)])
            }
            if let state = theorem.stateBody {
                return node("state-theorem", [theorem.name, canonicalExpression(state)])
            }
            return node("theorem", [theorem.name])
        }
        list("theorems", theorems) { $0 }
        list("extendsModules", spec.extendsModules) { $0.rawValue }
        field("constraint", canonicalOptional(spec.constraint.map(canonicalExpression)))
        let recursiveFunctions = spec.recursiveFuncs.map {
            node("recursive-function", [$0.name, canonicalList($0.params), canonicalExpression($0.body)])
        }
        list("recursiveFuncs", recursiveFunctions) { $0 }
        let formalOperators = spec.formalOperatorDefinitions.map(canonicalFormalOperatorDefinition)
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
        let refinements = spec.refinements.map { refinement in
            let target: String
            switch refinement.operator {
            case .spec: target = "spec"
            case .liveSpec: target = "liveSpec"
            case .liveSpecEquals: target = "liveSpecEquals"
            }
            return node("refinement", [
                refinement.name,
                refinement.instance.namespace,
                target,
                canonicalList(refinement.mappings.map {
                    node("refinement-mapping", [$0.target, canonicalExpression($0.source)])
                })
            ])
        }
        list("refinements", refinements) { $0 }
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
        case .weakFairnessNext: return node("weakFairnessNext", [])
        case .strongFairnessNext: return node("strongFairnessNext", [])
        case .weakFairnessActionCall(let action): return node("weakFairnessActionCall", [canonicalActionCall(action)])
        case .strongFairnessActionCall(let action): return node("strongFairnessActionCall", [canonicalActionCall(action)])
        }
    }

    private func canonicalFormalOperatorDefinition(_ definition: FormalOperatorDefinition) -> String {
        var next = 0
        var environment: [String: String] = [:]
        let parameters = definition.parameters.map { parameter -> String in
            let (canonical, extended) = fresh(parameter.name, environment: environment, next: &next)
            environment = extended
            switch parameter {
            case .value:
                return node("valueParameter", [canonical])
            case .operator(_, let arity):
                return node("operatorParameter", [canonical, String(arity)])
            }
        }
        return node("operator-definition", [
            definition.name,
            canonicalList(parameters),
            node("expression", [stateKey(definition.body, environment: environment, next: &next)])
        ])
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
