// swiftlint:disable identifier_name

public protocol PlusCalLabel: Hashable, Sendable {}

/// A validated PlusCal program-counter label.
///
/// String literals are accepted only at this boundary. The algorithm validator
/// rejects empty, reserved, and non-identifier labels before lowering.
public struct ProgramLabel: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }
}

extension ProgramLabel: PlusCalLabel {}

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

/// A value bound for one atomic `With` body.
///
/// It exists only while constructing the algorithm IR. The lowerer turns it
/// into a scoped TLA+ action binding; it is never runtime Swift state.
public struct WithValue<Value: TLAValueType>: StateExprConvertible, Sendable {
    fileprivate let expression: StateExpr

    public var stateExpr: StateExpr { expression }

    public var expr: Expr<Value> { Expr(expression) }

    /// Keep a typed enum literal contextual when it is compared to a `With` value.
    public static func == (lhs: WithValue<Value>, rhs: Value) -> StateExpr {
        .equal(lhs.stateExpr, .value(rhs.tlaValue))
    }

    public static func == (lhs: Value, rhs: WithValue<Value>) -> StateExpr {
        .equal(.value(lhs.tlaValue), rhs.stateExpr)
    }

    public static func != (lhs: WithValue<Value>, rhs: Value) -> StateExpr {
        .notEqual(lhs.stateExpr, .value(rhs.tlaValue))
    }

    public static func != (lhs: Value, rhs: WithValue<Value>) -> StateExpr {
        .notEqual(.value(lhs.tlaValue), rhs.stateExpr)
    }
}

extension WithValue {
    public subscript<Schema: TLARecordSchema, Field>(_ field: TLAField<Schema, Field>) -> Expr<Field>
    where Value == Record<Schema>, Field: TLAValueType {
        Expr<Field>(.recordAccess(stateExpr, field.name))
    }

    public subscript<Domain: FiniteDomainKey, Range>(_ index: WithValue<Domain>) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.stateExpr))
    }
}

public struct AlgorithmLValue<Value: TLAValueType>: Sendable {
    fileprivate let model: AlgorithmLValueModel
}

/// A typed shared algorithm variable.
///
/// Declare it with `let value = SharedVar(initial: 0)` inside a
/// `#spec` algorithm. The `#spec` macro registers the declaration with the
/// runtime builder, while the parser independently reads the same declaration.
/// Application code never needs the engine-level `Var` type for this form.
public struct SharedVariable<Value: TLAValueType>: StateExprConvertible, Sendable {
    fileprivate let name: String
    fileprivate let initial: StateExpr
    fileprivate let initialSet: StateExpr?
    fileprivate let swiftTypeName: String

    public var stateExpr: StateExpr { .variable(name) }

    public var algorithmLValue: AlgorithmLValue<Value> {
        AlgorithmLValue(model: .root(name))
    }

    @discardableResult
    public func becomes(_ value: Value) -> ActionExpr {
        .assign(name, .value(value.tlaValue))
    }

    @discardableResult
    public func becomes(_ value: Expr<Value>) -> ActionExpr {
        .assign(name, value.raw)
    }

    public var stays: ActionExpr { .unchanged(name) }
}

/// A typed process-local algorithm variable.
///
/// A `LocalVar` declaration is valid only inside an `Each` process body.
public struct LocalVariable<Value: TLAValueType>: StateExprConvertible, Sendable {
    fileprivate let name: String
    fileprivate let initial: StateExpr
    fileprivate let initialSet: StateExpr?
    fileprivate let swiftTypeName: String

    public var stateExpr: StateExpr { .variable(name) }

    public var algorithmLValue: AlgorithmLValue<Value> {
        AlgorithmLValue(model: .root(name))
    }
}

// `SharedVariable` is an authoring handle, but it must read like the typed
// variable it represents. Keep these operators on the handle rather than
// forcing authors to escape into `.stateExpr` or `Expr`.
extension SharedVariable where Value == Int {
    public static func + (_ lhs: SharedVariable, _ rhs: Int) -> Expr<Int> {
        Expr(.add(lhs.stateExpr, .int(rhs)))
    }

