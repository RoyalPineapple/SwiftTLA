// swiftlint:disable identifier_name

public struct FiniteDomain<Value: FiniteTLAValueDomain>: Sendable {
    fileprivate let values: [Value]

    public init() {
        values = Value.finiteValues
    }

    public init(_ values: [Value]) {
        self.values = values
    }

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
    /// process algorithm an explicit, finite set without treating a Swift
    /// enum's raw value as application data.
    public func members(before current: ProcessIdentifier<Value>) -> Expr<SetExpr<Value>> {
        members(before: current.stateExpr)
    }

    /// The declared members before a process-local member.
    public func members(before current: LocalVariable<Value>) -> Expr<SetExpr<Value>> {
        members(before: current.stateExpr)
    }

    /// The declared members before a value selected by `With`.
    public func members(before current: WithValue<Value>) -> Expr<SetExpr<Value>> {
        members(before: current.stateExpr)
    }

    private func members(before current: StateExpr) -> Expr<SetExpr<Value>> {
        var preceding = Expr<SetExpr<Value>>(.setLiteral([]))
        for (index, candidate) in values.enumerated().reversed() {
            let earlier = Expr<SetExpr<Value>>(
                .setLiteral(values.prefix(index).map { .value($0.tlaValue) })
            )
            preceding = If(
                StateExpr.equal(current, .value(candidate.tlaValue)),
                then: earlier,
                else: preceding
            )
        }
        return preceding
    }
}

public struct ProcessIdentifier<Value: FiniteTLAValueDomain>: StateExprConvertible, Sendable {
    fileprivate let expression: StateExpr

    public var stateExpr: StateExpr {
        expression
    }

    /// The current process identifier as a typed formal expression.
    public var expr: Expr<Value> {
        Expr(expression)
    }

    /// Compares the current process identifier with a typed formal value.
    public static func == (lhs: ProcessIdentifier<Value>, rhs: Value) -> StateExpr {
        .equal(lhs.stateExpr, .value(rhs.tlaValue))
    }

    /// Compares the current process identifier with a typed formal value.
    public static func != (lhs: ProcessIdentifier<Value>, rhs: Value) -> StateExpr {
        .notEqual(lhs.stateExpr, .value(rhs.tlaValue))
    }
}

/// A value bound for one atomic `With` body.
///
/// It carries a scoped formal action binding while the algorithm IR is built.
public struct WithValue<Value: TLAValueType>: StateExprConvertible, Sendable {
    let expression: StateExpr

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

    public static func == (lhs: WithValue<Value>, rhs: WithValue<Value>) -> StateExpr {
        .equal(lhs.stateExpr, rhs.stateExpr)
    }

    public static func != (lhs: WithValue<Value>, rhs: WithValue<Value>) -> StateExpr {
        .notEqual(lhs.stateExpr, rhs.stateExpr)
    }
}

extension WithValue {
    public func first<First: TLAValueType, Second: TLAValueType>() -> Expr<First>
    where Value == Pair<First, Second> {
        Expr<First>(.tupleAccess(stateExpr, 1))
    }

    public func second<First: TLAValueType, Second: TLAValueType>() -> Expr<Second>
    where Value == Pair<First, Second> {
        Expr<Second>(.tupleAccess(stateExpr, 2))
    }

    public subscript<Schema: TLARecordSchema, Field>(_ field: TLAField<Schema, Field>) -> Expr<Field>
    where Value == Record<Schema>, Field: TLAValueType {
        Expr<Field>(field.recordAccess(stateExpr))
    }

    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: WithValue<Domain>) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.stateExpr))
    }
}

extension Expr {
    /// Reads a finite formal function using a value selected by `With`.
    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: WithValue<Domain>) -> Expr<Range>
    where T == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(raw, index.stateExpr))
    }

    /// Reads a finite function using process-local formal state.
    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: LocalVariable<Domain>) -> Expr<Range>
    where T == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(raw, index.stateExpr))
    }
}

extension Function where Domain: FiniteTLAValueDomain {
    /// Builds a total finite formal function from a concrete typed value.
    public static func mapping(
        _ body: (WithValue<Domain>) -> Range
    ) -> Expr<Self> {
        mapping { key in Expr(body(key)) }
    }

