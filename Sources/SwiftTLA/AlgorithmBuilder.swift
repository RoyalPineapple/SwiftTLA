// swiftlint:disable identifier_name

public struct FiniteDomain<Value: FiniteTLAValueDomain>: TypedExpression {
    public typealias ExpressionValue = SetExpr<Value>
    fileprivate let values: [Value]

    public init() {
        values = Value.finiteValues
    }

    public init(_ values: [Value]) {
        self.values = values
    }

    public var stateExpr: StateExpr {
        if let issue = Value.sourceIssue { return .sourceIssue(issue) }
        return .setLiteral(values.map(\.stateExpr))
    }

    public var expr: Expr<SetExpr<Value>> { Expr(stateExpr) }

    public var members: [Value] {
        values
    }
}

extension FiniteDomain: Sequence {
    public func makeIterator() -> Array<Value>.Iterator {
        values.makeIterator()
    }
}

extension FiniteTLAValueDomain {
    public static var all: FiniteDomain<Self> {
        FiniteDomain()
    }
}

extension FiniteDomain {
    /// The declared members before the current process member.
    ///
    /// The declaration order is the formal order. This gives an ordered
    /// process algorithm an explicit, finite set whose elements retain typed
    /// formal values.
    public func members(before current: some TypedExpression<Value>) -> Expr<SetExpr<Value>> {
        var preceding = Expr<SetExpr<Value>>(.setLiteral([]))
        for (index, candidate) in values.enumerated().reversed() {
            let earlier = Expr<SetExpr<Value>>(
                .setLiteral(values.prefix(index).map { .value($0.tlaValue) })
            )
            preceding = If(
                current == candidate,
                then: earlier,
                else: preceding
            )
        }
        return preceding
    }
}

public struct ProcessIdentifier<Value: FiniteTLAValueDomain>: TypedExpression {
    fileprivate let expression: StateExpr

    public var stateExpr: StateExpr {
        expression
    }

    /// The current process identifier as a typed formal expression.
    public var expr: Expr<Value> {
        Expr(expression)
    }

}

/// A value bound for one atomic `With` body.
///
/// It carries a scoped formal action binding while the algorithm IR is built.
public struct WithValue<Value: TLAValueType>: TypedExpression {
    let expression: StateExpr

    public var stateExpr: StateExpr { expression }

    public var expr: Expr<Value> { Expr(expression) }

}

extension Function where Domain: FiniteTLAValueDomain {
    /// Builds a total finite formal function from a concrete typed value.
    public static func mapping(
        file: StaticString = #fileID, line: UInt = #line, column: UInt = #column,
        _ body: (WithValue<Domain>) -> Range
    ) -> Expr<Self> {
        mapping(file: file, line: line, column: column) { key in Expr(body(key)) }
    }

    /// Builds a total finite formal function from an expression over each key.
    ///
    /// This is useful for dependent initial state: the body may read an
    /// earlier shared variable. Its executable meaning is the returned typed
    /// expression.
    public static func mapping<Result: TypedExpression<Range>>(
        file: StaticString = #fileID, line: UInt = #line, column: UInt = #column,
        _ body: (WithValue<Domain>) -> Result
    ) -> Expr<Self> {
        let binding = generatedBinderName(file: file, line: line, column: column)
        let key = WithValue<Domain>(expression: .variable(binding))
        return Expr<Self>(.functionLiteral(
            .setLiteral(Domain.tlaValues.map(StateExpr.value)),
            binding,
            body(key).stateExpr
        ))
    }
}

public struct AlgorithmLValue<Value: TLAValueType>: Sendable {
    fileprivate let model: AlgorithmLValueModel
}

/// One formal parameter in a bounded PlusCal statement macro.
///
/// Its body is substituted into the surrounding `Do` block before the
/// algorithm lowers.
public struct MacroParameter<Value: TLAValueType>: TypedExpression {
    fileprivate let name: String

    public var stateExpr: StateExpr { .variable(name) }
    public var expr: Expr<Value> { Expr(stateExpr) }

    public var algorithmLValue: AlgorithmLValue<Value> {
        AlgorithmLValue(model: .root(name))
    }
}

/// A typed formal input of a PlusCal procedure.
public struct ProcedureParameter<Value: TLAValueType>: TypedExpression {
    fileprivate let name: String
    public var stateExpr: StateExpr { .variable(name) }
    public var expr: Expr<Value> { Expr(stateExpr) }
    public var algorithmLValue: AlgorithmLValue<Value> { AlgorithmLValue(model: .root(name)) }
}

/// A PlusCal statement macro.
///
/// Declare it inside `Algorithm`, then call it inside a `Do` body. The macro
/// expands to formal statements in the same atomic step.
public struct StatementMacro<Arguments: Sendable>: Sendable {
    private let parameterNames: [String]
    private let statements: [AlgorithmStatementModel]

    fileprivate init(parameterNames: [String], statements: [AlgorithmStatementModel]) {
        self.parameterNames = parameterNames
        self.statements = statements
    }

    public func callAsFunction() -> [StepStatement] where Arguments == Void {
        expand([])
    }

    /// Arguments retain the declaration's types through substitution.
    /// Assigned parameters still require variable expressions.
    public func callAsFunction(_ argument: some TypedExpression<Arguments>) -> [StepStatement]
    where Arguments: TLAValueType {
        expand([argument.stateExpr])
    }

    public func callAsFunction<First: TLAValueType, Second: TLAValueType>(
        _ first: some TypedExpression<First>, _ second: some TypedExpression<Second>
    ) -> [StepStatement] where Arguments == (First, Second) {
        expand([first.stateExpr, second.stateExpr])
    }

    private func expand(_ arguments: [StateExpr]) -> [StepStatement] {
        let arguments = Dictionary(uniqueKeysWithValues: zip(parameterNames, arguments))
        return statements.map {
            StepStatement(model: $0.substitutingVariables(arguments, assignmentTargets: .reject(.statementMacroAssignmentTarget)))
        }
    }
}

/// Declares a one-argument PlusCal statement macro.
public func Macro<Value: TLAValueType>(
    @DoBuilder _ body: (MacroParameter<Value>) -> [StepStatement]
) -> StatementMacro<Value> {
    let parameterName = "__pcal_macro_parameter"
    return StatementMacro(
        parameterNames: [parameterName],
        statements: body(MacroParameter(name: parameterName)).map(\.model)
    )
}

/// Declares a two-argument PlusCal statement macro. Both parameters remain
/// formal handles until expansion inside the caller's atomic `Do` block.
public func Macro<First: TLAValueType, Second: TLAValueType>(
    @DoBuilder _ body: (MacroParameter<First>, MacroParameter<Second>) -> [StepStatement]
) -> StatementMacro<(First, Second)> {
    let firstName = "__pcal_macro_parameter_0"
    let secondName = "__pcal_macro_parameter_1"
    return StatementMacro(
        parameterNames: [firstName, secondName],
        statements: body(MacroParameter(name: firstName), MacroParameter(name: secondName)).map(\.model)
    )
}