    public static func + (_ lhs: SharedVariable, _ rhs: SharedVariable) -> Expr<Int> {
        Expr(.add(lhs.stateExpr, rhs.stateExpr))
    }

    public static func + (_ lhs: SharedVariable, _ rhs: Expr<Int>) -> Expr<Int> {
        Expr(.add(lhs.stateExpr, rhs.raw))
    }

    public static func - (_ lhs: SharedVariable, _ rhs: Int) -> Expr<Int> {
        Expr(.subtract(lhs.stateExpr, .int(rhs)))
    }

    public static func - (_ lhs: SharedVariable, _ rhs: SharedVariable) -> Expr<Int> {
        Expr(.subtract(lhs.stateExpr, rhs.stateExpr))
    }

    public static func - (_ lhs: SharedVariable, _ rhs: Expr<Int>) -> Expr<Int> {
        Expr(.subtract(lhs.stateExpr, rhs.raw))
    }

    public static func % (_ lhs: SharedVariable, _ rhs: Int) -> Expr<Int> {
        Expr(.modulo(lhs.stateExpr, .int(rhs)))
    }

    public static func - (_ lhs: Int, _ rhs: SharedVariable) -> Expr<Int> {
        Expr(.subtract(.int(lhs), rhs.stateExpr))
    }

    public static func < (_ lhs: SharedVariable, _ rhs: Int) -> StateExpr {
        .lessThan(lhs.stateExpr, .int(rhs))
    }

    public static func > (_ lhs: SharedVariable, _ rhs: Int) -> StateExpr {
        .greaterThan(lhs.stateExpr, .int(rhs))
    }

    public static func <= (_ lhs: SharedVariable, _ rhs: Int) -> StateExpr {
        .lessOrEqual(lhs.stateExpr, .int(rhs))
    }

    public static func >= (_ lhs: SharedVariable, _ rhs: Int) -> StateExpr {
        .greaterOrEqual(lhs.stateExpr, .int(rhs))
    }

    public static func == (_ lhs: SharedVariable, _ rhs: Int) -> StateExpr {
        .equal(lhs.stateExpr, .int(rhs))
    }

    public static func != (_ lhs: SharedVariable, _ rhs: Int) -> StateExpr {
        .notEqual(lhs.stateExpr, .int(rhs))
    }
}

extension SharedVariable {
    public func contains<Element: TLAValueType>(_ element: Element) -> StateExpr
    where Value == SetExpr<Element> {
        .in(.value(element.tlaValue), stateExpr)
    }

    public func appending<Element: TLAValueType>(_ element: Element) -> Expr<TupleExpr<Element>>
    where Value == TupleExpr<Element> {
        Expr(.tupleAppend(stateExpr, .value(element.tlaValue)))
    }

    public func at<Element: TLAValueType>(_ index: Int) -> Expr<Element>
    where Value == TupleExpr<Element> {
        Expr(.tupleAccess(stateExpr, index))
    }

