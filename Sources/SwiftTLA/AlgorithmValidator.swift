/// Procedure-specific validation is kept separate from builder assembly.
internal enum AlgorithmProcedureValidator {
    static func procedureDiagnostics(for model: AlgorithmModel) -> [AlgorithmDiagnostic] {
        var diagnostics: [AlgorithmDiagnostic] = []
        let names = model.procedures.map(\.name)
        let arities = Dictionary(uniqueKeysWithValues: model.procedures.map { ($0.name, $0.parameters.count) })
        if Set(names).count != names.count {
            diagnostics.append(.init(.duplicateProcedure, at: .algorithm))
        }
        let slots = model.procedures.flatMap { procedure in
            procedure.parameters.map(\.root) + procedure.locals.map(\.root)
        }
        if Set(slots).count != slots.count {
            diagnostics.append(.init(.duplicateProcedureVariable, at: .algorithm))
        }
        for (index, component) in model.components.enumerated() {
            switch component {
            case .procedure(let procedure):
                validate(procedure, index: index, names: Set(names), arities: arities, diagnostics: &diagnostics)
            case .step(let step):
                validateProcedureControl(
                    step.statements,
                    at: .algorithm,
                    names: Set(names),
                    arities: arities,
                    inProcedure: false,
                    allowCalls: true,
                    diagnostics: &diagnostics
                )
            case .process(let process):
                for step in process.steps {
                    validateProcedureControl(
                        step.statements,
                        at: .step(process: index, label: step.label.name),
                        names: Set(names),
                        arities: arities,
                        inProcedure: false,
                        allowCalls: true,
                        diagnostics: &diagnostics
                    )
                }
            case .shared, .formalOperator, .invariant, .temporal, .stateConstraint, .unsupported, .local:
                break
            }
        }
        return diagnostics
    }

    private static func validate(
        _ procedure: AlgorithmProcedureModel,
        index: Int,
        names: Set<String>,
        arities: [String: Int],
        diagnostics: inout [AlgorithmDiagnostic]
    ) {
        let anchor: AlgorithmDiagnosticAnchor = .process(index)
        validateName(procedure.name, at: anchor, diagnostics: &diagnostics)
        let labels = procedure.steps.map(\.label.name)
        if labels.isEmpty || Set(labels).count != labels.count {
            diagnostics.append(.init(.duplicateLabel, at: anchor))
        }
        for parameter in procedure.parameters {
            validateName(parameter.root, at: anchor, diagnostics: &diagnostics)
        }
        for local in procedure.locals {
            validateName(local.root, at: anchor, diagnostics: &diagnostics)
        }
        for step in procedure.steps {
            validate(step, at: .step(process: index, label: step.label.name), labels: Set(labels), procedures: names, arities: arities, inProcedure: true, diagnostics: &diagnostics)
        }
        for component in procedure.components {
            switch component {
            case .local, .step, .unsupported:
                continue
            case .shared, .process, .procedure, .invariant, .temporal,
                 .formalOperator, .stateConstraint:
                diagnostics.append(.init(.invalidAlgorithmComponent, at: anchor))
            }
        }
    }

    private static func validate(
        _ step: AlgorithmStepModel,
        at anchor: AlgorithmDiagnosticAnchor,
        labels: Set<String>,
        procedures: Set<String>,
        arities: [String: Int] = [:],
        inProcedure: Bool,
        diagnostics: inout [AlgorithmDiagnostic]
    ) {
        validateName(step.label.name, at: anchor, diagnostics: &diagnostics)
        let paths = writePaths(step.statements)
        if paths.contains(where: { Set($0).count != $0.count }) {
            diagnostics.append(.init(.duplicateRootWrite, at: anchor))
        }
        if AlgorithmValidator.controlTransferCounts(step.statements).contains(where: { $0 > 1 }) {
            diagnostics.append(.init(.invalidAtomicControlFlow, at: anchor))
        }
        validateStatements(step.statements, at: anchor, labels: labels, procedures: procedures, arities: arities, inProcedure: inProcedure, diagnostics: &diagnostics)
    }

