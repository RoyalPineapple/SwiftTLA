import Foundation
import CryptoKit

func isFormalIdentifier(_ name: String) -> Bool {
    func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    guard let first = name.unicodeScalars.first, first == "_" || isLetter(first) else { return false }
    return name.unicodeScalars.dropFirst().allSatisfy {
        $0 == "_" || isLetter($0) || (48...57).contains($0.value)
    }
}

private let tlaReservedWords: Set<String> = [
    "ACTION", "ACTIONS", "ASSUME", "ASSUMPTION", "AXIOM", "BY", "CASE", "CHOOSE",
    "CONSTANT", "CONSTANTS", "COROLLARY", "DEF", "DEFINE", "DEFS", "DOMAIN", "ELSE",
    "ENABLED", "EXCEPT", "EXTENDS", "HAVE", "HIDE", "IF", "IN", "INSTANCE", "LAMBDA",
    "LEMMA", "LET", "LOCAL", "MODULE", "NEW", "OBVIOUS", "OMITTED", "ONLY", "OTHER",
    "PICK", "PROOF", "PROPOSITION", "PROVE", "QED", "RECURSIVE", "SF_", "STATE",
    "SUBSET", "SUFFICES", "TAKE", "TEMPORAL", "TEMPORALS", "THEN", "THEOREM", "UNCHANGED",
    "UNION", "USE", "VARIABLE", "VARIABLES", "WF_", "WITH", "WITNESS"
]

private let plusCalReservedWords: Set<String> = [
    "algorithm", "assert", "await", "begin", "call", "define", "do", "either", "else",
    "elsif", "end", "fair", "goto", "if", "macro", "or", "print", "procedure", "process",
    "return", "skip", "then", "variable", "variables", "when", "while", "with"
]

func isTLADeclarationName(_ name: String) -> Bool {
    isFormalIdentifier(name) && tlaReservedWords.contains(name) == false
}

func isPlusCalDeclarationName(_ name: String) -> Bool {
    isTLADeclarationName(name) && plusCalReservedWords.contains(name) == false
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
    public let name: String
    public let identity: CompilationIdentity
    public let variables: [VariableDescription]
    public let actions: [ActionDescription]
    public let invariants: [String]
    public let temporalProperties: [String]
    public let refinements: [String]
    public let stateConstraint: String?
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
    let renderedConfigurationWithoutSymmetry: String
    let renderedActions: [RenderedAction]
}

package struct RenderedAction: Sendable, Equatable {
    package let sourceName: String
    package let arguments: [TLAValue]
    package let renderedName: String

    package init(sourceName: String, arguments: [TLAValue], renderedName: String) {
        self.sourceName = sourceName
        self.arguments = arguments
        self.renderedName = renderedName
    }

    package var sourceInvocationName: String {
        guard !arguments.isEmpty else { return sourceName }
        return "\(sourceName)(\(arguments.map(\.description).joined(separator: ", ")))"
    }
}

struct DirectModuleAction: Sendable, Equatable {
    let sourceName: String
    let renderedName: String
    let renderedParameters: [String]
    let renderedBody: String
    let calls: [RenderedAction]
}

struct CompiledRefinement: Sendable {
    let name: String
    let instance: ModuleInstanceID
    let `operator`: RefinementDecl.Operator
    let abstract: CompiledSpecification
    let variableMappings: [CompiledStateExpr]
}

/// The result of lowering one module in its resolved import context.
private struct CompiledModule: Sendable {
    let layout: CompiledLayout
    let bindings: CompiledBindingTable
    let semantics: CompiledSemantics
    let refinements: [CompiledRefinement]
    let authoredAlgorithm: CompiledAuthoredPlusCalAlgorithmPlan?
    let requiredStandardModules: Set<StandardModule>
    let definitionsBeforeInstances: [Int]
    let definitionsAfterInstances: [Int]
}