    public subscript<Schema: TLARecordSchema, Field>(_ field: TLAField<Schema, Field>) -> Expr<Field>
    where Value == Record<Schema>, Field: TLAValueType {
        Expr<Field>(.recordAccess(stateExpr, field.name))
    }

    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: Domain) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.tlaValue.stateExpr))
    }

    /// Reads a finite function at the current PlusCal process identifier.
    public subscript<Domain: FiniteDomainKey, Range>(_ index: ProcessIdentifier<Domain>) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.stateExpr))
    }

    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: Expr<Domain>) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.raw))
    }

    public subscript<Domain: FiniteDomainKey, Range>(_ index: WithValue<Domain>) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.stateExpr))
    }

    public func updating<Domain: FiniteTLAValueDomain, Range>(
        _ index: Domain,
        _ update: (Expr<Range>) -> Expr<Range>
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        let selected = self[index]
        return Expr<Function<Domain, Range>>(
            .except(stateExpr, index.tlaValue.stateExpr, update(selected).raw)
        )
    }

    /// Updates a finite function at the current PlusCal process identifier.
    public func updating<Domain: FiniteDomainKey, Range>(
        _ index: ProcessIdentifier<Domain>,
        _ update: (Expr<Range>) -> Expr<Range>
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        let selected = self[index]
        return Expr<Function<Domain, Range>>(
            .except(stateExpr, index.stateExpr, update(selected).raw)
        )
    }

    /// Replaces a finite function value at the current PlusCal process identifier.
    public func updating<Domain: FiniteDomainKey, Range>(
        _ index: ProcessIdentifier<Domain>,
        to value: Expr<Range>
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Function<Domain, Range>>(.except(stateExpr, index.stateExpr, value.raw))
    }

    public func updating<Domain: FiniteDomainKey, Range>(
        _ index: ProcessIdentifier<Domain>,
        to value: Range
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        updating(index, to: Expr<Range>(.value(value.tlaValue)))
    }

    public func updating<Domain: FiniteTLAValueDomain, Range>(
        _ index: Expr<Domain>,
        _ update: (Expr<Range>) -> Expr<Range>
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Function<Domain, Range>>(
            .except(stateExpr, index.raw, update(Expr<Range>(.functionApply(stateExpr, index.raw))).raw)
        )
    }

    public func updating<Domain: FiniteDomainKey, Range>(
        _ index: WithValue<Domain>,
        _ update: (Expr<Range>) -> Expr<Range>
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Function<Domain, Range>>(
            .except(stateExpr, index.stateExpr, update(Expr<Range>(.functionApply(stateExpr, index.stateExpr))).raw)
        )
    }

    public func updating<Domain: FiniteTLAValueDomain, Range>(
        _ index: Expr<Domain>,
        to value: Expr<Range>
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Function<Domain, Range>>(.except(stateExpr, index.raw, value.raw))
    }

    public func updating<Domain: FiniteTLAValueDomain, Range>(
        _ index: Expr<Domain>,
        to value: Range
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        updating(index, to: Expr<Range>(.value(value.tlaValue)))
    }

    public func updating<Domain: FiniteTLAValueDomain, Range>(
        _ index: Domain,
        to value: Expr<Range>
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Function<Domain, Range>>(.except(stateExpr, index.tlaValue.stateExpr, value.raw))
    }

    public func updating<Domain: FiniteTLAValueDomain, Range>(
        _ index: Domain,
        to value: Range
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        updating(index, to: Expr<Range>(.value(value.tlaValue)))
    }

    public func inserting<Element: TLAValueType>(_ element: Element) -> Expr<SetExpr<Element>>
    where Value == SetExpr<Element> {
        Expr<SetExpr<Element>>(.union(stateExpr, .setLiteral([.value(element.tlaValue)])))
    }

    public func inserting<Element: TLAValueType>(_ element: Expr<Element>) -> Expr<SetExpr<Element>>
    where Value == SetExpr<Element> {
        Expr<SetExpr<Element>>(.union(stateExpr, .setLiteral([element.raw])))
    }

    public func removing<Element: TLAValueType>(_ element: Element) -> Expr<SetExpr<Element>>
    where Value == SetExpr<Element> {
        Expr<SetExpr<Element>>(.setDifference(stateExpr, .setLiteral([.value(element.tlaValue)])))
    }

    public func removing<Element: TLAValueType>(_ element: WithValue<Element>) -> Expr<SetExpr<Element>>
    where Value == SetExpr<Element> {
        Expr<SetExpr<Element>>(.setDifference(stateExpr, .setLiteral([element.stateExpr])))
    }
}

extension SharedVariable where Value: FormalSetValue {
    public var isEmpty: StateExpr {
        .equal(.cardinality(stateExpr), .value(.int(0)))
    }
}

extension SharedVariable where Value: FormalTupleValue {
    public var count: Expr<Int> {
        Expr(.tupleLength(stateExpr))
    }
}

extension LocalVariable {
    public subscript<Schema: TLARecordSchema, Field>(_ field: TLAField<Schema, Field>) -> Expr<Field>
    where Value == Record<Schema>, Field: TLAValueType {
        Expr<Field>(.recordAccess(stateExpr, field.name))
    }

    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: Domain) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.tlaValue.stateExpr))
    }

    /// Reads a finite function at the current PlusCal process identifier.
    public subscript<Domain: FiniteDomainKey, Range>(_ index: ProcessIdentifier<Domain>) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.stateExpr))
    }

    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: Expr<Domain>) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.raw))
    }
}

