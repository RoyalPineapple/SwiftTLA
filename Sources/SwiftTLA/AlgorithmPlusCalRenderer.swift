public struct AlgorithmPlusCalRenderDiagnostic: Error, Sendable, Hashable, CustomStringConvertible {
    public let failedConcept: String
    public let path: String
    public let expected: String
    public let actual: String
    public let nextSafeAction: String

    public init(
        failedConcept: String,
        path: String,
        expected: String,
        actual: String,
        nextSafeAction: String
    ) {
        self.failedConcept = failedConcept
        self.path = path
        self.expected = expected
        self.actual = actual
        self.nextSafeAction = nextSafeAction
    }

    public var description: String {
        "PlusCal rendering failed: \(failedConcept). Path: \(path). Expected: \(expected). "
            + "Actual: \(actual). Next safe action: \(nextSafeAction)"
    }
}

internal struct AuthoredPlusCalModule: Sendable {
    let name: String
    let extendsModules: [String]
    let constants: [String]
    let preludeDeclarations: [String]
    let algorithm: AlgorithmModel
    let defineDeclarations: [String]
    let postTranslationDeclarations: [String]
    let refinements: [String]

    var supportDeclarations: [String] {
        constants + preludeDeclarations
    }
}

enum AuthoredPlusCalPropertyKind: Sendable {
    case invariant
    case temporal
}

struct AuthoredPlusCalPropertyReference: Sendable {
    let name: String
    let kind: AuthoredPlusCalPropertyKind
}

internal struct AlgorithmPlusCalRenderer {
    let module: AuthoredPlusCalModule

    init(module: AuthoredPlusCalModule) {
        self.module = module
    }

    func sourceProperties() throws -> [AuthoredPlusCalPropertyReference] {
        let model = module.algorithm
        return try propertyNames(in: model.components, path: "components")
    }

    func translatorOwnedPropertyNames() -> Set<String> {
        let model = module.algorithm
        return Set(temporals(in: model.components).compactMap { temporal in
            isTranslatorTermination(temporal) ? temporal.name : nil
        })
    }

    func render() throws -> String {
        try render(module)
    }

    private func render(_ module: AuthoredPlusCalModule) throws -> String {
        let model = module.algorithm
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

        let processNames = model.translatedProcessNames()
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
        lines += module.postTranslationDeclarations
        lines += module.refinements
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
    ) throws -> [AuthoredPlusCalPropertyReference] {
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
        case .rejected(let diagnostic):
            throw unsupported(path: path, expected: "a validated algorithm statement", actual: diagnostic.rawValue)
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
        guard let renderedExpression = StateExpr.plusCalExpression(
            from: value,
            using: { $0 }
        ) else {
            throw unsupported(
                path: path,
                expected: "a direct anonymous formal-lambda application with value arguments, or a named operator reference",
                actual: "a residual anonymous formal lambda that PlusCal cannot render without changing higher-order semantics"
            )
        }
        return renderedExpression.description
    }

    private func propertyNames(
        in components: [AlgorithmComponentModel],
        path: String
    ) throws -> [AuthoredPlusCalPropertyReference] {
        try components.enumerated().flatMap { index, component in
            let componentPath = "\(path)[\(index)]"
            switch component {
            case .invariant(let invariant):
                return [.init(name: invariant.name, kind: .invariant)]
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
                return [.init(name: temporal.name, kind: .temporal)]
            case .process(let process):
                return try propertyNames(in: process.components, path: "\(componentPath).components")
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
        let model = module.algorithm
        guard temporal.name == "Termination", model.processes.count == 1,
              case .eventually(let expression) = temporal.expr,
              case .forAll(let domain, let binding, let predicate) = expression,
              domain == .setLiteral(model.processes[0].domain.map(StateExpr.value))
        else { return false }
        switch predicate {
        case .equal(.functionApply(.programCounter, .variable(let process)), .controlLocation(let location)),
             .equal(.controlLocation(let location), .functionApply(.programCounter, .variable(let process))):
            guard location.sourceName == "Done" else { return false }
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

}