/// The immutable compiled specification and validated outputs produced by compilation.
public struct CompiledSpecification: Sendable {
    public let description: CompilationDescription
    public var identity: CompilationIdentity { description.identity }
    package let layout: CompiledLayout
    package let semantics: CompiledSemantics
    let refinements: [CompiledRefinement]
    private let renderedBundle: TLAModuleBundle
    private let renderedConfigurationWithoutSymmetry: String
    private let renderedActionPlan: [RenderedAction]
    private let renderedPlusCalModuleBundle: TLAModuleBundle?

    package func renderedActions() -> [RenderedAction] {
        renderedActionPlan
    }

    fileprivate init(
        description: CompilationDescription,
        layout: CompiledLayout,
        semantics: CompiledSemantics,
        refinements: [CompiledRefinement],
        renderedBundle: TLAModuleBundle,
        renderedConfigurationWithoutSymmetry: String,
        renderedActionPlan: [RenderedAction],
        renderedPlusCalModuleBundle: TLAModuleBundle?
    ) {
        self.description = description
        self.layout = layout
        self.semantics = semantics
        self.refinements = refinements
        self.renderedBundle = renderedBundle
        self.renderedConfigurationWithoutSymmetry = renderedConfigurationWithoutSymmetry
        self.renderedActionPlan = renderedActionPlan
        self.renderedPlusCalModuleBundle = renderedPlusCalModuleBundle
    }

    /// Returns the complete TLA+/CFG bundle produced by compilation.
    public func renderedTLAModuleBundle() -> TLAModuleBundle {
        renderedBundle
    }

    package func renderedTLAModuleBundle(
        symmetryReduction: SymmetryReduction
    ) -> TLAModuleBundle {
        switch symmetryReduction {
        case .enabled:
            return renderedBundle
        case .disabled:
            return TLAModuleBundle(
                root: .init(
                    name: renderedBundle.root.name,
                    tla: renderedBundle.root.tla,
                    cfg: renderedConfigurationWithoutSymmetry
                ),
                imports: renderedBundle.imports,
                provenance: renderedBundle.provenance
            )
        }
    }

