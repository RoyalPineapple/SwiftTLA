/// A source-location-independent problem encountered while printing Algorithm
/// IR as PlusCal. Rendering never lowers the program or synthesizes control
/// state, so a component without a direct PlusCal spelling is reported rather
/// than approximated.
public struct AlgorithmPlusCalRenderDiagnostic: Error, Sendable, Hashable, CustomStringConvertible {
    /// The rendering capability that could not be satisfied.
    public let failedConcept: String
    /// Canonical Algorithm IR path of the unsupported node.
    public let path: String
    /// The direct PlusCal spelling or renderer capability that was required.
    public let expected: String
    /// The actual Algorithm IR node encountered by the renderer.
    public let actual: String
    /// Rendering is pure: a diagnostic never creates semantics or changes state.
    public let stateChange: StateChange
    public let nextSafeAction: String

    public enum StateChange: String, Sendable, Hashable {
        case none
    }

    public init(
        failedConcept: String,
        path: String,
        expected: String,
        actual: String,
        nextSafeAction: String,
        stateChange: StateChange = .none
    ) {
        self.failedConcept = failedConcept
        self.path = path
        self.expected = expected
        self.actual = actual
        self.nextSafeAction = nextSafeAction
        self.stateChange = stateChange
    }

    public var description: String {
        "PlusCal rendering failed: \(failedConcept). Path: \(path). Expected: \(expected). "
            + "Actual: \(actual). State change: \(stateChange.rawValue). Next safe action: \(nextSafeAction)"
    }
}

/// Prints the canonical Algorithm IR as a self-contained TLA+ module with a
/// PlusCal algorithm comment. This is deliberately a syntax renderer: it does
/// not invoke `AlgorithmLowerer`, construct a `TLASpec`, or introduce any
/// generated program-counter semantics.
extension Algorithm {
    func renderPlusCalModule() throws -> String {
        try AlgorithmPlusCalRenderer(model: model).render()
    }
}

/// Ordered module-link layout for the final PlusCal renderer.
///
/// Literal source definitions remain a deliberate formal-source boundary, but
/// imports and their order are structural: constants and support definitions
/// precede instances, which precede the Algorithm; properties follow the
/// translator-owned section. This carries no machine semantics: `AlgorithmModel`
/// remains the authored-machine IR.
internal struct AuthoredPlusCalModule: Sendable {
    let name: String
    let extendsModules: [String]
    let constants: [String]
    let definitionsBeforeInstances: [String]
    let instances: [FormalModuleInstance]
    let definitionsAfterInstances: [String]
    let algorithm: AlgorithmModel
    let defineDeclarations: [String]
    let postTranslationDeclarations: [String]

    var supportDeclarations: [String] {
        constants
            + definitionsBeforeInstances
            + instances.map { instance in
                let arguments = instance.arguments.map { "\($0.parameter) <- \($0.value)" }.joined(separator: ", ")
                let withClause = arguments.isEmpty ? "" : " WITH \(arguments)"
                return "\(instance.name) == INSTANCE \(instance.module.name)\(withClause)"
            }
            + definitionsAfterInstances
    }
}

internal struct AlgorithmPlusCalRenderer {
    let model: AlgorithmModel

    init(model: AlgorithmModel) {
        self.model = model
    }

    /// Source-level properties are kept outside the PlusCal comment, where
    /// the official translator leaves TLA+ operators intact.  They come from
    /// the retained Algorithm model rather than the lowered specification.
    func sourcePropertyDefinitions() throws -> [(name: String, definition: String)] {
        try properties(in: model.components, path: "components")
    }

    /// PlusCal's translator defines this temporal operator for a single
    /// process family.  Emitting the equivalent authored spelling after the
    /// comment would redeclare the translator-owned name.
    func translatorOwnedPropertyNames() -> Set<String> {
        Set(temporals(in: model.components).compactMap { temporal in
            isTranslatorTermination(temporal) ? temporal.name : nil
        })
    }

    func render() throws -> String {
        let sections = try AuthoredPlusCalDeclarationSections(
            model.formalOperatorDefinitions.map { definition in
                AuthoredPlusCalDeclaration(
                    name: definition.name,
                    text: FormalOperatorDecl(definition).tlaText,
                    phase: definition.plusCalPhase,
                    dependencies: definition.plusCalDependencies
                )
            }
        )
        return try render(
            AuthoredPlusCalModule(
                name: moduleName(model.name),
                extendsModules: ["Naturals", "Integers", "Sequences", "FiniteSets"],
                constants: [],
                definitionsBeforeInstances: sections.prelude,
                instances: [],
                definitionsAfterInstances: [],
                algorithm: model,
                defineDeclarations: sections.define,
                postTranslationDeclarations: try sourcePropertyDefinitions().map(\.definition)
            )
        )
    }

