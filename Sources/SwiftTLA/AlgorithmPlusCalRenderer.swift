internal struct AuthoredPlusCalModule: Sendable {
    let name: String
    let extendsModules: [String]
    let constants: [String]
    let preludeDeclarations: [String]
    let algorithm: CompiledAuthoredPlusCalAlgorithmPlan
    let defineDeclarations: [String]
    let postTranslationDeclarations: [String]
    let refinements: [String]

    var supportDeclarations: [String] {
        constants + preludeDeclarations
    }
}

internal struct AlgorithmPlusCalRenderer {
    let module: AuthoredPlusCalModule
    let formalRenderer: CompiledTLARenderer

    init(module: AuthoredPlusCalModule, formalRenderer: CompiledTLARenderer) {
        self.module = module
        self.formalRenderer = formalRenderer
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
        let fairness = model.sequentialFairness == .weak ? "fair " : ""
        lines.append("(*--\(fairness)algorithm \(model.name) {")

        if model.shared.isEmpty == false {
            lines.append("variables")
            lines += try declarations(model.shared, indent: "  ", terminator: ";")
        }
        if !module.defineDeclarations.isEmpty {
            lines.append("define {")
            lines += module.defineDeclarations.map { "  \($0)" }
            lines.append("}")
        }

        for procedure in model.procedures {
            lines += try render(procedure: procedure)
        }
        for process in model.processes {
            lines += try render(process: process)
        }

        if model.sequentialSteps.isEmpty == false {
            lines.append("{")
            for step in model.sequentialSteps {
                lines += try render(step: step, indent: "  ")
            }
            lines.append("}")
        }
        lines.append("} *)")
        lines += module.postTranslationDeclarations
        lines += module.refinements
        lines.append("====")
        return lines.joined(separator: "\n") + "\n"
    }

    private func render(procedure: CompiledAuthoredPlusCalProcedure) throws -> [String] {
        let name = try formalRenderer.procedureName(procedure.id)
        let parameters = try procedure.parameters.map(formalRenderer.binderName)
        var lines = ["", "procedure \(name)(\(parameters.joined(separator: ", ")))"]
        if procedure.locals.isEmpty == false {
            lines.append("variables")
            lines += try declarations(procedure.locals, indent: "  ", terminator: ";")
        }
        lines.append("{")
        for step in procedure.steps {
            lines += try render(step: step, indent: "  ")
        }
        lines.append("}")
        return lines
    }

    private func render(process: CompiledAuthoredPlusCalProcess) throws -> [String] {
        let fairness: String
        switch process.fairness {
        case .none: fairness = ""
        case .weak: fairness = "fair "
        case .strong: fairness = "fair+ "
        }
        // The header identifier names the process set. `self` names its
        // current member inside the process body.
        var lines = ["", "\(fairness)process (\(process.name) \\in \(try set(process.domain)))"]
        if process.locals.isEmpty == false {
            lines.append("variables")
            lines += try declarations(process.locals, indent: "  ", terminator: ";")
        }
        lines.append("{")
        for step in process.steps {
            lines += try render(step: step, indent: "  ")
        }
        lines.append("}")
        return lines
    }

    private func declarations(
        _ declarations: [CompiledAuthoredPlusCalState],
        indent: String,
        terminator: String
    ) throws -> [String] {
        try declarations.enumerated().map { index, declaration in
            let suffix = index == declarations.index(before: declarations.endIndex) ? terminator : ","
            let name = try formalRenderer.variableName(declaration.variable)
            let initializer: String
            switch declaration.initialization {
            case .expression(let value): initializer = "= \(try expression(value))"
            case .memberOf(let set): initializer = "\\in \(try expression(set))"
            }
            return "\(indent)\(name) \(initializer)\(suffix)"
        }
    }

    private func render(step: CompiledAuthoredPlusCalStep, indent: String) throws -> [String] {
        if let condition = step.loopCondition {
            let label = try formalRenderer.controlLocationSourceName(step.label)
            var lines = ["\(indent)\(label): while (\(try expression(condition))) {"]
            lines += try render(statements: step.statements, indent: indent + "  ")
            lines.append("\(indent)};")
            return lines
        }
        let label = try formalRenderer.controlLocationSourceName(step.label)
        var lines = ["\(indent)\(label):"]
        lines += try render(statements: step.statements, indent: indent + "  ")
        return lines
    }

    private func render(statements: [CompiledAuthoredPlusCalStatement], indent: String) throws -> [String] {
        try statements.flatMap { statement in
            try render(statement: statement, indent: indent)
        }
    }

    private func render(statement: CompiledAuthoredPlusCalStatement, indent: String) throws -> [String] {
        switch statement {
        case .await(let condition): return ["\(indent)await \(try expression(condition));"]
        case .assert(let condition): return ["\(indent)assert \(try expression(condition));"]
        case .set(let target, let value):
            return ["\(indent)\(try lvalue(target)) := \(try expression(value));"]
        case .parallel(let assignments):
            let rendered = try assignments.map { assignment in
                "\(try lvalue(assignment.target)) := \(try expression(assignment.value))"
            }.joined(separator: " || ")
            return ["\(indent)\(rendered);"]
        case .letBinding(let variable, let value, let body):
            let binder = try formalRenderer.binderName(variable)
            var lines = ["\(indent)with (\(binder) = \(try expression(value))) {"]
            lines += try render(statements: body, indent: indent + "  ")
            lines.append("\(indent)};")
            return lines
        case .with(let variable, let source, let body):
            let binder = try formalRenderer.binderName(variable)
            var lines = ["\(indent)with (\(binder) \\in \(try expression(source))) {"]
            lines += try render(statements: body, indent: indent + "  ")
            lines.append("\(indent)};")
            return lines
        case .ifElse(let condition, let then, let otherwise):
            var lines = ["\(indent)if (\(try expression(condition))) {"]
            lines += try render(statements: then, indent: indent + "  ")
            if otherwise.isEmpty {
                lines.append("\(indent)};")
            } else {
                lines.append("\(indent)} else {")
                lines += try render(statements: otherwise, indent: indent + "  ")
                lines.append("\(indent)};")
            }
            return lines
        case .either(let first, let second):
            var lines = ["\(indent)either {"]
            lines += try render(statements: first, indent: indent + "  ")
            lines.append("\(indent)} or {")
            lines += try render(statements: second, indent: indent + "  ")
            lines.append("\(indent)};")
            return lines
        case .goto(let label):
            return ["\(indent)goto \(try formalRenderer.controlLocationSourceName(label));"]
        case .call(let target, let arguments):
            let name = try formalRenderer.procedureName(target)
            let values = try arguments.map(expression).joined(separator: ", ")
            return ["\(indent)call \(name)(\(values));"]
        case .return: return ["\(indent)return;"]
        case .skip: return ["\(indent)skip;"]
        }
    }

    private func lvalue(_ value: CompiledAuthoredPlusCalLValue) throws -> String {
        switch value {
        case .root(let variable):
            return try formalRenderer.variableName(variable)
        case .function(let root, let key):
            return "\(try formalRenderer.variableName(root))[\(try expression(key))]"
        }
    }

    private func expression(_ value: CompiledStateExpr) throws -> String {
        try formalRenderer.state(value)
    }

    private func set(_ values: [CompiledValue]) throws -> String {
        let rendered = try values.map { try $0.rendered(using: formalRenderer.layout).description }
        return "{\(rendered.joined(separator: ", "))}"
    }

}