    /// Returns the source-faithful PlusCal bundle produced by compilation.
    public func renderedPlusCalBundle() throws -> TLAModuleBundle {
        guard let renderedPlusCalModuleBundle else {
            throw CompilationDiagnostic(
                code: .invalidAuthoredPlusCalPlan,
                stage: .rendering,
                path: "TLASpec.sourceAlgorithms",
                expected: "exactly one authored Algorithm",
                actual: "no authored PlusCal module in this compilation",
                nextSafeAction: "Compile one source model with one canonical Algorithm per exported module."
            )
        }
        return renderedPlusCalModuleBundle
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
        case invalidAlgorithm
        case invalidAlgorithmFairnessPlacement
        case invalidAlgorithmAssumptionPlacement
        case invalidFormalDeclaration
        case invalidFormalOperatorApplication
        case missingVariableInitializer
        case actionEnablednessInInitializer
        case cyclicActionEnabledness
        case cyclicVariableInitialization
        case stateDependentAssumption
        case invalidCollectionMember
        case emptySpecificationName
        case invalidSpecificationName
        case duplicateVariable
        case duplicateAction
        case duplicateInvariant
        case duplicateAlgorithm
        case invalidAuthoredPlusCalPlan
        case invalidModelCollection
        case invalidSymmetryDeclaration
        case duplicateRecordField
        case compilationIdentityMismatch
        case unsupportedGeneratedValueShape
        case unresolvedGeneratedValueShape
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

private extension TLASpec {
    func validateSourceDeclarationNames() throws {
        if let diagnostic = diagnostics.first { throw diagnostic }
        guard name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw CompilationDiagnostic(
                code: .emptySpecificationName,
                stage: .validation,
                path: "specification.name",
                expected: "a non-empty specification name",
                actual: name,
                nextSafeAction: "Give the specification a stable name, then compile again."
            )
        }
        guard isTLADeclarationName(name) else {
            throw CompilationDiagnostic(
                code: .invalidSpecificationName,
                stage: .validation,
                path: "specification.name",
                expected: "a formal module identifier that is not a reserved word",
                actual: name,
                nextSafeAction: "Use an ASCII identifier that is not reserved by TLA+ or PlusCal."
            )
        }

        func requireDeclaration(_ value: String, kind: String, path: String) throws {
            guard isTLADeclarationName(value) else {
                throw CompilationDiagnostic(
                    code: .invalidFormalDeclaration,
                    stage: .validation,
                    path: path,
                    expected: "a formal identifier that is not a reserved word",
                    actual: "invalid \(kind) name '\(value)'",
                    nextSafeAction: "Use an ASCII identifier that is not reserved by TLA+."
                )
            }
        }

        let collectionNames = Set(collections.map(\.name))
        let declarationGroups: [([String], String, String)] = [
            (variables.filter { collectionNames.contains($0.name) == false }.map(\.name), "variable", "variables"),
            (constants.map(\.name), "constant", "constants"),
            (invariants.map(\.name), "invariant", "invariants"),
            (temporalProperties.map(\.name), "temporal property", "temporalProperties"),
            (recursiveFuncs.map(\.name), "recursive operator", "recursiveFunctions"),
            (formalOperatorDefinitions.map(\.name), "formal operator", "formalOperators"),
            (moduleInstances.map(\.name), "module instance", "moduleInstances"),
            (refinements.map(\.name), "refinement", "refinements")
        ]

        for (names, kind, path) in declarationGroups {
            for (index, declaration) in names.enumerated() {
                try requireDeclaration(declaration, kind: kind, path: "\(path)[\(index)].name")
            }
        }

        for (configurationIndex, configuration) in importConfigurations.enumerated() {
            try requireDeclaration(
                configuration.moduleName,
                kind: "module",
                path: "importConfigurations[\(configurationIndex)].moduleName"
            )
            for (replacementIndex, replacement) in configuration.replacements.enumerated() {
                for (value, field) in [(replacement.operatorName, "operatorName"), (replacement.definitionName, "definitionName")] {
                    try requireDeclaration(
                        value,
                        kind: "module replacement",
                        path: "importConfigurations[\(configurationIndex)].replacements[\(replacementIndex)].\(field)"
                    )
                }
            }
        }
    }
}

public extension TLASpec {
    /// Validates and identifies this specification before it reaches a formal
    /// consumer. Structural module linking is added to this gate by the linker.
    func compile() throws -> CompiledSpecification {
        try validateSourceDeclarationNames()
        return try loweredSourceModel().compileLowered()
    }