    func render(_ module: AuthoredPlusCalModule) throws -> String {
        // TLA+ spells negative values through the unary `-.` operator from
        // `Integers`.  PlusCal's translator preserves that operator in the
        // generated module, so every rendered source must make it available.
        var lines = ["---- MODULE \(module.name) ----", "EXTENDS \(module.extendsModules.joined(separator: ", "))", ""]
        if !module.supportDeclarations.isEmpty {
            lines += module.supportDeclarations
            lines.append("")
        }
        lines.append("(*--algorithm \(model.name) {")

        let shared = model.components.compactMap { component -> AlgorithmStateModel? in
            guard case .shared(let declaration) = component else { return nil }
            return declaration
        }
        if !shared.isEmpty {
            lines.append("variables")
            lines += try declarations(shared, indent: "  ", terminator: ";", path: "shared")
        }
        if !module.defineDeclarations.isEmpty {
            lines.append("define {")
            lines += module.defineDeclarations.map { "  \($0)" }
            lines.append("}")
        }

        let processNames = renderedProcessNames()
        var processIndex = 0
        for (index, component) in model.components.enumerated() {
            switch component {
            case .shared:
                continue
            case .procedure(let procedure):
                lines += try render(procedure: procedure, path: "components[\(index)]")
            case .process(let process):
                lines += try render(
                    process: process,
                    processName: processNames[processIndex],
                    path: "components[\(index)]"
                )
                processIndex += 1
            case .step:
                // Sequential steps share the algorithm's C-syntax brace body.
                continue
            case .invariant, .temporal, .formalOperator:
                // Properties are emitted once after the PlusCal comment.
                continue
            case .stateConstraint:
                // The operator is emitted after the PlusCal comment, where
                // the official translator preserves it for TLC's CONSTRAINT.
                continue
            case .fairness:
                // Only AlgorithmFairness belongs to a PlusCal process header.
                // A generic TLA+ fairness condition has no direct source-level
                // PlusCal spelling in this IR, so preserve the no-semantics
                // boundary with a complete diagnostic.
                throw unsupported(
                    path: "components[\(index)]",
                    expected: "a process fairness modifier (`fair process` or `fair+ process`)",
                    actual: "top-level fairness declaration"
                )
            case .local:
                throw unsupported(path: "components[\(index)]", expected: "a process or procedure local declaration", actual: "top-level local declaration")
            case .propertyBoundary:
                throw unsupported(path: "components[\(index)]", expected: "a directly renderable PlusCal declaration", actual: "property boundary")
            }
        }

        let sequential = model.sequentialSteps
        if !sequential.isEmpty {
            lines.append("{")
            for (index, step) in sequential.enumerated() {
                lines += try render(step: step, indent: "  ", path: "sequentialSteps[\(index)]")
            }
            lines.append("}")
        }
        lines.append("} *)")
        let constraints = try model.components.enumerated().compactMap { index, component -> String? in
            guard case .stateConstraint(let constraint) = component else { return nil }
            return try expression(constraint, path: "components[\(index)].stateConstraint")
        }
        if !constraints.isEmpty {
            lines.append("StateConstraint == \(constraints.map { "(\($0))" }.joined(separator: " /\\ "))")
        }
        lines += module.postTranslationDeclarations
        lines.append("====")
        return lines.joined(separator: "\n") + "\n"
    }

    private func render(procedure: AlgorithmProcedureModel, path: String) throws -> [String] {
        var lines = ["", "procedure \(procedure.name)(\(procedure.parameters.map(\.root).joined(separator: ", ")))"]
        if !procedure.locals.isEmpty {
            lines.append("variables")
            lines += try declarations(procedure.locals, indent: "  ", terminator: ";", path: "\(path).locals")
        }
        lines.append("{")
        for (index, step) in procedure.steps.enumerated() {
            lines += try render(step: step, indent: "  ", path: "\(path).steps[\(index)]")
        }
        lines.append("}")
        return lines
    }

