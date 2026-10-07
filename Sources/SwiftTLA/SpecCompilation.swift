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
    public let parameters: [ParameterDescription]
    public let variables: [VariableDescription]
    public let actions: [ActionDescription]
    public let algorithms: [AlgorithmDescription]
    public let invariants: [String]
    public let reachabilityProperties: [String]
    public let temporalProperties: [String]
    public let refinements: [String]
    public let stateConstraint: String?
    public let procedures: [ProcedureDescription]
    public let controlLocations: [ControlLocationDescription]
    public let imports: [ModuleDescription]
}

public struct ParameterDescription: Sendable, Equatable {
    public let name: String
    public let displayName: String
}

public struct VariableDescription: Sendable, Equatable {
    public let name: String
    public let displayName: String
    public let sourceOffset: Int?
}

public struct ActionDescription: Sendable, Equatable {
    public let name: String
    public let renderedName: String
    public let sourceOffset: Int?
}

public struct AlgorithmDescription: Sendable, Equatable {
    public let name: String
    public let displayName: String
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

/// TLA+ output and declaration text shared with authored PlusCal rendering.
package struct RenderedModule: Sendable, Equatable {
    var moduleReplacements: [TLCModuleReplacement] = []
    package var imports: [TLAModuleFile] = []
    package var importedOwnership: [TLAModuleBundle.OwnershipEntry] = []
    package var dependencies: [TLAModuleBundle.ModuleDependency] = []
    package let renderedModuleSource: String
    package let configuration: TLCConfiguration
    package let renderedActions: [RenderedAction]
    package let symbolicActions: [ActionID]
    let definitions: [String]
    let instances: [String]
    let refinements: [String]
    let properties: [PropertyID: String]
    let constraint: String?
    package var temporalObligations: [PropertyID: [_RenderedTemporalObligation]] = [:]
    package var temporalBindingNames: [BinderID: String] = [:]
}

public struct RenderedAction: Sendable, Equatable {
    public let sourceName: String
    public let emittedBaseName: String
    public let arguments: [TLAValue]
    public let renderedName: String

    public init(sourceName: String, emittedBaseName: String? = nil,
        arguments: [TLAValue], renderedName: String) {
        self.sourceName = sourceName
        self.emittedBaseName = emittedBaseName ?? sourceName
        self.arguments = arguments
        self.renderedName = renderedName
    }

    public var sourceInvocationName: String {
        FormalActionCall(name: sourceName, arguments: arguments).description
    }

    public var emittedInvocationName: String {
        FormalActionCall(name: emittedBaseName, arguments: arguments).description
    }
}

/// Resolved TLC directive kinds for checks selected from a rendered model.
public struct RenderedCheckSelection: Sendable, Equatable {
    public let tlcInvariantNames: [String]
    public let tlcPropertyNames: [String]
    public let checkDeadlock: Bool

    fileprivate init(configuration: TLCConfiguration) {
        tlcInvariantNames = configuration.invariants + configuration.reachabilityProperties
        tlcPropertyNames = configuration.properties + configuration.refinements
        checkDeadlock = configuration.checkDeadlock
    }
}

struct DirectModuleAction: Sendable, Equatable {
    let sourceName: String
    let renderedName: String
    let renderedParameters: [String]
    let renderedBody: String
    let calls: [RenderedAction]
    let symbolicInvocation: String?
}

struct CompiledRefinement: Sendable {
    let id: PropertyID
    let name: String
    let instance: ModuleInstanceID
    let `operator`: RefinementDecl.Operator
    let abstract: CompiledSpecification
    let variableMappings: [CompiledStateQuery]
}

package struct CompiledGeneratedModelBinding: Sendable {
    package let fieldName: String
    package let value: CompiledStateQuery
    package let projected: Bool

    package init(fieldName: String, value: CompiledStateQuery, projected: Bool = false) {
        self.fieldName = fieldName
        self.value = value
        self.projected = projected
    }

    func map(_ transform: (CompiledExpression) throws -> CompiledExpression) rethrows -> Self {
        .init(fieldName: fieldName, value: try value.map(transform), projected: projected)
    }
}

package struct CompiledGeneratedModelRefinement: Sendable {
    package let id: PropertyID
    package let name: String
    package let instanceName: String
    package let targetModelType: String
    package let behavior: ModelBehavior
    package let parameters: [CompiledGeneratedModelBinding]
    package let state: [CompiledGeneratedModelBinding]

    func map(_ transform: (CompiledExpression) throws -> CompiledExpression) rethrows -> Self {
        .init(id: id, name: name, instanceName: instanceName, targetModelType: targetModelType,
            behavior: behavior,
            parameters: try parameters.map { try $0.map(transform) },
            state: try state.map { try $0.map(transform) })
    }
}

/// Source metadata needed by renderers after executable declarations are lowered.
struct CompiledModuleMetadata: Sendable {
    var name: String
    let constants: [ConstantDecl]
    let formalParameters: [FormalModuleParameter]
    var modelValueNames: Set<String>
    let extendsModules: [StandardModule]
    var imports: [String]
    let symmetrySets: [SymmetrySet]
    let formalDefinitionCount: Int
    let recursiveFunctionCount: Int

    func constantDeclaration(including additionalNames: [String]) -> String? {
        let formalConstants = formalParameters.filter { $0.kind == .constant }.map(\.name)
        let names = Set(constants.map(\.name) + formalConstants + additionalNames).union(modelValueNames).sorted()
        return names.isEmpty ? nil : "CONSTANTS \(names.joined(separator: ", "))"
    }

    init(source: TLASpec, modelValueNames: Set<String>) {
        self.modelValueNames = modelValueNames
        name = source.name
        constants = source.constants
        formalParameters = source.formalParameters
        extendsModules = source.extendsModules
        imports = source.imports.map(\.name)
        symmetrySets = source.symmetrySets
        formalDefinitionCount = source.formalOperatorDefinitions.count
        recursiveFunctionCount = source.recursiveFuncs.count
    }
}

fileprivate struct CompiledModule: Sendable {
    let metadata: CompiledModuleMetadata
    let layout: CompiledLayout
    let bindings: CompiledBindingTable
    let semantics: CompiledSemantics
    let refinements: [CompiledRefinement]
    let generatedRefinements: [CompiledGeneratedModelRefinement]
    let authoredAlgorithm: (plan: CompiledAuthoredPlusCalAlgorithmPlan, declarations: AuthoredPlusCalDeclarationOrder)?
    let requiredStandardModules: Set<StandardModule>
    let definitionsBeforeInstances: [Int]
    let definitionsAfterInstances: [Int]
}

/// Formal dependencies retain compiled declarations until the export boundary.
struct CompiledModuleImports: Sendable {
    fileprivate let root: String
    fileprivate let modules: [CompiledModule]
    fileprivate let provenance: TLAModuleBundle.Provenance

    private var dependencies: [TLAModuleBundle.ModuleDependency] {
        guard case .compiled(_, _, let dependencies) = provenance else {
            preconditionFailure("Compiler-owned imports require compiled provenance")
        }
        return dependencies
    }

    private func selectedNames(_ directImports: [String]) -> Set<String> {
        var selected = Set(directImports)
        var pending = directImports
        while let name = pending.popLast() {
            for edge in dependencies where edge.importingModule == name {
                if selected.insert(edge.importedModule).inserted { pending.append(edge.importedModule) }
            }
        }
        return selected
    }

    fileprivate func names(for directImports: [String], namespace: String?, configured: Bool) -> [String: String] {
        let selected = selectedNames(directImports)
        let needsNamespace = configured || modules.contains {
            selected.contains($0.metadata.name) && !$0.semantics.formalModuleReplacements.isEmpty
        }
        return Dictionary(uniqueKeysWithValues: selected.sorted().enumerated().map { offset, name in
            (name, needsNamespace ? namespace.map { "\($0)__Import\(offset)" } ?? name : name)
        })
    }

    fileprivate func replacements(for directImports: [String], moduleNames: [String: String]) -> [TLCModuleReplacement] {
        let selected = selectedNames(directImports)
        return modules.filter { selected.contains($0.metadata.name) }.flatMap {
            $0.semantics.formalModuleReplacements.map { $0.configuration(moduleNames: moduleNames) }
        }
    }

    fileprivate func append(to result: inout RenderedModule, directImports: [String], moduleNames: [String: String],
                            rootName: String, owningRoot: String, structuralPath: [String]) throws {
        guard case .compiled(_, let ownership, _) = provenance else {
            preconditionFailure("Compiler-owned imports require compiled provenance")
        }
        let selected = selectedNames(directImports)
        for module in modules where selected.contains(module.metadata.name) {
            let rendered = try module.metadata.renderModule(module, moduleNames: moduleNames)
            result.imports.append(.init(name: moduleNames[module.metadata.name] ?? module.metadata.name,
                tla: rendered.renderedModuleSource))
        }
        result.importedOwnership += ownership.filter { selected.contains($0.moduleName) }.map {
            .init(moduleName: moduleNames[$0.moduleName] ?? $0.moduleName, owningRoot: owningRoot,
                structuralPath: structuralPath + $0.structuralPath)
        }
        result.dependencies += dependencies.filter {
            selected.contains($0.importingModule)
                || ($0.importingModule == root && directImports.contains($0.importedModule))
        }.map {
            .init(importingModule: $0.importingModule == root ? rootName : moduleNames[$0.importingModule] ?? $0.importingModule,
                importedModule: moduleNames[$0.importedModule] ?? $0.importedModule,
                structuralPath: structuralPath + $0.structuralPath)
        }
    }
}

/// The validated program consumed by native generation, formal execution, and rendering.
public struct CompiledSpecification: Sendable {
    public let description: CompilationDescription
    public var identity: CompilationIdentity { description.identity }
    var moduleMetadata: CompiledModuleMetadata { module.metadata }
    var moduleImports: CompiledModuleImports {
        .init(root: module.metadata.name, modules: imports, provenance: provenance)
    }
    var requiredStandardModules: Set<StandardModule> { module.requiredStandardModules }
    package var layout: CompiledLayout { module.layout }
    package var semantics: CompiledSemantics { module.semantics }
    var bindings: CompiledBindingTable { module.bindings }
    var refinements: [CompiledRefinement] { module.refinements }
    var generatedRefinements: [CompiledGeneratedModelRefinement] { module.generatedRefinements }
    var authoredAlgorithm: CompiledAuthoredPlusCalAlgorithmPlan? { module.authoredAlgorithm?.plan }
    fileprivate let module: CompiledModule
    fileprivate let imports: [CompiledModule]
    fileprivate let provenance: TLAModuleBundle.Provenance