    private func compileLowered() throws -> CompiledSpecification {
        let closure = try FormalModuleClosure.resolve(root: self)
        for entry in closure.entries where entry.id != closure.root.id {
            try entry.module.validateSourceDeclarationNames()
        }
        let module = try compileModule(in: closure)
        let layout = module.layout
        let semantics = module.semantics
        let bindings = module.bindings
        let compiledRefinements = module.refinements
        let identity = compilationIdentity
        let directModuleSections = try directModuleSectionPlan(module)
        var moduleSectionPlans: [FormalModuleClosure.ModuleID: DirectModuleSectionPlan] = [:]
        for entry in closure.entries {
            if entry.id == closure.root.id {
                moduleSectionPlans[entry.id] = directModuleSections
                continue
            }
            moduleSectionPlans[entry.id] = try entry.module.directModuleSectionPlan(
                in: closure.planContext(for: entry)
            )
        }
        let formalRenderer = CompiledTLARenderer(layout: layout, bindings: bindings)
        let renderedRefinements = try compiledRefinements.map { try formalRenderer.refinement($0) }
        let authoredPlusCalModule = try authoredPlusCalModule(
            algorithm: module.authoredAlgorithm,
            semantics: semantics,
            layout: layout,
            formalRenderer: formalRenderer,
            renderedRefinements: renderedRefinements
        )
        guard let rootPlan = moduleSectionPlans[closure.root.id] else {
            throw CompilationDiagnostic(
                code: .compilationIdentityMismatch,
                stage: .rendering,
                path: "moduleClosure.\(closure.root.module.name)",
                expected: "a rendered root module plan",
                actual: "no rendered root module plan",
                nextSafeAction: "Compile the source model again."
            )
        }
        let renderedFiles = try closure.entries.map { entry in
            guard let plan = moduleSectionPlans[entry.id] else {
                throw CompilationDiagnostic(
                    code: .compilationIdentityMismatch,
                    stage: .rendering,
                    path: "moduleClosure.\(entry.module.name)",
                    expected: "a rendered module plan",
                    actual: "no rendered module plan",
                    nextSafeAction: "Compile the source model again."
                )
            }
            return TLAModuleFile(
                name: entry.module.name,
                tla: plan.renderedModuleSource,
                cfg: entry.id == closure.root.id ? plan.renderedConfiguration : nil
            )
        }
        guard let renderedRoot = renderedFiles.last else {
            throw CompilationDiagnostic(
                code: .emptyFormalModuleClosure,
                stage: .linking,
                path: "moduleClosure",
                expected: "a linked root module",
                actual: "an empty module closure",
                nextSafeAction: "Compile a source model with one root module."
            )
        }
        let renderedBundle = TLAModuleBundle(
            root: renderedRoot,
            imports: Array(renderedFiles.dropLast()),
            provenance: .compiled(
                identity: identity,
                ownership: closure.entries.map {
                    .init(
                        moduleName: $0.module.name,
                        owningRoot: $0.owningRoot,
                        structuralPath: $0.structuralPath
                    )
                },
                dependencies: closure.edges.map {
                    .init(
                        importingModule: $0.fromModule,
                        importedModule: $0.toModule,
                        structuralPath: $0.structuralPath
                    )
                }
            )
        )
        try renderedBundle.validateDeclaredClosure()
        let renderedPlusCalModuleBundle = try authoredPlusCalModule.map { module in
            let bundle = TLAModuleBundle(
                root: .init(
                    name: renderedRoot.name,
                    tla: try AlgorithmPlusCalRenderer(module: module, formalRenderer: formalRenderer).render(),
                    cfg: renderedRoot.cfg
                ),
                imports: renderedBundle.imports,
                provenance: renderedBundle.provenance
            )
            try bundle.validateDeclaredClosure()
            return bundle
        }
        let description = CompilationDescription(
            name: name,
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
            invariants: semantics.invariants.map(\.name),
            temporalProperties: semantics.temporalProperties.map(\.name),
            refinements: compiledRefinements.map(\.name),
            stateConstraint: semantics.constraint.map { _ in "StateConstraint" },
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
            imports: closure.entries.filter { $0.id != closure.root.id }.map {
                .init(
                    name: $0.module.name,
                    owningRoot: $0.owningRoot,
                    structuralPath: $0.structuralPath
                )
            }
        )
        return CompiledSpecification(
            description: description,
            layout: layout,
            semantics: semantics,
            refinements: compiledRefinements,
            renderedBundle: renderedBundle,
            renderedConfigurationWithoutSymmetry: rootPlan.renderedConfigurationWithoutSymmetry,
            renderedActionPlan: rootPlan.renderedActions,
            renderedPlusCalModuleBundle: renderedPlusCalModuleBundle
        )
    }

