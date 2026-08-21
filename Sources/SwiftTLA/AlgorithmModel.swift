import Foundation

/// Internal marker for a process-local variable viewed as its lowered
/// per-process function.  It is introduced only by `LocalVariable.family` and
/// removed by the algorithm lowerer before the formal specification escapes.
let algorithmLocalFamilyPrefix = "__pcal_local_family:"

internal struct AlgorithmModel: Sendable {
    let name: String
    let components: [AlgorithmComponentModel]

    var processes: [AlgorithmProcessModel] {
        components.compactMap {
            guard case .process(let process) = $0 else { return nil }
            return process
        }
    }

    /// A PlusCal `begin ... end algorithm` body has one scalar program
    /// counter. Keep it distinct from a one-member `Each` process, whose
    /// counter is a function and whose transition labels carry a parameter.
    var sequentialSteps: [AlgorithmStepModel] {
        components.compactMap {
            guard case .step(let step) = $0 else { return nil }
            return step
        }
    }

    var procedures: [AlgorithmProcedureModel] {
        components.compactMap {
            guard case .procedure(let procedure) = $0 else { return nil }
            return procedure
        }
    }

    var formalOperatorDefinitions: [FormalOperatorDefinition] {
        components.compactMap {
            guard case .formalOperator(let definition) = $0 else { return nil }
            return definition
        }
    }

    var stateDeclarations: [AlgorithmStateModel] {
        components.flatMap { component in
            switch component {
            case .shared(let state): return [state]
            case .process(let process):
                return process.components.compactMap {
                    guard case .local(let state) = $0 else { return nil }
                    return state
                }
            case .procedure(let procedure):
                return procedure.parameters.map {
                    .init(root: $0.root, initial: $0.initial, swiftTypeName: $0.swiftTypeName)
                } + procedure.locals
            default: return []
            }
        }
    }