/// Declares a parameterless PlusCal statement macro.
public func Macro(@DoBuilder _ body: () -> [StepStatement]) -> StatementMacro<Void> {
    StatementMacro(parameterNames: [], statements: body().map(\.model))
}

/// A typed shared variable declaration.
///
/// Declare it through the scope supplied by `TLASpec` or `Algorithm`.
public struct SharedVariable<Value: TLAValueType>: TypedExpression {
    fileprivate let name: String
    fileprivate let initialization: VariableInitialization

    fileprivate init(name: String, initialization: VariableInitialization) {
        self.name = name
        self.initialization = initialization
    }

    fileprivate init(name: String, initial: Value) {
        self.init(
            name: name,
            initialization: .value(initial.tlaValue)
        )
    }

    fileprivate init(name: String, in values: some TypedExpression<SetExpr<Value>>) {
        self.init(
            name: name,
            initialization: .memberOf(values.stateExpr)
        )
    }

    fileprivate init(name: String, initial: some TypedExpression<Value>) {
        self.init(
            name: name,
            initialization: .expression(initial.stateExpr)
        )
    }

    public var stateExpr: StateExpr { .variable(name) }

    /// The typed expression for the current formal value.
    public var expr: Expr<Value> { Expr(stateExpr) }

    public var algorithmLValue: AlgorithmLValue<Value> {
        AlgorithmLValue(model: .root(name))
    }

    @discardableResult
    public func becomes(_ value: Value) -> ActionExpr {
        .assign(.named(name), .value(value.tlaValue))
    }

    @discardableResult
    public func becomes(_ value: some TypedExpression<Value>) -> ActionExpr {
        .assign(.named(name), value.stateExpr)
    }

    public var stays: ActionExpr { .unchanged(.named(name)) }
}

/// A typed process-local algorithm variable.
///
/// Declare it through the scope supplied by `Each` or `Procedure`.
public struct LocalVariable<Value: TLAValueType>: TypedExpression {
    fileprivate let name: String
    fileprivate let initialization: VariableInitialization

    fileprivate init(name: String, initialization: VariableInitialization) {
        self.name = name
        self.initialization = initialization
    }

    fileprivate init(name: String, initial: Value) {
        self.init(
            name: name,
            initialization: .value(initial.tlaValue)
        )
    }

    fileprivate init(name: String, initial: some TypedExpression<Value>) {
        self.init(
            name: name,
            initialization: .expression(initial.stateExpr)
        )
    }

    public var stateExpr: StateExpr { .variable(name) }

    /// The typed expression for the current process-local formal value.
    public var expr: Expr<Value> { Expr(stateExpr) }

    /// Views this process-local declaration as the total function over its
    /// process family for properties such as `Range(ops)`.
    public func family<Process: FiniteTLAValueDomain>(
        for _: Process.Type
    ) -> Expr<Function<Process, Value>> {
        Expr(.processLocalFamily(name))
    }

    public var algorithmLValue: AlgorithmLValue<Value> {
        AlgorithmLValue(model: .root(name))
    }

    @discardableResult
    public func becomes(_ value: Value) -> ActionExpr {
        .assign(.named(name), .value(value.tlaValue))
    }

    @discardableResult
    public func becomes(_ value: some TypedExpression<Value>) -> ActionExpr {
        .assign(.named(name), value.stateExpr)
    }

    public var stays: ActionExpr { .unchanged(.named(name)) }
}

/// Scheduling policy for one `Each` process family.
///
/// `.weak` is the PlusCal `fair process` spelling. The lowerer applies it to
/// every generated atomic action for every concrete process identifier.
public enum ProcessFairness: Sendable {
    case none
    case weak
    case strong

    fileprivate var model: AlgorithmFairness {
        switch self {
        case .none: .none
        case .weak: .weak
        case .strong: .strong
        }
    }
}

/// Scheduling policy for a sequential `Algorithm` body.
///
/// `.weak` preserves scalar control state and lowers to `WF(Next)`.
public enum SequentialAlgorithmFairness: Sendable, Equatable {
    case none
    case weak
}

extension Var {
    public var algorithmLValue: AlgorithmLValue<T> {
        AlgorithmLValue(model: .root(name))
    }
}

public struct AlgorithmElement: Sendable {
    fileprivate let model: AlgorithmComponentModel
}

private extension SharedVariable {
    var algorithmElement: AlgorithmElement {
        AlgorithmElement(model: .shared(.init(
            root: name,
            initialization: initialization,
            swiftTypeName: swiftSurfaceTypeName(for: Value.self)
        )))
    }

    var specificationDeclaration: VarDecl {
        VarDecl(name, initialization: initialization, generatedSwiftType: swiftSurfaceTypeName(for: Value.self))
    }
}

public final class SpecificationScope {
    var declarations: [VarDecl] = []

    init() {}

    public func sharedVar<Value: TLAValueType>(
        _ name: String,
        initial: Value
    ) -> SharedVariable<Value> {
        let variable = SharedVariable(name: name, initial: initial)
        declarations.append(variable.specificationDeclaration)
        return variable
    }

    public func sharedVar(_ name: String, in range: ClosedRange<Int>) -> SharedVariable<Int> {
        let variable = SharedVariable<Int>(
            name: name,
            initialization: .memberOf(.setLiteral(range.map { .value(.int($0)) }))
        )
        declarations.append(variable.specificationDeclaration)
        return variable
    }

    public func sharedVar<Value: TLAValueType>(
        _ name: String,
        in values: some TypedExpression<SetExpr<Value>>
    ) -> SharedVariable<Value> {
        let variable = SharedVariable(name: name, in: values)
        declarations.append(variable.specificationDeclaration)
        return variable
    }

    public func sharedVar<Value: TLAValueType>(
        _ name: String,
        initial: some TypedExpression<Value>
    ) -> SharedVariable<Value> {
        let variable = SharedVariable(name: name, initial: initial)
        declarations.append(variable.specificationDeclaration)
        return variable
    }
}

public final class AlgorithmScope {
    fileprivate var declarations: [AlgorithmElement] = []

    init() {}

    public func sharedVar<Value: TLAValueType>(
        _ name: String,
        initial: Value
    ) -> SharedVariable<Value> {
        let variable = SharedVariable(name: name, initial: initial)
        declarations.append(variable.algorithmElement)
        return variable
    }

    public func sharedVar(_ name: String, in range: ClosedRange<Int>) -> SharedVariable<Int> {
        let variable = SharedVariable<Int>(
            name: name,
            initialization: .memberOf(.setLiteral(range.map { .value(.int($0)) }))
        )
        declarations.append(variable.algorithmElement)
        return variable
    }

    public func sharedVar<Value: TLAValueType>(
        _ name: String,
        in values: some TypedExpression<SetExpr<Value>>
    ) -> SharedVariable<Value> {
        let variable = SharedVariable(name: name, in: values)
        declarations.append(variable.algorithmElement)
        return variable
    }