    private static func validateStatements(
        _ statements: [AlgorithmStatementModel],
        at anchor: AlgorithmDiagnosticAnchor,
        labels: Set<String>,
        procedures: Set<String>,
        arities: [String: Int],
        inProcedure: Bool,
        diagnostics: inout [AlgorithmDiagnostic]
    ) {
        for (index, statement) in statements.enumerated() {
            switch statement {
            case .rejected(let code): diagnostics.append(.init(code, at: anchor))
            case .await, .assert, .skip: break
            case .set(let target, _): validateName(target.root, at: anchor, diagnostics: &diagnostics)
            case .letBinding(_, _, let body), .with(_, _, let body), .choose(_, _, let body):
                validateStatements(body, at: anchor, labels: labels, procedures: procedures, arities: arities, inProcedure: inProcedure, diagnostics: &diagnostics)
            case .ifElse(_, let then, let otherwise), .either(let then, let otherwise):
                validateStatements(then, at: anchor, labels: labels, procedures: procedures, arities: arities, inProcedure: inProcedure, diagnostics: &diagnostics)
                validateStatements(otherwise, at: anchor, labels: labels, procedures: procedures, arities: arities, inProcedure: inProcedure, diagnostics: &diagnostics)
            case .goto(let label):
                if !labels.contains(label.name) { diagnostics.append(.init(.invalidTarget, at: anchor)) }
            case .call(let target, let arguments):
                if !procedures.contains(target) { diagnostics.append(.init(.invalidProcedureTarget, at: anchor)) }
                if let arity = arities[target], arity != arguments.count {
                    diagnostics.append(.init(.invalidProcedureArity, at: anchor))
                }
                let followedByReturn: Bool
                if statements.indices.contains(index + 1), case .return = statements[index + 1] {
                    followedByReturn = true
                } else {
                    followedByReturn = false
                }
                if index != statements.index(before: statements.endIndex) && !followedByReturn {
                    diagnostics.append(.init(.invalidProcedureControlFlow, at: anchor))
                }
            case .return:
                if !inProcedure { diagnostics.append(.init(.invalidProcedureReturn, at: anchor)) }
                if index != statements.index(before: statements.endIndex) {
                    diagnostics.append(.init(.invalidProcedureControlFlow, at: anchor))
                }
            case .stop: break
            }
        }
    }

    private static func validateProcedureControl(
        _ statements: [AlgorithmStatementModel],
        at anchor: AlgorithmDiagnosticAnchor,
        names: Set<String>,
        arities: [String: Int],
        inProcedure: Bool,
        allowCalls: Bool,
        diagnostics: inout [AlgorithmDiagnostic]
    ) {
        for (index, statement) in statements.enumerated() {
            switch statement {
            case .rejected(let code): diagnostics.append(.init(code, at: anchor))
            case .call(let target, let arguments):
                if !allowCalls {
                    diagnostics.append(.init(.invalidAlgorithmComponent, at: anchor))
                    continue
                }
                if !names.contains(target) {
                    diagnostics.append(.init(.invalidProcedureTarget, at: anchor))
                }
                if let expected = arities[target], expected != arguments.count {
                    diagnostics.append(.init(.invalidProcedureArity, at: anchor))
                }
                let followedByReturn: Bool
                if statements.indices.contains(index + 1), case .return = statements[index + 1] {
                    followedByReturn = true
                } else {
                    followedByReturn = false
                }
                if index != statements.index(before: statements.endIndex) && !followedByReturn {
                    diagnostics.append(.init(.invalidProcedureControlFlow, at: anchor))
                }
            case .return:
                if !inProcedure {
                    diagnostics.append(.init(.invalidProcedureReturn, at: anchor))
                }
                if index != statements.index(before: statements.endIndex) {
                    diagnostics.append(.init(.invalidProcedureControlFlow, at: anchor))
                }
            case .letBinding(_, _, let body), .with(_, _, let body), .choose(_, _, let body):
                validateProcedureControl(body, at: anchor, names: names, arities: arities, inProcedure: inProcedure, allowCalls: allowCalls, diagnostics: &diagnostics)
            case .ifElse(_, let then, let otherwise), .either(let then, let otherwise):
                validateProcedureControl(then, at: anchor, names: names, arities: arities, inProcedure: inProcedure, allowCalls: allowCalls, diagnostics: &diagnostics)
                validateProcedureControl(otherwise, at: anchor, names: names, arities: arities, inProcedure: inProcedure, allowCalls: allowCalls, diagnostics: &diagnostics)
            case .await, .assert, .set, .goto, .stop, .skip:
                break
            }
        }
    }


    private static func writePaths(_ statements: [AlgorithmStatementModel]) -> [[String]] {
        statements.reduce(into: [[]]) { paths, statement in
            let statementPaths: [[String]]
            switch statement {
            case .rejected: statementPaths = [[]]
            case .set(let target, _): statementPaths = [[target.root]]
            case .ifElse(_, let then, let otherwise), .either(let then, let otherwise): statementPaths = writePaths(then) + writePaths(otherwise)
            case .choose(_, _, let body), .letBinding(_, _, let body), .with(_, _, let body): statementPaths = writePaths(body)
            case .await, .assert, .goto, .call, .return, .stop, .skip: statementPaths = [[]]
            }
            paths = paths.flatMap { path in statementPaths.map { path + $0 } }
        }
    }

    private static func validateDomain(_ domain: [TLAValue], at anchor: AlgorithmDiagnosticAnchor, diagnostics: inout [AlgorithmDiagnostic]) {
        if domain.isEmpty { diagnostics.append(.init(.emptyDomain, at: anchor)) }
        else if Set(domain).count != domain.count { diagnostics.append(.init(.duplicateDomainMember, at: anchor)) }
    }

    private static func validateName(_ name: String, at anchor: AlgorithmDiagnosticAnchor, diagnostics: inout [AlgorithmDiagnostic]) {
        if name.hasPrefix("__pcal_") { diagnostics.append(.init(.reservedName, at: anchor)) }
        else if isPlusCalDeclarationName(name) == false {
            diagnostics.append(.init(.invalidName, at: anchor))
        }
    }
}
