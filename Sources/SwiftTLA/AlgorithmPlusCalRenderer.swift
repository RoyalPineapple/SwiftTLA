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
public extension Algorithm {
    func renderPlusCalModule() throws -> String {
        try AlgorithmPlusCalRenderer(model: model).render()
    }
}

internal struct AlgorithmPlusCalRenderer {
    let model: AlgorithmModel

    func render() throws -> String {
        var lines = ["---- MODULE \(moduleName(model.name)) ----", "EXTENDS Naturals, Sequences, FiniteSets", "", "(*--algorithm \(model.name) {"]

        let shared = model.components.compactMap { component -> AlgorithmStateModel? in
            guard case .shared(let declaration) = component else { return nil }
            return declaration
        }
        if !shared.isEmpty {
            lines.append("variables")
            lines += declarations(shared, indent: "  ", terminator: ";")
        }

        for (index, component) in model.components.enumerated() {
            switch component {
            case .shared:
                continue
            case .procedure(let procedure):
                lines += try render(procedure: procedure, path: "components[\(index)]")
            case .process(let process):
                lines += try render(process: process, path: "components[\(index)]")
            case .step:
                // Sequential steps share the algorithm's C-syntax brace body.
                continue
            case .invariant(let invariant):
                lines.append("\\* Invariant \(invariant.name) == \(expression(invariant.body))")
            case .temporal(let temporal):
                lines.append("\\* Temporal \(temporal.name) == \(temporal.expr)")
            case .stateConstraint(let constraint):
                lines.append("\\* StateConstraint == \(expression(constraint))")
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
        lines.append("====")
        return lines.joined(separator: "\n") + "\n"
    }

    private func render(procedure: AlgorithmProcedureModel, path: String) throws -> [String] {
        var lines = ["", "procedure \(procedure.name)(\(procedure.parameters.map(\.root).joined(separator: ", ")))"]
        if !procedure.locals.isEmpty {
            lines.append("variables")
            lines += declarations(procedure.locals, indent: "  ", terminator: ";")
        }
        lines.append("{")
        for (index, step) in procedure.steps.enumerated() {
            lines += try render(step: step, indent: "  ", path: "\(path).steps[\(index)]")
        }
        lines.append("}")
        return lines
    }

    private func render(process: AlgorithmProcessModel, path: String) throws -> [String] {
        let fairness: String
        switch process.fairness {
        case .none: fairness = ""
        case .weak: fairness = "fair "
        case .strong: fairness = "fair+ "
        }
        // `self` is a PlusCal implementation name.  The Algorithm IR uses
        // `__pcal_self` internally, but spelling either one in the rendered
        // source lets the official translator capture it as an operator.
        // Give every rendered process a regular, hygienic binding instead.
        var lines = ["", "\(fairness)process (pcalSelf \\in \(set(process.domain)))"]
        let locals = process.components.compactMap { component -> AlgorithmStateModel? in
            guard case .local(let declaration) = component else { return nil }
            return declaration
        }
        if !locals.isEmpty {
            lines.append("variables")
            lines += declarations(locals, indent: "  ", terminator: ";")
        }
        lines.append("{")
        for (index, component) in process.components.enumerated() {
            switch component {
            case .local:
                continue
            case .step(let step):
                lines += try render(step: step, indent: "  ", path: "\(path).components[\(index)]")
            case .invariant(let invariant):
                lines.append("  \\* Invariant \(invariant.name) == \(expression(invariant.body))")
            case .temporal:
                throw unsupported(path: "\(path).components[\(index)]", expected: "a process statement or local declaration", actual: "process temporal property")
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

    private func declarations(_ declarations: [AlgorithmStateModel], indent: String, terminator: String) -> [String] {
        declarations.enumerated().map { index, declaration in
            let suffix = index == declarations.index(before: declarations.endIndex) ? terminator : ","
            let initializer = declaration.initialSet.map { "\\in \(expression($0))" } ?? "= \(expression(declaration.initial))"
            return "\(indent)\(declaration.root) \(initializer)\(suffix)"
        }
    }

    private func render(step: AlgorithmStepModel, indent: String, path: String) throws -> [String] {
        if let condition = step.loopCondition {
            var lines = ["\(indent)\(step.label.name): while (\(expression(condition))) {"]
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

                let rendered = assignments.map { "\(lvalue($0.target)) := \(expression($0.value))" }
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
        case .await(let condition): return ["\(indent)await \(expression(condition));"]
        case .assert(let condition): return ["\(indent)assert \(expression(condition));"]
        case .set(let target, let value): return ["\(indent)\(lvalue(target)) := \(expression(value));"]
        case .letBinding(let variable, let value, let body):
            var lines = ["\(indent)with (\(variable) = \(expression(value))) {"]
            lines += try render(statements: body, indent: indent + "  ", path: "\(path).body")
            lines.append("\(indent)};")
            return lines
        case .with(let variable, let source, let body):
            var lines = ["\(indent)with (\(variable) \\in \(expression(source))) {"]
            lines += try render(statements: body, indent: indent + "  ", path: "\(path).body")
            lines.append("\(indent)};")
            return lines
        case .ifElse(let condition, let then, let otherwise):
            var lines = ["\(indent)if (\(expression(condition))) {"]
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
        case .call(let target, let arguments): return ["\(indent)call \(target)(\(arguments.map(expression).joined(separator: ", ")));"]
        case .return: return ["\(indent)return;"]
        case .stop: return ["\(indent)goto Done;"]
        case .skip: return ["\(indent)skip;"]
        }
    }

    private func lvalue(_ value: AlgorithmLValueModel) -> String {
        switch value {
        case .root(let name): return name
        case .function(let root, let key): return "\(root)[\(expression(key))]"
        }
    }

    private func expression(_ value: StateExpr) -> String {
        value.description.replacingOccurrences(of: "__pcal_self", with: "pcalSelf")
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