    private func directModuleSectionPlan(_ module: CompiledModule) throws -> DirectModuleSectionPlan {
        let layout = module.layout
        let bindings = module.bindings
        let semantics = module.semantics
        let refinements = module.refinements
        let requiredStandardModules = module.requiredStandardModules
        guard actions.count == semantics.actions.count,
              formalOperatorDefinitions.count <= semantics.formalOperatorDefinitions.count,
              recursiveFuncs.count <= semantics.recursiveFunctions.count else {
            throw CompilationDiagnostic(
                code: .compilationIdentityMismatch,
                stage: .rendering,
                path: "directModuleSectionPlan",
                expected: "compiled declarations aligned with this source model",
                actual: "actions \(semantics.actions.count)/\(actions.count), definitions \(semantics.formalOperatorDefinitions.count)/\(formalOperatorDefinitions.count), recursive functions \(semantics.recursiveFunctions.count)/\(recursiveFuncs.count)",
                nextSafeAction: "Compile the source model again."
            )
        }
        let renderer = CompiledTLARenderer(layout: layout, bindings: bindings)
        let renderedRefinements = try refinements.map(renderer.refinement)
        let renderedFormalModuleReplacements = try semantics.formalModuleReplacements.map(renderer.formalModuleReplacement)
        let emittedActionNamesByID = Dictionary(
            uniqueKeysWithValues: layout.actions.map { ($0.id, $0.renderedName) }
        )
        let emittedActionCalls = try directActionCalls(
            semantics.actions,
            emittedActionNames: emittedActionNamesByID
        )
        let emittedActionCallNames = Dictionary(
            uniqueKeysWithValues: emittedActionCalls.map { ($0.call, $0.renderedName) }
        )
        let callsByAction = Dictionary(grouping: emittedActionCalls, by: { $0.call.action })
        let directModuleActions: [DirectModuleAction] = try actions.enumerated().map { index, declaration in
            let compiled = semantics.actions[index]
            guard let renderedName = emittedActionNamesByID[compiled.id] else {
                throw CompilationDiagnostic(
                    code: .compilationIdentityMismatch,
                    stage: .rendering,
                    path: "actions[\(compiled.id.ordinal)]",
                    expected: "a rendered action name",
                    actual: "the compiled action identity is outside the compiled layout",
                    nextSafeAction: "Compile the source model again."
                )
            }
            return DirectModuleAction(
                sourceName: declaration.name,
                renderedName: renderedName,
                renderedParameters: try compiled.bindings.map { try renderer.binderName($0.binder) },
                renderedBody: try renderer.action(compiled.body),
                calls: try callsByAction[compiled.id, default: []].map { emitted in
                    RenderedAction(
                        sourceName: declaration.name,
                        arguments: try emitted.call.arguments.map { try $0.rendered(using: layout) },
                        renderedName: emitted.renderedName
                    )
                }
            )
        }
        return DirectModuleSectionPlan(
            renderedModuleSource: try renderedDirectModuleSource(
                definitionsBeforeInstances: try module.definitionsBeforeInstances.map { try renderer.formalDefinition(semantics.formalOperatorDefinitions[$0]) },
                definitionsAfterInstances: try module.definitionsAfterInstances.map { try renderer.formalDefinition(semantics.formalOperatorDefinitions[$0]) },
                renderedActions: directModuleActions,
                emittedActionNamesByID: emittedActionNamesByID,
                emittedActionCallNames: emittedActionCallNames,
                renderedRefinements: renderedRefinements,
                renderedFormalModuleReplacements: renderedFormalModuleReplacements,
                renderer: renderer,
                layout: layout,
                semantics: semantics,
                requiredStandardModules: requiredStandardModules
            ),
            renderedConfiguration: renderedTLCConfiguration(semantics: semantics, usesSymmetryReduction: true),
            renderedConfigurationWithoutSymmetry: renderedTLCConfiguration(
                semantics: semantics,
                usesSymmetryReduction: false
            ),
            renderedActions: directModuleActions.filter { !$0.sourceName.isEmpty }.flatMap(\.calls)
        )
    }

    private func directModuleSectionPlan(
        in context: FormalModuleClosure.ModulePlanContext
    ) throws -> DirectModuleSectionPlan {
        let source = try loweredSourceModel()
        let module = try source.compileModule(
            in: context.closure,
            incomingModuleParameters: context.incomingModuleParameters
        )
        return try source.directModuleSectionPlan(module)
    }

