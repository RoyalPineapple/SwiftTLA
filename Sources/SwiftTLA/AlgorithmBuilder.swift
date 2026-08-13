// swiftlint:disable identifier_name

public protocol PlusCalLabel: Hashable, Sendable {}

public struct FiniteDomain<Value: FiniteDomainKey>: Sendable {
    fileprivate let values: [Value]

    public init() {
        values = Value.formalDomain
    }

    public var members: [Value] {
        values
    }
}

extension FiniteDomainKey {
    public static var all: FiniteDomain<Self> {
        FiniteDomain()
    }
}

public struct ProcessIdentifier<Value: FiniteDomainKey>: StateExprConvertible, Sendable {
    fileprivate let expression: StateExpr

    public var stateExpr: StateExpr {
        expression
    }
}

public struct AlgorithmLValue<Value: TLAValueType>: Sendable {
    fileprivate let model: AlgorithmLValueModel
}

extension Var {
    public var algorithmLValue: AlgorithmLValue<T> {
        AlgorithmLValue(model: .root(name))
    }
}

extension DictionaryVar {
    public func algorithmLValue(_ member: DictMember<K>) -> AlgorithmLValue<V> {
        AlgorithmLValue(model: .function(root: name, key: member.key))
    }
}

public struct AlgorithmElement: Sendable {
    fileprivate let model: AlgorithmComponentModel
}

public struct StepStatement: Sendable {
    fileprivate let model: AlgorithmStatementModel
}

@resultBuilder
public enum AlgorithmBuilder {
    public static func buildBlock(_ components: [AlgorithmElement]...) -> [AlgorithmElement] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [AlgorithmElement]?) -> [AlgorithmElement] {
        component ?? []
    }

    public static func buildEither(first component: [AlgorithmElement]) -> [AlgorithmElement] {
        component
    }

    public static func buildEither(second component: [AlgorithmElement]) -> [AlgorithmElement] {
        component
    }

    public static func buildArray(_ components: [[AlgorithmElement]]) -> [AlgorithmElement] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ component: AlgorithmElement) -> [AlgorithmElement] {
        [component]
    }

    public static func buildExpression(_ component: InvDecl) -> [AlgorithmElement] {
        [AlgorithmElement(model: .propertyBoundary)]
    }

    public static func buildExpression(_ component: TemporalDecl) -> [AlgorithmElement] {
        [AlgorithmElement(model: .propertyBoundary)]
    }

    public static func buildExpression(_ component: FairnessDecl) -> [AlgorithmElement] {
        [AlgorithmElement(model: .propertyBoundary)]
    }

    public static func buildExpression(_ component: AssumeDecl) -> [AlgorithmElement] {
        [AlgorithmElement(model: .propertyBoundary)]
    }

    public static func buildExpression(_ component: DefinitionDecl) -> [AlgorithmElement] {
        [AlgorithmElement(model: .propertyBoundary)]
    }

    public static func buildExpression(_ component: TheoremDecl) -> [AlgorithmElement] {
        [AlgorithmElement(model: .propertyBoundary)]
    }

    public static func buildExpression(_ component: ConstraintDecl) -> [AlgorithmElement] {
        [AlgorithmElement(model: .propertyBoundary)]
    }
}

@resultBuilder
public enum StepBuilder {
    public static func buildBlock(_ statements: [StepStatement]...) -> [StepStatement] {
        statements.flatMap { $0 }
    }

    public static func buildOptional(_ component: [StepStatement]?) -> [StepStatement] {
        component ?? []
    }

    public static func buildEither(first component: [StepStatement]) -> [StepStatement] {
        component
    }

    public static func buildEither(second component: [StepStatement]) -> [StepStatement] {
        component
    }

    public static func buildArray(_ components: [[StepStatement]]) -> [StepStatement] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ statement: StepStatement) -> [StepStatement] {
        [statement]
    }
}

public struct Algorithm: Sendable, SpecComponent {
    internal let model: AlgorithmModel

    public init(_ name: String, @AlgorithmBuilder _ body: () -> [AlgorithmElement]) {
        model = AlgorithmModel(name: name, components: body().map(\.model))
    }

    public func validate() -> [AlgorithmDiagnostic] {
        AlgorithmValidator.validate(model)
    }

    @discardableResult
    public func requireValid() throws -> Algorithm {
        let diagnostics = validate()
        guard diagnostics.isEmpty else {
            throw AlgorithmValidationError(diagnostics)
        }
        return self
    }
}

public func Shared<Value: TLAValueType>(_ variable: Var<Value>, initial: Value) -> AlgorithmElement {
    AlgorithmElement(model: .shared(AlgorithmStateModel(root: variable.name, initial: initial.tlaValue)))
}