    public func sharedVar<Value: TLAValueType>(
        _ name: String,
        initial: some TypedExpression<Value>
    ) -> SharedVariable<Value> {
        let variable = SharedVariable(name: name, initial: initial)
        declarations.append(variable.algorithmElement)
        return variable
    }
}

public final class ProcessScope {
    fileprivate var declarations: [AlgorithmElement] = []

    init() {}

    public func localVar<Value: TLAValueType>(
        _ name: String,
        initial: Value
    ) -> LocalVariable<Value> {
        let variable = LocalVariable(name: name, initial: initial)
        declarations.append(localDeclaration(variable))
        return variable
    }

    public func localVar<Value: TLAValueType>(_ name: String, initial: some TypedExpression<Value>) -> LocalVariable<Value> {
        let variable = LocalVariable(name: name, initial: initial)
        declarations.append(localDeclaration(variable))
        return variable
    }
}

public final class ProcedureScope {
    fileprivate var declarations: [AlgorithmElement] = []

    init() {}

    public func localVar<Value: TLAValueType>(
        _ name: String,
        initial: Value
    ) -> LocalVariable<Value> {
        let variable = LocalVariable(name: name, initial: initial)
        declarations.append(localDeclaration(variable))
        return variable
    }

    public func localVar<Value: TLAValueType>(_ name: String, initial: some TypedExpression<Value>) -> LocalVariable<Value> {
        let variable = LocalVariable(name: name, initial: initial)
        declarations.append(localDeclaration(variable))
        return variable
    }
}

private func localDeclaration<Value>(_ variable: LocalVariable<Value>) -> AlgorithmElement {
    AlgorithmElement(model: .local(.init(
        root: variable.name,
        initialization: variable.initialization,
        swiftTypeName: swiftSurfaceTypeName(for: Value.self)
    )))
}

public struct StepStatement: Sendable {
    fileprivate let model: AlgorithmStatementModel
}

@resultBuilder
public enum AlgorithmBuilder {
    public static func buildBlock(_ components: [AlgorithmElement]...) -> [AlgorithmElement] {
        components.flatMap { $0 }
    }

    public static func buildPartialBlock(first component: [AlgorithmElement]) -> [AlgorithmElement] {
        component
    }

    public static func buildPartialBlock(
        accumulated: [AlgorithmElement],
        next component: [AlgorithmElement]
    ) -> [AlgorithmElement] {
        accumulated + component
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
        [AlgorithmElement(model: .invariant(.init(name: component.name, body: component.body)))]
    }

    public static func buildExpression(_ component: TemporalDecl) -> [AlgorithmElement] {
        [AlgorithmElement(model: .temporal(.init(name: component.name, expr: component.expr)))]
    }

    public static func buildExpression(_ component: FairnessDecl) -> [AlgorithmElement] {
        [AlgorithmElement(model: .invalidPlacement(.genericFairness))]
    }

    public static func buildExpression(_ component: AssumeDecl) -> [AlgorithmElement] {
        [AlgorithmElement(model: .invalidPlacement(.assumption))]
    }

    public static func buildExpression(_ component: ConstraintDecl) -> [AlgorithmElement] {
        [AlgorithmElement(model: .stateConstraint(component.body))]
    }

    public static func buildExpression(_ component: FormalOperatorDecl) -> [AlgorithmElement] {
        [AlgorithmElement(model: .formalOperator(component.definition))]
    }
}

/// Bounds the states that TLC retains while it explores this algorithm.
///
/// Put this beside the algorithm state it refers to. It is deliberately named
/// differently from a correctness `Invariant`: a state constraint limits
/// exploration, while an invariant is checked in every retained state.
public func StateConstraint(_ expression: some TypedExpression<Bool>) -> AlgorithmElement {
    AlgorithmElement(model: .stateConstraint(expression.stateExpr))
}

@resultBuilder
public enum DoBuilder {
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

    public static func buildExpression(_ statements: [StepStatement]) -> [StepStatement] {
        statements
    }
}

public struct Algorithm: Sendable, SpecComponent {
    package let model: AlgorithmModel

    public init(
        _ name: String,
        fairness: SequentialAlgorithmFairness = .none,
        @AlgorithmBuilder _ body: () -> [AlgorithmElement]
    ) {
        model = AlgorithmModel(name: name, sequentialFairness: fairness, components: body().map(\.model))
    }

    public init(
        _ name: String,
        fairness: SequentialAlgorithmFairness = .none,
        @AlgorithmBuilder scoped body: (AlgorithmScope) -> [AlgorithmElement]
    ) {
        let scope = AlgorithmScope()
        let components = body(scope)
        model = AlgorithmModel(
            name: name,
            sequentialFairness: fairness,
            components: scope.declarations.map(\.model) + components.map(\.model)
        )
    }

    package init(model: AlgorithmModel) {
        self.model = model
    }

    package func validate() -> [AlgorithmDiagnostic] {
        AlgorithmValidator.validate(model)
    }

    @discardableResult
    package func requireValid() throws -> Algorithm {
        let diagnostics = validate()
        guard let diagnostic = diagnostics.first else { return self }
        throw diagnostic.compilationDiagnostic(algorithmName: model.name)
    }
}

/// Declares one independently scheduled process for every member of `domain`.
public func Each<Value: FiniteTLAValueDomain>(
    _ domain: FiniteDomain<Value>,
    fairness: ProcessFairness = .none,
    @AlgorithmBuilder _ body: (ProcessIdentifier<Value>) -> [AlgorithmElement]
) -> AlgorithmElement {
    process(domain, fairness: fairness.model, body)
}

public func Each<Value: FiniteTLAValueDomain>(
    _ domain: FiniteDomain<Value>,
    fairness: ProcessFairness = .none,
    @AlgorithmBuilder scoped body: (ProcessIdentifier<Value>, ProcessScope) -> [AlgorithmElement]
) -> AlgorithmElement {
    let scope = ProcessScope()
    let identifier = ProcessIdentifier<Value>(expression: .currentProcess)
    let components = body(identifier, scope)
    return AlgorithmElement(model: .process(.init(
        typeName: swiftSurfaceTypeName(for: Value.self),
        domain: domain.values.map(\.tlaValue),
        fairness: fairness.model,
        components: scope.declarations.map(\.model) + components.map(\.model)
    )))
}

private func process<Value: FiniteTLAValueDomain>(
    _ domain: FiniteDomain<Value>,
    fairness: AlgorithmFairness,
    @AlgorithmBuilder _ body: (ProcessIdentifier<Value>) -> [AlgorithmElement]
) -> AlgorithmElement {
    let identifier = ProcessIdentifier<Value>(expression: .currentProcess)
    return AlgorithmElement(
        model: .process(
            AlgorithmProcessModel(
                typeName: swiftSurfaceTypeName(for: Value.self),
                domain: domain.values.map(\.tlaValue),
                fairness: fairness,
                components: body(identifier).map(\.model)
            )
        )
    )
}