    private func compileModule(
        in closure: FormalModuleClosure,
        incomingModuleParameters: [FormalModuleReplacement] = []
    ) throws -> CompiledModule {
        try validateUnique(variables.map(\.name), code: .duplicateVariable, path: "variables")
        try validateUnique(actions.map(\.name), code: .duplicateAction, path: "actions")
        try validateUnique(invariants.map(\.name), code: .duplicateInvariant, path: "invariants")
        try validateModelCollectionDeclarations()
        try validateSymmetryDeclarations()
        try validateRefinements()
        let definitionOrder = try orderedDirectDefinitions()
        let layout = CompiledLayout(spec: self, closure: closure)
        var lowerer = CompiledLowerer(
            spec: self, closure: closure, layout: layout,
            incomingModuleParameters: incomingModuleParameters
        )
        let semantics = try lowerer.lower(spec: self)
        let authoredAlgorithm = try authoredPlusCalAlgorithmPlan.map {
            try lowerer.authoredPlusCalPlan($0)
        }
        let refinements = try compiledRefinements(lowerer: &lowerer, layout: layout, semantics: semantics)
        return CompiledModule(
            layout: layout, bindings: lowerer.bindings, semantics: semantics,
            refinements: refinements, authoredAlgorithm: authoredAlgorithm,
            requiredStandardModules: lowerer.requiredStandardModules,
            definitionsBeforeInstances: definitionOrder.beforeInstances,
            definitionsAfterInstances: definitionOrder.afterInstances
        )
    }

    private func validateModelCollectionDeclarations() throws {
        guard let error = collectionValidationError() else {
            return
        }
        throw CompilationDiagnostic(
            code: .invalidModelCollection,
            stage: .validation,
            path: "collections",
            expected: "a valid model collection declaration",
            actual: error.description,
            nextSafeAction: "Correct the model collection declaration, then compile again."
        )
    }