    /// Builds a total finite formal function from an expression over each key.
    ///
    /// This is useful for dependent initial state: the body may read an
    /// earlier shared variable, but it cannot execute ordinary Swift logic.
    public static func mapping(
        _ body: (WithValue<Domain>) -> Expr<Range>
    ) -> Expr<Self> {
        let binding = "__pcal_function_key"
        let key = WithValue<Domain>(expression: .variable(binding))
        return Expr<Self>(.functionLiteral(
            .setLiteral(Domain.tlaValues.map(StateExpr.value)),
            binding,
            body(key).raw
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
public struct MacroParameter<Value: TLAValueType>: StateExprConvertible, Sendable {
    fileprivate let name: String

    public var stateExpr: StateExpr { .variable(name) }
    public var expr: Expr<Value> { Expr(stateExpr) }

    public var algorithmLValue: AlgorithmLValue<Value> {
        AlgorithmLValue(model: .root(name))
    }
}

/// A typed formal input of a PlusCal procedure.
public struct ProcedureParameter<Value: TLAValueType>: StateExprConvertible, Sendable {
    fileprivate let name: String
    public var stateExpr: StateExpr { .variable(name) }
    public var expr: Expr<Value> { Expr(stateExpr) }
    public var algorithmLValue: AlgorithmLValue<Value> { AlgorithmLValue(model: .root(name)) }
}

extension MacroParameter where Value == Int {
    public static func == (lhs: MacroParameter, rhs: Int) -> StateExpr {
        .equal(lhs.stateExpr, .value(.int(rhs)))
    }

    public static func > (lhs: MacroParameter, rhs: Int) -> StateExpr {
        .greaterThan(lhs.stateExpr, .value(.int(rhs)))
    }

    public static func + (lhs: MacroParameter, rhs: Int) -> Expr<Int> {
        Expr(.add(lhs.stateExpr, .value(.int(rhs))))
    }

    public static func - (lhs: MacroParameter, rhs: Int) -> Expr<Int> {
        Expr(.subtract(lhs.stateExpr, .value(.int(rhs))))
    }
}

extension MacroParameter where Value: FiniteTLAValueDomain {
    public static func == (lhs: MacroParameter, rhs: Value) -> StateExpr {
        .equal(lhs.stateExpr, rhs.tlaValue.stateExpr)
    }

    public static func != (lhs: MacroParameter, rhs: Value) -> StateExpr {
        .notEqual(lhs.stateExpr, rhs.tlaValue.stateExpr)
    }
}

/// A PlusCal statement macro.
///
/// Declare it inside `Algorithm`, then call it inside a `Do` body. The macro
/// expands to formal statements in the same atomic step.
public struct StatementMacro: Sendable {
    private let parameterNames: [String]
    private let statements: [AlgorithmStatementModel]

    fileprivate init(parameterNames: [String], statements: [AlgorithmStatementModel]) {
        self.parameterNames = parameterNames
        self.statements = statements
    }

    public func callAsFunction<Value: TLAValueType>(_ argument: SharedVariable<Value>) -> [StepStatement] {
        expand([.variable(argument.name)])
    }

    public func callAsFunction<Value: TLAValueType>(_ argument: LocalVariable<Value>) -> [StepStatement] {
        expand([.variable(argument.name)])
    }

    /// Expands a macro with a formal expression. The expression is substituted
    /// into read positions only; a macro parameter assigned by its body still
    /// requires a variable argument.
    public func callAsFunction<Value: TLAValueType>(_ argument: Expr<Value>) -> [StepStatement] {
        expand([argument.raw])
    }

    /// Expands a macro using the current process identifier as its formal
    /// argument. The expansion stays in its surrounding atomic `Do` block.
    public func callAsFunction<Value: FiniteTLAValueDomain>(_ argument: ProcessIdentifier<Value>) -> [StepStatement] {
        expand([argument.stateExpr])
    }

    public func callAsFunction() -> [StepStatement] {
        expand([])
    }

    public func callAsFunction<First: TLAValueType, Second: TLAValueType>(
        _ first: SharedVariable<First>, _ second: SharedVariable<Second>
    ) -> [StepStatement] {
        expand([.variable(first.name), .variable(second.name)])
    }

    public func callAsFunction<First: TLAValueType, Second: TLAValueType>(
        _ first: LocalVariable<First>, _ second: LocalVariable<Second>
    ) -> [StepStatement] {
        expand([.variable(first.name), .variable(second.name)])
    }

    public func callAsFunction<First: TLAValueType, Second: TLAValueType>(
        _ first: SharedVariable<First>, _ second: LocalVariable<Second>
    ) -> [StepStatement] {
        expand([.variable(first.name), .variable(second.name)])
    }

    public func callAsFunction<First: TLAValueType, Second: TLAValueType>(
        _ first: LocalVariable<First>, _ second: SharedVariable<Second>
    ) -> [StepStatement] {
        expand([.variable(first.name), .variable(second.name)])
    }

    /// Expands a macro with formal expression arguments. This preserves the
    /// expressions in the algorithm IR instead of evaluating Swift values.
    public func callAsFunction<First: TLAValueType, Second: TLAValueType>(
        _ first: Expr<First>, _ second: Expr<Second>
    ) -> [StepStatement] {
        expand([first.raw, second.raw])
    }

    /// Expands a macro with any supported formal expressions. This is the
    /// general form for mixed variable and expression arguments.
    public func callAsFunction(_ arguments: any StateExprConvertible...) -> [StepStatement] {
        expand(arguments.map(\.stateExpr))
    }

    private func expand(_ arguments: [StateExpr]) -> [StepStatement] {
        guard parameterNames.count == arguments.count else {
            return [.init(model: .rejected(.statementMacroArgumentCount))]
        }
        return parameterNames.enumerated().reduce(statements) { expanded, binding in
            expanded.map {
                $0.substitutingVariable(
                    binding.element,
                    with: arguments[binding.offset],
                    assignmentTargets: .reject(.statementMacroAssignmentTarget)
                )
            }
        }.map(StepStatement.init(model:))
    }
}

/// Declares a one-argument PlusCal statement macro.
public func Macro<Value: TLAValueType>(
    @DoBuilder _ body: (MacroParameter<Value>) -> [StepStatement]
) -> StatementMacro {
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
) -> StatementMacro {
    let firstName = "__pcal_macro_parameter_0"
    let secondName = "__pcal_macro_parameter_1"
    return StatementMacro(
        parameterNames: [firstName, secondName],
        statements: body(MacroParameter(name: firstName), MacroParameter(name: secondName)).map(\.model)
    )
}

/// Declares a parameterless PlusCal statement macro.
public func Macro(@DoBuilder _ body: () -> [StepStatement]) -> StatementMacro {
    StatementMacro(parameterNames: [], statements: body().map(\.model))
}

/// A typed shared variable declaration.
///
/// Declare it through the scope supplied by `TLASpec` or `Algorithm`.
public struct SharedVariable<Value: TLAValueType>: StateExprConvertible, Sendable {
    fileprivate let name: String
    fileprivate let initialization: VariableInitialization
    fileprivate let swiftTypeName: String

    fileprivate init(name: String, initialization: VariableInitialization, swiftTypeName: String) {
        self.name = name
        self.initialization = initialization
        self.swiftTypeName = swiftTypeName
    }

    fileprivate init(name: String, initial: Value) {
        self.init(
            name: name,
            initialization: .value(initial.tlaValue),
            swiftTypeName: swiftSurfaceTypeName(for: Value.self)
        )
    }

    fileprivate init(name: String, in values: Expr<SetExpr<Value>>) {
        self.init(
            name: name,
            initialization: .memberOf(values.raw),
            swiftTypeName: swiftSurfaceTypeName(for: Value.self)
        )
    }

    fileprivate init(name: String, initial: Expr<Value>) {
        self.init(
            name: name,
            initialization: .expression(initial.raw),
            swiftTypeName: swiftSurfaceTypeName(for: Value.self)
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
    public func becomes(_ value: Expr<Value>) -> ActionExpr {
        .assign(.named(name), value.raw)
    }

    /// Assigns the current value of another shared formal variable of the
    /// same type. This keeps direct PlusCal-style state transfer typed.
    @discardableResult
    public func becomes(_ other: SharedVariable<Value>) -> ActionExpr {
        .assign(.named(name), other.stateExpr)
    }

    /// Assigns the current value of a process-local formal variable of the
    /// same type.
    @discardableResult
    public func becomes(_ other: LocalVariable<Value>) -> ActionExpr {
        .assign(.named(name), other.stateExpr)
    }

    public var stays: ActionExpr { .unchanged(.named(name)) }
}

/// A typed process-local algorithm variable.
///
/// Declare it through the scope supplied by `Each` or `Procedure`.
public struct LocalVariable<Value: TLAValueType>: StateExprConvertible, Sendable {
    fileprivate let name: String
    fileprivate let initialization: VariableInitialization
    fileprivate let swiftTypeName: String

    fileprivate init(name: String, initialization: VariableInitialization, swiftTypeName: String) {
        self.name = name
        self.initialization = initialization
        self.swiftTypeName = swiftTypeName
    }

    fileprivate init(name: String, initial: Value) {
        self.init(
            name: name,
            initialization: .value(initial.tlaValue),
            swiftTypeName: swiftSurfaceTypeName(for: Value.self)
        )
    }

    fileprivate init(name: String, initial: Expr<Value>) {
        self.init(
            name: name,
            initialization: .expression(initial.raw),
            swiftTypeName: swiftSurfaceTypeName(for: Value.self)
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
    public func becomes(_ value: Expr<Value>) -> ActionExpr {
        .assign(.named(name), value.raw)
    }

    @discardableResult
    public func becomes(_ other: SharedVariable<Value>) -> ActionExpr {
        .assign(.named(name), other.stateExpr)
    }

    @discardableResult
    public func becomes(_ other: LocalVariable<Value>) -> ActionExpr {
        .assign(.named(name), other.stateExpr)
    }

    public var stays: ActionExpr { .unchanged(.named(name)) }
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

}

// Process-local and shared formal variables use the same typed arithmetic
// surface. Their scopes determine lowering.
extension LocalVariable where Value == Int {
    public static func + (_ lhs: LocalVariable, _ rhs: Int) -> Expr<Int> {
        Expr(.add(lhs.stateExpr, .int(rhs)))
    }

    public static func - (_ lhs: LocalVariable, _ rhs: Int) -> Expr<Int> {
        Expr(.subtract(lhs.stateExpr, .int(rhs)))
    }

    public static func == (_ lhs: LocalVariable, _ rhs: Int) -> StateExpr {
        .equal(lhs.stateExpr, .int(rhs))
    }

    public static func != (_ lhs: LocalVariable, _ rhs: Int) -> StateExpr {
        .notEqual(lhs.stateExpr, .int(rhs))
    }
}

extension SharedVariable {
    public static func == (_ lhs: SharedVariable, _ rhs: Value) -> StateExpr {
        .equal(lhs.stateExpr, .value(rhs.tlaValue))
    }

    public static func != (_ lhs: SharedVariable, _ rhs: Value) -> StateExpr {
        .notEqual(lhs.stateExpr, .value(rhs.tlaValue))
    }

    public static func == (_ lhs: SharedVariable, _ rhs: Expr<Value>) -> StateExpr {
        .equal(lhs.stateExpr, rhs.raw)
    }

    public static func != (_ lhs: SharedVariable, _ rhs: Expr<Value>) -> StateExpr {
        .notEqual(lhs.stateExpr, rhs.raw)
    }

}

extension SharedVariable where Value: FiniteTLAValueDomain {
    public static func == (_ lhs: SharedVariable, _ rhs: ProcessIdentifier<Value>) -> StateExpr {
        .equal(lhs.stateExpr, rhs.stateExpr)
    }

    public static func != (_ lhs: SharedVariable, _ rhs: ProcessIdentifier<Value>) -> StateExpr {
        .notEqual(lhs.stateExpr, rhs.stateExpr)
    }

    public static func == (_ lhs: SharedVariable, _ rhs: WithValue<Value>) -> StateExpr {
        .equal(lhs.stateExpr, rhs.stateExpr)
    }

    public static func != (_ lhs: SharedVariable, _ rhs: WithValue<Value>) -> StateExpr {
        .notEqual(lhs.stateExpr, rhs.stateExpr)
    }
}

extension SharedVariable {
    public func contains<Element: TLAValueType>(_ element: Element) -> StateExpr
    where Value == SetExpr<Element> {
        .in(.value(element.tlaValue), stateExpr)
    }

    /// Tests membership of a value selected by `With`.
    public func contains<Element: TLAValueType>(_ element: WithValue<Element>) -> StateExpr
    where Value == SetExpr<Element> {
        .in(element.stateExpr, stateExpr)
    }

    /// Returns this shared formal set without `element`.
    public func removing<Element: TLAValueType>(_ element: Expr<Element>) -> Expr<SetExpr<Element>>
    where Value == SetExpr<Element> {
        Expr(.setDifference(stateExpr, .setLiteral([element.raw])))
    }

    public func appending<Element: TLAValueType>(_ element: Element) -> Expr<TupleExpr<Element>>
    where Value == TupleExpr<Element> {
        Expr(.tupleAppend(stateExpr, .value(element.tlaValue)))
    }

    public func at<Element: TLAValueType>(_ index: Int) -> Expr<Element>
    where Value == TupleExpr<Element> {
        Expr(.tupleAccess(stateExpr, index))
    }

    /// Reads a formal sequence at a one-based formal index.
    public subscript<Element: TLAValueType>(_ index: Expr<Int>) -> Expr<Element>
    where Value == TupleExpr<Element> {
        Expr(.tupleDynamicAccess(stateExpr, index.raw))
    }

    /// Reads a formal sequence at a one-based shared formal index.
    public subscript<Element: TLAValueType>(_ index: SharedVariable<Int>) -> Expr<Element>
    where Value == TupleExpr<Element> {
        Expr(.tupleDynamicAccess(stateExpr, index.stateExpr))
    }

    /// Reads a zero-based formal sequence at a formal index.
    public subscript<Element: TLAValueType>(_ index: Expr<Int>) -> Expr<Element>
    where Value == ZeroBasedSequence<Element> {
        Expr(.functionApply(stateExpr, index.raw))
    }

    public subscript<Element: TLAValueType>(_ index: Int) -> Expr<Element>
    where Value == ZeroBasedSequence<Element> {
        Expr(.functionApply(stateExpr, .int(index)))
    }

    /// Replaces one value in a zero-based formal sequence.
    public func updating<Element: TLAValueType>(
        _ index: Expr<Int>,
        to value: Expr<Element>
    ) -> Expr<ZeroBasedSequence<Element>> where Value == ZeroBasedSequence<Element> {
        Expr(.except(stateExpr, index.raw, value.raw))
    }

    public func updating<Element: TLAValueType>(
        _ index: Int,
        to value: Expr<Element>
    ) -> Expr<ZeroBasedSequence<Element>> where Value == ZeroBasedSequence<Element> {
        Expr(.except(stateExpr, .int(index), value.raw))
    }

    public subscript<Schema: TLARecordSchema, Field>(_ field: TLAField<Schema, Field>) -> Expr<Field>
    where Value == Record<Schema>, Field: TLAValueType {
        Expr<Field>(field.recordAccess(stateExpr))
    }

    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: Domain) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.tlaValue.stateExpr))
    }

    /// Reads a finite function at the current PlusCal process identifier.
    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: ProcessIdentifier<Domain>) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.stateExpr))
    }