public func Local<Value: TLAValueType>(_ variable: Var<Value>, initial: Value) -> AlgorithmElement {
    AlgorithmElement(model: .local(AlgorithmStateModel(root: variable.name, initial: initial.tlaValue)))
}

public func Process<Value: FiniteDomainKey>(
    _ domain: FiniteDomain<Value>,
    @AlgorithmBuilder _ body: (ProcessIdentifier<Value>) -> [AlgorithmElement]
) -> AlgorithmElement {
    let identifier = ProcessIdentifier<Value>(expression: .variable("__pcal_self"))
    return AlgorithmElement(
        model: .process(
            AlgorithmProcessModel(
                typeName: String(reflecting: Value.self),
                domain: domain.values.map(\.tlaValue),
                components: body(identifier).map(\.model)
            )
        )
    )
}

/// Defines one labeled atomic region of a PlusCal algorithm.
///
/// All statements in the body read the same pre-state and produce one
/// transition. The label is the program-counter destination for `Goto`.
public func Do<Name: PlusCalLabel & RawRepresentable>(
    _ label: Name,
    @StepBuilder _ body: () -> [StepStatement]
) -> AlgorithmElement where Name.RawValue == String {
    AlgorithmElement(model: .step(AlgorithmStepModel(label: AlgorithmLabelModel(name: label.rawValue), statements: body().map(\.model))))
}

public func Await(_ condition: some StateExprConvertible) -> StepStatement {
    StepStatement(model: .await(condition.stateExpr))
}

public func Assign<Value: TLAValueType>(
    _ target: AlgorithmLValue<Value>,
    to value: some StateExprConvertible
) -> StepStatement {
    StepStatement(model: .set(target: target.model, value: value.stateExpr))
}

public func Assign<Value: TLAValueType>(
    _ variable: Var<Value>,
    to value: some StateExprConvertible
) -> StepStatement {
    Assign(variable.algorithmLValue, to: value)
}

public func If(
    _ condition: some StateExprConvertible,
    @StepBuilder _ then: () -> [StepStatement],
    @StepBuilder else otherwise: @escaping () -> [StepStatement] = { [] }
) -> StepStatement {
    StepStatement(model: .ifElse(condition.stateExpr, then().map(\.model), otherwise().map(\.model)))
}

public func Either(
    @StepBuilder _ first: () -> [StepStatement],
    @StepBuilder or second: @escaping () -> [StepStatement]
) -> StepStatement {
    StepStatement(model: .either(first().map(\.model), second().map(\.model)))
}

public func Choose<Value: FiniteDomainKey>(
    _ domain: FiniteDomain<Value>,
    @StepBuilder _ body: (ProcessIdentifier<Value>) -> [StepStatement]
) -> StepStatement {
    let name = "__pcal_choice"
    let value = ProcessIdentifier<Value>(expression: .variable(name))
    return StepStatement(model: .choose(variable: name, domain: domain.values.map(\.tlaValue), body(value).map(\.model)))
}

public func Goto<Label: PlusCalLabel & RawRepresentable>(_ label: Label) -> StepStatement where Label.RawValue == String {
    StepStatement(model: .goto(AlgorithmLabelModel(name: label.rawValue)))
}

public func Stop() -> StepStatement {
    StepStatement(model: .stop)
}

internal enum AlgorithmValidator {
    static func validate(_ model: AlgorithmModel) -> [AlgorithmDiagnostic] {
        var diagnostics: [AlgorithmDiagnostic] = []
        validateName(model.name, at: .algorithm, diagnostics: &diagnostics)

        for (index, component) in model.components.enumerated() {
            switch component {
            case .shared(let state):
                validateName(state.root, at: .algorithm, diagnostics: &diagnostics)
            case .process(let process):
                validate(process, index: index, diagnostics: &diagnostics)
            case .propertyBoundary:
                diagnostics.append(AlgorithmDiagnostic(.propertyBoundary, at: .algorithm))
            case .local, .step:
                diagnostics.append(AlgorithmDiagnostic(.invalidAlgorithmComponent, at: .algorithm))
            }
        }
        return diagnostics
    }

