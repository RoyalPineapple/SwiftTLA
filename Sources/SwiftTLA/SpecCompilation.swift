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

/// The point at which a formal specification becomes available to consumers.
///
/// A compiled specification owns the sole semantic `TLASpec` payload. Later
/// pipeline stages can attach validated module and generated-machine plans
/// without reparsing or rebuilding that payload.
public struct CompiledSpecification: Sendable {
    public let spec: TLASpec
    public let formalModuleClosure: FormalModuleClosure
    public let identity: CompilationIdentity

    init(spec: TLASpec, formalModuleClosure: FormalModuleClosure, identity: CompilationIdentity) {
        self.spec = spec
        self.formalModuleClosure = formalModuleClosure
        self.identity = identity
    }

    /// Renders a complete TLA+/CFG bundle from the already-linked closure.
    ///
    /// This is the rendering boundary for compiled models. It neither reparses
    /// source nor discovers module dependencies from rendered text.
    public func renderedTLAModuleBundle() throws -> TLAModuleBundle {
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

        let files = entries.map { entry in
            TLAModuleFile(
                name: entry.module.name,
                tla: entry.module.tlaModule,
                cfg: entry.module.name == spec.name ? entry.module.tlaCfg : nil
            )
        }
        let bundle = TLAModuleBundle(
            root: files[files.count - 1],
            imports: Array(files.dropLast()),
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

    /// Compatibility export for callers that only need an in-memory bundle.
    /// New compiler-boundary callers should use `renderedTLAModuleBundle()`.
    public var tlaBundle: TLAModuleBundle {
        get throws { try renderedTLAModuleBundle() }
    }

    /// The root TLA+ source of this validated compilation.
    public var tlaModule: String {
        get throws { try renderedTLAModuleBundle().tla }
    }

    /// The root TLC configuration of this validated compilation.
    public var tlaCfg: String {
        get throws { try renderedTLAModuleBundle().cfg }
    }

    /// The authored PlusCal presentation of this validated compilation.
    public func renderedAuthoredPlusCalModules() throws -> [String] {
        _ = try renderedTLAModuleBundle()
        return try spec.renderAuthoredPlusCalModules()
    }
}

/// A blocking, inspection-ready compiler failure.
public struct CompilationDiagnostic: Error, Sendable, Hashable, CustomStringConvertible {
    public enum Stage: String, Sendable, Hashable {
        case validation
        case lowering
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
        case unresolvedImport
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
    /// Lowers parser output exactly once into the canonical formal payload.
    ///
    /// Callers may contribute invariants derived from Swift-only type facts;
    /// those facts never carry a second copy of formal expressions.
    func compile(
        specificationName: String,
        additionalInvariants: [NamedInvariant] = []
    ) throws -> CompiledSpecification {
        let resolvedImports = try imports.map { name -> TLASpec in
            guard let module = FormalModuleRegistry.lookup(name) else {
                throw CompilationDiagnostic(
                    code: .unresolvedImport,
                    stage: .lowering,
                    path: "imports.\(name)",
                    expected: "a registered formal module named '\(name)'",
                    actual: "no registered module",
                    nextSafeAction: "Register or import the named formal module, then compile again."
                )
            }
            return module
        }
        let variableNames = variables.map(\.name)
        let spec = TLASpec(
            name: specificationName,
            variables: variables.map(\.formal),
            constants: constants,
            formalParameters: formalParameters,
            actions: actions.map {
                NamedAction(name: $0.name, body: completeAction($0.body, allVars: variableNames), bindings: $0.bindings)
            },
            invariants: invariants.map { NamedInvariant(name: $0.name, body: $0.body) } + additionalInvariants,
            temporalProperties: temporal.map { NamedTemporal(name: $0.name, expr: $0.expr) },
            fairness: fairness,
            definitions: definitions,
            constraint: constraint,
            formalOperatorDefinitions: formalOperatorDefinitions,
            imports: resolvedImports,
            importConfigurations: importConfigurations,
            moduleInstances: moduleInstances,
            symmetrySets: symmetrySets,
            symmetricCollections: symmetricCollections.map(\.declaration),
            algorithmFidelityTokens: algorithmFidelityTokens,
            authoredPlusCalDeclarations: authoredPlusCalDeclarations
        )
        return try spec.compile()
    }
}

public extension TLASpec {
    /// Validates and identifies this specification before it reaches a formal
    /// consumer. Structural module linking is added to this gate by the linker.
    func compile() throws -> CompiledSpecification {
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
        return CompiledSpecification(
            spec: self,
            formalModuleClosure: closure,
            identity: .init(value: compilationFingerprint)
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

/// Canonicalizes the formal data model with unambiguous field boundaries.
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
        list("variables", spec.variables, canonicalVariable)
        let constants = spec.constants.keys.sorted().map { key in
            node("constant", [key, canonicalValue(spec.constants[key]!)])
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
        list("definitions", spec.definitions) { $0 }
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
        list("runtimeFuncBodies", spec.runtimeFuncBodies) { $0 }
        let symmetrySets = spec.symmetrySets.map { set in
            node("symmetry-set", [set.variableName, canonicalList(set.values.map(canonicalValue).sorted())])
        }
        list("symmetrySets", symmetrySets) { $0 }
        let symmetryGroups = spec.symmetryGroups.map {
            node("symmetry-group", [canonicalList($0.names)])
        }
        list("symmetryGroups", symmetryGroups) { $0 }
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
            return node("record", [canonicalList(values.keys.sorted().map {
                node("record-entry", [$0, canonicalValue(values[$0]!)])
            })])
        case .function(let values):
            return node("function", [canonicalList(values.map {
                node("function-entry", [canonicalValue($0.key), canonicalValue($0.value)])
            }.sorted())])
        }
    }

    private func canonicalExpression(_ expression: StateExpr) -> String {
        switch expression {
        case .value(let value): return node("value", [canonicalValue(value)])
        case .variable(let name): return node("variable", [name])
        case .add(let a, let b): return binary("add", a, b)
        case .subtract(let a, let b): return binary("subtract", a, b)
        case .multiply(let a, let b): return binary("multiply", a, b)
        case .divide(let a, let b): return binary("divide", a, b)
        case .modulo(let a, let b): return binary("modulo", a, b)
        case .integerDivide(let a, let b): return binary("integerDivide", a, b)
        case .negate(let value): return unary("negate", value)
        case .equal(let a, let b): return binary("equal", a, b)
        case .notEqual(let a, let b): return binary("notEqual", a, b)
        case .lessThan(let a, let b): return binary("lessThan", a, b)
        case .lessOrEqual(let a, let b): return binary("lessOrEqual", a, b)
        case .greaterThan(let a, let b): return binary("greaterThan", a, b)
        case .greaterOrEqual(let a, let b): return binary("greaterOrEqual", a, b)
        case .and(let a, let b): return binary("and", a, b)
        case .or(let a, let b): return binary("or", a, b)
        case .not(let value): return unary("not", value)
        case .ifThenElse(let c, let t, let f): return node("if", [canonicalExpression(c), canonicalExpression(t), canonicalExpression(f)])
        case .setLiteral(let values): return node("setLiteral", values.map(canonicalExpression))
        case .in(let a, let b): return binary("in", a, b)
        case .subset(let a, let b): return binary("subset", a, b)
        case .union(let a, let b): return binary("union", a, b)
        case .intersection(let a, let b): return binary("intersection", a, b)
        case .setDifference(let a, let b): return binary("setDifference", a, b)
        case .cardinality(let value): return unary("cardinality", value)
        case .setFilter(let set, let binding, let predicate): return node("setFilter", [canonicalExpression(set), binding, canonicalExpression(predicate)])
        case .setMap(let value, let binding, let set): return node("setMap", [canonicalExpression(value), binding, canonicalExpression(set)])
        case .powerSet(let value): return unary("powerSet", value)
        case .unionAll(let value): return unary("unionAll", value)
        case .integerRange(let a, let b): return binary("integerRange", a, b)
        case .tupleLiteral(let values): return node("tupleLiteral", values.map(canonicalExpression))
        case .tupleAccess(let tuple, let index): return node("tupleAccess", [canonicalExpression(tuple), String(index)])
        case .tupleDynamicAccess(let tuple, let index): return binary("tupleDynamicAccess", tuple, index)
        case .tupleLength(let value): return unary("tupleLength", value)
        case .tupleAppend(let a, let b): return binary("tupleAppend", a, b)
        case .tupleHead(let value): return unary("tupleHead", value)
        case .tupleTail(let value): return unary("tupleTail", value)
        case .tupleConcatenate(let a, let b): return binary("tupleConcatenate", a, b)
        case .recordLiteral(let fields): return node("recordLiteral", fields.keys.sorted().map { node($0, [canonicalExpression(fields[$0]!)]) })
        case .recordAccess(let record, let field): return node("recordAccess", [canonicalExpression(record), field])
        case .domain(let value): return unary("domain", value)
        case .functionLiteral(let domain, let binding, let body): return node("functionLiteral", [canonicalExpression(domain), binding, canonicalExpression(body)])
        case .functionApply(let function, let argument): return binary("functionApply", function, argument)
        case .except(let function, let key, let value): return node("except", [canonicalExpression(function), canonicalExpression(key), canonicalExpression(value)])
        case .caseExpr(let branches, let otherwise): return node("case", [canonicalList(branches.map(canonicalExpression)), otherwise.map(canonicalExpression) ?? "none"])
        case .forAll(let set, let binding, let predicate): return quantified("forAll", set, binding, predicate)
        case .exists(let set, let binding, let predicate): return quantified("exists", set, binding, predicate)
        case .choose(let set, let binding, let predicate): return quantified("choose", set, binding, predicate)
        case .enabledAction(let name): return node("enabledAction", [name])
        case .sequenceFromSet(let value): return unary("sequenceFromSet", value)
        case .setSum(let function, let values): return binary("setSum", function, values)
        case .functionSet(let domain, let range): return binary("functionSet", domain, range)
        case .foldFunction(let lambda, let initial, let sequence): return node("foldFunction", [canonicalLambda(lambda), canonicalExpression(initial), canonicalExpression(sequence)])
        case .operatorApplication(let operation, let arguments): return node("operatorApplication", [canonicalOperator(operation), canonicalList(arguments.map(canonicalCallArgument))])
        case .recursiveCall(let name, let arguments): return node("recursiveCall", [name, canonicalList(arguments.map(canonicalExpression))])
        case .letValue(let name, let value, let body): return node("letValue", [name, canonicalExpression(value), canonicalExpression(body)])
        case .letIn(let definitions, let body): return node("letIn", [canonicalList(definitions.map(canonicalLocalOperator)), canonicalExpression(body)])
        }
    }

    private func canonicalActionExpression(_ expression: ActionExpr) -> String {
        switch expression {
        case .assign(let name, let value): return node("assign", [name, canonicalExpression(value)])
        case .unchanged(let name): return node("unchanged", [name])
        case .guard_(let value): return node("guard", [canonicalExpression(value)])
        case .chooseAction(let name, let set): return node("chooseAction", [name, canonicalExpression(set)])
        case .existsAction(let name, let set, let body): return node("existsAction", [name, canonicalExpression(set), canonicalActionExpression(body)])
        case .ifElse(let condition, let then, let otherwise): return node("actionIf", [canonicalExpression(condition), canonicalActionExpression(then), canonicalActionExpression(otherwise)])
        case .define(let name, let value, let body): return node("actionDefine", [name, canonicalExpression(value), canonicalActionExpression(body)])
        case .and(let a, let b): return node("actionAnd", [canonicalActionExpression(a), canonicalActionExpression(b)])
        case .or(let a, let b): return node("actionOr", [canonicalActionExpression(a), canonicalActionExpression(b)])
        }
    }

    private func canonicalTemporal(_ expression: TemporalExpr) -> String {
        switch expression {
        case .always(let value): return unary("always", value)
        case .eventually(let value): return unary("eventually", value)
        case .alwaysEventually(let value): return unary("alwaysEventually", value)
        case .eventuallyAlways(let value): return unary("eventuallyAlways", value)
        case .leadsTo(let a, let b): return binary("leadsTo", a, b)
        }
    }

    private func canonicalFairness(_ value: FairnessCondition) -> String {
        switch value {
        case .weakFairness(let action): return node("weakFairness", [action])
        case .strongFairness(let action): return node("strongFairness", [action])
        case .weakFairnessInvocation(let invocation): return node("weakFairnessInvocation", [canonicalInvocation(invocation)])
        case .strongFairnessInvocation(let invocation): return node("strongFairnessInvocation", [canonicalInvocation(invocation)])
        }
    }

    private func canonicalFormalParameter(_ value: FormalParameter) -> String {
        switch value {
        case .value(let name): return node("valueParameter", [name])
        case .operator(let name, let arity): return node("operatorParameter", [name, String(arity)])
        }
    }
    private func canonicalOperator(_ value: FormalOperator) -> String {
        switch value {
        case .lambda(let lambda): return node("lambda", [canonicalLambda(lambda)])
        case .reference(let name, let arity): return node("reference", [name, String(arity)])
        }
    }
    private func canonicalCallArgument(_ value: FormalCallArgument) -> String {
        switch value {
        case .value(let expression): return node("valueArgument", [canonicalExpression(expression)])
        case .operator(let operation): return node("operatorArgument", [canonicalOperator(operation)])
        }
    }
    private func canonicalLambda(_ value: FormalLambda) -> String { node("lambda", [canonicalList(value.parameters), canonicalExpression(value.body)]) }
    private func canonicalLocalOperator(_ value: LocalOperator) -> String { node("localOperator", [value.name, canonicalList(value.parameters), canonicalOptional(value.domain.map(canonicalExpression)), canonicalExpression(value.body)]) }
    private func canonicalInvocation(_ value: TLAActionInvocation) -> String { node("invocation", [value.name, canonicalList(value.arguments.map(canonicalValue))]) }
    private func unary(_ tag: String, _ value: StateExpr) -> String { node(tag, [canonicalExpression(value)]) }
    private func binary(_ tag: String, _ lhs: StateExpr, _ rhs: StateExpr) -> String { node(tag, [canonicalExpression(lhs), canonicalExpression(rhs)]) }
    private func quantified(_ tag: String, _ set: StateExpr, _ binding: String, _ predicate: StateExpr) -> String { node(tag, [canonicalExpression(set), binding, canonicalExpression(predicate)]) }
    private func canonicalList(_ values: [String]) -> String { node("list", values) }
    private func canonicalOptional(_ value: String?) -> String {
        value.map { node("some", [$0]) } ?? node("none", [])
    }
    private func node(_ tag: String, _ fields: [String]) -> String {
        ([tag, String(fields.count)] + fields).map { "\($0.utf8.count):\($0)" }.joined()
    }
}