/// Declares a shared PlusCal-shaped variable.
///
/// Use it as a local declaration inside `#spec`; the macro registers the
/// resulting handle with the enclosing `Algorithm` builder.
public func SharedVar<Value: TLAValueType>(
    _ name: String,
    initial: Value
) -> SharedVariable<Value> {
    SharedVariable(
        name: name,
        initial: .value(initial.tlaValue),
        initialSet: nil,
        swiftTypeName: String(reflecting: Value.self)
    )
}

/// The name is supplied from the enclosing `let` binding by `#spec`.
/// This overload is intentionally useful only inside that macro boundary.
public func SharedVar<Value: TLAValueType>(initial: Value) -> SharedVariable<Value> {
    SharedVariable(
        name: "",
        initial: .value(initial.tlaValue),
        initialSet: nil,
        swiftTypeName: String(reflecting: Value.self)
    )
}

/// Declares an integer shared variable with a finite nondeterministic initial
/// value. The generated initial state contains one state for each member.
public func SharedVar(in range: ClosedRange<Int>) -> SharedVariable<Int> {
    SharedVar("", in: range)
}

/// The named form used by the `#spec` declaration rewrite.
public func SharedVar(_ name: String, in range: ClosedRange<Int>) -> SharedVariable<Int> {
    let values = range.map { StateExpr.value(.int($0)) }
    return SharedVariable(
        name: name,
        initial: .value(.int(range.lowerBound)),
        initialSet: .setLiteral(values),
        swiftTypeName: "Int"
    )
}

/// Declares a shared variable with a typed formal initial expression.
public func SharedVar<Value: TLAValueType>(
    _ name: String,
    initial: Expr<Value>
) -> SharedVariable<Value> {
    SharedVariable(name: name, initial: initial.raw, initialSet: nil, swiftTypeName: String(reflecting: Value.self))
}

/// The name is supplied from the enclosing `let` binding by `#spec`.
public func SharedVar<Value: TLAValueType>(initial: Expr<Value>) -> SharedVariable<Value> {
    SharedVariable(name: "", initial: initial.raw, initialSet: nil, swiftTypeName: String(reflecting: Value.self))
}

/// Declares a process-local PlusCal-shaped variable.
public func LocalVar<Value: TLAValueType>(
    _ name: String,
    initial: Value
) -> LocalVariable<Value> {
    LocalVariable(name: name, initial: .value(initial.tlaValue), initialSet: nil, swiftTypeName: String(reflecting: Value.self))
}

/// The name is supplied from the enclosing `let` binding by `#spec`.
/// This overload is intentionally useful only inside that macro boundary.
public func LocalVar<Value: TLAValueType>(initial: Value) -> LocalVariable<Value> {
    LocalVariable(name: "", initial: .value(initial.tlaValue), initialSet: nil, swiftTypeName: String(reflecting: Value.self))
}

/// Declares a process-local variable with a typed formal initial expression.
public func LocalVar<Value: TLAValueType>(
    _ name: String,
    initial: Expr<Value>
) -> LocalVariable<Value> {
    LocalVariable(name: name, initial: initial.raw, initialSet: nil, swiftTypeName: String(reflecting: Value.self))
}