    /// Names the generated PlusCal process operators exactly as pcal.trans
    /// does, including collisions with authored declarations.
    func translatedProcessNames() -> [String] {
        var used = authoredIdentifiers
        return processes.indices.map { index in
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

    private var authoredIdentifiers: Set<String> {
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

        var result: Set<String> = ["self"]
        collect(components, into: &result)
        return result
    }

    func plusCalProjection() -> AlgorithmModel {
        let localRoots: Set<String> = Set(processes.flatMap { process in
            process.components.compactMap { component in
                guard case .local(let declaration) = component else { return nil }
                return declaration.root
            }
        })

        func expression(_ value: StateExpr) -> StateExpr {
            let family = localRoots.reduce(value) { result, root in
                StateExpr.substituteVariable(
                    "\(algorithmLocalFamilyPrefix)\(root)",
                    with: .variable(root),
                    in: result
                )
            }
            return family.replacingCurrentProcess(with: .variable("self"))
        }

        func temporal(_ value: TemporalExpr) -> TemporalExpr {
            switch value {
            case .always(let predicate): return .always(expression(predicate))
            case .eventually(let predicate): return .eventually(expression(predicate))
            case .alwaysEventually(let predicate): return .alwaysEventually(expression(predicate))
            case .eventuallyAlways(let predicate): return .eventuallyAlways(expression(predicate))
            case .leadsTo(let source, let destination): return .leadsTo(expression(source), expression(destination))
            }
        }

        func state(_ value: AlgorithmStateModel) -> AlgorithmStateModel {
            .init(
                root: value.root,
                initial: expression(value.initial),
                initialSet: value.initialSet.map(expression),
                swiftTypeName: value.swiftTypeName,
                isTuple: value.isTuple
            )
        }

        func statements(_ values: [AlgorithmStatementModel]) -> [AlgorithmStatementModel] {
            values.map { statement in
                statement.replacingCurrentProcess(with: .variable("self"))
            }.map { statement in
                localRoots.reduce(statement) { result, root in
                    result.substitutingVariable(
                        "\(algorithmLocalFamilyPrefix)\(root)",
                        with: .variable(root),
                        assignmentTargets: .preserve
                    )
                }
            }
        }

        func step(_ value: AlgorithmStepModel) -> AlgorithmStepModel {
            .init(
                label: value.label,
                statements: statements(value.statements),
                loopCondition: value.loopCondition.map(expression)
            )
        }

        func component(_ value: AlgorithmComponentModel) -> AlgorithmComponentModel {
            switch value {
            case .shared(let declaration): return .shared(state(declaration))
            case .process(let process):
                return .process(
                    .init(
                        typeName: process.typeName,
                        domain: process.domain,
                        fairness: process.fairness,
                        components: process.components.map(component)
                    )
                )
            case .procedure(let procedure):
                return .procedure(
                    .init(
                        name: procedure.name,
                        parameters: procedure.parameters.map {
                            .init(root: $0.root, initial: expression($0.initial), swiftTypeName: $0.swiftTypeName)
                        },
                        locals: procedure.locals.map(state),
                        steps: procedure.steps.map(step)
                    )
                )
            case .invariant(let invariant):
                return .invariant(.init(name: invariant.name, body: expression(invariant.body)))
            case .temporal(let declaration):
                return .temporal(.init(name: declaration.name, expr: temporal(declaration.expr)))
            case .fairness:
                return value
            case .formalOperator(let definition):
                return .formalOperator(
                    .init(
                        name: definition.name,
                        parameters: definition.parameters,
                        body: expression(definition.body),
                        plusCalPhase: definition.plusCalPhase,
                        plusCalDependencies: definition.plusCalDependencies
                    )
                )
            case .stateConstraint(let constraint): return .stateConstraint(expression(constraint))
            case .local(let declaration): return .local(state(declaration))
            case .step(let declaration): return .step(step(declaration))
            case .propertyBoundary: return .propertyBoundary
            }
        }

        return .init(name: name, components: components.map(component))
    }
}

/// Opaque pre-lowering evidence for an authored `Algorithm`.
///
/// The token deliberately exposes neither the Algorithm IR nor a lowered
/// `TLASpec`. It is retained solely to make parser/builder fidelity checks
/// observe source-level distinctions that lowering can erase.
public struct AlgorithmFidelityToken: Sendable, Hashable {
    let canonicalForm: String

    internal init(model: AlgorithmModel) {
        canonicalForm = algorithmCanonicalEncoding(model)
    }

    var encodedCanonicalForm: String {
        Data(canonicalForm.utf8).base64EncodedString()
    }
}

private func algorithmCanonicalEncoding(_ model: AlgorithmModel) -> String {
    var next = 0
    var nodes: [(path: String, value: String)] = []
    func record(_ path: String, _ value: String) -> String {
        nodes.append((path, value))
        return value
    }
    func state(_ expression: StateExpr, _ environment: [String: String]) -> String {
        stateKey(expression, environment: environment, next: &next)
    }
    func lvalue(_ value: AlgorithmLValueModel, _ environment: [String: String]) -> String {
        switch value {
        case .root(let name): return "root(\(environment[name] ?? name))"
        case .function(let root, let key):
            return "function(\(environment[root] ?? root),\(state(key, environment)))"
        }
    }
    func statements(_ values: [AlgorithmStatementModel], _ environment: [String: String], path: String) -> String {
        values.enumerated().map { index, value in
            statement(value, environment, path: "\(path)[\(index)]")
        }.joined(separator: ",")
    }
    func statement(_ value: AlgorithmStatementModel, _ environment: [String: String], path: String) -> String {
        let result: String
        switch value {
        case .rejected(let diagnostic): result = "rejected(\(diagnostic.rawValue))"
        case .await(let expression): result = "await(\(state(expression, environment)))"
        case .assert(let expression): result = "assert(\(state(expression, environment)))"
        case .set(let target, let expression): result = "set(\(lvalue(target, environment)),\(state(expression, environment)))"
        case .letBinding(let variable, let expression, let body):
            let value = state(expression, environment)
            let (name, extended) = fresh(variable, environment: environment, next: &next)
            result = "let(\(name),\(value),[\(statements(body, extended, path: "\(path).statements"))])"
        case .with(let variable, let source, let body):
            let sourceKey = state(source, environment)
            let (name, extended) = fresh(variable, environment: environment, next: &next)
            result = "with(\(name),\(sourceKey),[\(statements(body, extended, path: "\(path).statements"))])"
        case .ifElse(let condition, let then, let otherwise):
            result = "if(\(state(condition, environment)),[\(statements(then, environment, path: "\(path).then") )],[\(statements(otherwise, environment, path: "\(path).else") )])"
        case .either(let first, let second):
            result = "either([\(statements(first, environment, path: "\(path).first") )],[\(statements(second, environment, path: "\(path).second") )])"
        case .choose(let variable, let domain, let body):
            let (name, extended) = fresh(variable, environment: environment, next: &next)
            result = "choose(\(name),[\(domain.map(\.description).joined(separator: ","))],[\(statements(body, extended, path: "\(path).statements"))])"
        case .goto(let label): result = "goto(\(label.name))"
        case .call(let target, let arguments): result = "call(\(target),[\(arguments.map { state($0, environment) }.joined(separator: ","))])"
        case .return: result = "return"
        case .stop: result = "stop"
        case .skip: result = "skip"
        }
        return record(path, result)
    }
    func component(_ value: AlgorithmComponentModel, _ environment: [String: String], path: String) -> String {
        let result: String
        switch value {
        case .shared(let declaration):
            result = "shared(\(declaration.root),\(state(declaration.initial, environment)),\(declaration.initialSet.map { state($0, environment) } ?? "nil"))"
        case .local(let declaration):
            result = "local(\(declaration.root),\(state(declaration.initial, environment)),\(declaration.initialSet.map { state($0, environment) } ?? "nil"))"
        case .step(let step):
            result = "step(\(step.label.name),\(step.loopCondition.map { state($0, environment) } ?? "nil"),[\(statements(step.statements, environment, path: "\(path).statements"))])"
        case .process(let process):
            let components = process.components.enumerated().map { index, child in
                component(child, environment, path: "\(path).components[\(index)]")
            }.joined(separator: ",")
            result = "process(\(process.typeName),[\(process.domain.map(\.description).joined(separator: ","))],\(process.fairness),[\(components)])"
        case .procedure(let procedure):
            var procedureEnvironment = environment
            let parameters = procedure.parameters.map { parameter -> String in
                let initial = state(parameter.initial, procedureEnvironment)
                let (name, extended) = fresh(parameter.root, environment: procedureEnvironment, next: &next)
                procedureEnvironment = extended
                return "parameter(\(name),\(initial))"
            }
            let locals = procedure.locals.enumerated().map { index, local in
                component(.local(local), procedureEnvironment, path: "\(path).locals[\(index)]")
            }.joined(separator: ",")
            let steps = procedure.steps.enumerated().map { index, step in
                component(.step(step), procedureEnvironment, path: "\(path).steps[\(index)]")
            }.joined(separator: ",")
            result = "procedure(\(procedure.name),[\(parameters.joined(separator: ","))],[\(locals)],[\(steps)])"
        case .invariant(let invariant): result = "invariant(\(invariant.name),\(state(invariant.body, environment)))"
        case .temporal(let temporal): result = "temporal(\(temporal.name),\(temporal.expr))"
        case .fairness(let fairness): result = "fairness(\(fairness))"
        case .formalOperator(let definition):
            var definitionEnvironment = environment
            let parameters = definition.parameters.map { parameter -> String in
                let (name, extended) = fresh(parameter.name, environment: definitionEnvironment, next: &next)
                definitionEnvironment = extended
                switch parameter {
                case .value: return "value(\(name))"
                case .operator(_, let arity): return "operator(\(name),\(arity))"
                }
            }
            result = "formalOperator(\(definition.name),[\(parameters.joined(separator: ","))],\(state(definition.body, definitionEnvironment)))"
        case .stateConstraint(let expression): result = "constraint(\(state(expression, environment)))"
        case .propertyBoundary: result = "propertyBoundary"
        }
        return record(path, result)
    }
    let components = model.components.enumerated().map { index, child in
        component(child, [:], path: "components[\(index)]")
    }.joined(separator: ",")
    _ = record("algorithm", "algorithm(\(model.name),[\(components)])")
    return nodes.map { "\($0.path)\u{1F}\($0.value)" }.joined(separator: "\u{1E}")
}

internal indirect enum AlgorithmComponentModel: Sendable {
    case shared(AlgorithmStateModel)
    case process(AlgorithmProcessModel)
    case procedure(AlgorithmProcedureModel)
    case invariant(NamedInvariant)
    case temporal(NamedTemporal)
    case fairness(FairnessCondition)
    case formalOperator(FormalOperatorDefinition)
    /// A TLC state-space bound declared beside the algorithm that it bounds.
    /// It is not a correctness property: excluded states are not explored.
    case stateConstraint(StateExpr)
    case local(AlgorithmStateModel)
    case step(AlgorithmStepModel)
    case propertyBoundary
}

/// One formal PlusCal procedure. The public builder does not expose this
/// internal representation until its parser twin is available.
internal struct AlgorithmProcedureModel: Sendable {
    let name: String
    let parameters: [AlgorithmProcedureParameterModel]
    let locals: [AlgorithmStateModel]
    let steps: [AlgorithmStepModel]
}

internal struct AlgorithmProcedureParameterModel: Sendable {
    let root: String
    let initial: StateExpr
    let swiftTypeName: String?
}

internal struct AlgorithmProcessModel: Sendable {
    let typeName: String
    let domain: [TLAValue]
    let fairness: AlgorithmFairness
    let components: [AlgorithmComponentModel]

    var steps: [AlgorithmStepModel] {
        components.compactMap {
            guard case .step(let step) = $0 else { return nil }
            return step
        }
    }
}

internal enum AlgorithmFairness: Sendable {
    case none
    case weak
    case strong
}

internal struct AlgorithmStateModel: Sendable {
    let root: String
    let initial: StateExpr
    let initialSet: StateExpr?
    let swiftTypeName: String?
    let isTuple: Bool

    init(
        root: String,
        initial: StateExpr,
        initialSet: StateExpr? = nil,
        swiftTypeName: String? = nil,
        isTuple: Bool = false
    ) {
        self.root = root
        self.initial = initial
        self.initialSet = initialSet
        self.swiftTypeName = swiftTypeName
        self.isTuple = isTuple
    }
}

internal struct AlgorithmStepModel: Sendable {
    let label: AlgorithmLabelModel
    let statements: [AlgorithmStatementModel]
    /// A labeled PlusCal `while` loop. A true condition returns to `label`; a
    /// false condition advances to the following step.
    let loopCondition: StateExpr?

    init(label: AlgorithmLabelModel, statements: [AlgorithmStatementModel], loopCondition: StateExpr? = nil) {
        self.label = label
        self.statements = statements
        self.loopCondition = loopCondition
    }
}

internal struct AlgorithmLabelModel: Sendable, Hashable {
    let name: String
}

internal enum AlgorithmLValueModel: Sendable {
    case root(String)
    case function(root: String, key: StateExpr)

    var root: String {
        switch self {
        case .root(let root), .function(let root, _):
            return root
        }
    }
}

internal indirect enum AlgorithmStatementModel: Sendable {
    case rejected(AlgorithmDiagnosticCode)
    case await(StateExpr)
    case assert(StateExpr)
    case set(target: AlgorithmLValueModel, value: StateExpr)
    case letBinding(variable: String, value: StateExpr, [AlgorithmStatementModel])
    case with(variable: String, source: StateExpr, [AlgorithmStatementModel])
    case ifElse(StateExpr, [AlgorithmStatementModel], [AlgorithmStatementModel])
    case either([AlgorithmStatementModel], [AlgorithmStatementModel])
    case choose(variable: String, domain: [TLAValue], [AlgorithmStatementModel])
    case goto(AlgorithmLabelModel)
    case call(target: String, arguments: [StateExpr])
    case `return`
    case stop
    case skip
}