/// Defines one labeled atomic region of a PlusCal algorithm.
///
/// All statements in the body read the same pre-state and produce one
/// transition. The label is the program-counter destination for `Goto`.
public func Do<Name: CaseIterable & RawRepresentable & Sendable>(
    _ label: Name,
    @DoBuilder _ body: () -> [StepStatement]
) -> AlgorithmElement where Name.RawValue == String {
    AlgorithmElement(model: .step(AlgorithmStepModel(label: AlgorithmLabelModel(name: label.rawValue), statements: body().map(\.model))))
}

/// Defines a labeled bounded `while` loop.
///
/// Each execution of the body is one atomic transition. When `condition` is
/// false, control advances to the next `Do` or `While` block.
public func While<Name: CaseIterable & RawRepresentable & Sendable>(
    _ label: Name,
    _ condition: some TypedExpression<Bool>,
    @DoBuilder _ body: () -> [StepStatement]
) -> AlgorithmElement where Name.RawValue == String {
    AlgorithmElement(model: .step(AlgorithmStepModel(
        label: AlgorithmLabelModel(name: label.rawValue),
        statements: body().map(\.model),
        loopCondition: condition.stateExpr
    )))
}

public func Await(_ condition: some TypedExpression<Bool>) -> StepStatement {
    StepStatement(model: .await(condition.stateExpr))
}

/// PlusCal `when`: a guarded atomic step. `When` and `Await` have the same
/// transition semantics; the different spelling is author intent only.
public func When(_ condition: some TypedExpression<Bool>) -> StepStatement {
    Await(condition)
}

/// A PlusCal assertion. A false assertion creates a compiled safety
/// check at this atomic program-counter location.
public func Assert(_ condition: some TypedExpression<Bool>) -> StepStatement {
    StepStatement(model: .assert(condition.stateExpr))
}

/// Invokes a declared PlusCal procedure from a sequential algorithm step.
/// Arguments are formal expressions evaluated in the caller's pre-state.
public func Call<Name: CaseIterable & RawRepresentable & Sendable>(
    _ target: Name,
    with arguments: (any StateExprConvertible)...
) -> StepStatement where Name.RawValue == String {
    StepStatement(model: .call(target: target.rawValue, arguments: arguments.map(\.stateExpr)))
}

/// Returns from the enclosing PlusCal procedure.
public func Return() -> StepStatement {
    StepStatement(model: .return)
}

public func Procedure<Name: CaseIterable & RawRepresentable & Sendable>(
    _ name: Name,
    @AlgorithmBuilder _ body: () -> [AlgorithmElement]
) -> AlgorithmElement where Name.RawValue == String {
    procedure(name: name.rawValue, parameters: [], components: body())
}

public func Procedure<Name: CaseIterable & RawRepresentable & Sendable, Value: TLAValueType>(
    _ name: Name,
    parameters: Value.Type,
    @AlgorithmBuilder _ body: (ProcedureParameter<Value>) -> [AlgorithmElement]
) -> AlgorithmElement where Name.RawValue == String {
    let parameterName = "parameter0"
    return procedure(
        name: name.rawValue,
        parameters: [.init(root: parameterName, initial: .value(Value.defaultValue.tlaValue), swiftTypeName: swiftSurfaceTypeName(for: Value.self))],
        components: body(ProcedureParameter(name: parameterName))
    )
}

public func Procedure<Name: CaseIterable & RawRepresentable & Sendable, Value: TLAValueType>(
    _ name: Name,
    parameters: Value.Type,
    @AlgorithmBuilder scoped body: (ProcedureParameter<Value>, ProcedureScope) -> [AlgorithmElement]
) -> AlgorithmElement where Name.RawValue == String {
    let parameterName = "parameter0"
    let scope = ProcedureScope()
    let body = body(ProcedureParameter(name: parameterName), scope)
    return procedure(
        name: name.rawValue,
        parameters: [.init(root: parameterName, initial: .value(Value.defaultValue.tlaValue), swiftTypeName: swiftSurfaceTypeName(for: Value.self))],
        components: scope.declarations + body
    )
}

private func procedure(
    name: String,
    parameters: [AlgorithmProcedureParameterModel],
    components: [AlgorithmElement]
) -> AlgorithmElement {
    let models = components.map(\.model)
    return AlgorithmElement(model: .procedure(.init(
        name: name,
        parameters: parameters,
        components: models
    )))
}

public func Procedure<Name: CaseIterable & RawRepresentable & Sendable, First: TLAValueType, Second: TLAValueType>(
    _ name: Name, parameters: First.Type, _ second: Second.Type,
    @AlgorithmBuilder _ body: (ProcedureParameter<First>, ProcedureParameter<Second>) -> [AlgorithmElement]
) -> AlgorithmElement where Name.RawValue == String {
    procedure(
        name: name.rawValue,
        parameters: [
            .init(root: "parameter0", initial: .value(First.defaultValue.tlaValue), swiftTypeName: swiftSurfaceTypeName(for: First.self)),
            .init(root: "parameter1", initial: .value(Second.defaultValue.tlaValue), swiftTypeName: swiftSurfaceTypeName(for: Second.self))
        ],
        components: body(.init(name: "parameter0"), .init(name: "parameter1"))
    )
}

public func Procedure<Name: CaseIterable & RawRepresentable & Sendable, A: TLAValueType, B: TLAValueType, C: TLAValueType>(
    _ name: Name, parameters: A.Type, _ b: B.Type, _ c: C.Type,
    @AlgorithmBuilder _ body: (ProcedureParameter<A>, ProcedureParameter<B>, ProcedureParameter<C>) -> [AlgorithmElement]
) -> AlgorithmElement where Name.RawValue == String {
    procedure(
        name: name.rawValue,
        parameters: [
            .init(root: "parameter0", initial: .value(A.defaultValue.tlaValue), swiftTypeName: swiftSurfaceTypeName(for: A.self)),
            .init(root: "parameter1", initial: .value(B.defaultValue.tlaValue), swiftTypeName: swiftSurfaceTypeName(for: B.self)),
            .init(root: "parameter2", initial: .value(C.defaultValue.tlaValue), swiftTypeName: swiftSurfaceTypeName(for: C.self))
        ],
        components: body(.init(name: "parameter0"), .init(name: "parameter1"), .init(name: "parameter2"))
    )
}

public func Procedure<Name: CaseIterable & RawRepresentable & Sendable, A: TLAValueType, B: TLAValueType, C: TLAValueType, D: TLAValueType>(
    _ name: Name, parameters: A.Type, _ b: B.Type, _ c: C.Type, _ d: D.Type,
    @AlgorithmBuilder _ body: (ProcedureParameter<A>, ProcedureParameter<B>, ProcedureParameter<C>, ProcedureParameter<D>) -> [AlgorithmElement]
) -> AlgorithmElement where Name.RawValue == String {
    procedure(
        name: name.rawValue,
        parameters: [
            .init(root: "parameter0", initial: .value(A.defaultValue.tlaValue), swiftTypeName: swiftSurfaceTypeName(for: A.self)),
            .init(root: "parameter1", initial: .value(B.defaultValue.tlaValue), swiftTypeName: swiftSurfaceTypeName(for: B.self)),
            .init(root: "parameter2", initial: .value(C.defaultValue.tlaValue), swiftTypeName: swiftSurfaceTypeName(for: C.self)),
            .init(root: "parameter3", initial: .value(D.defaultValue.tlaValue), swiftTypeName: swiftSurfaceTypeName(for: D.self))
        ],
        components: body(.init(name: "parameter0"), .init(name: "parameter1"), .init(name: "parameter2"), .init(name: "parameter3"))
    )
}

