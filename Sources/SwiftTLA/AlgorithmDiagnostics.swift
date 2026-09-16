extension AtomicStep {
    package func requireIndependentStep() throws {
        var pending = model.statements
        while let statement = pending.popLast() {
            switch statement {
            case .goto, .call, .return, .stop:
                throw CompilationDiagnostic(code: .invalidAlgorithm, stage: .validation,
                    path: "steps.\(model.label.name)",
                    expected: "an atomic step without algorithm control transfers",
                    actual: "Goto, Call, Return, and Stop require an enclosing Algorithm",
                    nextSafeAction: "Use guards for independent steps or move the step into Algorithm.")
            case .letBinding(_, _, let body), .with(_, _, let body), .choose(_, _, let body):
                pending += body
            case .ifElse(_, let first, let second), .either(let first, let second):
                pending += first + second
            case .set, .parallel, .when, .assert, .skip, .rejected:
                break
            }
        }
    }
}

package enum AlgorithmDiagnosticCode: String, Sendable, Hashable {
    case reservedName
    case invalidName
    case emptyDomain
    case duplicateDomainMember
    case duplicateLabel
    case invalidTarget
    case invalidAtomicControlFlow
    case missingStop
    case invalidAlgorithmComponent
    case invalidSequentialFairness
    case duplicateProcedure
    case duplicateProcedureVariable
    case invalidProcedureTarget
    case invalidProcedureArity
    case invalidProcedureReturn
    case invalidProcedureControlFlow
    case statementMacroArgumentCount
    case statementMacroAssignmentTarget
}

package enum AlgorithmDiagnosticAnchor: Sendable, Hashable {
    case algorithm
    case process(Int)
    case step(process: Int, label: String)
}

package struct AlgorithmDiagnostic: Sendable, Hashable, CustomStringConvertible {
    package let code: AlgorithmDiagnosticCode
    package let anchor: AlgorithmDiagnosticAnchor

    init(_ code: AlgorithmDiagnosticCode, at anchor: AlgorithmDiagnosticAnchor) {
        self.code = code
        self.anchor = anchor
    }

    package var description: String {
        "\(code.rawValue) at \(anchor)"
    }

    func compilationDiagnostic(algorithmName: String) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: .invalidAlgorithm,
            stage: .validation,
            path: "algorithms[\(algorithmName)]" + anchor.pathSuffix,
            expected: "a valid authored Algorithm declaration",
            actual: code.rawValue,
            nextSafeAction: "Correct the Algorithm declaration at the reported path."
        )
    }
}

private extension AlgorithmDiagnosticAnchor {
    var pathSuffix: String {
        switch self {
        case .algorithm:
            ""
        case .process(let index):
            ".processes[\(index)]"
        case .step(let process, let label):
            ".processes[\(process)].steps[\(label)]"
        }
    }
}

internal enum AlgorithmPlacementValidator {
    static func validate(_ model: AlgorithmModel) throws {
        for (index, component) in model.components.enumerated() {
            try validate(component, path: ["algorithm", "components[\(index)]"])
        }
    }

    private static func validate(
        _ component: AlgorithmComponentModel,
        path: [String]
    ) throws {
        switch component {
        case .invalidPlacement(let component):
            throw diagnostic(for: component, path: path)
        case .process(let process):
            for (index, component) in process.components.enumerated() {
                try validate(component, path: path + ["components[\(index)]"])
            }
        case .procedure(let procedure):
            for (index, component) in procedure.components.enumerated() {
                try validate(component, path: path + ["procedure", "components[\(index)]"])
            }
        case .shared, .invariant, .reachable, .temporal, .formalOperator,
             .stateConstraint, .local, .step:
            return
        }
    }

    private static func diagnostic(
        for component: InvalidAlgorithmComponent,
        path: [String]
    ) -> CompilationDiagnostic {
        switch component {
        case .genericFairness:
            .init(
                code: .invalidAlgorithmFairnessPlacement,
                stage: .validation,
                path: path.joined(separator: "."),
                expected: component.expectedPlacement,
                actual: component.actualPlacement,
                nextSafeAction: component.nextSafeAction
            )
        case .assumption:
            .init(
                code: .invalidAlgorithmAssumptionPlacement,
                stage: .validation,
                path: path.joined(separator: "."),
                expected: component.expectedPlacement,
                actual: component.actualPlacement,
                nextSafeAction: component.nextSafeAction
            )
        }
    }
}