    private static func validate(
        _ process: AlgorithmProcessModel,
        index: Int,
        diagnostics: inout [AlgorithmDiagnostic]
    ) {
        let processAnchor = AlgorithmDiagnosticAnchor.process(index)
        validateDomain(process.domain, at: processAnchor, diagnostics: &diagnostics)

        let steps = process.steps
        let labels = steps.map(\.label.name)
        for label in labels {
            validateName(label, at: processAnchor, diagnostics: &diagnostics)
        }
        if Set(labels).count != labels.count {
            diagnostics.append(AlgorithmDiagnostic(.duplicateLabel, at: processAnchor))
        }

        for component in process.components {
            switch component {
            case .local(let state):
                validateName(state.root, at: processAnchor, diagnostics: &diagnostics)
            case .step(let step):
                validate(step, process: index, labels: Set(labels), diagnostics: &diagnostics)
            case .propertyBoundary:
                diagnostics.append(AlgorithmDiagnostic(.propertyBoundary, at: processAnchor))
            case .shared, .process:
                diagnostics.append(AlgorithmDiagnostic(.invalidAlgorithmComponent, at: processAnchor))
            }
        }

        if !steps.contains(where: { containsStop($0.statements) }) {
            diagnostics.append(AlgorithmDiagnostic(.missingStop, at: processAnchor))
        }
    }

    private static func validate(
        _ step: AlgorithmStepModel,
        process: Int,
        labels: Set<String>,
        diagnostics: inout [AlgorithmDiagnostic]
    ) {
        let anchor = AlgorithmDiagnosticAnchor.step(process: process, label: step.label.name)
        let paths = writePaths(step.statements)
        if paths.contains(where: { Set($0).count != $0.count }) {
            diagnostics.append(AlgorithmDiagnostic(.duplicateRootWrite, at: anchor))
        }
        validateStatements(step.statements, at: anchor, labels: labels, diagnostics: &diagnostics)
    }

    private static func validateStatements(
        _ statements: [AlgorithmStatementModel],
        at anchor: AlgorithmDiagnosticAnchor,
        labels: Set<String>,
        diagnostics: inout [AlgorithmDiagnostic]
    ) {
        for statement in statements {
            switch statement {
            case .await:
                break
            case .set(let target, _):
                validateName(target.root, at: anchor, diagnostics: &diagnostics)
            case .ifElse(_, let then, let otherwise), .either(let then, let otherwise):
                validateStatements(then, at: anchor, labels: labels, diagnostics: &diagnostics)
                validateStatements(otherwise, at: anchor, labels: labels, diagnostics: &diagnostics)
            case .choose(_, let domain, let body):
                validateDomain(domain, at: anchor, diagnostics: &diagnostics)
                validateStatements(body, at: anchor, labels: labels, diagnostics: &diagnostics)
            case .goto(let label):
                if !labels.contains(label.name) {
                    diagnostics.append(AlgorithmDiagnostic(.invalidTarget, at: anchor))
                }
            case .stop:
                break
            }
        }
    }

    private static func writePaths(_ statements: [AlgorithmStatementModel]) -> [[String]] {
        statements.reduce(into: [[]]) { paths, statement in
            let statementPaths: [[String]]
            switch statement {
            case .set(let target, _):
                statementPaths = [[target.root]]
            case .ifElse(_, let then, let otherwise), .either(let then, let otherwise):
                statementPaths = writePaths(then) + writePaths(otherwise)
            case .choose(_, _, let body):
                statementPaths = writePaths(body)
            case .await, .goto, .stop:
                statementPaths = [[]]
            }
            paths = paths.flatMap { path in statementPaths.map { path + $0 } }
        }
    }

    private static func containsStop(_ statements: [AlgorithmStatementModel]) -> Bool {
        statements.contains {
            switch $0 {
            case .stop:
                return true
            case .ifElse(_, let then, let otherwise), .either(let then, let otherwise):
                return containsStop(then) || containsStop(otherwise)
            case .choose(_, _, let body):
                return containsStop(body)
            case .await, .set, .goto:
                return false
            }
        }
    }

    private static func validateDomain(
        _ domain: [TLAValue],
        at anchor: AlgorithmDiagnosticAnchor,
        diagnostics: inout [AlgorithmDiagnostic]
    ) {
        if domain.isEmpty {
            diagnostics.append(AlgorithmDiagnostic(.emptyDomain, at: anchor))
        } else if Set(domain).count != domain.count {
            diagnostics.append(AlgorithmDiagnostic(.duplicateDomainMember, at: anchor))
        }
    }

    private static func validateName(
        _ name: String,
        at anchor: AlgorithmDiagnosticAnchor,
        diagnostics: inout [AlgorithmDiagnostic]
    ) {
        if name.hasPrefix("__pcal_") {
            diagnostics.append(AlgorithmDiagnostic(.reservedName, at: anchor))
        } else if name.isEmpty || name.contains(where: { !$0.isLetter && !$0.isNumber && $0 != "_" }) {
            diagnostics.append(AlgorithmDiagnostic(.invalidName, at: anchor))
        }
    }
}