/// Binds a nondeterministically chosen member of a bounded formal set for one
/// atomic block. An empty set disables that block, as PlusCal `with (x \in S)`.
public func With<Value: TLAValueType>(
    _ source: some TypedExpression<SetExpr<Value>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    let variable = generatedBinderName(file: file, line: line, column: column)
    let value = WithValue<Value>(expression: .variable(variable))
    return StepStatement(model: .with(variable: variable, source: source.stateExpr, body(value).map(\.model)))
}

/// Binds two independent members for one atomic block.
///
/// This is the Swift spelling of PlusCal's `with (left \in Left; right \in Right)`.
/// It lowers to nested formal binders, so each choice remains independently
/// scoped and an empty source disables the whole block.
public func With<First: TLAValueType, Second: TLAValueType>(
    _ first: some TypedExpression<SetExpr<First>>,
    _ second: some TypedExpression<SetExpr<Second>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (WithValue<First>, WithValue<Second>) -> [StepStatement]
) -> StepStatement {
    With(first, file: file, line: line, column: column) { firstValue in
        With(second, file: file, line: line, column: column + 1) { secondValue in
            body(firstValue, secondValue)
        }
    }
}

/// Binds three independent members in formal left-to-right scope order.
public func With<First: TLAValueType, Second: TLAValueType, Third: TLAValueType>(
    _ first: some TypedExpression<SetExpr<First>>,
    _ second: some TypedExpression<SetExpr<Second>>,
    _ third: some TypedExpression<SetExpr<Third>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (WithValue<First>, WithValue<Second>, WithValue<Third>) -> [StepStatement]
) -> StepStatement {
    With(first, file: file, line: line, column: column) { firstValue in
        With(second, file: file, line: line, column: column + 1) { secondValue in
            With(third, file: file, line: line, column: column + 2) { thirdValue in
                body(firstValue, secondValue, thirdValue)
            }
        }
    }
}

/// Binds four independent members in formal left-to-right scope order.
public func With<First: TLAValueType, Second: TLAValueType, Third: TLAValueType, Fourth: TLAValueType>(
    _ first: some TypedExpression<SetExpr<First>>,
    _ second: some TypedExpression<SetExpr<Second>>,
    _ third: some TypedExpression<SetExpr<Third>>,
    _ fourth: some TypedExpression<SetExpr<Fourth>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (WithValue<First>, WithValue<Second>, WithValue<Third>, WithValue<Fourth>) -> [StepStatement]
) -> StepStatement {
    With(first, second, third, file: file, line: line, column: column) { firstValue, secondValue, thirdValue in
        With(fourth, file: file, line: line, column: column + 3) { fourthValue in
            body(firstValue, secondValue, thirdValue, fourthValue)
        }
    }
}

/// Destructures a selected two-member formal tuple for one atomic block.
///
/// This is the typed Swift spelling of PlusCal's
/// `with <<first, second>> \in Pairs`. The generated bindings are formal
/// expressions.
public func With<First: TLAValueType, Second: TLAValueType>(
    _ pairs: some TypedExpression<SetExpr<Pair<First, Second>>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (WithValue<First>, WithValue<Second>) -> [StepStatement]
) -> StepStatement {
    With(pairs, file: file, line: line, column: column) { pair in
        Let(pair.first(), file: file, line: line, column: column + 1) { first in
            Let(pair.second(), file: file, line: line, column: column + 2) { second in
                body(first, second)
            }
        }
    }
}

/// Binds PlusCal's deterministic `with name = expression` form for one atomic
/// block. It lowers to a scoped TLA+ `LET name == expression IN ...`
/// expression.
public func Let<Value: TLAValueType>(
    _ value: some TypedExpression<Value>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    let variable = generatedBinderName(file: file, line: line, column: column)
    let bound = WithValue<Value>(expression: .variable(variable))
    return StepStatement(model: .letBinding(variable: variable, value: value.stateExpr, body(bound).map(\.model)))
}

public func Let<Value: TLAValueType>(
    _ value: Value,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    Let(Expr<Value>(.value(value.tlaValue)), file: file, line: line, column: column) { body($0) }
}

/// Tests whether a bounded formal set has a member that satisfies `predicate`.
///
/// This is the typed Swift spelling of TLA+ `\\E value \\in domain : predicate`.
public func Exists<Value: TLAValueType, Predicate: TypedExpression<Bool>>(
    in domain: some TypedExpression<SetExpr<Value>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    where predicate: (WithValue<Value>) -> Predicate
) -> Expr<Bool> {
    let variable = generatedBinderName(file: file, line: line, column: column)
    return Expr(.exists(domain.stateExpr, variable, predicate(WithValue(expression: .variable(variable))).stateExpr))
}

/// Tests a predicate for two independently bound members.
///
/// This is the Swift spelling of nested TLA+ existential quantifiers. The
/// nested AST preserves the same scope and short-circuit semantics as the
/// source language's multi-binder form.
public func Exists<First: TLAValueType, Second: TLAValueType, Predicate: TypedExpression<Bool>>(
    in first: some TypedExpression<SetExpr<First>>,
    and second: some TypedExpression<SetExpr<Second>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    where predicate: (WithValue<First>, WithValue<Second>) -> Predicate
) -> Expr<Bool> {
    Exists(in: first, file: file, line: line, column: column) { firstValue in
        Exists(in: second, file: file, line: line, column: column + 1) { secondValue in
            predicate(firstValue, secondValue)
        }
    }
}

/// Tests whether every bounded formal set member satisfies `predicate`.
///
/// This is the typed Swift spelling of TLA+ `\\A value \\in domain : predicate`.
public func ForAll<Value: TLAValueType, Predicate: TypedExpression<Bool>>(
    in domain: some TypedExpression<SetExpr<Value>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    where predicate: (WithValue<Value>) -> Predicate
) -> Expr<Bool> {
    let variable = generatedBinderName(file: file, line: line, column: column)
    return Expr(.forAll(domain.stateExpr, variable, predicate(WithValue(expression: .variable(variable))).stateExpr))
}

/// Tests a predicate for every pair of independently bound members.
public func ForAll<First: TLAValueType, Second: TLAValueType, Predicate: TypedExpression<Bool>>(
    in first: some TypedExpression<SetExpr<First>>,
    and second: some TypedExpression<SetExpr<Second>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    where predicate: (WithValue<First>, WithValue<Second>) -> Predicate
) -> Expr<Bool> {
    ForAll(in: first, file: file, line: line, column: column) { firstValue in
        ForAll(in: second, file: file, line: line, column: column + 1) { secondValue in
            predicate(firstValue, secondValue)
        }
    }
}