    private func render(
        process: AlgorithmProcessModel,
        processName: String,
        path: String
    ) throws -> [String] {
        let fairness: String
        switch process.fairness {
        case .none: fairness = ""
        case .weak: fairness = "fair "
        case .strong: fairness = "fair+ "
        }
        // The header identifier names the process set. `self` is the
        // language-defined identifier for its current member inside the body.
        // Keep the IR-only name out of the source and avoid collisions with
        // declarations authored in this algorithm.
        var lines = ["", "\(fairness)process (\(processName) \\in \(set(process.domain)))"]
        let locals = process.components.compactMap { component -> AlgorithmStateModel? in
            guard case .local(let declaration) = component else { return nil }
            return declaration
        }
        if !locals.isEmpty {
            lines.append("variables")
            lines += try declarations(locals, indent: "  ", terminator: ";", path: "\(path).locals")
        }
        lines.append("{")
        for (index, component) in process.components.enumerated() {
            switch component {
            case .local:
                continue
            case .step(let step):
                lines += try render(step: step, indent: "  ", path: "\(path).components[\(index)]")
            case .invariant, .temporal, .formalOperator:
                // Properties are emitted once after the PlusCal comment.
                continue
            case .fairness:
                throw unsupported(path: "\(path).components[\(index)]", expected: "the process fairness modifier (`fair` or `fair+`)", actual: "nested process fairness declaration")
            case .stateConstraint:
                throw unsupported(path: "\(path).components[\(index)]", expected: "a process statement or local declaration", actual: "process state constraint")
            case .propertyBoundary:
                throw unsupported(path: "\(path).components[\(index)]", expected: "a process statement or local declaration", actual: "property boundary")
            case .shared, .process, .procedure:
                throw unsupported(path: "\(path).components[\(index)]", expected: "a process statement or local declaration", actual: "nested algorithm component")
            }
        }
        lines.append("}")
        return lines
    }

    private func declarations(_ declarations: [AlgorithmStateModel], indent: String, terminator: String, path: String) throws -> [String] {
        try declarations.enumerated().map { index, declaration in
            let suffix = index == declarations.index(before: declarations.endIndex) ? terminator : ","
            let initializer = try declaration.initialSet.map { "\\in \(try expression($0, path: "\(path)[\(index)].initialSet"))" }
                ?? "= \(try expression(declaration.initial, path: "\(path)[\(index)].initial"))"
            return "\(indent)\(declaration.root) \(initializer)\(suffix)"
        }
    }

    private func render(step: AlgorithmStepModel, indent: String, path: String) throws -> [String] {
        if let condition = step.loopCondition {
            var lines = ["\(indent)\(step.label.name): while (\(try expression(condition, path: "\(path).loopCondition"))) {"]
            lines += try render(statements: step.statements, indent: indent + "  ", path: "\(path).statements")
            lines.append("\(indent)};")
            return lines
        }
        var lines = ["\(indent)\(step.label.name):"]
        lines += try render(statements: step.statements, indent: indent + "  ", path: "\(path).statements")
        return lines
    }

    private func render(statements: [AlgorithmStatementModel], indent: String, path: String) throws -> [String] {
        var lines: [String] = []
        var index = statements.startIndex

        while index < statements.endIndex {
            // A `Do` body captures every assignment right-hand side from the
            // pre-state.  PlusCal spells that relation with `||`; rendering
            // ordinary sequential `:=` statements changes an authored swap
            // into two sequential writes.
            if case .set = statements[index] {
                var assignments: [(target: AlgorithmLValueModel, value: StateExpr)] = []
                repeat {
                    guard case .set(let target, let value) = statements[index] else { break }
                    assignments.append((target, value))
                    index = statements.index(after: index)
                } while index < statements.endIndex && {
                    if case .set = statements[index] { return true }
                    return false
                }()

                let rendered = try assignments.enumerated().map { assignmentIndex, assignment in
                    "\(try lvalue(assignment.target, path: "\(path)[\(assignmentIndex)].target")) := \(try expression(assignment.value, path: "\(path)[\(assignmentIndex)].value"))"
                }
                    .joined(separator: " || ")
                lines.append("\(indent)\(rendered);")
                continue
            }

            lines += try render(statement: statements[index], indent: indent, path: "\(path)[\(index)]")
            index = statements.index(after: index)
        }
        return lines
    }