    /// Reads a finite function using a process-local formal key.
    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: LocalVariable<Domain>) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.stateExpr))
    }

    /// Reads a finite function using a typed statement-macro parameter.
    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: MacroParameter<Domain>) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.stateExpr))
    }

    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: Expr<Domain>) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.raw))
    }

    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: WithValue<Domain>) -> Expr<Range>
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
    public func updating<Domain: FiniteTLAValueDomain, Range>(
        _ index: ProcessIdentifier<Domain>,
        _ update: (Expr<Range>) -> Expr<Range>
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        let selected = self[index]
        return Expr<Function<Domain, Range>>(
            .except(stateExpr, index.stateExpr, update(selected).raw)
        )
    }

    /// Replaces a finite function value at the current PlusCal process identifier.
    public func updating<Domain: FiniteTLAValueDomain, Range>(
        _ index: ProcessIdentifier<Domain>,
        to value: Expr<Range>
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Function<Domain, Range>>(.except(stateExpr, index.stateExpr, value.raw))
    }

    public func updating<Domain: FiniteTLAValueDomain, Range>(
        _ index: ProcessIdentifier<Domain>,
        to value: Range
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        updating(index, to: Expr<Range>(.value(value.tlaValue)))
    }

    /// Replaces a finite function value using a process-local formal key.
    public func updating<Domain: FiniteTLAValueDomain, Range>(
        _ index: LocalVariable<Domain>,
        to value: Expr<Range>
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Function<Domain, Range>>(.except(stateExpr, index.stateExpr, value.raw))
    }

    /// Replaces a finite function value using a typed statement-macro parameter.
    public func updating<Domain: FiniteTLAValueDomain, Range>(
        _ index: MacroParameter<Domain>,
        to value: Expr<Range>
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Function<Domain, Range>>(.except(stateExpr, index.stateExpr, value.raw))
    }

    /// Replaces a finite function value using a typed statement-macro parameter.
    public func updating<Domain: FiniteTLAValueDomain, Range>(
        _ index: MacroParameter<Domain>,
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

    public func updating<Domain: FiniteTLAValueDomain, Range>(
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

    /// Inserts the current identifier of a finite PlusCal process into a
    /// shared formal set.
    public func inserting<Element: FiniteTLAValueDomain>(_ element: ProcessIdentifier<Element>) -> Expr<SetExpr<Element>>
    where Value == SetExpr<Element> {
        Expr<SetExpr<Element>>(.union(stateExpr, .setLiteral([element.stateExpr])))
    }

    public func inserting<Element: FiniteTLAValueDomain>(_ element: WithValue<Element>) -> Expr<SetExpr<Element>>
    where Value == SetExpr<Element> {
        Expr<SetExpr<Element>>(.union(stateExpr, .setLiteral([element.stateExpr])))
    }

    public func removing<Element: TLAValueType>(_ element: Element) -> Expr<SetExpr<Element>>
    where Value == SetExpr<Element> {
        Expr<SetExpr<Element>>(.setDifference(stateExpr, .setLiteral([.value(element.tlaValue)])))
    }

    public func removing<Element: TLAValueType>(_ element: WithValue<Element>) -> Expr<SetExpr<Element>>
    where Value == SetExpr<Element> {
        Expr<SetExpr<Element>>(.setDifference(stateExpr, .setLiteral([element.stateExpr])))
    }

    public func contains<Element: TLAValueType>(_ element: Expr<Element>) -> StateExpr
    where Value == SetExpr<Element> {
        .in(element.raw, stateExpr)
    }
}

extension SharedVariable where Value: FormalZeroBasedSequenceValue {
    /// The formal number of elements in a zero-based sequence.
    public var count: Expr<Int> {
        Expr(.cardinality(.domain(stateExpr)))
    }
}

extension SharedVariable where Value: FormalSetValue {
    public var isEmpty: StateExpr {
        .equal(.cardinality(stateExpr), .value(.int(0)))
    }

    /// Tests whether this formal set is contained in another formal set.
    public func isSubset(of other: some StateExprConvertible) -> StateExpr {
        stateExpr.isSubset(of: other)
    }

    public var cardinality: Expr<Int> {
        Expr(.cardinality(stateExpr))
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
        Expr<Field>(field.recordAccess(stateExpr))
    }

    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: Domain) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.tlaValue.stateExpr))
    }

    /// Reads a finite function at the current PlusCal process identifier.
    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: ProcessIdentifier<Domain>) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.stateExpr))
    }

    public subscript<Domain: FiniteTLAValueDomain, Range>(_ index: Expr<Domain>) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.raw))
    }
}