    /// Render verification artifacts from the existing program without compiling it again.
    public func render() throws -> RenderedSpecification {
        guard module.generatedRefinements.isEmpty else {
            throw CompilationDiagnostic(code: .unsupportedRefinementTarget, stage: .rendering,
                path: "generatedRefinements", expected: "typed generated-model linking",
                actual: "CompiledSpecification has no generated target type",
                nextSafeAction: "Render through the generated model's typed export.")
        }
        let metadata = module.metadata
        let rootModule = try metadata.renderModule(module)
        guard rootModule.symbolicActions.isEmpty else {
            throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .rendering,
                path: "export.\(metadata.name).actions",
                expected: "configured action invocation metadata", actual: "symbolic action domains",
                nextSafeAction: "Export through the generated model with its typed configuration.")
        }
        let renderedBundle = TLAModuleBundle(
            root: .init(name: metadata.name, tla: rootModule.renderedModuleSource, cfg: rootModule.configuration.render(usesSymmetryReduction: false)),
            imports: try imports.map { imported in
                let plan = try imported.metadata.renderModule(imported)
                return .init(name: imported.metadata.name, tla: plan.renderedModuleSource, cfg: nil)
            },
            provenance: provenance
        )
        try renderedBundle.validateDeclaredClosure()
        let renderer = CompiledTLARenderer(moduleName: metadata.name,
            reservedNames: metadata.modelValueNames.union(metadata.constants.map(\.name)).union(metadata.formalParameters.map(\.name)),
            layout: module.layout, bindings: module.bindings,
            operators: module.semantics.operators, actions: module.semantics.behavior.actions, functions: [])
        let algorithm = try module.authoredAlgorithm.map { authored in
            try metadata.authoredPlusCalModule(
                algorithm: authored.plan, declarationOrder: authored.declarations,
                layout: module.layout, declarations: rootModule,
                parameterNames: try module.layout.parameters.map { try renderer.binderName($0.binder) }
            )
        }
        let plusCalBundle = try algorithm.map { algorithm in
            let bundle = TLAModuleBundle(
                root: .init(name: metadata.name,
                    tla: try AlgorithmPlusCalRenderer(module: algorithm, formalRenderer: renderer).render(),
                    cfg: renderedBundle.root.cfg),
                imports: renderedBundle.imports, provenance: provenance
            )
            try bundle.validateDeclaredClosure()
            return bundle
        }
        return RenderedSpecification(
            tlaBundle: renderedBundle,
            configuration: rootModule.configuration,
            actions: rootModule.renderedActions, renderedPlusCalModuleBundle: plusCalBundle.map { .success($0) },
            fairnessProfileOperators: Dictionary(uniqueKeysWithValues: module.semantics.behavior.fairnessProfiles.map {
                ($0.name, $0.operatorName)
            }),
            temporalObligations: Dictionary(uniqueKeysWithValues: module.semantics.behavior.temporalProperties.compactMap { property in
                guard property.bindings.isEmpty, let obligations = rootModule.temporalObligations[property.id] else { return nil }
                return (property.name, obligations)
            })
        )
    }
}

/// Verification output rendered once and reusable by exporters and TLC checks.
public struct RenderedSpecification: Sendable {
    public let tlaBundle: TLAModuleBundle
    fileprivate let configuration: TLCConfiguration
    public let actions: [RenderedAction]
    fileprivate let renderedPlusCalModuleBundle: Result<TLAModuleBundle, CompilationDiagnostic>?
    fileprivate let renderedPlusCalProfiles: [String: Result<TLAModuleBundle, CompilationDiagnostic>]
    fileprivate let fairnessProfileOperators: [String: String]
    package let temporalObligations: [String: [_RenderedTemporalObligation]]

    init(tlaBundle: TLAModuleBundle, configuration: TLCConfiguration, actions: [RenderedAction],
        renderedPlusCalModuleBundle: Result<TLAModuleBundle, CompilationDiagnostic>?,
        renderedPlusCalProfiles: [String: Result<TLAModuleBundle, CompilationDiagnostic>] = [:],
        fairnessProfileOperators: [String: String] = [:],
        temporalObligations: [String: [_RenderedTemporalObligation]] = [:]) {
        self.tlaBundle = tlaBundle
        self.configuration = configuration
        self.actions = actions
        self.renderedPlusCalModuleBundle = renderedPlusCalModuleBundle
        self.renderedPlusCalProfiles = renderedPlusCalProfiles
        self.fairnessProfileOperators = fairnessProfileOperators
        self.temporalObligations = temporalObligations.mapValues { obligations in
            obligations.sorted {
                ($0.initialCondition, $0.property) < ($1.initialCondition, $1.property)
            }
        }
    }

    /// Final artifact boundary used by generated machines; this does not compile or interpret a model.
    @_documentation(visibility: internal)
    public init(_generatedModule name: String, source: String, compilationIdentity: String,
        declarations: [String], checkDeadlock: Bool, invariants: [String], reachabilityProperties: [String], properties: [String], refinements: [String],
        symmetry: [String], actions: [RenderedAction], _generatedPlusCal: Result<String, CompilationDiagnostic>? = nil,
        _generatedPlusCalProfiles: [String: Result<String, CompilationDiagnostic>] = [:],
        _assumptionsOnly: Bool = false,
        _generatedParameters: [(name: String, value: TLAValue)] = [],
        _generatedImports: [(name: String, source: String, structuralPath: [String])] = [],
        _generatedDependencies: [(importingModule: String, importedModule: String, structuralPath: [String])] = [],
        _generatedFairnessProfileOperators: [String: String] = [:],
        _generatedTemporalObligations: [String: [_RenderedTemporalObligation]] = [:]) throws {
        var declarations = declarations
        var definitions: [String] = []
        var prefix = "__SwiftTLAParameter"
        let sources = [source] + _generatedImports.map(\.source)
            + [(try? _generatedPlusCal?.get()) ?? ""] + declarations + _generatedParameters.map(\.name)
        while sources.contains(where: { $0.contains(prefix) }) { prefix += "_" }
        for (index, parameter) in _generatedParameters.enumerated() {
            if parameter.value.isTLCConfigurationLiteral {
                declarations.append("CONSTANT \(parameter.name) = \(parameter.value)")
            } else {
                let definition = "\(prefix)\(index)"
                definitions.append("\(definition) == \(parameter.value)")
                declarations.append("CONSTANT \(parameter.name) <- \(definition)")
            }
        }
        func configuredSource(_ source: String) throws -> String {
            guard !definitions.isEmpty else { return source }
            guard let end = source.range(of: "====", options: .backwards) else {
                throw CompilationDiagnostic(code: .unknownReference, stage: .rendering, path: "configuration",
                    expected: "a complete rendered module", actual: "missing module terminator",
                    nextSafeAction: "Render the resolved model before binding configuration.")
            }
            return String(source[..<end.lowerBound]) + definitions.joined(separator: "\n") + "\n" + source[end.lowerBound...]
        }
        if _assumptionsOnly && (checkDeadlock || !invariants.isEmpty || !reachabilityProperties.isEmpty
            || !properties.isEmpty || !refinements.isEmpty || !symmetry.isEmpty || !actions.isEmpty) {
            throw CompilationDiagnostic(code: .unknownReference, stage: .rendering,
                path: "assumption-only export", expected: "assumptions without state-machine checks",
                actual: "state-machine selection", nextSafeAction: "Remove state checks from this state-free model.")
        }
        let configuration = TLCConfiguration(assumptionsOnly: _assumptionsOnly,
            declarations: declarations, checkDeadlock: checkDeadlock,
            invariants: invariants, reachabilityProperties: reachabilityProperties, properties: properties, refinements: refinements, symmetry: symmetry)
        let bundle = TLAModuleBundle(root: .init(name: name, tla: try configuredSource(source),
            cfg: configuration.render(usesSymmetryReduction: false)),
            imports: _generatedImports.map { .init(name: $0.name, tla: $0.source) }, provenance: .compiled(
                identity: .init(value: compilationIdentity),
                ownership: [.init(moduleName: name, owningRoot: name, structuralPath: [])]
                    + _generatedImports.map { .init(moduleName: $0.name, owningRoot: name, structuralPath: $0.structuralPath) },
                dependencies: _generatedDependencies.map {
                    .init(importingModule: $0.importingModule, importedModule: $0.importedModule, structuralPath: $0.structuralPath)
                }))
        try bundle.validateDeclaredClosure()
        func configuredPlusCal(_ result: Result<String, CompilationDiagnostic>) throws -> Result<TLAModuleBundle, CompilationDiagnostic> {
            switch result {
            case .failure(let diagnostic): return .failure(diagnostic)
            case .success(let source):
                let authored = TLAModuleBundle(root: .init(name: name, tla: try configuredSource(source), cfg: bundle.root.cfg),
                    imports: bundle.imports, provenance: bundle.provenance)
                try authored.validateDeclaredClosure()
                return .success(authored)
            }
        }
        let plusCal = try _generatedPlusCal.map(configuredPlusCal)
        let plusCalProfiles = try _generatedPlusCalProfiles.mapValues(configuredPlusCal)
        self.init(tlaBundle: bundle, configuration: configuration, actions: actions, renderedPlusCalModuleBundle: plusCal,
            renderedPlusCalProfiles: plusCalProfiles,
            fairnessProfileOperators: _generatedFairnessProfileOperators,
            temporalObligations: _generatedTemporalObligations)
    }