/// Tests a predicate for every member of a declared finite domain.
///
/// This is the typed Swift spelling of a bounded TLA+ `\\A value \\in Type`
/// predicate. It is useful for properties over a PlusCal process family.
public func ForAll<Value: FiniteTLAValueDomain, Predicate: TypedExpression<Bool>>(
    _ domain: FiniteDomain<Value>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    where predicate: (WithValue<Value>) -> Predicate
) -> Expr<Bool> {
    let variable = generatedBinderName(file: file, line: line, column: column)
    return Expr(.forAll(
        .setLiteral(domain.values.map { .value($0.tlaValue) }),
        variable,
        predicate(WithValue(expression: .variable(variable))).stateExpr
    ))
}

/// True when a process in the surrounding `Algorithm` has reached `Done`.
/// The program counter remains lowerer-owned; this avoids raw string-keyed
/// inspection of generated control state.
public func Finished() -> Expr<Bool> {
    Expr(.equal(.programCounter, .controlLocation(.done)))
}

/// True when one member of a process family has reached `Done`.
/// The program counter remains lowerer-owned; this avoids raw string-keyed
/// inspection of generated control state.
public func Finished<Value: FiniteTLAValueDomain>(_ process: WithValue<Value>) -> Expr<Bool> {
    Expr(.equal(
        .functionApply(.programCounter, process.stateExpr),
        .controlLocation(.done)
    ))
}

/// True when the current `Each` process has reached `Done`.
public func Finished<Value: FiniteTLAValueDomain>(_ process: ProcessIdentifier<Value>) -> Expr<Bool> {
    Expr(.equal(
        .functionApply(.programCounter, process.stateExpr),
        .controlLocation(.done)
    ))
}

/// True when one process is at a named PlusCal label.
///
/// This is the typed way to state properties about algorithm control flow.
/// The generated program counter remains an implementation detail.
public func At<Label: CaseIterable & RawRepresentable & Sendable, Value: FiniteTLAValueDomain>(
    _ label: Label,
    _ process: WithValue<Value>
) -> Expr<Bool> where Label.RawValue == String {
    Expr(.equal(
        .functionApply(.programCounter, process.stateExpr),
        .controlLocation(.init(label.rawValue))
    ))
}

/// True when the current `Each` process is at a named PlusCal label.
public func At<Label: CaseIterable & RawRepresentable & Sendable, Value: FiniteTLAValueDomain>(
    _ label: Label,
    _ process: ProcessIdentifier<Value>
) -> Expr<Bool> where Label.RawValue == String {
    Expr(.equal(
        .functionApply(.programCounter, process.stateExpr),
        .controlLocation(.init(label.rawValue))
    ))
}



/// A writable model location with a statically known value type.
public protocol AssignmentTarget<Value>: Sendable {
    associatedtype Value: TLAValueType
    var algorithmLValue: AlgorithmLValue<Value> { get }
}

extension AlgorithmLValue: AssignmentTarget {
    public var algorithmLValue: Self { self }
}
extension Var: AssignmentTarget {}
extension SharedVariable: AssignmentTarget {}
extension LocalVariable: AssignmentTarget {}
extension MacroParameter: AssignmentTarget {}

public func Assign<Target: AssignmentTarget, Expression: TypedExpression>(
    _ target: Target,
    to value: Expression
) -> StepStatement where Target.Value == Expression.ExpressionValue {
    StepStatement(model: .set(target: target.algorithmLValue.model, value: value.stateExpr))
}

public func Assign<Target: AssignmentTarget>(_ target: Target, to value: Target.Value) -> StepStatement {
    Assign(target, to: value.expr)
}

public func If(
    _ condition: some TypedExpression<Bool>,
    @DoBuilder _ then: () -> [StepStatement],
    @DoBuilder else otherwise: @escaping () -> [StepStatement] = { [] }
) -> StepStatement {
    StepStatement(model: .ifElse(condition.stateExpr, then().map(\.model), otherwise().map(\.model)))
}

/// Builds a typed formal conditional value.
///
/// This is distinct from the statement-builder `If(condition) { ... } else: { ... }` form.
public func If<Then: TypedExpression, Otherwise: TypedExpression>(
    _ condition: some TypedExpression<Bool>,
    then: Then,
    else otherwise: Otherwise
) -> Expr<Then.ExpressionValue> where Then.ExpressionValue == Otherwise.ExpressionValue {
    Expr(.ifThenElse(condition.stateExpr, then.stateExpr, otherwise.stateExpr))
}

public func If<Value: TLAValueType>(
    _ condition: some TypedExpression<Bool>, then: Value, else otherwise: Value
) -> Expr<Value> {
    If(condition, then: then.expr, else: otherwise.expr)
}

public func If<Expression: TypedExpression>(
    _ condition: some TypedExpression<Bool>, then: Expression.ExpressionValue, else otherwise: Expression
) -> Expr<Expression.ExpressionValue> {
    If(condition, then: then.expr, else: otherwise)
}

public func If<Expression: TypedExpression>(
    _ condition: some TypedExpression<Bool>, then: Expression, else otherwise: Expression.ExpressionValue
) -> Expr<Expression.ExpressionValue> {
    If(condition, then: then, else: otherwise.expr)
}

public func Either(
    @DoBuilder _ first: () -> [StepStatement],
    @DoBuilder or second: @escaping () -> [StepStatement]
) -> StepStatement {
    StepStatement(model: .either(first().map(\.model), second().map(\.model)))
}

public func Choose<Value: FiniteTLAValueDomain>(
    _ domain: FiniteDomain<Value>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (ProcessIdentifier<Value>) -> [StepStatement]
) -> StepStatement {
    let name = generatedBinderName(file: file, line: line, column: column)
    let value = ProcessIdentifier<Value>(expression: .variable(name))
    return StepStatement(model: .choose(variable: name, domain: domain.values.map(\.tlaValue), body(value).map(\.model)))
}

/// Binds an ordered pair of values from finite domains. This lowers to nested
/// PlusCal choices, so the second binder is scoped inside the first.
public func Choose<First: FiniteTLAValueDomain, Second: FiniteTLAValueDomain>(
    _ firstDomain: FiniteDomain<First>,
    _ secondDomain: FiniteDomain<Second>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (ProcessIdentifier<First>, ProcessIdentifier<Second>) -> [StepStatement]
) -> StepStatement {
    let firstName = generatedBinderName(file: file, line: line, column: column)
    let secondName = generatedBinderName(file: file, line: line, column: column + 1)
    let first = ProcessIdentifier<First>(expression: .variable(firstName))
    let second = ProcessIdentifier<Second>(expression: .variable(secondName))
    return StepStatement(model: .choose(
        variable: firstName,
        domain: firstDomain.values.map(\.tlaValue),
        [.choose(variable: secondName, domain: secondDomain.values.map(\.tlaValue), body(first, second).map(\.model))]
    ))
}