/// The name is supplied from the enclosing `let` binding by `#spec`.
public func LocalVar<Value: TLAValueType>(initial: Expr<Value>) -> LocalVariable<Value> {
    LocalVariable(name: "", initial: initial.raw, initialSet: nil, swiftTypeName: String(reflecting: Value.self))
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

    public static func buildExpression<Value>(_ variable: SharedVariable<Value>) -> [AlgorithmElement] {
        [AlgorithmElement(model: .shared(.init(
            root: variable.name,
            initial: variable.initial,
            initialSet: variable.initialSet,
            swiftTypeName: variable.swiftTypeName
        )))]
    }

    public static func buildExpression<Value>(_ variable: LocalVariable<Value>) -> [AlgorithmElement] {
        [AlgorithmElement(model: .local(.init(
            root: variable.name,
            initial: variable.initial,
            initialSet: variable.initialSet,
            swiftTypeName: variable.swiftTypeName
        )))]
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

extension SpecBuilder {
    /// Lets a `#spec` body use the same typed shared declaration whether it
    /// contains a PlusCal `Algorithm` or an ordinary TLA+ action specification.
    public static func buildExpression<Value>(_ variable: SharedVariable<Value>) -> [SpecComponent] {
        let initial = (try? variable.initial.evaluate(in: [:])) ?? Value.defaultValue.tlaValue
        return [VarDecl(variable.name, initial, initialSet: variable.initialSet)]
    }
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
    AlgorithmElement(model: .shared(AlgorithmStateModel(root: variable.name, initial: .value(initial.tlaValue))))
}

public func Local<Value: TLAValueType>(_ variable: Var<Value>, initial: Value) -> AlgorithmElement {
    AlgorithmElement(model: .local(AlgorithmStateModel(root: variable.name, initial: .value(initial.tlaValue))))
}

/// Declares one independently scheduled process for every member of `domain`.
///
/// `Each` is concurrent: its bodies do not run as a sequential Swift loop.
public func Each<Value: FiniteDomainKey>(
    _ domain: FiniteDomain<Value>,
    fairness: ProcessFairness = .none,
    @AlgorithmBuilder _ body: (ProcessIdentifier<Value>) -> [AlgorithmElement]
) -> AlgorithmElement {
    process(domain, fairness: fairness.model, body)
}

private func process<Value: FiniteDomainKey>(
    _ domain: FiniteDomain<Value>,
    fairness: AlgorithmFairness,
    @AlgorithmBuilder _ body: (ProcessIdentifier<Value>) -> [AlgorithmElement]
) -> AlgorithmElement {
    let identifier = ProcessIdentifier<Value>(expression: .variable("__pcal_self"))
    return AlgorithmElement(
        model: .process(
            AlgorithmProcessModel(
                typeName: String(reflecting: Value.self),
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
public func Do<Name: PlusCalLabel & RawRepresentable>(
    _ label: Name,
    @DoBuilder _ body: () -> [StepStatement]
) -> AlgorithmElement where Name.RawValue == String {
    AlgorithmElement(model: .step(AlgorithmStepModel(label: AlgorithmLabelModel(name: label.rawValue), statements: body().map(\.model))))
}

public func Do(
    _ label: ProgramLabel,
    @DoBuilder _ body: () -> [StepStatement]
) -> AlgorithmElement {
    AlgorithmElement(model: .step(AlgorithmStepModel(label: AlgorithmLabelModel(name: label.rawValue), statements: body().map(\.model))))
}

/// Defines a labeled bounded `while` loop.
///
/// Each execution of the body is one atomic transition. When `condition` is
/// false, control advances to the next `Do` or `While` block.
public func While<Name: PlusCalLabel & RawRepresentable>(
    _ label: Name,
    _ condition: some StateExprConvertible,
    @DoBuilder _ body: () -> [StepStatement]
) -> AlgorithmElement where Name.RawValue == String {
    AlgorithmElement(model: .step(AlgorithmStepModel(
        label: AlgorithmLabelModel(name: label.rawValue),
        statements: body().map(\.model),
        loopCondition: condition.stateExpr
    )))
}

public func While(
    _ label: ProgramLabel,
    _ condition: some StateExprConvertible,
    @DoBuilder _ body: () -> [StepStatement]
) -> AlgorithmElement {
    AlgorithmElement(model: .step(AlgorithmStepModel(
        label: AlgorithmLabelModel(name: label.rawValue),
        statements: body().map(\.model),
        loopCondition: condition.stateExpr
    )))
}

public func Await(_ condition: some StateExprConvertible) -> StepStatement {
    StepStatement(model: .await(condition.stateExpr))
}

/// PlusCal `when`: a guarded atomic step. `When` and `Await` have the same
/// transition semantics; the different spelling is author intent only.
public func When(_ condition: some StateExprConvertible) -> StepStatement {
    Await(condition)
}

/// A PlusCal assertion. A false assertion becomes a generated formal safety
/// check at this atomic program-counter location; it is not a Swift debug
/// assertion and cannot be compiled out.
public func Assert(_ condition: some StateExprConvertible) -> StepStatement {
    StepStatement(model: .assert(condition.stateExpr))
}

/// Binds a nondeterministically chosen member of a bounded formal set for one
/// atomic block. An empty set disables that block, as PlusCal `with (x \in S)`.
public func With<Value: TLAValueType>(
    _ source: Expr<SetExpr<Value>>,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    let variable = "__pcal_with"
    let value = WithValue<Value>(expression: .variable(variable))
    return StepStatement(model: .with(variable: variable, source: source.raw, body(value).map(\.model)))
}

public func With<Value: TLAValueType>(
    _ source: Var<SetExpr<Value>>,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    With(Expr<SetExpr<Value>>(source.stateExpr), body)
}

public func With<Value: TLAValueType>(
    _ source: SharedVariable<SetExpr<Value>>,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    With(Expr<SetExpr<Value>>(source.stateExpr), body)
}

/// Binds one member of a finite Swift domain. This is the most direct Swift
/// spelling of PlusCal `with (value \in Type)`.
public func With<Value: FiniteDomainKey>(
    _ source: FiniteDomain<Value>,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    let variable = "__pcal_with"
    let value = WithValue<Value>(expression: .variable(variable))
    return StepStatement(model: .with(
        variable: variable,
        source: .setLiteral(source.values.map { .value($0.tlaValue) }),
        body(value).map(\.model)
    ))
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

public func Assign<Value: TLAValueType>(
    _ variable: SharedVariable<Value>,
    to value: some StateExprConvertible
) -> StepStatement {
    Assign(variable.algorithmLValue, to: value)
}

public func Assign<Value: TLAValueType>(
    _ variable: LocalVariable<Value>,
    to value: some StateExprConvertible
) -> StepStatement {
    Assign(variable.algorithmLValue, to: value)
}

public func If(
    _ condition: some StateExprConvertible,
    @DoBuilder _ then: () -> [StepStatement],
    @DoBuilder else otherwise: @escaping () -> [StepStatement] = { [] }
) -> StepStatement {
    StepStatement(model: .ifElse(condition.stateExpr, then().map(\.model), otherwise().map(\.model)))
}

public func Either(
    @DoBuilder _ first: () -> [StepStatement],
    @DoBuilder or second: @escaping () -> [StepStatement]
) -> StepStatement {
    StepStatement(model: .either(first().map(\.model), second().map(\.model)))
}

public func Choose<Value: FiniteDomainKey>(
    _ domain: FiniteDomain<Value>,
    @DoBuilder _ body: (ProcessIdentifier<Value>) -> [StepStatement]
) -> StepStatement {
    let name = "__pcal_choice"
    let value = ProcessIdentifier<Value>(expression: .variable(name))
    return StepStatement(model: .choose(variable: name, domain: domain.values.map(\.tlaValue), body(value).map(\.model)))
}

public func Goto<Label: PlusCalLabel & RawRepresentable>(_ label: Label) -> StepStatement where Label.RawValue == String {
    StepStatement(model: .goto(AlgorithmLabelModel(name: label.rawValue)))
}

public func Goto(_ label: ProgramLabel) -> StepStatement {
    StepStatement(model: .goto(AlgorithmLabelModel(name: label.rawValue)))
}

public func Stop() -> StepStatement {
    StepStatement(model: .stop)
}

/// A PlusCal no-op. It changes no user state but still advances control.
public func Skip() -> StepStatement {
    StepStatement(model: .skip)
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
            case .await, .assert, .skip:
                break
            case .with(_, _, let body):
                validateStatements(body, at: anchor, labels: labels, diagnostics: &diagnostics)
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
            case .await, .assert, .goto, .stop, .skip:
                statementPaths = [[]]
            case .with(_, _, let body):
                statementPaths = writePaths(body)
            }
            paths = paths.flatMap { path in statementPaths.map { path + $0 } }
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
