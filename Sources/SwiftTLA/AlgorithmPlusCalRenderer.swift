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
    let algorithm: AuthoredPlusCalAlgorithmPlan
    let defineDeclarations: [String]
    let postTranslationDeclarations: [String]
    let refinements: [String]

    var supportDeclarations: [String] {
        constants + preludeDeclarations
    }
}

private func authoredPlusCalIdentifier(
    _ name: String,
    path: String,
    validatingIdentifiers: Bool = true,
    allowingReservedWord: Bool = false
) throws -> String {
    let isValid = allowingReservedWord ? isFormalIdentifier(name) : isPlusCalDeclarationName(name)
    guard validatingIdentifiers == false || isValid else {
        throw AlgorithmPlusCalRenderDiagnostic(
            failedConcept: "formal identifier rendering",
            path: path,
            expected: "an ASCII identifier beginning with a letter or underscore",
            actual: "invalid identifier '\(name)'",
            nextSafeAction: "Use only ASCII letters, digits, and underscores, beginning with a letter or underscore."
        )
    }
    return name
}

private func authoredPlusCalOperatorReference(_ name: String, path: String) throws -> String {
    let separator = "\u{21}"
    let components = name.components(separatedBy: separator)
    return try components.enumerated().map {
        try authoredPlusCalIdentifier($0.element, path: "\(path).components[\($0.offset)]")
    }.joined(separator: separator)
}

private extension FormalOperator {
    func authoredPlusCalSource(path: String, validatingIdentifiers: Bool) throws -> String {
        switch self {
        case .lambda(let lambda):
            let parameters = try lambda.parameters.enumerated().map {
                try authoredPlusCalIdentifier(
                    $0.element,
                    path: "\(path).parameters[\($0.offset)]",
                    validatingIdentifiers: validatingIdentifiers
                )
            }.joined(separator: ", ")
            return "LAMBDA \(parameters) : \(try lambda.body.authoredPlusCalSource(path: "\(path).body", validatingIdentifiers: validatingIdentifiers))"
        case .reference(let name, _):
            guard validatingIdentifiers else { return name }
            return try authoredPlusCalOperatorReference(name, path: path)
        }
    }
}

private extension FormalCallArgument {
    func authoredPlusCalSource(path: String, validatingIdentifiers: Bool) throws -> String {
        switch self {
        case .value(let expression):
            return try expression.authoredPlusCalSource(path: path, validatingIdentifiers: validatingIdentifiers)
        case .operator(let operation):
            return try operation.authoredPlusCalSource(path: path, validatingIdentifiers: validatingIdentifiers)
        }
    }
}