/// Binds one integer from an explicit, finite range for an atomic block.
///
/// This is the natural bounded spelling of PlusCal `with (value \in Nat)`
/// when a TLC configuration supplies the finite range. The range defines the
/// formal choice branches explored by the runtime.
public func Choose(
    _ domain: ClosedRange<Int>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (WithValue<Int>) -> [StepStatement]
) -> StepStatement {
    let name = generatedBinderName(file: file, line: line, column: column)
    let value = WithValue<Int>(expression: .variable(name))
    return StepStatement(model: .choose(
        variable: name,
        domain: domain.map(TLAValue.int),
        body(value).map(\.model)
    ))
}

/// Binds an ordered pair of integers from explicit finite ranges.
public func Choose(
    _ firstDomain: ClosedRange<Int>,
    _ secondDomain: ClosedRange<Int>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (WithValue<Int>, WithValue<Int>) -> [StepStatement]
) -> StepStatement {
    let firstName = generatedBinderName(file: file, line: line, column: column)
    let secondName = generatedBinderName(file: file, line: line, column: column + 1)
    let first = WithValue<Int>(expression: .variable(firstName))
    let second = WithValue<Int>(expression: .variable(secondName))
    return StepStatement(model: .choose(
        variable: firstName,
        domain: firstDomain.map(TLAValue.int),
        [.choose(variable: secondName, domain: secondDomain.map(TLAValue.int), body(first, second).map(\.model))]
    ))
}

public func Goto<Label: CaseIterable & RawRepresentable & Sendable>(_ label: Label) -> StepStatement where Label.RawValue == String {
    StepStatement(model: .goto(AlgorithmLabelModel(name: label.rawValue)))
}

public func Stop() -> StepStatement {
    StepStatement(model: .stop)
}

/// A PlusCal no-op. It changes no user state but still advances control.
public func Skip() -> StepStatement {
    StepStatement(model: .skip)
}