    private func render(statement: AlgorithmStatementModel, indent: String, path: String) throws -> [String] {
        switch statement {
        case .await(let condition): return ["\(indent)await \(try expression(condition, path: "\(path).condition"));"]
        case .assert(let condition): return ["\(indent)assert \(try expression(condition, path: "\(path).condition"));"]
        case .set(let target, let value): return ["\(indent)\(try lvalue(target, path: "\(path).target")) := \(try expression(value, path: "\(path).value"));"]
        case .letBinding(let variable, let value, let body):
            var lines = ["\(indent)with (\(variable) = \(try expression(value, path: "\(path).value"))) {"]
            lines += try render(statements: body, indent: indent + "  ", path: "\(path).body")
            lines.append("\(indent)};")
            return lines
        case .with(let variable, let source, let body):
            var lines = ["\(indent)with (\(variable) \\in \(try expression(source, path: "\(path).source"))) {"]
            lines += try render(statements: body, indent: indent + "  ", path: "\(path).body")
            lines.append("\(indent)};")
            return lines
        case .ifElse(let condition, let then, let otherwise):
            var lines = ["\(indent)if (\(try expression(condition, path: "\(path).condition"))) {"]
            lines += try render(statements: then, indent: indent + "  ", path: "\(path).then")
            if otherwise.isEmpty {
                lines.append("\(indent)};")
            } else {
                lines.append("\(indent)} else {")
                lines += try render(statements: otherwise, indent: indent + "  ", path: "\(path).else")
                lines.append("\(indent)};")
            }
            return lines
        case .either(let first, let second):
            var lines = ["\(indent)either {"]
            lines += try render(statements: first, indent: indent + "  ", path: "\(path).first")
            lines.append("\(indent)} or {")
            lines += try render(statements: second, indent: indent + "  ", path: "\(path).second")
            lines.append("\(indent)};")
            return lines
        case .choose(let variable, let domain, let body):
            // `Choose` is SwiftTLA's bounded spelling of PlusCal's with-member choice.
            var lines = ["\(indent)with (\(variable) \\in \(set(domain))) {"]
            lines += try render(statements: body, indent: indent + "  ", path: "\(path).body")
            lines.append("\(indent)};")
            return lines
        case .goto(let label): return ["\(indent)goto \(label.name);"]
        case .call(let target, let arguments):
            return ["\(indent)call \(target)(\(try arguments.enumerated().map { try expression($0.element, path: "\(path).arguments[\($0.offset)]") }.joined(separator: ", ")));"]
        case .return: return ["\(indent)return;"]
        case .stop: return ["\(indent)goto Done;"]
        case .skip: return ["\(indent)skip;"]
        }
    }

    private func lvalue(_ value: AlgorithmLValueModel, path: String) throws -> String {
        switch value {
        case .root(let name): return name
        case .function(let root, let key): return "\(root)[\(try expression(key, path: "\(path).key"))]"
        }
    }

    func expression(_ value: StateExpr, path: String) throws -> String {
        let sourceValue = localFamilyRoots.reduce(value) { expression, root in
            renameVar("__pcal_local_family:\(root)", to: root, in: expression)
        }
        let rendered = StateExpr.renamingRecursiveCalls(
            in: renameVar("__pcal_self", to: "self", in: sourceValue),
            using: { $0 },
            lowerAnonymousLambdaApplications: true
        ).description
        guard !rendered.contains("LAMBDA") else {
            throw unsupported(
                path: path,
                expected: "a direct anonymous formal-lambda application with value arguments, or a named operator reference",
                actual: "a residual anonymous formal lambda that PlusCal cannot render without changing higher-order semantics"
            )
        }
        return rendered
    }

    private var localFamilyRoots: [String] {
        model.processes.flatMap { process in
            process.components.compactMap { component in
                guard case .local(let declaration) = component else { return nil }
                return declaration.root
            }
        }
    }