extension StateExpr {
    func authoredPlusCalSource(path: String, validatingIdentifiers: Bool = true) throws -> String {
        func source(_ value: StateExpr, _ component: String) throws -> String {
            try value.authoredPlusCalSource(
                path: "\(path).\(component)",
                validatingIdentifiers: validatingIdentifiers
            )
        }

        func binary(_ lhs: StateExpr, _ separator: String, _ rhs: StateExpr) throws -> String {
            "(\(try source(lhs, "left"))\(separator)\(try source(rhs, "right")))"
        }

        func list(_ values: [StateExpr], component: String) throws -> String {
            try values.enumerated().map {
                try $0.element.authoredPlusCalSource(
                    path: "\(path).\(component)[\($0.offset)]",
                    validatingIdentifiers: validatingIdentifiers
                )
            }.joined(separator: ", ")
        }

        switch self {
        case .sourceIssue(let issue):
            if validatingIdentifiers == false { return issue.description }
            throw AlgorithmPlusCalRenderDiagnostic(
                failedConcept: "formal expression rendering",
                path: path,
                expected: "a validated formal expression",
                actual: issue.description,
                nextSafeAction: "Resolve the source diagnostic, then compile again."
            )
        case .processLocalFamily(let name):
            if validatingIdentifiers == false { return "processLocalFamily(\(name))" }
            throw AlgorithmPlusCalRenderDiagnostic(
                failedConcept: "process-local expression rendering",
                path: path,
                expected: "a process-local reference projected for the current process",
                actual: "unresolved process-local family '\(name)'",
                nextSafeAction: "Compile the Algorithm before rendering authored PlusCal."
            )
        case .currentProcess:
            if validatingIdentifiers == false { return "currentProcess" }
            throw AlgorithmPlusCalRenderDiagnostic(
                failedConcept: "current-process expression rendering",
                path: path,
                expected: "the projected PlusCal self identifier",
                actual: "an unresolved current-process expression",
                nextSafeAction: "Compile the Algorithm before rendering authored PlusCal."
            )
        case .value(let value): return value.description
        case .variable(let name):
            return try authoredPlusCalIdentifier(name, path: path, validatingIdentifiers: validatingIdentifiers)
        case .programCounter: return CompilerControlSymbol.programCounter.rawValue
        case .procedureStack: return CompilerControlSymbol.stack.rawValue
        case .controlLocation(let reference): return TLAValue.string(reference.sourceName).description
        case .add(let lhs, let rhs): return try binary(lhs, " + ", rhs)
        case .subtract(let lhs, let rhs): return try binary(lhs, " - ", rhs)
        case .multiply(let lhs, let rhs): return try binary(lhs, " * ", rhs)
        case .divide(let lhs, let rhs), .integerDivide(let lhs, let rhs): return try binary(lhs, " \\div ", rhs)
        case .modulo(let lhs, let rhs): return try binary(lhs, " % ", rhs)
        case .negate(let value): return "(-\(try source(value, "value")))"
        case .equal(let lhs, let rhs): return try binary(lhs, " = ", rhs)
        case .notEqual(let lhs, let rhs): return try binary(lhs, " /= ", rhs)
        case .lessThan(let lhs, let rhs): return try binary(lhs, " < ", rhs)
        case .lessOrEqual(let lhs, let rhs): return try binary(lhs, " <= ", rhs)
        case .greaterThan(let lhs, let rhs): return try binary(lhs, " > ", rhs)
        case .greaterOrEqual(let lhs, let rhs): return try binary(lhs, " >= ", rhs)
        case .and(let lhs, let rhs): return try binary(lhs, " /\\ ", rhs)
        case .or(let lhs, let rhs):
            return "(IF \(try source(lhs, "left")) THEN TRUE ELSE \(try source(rhs, "right")))"
        case .not(let value): return "(~\(try source(value, "value")))"
        case .ifThenElse(let condition, let then, let otherwise):
            return "(IF \(try source(condition, "condition")) THEN \(try source(then, "then")) ELSE \(try source(otherwise, "else")))"
        case .setLiteral(let values): return "{\(try list(values, component: "members"))}"
        case .in(let lhs, let rhs): return try binary(lhs, " \\in ", rhs)
        case .subset(let lhs, let rhs): return try binary(lhs, " \\subseteq ", rhs)
        case .union(let lhs, let rhs): return try binary(lhs, " \\cup ", rhs)
        case .intersection(let lhs, let rhs): return try binary(lhs, " \\cap ", rhs)
        case .setDifference(let lhs, let rhs): return try binary(lhs, " \\ ", rhs)
        case .cardinality(let value): return "Cardinality(\(try source(value, "value")))"
        case .setFilter(let set, let name, let predicate):
            let binder = try authoredPlusCalIdentifier(name, path: "\(path).binder", validatingIdentifiers: validatingIdentifiers)
            return "{\(binder) \\in \(try source(set, "domain")) : \(try source(predicate, "body"))}"
        case .setMap(let value, let name, let set):
            let binder = try authoredPlusCalIdentifier(name, path: "\(path).binder", validatingIdentifiers: validatingIdentifiers)
            return "{\(try source(value, "body")) : \(binder) \\in \(try source(set, "domain"))}"
        case .powerSet(let value): return "SUBSET \(try source(value, "value"))"
        case .unionAll(let value): return "UNION \(try source(value, "value"))"
        case .integerRange(let lower, let upper): return "\(try source(lower, "lower"))..\(try source(upper, "upper"))"
        case .tupleLiteral(let values): return "<<\(try list(values, component: "members"))>>"
        case .tupleAccess(let tuple, let index): return "\(try source(tuple, "tuple"))[\(index)]"
        case .tupleDynamicAccess(let tuple, let index):
            return "\(try source(tuple, "tuple"))[\(try source(index, "index"))]"
        case .tupleLength(let tuple): return "Len(\(try source(tuple, "tuple")))"
        case .tupleAppend(let tuple, let value): return "Append(\(try source(tuple, "tuple")), \(try source(value, "value")))"
        case .tupleHead(let tuple): return "Head(\(try source(tuple, "tuple")))"
        case .tupleTail(let tuple): return "Tail(\(try source(tuple, "tuple")))"
        case .tupleConcatenate(let lhs, let rhs): return try binary(lhs, " \\o ", rhs)
        case .recordLiteral(let fields):
            let entries = try fields.fields.enumerated().map { index, field in
                let name = try authoredPlusCalIdentifier(
                    field.name,
                    path: "\(path).fields[\(index)].name",
                    validatingIdentifiers: validatingIdentifiers,
                    allowingReservedWord: true
                )
                return "\(name) |-> \(try field.value.authoredPlusCalSource(path: "\(path).fields[\(index)].value", validatingIdentifiers: validatingIdentifiers))"
            }
            return "[\(entries.joined(separator: ", "))]"
        case .recordAccess(let record, let field):
            return "(\(try source(record, "record"))).\(try authoredPlusCalIdentifier(field, path: "\(path).field", validatingIdentifiers: validatingIdentifiers, allowingReservedWord: true))"
        case .domain(let function): return "DOMAIN \(try source(function, "function"))"
        case .functionLiteral(let domain, let name, let body):
            let binder = try authoredPlusCalIdentifier(name, path: "\(path).binder", validatingIdentifiers: validatingIdentifiers)
            return "[\(binder) \\in \(try source(domain, "domain")) |-> \(try source(body, "body"))]"
        case .functionApply(let function, let argument):
            return "\(try source(function, "function"))[\(try source(argument, "argument"))]"
        case .except(let function, let key, let value):
            return "[\(try source(function, "function")) EXCEPT \u{21}[\(try source(key, "key"))] = \(try source(value, "value"))]"
        case .caseExpr(let pairs, let otherwise):
            guard pairs.isEmpty == false, pairs.count.isMultiple(of: 2) else {
                if validatingIdentifiers == false {
                    return pairs.isEmpty
                        ? "CASE <missing condition and value branch>"
                        : "CASE <unmatched condition \(pairs.last.map(String.init(describing:)) ?? "missing")>"
                }
                throw AlgorithmPlusCalRenderDiagnostic(
                    failedConcept: "CASE expression rendering",
                    path: path,
                    expected: "complete condition and value pairs",
                    actual: pairs.isEmpty ? "no CASE branches" : "an unmatched CASE branch",
                    nextSafeAction: "Provide complete CASE branches, then compile again."
                )
            }
            var branches = try stride(from: 0, to: pairs.count, by: 2).map { index in
                "\(try pairs[index].authoredPlusCalSource(path: "\(path).branch[\(index / 2)].condition", validatingIdentifiers: validatingIdentifiers)) -> \(try pairs[index + 1].authoredPlusCalSource(path: "\(path).branch[\(index / 2)].value", validatingIdentifiers: validatingIdentifiers))"
            }
            if let otherwise {
                branches.append("OTHER -> \(try source(otherwise, "otherwise"))")
            }
            return "CASE \(branches.joined(separator: " [] "))"
        case .forAll(let set, let name, let predicate):
            let binder = try authoredPlusCalIdentifier(name, path: "\(path).binder", validatingIdentifiers: validatingIdentifiers)
            return "\\A \(binder) \\in \(try source(set, "domain")) : \(try source(predicate, "body"))"
        case .exists(let set, let name, let predicate):
            let binder = try authoredPlusCalIdentifier(name, path: "\(path).binder", validatingIdentifiers: validatingIdentifiers)
            return "\\E \(binder) \\in \(try source(set, "domain")) : \(try source(predicate, "body"))"
        case .choose(let set, let name, let predicate):
            let binder = try authoredPlusCalIdentifier(name, path: "\(path).binder", validatingIdentifiers: validatingIdentifiers)
            return "CHOOSE \(binder) \\in \(try source(set, "domain")) : \(try source(predicate, "body"))"
        case .enabledAction(let name):
            return "ENABLED \(try authoredPlusCalIdentifier(name, path: path, validatingIdentifiers: validatingIdentifiers))"
        case .sequenceFromSet(let set): return "SeqFromSet(\(try source(set, "set")))"
        case .setSum(let function, let set): return "Sum(\(try source(function, "function")), \(try source(set, "set")))"
        case .functionSet(let domain, let range): return "[\(try source(domain, "domain")) -> \(try source(range, "range"))]"
        case .foldFunction(let operation, let initial, let sequence):
            let lambda = try FormalOperator.lambda(operation).authoredPlusCalSource(
                path: "\(path).operation",
                validatingIdentifiers: validatingIdentifiers
            )
            return "FoldFunction(\(lambda), \(try source(initial, "initial")), \(try source(sequence, "sequence")))"
        case .operatorApplication(let operation, let arguments):
            let renderedOperation = try operation.authoredPlusCalSource(
                path: "\(path).operation",
                validatingIdentifiers: validatingIdentifiers
            )
            let renderedArguments = try arguments.enumerated().map {
                try $0.element.authoredPlusCalSource(
                    path: "\(path).arguments[\($0.offset)]",
                    validatingIdentifiers: validatingIdentifiers
                )
            }.joined(separator: ", ")
            if case .lambda = operation {
                return "(\(renderedOperation))(\(renderedArguments))"
            }
            return renderedArguments.isEmpty ? renderedOperation : "\(renderedOperation)(\(renderedArguments))"
        case .recursiveCall(let name, let arguments):
            let operation = validatingIdentifiers
                ? try authoredPlusCalOperatorReference(name, path: path)
                : name
            let renderedArguments = try list(arguments, component: "arguments")
            return arguments.isEmpty ? operation : "\(operation)(\(renderedArguments))"
        case .letValue(let name, let value, let body):
            let binder = try authoredPlusCalIdentifier(name, path: "\(path).binder", validatingIdentifiers: validatingIdentifiers)
            return "LET \(binder) == \(try source(value, "value")) IN \(try source(body, "body"))"
        case .letIn(let operators, let body):
            let names = Set(operators.map(\.name))
            let recursiveNames = operators
                .filter { $0.domain == nil }
                .flatMap { localOperatorCalls(in: $0.body) }
                .filter(names.contains)
            let recursive = try operators.filter { recursiveNames.contains($0.name) }.enumerated().map { _, operation in
                let name = try authoredPlusCalIdentifier(
                    operation.name,
                    path: "\(path).operators.\(operation.name)",
                    validatingIdentifiers: validatingIdentifiers
                )
                let slots = operation.parameters.map { _ in "_" }.joined(separator: ", ")
                return operation.parameters.isEmpty ? name : "\(name)(\(slots))"
            }.joined(separator: ", ")
            let declarations = try operators.enumerated().map { index, operation in
                let operationPath = "\(path).operators[\(index)]"
                let name = try authoredPlusCalIdentifier(
                    operation.name,
                    path: "\(operationPath).name",
                    validatingIdentifiers: validatingIdentifiers
                )
                let parameters = try operation.parameters.enumerated().map {
                    try authoredPlusCalIdentifier(
                        $0.element,
                        path: "\(operationPath).parameters[\($0.offset)]",
                        validatingIdentifiers: validatingIdentifiers
                    )
                }
                let signature: String
                if let domain = operation.domain, let parameter = parameters.first {
                    signature = "[\(parameter) \\in \(try domain.authoredPlusCalSource(path: "\(operationPath).domain", validatingIdentifiers: validatingIdentifiers))]"
                } else {
                    signature = parameters.isEmpty ? "" : "(\(parameters.joined(separator: ", ")))"
                }
                return "\(name)\(signature) == \(try operation.body.authoredPlusCalSource(path: "\(operationPath).body", validatingIdentifiers: validatingIdentifiers))"
            }.joined(separator: "\n    ")
            let recursiveDeclaration = recursive.isEmpty ? "" : "RECURSIVE \(recursive)\n    "
            return "LET \(recursiveDeclaration)\(declarations)\nIN \(try source(body, "body"))"
        }
    }
}