    /// Links another generated model's compiled TLA at the final export boundary.
    @_documentation(visibility: internal)
    public func addingGeneratedRefinement<Abstract: ConfiguredGeneratedModel>(
        _ name: String, instance: String, of abstract: Abstract.Type,
        configuration abstractConfiguration: Abstract.Configuration,
        behavior: ModelBehavior = .specification,
        parameters: [(PartialKeyPath<Abstract.Configuration>, String)],
        state: [(PartialKeyPath<Abstract.State>, String)]
    ) throws -> Self {
        guard !configuration.assumptionsOnly, isTLADeclarationName(name), isTLADeclarationName(instance),
              !checkNames.contains(name), name != instance else {
            throw CompilationDiagnostic(code: .duplicateRefinement, stage: .rendering,
                path: "refinements.\(name)", expected: "distinct formal refinement and instance names",
                actual: "\(instance), \(name)", nextSafeAction: "Use distinct bound identities in #spec.")
        }
        func substitutions<Root>(
            _ values: [(PartialKeyPath<Root>, String)],
            names: [PartialKeyPath<Root>: GeneratedModelFieldIdentity], kind: String
        ) throws -> [(String, String)] {
            let mapped = try values.map { keyPath, expression in
                guard let target = names[keyPath]?.formalName,
                      !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CompilationDiagnostic(code: .unknownRefinementMappingTarget, stage: .rendering,
                        path: "refinements.\(name).\(kind)", expected: "a generated target field and resolved expression",
                        actual: "an unknown target or empty expression",
                        nextSafeAction: "Map a generated member of the abstract model.")
                }
                return (target, expression)
            }
            guard mapped.count == names.count, Set(mapped.map { $0.0 }).count == names.count else {
                throw CompilationDiagnostic(code: .incompleteRefinementMapping, stage: .rendering,
                    path: "refinements.\(name).\(kind)", expected: "one mapping for every generated target field",
                    actual: "\(mapped.count) mappings for \(names.count) fields",
                    nextSafeAction: "Map every abstract field exactly once.")
            }
            return mapped
        }
        let bindings = try substitutions(parameters, names: Abstract.Configuration.fieldIdentities, kind: "parameters")
            + substitutions(state, names: Abstract.State.fieldIdentities, kind: "state")
        let target = try abstract.render(configuration: abstractConfiguration).tlaBundle
        guard case .compiled(let targetIdentity, let targetOwnership, let targetDependencies) = target.provenance else {
            throw CompilationDiagnostic(code: .compilationIdentityMismatch, stage: .rendering,
                path: "refinements.\(name).abstract", expected: "a generated compiled abstract model",
                actual: "external formal input", nextSafeAction: "Use a generated model as the refinement target.")
        }
        let replacement = bindings.sorted { $0.0 < $1.0 }
            .map { "\($0.0) <- (\($0.1))" }.joined(separator: ", ")
        let property = behavior == .specification
            ? "\(instance)!Spec"
            : "\(instance)!Init /\\ [][\(instance)!Next]_\(instance)!vars"
        let definitions = "\(instance) == INSTANCE \(target.root.name)"
            + (replacement.isEmpty ? "" : " WITH " + replacement)
            + "\n\(name) == \(property)\n"
        let selected = TLCConfiguration(behavior: configuration.behavior,
            specificationName: configuration.specificationName, assumptionsOnly: configuration.assumptionsOnly,
            declarations: configuration.declarations, checkDeadlock: configuration.checkDeadlock,
            invariants: configuration.invariants, reachabilityProperties: configuration.reachabilityProperties,
            properties: configuration.properties, refinements: configuration.refinements + [name],
            symmetry: configuration.symmetry)
        func linked(_ source: TLAModuleBundle) throws -> TLAModuleBundle {
            guard let end = source.root.tla.range(of: "====", options: .backwards),
                  case .compiled(let rootIdentity, let rootOwnership, let rootDependencies) = source.provenance else {
                throw CompilationDiagnostic(code: .compilationIdentityMismatch, stage: .rendering,
                    path: "refinements.\(name).source", expected: "a complete generated concrete module",
                    actual: "an incomplete or external module", nextSafeAction: "Render the generated concrete model first.")
            }
            let sourceText = String(source.root.tla[..<end.lowerBound]) + definitions + source.root.tla[end.lowerBound...]
            var imports = source.imports
            for file in [target.root] + target.imports {
                if let existing = imports.first(where: { $0.name == file.name }) {
                    // ponytail: distinct sources with one module name need compiler-assigned import namespaces.
                    guard existing.tla == file.tla else { throw TLAModuleBundleIntegrityError.duplicateModule(file.name) }
                } else {
                    imports.append(.init(name: file.name, tla: file.tla))
                }
            }
            let identityInput = rootIdentity.value + ":" + targetIdentity.value + ":" + definitions
            let identity = CompilationIdentity(value: SHA256.hash(data: Data(identityInput.utf8))
                .map { String(format: "%02x", $0) }.joined())
            let path = [instance]
            let ownership = rootOwnership + targetOwnership.map {
                TLAModuleBundle.OwnershipEntry(moduleName: $0.moduleName,
                    owningRoot: source.root.name, structuralPath: path + $0.structuralPath)
            }
            let dependencies = rootDependencies
                + [.init(importingModule: source.root.name, importedModule: target.root.name, structuralPath: path)]
                + targetDependencies.map {
                    .init(importingModule: $0.importingModule, importedModule: $0.importedModule,
                        structuralPath: path + $0.structuralPath)
                }
            let bundle = TLAModuleBundle(root: .init(name: source.root.name, tla: sourceText,
                cfg: selected.render(usesSymmetryReduction: false)), imports: imports,
                provenance: .compiled(identity: identity, ownership: ownership, dependencies: dependencies))
            try bundle.validateDeclaredClosure()
            return bundle
        }
        func linkedResult(_ result: Result<TLAModuleBundle, CompilationDiagnostic>) throws
            -> Result<TLAModuleBundle, CompilationDiagnostic> {
            switch result {
            case .success(let bundle): return .success(try linked(bundle))
            case .failure(let diagnostic): return .failure(diagnostic)
            }
        }
        return try Self(tlaBundle: linked(tlaBundle), configuration: selected, actions: actions,
            renderedPlusCalModuleBundle: renderedPlusCalModuleBundle.map(linkedResult),
            renderedPlusCalProfiles: renderedPlusCalProfiles.mapValues(linkedResult),
            fairnessProfileOperators: fairnessProfileOperators, temporalObligations: temporalObligations)
    }

    public func tlaBundle(
        symmetryReduction: SymmetryReduction
    ) throws -> TLAModuleBundle {
        let usesSymmetryReduction = try configuration.usesSupportedSymmetryReduction(symmetryReduction)
        return TLAModuleBundle(
            root: .init(
                name: tlaBundle.root.name,
                tla: tlaBundle.root.tla,
                cfg: configuration.render(usesSymmetryReduction: usesSymmetryReduction)
            ),
            imports: tlaBundle.imports,
            provenance: tlaBundle.provenance
        )
    }

    public var invariantNames: Set<String> { Set(configuration.invariants) }
    public var reachabilityNames: Set<String> { Set(configuration.reachabilityProperties) }
    public var temporalNames: Set<String> { Set(configuration.properties) }
    public var refinementNames: Set<String> { Set(configuration.refinements) }
    public var checkNames: Set<String> { Set(configuration.invariants + configuration.reachabilityProperties + configuration.properties + configuration.refinements) }
    public var checksDeadlock: Bool { configuration.checkDeadlock }
    public var isAssumptionsOnly: Bool { configuration.assumptionsOnly }
    public var behavior: ModelBehavior { configuration.behavior }

    public func temporalObligationBundles(checking name: String) throws -> [TLAModuleBundle]? {
        _ = try configuration.selecting([name], checkDeadlock: false)
        guard let obligations = temporalObligations[name], !obligations.isEmpty else { return nil }
        let source = tlaBundle.root.tla
        guard let end = source.range(of: "====", options: .backwards) else {
            throw CompilationDiagnostic(code: .unknownReference, stage: .rendering, path: "temporal obligations",
                expected: "a complete rendered module", actual: "missing module terminator",
                nextSafeAction: "Render the resolved model before selecting checks.")
        }
        var prefix = "__SwiftTLAObligation"
        let sources = [source] + tlaBundle.imports.map(\.tla)
        while sources.contains(where: { $0.contains(prefix) }) { prefix += "_" }
        return obligations.map { obligation in
            let behaviorName = prefix + "Behavior"
            let propertyName = prefix + "Property"
            let behavior = configuration.behavior == .specification ? configuration.specificationName : "Init"
            let definitions = "\(behaviorName) == \(behavior) /\\ (\(obligation.initialCondition))\n"
                + "\(propertyName) == \(obligation.property)\n\n"
            let directives = configuration.behavior == .specification
                ? ["SPECIFICATION \(behaviorName)"] : ["INIT \(behaviorName)", "NEXT Next"]
            let cfg = (directives + ["CHECK_DEADLOCK FALSE"] + configuration.declarations
                + ["PROPERTY \(propertyName)"]).joined(separator: "\n") + "\n"
            return TLAModuleBundle(root: .init(name: tlaBundle.root.name,
                tla: String(source[..<end.lowerBound]) + definitions + source[end.lowerBound...], cfg: cfg),
                imports: tlaBundle.imports, provenance: tlaBundle.provenance)
        }
    }

    /// Converts model-owned check identities at the formal export boundary.
    public func selectingChecks<Property: Hashable & Sendable>(_ checks: ModelChecks<Property>, formalPropertyNames: [Property: String],
        behavior: ModelBehavior? = nil, symmetry: String? = nil, fairnessProfile: String? = nil) throws -> Self {
        let names = try Set(checks.properties.map { property in
            guard let name = formalPropertyNames[property] else {
                throw CompilationDiagnostic(code: .unknownReference, stage: .rendering, path: "check selection",
                    expected: "a formal name for each selected property", actual: "missing property projection",
                    nextSafeAction: "Use the generated model's formal property names.")
            }
            return name
        })
        guard names.count == checks.properties.count else {
            throw CompilationDiagnostic(code: .unknownReference, stage: .rendering, path: "check selection",
                expected: "distinct formal names for selected properties", actual: "duplicate property projection",
                nextSafeAction: "Use the generated model's formal property names.")
        }
        let profileOperator: String?
        if let fairnessProfile {
            guard (behavior ?? configuration.behavior) == .specification,
                  let operatorName = fairnessProfileOperators[fairnessProfile] else {
                throw CompilationDiagnostic(code: .unsupportedFairnessProfile, stage: .rendering,
                    path: "fairnessProfile", expected: "a declared profile selected with specification behavior",
                    actual: fairnessProfile, nextSafeAction: "Select a profile declared by this model.")
            }
            profileOperator = operatorName
        } else {
            profileOperator = nil
        }
        let selected = try configuration.selecting(names, checkDeadlock: checks.checkDeadlock,
                behavior: behavior, specificationName: profileOperator)
            .selectingSymmetry(symmetry)
        func bundle(_ original: TLAModuleBundle, using configuration: TLCConfiguration) -> TLAModuleBundle {
            .init(root: .init(name: original.root.name, tla: original.root.tla,
                cfg: configuration.render(usesSymmetryReduction: symmetry != nil)), imports: original.imports, provenance: original.provenance)
        }
        let selectedPlusCal: Result<TLAModuleBundle, CompilationDiagnostic>?
        if let fairnessProfile {
            let profileConfiguration = try selected.selecting(names, checkDeadlock: checks.checkDeadlock,
                specificationName: "Spec")
            if let profile = renderedPlusCalProfiles[fairnessProfile] {
                selectedPlusCal = profile.map { bundle($0, using: profileConfiguration) }
            } else if renderedPlusCalModuleBundle != nil {
                selectedPlusCal = .failure(.init(code: .unsupportedFairnessProfile, stage: .rendering,
                    path: "plusCal.fairnessProfile", expected: "a compiled profile-specific PlusCal bundle",
                    actual: fairnessProfile, nextSafeAction: "Export through the generated model's typed configuration."))
            } else {
                selectedPlusCal = nil
            }
        } else {
            selectedPlusCal = renderedPlusCalModuleBundle.map { $0.map { bundle($0, using: selected) } }
        }
        return .init(tlaBundle: bundle(tlaBundle, using: selected), configuration: selected, actions: actions,
            renderedPlusCalModuleBundle: selectedPlusCal,
            renderedPlusCalProfiles: renderedPlusCalProfiles,
            fairnessProfileOperators: fairnessProfileOperators,
            temporalObligations: temporalObligations.filter { names.contains($0.key) })
    }

    /// Selects declared checks for an independent validation pass without rendering the model again.
    /// Symmetry defaults to disabled so the pass retains the complete, unreduced graph.
    public func tlaBundle(checking checks: Set<String>, checkDeadlock: Bool,
        symmetryReduction: SymmetryReduction = .disabled, behavior: ModelBehavior? = nil) throws -> TLAModuleBundle {
        let selected = try configuration.selecting(checks, checkDeadlock: checkDeadlock, behavior: behavior)
        let usesSymmetryReduction = try selected.usesSupportedSymmetryReduction(symmetryReduction)
        return TLAModuleBundle(
            root: .init(name: tlaBundle.root.name, tla: tlaBundle.root.tla,
                cfg: selected.render(usesSymmetryReduction: usesSymmetryReduction)),
            imports: tlaBundle.imports, provenance: tlaBundle.provenance
        )
    }

    /// Select only checks declared by this rendered model, retaining their
    /// resolved formal names and TLC check kinds.
    public func checkSelection(checking names: Set<String>, checkDeadlock: Bool) throws -> RenderedCheckSelection {
        RenderedCheckSelection(configuration: try configuration.selecting(names, checkDeadlock: checkDeadlock))
    }

    /// Returns the source-faithful PlusCal bundle produced by rendering.
    public func plusCalBundle() throws -> TLAModuleBundle {
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
        return try renderedPlusCalModuleBundle.get()
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
        case invalidTypedFunctionLiteral
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
        case emptySpecificationName
        case invalidSpecificationName
        case duplicateVariable
        case duplicateAction
        case duplicateInvariant
        case duplicateAlgorithm
        case invalidAuthoredPlusCalPlan
        case invalidSymmetryDeclaration
        case unsupportedSymmetryReduction
        case unsupportedFairnessProfile
        case duplicateRecordField
        case compilationIdentityMismatch
        case unsupportedGeneratedValueShape
        case unsupportedReachabilityEvaluation
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
        case stateDependentFormalModuleReplacement
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
    package var sourceOffset: Int?

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
        sourceOffset = nil
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

        let declarationGroups: [([String], String, String)] = [
            (variables.map(\.name), "variable", "variables"),
            (constants.map(\.name), "constant", "constants"),
            (invariants.map(\.name), "invariant", "invariants"),
            (reachabilityProperties.map(\.name), "reachability property", "reachabilityProperties"),
            (temporalProperties.map(\.name), "temporal property", "temporalProperties"),
            (recursiveFuncs.map(\.name), "recursive operator", "recursiveFunctions"),
            (formalOperatorDefinitions.map(\.name), "formal operator", "formalOperators"),
            (moduleInstances.map(\.name), "module instance", "moduleInstances"),
            (refinements.map(\.name), "refinement", "refinements"),
            (generatedModelInstances.map(\.name), "generated model instance", "generatedModelInstances"),
            (generatedRefinements.map(\.name), "generated refinement", "generatedRefinements")
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
        let compiledRefinements = module.refinements
        let compiledGeneratedRefinements = module.generatedRefinements
        let identity = compilationIdentity
        let imports = try closure.entries.filter { $0.id != closure.root.id }.map { entry in
            let source = try entry.module.loweredSourceModel()
            let context = closure.planContext(for: entry)
            return try source.compileModule(in: context.closure, incomingModuleParameters: context.incomingModuleParameters)
        }
        let provenance = TLAModuleBundle.Provenance.compiled(
            identity: identity,
            ownership: closure.entries.map {
                .init(moduleName: $0.module.name, owningRoot: $0.owningRoot, structuralPath: $0.structuralPath)
            },
            dependencies: closure.edges.map {
                .init(importingModule: $0.fromModule, importedModule: $0.toModule, structuralPath: $0.structuralPath)
            }
        )
        let description = CompilationDescription(
            name: name,
            identity: identity,
            parameters: layout.parameters.map {
                .init(name: $0.reference.name, displayName: $0.reference.displayLabel ?? $0.reference.name)
            },
            variables: layout.variables.map {
                .init(name: $0.declaration.name, displayName: $0.displayLabel ?? $0.declaration.name,
                    sourceOffset: $0.declaration.sourceOffset)
            },
            actions: layout.actions.map {
                .init(
                    name: $0.declaration.name,
                    renderedName: $0.renderedName,
                    sourceOffset: $0.declaration.sourceOffset
                )
            },
            algorithms: sourceAlgorithms.map {
                .init(name: $0.model.name, displayName: $0.model.displayLabel ?? $0.model.name)
            },
            invariants: semantics.behavior.invariants.map(\.name),
            reachabilityProperties: semantics.behavior.reachabilityProperties.map(\.name),
            temporalProperties: semantics.behavior.temporalProperties.map(\.name),
            refinements: compiledRefinements.map(\.name) + compiledGeneratedRefinements.map(\.name),
            stateConstraint: semantics.behavior.constraint.map { _ in "StateConstraint" },
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
        return CompiledSpecification(description: description, module: module, imports: imports, provenance: provenance)
    }

    private func compileModule(
        in closure: FormalModuleClosure,
        incomingModuleParameters: [FormalModuleReplacement] = []
    ) throws -> CompiledModule {
        try validateUnique(variables.map(\.name), code: .duplicateVariable, path: "variables")
        try validateUnique(actions.map(\.name), code: .duplicateAction, path: "actions")
        try validateUnique(invariants.map(\.name), code: .duplicateInvariant, path: "invariants")
        try validateUnique((invariants + reachabilityProperties).map(\.name) + temporalProperties.map(\.name),
            code: .duplicateInvariant, path: "properties")
        try validateSymmetryDeclarations()
        try validateRefinements()
        try validateGeneratedRefinements()
        let definitionOrder = try orderedDirectDefinitions()
        let layout = CompiledLayout(source: self)
        var lowerer = CompiledLowerer(
            spec: self, closure: closure, layout: layout,
            incomingModuleParameters: incomingModuleParameters
        )
        var semantics = try lowerer.lower(spec: self)
        let authoredAlgorithm: (plan: CompiledAuthoredPlusCalAlgorithmPlan, declarations: AuthoredPlusCalDeclarationOrder)?
        if sourceAlgorithms.count == 1, let plan = authoredPlusCalAlgorithmPlan {
            authoredAlgorithm = (try lowerer.authoredPlusCalPlan(plan), try AuthoredPlusCalDeclarationOrder(source: self))
        } else {
            authoredAlgorithm = nil
        }
        let refinements = try compiledRefinements(lowerer: &lowerer, layout: layout, semantics: semantics)
        let compiledGenerated = try compiledGeneratedRefinements(
            lowerer: &lowerer, layout: layout, semantics: semantics)
        semantics.operators = lowerer.operators
        semantics.operators.resolveDependencies()
        try validateAuthoredProperties(algorithm: authoredAlgorithm?.plan, layout: layout)
        return CompiledModule(
            metadata: .init(source: self, modelValueNames: lowerer.modelValueNames), layout: layout, bindings: lowerer.bindings, semantics: semantics,
            refinements: refinements, generatedRefinements: compiledGenerated,
            authoredAlgorithm: authoredAlgorithm,
            requiredStandardModules: lowerer.requiredStandardModules,
            definitionsBeforeInstances: definitionOrder.beforeInstances,
            definitionsAfterInstances: definitionOrder.afterInstances
        )
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
            .union(reachabilityProperties.map(\.name))
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

    private func validateGeneratedRefinements() throws {
        try validateUnique(generatedModelInstances.map(\.name), code: .duplicateRefinement,
            path: "generatedModelInstances")
        try validateUnique(generatedRefinements.map(\.name), code: .duplicateRefinement,
            path: "generatedRefinements")
        let occupied = Set(variables.map(\.name) + actions.map(\.name) + invariants.map(\.name)
            + reachabilityProperties.map(\.name) + temporalProperties.map(\.name)
            + formalOperatorDefinitions.map(\.name) + recursiveFuncs.map(\.name)
            + moduleInstances.map(\.name) + refinements.map(\.name))
        for instance in generatedModelInstances {
            guard !occupied.contains(instance.name), !instance.targetModelType.isEmpty else {
                throw CompilationDiagnostic(code: .duplicateRefinement, stage: .validation,
                    path: "generatedModelInstances.\(instance.name)",
                    expected: "a distinct bound generated-model type and instance",
                    actual: instance.targetModelType,
                    nextSafeAction: "Use a distinct let-bound generated model instance.")
            }
            try validateUnique(instance.fieldBindings.map(\.fieldName),
                code: .duplicateRefinementMapping, path: "generatedModelInstances.\(instance.name).bindings")
        }
        let instanceNames = Set(generatedModelInstances.map(\.name))
        for refinement in generatedRefinements {
            guard !occupied.contains(refinement.name), !instanceNames.contains(refinement.name) else {
                throw CompilationDiagnostic(code: .duplicateRefinement, stage: .validation,
                    path: "generatedRefinements.\(refinement.name)",
                    expected: "a property identity distinct from other declarations",
                    actual: refinement.name,
                    nextSafeAction: "Use a distinct let binding for the refinement.")
            }
            guard instanceNames.contains(refinement.instanceName) else {
                throw CompilationDiagnostic(code: .unresolvedRefinementInstance, stage: .linking,
                    path: "generatedRefinements.\(refinement.name).instance",
                    expected: "a registered generated-model Instance",
                    actual: refinement.instanceName,
                    nextSafeAction: "Register the bound Instance before its Refinement.")
            }
            try validateUnique(refinement.fieldMappings.map(\.fieldName),
                code: .duplicateRefinementMapping, path: "generatedRefinements.\(refinement.name).mappings")
        }
    }

    private func compiledGeneratedRefinements(
        lowerer: inout CompiledLowerer,
        layout: CompiledLayout,
        semantics: CompiledSemantics
    ) throws -> [CompiledGeneratedModelRefinement] {
        try zip(generatedRefinements, layout.generatedRefinementProperties).map { refinement, property in
            guard let instance = generatedModelInstances.first(where: { $0.name == refinement.instanceName }) else {
                throw CompilationDiagnostic(code: .unresolvedRefinementInstance, stage: .linking,
                    path: "generatedRefinements.\(refinement.name).instance",
                    expected: "a registered generated-model Instance", actual: refinement.instanceName,
                    nextSafeAction: "Register the bound Instance before its Refinement.")
            }
            let parameters = try instance.fieldBindings.map { binding in
                let expression = try lowerer.refinementExpression(binding.source,
                    at: "generatedModelInstances.\(instance.name).bindings.\(binding.fieldName)")
                let requirements = expression.stateRequirements(operators: lowerer.operators)
                guard requirements.variables.isEmpty && !requirements.requiresCompleteState else {
                    throw CompilationDiagnostic(code: .stateDependentRefinementParameter, stage: .binding,
                        path: "generatedModelInstances.\(instance.name).bindings.\(binding.fieldName)",
                        expected: "a state-independent abstract configuration value",
                        actual: "an expression that reads concrete model state",
                        nextSafeAction: "Bind the abstract parameter from concrete configuration only.")
                }
                return CompiledGeneratedModelBinding(fieldName: binding.fieldName,
                    value: .init(expression: expression, operators: lowerer.operators,
                        actionDependencies: semantics.behavior.enabledActionDependencies))
            }
            let state = try refinement.fieldMappings.map { mapping in
                let expression = try lowerer.refinementExpression(mapping.source,
                    at: "generatedRefinements.\(refinement.name).mappings.\(mapping.fieldName)")
                return CompiledGeneratedModelBinding(fieldName: mapping.fieldName,
                    value: .init(expression: expression, operators: lowerer.operators,
                        actionDependencies: semantics.behavior.enabledActionDependencies),
                    projected: mapping.projected)
            }
            return .init(id: property.id, name: refinement.name,
                instanceName: instance.name, targetModelType: instance.targetModelType,
                behavior: refinement.behavior,
                parameters: parameters, state: state)
        }
    }

    private func compiledRefinements(
        lowerer: inout CompiledLowerer,
        layout: CompiledLayout,
        semantics: CompiledSemantics
    ) throws -> [CompiledRefinement] {
        return try zip(refinements, layout.refinementProperties).map { refinement, property in
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
            let modelParametersByBinder = Dictionary(uniqueKeysWithValues: layout.parameters.map {
                ($0.binder, $0.reference)
            })
            var modelParameterDependencies: Set<ParameterReference> = []
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
                var pending = [compiled]
                while let expression = pending.popLast() {
                    if case .boundValue(let binder) = expression.operation,
                       let reference = modelParametersByBinder[binder] {
                        modelParameterDependencies.insert(reference)
                    }
                    pending.append(contentsOf: expression.children)
                }
                let dependencies = compiled.stateRequirements(operators: lowerer.operators)
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
            var specialized = abstractModule.specializing(parameters: parameters)
            let parameterDependencies = parameters.values.reduce(into: Set<String>()) {
                $0.formUnion($1.freeVariableNames)
            }
            specialized.formalParameters += formalParameters.filter {
                parameterDependencies.contains($0.name)
                    && !specialized.formalParameters.contains($0)
            }
            specialized.parameters += self.parameters.filter { modelParameterDependencies.contains($0.reference) }
            // A TLC exploration constraint is configuration, not part of C!Spec.
            specialized.constraints = []
            return .init(
                id: property.id,
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
                    let expression = try lowerer.refinementExpression(
                        source,
                        at: "refinements.\(refinement.name).mappings.\(variable.name)"
                    )
                    return .init(expression: expression, operators: lowerer.operators,
                        actionDependencies: semantics.behavior.enabledActionDependencies)
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
    for action in actions where action.bindings.allSatisfy({ $0.literalMembers != nil }) {
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
        let domains = action.bindings.compactMap(\.literalMembers)
        func addCalls(_ position: Int, arguments: [CompiledValue], indices: [Int]) {
            guard position < action.bindings.count else {
                let suffix = indices.isEmpty ? "" : "__\(indices.map(String.init).joined(separator: "_"))"
                calls.append((
                    call: .init(action: action.id, arguments: arguments),
                    renderedName: "\(emittedName)\(suffix)"
                ))
                return
            }
            for (index, value) in domains[position].enumerated() {
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
    private var preservesActionEvaluation = false

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
        preservesActionEvaluation = !spec.checkingRegisters.isEmpty
        field("spec.name", spec.name)
        let layout = CompiledLayout(source: spec)
        field("declarationLayout", layout.canonicalEncoding)
        list("variables", spec.variables, canonicalVariable)
        let constants = spec.constants.sorted { $0.name < $1.name }.map {
            node("constant", [$0.name, canonicalValue($0.value)])
        }
        list("constants", constants) { $0 }
        if !spec.checkingRegisters.isEmpty {
            let registers = spec.checkingRegisters.map {
                node("checkingRegister", [$0.reference.name, $0.swiftType, canonicalExpression($0.initial)])
            }
            list("checkingRegisters", registers) { $0 }
        }
        if !spec.parameters.isEmpty {
            let parameters = spec.parameters.map {
                node("parameter", [$0.reference.name, $0.swiftType, canonicalExpression($0.domain)])
            }
            list("parameters", parameters) { $0 }
        }
        let formalParameters = spec.formalParameters.map {
            node("formal-parameter", [$0.name, $0.kind.rawValue])
        }
        if !spec.validationScenarios.isEmpty {
            let properties = layout.properties
            let scenarios = spec.validationScenarios.map { scenario in
                node("scenario", [scenario.name,
                    canonicalList(scenario.bindings.map { node("binding", [$0.parameter.name, canonicalExpression($0.value)]) }),
                    canonicalList(scenario.expectations.map { expectation in
                        let property = properties.first { $0.reference == expectation.property }
                        return node("expect", [canonicalOptional(property.map { String($0.id.ordinal) }), expectation.expected.rawValue])
                    }),
                    canonicalList(scenario.deadlockExpectations.map(\.rawValue)),
                    canonicalList(scenario.propertySelections.map { selected in
                        canonicalList(selected.map { reference in
                            canonicalOptional(properties.first { $0.reference == reference }.map { String($0.id.ordinal) })
                        })
                    }),
                    canonicalList(scenario.deadlockSelections.map { String($0) }),
                    canonicalList(scenario.behaviorSelections.map(\.rawValue)),
                    canonicalList(scenario.fairnessProfileSelections.map { reference in
                        String(spec.fairnessProfiles.firstIndex(where: { $0.reference == reference }) ?? -1)
                    }),
                    canonicalList(scenario.checkingModeSelections.map(\.rawValue)),
                    canonicalList(scenario.symmetrySelections.map { reference in
                        String(spec.symmetrySets.firstIndex(where: { $0.reference == reference }) ?? -1)
                    })])
            }
            list("validation", scenarios) { $0 }
        }
        if !spec.fairnessProfiles.isEmpty {
            let profiles = spec.fairnessProfiles.map { profile in
                node("fairnessProfile", [profile.name,
                    canonicalList(profile.excludedLabels.map(\.name))])
            }
            list("fairnessProfiles", profiles) { $0 }
        }
        list("formalParameters", formalParameters) { $0 }
        list("actions", spec.actions, canonicalAction)
        let invariants = spec.invariants.map {
            node("invariant", [$0.name, canonicalExpression($0.body)])
        }
        list("invariants", invariants) { $0 }
        list("initialInvariantSelections", spec.initialInvariantSelections) { selected in
            String(spec.invariants.firstIndex(where: { $0.reference == selected }) ?? -1)
        }
        if !spec.reachabilityProperties.isEmpty {
            let reachability = spec.reachabilityProperties.map {
                node("reachable", [$0.name, canonicalExpression($0.body)])
            }
            list("reachability", reachability) { $0 }
        }
        let temporalProperties = spec.temporalProperties.map {
            var fields = [$0.name, canonicalTemporal($0.expr)]
            if !$0.bindings.isEmpty {
                fields.append(node("bindings", $0.bindings.map {
                    node("binding", [$0.name, canonicalExpression($0.domain), canonicalOptional($0.generatedSwiftType)])
                }))
            }
            return node("temporal", fields)
        }
        list("temporal", temporalProperties) { $0 }
        list("fairness", spec.fairness, canonicalFairness)
        let assumption = spec.assumptions.map(\.expression).reduce(nil as StateExpr?) { partial, expression in
            partial.map { .and($0, expression) } ?? expression
        }
        field("assume", canonicalOptional(assumption.map(canonicalExpression)))
        field("checkDeadlock", node("bool", [String(spec.checkDeadlock)]))
        list("extendsModules", spec.extendsModules) { $0.rawValue }
        let constraint = spec.constraints.map(\.expression).reduce(nil as StateExpr?) { partial, expression in
            partial.map { .and($0, expression) } ?? expression
        }
        field("constraint", canonicalOptional(constraint.map(canonicalExpression)))
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
        let generatedInstances = spec.generatedModelInstances.map { instance in
            node("generated-instance", [instance.name, instance.targetModelType,
                canonicalList(instance.fieldBindings.map {
                    node("bind", [$0.fieldName, canonicalExpression($0.source)])
                })])
        }
        list("generatedInstances", generatedInstances) { $0 }
        let generatedRefinements = spec.generatedRefinements.map { refinement in
            node("generated-refinement", [refinement.name, refinement.instanceName, refinement.behavior.rawValue,
                canonicalList(refinement.fieldMappings.map {
                    node("map", [$0.fieldName, canonicalExpression($0.source), $0.projected ? "projected" : "exact"])
                })])
        }
        list("generatedRefinements", generatedRefinements) { $0 }
        let symmetrySets = spec.symmetrySets.map { set in
            let domain: String
            switch set.domain {
            case .finite(let values): domain = node("finite", [canonicalList(values.map(canonicalValue).sorted())])
            case .parameter(let reference): domain = node("parameter", [reference.name])
            }
            return node("symmetry-set", [set.variableName, domain])
        }
        list("symmetrySets", symmetrySets) { $0 }
    }

    private func canonicalVariable(_ variable: NamedVar) -> String {
        return node("variable", [
            variable.name,
            canonicalInitialization(variable.initialization),
            canonicalOptional(variable.generatedSwiftType),
            canonicalOptional(variable.resolvedValueType.map(nativeTypeKey))
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
                    $0.literalMembers.map { canonicalList($0.map(canonicalValue)) }
                        ?? node("domain", [canonicalExpression($0.domain)]),
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
        node("action", [alphaKey(expression, bindingNames: bindingNames,
            preservingEvaluation: preservesActionEvaluation)])
    }

    private func canonicalTemporal(_ expression: TemporalCondition<StateExpr>) -> String {
        node("temporal", [alphaKey(expression)])
    }

    private func canonicalFairness(_ value: FairnessCondition) -> String {
        switch value {
        case .projected(let condition, let projection):
            return node("projectedFairness", [canonicalFairness(condition), alphaKey(projection)])
        case .weakFairness(let action): return node("weakFairness", [action])
        case .strongFairness(let action): return node("strongFairness", [action])
        case .weakFairnessNext: return node("weakFairnessNext", [])
        case .strongFairnessNext: return node("strongFairnessNext", [])
        case .weakFairnessActionCall(let action): return node("weakFairnessActionCall", [canonicalActionCall(action)])
        case .strongFairnessActionCall(let action): return node("strongFairnessActionCall", [canonicalActionCall(action)])
        case .weakFairnessEachAction(let action): return node("weakFairnessEachAction", [action])
        case .strongFairnessEachAction(let action): return node("strongFairnessEachAction", [action])
        case .weakFairnessActionGroup(let actions): return node("weakFairnessActionGroup", actions)
        case .strongFairnessActionGroup(let actions): return node("strongFairnessActionGroup", actions)
        case .weakFairnessEachActionGroup(let actions): return node("weakFairnessEachActionGroup", actions)
        case .strongFairnessEachActionGroup(let actions): return node("strongFairnessEachActionGroup", actions)
        }
    }

    private func canonicalFormalOperatorDefinition(_ definition: FormalOperatorDefinition) -> String {
        var next = 0
        var environment: [String: String] = [:]
        let parameters = definition.parameters.map { parameter -> String in
            let (canonical, extended) = fresh(parameter.name, environment: environment, next: &next)
            environment = extended
            switch parameter {
            case .value(_, let typeName):
                let signature = typeName.map { [canonicalOptional($0)] } ?? []
                return node("valueParameter", [canonical] + signature)
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

extension CompiledProgram {
    package func renderAuthoredPlusCal(
        declarations: RenderedModule, fairnessProfile: CompiledFairnessProfile? = nil
    ) throws -> String? {
        guard let authoredAlgorithm else { return nil }
        for function in functions {
            var pending = [function.body] + (function.domainGuard.map { [$0] } ?? [])
            while let expression = pending.popLast() {
                if case .enabledAction = expression.operation {
                    throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .rendering,
                        path: "export.plusCal.helpers", expected: "a helper independent of translated action names",
                        actual: "a helper queries action enabledness",
                        nextSafeAction: "Resolve enabledness against the authored PlusCal translation before exporting this helper.")
                }
                pending.append(contentsOf: expression.children)
            }
        }
        var metadata = moduleMetadata
        metadata.modelValueNames = exportedModelValueNames
        let renderer = CompiledTLARenderer(moduleName: metadata.name,
            reservedNames: metadata.modelValueNames.union(metadata.constants.map(\.name)),
            layout: layout, bindings: .init(binders: binderNames), operators: .init(),
            actions: behavior.actions, functions: functions)
        let constants = metadata.constants.sorted { $0.name < $1.name }.map { "ASSUME \($0.name) = \($0.value)" }
        let prelude = try constants + renderer.resolvedFunctionDefinitions()
            + formalModuleReplacements.map(renderer.formalModuleReplacement) + renderer.assumptions(behavior)
        let selectedAlgorithm = fairnessProfile.map { authoredAlgorithm.selecting($0, layout: layout) }
            ?? authoredAlgorithm
        let module = try metadata.authoredPlusCalModule(algorithm: selectedAlgorithm,
            layout: layout, declarations: declarations,
            prelude: prelude, define: [], postTranslation: declarations.instances,
            parameterNames: layout.parameters.map { binderNames[$0.binder]! }, requiredModules: requiredStandardModules)
        return try AlgorithmPlusCalRenderer(module: module, formalRenderer: renderer).render()
    }

    package func renderModule() throws -> RenderedModule {
        try renderModule(named: moduleName, owningRoot: moduleName, structuralPath: [])
    }

    package func renderGeneratedModelValue(_ value: CompiledStateQuery) throws -> String {
        let renderer = CompiledTLARenderer(moduleName: moduleName,
            reservedNames: exportedModelValueNames.union(moduleMetadata.constants.map(\.name)),
            layout: layout, bindings: .init(binders: binderNames), operators: .init(),
            actions: behavior.actions, functions: functions)
        return try renderer.state(value.expression)
    }

    private var exportedModelValueNames: Set<String> {
        refinements.reduce(moduleMetadata.modelValueNames.union(CompiledValue.modelValueNames(
            in: moduleMetadata.constants.map { CompiledValue(formal: $0.value) }))) {
            $0.union($1.abstract.exportedModelValueNames)
        }
    }

    private func renderModule(named name: String, owningRoot: String, structuralPath: [String]) throws -> RenderedModule {
        guard moduleMetadata.formalParameters.isEmpty else {
            throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .rendering,
                path: "export.\(moduleMetadata.name)", expected: "a resolved standalone module",
                actual: "formal parameters need resolved module bindings",
                nextSafeAction: "Resolve the complete module closure before typed export.")
        }
        var metadata = moduleMetadata
        metadata.name = name
        let moduleNames = moduleImports.names(for: metadata.imports,
            namespace: structuralPath.isEmpty ? nil : name, configured: !formalModuleReplacements.isEmpty)
        var replacements = formalModuleReplacements.map { $0.configuration(moduleNames: moduleNames) }
            + moduleImports.replacements(for: metadata.imports, moduleNames: moduleNames)
        let modelValues = exportedModelValueNames
        var reserved = Set(layout.declarations.map(\.name))
        reserved.formUnion(metadata.constants.map(\.name))
        reserved.formUnion(layout.parameters.map { $0.reference.name })
        reserved.formUnion(layout.moduleInstances.map(\.namespace))
        reserved.formUnion(refinements.map(\.name))
        reserved.formUnion(generatedRefinements.map(\.name))
        reserved.formUnion(generatedRefinements.map(\.instanceName))
        reserved.formUnion(["Init", "Next", "Spec", "vars", "StateConstraint", "Terminating"])
        for value in modelValues.subtracting(metadata.modelValueNames).sorted() where reserved.contains(value) {
            guard metadata.constants.contains(where: { $0.name == value && $0.value == .constant(value) }) else {
                throw CompilationDiagnostic(code: .invalidFormalDeclaration, stage: .rendering,
                    path: "export.\(name).modelValues", expected: "a model value distinct from module declarations",
                    actual: "imported model value '\(value)' conflicts with a declared symbol",
                    nextSafeAction: "Rename the model value or the conflicting declaration.")
            }
        }
        metadata.modelValueNames = modelValues
        let renderer = CompiledTLARenderer(moduleName: name,
            reservedNames: metadata.modelValueNames.union(metadata.constants.map(\.name)),
            layout: layout, bindings: .init(binders: binderNames), operators: .init(),
            actions: behavior.actions, functions: functions)
        var imports: [TLAModuleFile] = []
        var ownership: [TLAModuleBundle.OwnershipEntry] = []
        var dependencies: [TLAModuleBundle.ModuleDependency] = []
        var instances: [String] = []
        var renderedRefinements: [String] = []
        for refinement in refinements {
            guard let instance = layout.moduleInstances.first(where: { $0.id == refinement.instance }) else {
                throw CompilationDiagnostic(code: .unresolvedRefinementInstance, stage: .rendering,
                    path: "export.\(name).refinements.\(refinement.name)", expected: "a resolved module-instance identity",
                    actual: "missing instance", nextSafeAction: "Resolve the refinement instance before typed export.")
            }
            guard refinement.operator == .spec else {
                throw CompilationDiagnostic(code: .unsupportedRefinementTarget, stage: .rendering,
                    path: "export.\(name).refinements.\(refinement.name)", expected: "a resolved specification target",
                    actual: "\(refinement.operator)", nextSafeAction: "Resolve the target behavior before typed export.")
            }
            let importedName = "\(name)__Refinement\(instance.id.ordinal)"
            let path = structuralPath + [instance.namespace]
            let abstract = try refinement.abstract.renderModule(named: importedName, owningRoot: owningRoot, structuralPath: path)
            guard refinement.abstract.layout.variables.count == refinement.variableMappings.count else {
                throw CompilationDiagnostic(code: .incompleteRefinementMapping, stage: .rendering,
                    path: "export.\(name).refinements.\(refinement.name)", expected: "one resolved mapping per abstract variable",
                    actual: "mapping count differs", nextSafeAction: "Resolve all variable mappings before typed export.")
            }
            var mappings = try zip(refinement.abstract.layout.variables, refinement.variableMappings).map {
                "\($0.declaration.name) <- \(try renderer.state($1.expression))"
            }
            for parameter in refinement.abstract.layout.parameters {
                guard let concrete = layout.parameters.first(where: { $0.reference == parameter.reference }),
                      let abstractName = refinement.abstract.binderNames[parameter.binder] else {
                    throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .rendering,
                        path: "export.\(name).refinements.\(refinement.name).parameters",
                        expected: "a concrete parameter with the same resolved identity",
                        actual: "unbound abstract parameter \(parameter.reference.name)",
                        nextSafeAction: "Map the abstract configuration to a concrete model parameter.")
                }
                mappings.append("\(abstractName) <- \(try renderer.binderName(concrete.binder))")
            }
            let constants = refinement.abstract.moduleMetadata.constants
            mappings += constants.map { "\($0.name) <- \($0.value)" }
            mappings += refinement.abstract.exportedModelValueNames.subtracting(constants.map(\.name)).sorted()
                .map { "\($0) <- \($0)" }
            instances.append("\(instance.namespace) == INSTANCE \(importedName)" + (mappings.isEmpty ? "" : " WITH " + mappings.joined(separator: ", ")))
            for (offset, replacement) in abstract.moduleReplacements.enumerated() {
                let forwarded = "\(importedName)__Configuration\(offset)"
                instances.append("\(forwarded) == \(instance.namespace)!\(replacement.definitionName)")
                replacements.append(.init(moduleName: replacement.moduleName,
                    operatorName: replacement.operatorName, definitionName: forwarded))
            }
            renderedRefinements.append("\(refinement.name) == \(instance.namespace)!Spec")
            imports.append(.init(name: importedName, tla: abstract.renderedModuleSource))
            imports += abstract.imports
            ownership.append(.init(moduleName: importedName, owningRoot: owningRoot, structuralPath: path))
            ownership += abstract.importedOwnership
            dependencies.append(.init(importingModule: name, importedModule: importedName, structuralPath: path))
            dependencies += abstract.dependencies
        }
        var uniqueReplacements: [TLCModuleReplacement] = []
        for replacement in replacements {
            if let existing = uniqueReplacements.first(where: {
                $0.moduleName == replacement.moduleName && $0.operatorName == replacement.operatorName
            }) {
                guard existing == replacement else {
                    throw CompilationDiagnostic(code: .duplicateFormalModuleReplacement, stage: .rendering,
                        path: "export.\(name).configuration.\(replacement.moduleName).\(replacement.operatorName)",
                        expected: "one replacement for each exported module operator",
                        actual: "conflicting configuration definitions",
                        nextSafeAction: "Resolve each configured module instance into a distinct export scope.")
                }
            } else {
                uniqueReplacements.append(replacement)
            }
        }
        replacements = uniqueReplacements
        var result = try metadata.assembleModule(behavior: behavior, renderer: renderer,
            definitions: [], definitionsBeforeInstances: [], definitionsAfterInstances: [], instances: instances,
            recursiveFunctions: renderer.resolvedFunctionDefinitions(), renderedRefinements: renderedRefinements,
            renderedFormalModuleReplacements: formalModuleReplacements.map(renderer.formalModuleReplacement),
            configuration: metadata.tlcConfiguration(behavior: behavior, replacements: replacements,
                refinementNames: refinements.map(\.name), hasState: !layout.variables.isEmpty),
            requiredStandardModules: requiredStandardModules,
            importedNames: metadata.imports.map { moduleNames[$0] ?? $0 }, instancesAfterBehavior: true)
        result.moduleReplacements = replacements
        result.imports = imports
        result.importedOwnership = ownership
        result.dependencies = dependencies
        try moduleImports.append(to: &result, directImports: metadata.imports, moduleNames: moduleNames,
            rootName: name, owningRoot: owningRoot, structuralPath: structuralPath)
        var uniqueImports: [TLAModuleFile] = []
        for imported in result.imports {
            if let existing = uniqueImports.first(where: { $0.name == imported.name }) {
                guard existing == imported else {
                    throw CompilationDiagnostic(code: .conflictingFormalModuleSource, stage: .rendering,
                        path: "export.\(name).imports.\(imported.name)",
                        expected: "one compiled source per module name", actual: "different imported module bodies",
                        nextSafeAction: "Give distinct formal modules distinct names.")
                }
            } else {
                uniqueImports.append(imported)
            }
        }
        result.imports = uniqueImports
        var owned: Set<String> = []
        result.importedOwnership = result.importedOwnership.filter { owned.insert($0.moduleName).inserted }
        return result
    }
}

private extension CompiledModuleMetadata {
    func renderModule(_ module: CompiledModule, moduleNames: [String: String] = [:]) throws -> RenderedModule {
        var metadata = self
        metadata.name = moduleNames[name] ?? name
        metadata.imports = imports.map { moduleNames[$0] ?? $0 }
        return try metadata.renderModuleContents(module, moduleNames: moduleNames)
    }

    func renderModuleContents(_ module: CompiledModule, moduleNames: [String: String]) throws -> RenderedModule {
        let layout = module.layout
        guard layout.parameters.isEmpty else {
            throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .lowering,
                path: "export.\(name).parameters",
                expected: "configuration-aware export from the resolved typed program",
                actual: "the legacy renderer has no model parameter bindings",
                nextSafeAction: "Use native execution until configuration-aware TLA+ export is implemented.")
        }
        let bindings = module.bindings
        let semantics = module.semantics
        let refinements = module.refinements
        let requiredStandardModules = module.requiredStandardModules
        let renderer = CompiledTLARenderer(moduleName: name,
            reservedNames: modelValueNames.union(constants.map(\.name)).union(formalParameters.map(\.name)),
            layout: layout, bindings: bindings,
            operators: semantics.operators, actions: semantics.behavior.actions, functions: [], moduleNames: moduleNames)
        let definitions = try semantics.operators.formalDefinitionIDs.prefix(formalDefinitionCount).map(renderer.formalDefinition)
        let instances = try semantics.moduleInstances.map(renderer.moduleInstance)
        let renderedRefinements = try refinements.map(renderer.refinement)
        let renderedFormalModuleReplacements = try semantics.formalModuleReplacements.map(renderer.formalModuleReplacement)
        let recursiveFunctions = try semantics.operators.recursiveFunctionIDs.prefix(recursiveFunctionCount).flatMap { id in
            let function = try renderer.recursiveFunction(id)
            return [function.declaration, function.body]
        }
        return try assembleModule(behavior: semantics.behavior, renderer: renderer,
            definitions: definitions,
            definitionsBeforeInstances: module.definitionsBeforeInstances.map { definitions[$0] },
            definitionsAfterInstances: module.definitionsAfterInstances.map { definitions[$0] },
            instances: instances, recursiveFunctions: recursiveFunctions,
            renderedRefinements: renderedRefinements,
            renderedFormalModuleReplacements: renderedFormalModuleReplacements,
            configuration: tlcConfiguration(behavior: semantics.behavior,
                replacements: semantics.formalModuleReplacements.map { $0.configuration(moduleNames: moduleNames) },
                refinementNames: refinements.map(\.name), hasState: !layout.variables.isEmpty),
            requiredStandardModules: requiredStandardModules, importedNames: imports)
    }

    func assembleModule(
        behavior: CompiledBehavior, renderer: CompiledTLARenderer,
        definitions: [String], definitionsBeforeInstances: [String], definitionsAfterInstances: [String],
        instances: [String], recursiveFunctions: [String], renderedRefinements: [String],
        renderedFormalModuleReplacements: [String], configuration: TLCConfiguration,
        requiredStandardModules: Set<StandardModule>, importedNames: [String], instancesAfterBehavior: Bool = false
    ) throws -> RenderedModule {
        let layout = renderer.layout
        func statePredicate(_ expression: CompiledExpression, negated: Bool = false) throws -> String {
            let rendered = try renderer.state(expression)
            let predicate = negated ? "~(\(rendered))" : rendered
            // TLC folds constant operators before registering invariants. Keep their
            // truth values unchanged while making initial-state witnesses observable.
            let requirements = expression.stateRequirements(operators: renderer.operators)
            guard requirements.variables.isEmpty, !requirements.requiresCompleteState,
                  let variable = layout.variables.first else { return predicate }
            let state = try renderer.state(.stateVariable(variable.id))
            return "(\(predicate)) /\\ (\(state) = \(state))"
        }
        let invariants = try behavior.invariants.map { ($0.id, "\($0.name) == \(try statePredicate($0.predicate.expression))") }
            + behavior.reachabilityProperties.map { ($0.id, "\($0.name) == \(try statePredicate($0.predicate.expression, negated: true))") }
        let temporalProperties = try behavior.temporalProperties.map { ($0.id, "\($0.name) == \(try renderer.temporal($0))") }
        let constraint = try behavior.constraint.map { "StateConstraint == \(try renderer.state($0.expression))" }
        let emittedActionNamesByID = Dictionary(
            uniqueKeysWithValues: layout.actions.map { ($0.id, $0.renderedName) }
        )
        let emittedActionCalls = try directActionCalls(
            behavior.actions,
            emittedActionNames: emittedActionNamesByID
        )
        let emittedActionCallNames = Dictionary(
            uniqueKeysWithValues: emittedActionCalls.map { ($0.call, $0.renderedName) }
        )
        let callsByAction = Dictionary(grouping: emittedActionCalls, by: { $0.call.action })
        let directModuleActions: [DirectModuleAction] = try layout.actions.enumerated().map { index, declaration in
            let compiled = behavior.actions[index]
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
                sourceName: declaration.declaration.name,
                renderedName: renderedName,
                renderedParameters: try compiled.bindings.map { try renderer.binderName($0.binder) },
                renderedBody: try renderer.action(compiled.body),
                calls: try callsByAction[compiled.id, default: []].map { emitted in
                    RenderedAction(
                        sourceName: declaration.declaration.name,
                        emittedBaseName: declaration.renderedName,
                        arguments: try emitted.call.arguments.map { try $0.rendered(using: layout) },
                        renderedName: emitted.renderedName
                    )
                },
                symbolicInvocation: compiled.bindings.contains { $0.literalMembers == nil }
                    ? try renderer.actionReference(compiled.id) : nil
            )
        }
        return RenderedModule(
            renderedModuleSource: try renderedDirectModuleSource(
                definitionsBeforeInstances: definitionsBeforeInstances,
                definitionsAfterInstances: definitionsAfterInstances,
                renderedInstances: instances,
                recursiveFunctions: recursiveFunctions,
                renderedInvariants: invariants.map(\.1),
                renderedTemporalProperties: temporalProperties.map(\.1),
                renderedConstraint: constraint,
                renderedActions: directModuleActions,
                emittedActionCallNames: emittedActionCallNames,
                renderedRefinements: renderedRefinements,
                renderedFormalModuleReplacements: renderedFormalModuleReplacements,
                renderer: renderer,
                layout: layout,
                behavior: behavior,
                requiredStandardModules: requiredStandardModules,
                importedNames: importedNames,
                instancesAfterBehavior: instancesAfterBehavior
            ),
            configuration: configuration,
            renderedActions: directModuleActions.filter { !$0.sourceName.isEmpty }.flatMap(\.calls),
            symbolicActions: behavior.actions.filter { $0.bindings.contains { $0.literalMembers == nil } }.map(\.id),
            definitions: definitions, instances: instances, refinements: renderedRefinements,
            properties: Dictionary(uniqueKeysWithValues: invariants + temporalProperties), constraint: constraint,
            temporalObligations: Dictionary(uniqueKeysWithValues: try behavior.temporalProperties.compactMap { property in
                guard let obligations = try renderer.temporalObligations(property.expression) else { return nil }
                return (property.id, obligations)
            }),
            temporalBindingNames: renderer.bindings.binders
        )
    }

    private func renderedDirectModuleSource(
        definitionsBeforeInstances: [String],
        definitionsAfterInstances: [String],
        renderedInstances: [String],
        recursiveFunctions: [String],
        renderedInvariants: [String],
        renderedTemporalProperties: [String],
        renderedConstraint: String?,
        renderedActions: [DirectModuleAction],
        emittedActionCallNames: [CompiledActionCall: String],
        renderedRefinements: [String],
        renderedFormalModuleReplacements: [String],
        renderer: CompiledTLARenderer,
        layout: CompiledLayout,
        behavior: CompiledBehavior,
        requiredStandardModules: Set<StandardModule>,
        importedNames: [String],
        instancesAfterBehavior: Bool
    ) throws -> String {
        let varNames = layout.variables.map(\.declaration.name)
        let varsTuple = varNames.count == 1 ? varNames[0] : "<<\(varNames.joined(separator: ", "))>>"
        let isLibraryModule = varNames.isEmpty && renderedActions.isEmpty
        var lines: [String] = []

        lines.append("---- MODULE \(name) ----")

        let symmetryModule: [StandardModule] = symmetrySets.isEmpty ? [] : [.tlc]
        let modules = ((extendsModules + [.finiteSets, .sequences] + requiredStandardModules.sorted { $0.rawValue < $1.rawValue } + symmetryModule)
            .map(\.rawValue)
            + importedNames)
            .reduce(into: [String]()) { names, module in
                if !names.contains(module) { names.append(module) }
            }
        lines.append("EXTENDS \(modules.joined(separator: ", "))")
        lines.append("")

        let formalVariableSymbols = formalParameters
            .filter { $0.kind == .variable }
            .map(\.name)
        if let declaration = constantDeclaration(including: try layout.parameters.map { try renderer.binderName($0.binder) }) {
            lines.append(declaration)
            for constant in constants.sorted(by: { $0.name < $1.name }) {
                lines.append("ASSUME \(constant.name) = \(constant.value)")
            }
            lines.append("")
        }

        let symmetryParameterNames = try Dictionary(uniqueKeysWithValues: layout.parameters.map {
            ($0.reference, try renderer.binderName($0.binder))
        })
        for symmetry in symmetrySets {
            guard let domain = symmetry.domain.renderedSet(parameterNames: symmetryParameterNames) else {
                throw CompilationDiagnostic(code: .unknownReference, stage: .rendering,
                    path: "symmetrySets.\(symmetry.variableName)", expected: "a rendered model parameter",
                    actual: "a missing parameter", nextSafeAction: "Use a model-owned parameter.")
            }
            lines.append("Symm\(symmetry.variableName) == Permutations(\(domain))")
        }
        if !symmetrySets.isEmpty { lines.append("") }

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
        lines.append(contentsOf: recursiveFunctions)
        if !recursiveFunctions.isEmpty { lines.append("") }
        let instanceDeclarations = (renderedInstances + definitionsAfterInstances + renderedRefinements)
            .flatMap { [$0, ""] }
        if !instancesAfterBehavior { lines += instanceDeclarations }

        lines += try renderer.assumptions(behavior)
        if behavior.assume != nil { lines.append("") }

        if !isLibraryModule, varNames.count > 1 {
            lines.append("vars == \(varsTuple)")
            lines.append("")
        }
        for index in behavior.enabledActionIndices {
            let renderedAction = renderedActions[index]
            guard !renderedAction.sourceName.isEmpty else { continue }
            let parameters = renderedAction.renderedParameters.joined(separator: ", ")
            let emittedName = renderedAction.renderedName
            let header = parameters.isEmpty ? emittedName : "\(emittedName)(\(parameters))"
            lines.append("\(header) == \(renderedAction.renderedBody)")
            for call in renderedAction.calls where call.arguments.isEmpty == false {
                lines.append("\(call.renderedName) == \(formalActionCall(named: emittedName, arguments: call.arguments))")
            }
        }
        lines.append("")

        lines.append(contentsOf: renderedInvariants)
        if !renderedInvariants.isEmpty { lines.append("") }
        if let renderedConstraint {
            lines.append(renderedConstraint)
            lines.append("")
        }
        guard !isLibraryModule else {
            lines.append("====")
            return lines.joined(separator: "\n") + "\n"
        }

        let initializations = Dictionary(
            uniqueKeysWithValues: behavior.initializations.map {
                ($0.variable, $0.initialization)
            }
        )
        var initialPredicates = try layout.variables.map { variable -> String in
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
            case .value(let expression):
                return "\(name) = \(try renderer.state(expression))"
            case .memberOf(let set):
                let literal = set.computation
                func isRecord(_ expression: CompiledExpression) -> Bool {
                    var value = expression
                    while case .convert = value.operation { value = value.children[0] }
                    switch value.operation {
                    case .recordLiteral, .value(.record): return true
                    default: return false
                    }
                }
                let unionMembers: Bool = if case .set(let element) = literal.resultType {
                    element.unionAlternatives != nil
                } else {
                    false
                }
                let alternatives: [String]? = switch literal.operation {
                case .value(.set(let values)) where values.contains(where: {
                    if case .record = $0 { return true }
                    return false
                }):
                    try values.map { try $0.rendered(using: layout).description }
                case .setLiteral where unionMembers || literal.children.contains(where: isRecord):
                    try literal.children.map { try renderer.state($0) }
                default: nil
                }
                if let alternatives {
                    let alternatives = alternatives.sorted().map { "\(name) = \($0)" }
                    return alternatives.isEmpty ? "FALSE" : "(\(alternatives.joined(separator: " \\/ ")))"
                }
                return "\(name) \\in \(try renderer.state(set))"
            }
        }
        if let selected = behavior.initialInvariant {
            guard let invariant = behavior.invariants.first(where: { $0.id == selected }) else {
                throw CompilationDiagnostic(code: .compilationIdentityMismatch, stage: .rendering,
                    path: "initialStates", expected: "the selected compiled invariant",
                    actual: "missing invariant", nextSafeAction: "Compile the model again from its current source.")
            }
            initialPredicates.append(invariant.name)
        }
        if initialPredicates.count == 1 {
            lines.append("Init == \(initialPredicates[0])")
        } else {
            lines.append("Init ==")
            for predicate in initialPredicates { lines.append("  /\\ \(predicate)") }
        }
        lines.append("")

        let invocations = renderedActions
            .filter { $0.sourceName.isEmpty == false }
            .flatMap { $0.symbolicInvocation.map { [$0] } ?? $0.calls.map(\.renderedName) }
        if invocations.count != 1 || invocations[0] != "Next" {
            if invocations.isEmpty {
                lines.append("Next == FALSE")
            } else if invocations.count == 1 {
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
        for condition in behavior.fairness {
            lines.append("  /\\ \(try renderer.fairness(condition, vars: varsTuple, actionCalls: emittedActionCallNames))")
        }
        lines.append("")
        for profile in behavior.fairnessProfiles {
            lines.append("\(profile.operatorName) ==")
            lines.append("  /\\ Init")
            lines.append("  /\\ [][Next]_\(varsTuple)")
            for condition in profile.fairness {
                lines.append("  /\\ \(try renderer.fairness(condition, vars: varsTuple, actionCalls: emittedActionCallNames))")
            }
            lines.append("")
        }
        lines.append(contentsOf: renderedTemporalProperties)
        if !renderedTemporalProperties.isEmpty { lines.append("") }
        if instancesAfterBehavior { lines += instanceDeclarations }
        lines.append("====")
        return lines.joined(separator: "\n") + "\n"
    }

    func tlcConfiguration(behavior: CompiledBehavior, replacements: [TLCModuleReplacement],
        refinementNames: [String], hasState: Bool) -> TLCConfiguration {
        var lines: [String] = []
        for constant in constants.sorted(by: { $0.name < $1.name }) {
            lines.append("CONSTANT \(constant.name) = \(constant.value)")
        }
        for replacement in replacements {
            lines.append(
                "CONSTANT \(replacement.operatorName) <- [\(replacement.moduleName)]\(replacement.definitionName)"
            )
        }
        for name in modelValueNames.subtracting(constants.map(\.name)).sorted() {
            lines.append("CONSTANT \(name) = \(name)")
        }
        if behavior.constraint != nil { lines.append("CONSTRAINT StateConstraint") }
        let assumptionsOnly = !hasState && behavior.actions.isEmpty
            && behavior.invariants.isEmpty && behavior.reachabilityProperties.isEmpty
            && behavior.temporalProperties.isEmpty && refinementNames.isEmpty && behavior.assume != nil
            && behavior.constraint == nil && behavior.fairness.isEmpty
        return TLCConfiguration(
            assumptionsOnly: assumptionsOnly,
            declarations: lines,
            checkDeadlock: assumptionsOnly ? false : behavior.checkDeadlock,
            invariants: behavior.invariants.map(\.name),
            reachabilityProperties: behavior.reachabilityProperties.map(\.name),
            properties: behavior.temporalProperties.map(\.name),
            refinements: refinementNames,
            symmetry: symmetrySets.map { "Symm\($0.variableName)" }
        )
    }

}