    private func properties(
        in components: [AlgorithmComponentModel],
        path: String
    ) throws -> [(name: String, definition: String)] {
        try components.enumerated().flatMap { index, component in
            let componentPath = "\(path)[\(index)]"
            switch component {
            case .invariant(let invariant):
                return [(
                    invariant.name,
                    "\(invariant.name) == \(try expression(invariant.body, path: "\(componentPath).invariant"))"
                )]
            case .temporal(let temporal):
                if isTranslatorTermination(temporal) {
                    return []
                }
                if temporal.name == "Termination" {
                    throw AlgorithmPlusCalRenderDiagnostic(
                        failedConcept: "PlusCal temporal property export",
                        path: componentPath,
                        expected: "the translator's standard Termination predicate for this process family",
                        actual: "a distinct property named Termination",
                        nextSafeAction: "Rename the custom property, or use Eventually(All(domain) { Finished($0) }) so the official translator owns Termination."
                    )
                }
                return [(temporal.name, "\(temporal.name) == \(try self.temporal(temporal.expr, path: "\(componentPath).temporal"))")]
            case .process(let process):
                return try properties(in: process.components, path: "\(componentPath).components")
            case .shared, .procedure, .fairness, .formalOperator, .stateConstraint, .local, .step, .propertyBoundary:
                return []
            }
        }
    }

    private func temporals(in components: [AlgorithmComponentModel]) -> [NamedTemporal] {
        components.flatMap { component in
            switch component {
            case .temporal(let temporal): return [temporal]
            case .process(let process): return temporals(in: process.components)
            case .shared, .procedure, .invariant, .fairness, .formalOperator, .stateConstraint, .local, .step, .propertyBoundary: return []
            }
        }
    }

    private func isTranslatorTermination(_ temporal: NamedTemporal) -> Bool {
        guard temporal.name == "Termination", model.processes.count == 1,
              case .eventually(let expression) = temporal.expr,
              case .forAll(let domain, let binding, let predicate) = expression,
              domain == .setLiteral(model.processes[0].domain.map(StateExpr.value))
        else { return false }
        switch predicate {
        case .equal(.functionApply(.variable("pc"), .variable(let process)), .value(.string("Done"))),
             .equal(.value(.string("Done")), .functionApply(.variable("pc"), .variable(let process))):
            return process == binding
        default:
            return false
        }
    }

    private func temporal(_ value: TemporalExpr, path: String) throws -> String {
        switch value {
        case .always(let predicate): return "[](\(try expression(predicate, path: "\(path).always")))"
        case .eventually(let predicate): return "<>(\(try expression(predicate, path: "\(path).eventually")))"
        case .alwaysEventually(let predicate): return "[]<>(\(try expression(predicate, path: "\(path).alwaysEventually")))"
        case .eventuallyAlways(let predicate): return "<>[](\(try expression(predicate, path: "\(path).eventuallyAlways")))"
        case .leadsTo(let lhs, let rhs):
            return "(\(try expression(lhs, path: "\(path).from")) ~> \(try expression(rhs, path: "\(path).to")))"
        }
    }

    private func renderedProcessNames() -> [String] {
        var used = authoredIdentifiers()
        return model.processes.indices.map { index in
            let stem = "pcalProcess\(index + 1)"
            var candidate = stem
            var suffix = 2
            while used.contains(candidate) {
                candidate = "\(stem)_\(suffix)"
                suffix += 1
            }
            used.insert(candidate)
            return candidate
        }
    }

    private func authoredIdentifiers() -> Set<String> {
        func collect(_ components: [AlgorithmComponentModel], into names: inout Set<String>) {
            for component in components {
                switch component {
                case .shared(let declaration), .local(let declaration):
                    names.insert(declaration.root)
                case .step(let step):
                    names.insert(step.label.name)
                case .process(let process):
                    collect(process.components, into: &names)
                case .procedure(let procedure):
                    names.insert(procedure.name)
                    procedure.parameters.forEach { names.insert($0.root) }
                    procedure.locals.forEach { names.insert($0.root) }
                    procedure.steps.forEach { names.insert($0.label.name) }
                case .invariant(let invariant):
                    names.insert(invariant.name)
                case .temporal(let temporal):
                    names.insert(temporal.name)
                case .fairness, .formalOperator, .stateConstraint, .propertyBoundary:
                    continue
                }
            }
        }

        var names: Set<String> = ["self"]
        collect(model.components, into: &names)
        return names
    }

    private func set(_ values: [TLAValue]) -> String {
        "{\(values.map(\.description).joined(separator: ", "))}"
    }

    private func unsupported(path: String, expected: String, actual: String) -> AlgorithmPlusCalRenderDiagnostic {
        AlgorithmPlusCalRenderDiagnostic(
            failedConcept: "semantic-free PlusCal source rendering",
            path: path,
            expected: expected,
            actual: actual,
            nextSafeAction: "Use the supported direct PlusCal form, or extend the renderer with a syntax-only spelling before retrying."
        )
    }

    private func moduleName(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "")
    }
}