internal struct AlgorithmPlusCalRenderer {
    let module: AuthoredPlusCalModule

    init(module: AuthoredPlusCalModule) {
        self.module = module
    }

    func render() throws -> String {
        try render(module)
    }

    private func render(_ module: AuthoredPlusCalModule) throws -> String {
        let model = module.algorithm
        // TLA+ spells negative values through the unary `-.` operator from
        // `Integers`.  PlusCal's translator preserves that operator in the
        // generated module, so every rendered source must make it available.
        let moduleName = try authoredPlusCalIdentifier(module.name, path: "module.name")
        let extendsModules = try module.extendsModules.enumerated().map {
            try authoredPlusCalIdentifier($0.element, path: "module.extends[\($0.offset)]")
        }
        var lines = ["---- MODULE \(moduleName) ----", "EXTENDS \(extendsModules.joined(separator: ", "))", ""]
        if !module.supportDeclarations.isEmpty {
            lines += module.supportDeclarations
            lines.append("")
        }
        let fairness = model.sequentialFairness == .weak ? "fair " : ""
        let algorithmName = try authoredPlusCalIdentifier(model.name, path: "algorithm.name")
        lines.append("(*--\(fairness)algorithm \(algorithmName) {")

        if model.shared.isEmpty == false {
            lines.append("variables")
            lines += try declarations(model.shared, indent: "  ", terminator: ";", path: "shared")
        }
        if !module.defineDeclarations.isEmpty {
            lines.append("define {")
            lines += module.defineDeclarations.map { "  \($0)" }
            lines.append("}")
        }

        for (index, procedure) in model.procedures.enumerated() {
            lines += try render(procedure: procedure, path: "procedures[\(index)]")
        }
        for (index, process) in model.processes.enumerated() {
            lines += try render(process: process, path: "processes[\(index)]")
        }

        if model.sequentialSteps.isEmpty == false {
            lines.append("{")
            for (index, step) in model.sequentialSteps.enumerated() {
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
        let name = try authoredPlusCalIdentifier(procedure.name, path: "\(path).name")
        let parameters = try procedure.parameters.enumerated().map {
            try authoredPlusCalIdentifier($0.element.root, path: "\(path).parameters[\($0.offset)]")
        }
        var lines = ["", "procedure \(name)(\(parameters.joined(separator: ", ")))"]
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
        process: AuthoredPlusCalProcessPlan,
        path: String
    ) throws -> [String] {
        let fairness: String
        switch process.fairness {
        case .none: fairness = ""
        case .weak: fairness = "fair "
        case .strong: fairness = "fair+ "
        }
        // The header identifier names the process set. `self` names its
        // current member inside the process body.
        var lines = ["", "\(fairness)process (\(process.name) \\in \(set(process.domain)))"]
        if process.locals.isEmpty == false {
            lines.append("variables")
            lines += try declarations(process.locals, indent: "  ", terminator: ";", path: "\(path).locals")
        }
        lines.append("{")
        for (index, step) in process.steps.enumerated() {
            lines += try render(step: step, indent: "  ", path: "\(path).steps[\(index)]")
        }
        lines.append("}")
        return lines
    }

    private func declarations(
        _ declarations: [AlgorithmStateModel],
        indent: String,
        terminator: String,
        path: String
    ) throws -> [String] {
        try declarations.enumerated().map { index, declaration in
            let suffix = index == declarations.index(before: declarations.endIndex) ? terminator : ","
            let name = try authoredPlusCalIdentifier(declaration.root, path: "\(path)[\(index)].name")
            let initializer: String
            switch declaration.initialization {
            case .value(let value): initializer = "= \(value)"
            case .expression(let value): initializer = "= \(try expression(value, path: "\(path)[\(index)].initialization"))"
            case .memberOf(let set): initializer = "\\in \(try expression(set, path: "\(path)[\(index)].initialization"))"
            }
            return "\(indent)\(name) \(initializer)\(suffix)"
        }
    }

    private func render(step: AlgorithmStepModel, indent: String, path: String) throws -> [String] {
        if let condition = step.loopCondition {
            let label = try authoredPlusCalIdentifier(step.label.name, path: "\(path).label")
            var lines = ["\(indent)\(label): while (\(try expression(condition, path: "\(path).condition"))) {"]
            lines += try render(statements: step.statements, indent: indent + "  ", path: "\(path).statements")
            lines.append("\(indent)};")
            return lines
        }
        let label = try authoredPlusCalIdentifier(step.label.name, path: "\(path).label")
        var lines = ["\(indent)\(label):"]
        lines += try render(statements: step.statements, indent: indent + "  ", path: "\(path).statements")
        return lines
    }

    private func render(statements: [AlgorithmStatementModel], indent: String, path: String) throws -> [String] {
        try statements.enumerated().flatMap { index, statement in
            try render(statement: statement, indent: indent, path: "\(path)[\(index)]")
        }
    }

    private func render(statement: AlgorithmStatementModel, indent: String, path: String) throws -> [String] {
        switch statement {
        case .rejected(let diagnostic):
            throw unplannedStatement(diagnostic.rawValue, path: path)
        case .await(let condition): return ["\(indent)await \(try expression(condition, path: "\(path).condition"));"]
        case .assert(let condition): return ["\(indent)assert \(try expression(condition, path: "\(path).condition"));"]
        case .set(let target, let value):
            return ["\(indent)\(try lvalue(target, path: "\(path).target")) := \(try expression(value, path: "\(path).value"));"]
        case .parallel(let assignments):
            let rendered = try assignments.enumerated().map { index, assignment in
                "\(try lvalue(assignment.target, path: "\(path)[\(index)].target")) := \(try expression(assignment.value, path: "\(path)[\(index)].value"))"
            }.joined(separator: " || ")
            return ["\(indent)\(rendered);"]
        case .letBinding(let variable, let value, let body):
            let binder = try authoredPlusCalIdentifier(variable, path: "\(path).binder")
            var lines = ["\(indent)with (\(binder) = \(try expression(value, path: "\(path).value"))) {"]
            lines += try render(statements: body, indent: indent + "  ", path: "\(path).body")
            lines.append("\(indent)};")
            return lines
        case .with(let variable, let source, let body):
            let binder = try authoredPlusCalIdentifier(variable, path: "\(path).binder")
            var lines = ["\(indent)with (\(binder) \\in \(try expression(source, path: "\(path).source"))) {"]
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
        case .choose:
            throw unplannedStatement("choose", path: path)
        case .goto(let label):
            return ["\(indent)goto \(try authoredPlusCalIdentifier(label.name, path: "\(path).label"));"]
        case .call(let target, let arguments):
            let name = try authoredPlusCalIdentifier(target, path: "\(path).procedure")
            let values = try arguments.enumerated().map {
                try expression($0.element, path: "\(path).arguments[\($0.offset)]")
            }.joined(separator: ", ")
            return ["\(indent)call \(name)(\(values));"]
        case .return: return ["\(indent)return;"]
        case .stop:
            throw unplannedStatement("stop", path: path)
        case .skip: return ["\(indent)skip;"]
        }
    }

    private func lvalue(_ value: AlgorithmLValueModel, path: String) throws -> String {
        switch value {
        case .root(let name): return try authoredPlusCalIdentifier(name, path: path)
        case .function(let root, let key):
            return "\(try authoredPlusCalIdentifier(root, path: path))[\(try expression(key, path: "\(path).key"))]"
        }
    }

    private func expression(_ value: StateExpr, path: String) throws -> String {
        try value.authoredPlusCalSource(path: path)
    }

    private func set(_ values: [TLAValue]) -> String {
        "{\(values.map(\.description).joined(separator: ", "))}"
    }

    private func unplannedStatement(_ statement: String, path: String) -> CompilationDiagnostic {
        .init(
            code: .invalidAuthoredPlusCalPlan,
            stage: .rendering,
            path: path,
            expected: "a planned authored PlusCal statement",
            actual: statement,
            nextSafeAction: "Compile the model again from its current source."
        )
    }

}