extension LocalVariable where Value: FormalSetValue {
    /// Tests whether the current process-local formal set is empty.
    public var isEmpty: StateExpr {
        .equal(.cardinality(stateExpr), .value(.int(0)))
    }

    /// Returns this process-local set without a value selected by `With`.
    public func removing<Element: TLAValueType>(_ element: WithValue<Element>) -> Expr<SetExpr<Element>>
    where Value == SetExpr<Element> {
        Expr(.setDifference(stateExpr, .setLiteral([element.stateExpr])))
    }

    /// Returns this process-local set without another local formal value.
    public func removing<Element: TLAValueType>(_ element: Expr<Element>) -> Expr<SetExpr<Element>>
    where Value == SetExpr<Element> {
        Expr(.setDifference(stateExpr, .setLiteral([element.raw])))
    }
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

private struct SharedVariableDeclaration: Sendable {
    let name: String
    let initialization: VariableInitialization
    let swiftTypeName: String

    init<Value>(_ variable: SharedVariable<Value>) {
        name = variable.name
        initialization = variable.initialization
        swiftTypeName = variable.swiftTypeName
    }

    var algorithmElement: AlgorithmElement {
        AlgorithmElement(model: .shared(.init(
            root: name,
            initialization: initialization,
            swiftTypeName: swiftTypeName
        )))
    }