    private func renderedDirectModuleSource(
        definitionsBeforeInstances: [String],
        definitionsAfterInstances: [String],
        renderedActions: [DirectModuleAction],
        emittedActionNamesByID: [ActionID: String],
        emittedActionCallNames: [CompiledActionCall: String],
        renderedRefinements: [String],
        renderedFormalModuleReplacements: [String],
        renderer: CompiledTLARenderer,
        layout: CompiledLayout,
        semantics: CompiledSemantics,
        requiredStandardModules: Set<StandardModule>
    ) throws -> String {
        let varNames = variables.map(\.name)
        let varsTuple = varNames.count == 1 ? varNames[0] : "<<\(varNames.joined(separator: ", "))>>"
        let isLibraryModule = variables.isEmpty && renderedActions.isEmpty
        var lines: [String] = []

        lines.append("---- MODULE \(name) ----")

        let symmetryModule: [StandardModule] = symmetrySets.isEmpty ? [] : [.tlc]
        let importedNames = imports.map(\.name)
        let modules = ((extendsModules + [.finiteSets, .sequences] + requiredStandardModules.sorted { $0.rawValue < $1.rawValue } + symmetryModule)
            .map(\.rawValue)
            + importedNames)
            .reduce(into: [String]()) { names, module in
                if !names.contains(module) { names.append(module) }
            }
        lines.append("EXTENDS \(modules.joined(separator: ", "))")
        lines.append("")

        let generatedMemberSymbols = collections.flatMap { collection in
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

        for collection in collections {
            let metadata = collection.metadata
            lines.append("\(metadata.domainSymbol) == {\(metadata.members.map(\.description).joined(separator: ", "))}")
        }
        for symmetry in symmetrySets {
            let values = Array(symmetry.values).sorted()
            lines.append("Symm\(symmetry.variableName) == Permutations({\(values.map(\.description).joined(separator: ", "))})")
        }
        if !collections.isEmpty || !symmetrySets.isEmpty { lines.append("") }

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
            lines.append(definition)
            lines.append("")
        }
        for function in semantics.recursiveFunctions.prefix(recursiveFuncs.count) {
            let rendered = try renderer.recursiveFunction(function)
            lines.append(rendered.declaration)
            lines.append(rendered.body)
            lines.append("")
        }
        for instance in semantics.moduleInstances {
            lines.append(try renderer.moduleInstance(instance))
            lines.append("")
        }
        for definition in definitionsAfterInstances {
            lines.append(definition)
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

        let initializations = Dictionary(
            uniqueKeysWithValues: semantics.variableInitializations.map {
                ($0.variable, $0.initialization)
            }
        )
        let initialPredicates = try layout.variables.map { variable -> String in
            let name = variable.declaration.name
            guard let initialization = initializations[variable.id] else {
                throw CompilationDiagnostic(
                    code: .compilationIdentityMismatch,
                    stage: .rendering,
                    path: "variables.\(name).initialization",
                    expected: "a compiled initializer for this declared variable",
                    actual: "the compiled layout has no matching initializer",
                    nextSafeAction: "Compile the source model again."
                )
            }
            switch initialization {
            case .value(let value):
                return "\(name) = \(try value.rendered(using: layout))"
            case .expression(let expression):
                return "\(name) = \(try renderer.state(expression))"
            case .memberOf(let set):
                return "\(name) \\in \(try renderer.state(set))"
            }
        }
        if initialPredicates.count == 1 {
            lines.append("Init == \(initialPredicates[0])")
        } else {
            lines.append("Init ==")
            for predicate in initialPredicates { lines.append("  /\\ \(predicate)") }
        }
        lines.append("")

        for renderedAction in renderedActions where renderedAction.sourceName.isEmpty == false {
            let parameters = renderedAction.renderedParameters.joined(separator: ", ")
            let emittedName = renderedAction.renderedName
            let header = parameters.isEmpty ? emittedName : "\(emittedName)(\(parameters))"
            lines.append("\(header) == \(renderedAction.renderedBody)")
            for call in renderedAction.calls where call.arguments.isEmpty == false {
                lines.append("\(call.renderedName) == \(formalActionCall(named: emittedName, arguments: call.arguments))")
            }
        }
        lines.append("")

        let invocations = renderedActions
            .filter { $0.sourceName.isEmpty == false }
            .flatMap(\.calls)
            .map(\.renderedName)
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
        lines.append("====")
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderedTLCConfiguration(
        semantics: CompiledSemantics,
        usesSymmetryReduction: Bool
    ) -> String {
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
        for collection in collections {
            for member in collection.metadata.members {
                lines.append("CONSTANT \(member) = \(member)")
            }
        }
        if constraint != nil { lines.append("CONSTRAINT StateConstraint") }
        for invariant in invariants { lines.append("INVARIANT \(invariant.name)") }
        for temporal in temporalProperties { lines.append("PROPERTY \(temporal.name)") }
        if usesSymmetryReduction {
            for symmetry in symmetrySets { lines.append("SYMMETRY Symm\(symmetry.variableName)") }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Resolve declaration order before a renderer consumes the compiled module.
    private func orderedDirectDefinitions() throws -> (beforeInstances: [Int], afterInstances: [Int]) {
        let definitions = formalOperatorDefinitions
        try validateUnique(definitions.map(\.name), code: .duplicateRenderedModuleDefinition, path: "definitions")
        let instanceNames = Set(moduleInstances.map(\.name))
        let declaredNames = instanceNames.union(definitions.map(\.name))
        for definition in definitions {
            for dependency in definition.plusCalDependencies where !declaredNames.contains(dependency) {
                throw CompilationDiagnostic(
                    code: .unresolvedDirectModuleDependency,
                    stage: .linking,
                    path: "definitions.\(definition.name).dependencies.\(dependency)",
                    expected: "a definition or INSTANCE declared by this module",
                    actual: "no declaration named '\(dependency)'",
                    nextSafeAction: "Declare the dependency or remove it from dependsOn, then compile again."
                )
            }
        }
        let before = definitions.indices.filter { instanceNames.isDisjoint(with: definitions[$0].plusCalDependencies) }
        let after = definitions.indices.filter { !instanceNames.isDisjoint(with: definitions[$0].plusCalDependencies) }
        func ordered(_ indices: [Int], declared: Set<String>) throws -> [Int] {
            var pending = indices
            var emitted = declared
            var result: [Int] = []
            while let index = pending.firstIndex(where: { definitions[$0].plusCalDependencies.allSatisfy(emitted.contains) }) {
                let definition = pending.remove(at: index)
                result.append(definition)
                emitted.insert(definitions[definition].name)
            }
            guard pending.isEmpty else {
                throw CompilationDiagnostic(
                    code: .cyclicDirectModuleDependency,
                    stage: .linking,
                    path: "definitions",
                    expected: "an acyclic declaration dependency graph",
                    actual: pending.map { definitions[$0].name }.joined(separator: ", "),
                    nextSafeAction: "Break the declaration cycle, then compile again."
                )
            }
            return result
        }
        return (
            try ordered(before, declared: []),
            try ordered(after, declared: Set(before.map { definitions[$0].name }).union(instanceNames))
        )
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
                    nextSafeAction: "Use a .spec refinement."
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
        lowerer: inout CompiledLowerer,
        layout: CompiledLayout,
        semantics: CompiledSemantics
    ) throws -> [CompiledRefinement] {
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
                let dependencies = compiled.stateRequirements(
                    formalOperators: semantics.formalOperatorDefinitions,
                    recursiveFunctions: semantics.recursiveFunctions
                )
                guard dependencies.variables.isEmpty && dependencies.requiresCompleteState == false else {
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

private func directActionCalls(
    _ actions: [CompiledAction],
    emittedActionNames: [ActionID: String]
) throws -> [(call: CompiledActionCall, renderedName: String)] {
    var calls: [(call: CompiledActionCall, renderedName: String)] = []
    for action in actions {
        guard let emittedName = emittedActionNames[action.id] else {
            throw CompilationDiagnostic(
                code: .compilationIdentityMismatch,
                stage: .rendering,
                path: "actions[\(action.id.ordinal)]",
                expected: "a rendered action name",
                actual: "no rendered name",
                nextSafeAction: "Compile the source model again."
            )
        }
        func addCalls(_ position: Int, arguments: [CompiledValue], indices: [Int]) {
            guard position < action.bindings.count else {
                let suffix = indices.isEmpty ? "" : "__\(indices.map(String.init).joined(separator: "_"))"
                calls.append((
                    call: .init(action: action.id, arguments: arguments),
                    renderedName: "\(emittedName)\(suffix)"
                ))
                return
            }
            for (index, value) in action.bindings[position].values.enumerated() {
                addCalls(position + 1, arguments: arguments + [value], indices: indices + [index])
            }
        }
        addCalls(0, arguments: [], indices: [])
    }
    return calls
}

/// Encodes the lowered declaration plan with unambiguous field boundaries.
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
        let collections = spec.collections.map {
            node("model-collection", [
                $0.name,
                String($0.verificationScope),
                canonicalValue($0.initial)
            ])
        }
        list("collections", collections) { $0 }
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
            canonicalInitialization(variable.initialization),
            collection,
            canonicalOptional(variable.generatedSwiftType)
        ])
    }

    private func canonicalInitialization(_ initialization: VariableInitialization) -> String {
        switch initialization {
        case .value(let value): return node("value", [canonicalValue(value)])
        case .expression(let expression): return node("expression", [canonicalExpression(expression)])
        case .memberOf(let set): return node("member-of", [canonicalExpression(set)])
        }
    }

    private func canonicalAction(_ action: NamedAction) -> String {
        return node("action", [
            action.name,
            canonicalActionExpression(action.body),
            canonicalList(action.bindings.map {
                node("action-binding", [
                    $0.name,
                    canonicalList($0.values.map(canonicalValue)),
                    canonicalOptional($0.generatedSwiftType)
                ])
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

    private func canonicalActionExpression(
        _ expression: ActionExpr,
        bindingNames: [String] = []
    ) -> String {
        node("action", [alphaKey(expression, bindingNames: bindingNames)])
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