package enum AlgorithmValidator {
    package static func validate(_ model: AlgorithmModel) -> [AlgorithmDiagnostic] {
        var diagnostics: [AlgorithmDiagnostic] = []
        validateName(model.name, at: .algorithm, diagnostics: &diagnostics)
        let procedureNames = model.procedures.map(\.name)
        let procedures = Set(procedureNames)
        let procedureArities = model.procedures.reduce(into: [String: Int]()) {
            $0[$1.name] = $1.parameters.count
        }
        if procedures.count < procedureNames.count {
            diagnostics.append(.init(.duplicateProcedure, at: .algorithm))
        }
        let procedureVariables = model.procedures.flatMap { procedure in
            procedure.parameters.map(\.root) + procedure.locals.map(\.root)
        }
        if Set(procedureVariables).count < procedureVariables.count {
            diagnostics.append(.init(.duplicateProcedureVariable, at: .algorithm))
        }

        if !model.processes.isEmpty, !model.sequentialSteps.isEmpty {
            diagnostics.append(AlgorithmDiagnostic(.invalidAlgorithmComponent, at: .algorithm))
        }
        if model.sequentialFairness == .weak,
           (!model.processes.isEmpty || model.sequentialSteps.isEmpty) {
            diagnostics.append(AlgorithmDiagnostic(.invalidSequentialFairness, at: .algorithm))
        }
        let sequentialLabels = model.sequentialSteps.map(\.label.name)
        if Set(sequentialLabels).count != sequentialLabels.count {
            diagnostics.append(AlgorithmDiagnostic(.duplicateLabel, at: .algorithm))
        }

        for (index, component) in model.components.enumerated() {
            switch component {
            case .shared(let state):
                validateName(state.root, at: .algorithm, diagnostics: &diagnostics)
            case .process(let process):
                validate(
                    process,
                    index: index,
                    procedures: procedures,
                    procedureArities: procedureArities,
                    diagnostics: &diagnostics
                )
            case .procedure(let procedure):
                validate(
                    procedure,
                    index: index,
                    procedures: procedures,
                    procedureArities: procedureArities,
                    diagnostics: &diagnostics
                )
            case .invariant(let invariant):
                validateName(invariant.name, at: .algorithm, diagnostics: &diagnostics)
            case .temporal(let temporal):
                validateName(temporal.name, at: .algorithm, diagnostics: &diagnostics)
            case .invalidPlacement:
                break
            case .formalOperator(let definition):
                validateName(definition.name, at: .algorithm, diagnostics: &diagnostics)
            case .stateConstraint:
                break
            case .step(let step):
                validateSequential(
                    step,
                    labels: Set(model.sequentialSteps.map(\.label.name)),
                    procedures: procedures,
                    procedureArities: procedureArities,
                    diagnostics: &diagnostics
                )
            case .local:
                diagnostics.append(AlgorithmDiagnostic(.invalidAlgorithmComponent, at: .algorithm))
            }
        }
        return diagnostics
    }

    private static func validateSequential(
        _ step: AlgorithmStepModel,
        labels: Set<String>,
        procedures: Set<String>,
        procedureArities: [String: Int],
        diagnostics: inout [AlgorithmDiagnostic]
    ) {
        let allSteps = labels
        validateName(step.label.name, at: .algorithm, diagnostics: &diagnostics)
        let paths = writePaths(step.statements)
        if paths.contains(where: { Set($0).count != $0.count }) {
            diagnostics.append(AlgorithmDiagnostic(.duplicateRootWrite, at: .algorithm))
        }
        if controlTransferCounts(step.statements).contains(where: { $0 > 1 }) {
            diagnostics.append(AlgorithmDiagnostic(.invalidAtomicControlFlow, at: .algorithm))
        }
        validateStatements(
            step.statements,
            at: .algorithm,
            labels: allSteps,
            procedures: procedures,
            procedureArities: procedureArities,
            inProcedure: false,
            diagnostics: &diagnostics
        )
    }

    private static func validate(
        _ process: AlgorithmProcessModel,
        index: Int,
        procedures: Set<String>,
        procedureArities: [String: Int],
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
                validate(
                    step,
                    process: index,
                    labels: Set(labels),
                    procedures: procedures,
                    procedureArities: procedureArities,
                    diagnostics: &diagnostics
                )
            case .invariant(let invariant):
                validateName(invariant.name, at: processAnchor, diagnostics: &diagnostics)
            case .invalidPlacement:
                continue
            case .temporal, .formalOperator, .stateConstraint:
                diagnostics.append(AlgorithmDiagnostic(.invalidAlgorithmComponent, at: processAnchor))
            case .shared, .process, .procedure:
                diagnostics.append(AlgorithmDiagnostic(.invalidAlgorithmComponent, at: processAnchor))
            }
        }

    }

    private static func validate(
        _ step: AlgorithmStepModel,
        process: Int,
        labels: Set<String>,
        procedures: Set<String>,
        procedureArities: [String: Int],
        diagnostics: inout [AlgorithmDiagnostic]
    ) {
        let anchor = AlgorithmDiagnosticAnchor.step(process: process, label: step.label.name)
        let paths = writePaths(step.statements)
        if paths.contains(where: { Set($0).count != $0.count }) {
            diagnostics.append(AlgorithmDiagnostic(.duplicateRootWrite, at: anchor))
        }
        if controlTransferCounts(step.statements).contains(where: { $0 > 1 }) {
            diagnostics.append(AlgorithmDiagnostic(.invalidAtomicControlFlow, at: anchor))
        }
        validateStatements(
            step.statements,
            at: anchor,
            labels: labels,
            procedures: procedures,
            procedureArities: procedureArities,
            inProcedure: false,
            diagnostics: &diagnostics
        )
    }

    private static func validate(
        _ procedure: AlgorithmProcedureModel,
        index: Int,
        procedures: Set<String>,
        procedureArities: [String: Int],
        diagnostics: inout [AlgorithmDiagnostic]
    ) {
        let anchor = AlgorithmDiagnosticAnchor.process(index)
        validateName(procedure.name, at: anchor, diagnostics: &diagnostics)
        let labels = procedure.steps.map(\.label.name)
        if labels.isEmpty || Set(labels).count < labels.count {
            diagnostics.append(.init(.duplicateLabel, at: anchor))
        }
        procedure.parameters.forEach {
            validateName($0.root, at: anchor, diagnostics: &diagnostics)
        }
        procedure.locals.forEach {
            validateName($0.root, at: anchor, diagnostics: &diagnostics)
        }
        for step in procedure.steps {
            let stepAnchor = AlgorithmDiagnosticAnchor.step(process: index, label: step.label.name)
            validateName(step.label.name, at: stepAnchor, diagnostics: &diagnostics)
            let paths = writePaths(step.statements)
            if paths.contains(where: { Set($0).count < $0.count }) {
                diagnostics.append(.init(.duplicateRootWrite, at: stepAnchor))
            }
            if controlTransferCounts(step.statements).contains(where: { $0 > 1 }) {
                diagnostics.append(.init(.invalidAtomicControlFlow, at: stepAnchor))
            }
            validateStatements(
                step.statements,
                at: stepAnchor,
                labels: Set(labels),
                procedures: procedures,
                procedureArities: procedureArities,
                inProcedure: true,
                diagnostics: &diagnostics
            )
        }
        for component in procedure.components {
            switch component {
            case .local, .step, .invalidPlacement:
                break
            case .shared, .process, .procedure, .invariant, .temporal,
                 .formalOperator, .stateConstraint:
                diagnostics.append(.init(.invalidAlgorithmComponent, at: anchor))
            }
        }
    }

    private static func validateStatements(
        _ statements: [AlgorithmStatementModel],
        at anchor: AlgorithmDiagnosticAnchor,
        labels: Set<String>,
        procedures: Set<String>,
        procedureArities: [String: Int],
        inProcedure: Bool,
        diagnostics: inout [AlgorithmDiagnostic]
    ) {
        for (index, statement) in statements.enumerated() {
            switch statement {
            case .rejected(let code):
                diagnostics.append(AlgorithmDiagnostic(code, at: anchor))
            case .await, .assert, .skip:
                break
            case .letBinding(_, _, let body), .with(_, _, let body):
                validateStatements(body, at: anchor, labels: labels, procedures: procedures, procedureArities: procedureArities, inProcedure: inProcedure, diagnostics: &diagnostics)
            case .set(let target, _):
                validateName(target.root, at: anchor, diagnostics: &diagnostics)
            case .parallel(let assignments):
                assignments.forEach { validateName($0.target.root, at: anchor, diagnostics: &diagnostics) }
            case .ifElse(_, let then, let otherwise), .either(let then, let otherwise):
                validateStatements(then, at: anchor, labels: labels, procedures: procedures, procedureArities: procedureArities, inProcedure: inProcedure, diagnostics: &diagnostics)
                validateStatements(otherwise, at: anchor, labels: labels, procedures: procedures, procedureArities: procedureArities, inProcedure: inProcedure, diagnostics: &diagnostics)
            case .choose(_, let domain, let body):
                validateDomain(domain, at: anchor, diagnostics: &diagnostics)
                validateStatements(body, at: anchor, labels: labels, procedures: procedures, procedureArities: procedureArities, inProcedure: inProcedure, diagnostics: &diagnostics)
            case .goto(let label):
                if !labels.contains(label.name) {
                    diagnostics.append(AlgorithmDiagnostic(.invalidTarget, at: anchor))
                }
            case .call(let target, let arguments):
                if procedures.contains(target) == false {
                    diagnostics.append(.init(.invalidProcedureTarget, at: anchor))
                }
                if let expected = procedureArities[target],
                   expected < arguments.count || expected > arguments.count {
                    diagnostics.append(.init(.invalidProcedureArity, at: anchor))
                }
                let followedByReturn: Bool
                if statements.indices.contains(index + 1), case .return = statements[index + 1] {
                    followedByReturn = true
                } else {
                    followedByReturn = false
                }
                if index < statements.index(before: statements.endIndex), followedByReturn == false {
                    diagnostics.append(.init(.invalidProcedureControlFlow, at: anchor))
                }
            case .return:
                if inProcedure == false {
                    diagnostics.append(.init(.invalidProcedureReturn, at: anchor))
                }
                if index < statements.index(before: statements.endIndex) {
                    diagnostics.append(.init(.invalidProcedureControlFlow, at: anchor))
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
            case .rejected: statementPaths = [[]]
            case .set(let target, _):
                statementPaths = [[target.root]]
            case .parallel(let assignments):
                statementPaths = [assignments.map(\.target.root)]
            case .ifElse(_, let then, let otherwise), .either(let then, let otherwise):
                statementPaths = writePaths(then) + writePaths(otherwise)
            case .choose(_, _, let body):
                statementPaths = writePaths(body)
            case .await, .assert, .goto, .call, .return, .stop, .skip:
                statementPaths = [[]]
            case .letBinding(_, _, let body), .with(_, _, let body):
                statementPaths = writePaths(body)
            }
            paths = paths.flatMap { path in statementPaths.map { path + $0 } }
        }
    }

    static func controlTransferCounts(_ statements: [AlgorithmStatementModel]) -> [Int] {
        var paths = [0]
        var index = statements.startIndex
        while index < statements.endIndex {
            let statement = statements[index]
            let statementPaths: [Int]
            if case .call = statement,
               statements.indices.contains(index + 1),
               case .return = statements[index + 1] {
                statementPaths = [1]
                index += 2
            } else {
                switch statement {
                case .goto, .call, .return, .stop:
                    statementPaths = [1]
                case .letBinding(_, _, let body), .with(_, _, let body), .choose(_, _, let body):
                    statementPaths = controlTransferCounts(body)
                case .parallel:
                    statementPaths = [0]
                case .ifElse(_, let then, let otherwise), .either(let then, let otherwise):
                    statementPaths = controlTransferCounts(then) + controlTransferCounts(otherwise)
                case .rejected, .await, .assert, .set, .skip:
                    statementPaths = [0]
                }
                index += 1
            }
            paths = paths.flatMap { path in statementPaths.map { path + $0 } }
        }
        return paths
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
        } else if isPlusCalDeclarationName(name) == false {
            diagnostics.append(AlgorithmDiagnostic(.invalidName, at: anchor))
        }
    }
}