    var specificationDeclaration: VarDecl {
        switch initialization {
        case .value(let value):
            VarDecl(name, value, generatedSwiftType: swiftTypeName)
        case .expression(let expression):
            VarDecl(name, expression: expression, generatedSwiftType: swiftTypeName)
        case .memberOf(let set):
            VarDecl(name, memberOf: set, generatedSwiftType: swiftTypeName)
        }
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
        declarations.append(SharedVariableDeclaration(variable).specificationDeclaration)
        return variable
    }

    public func sharedVar(_ name: String, in range: ClosedRange<Int>) -> SharedVariable<Int> {
        let variable = SharedVariable<Int>(
            name: name,
            initialization: .memberOf(.setLiteral(range.map { .value(.int($0)) })),
            swiftTypeName: "Int"
        )
        declarations.append(SharedVariableDeclaration(variable).specificationDeclaration)
        return variable
    }

    public func sharedVar<Value: TLAValueType>(
        _ name: String,
        in values: Expr<SetExpr<Value>>
    ) -> SharedVariable<Value> {
        let variable = SharedVariable(name: name, in: values)
        declarations.append(SharedVariableDeclaration(variable).specificationDeclaration)
        return variable
    }

    public func sharedVar<Value: TLAValueType>(
        _ name: String,
        initial: Expr<Value>
    ) -> SharedVariable<Value> {
        let variable = SharedVariable(name: name, initial: initial)
        declarations.append(SharedVariableDeclaration(variable).specificationDeclaration)
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
        declarations.append(SharedVariableDeclaration(variable).algorithmElement)
        return variable
    }

    public func sharedVar(_ name: String, in range: ClosedRange<Int>) -> SharedVariable<Int> {
        let variable = SharedVariable<Int>(
            name: name,
            initialization: .memberOf(.setLiteral(range.map { .value(.int($0)) })),
            swiftTypeName: "Int"
        )
        declarations.append(SharedVariableDeclaration(variable).algorithmElement)
        return variable
    }

    public func sharedVar<Value: TLAValueType>(
        _ name: String,
        in values: Expr<SetExpr<Value>>
    ) -> SharedVariable<Value> {
        let variable = SharedVariable(name: name, in: values)
        declarations.append(SharedVariableDeclaration(variable).algorithmElement)
        return variable
    }

    public func sharedVar<Value: TLAValueType>(
        _ name: String,
        initial: Expr<Value>
    ) -> SharedVariable<Value> {
        let variable = SharedVariable(name: name, initial: initial)
        declarations.append(SharedVariableDeclaration(variable).algorithmElement)
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

    public func localVar<Value: TLAValueType>(_ name: String, initial: Expr<Value>) -> LocalVariable<Value> {
        let variable = LocalVariable(name: name, initial: initial)
        declarations.append(localDeclaration(variable))
        return variable
    }

    public func localVar(_ name: String, initial: StateExpr) -> LocalVariable<Bool> {
        let variable = LocalVariable<Bool>(name: name, initialization: .expression(initial), swiftTypeName: "Bool")
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

    public func localVar<Value: TLAValueType>(_ name: String, initial: Expr<Value>) -> LocalVariable<Value> {
        let variable = LocalVariable(name: name, initial: initial)
        declarations.append(localDeclaration(variable))
        return variable
    }

    public func localVar(_ name: String, initial: StateExpr) -> LocalVariable<Bool> {
        let variable = LocalVariable<Bool>(name: name, initialization: .expression(initial), swiftTypeName: "Bool")
        declarations.append(localDeclaration(variable))
        return variable
    }
}

private func localDeclaration<Value>(_ variable: LocalVariable<Value>) -> AlgorithmElement {
    AlgorithmElement(model: .local(.init(
        root: variable.name,
        initialization: variable.initialization,
        swiftTypeName: variable.swiftTypeName
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
public func StateConstraint(_ expression: some StateExprConvertible) -> AlgorithmElement {
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
    internal let model: AlgorithmModel

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

    internal init(model: AlgorithmModel) {
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
    _ condition: some StateExprConvertible,
    @DoBuilder _ body: () -> [StepStatement]
) -> AlgorithmElement where Name.RawValue == String {
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

/// A PlusCal assertion. A false assertion creates a generated formal safety
/// check at this atomic program-counter location.
public func Assert(_ condition: some StateExprConvertible) -> StepStatement {
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
    _ source: Expr<SetExpr<Value>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    let variable = generatedBinderName(file: file, line: line, column: column)
    let value = WithValue<Value>(expression: .variable(variable))
    return StepStatement(model: .with(variable: variable, source: source.raw, body(value).map(\.model)))
}

/// Binds two independent members for one atomic block.
///
/// This is the Swift spelling of PlusCal's `with (left \in Left; right \in Right)`.
/// It lowers to nested formal binders, so each choice remains independently
/// scoped and an empty source disables the whole block.
public func With<First: TLAValueType, Second: TLAValueType>(
    _ first: Expr<SetExpr<First>>,
    _ second: Expr<SetExpr<Second>>,
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
    _ first: Expr<SetExpr<First>>,
    _ second: Expr<SetExpr<Second>>,
    _ third: Expr<SetExpr<Third>>,
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
    _ first: Expr<SetExpr<First>>,
    _ second: Expr<SetExpr<Second>>,
    _ third: Expr<SetExpr<Third>>,
    _ fourth: Expr<SetExpr<Fourth>>,
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
    _ pairs: Expr<SetExpr<Pair<First, Second>>>,
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
    _ value: Expr<Value>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    let variable = generatedBinderName(file: file, line: line, column: column)
    let bound = WithValue<Value>(expression: .variable(variable))
    return StepStatement(model: .letBinding(variable: variable, value: value.raw, body(bound).map(\.model)))
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
public func Exists<Value: TLAValueType, Predicate: StateExprConvertible>(
    in domain: Expr<SetExpr<Value>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    where predicate: (WithValue<Value>) -> Predicate
) -> Expr<Bool> {
    let variable = generatedBinderName(file: file, line: line, column: column)
    return Expr(.exists(domain.raw, variable, predicate(WithValue(expression: .variable(variable))).stateExpr))
}

/// Tests a predicate for two independently bound members.
///
/// This is the Swift spelling of nested TLA+ existential quantifiers. The
/// nested AST preserves the same scope and short-circuit semantics as the
/// source language's multi-binder form.
public func Exists<First: TLAValueType, Second: TLAValueType, Predicate: StateExprConvertible>(
    in first: Expr<SetExpr<First>>,
    and second: Expr<SetExpr<Second>>,
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
public func ForAll<Value: TLAValueType, Predicate: StateExprConvertible>(
    in domain: Expr<SetExpr<Value>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    where predicate: (WithValue<Value>) -> Predicate
) -> Expr<Bool> {
    let variable = generatedBinderName(file: file, line: line, column: column)
    return Expr(.forAll(domain.raw, variable, predicate(WithValue(expression: .variable(variable))).stateExpr))
}

/// Tests a predicate for every pair of independently bound members.
public func ForAll<First: TLAValueType, Second: TLAValueType, Predicate: StateExprConvertible>(
    in first: Expr<SetExpr<First>>,
    and second: Expr<SetExpr<Second>>,
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

/// States that every member of a bounded formal set satisfies `predicate`.
///
/// This `All(in:)` form returns a formal condition directly, which makes it
/// natural inside `Invariant` and `When` blocks.
public func All<Value: TLAValueType, Predicate: StateExprConvertible>(
    in domain: Expr<SetExpr<Value>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    where predicate: (WithValue<Value>) -> Predicate
) -> StateExpr {
    let variable = generatedBinderName(file: file, line: line, column: column)
    return .forAll(domain.raw, variable, predicate(WithValue(expression: .variable(variable))).stateExpr)
}

/// States that a predicate holds for every independently chosen pair of
/// members from two bounded formal sets.
///
/// This is the direct condition-valued counterpart to `ForAll(in:and:where:)`.
/// It lowers to nested universal binders, preserving each binder's scope.
public func All<First: TLAValueType, Second: TLAValueType, Predicate: StateExprConvertible>(
    in first: Expr<SetExpr<First>>,
    and second: Expr<SetExpr<Second>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    where predicate: (WithValue<First>, WithValue<Second>) -> Predicate
) -> StateExpr {
    All(in: first, file: file, line: line, column: column) { firstValue in
        All(in: second, file: file, line: line, column: column + 1) { secondValue in
            predicate(firstValue, secondValue)
        }
    }
}

/// Tests a predicate for every member of a declared finite domain.
///
/// This is the typed Swift spelling of a bounded TLA+ `\\A value \\in Type`
/// predicate. It is useful for properties over a PlusCal process family.
public func All<Value: FiniteTLAValueDomain>(
    _ domain: FiniteDomain<Value>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    where predicate: (WithValue<Value>) -> StateExpr
) -> StateExpr {
    let variable = generatedBinderName(file: file, line: line, column: column)
    return .forAll(
        .setLiteral(domain.values.map { .value($0.tlaValue) }),
        variable,
        predicate(WithValue(expression: .variable(variable)))
    )
}

/// True when a process in the surrounding `Algorithm` has reached `Done`.
/// The program counter remains lowerer-owned; this avoids raw string-keyed
/// inspection of generated control state.
public func Finished() -> StateExpr {
    .equal(.programCounter, .controlLocation(.done))
}

/// True when one member of a process family has reached `Done`.
/// The program counter remains lowerer-owned; this avoids raw string-keyed
/// inspection of generated control state.
public func Finished<Value: FiniteTLAValueDomain>(_ process: WithValue<Value>) -> StateExpr {
    .equal(
        .functionApply(.programCounter, process.stateExpr),
        .controlLocation(.done)
    )
}

/// True when the current `Each` process has reached `Done`.
public func Finished<Value: FiniteTLAValueDomain>(_ process: ProcessIdentifier<Value>) -> StateExpr {
    .equal(
        .functionApply(.programCounter, process.stateExpr),
        .controlLocation(.done)
    )
}

/// True when one process is at a named PlusCal label.
///
/// This is the typed way to state properties about algorithm control flow.
/// The generated program counter remains an implementation detail.
public func At<Label: CaseIterable & RawRepresentable & Sendable, Value: FiniteTLAValueDomain>(
    _ label: Label,
    _ process: WithValue<Value>
) -> StateExpr where Label.RawValue == String {
    .equal(
        .functionApply(.programCounter, process.stateExpr),
        .controlLocation(.init(label.rawValue))
    )
}

/// True when the current `Each` process is at a named PlusCal label.
public func At<Label: CaseIterable & RawRepresentable & Sendable, Value: FiniteTLAValueDomain>(
    _ label: Label,
    _ process: ProcessIdentifier<Value>
) -> StateExpr where Label.RawValue == String {
    .equal(
        .functionApply(.programCounter, process.stateExpr),
        .controlLocation(.init(label.rawValue))
    )
}

public func With<Value: TLAValueType>(
    _ source: Var<SetExpr<Value>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    With(Expr<SetExpr<Value>>(source.stateExpr), file: file, line: line, column: column) { body($0) }
}

public func With<Value: TLAValueType>(
    _ source: SharedVariable<SetExpr<Value>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    With(Expr<SetExpr<Value>>(source.stateExpr), file: file, line: line, column: column) { body($0) }
}

/// Binds one member of a process-local formal set.
public func With<Value: TLAValueType>(
    _ source: LocalVariable<SetExpr<Value>>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    With(source.expr, file: file, line: line, column: column) { body($0) }
}

/// Binds one member of a finite Swift domain. This is the most direct Swift
/// spelling of PlusCal `with (value \in Type)`.
public func With<Value: FiniteTLAValueDomain>(
    _ source: FiniteDomain<Value>,
    file: StaticString = #fileID,
    line: UInt = #line,
    column: UInt = #column,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    let variable = generatedBinderName(file: file, line: line, column: column)
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

public func Assign<Value: TLAValueType>(
    _ parameter: MacroParameter<Value>,
    to value: some StateExprConvertible
) -> StepStatement {
    Assign(parameter.algorithmLValue, to: value)
}

public func If(
    _ condition: some StateExprConvertible,
    @DoBuilder _ then: () -> [StepStatement],
    @DoBuilder else otherwise: @escaping () -> [StepStatement] = { [] }
) -> StepStatement {
    StepStatement(model: .ifElse(condition.stateExpr, then().map(\.model), otherwise().map(\.model)))
}

/// Builds a typed formal conditional value.
///
/// This is distinct from the statement-builder `If(condition) { ... } else: { ... }` form.
public func If(
    _ condition: some StateExprConvertible,
    then: StateExpr,
    else otherwise: StateExpr
) -> StateExpr {
    .ifThenElse(condition.stateExpr, then.stateExpr, otherwise.stateExpr)
}

/// Builds a typed formal conditional value.
///
/// This is distinct from the statement-builder `If(condition) { ... } else: { ... }` form.
public func If<Value: TLAValueType>(
    _ condition: some StateExprConvertible,
    then: Value,
    else otherwise: Value
) -> Expr<Value> {
    Expr(.ifThenElse(condition.stateExpr, .value(then.tlaValue), .value(otherwise.tlaValue)))
}

public func If<Value: TLAValueType>(
    _ condition: some StateExprConvertible,
    then: Value,
    else otherwise: Expr<Value>
) -> Expr<Value> {
    Expr(.ifThenElse(condition.stateExpr, .value(then.tlaValue), otherwise.raw))
}

public func If<Value: TLAValueType>(
    _ condition: some StateExprConvertible,
    then: Expr<Value>,
    else otherwise: Value
) -> Expr<Value> {
    Expr(.ifThenElse(condition.stateExpr, then.raw, .value(otherwise.tlaValue)))
}

public func If<Value: TLAValueType>(
    _ condition: some StateExprConvertible,
    then: Expr<Value>,
    else otherwise: Expr<Value>
) -> Expr<Value> {
    Expr(.ifThenElse(condition.stateExpr, then.raw, otherwise.raw))
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

internal enum AlgorithmValidator {
    static func validate(_ model: AlgorithmModel) -> [AlgorithmDiagnostic] {
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
