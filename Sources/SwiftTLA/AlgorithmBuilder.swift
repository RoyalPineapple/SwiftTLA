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
        var result = Expr<SetExpr<Value>>(.setLiteral([]))
        for (index, candidate) in values.enumerated().reversed() {
            let earlier = Expr<SetExpr<Value>>(
                .setLiteral(values.prefix(index).map { .value($0.tlaValue) })
            )
            result = If(
                StateExpr.equal(current, .value(candidate.tlaValue)),
                then: earlier,
                else: result
            )
        }
        return result
    }
}

public struct ProcessIdentifier<Value: FiniteDomainKey>: StateExprConvertible, Sendable {
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
/// It exists only while constructing the algorithm IR. The lowerer turns it
/// into a scoped TLA+ action binding; it is never runtime Swift state.
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
        Expr<Field>(.recordAccess(stateExpr, field.name))
    }

    public subscript<Domain: FiniteDomainKey, Range>(_ index: WithValue<Domain>) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.stateExpr))
    }
}

extension Expr {
    /// Reads a finite function using a value selected by `With`.
    ///
    /// This keeps a scoped formal choice in the typed DSL; it is not a
    /// host-language dictionary lookup.
    public subscript<Domain: FiniteDomainKey, Range>(_ index: WithValue<Domain>) -> Expr<Range>
    where T == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(raw, index.stateExpr))
    }

    /// Reads a finite function using process-local formal state.
    public subscript<Domain: FiniteDomainKey, Range>(_ index: LocalVariable<Domain>) -> Expr<Range>
    where T == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(raw, index.stateExpr))
    }
}

extension Function where Domain: FiniteDomainKey {
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
/// A macro parameter is an authoring handle, not a Swift value. Its body is
/// substituted into the surrounding `Do` block before the algorithm lowers.
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

extension MacroParameter where Value: FiniteDomainKey {
    public static func == (lhs: MacroParameter, rhs: Value) -> StateExpr {
        .equal(lhs.stateExpr, rhs.tlaValue.stateExpr)
    }

    public static func != (lhs: MacroParameter, rhs: Value) -> StateExpr {
        .notEqual(lhs.stateExpr, rhs.tlaValue.stateExpr)
    }
}

/// A PlusCal statement macro.
///
/// Declare it inside `Algorithm`, then call it inside a `Do` body. The
/// macro is formal syntax: it expands to statements in the same atomic step;
/// it does not introduce a Swift function call or a separate transition.
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
    public func callAsFunction<Value: FiniteDomainKey>(_ argument: ProcessIdentifier<Value>) -> [StepStatement] {
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
        precondition(
            parameterNames.count == arguments.count,
            "What failed: statement macro invocation arity. Where: macro expansion. "
                + "Expected \(parameterNames.count) formal argument(s); found \(arguments.count). "
                + "What changed: no algorithm model was changed. Next safe action: pass the declared number of arguments."
        )
        return parameterNames.enumerated().reduce(statements) { expanded, binding in
            expanded.map {
                substituteMacroParameter($0, from: binding.element, with: arguments[binding.offset])
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

private func substituteMacroParameter(
    _ statement: AlgorithmStatementModel,
    from: String,
    to: String
) -> AlgorithmStatementModel {
    substituteMacroParameter(statement, from: from, with: .variable(to))
}

private func substituteMacroParameter(
    _ statement: AlgorithmStatementModel,
    from: String,
    with replacement: StateExpr
) -> AlgorithmStatementModel {
    func substitute(_ expression: StateExpr) -> StateExpr {
        StateExpr.substituteVariable(from, with: replacement, in: expression)
    }

    func substituteTarget(_ target: AlgorithmLValueModel) -> AlgorithmLValueModel {
        switch target {
        case .root(let root):
            guard root == from else { return .root(root) }
            guard case .variable(let replacementRoot) = replacement else {
                preconditionFailure(
                    "What failed: macro assignment-target substitution. Where: macro parameter '\(from)'. "
                        + "Expected a formal variable because the macro assigns to it; found \(replacement). "
                        + "What changed: no algorithm model was changed. Next safe action: pass a shared or local variable, "
                        + "or keep this parameter in read-only expressions."
                )
            }
            return .root(replacementRoot)
        case .function(let root, let key):
            let replacementRoot: String
            if root == from {
                guard case .variable(let name) = replacement else {
                    preconditionFailure(
                        "What failed: macro function-target substitution. Where: macro parameter '\(from)'. "
                            + "Expected a formal variable because the macro assigns through it; found \(replacement). "
                            + "What changed: no algorithm model was changed. Next safe action: pass a shared or local variable, "
                            + "or keep this parameter in read-only expressions."
                    )
                }
                replacementRoot = name
            } else {
                replacementRoot = root
            }
            return .function(root: replacementRoot, key: substitute(key))
        }
    }

    switch statement {
    case .await(let expression): return .await(substitute(expression))
    case .assert(let expression): return .assert(substitute(expression))
    case .set(let target, let value):
        return .set(target: substituteTarget(target), value: substitute(value))
    case .letBinding(let variable, let value, let body):
        let (scopedVariable, scopedBody) = captureSafeMacroBody(
            variable: variable,
            body: body,
            replacing: from,
            with: replacement
        )
        return .letBinding(
            variable: scopedVariable,
            value: substitute(value),
            scopedBody
        )
    case .with(let variable, let source, let body):
        let (scopedVariable, scopedBody) = captureSafeMacroBody(
            variable: variable,
            body: body,
            replacing: from,
            with: replacement
        )
        return .with(
            variable: scopedVariable,
            source: substitute(source),
            scopedBody
        )
    case .ifElse(let condition, let then, let otherwise):
        return .ifElse(
            substitute(condition),
            then.map { substituteMacroParameter($0, from: from, with: replacement) },
            otherwise.map { substituteMacroParameter($0, from: from, with: replacement) }
        )
    case .either(let first, let second):
        return .either(
            first.map { substituteMacroParameter($0, from: from, with: replacement) },
            second.map { substituteMacroParameter($0, from: from, with: replacement) }
        )
    case .choose(let variable, let domain, let body):
        let (scopedVariable, scopedBody) = captureSafeMacroBody(
            variable: variable,
            body: body,
            replacing: from,
            with: replacement
        )
        return .choose(
            variable: scopedVariable,
            domain: domain,
            scopedBody
        )
    case .call(let target, let arguments): return .call(target: target, arguments: arguments.map(substitute))
    case .goto, .return, .stop, .skip: return statement
    }
}

private func captureSafeMacroBody(
    variable: String,
    body: [AlgorithmStatementModel],
    replacing parameter: String,
    with replacement: StateExpr
) -> (String, [AlgorithmStatementModel]) {
    guard variable != parameter else { return (variable, body) }
    guard replacement.freeVariableNames.contains(variable) else {
        return (variable, body.map { substituteMacroParameter($0, from: parameter, with: replacement) })
    }
    let fresh = FreshVarName.fresh()
    let renamed = body.map { substituteMacroParameter($0, from: variable, with: .variable(fresh)) }
    return (fresh, renamed.map { substituteMacroParameter($0, from: parameter, with: replacement) })
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

    /// The typed expression for the current formal value.
    public var expr: Expr<Value> { Expr(stateExpr) }

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

    /// Assigns the current value of another shared formal variable of the
    /// same type. This keeps direct PlusCal-style state transfer typed.
    @discardableResult
    public func becomes(_ other: SharedVariable<Value>) -> ActionExpr {
        .assign(name, other.stateExpr)
    }

    /// Assigns the current value of a process-local formal variable of the
    /// same type.
    @discardableResult
    public func becomes(_ other: LocalVariable<Value>) -> ActionExpr {
        .assign(name, other.stateExpr)
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

    /// The typed expression for the current process-local formal value.
    public var expr: Expr<Value> { Expr(stateExpr) }

    /// Views this process-local declaration as the total function that PlusCal
    /// lowers over its process family. Use it for an algorithm property about
    /// all local values, such as `Range(ops)`, not for a current-process read.
    /// The marker is consumed by `AlgorithmLowerer`; it never becomes an
    /// application-facing raw state map.
    public func family<Process: FiniteDomainKey>(
        for _: Process.Type
    ) -> Expr<Function<Process, Value>> {
        Expr(.variable("\(algorithmLocalFamilyPrefix)\(name)"))
    }

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

    @discardableResult
    public func becomes(_ other: SharedVariable<Value>) -> ActionExpr {
        .assign(name, other.stateExpr)
    }

    @discardableResult
    public func becomes(_ other: LocalVariable<Value>) -> ActionExpr {
        .assign(name, other.stateExpr)
    }

    public var stays: ActionExpr { .unchanged(name) }
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

// A process-local formal variable reads like a shared formal variable. The
// distinction is scope and lowering, not an author-facing loss of arithmetic.
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

extension SharedVariable where Value: FiniteDomainKey {
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

    /// Reads a finite function using a process-local formal key.
    public subscript<Domain: FiniteDomainKey, Range>(_ index: LocalVariable<Domain>) -> Expr<Range>
    where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Range>(.functionApply(stateExpr, index.stateExpr))
    }

    /// Reads a finite function using a typed statement-macro parameter.
    public subscript<Domain: FiniteDomainKey, Range>(_ index: MacroParameter<Domain>) -> Expr<Range>
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

    /// Replaces a finite function value using a process-local formal key.
    public func updating<Domain: FiniteDomainKey, Range>(
        _ index: LocalVariable<Domain>,
        to value: Expr<Range>
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Function<Domain, Range>>(.except(stateExpr, index.stateExpr, value.raw))
    }

    /// Replaces a finite function value using a typed statement-macro parameter.
    public func updating<Domain: FiniteDomainKey, Range>(
        _ index: MacroParameter<Domain>,
        to value: Expr<Range>
    ) -> Expr<Function<Domain, Range>> where Value == Function<Domain, Range>, Range: TLAValueType {
        Expr<Function<Domain, Range>>(.except(stateExpr, index.stateExpr, value.raw))
    }

    /// Replaces a finite function value using a typed statement-macro parameter.
    public func updating<Domain: FiniteDomainKey, Range>(
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

    /// Inserts the current identifier of a finite PlusCal process into a
    /// shared formal set.
    public func inserting<Element: FiniteDomainKey>(_ element: ProcessIdentifier<Element>) -> Expr<SetExpr<Element>>
    where Value == SetExpr<Element> {
        Expr<SetExpr<Element>>(.union(stateExpr, .setLiteral([element.stateExpr])))
    }

    public func inserting<Element: FiniteDomainKey>(_ element: WithValue<Element>) -> Expr<SetExpr<Element>>
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

/// Declares a shared variable whose initial value is chosen from a static,
/// finite formal set. This is the typed form for records, enums, functions,
/// and other bounded formal values.
public func SharedVar<Value: TLAValueType>(in values: Expr<SetExpr<Value>>) -> SharedVariable<Value> {
    SharedVar("", in: values)
}

/// The named form used by the `#spec` declaration rewrite.
public func SharedVar<Value: TLAValueType>(
    _ name: String,
    in values: Expr<SetExpr<Value>>
) -> SharedVariable<Value> {
    // The initial domain is a formal expression, not Swift collection data.
    // Static sets keep a canonical declaration value for parser fidelity;
    // dependent domains (for example `ZSeq(CharacterSet)`) use the type's
    // neutral value solely as metadata. `initialSet` is the actual Init rule.
    let representative: TLAValue
    if case .set(let members) = try? values.raw.evaluate(in: [:]),
       let first = members.min(by: { $0.description < $1.description }) {
        representative = first
    } else {
        representative = Value.defaultValue.tlaValue
    }
    return SharedVariable(
        name: name,
        // `initialSet` supplies every initial state.
        initial: .value(representative),
        initialSet: values.raw,
        swiftTypeName: String(reflecting: Value.self)
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

/// Declares a process-local Boolean from a formal condition.
///
/// This is useful when a process starts in a role-dependent state, such as
/// one designated initiator being active while the other processes wait.
public func LocalVar(_ name: String, initial: StateExpr) -> LocalVariable<Bool> {
    LocalVariable(name: name, initial: initial, initialSet: nil, swiftTypeName: "Bool")
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
        [AlgorithmElement(model: .invariant(.init(name: component.name, body: component.body)))]
    }

    public static func buildExpression(_ component: TemporalDecl) -> [AlgorithmElement] {
        [AlgorithmElement(model: .temporal(.init(name: component.name, expr: component.expr)))]
    }

    public static func buildExpression(_ component: FairnessDecl) -> [AlgorithmElement] {
        [AlgorithmElement(model: .fairness(component.condition))]
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
        [AlgorithmElement(model: .stateConstraint(component.body))]
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

    public static func buildExpression(_ statements: [StepStatement]) -> [StepStatement] {
        statements
    }
}

public struct Algorithm: Sendable, SpecComponent {
    internal let model: AlgorithmModel

    public init(_ name: String, @AlgorithmBuilder _ body: () -> [AlgorithmElement]) {
        model = AlgorithmModel(name: name, components: body().map(\.model))
    }

    internal init(model: AlgorithmModel) {
        self.model = model
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
                typeName: String(describing: Value.self),
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

/// Invokes a declared PlusCal procedure from a sequential algorithm step.
/// Arguments are formal expressions evaluated in the caller's pre-state.
public func Call(_ target: String, with arguments: (any StateExprConvertible)... ) -> StepStatement {
    StepStatement(model: .call(target: target, arguments: arguments.map(\.stateExpr)))
}

/// Returns from the enclosing PlusCal procedure.
public func Return() -> StepStatement {
    StepStatement(model: .return)
}

public func Procedure(
    _ name: String,
    @AlgorithmBuilder _ body: () -> [AlgorithmElement]
) -> AlgorithmElement {
    let components = body().map(\.model)
    return AlgorithmElement(model: .procedure(.init(
        name: name,
        parameters: [],
        locals: components.compactMap { if case .local(let value) = $0 { value } else { nil } },
        steps: components.compactMap { if case .step(let value) = $0 { value } else { nil } }
    )))
}

public func Procedure<Value: TLAValueType>(
    _ name: String,
    parameters: Value.Type,
    @AlgorithmBuilder _ body: (ProcedureParameter<Value>) -> [AlgorithmElement]
) -> AlgorithmElement {
    let parameterName = "parameter0"
    let components = body(ProcedureParameter(name: parameterName)).map(\.model)
    return AlgorithmElement(model: .procedure(.init(
        name: name,
        parameters: [.init(root: parameterName, initial: .value(Value.defaultValue.tlaValue), swiftTypeName: String(reflecting: Value.self))],
        locals: components.compactMap { if case .local(let value) = $0 { value } else { nil } },
        steps: components.compactMap { if case .step(let value) = $0 { value } else { nil } }
    )))
}

public func Procedure<First: TLAValueType, Second: TLAValueType>(
    _ name: String, parameters: First.Type, _ second: Second.Type,
    @AlgorithmBuilder _ body: (ProcedureParameter<First>, ProcedureParameter<Second>) -> [AlgorithmElement]
) -> AlgorithmElement {
    let components = body(.init(name: "parameter0"), .init(name: "parameter1")).map(\.model)
    return AlgorithmElement(model: .procedure(.init(name: name, parameters: [
        .init(root: "parameter0", initial: .value(First.defaultValue.tlaValue), swiftTypeName: String(reflecting: First.self)),
        .init(root: "parameter1", initial: .value(Second.defaultValue.tlaValue), swiftTypeName: String(reflecting: Second.self))
    ], locals: components.compactMap { if case .local(let value) = $0 { value } else { nil } }, steps: components.compactMap { if case .step(let value) = $0 { value } else { nil } })))
}

public func Procedure<A: TLAValueType, B: TLAValueType, C: TLAValueType>(
    _ name: String, parameters: A.Type, _ b: B.Type, _ c: C.Type,
    @AlgorithmBuilder _ body: (ProcedureParameter<A>, ProcedureParameter<B>, ProcedureParameter<C>) -> [AlgorithmElement]
) -> AlgorithmElement {
    let components = body(.init(name: "parameter0"), .init(name: "parameter1"), .init(name: "parameter2")).map(\.model)
    return AlgorithmElement(model: .procedure(.init(name: name, parameters: [
        .init(root: "parameter0", initial: .value(A.defaultValue.tlaValue), swiftTypeName: String(reflecting: A.self)), .init(root: "parameter1", initial: .value(B.defaultValue.tlaValue), swiftTypeName: String(reflecting: B.self)), .init(root: "parameter2", initial: .value(C.defaultValue.tlaValue), swiftTypeName: String(reflecting: C.self))
    ], locals: components.compactMap { if case .local(let value) = $0 { value } else { nil } }, steps: components.compactMap { if case .step(let value) = $0 { value } else { nil } })))
}

public func Procedure<A: TLAValueType, B: TLAValueType, C: TLAValueType, D: TLAValueType>(
    _ name: String, parameters: A.Type, _ b: B.Type, _ c: C.Type, _ d: D.Type,
    @AlgorithmBuilder _ body: (ProcedureParameter<A>, ProcedureParameter<B>, ProcedureParameter<C>, ProcedureParameter<D>) -> [AlgorithmElement]
) -> AlgorithmElement {
    let components = body(.init(name: "parameter0"), .init(name: "parameter1"), .init(name: "parameter2"), .init(name: "parameter3")).map(\.model)
    return AlgorithmElement(model: .procedure(.init(name: name, parameters: [
        .init(root: "parameter0", initial: .value(A.defaultValue.tlaValue), swiftTypeName: String(reflecting: A.self)), .init(root: "parameter1", initial: .value(B.defaultValue.tlaValue), swiftTypeName: String(reflecting: B.self)), .init(root: "parameter2", initial: .value(C.defaultValue.tlaValue), swiftTypeName: String(reflecting: C.self)), .init(root: "parameter3", initial: .value(D.defaultValue.tlaValue), swiftTypeName: String(reflecting: D.self))
    ], locals: components.compactMap { if case .local(let value) = $0 { value } else { nil } }, steps: components.compactMap { if case .step(let value) = $0 { value } else { nil } })))
}

/// Binds a nondeterministically chosen member of a bounded formal set for one
/// atomic block. An empty set disables that block, as PlusCal `with (x \in S)`.
public func With<Value: TLAValueType>(
    _ source: Expr<SetExpr<Value>>,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    let variable = FreshVarName.fresh()
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
    @DoBuilder _ body: (WithValue<First>, WithValue<Second>) -> [StepStatement]
) -> StepStatement {
    With(first) { firstValue in
        With(second) { secondValue in
            body(firstValue, secondValue)
        }
    }
}

/// Binds three independent members in formal left-to-right scope order.
public func With<First: TLAValueType, Second: TLAValueType, Third: TLAValueType>(
    _ first: Expr<SetExpr<First>>,
    _ second: Expr<SetExpr<Second>>,
    _ third: Expr<SetExpr<Third>>,
    @DoBuilder _ body: (WithValue<First>, WithValue<Second>, WithValue<Third>) -> [StepStatement]
) -> StepStatement {
    With(first) { firstValue in
        With(second) { secondValue in
            With(third) { thirdValue in
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
    @DoBuilder _ body: (WithValue<First>, WithValue<Second>, WithValue<Third>, WithValue<Fourth>) -> [StepStatement]
) -> StepStatement {
    With(first, second, third) { firstValue, secondValue, thirdValue in
        With(fourth) { fourthValue in
            body(firstValue, secondValue, thirdValue, fourthValue)
        }
    }
}

/// Destructures a selected two-member formal tuple for one atomic block.
///
/// This is the typed Swift spelling of PlusCal's
/// `with <<first, second>> \in Pairs`. The generated bindings are still
/// formal expressions and never become host-language tuple values.
public func With<First: TLAValueType, Second: TLAValueType>(
    _ pairs: Expr<SetExpr<Pair<First, Second>>>,
    @DoBuilder _ body: (WithValue<First>, WithValue<Second>) -> [StepStatement]
) -> StepStatement {
    With(pairs) { pair in
        Let(pair.first()) { first in
            Let(pair.second()) { second in
                body(first, second)
            }
        }
    }
}

/// Binds a deterministic formal value for one atomic block.
///
/// This is PlusCal's `with name = expression` form, not membership selection.
/// It lowers to a scoped TLA+ `LET name == expression IN ...` expression.
public func Let<Value: TLAValueType>(
    _ value: Expr<Value>,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    let variable = FreshVarName.fresh()
    let bound = WithValue<Value>(expression: .variable(variable))
    return StepStatement(model: .letBinding(variable: variable, value: value.raw, body(bound).map(\.model)))
}

public func Let<Value: TLAValueType>(
    _ value: Value,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    Let(Expr<Value>(.value(value.tlaValue)), body)
}

/// Tests whether a bounded formal set has a member that satisfies `predicate`.
///
/// This is the typed Swift spelling of TLA+ `\\E value \\in domain : predicate`.
/// The bound value is formal data, not a Swift collection element.
public func Exists<Value: TLAValueType, Predicate: StateExprConvertible>(
    in domain: Expr<SetExpr<Value>>,
    where predicate: (WithValue<Value>) -> Predicate
) -> Expr<Bool> {
    let variable = FreshVarName.fresh()
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
    where predicate: (WithValue<First>, WithValue<Second>) -> Predicate
) -> Expr<Bool> {
    Exists(in: first) { firstValue in
        Exists(in: second) { secondValue in
            predicate(firstValue, secondValue)
        }
    }
}

/// Tests whether every bounded formal set member satisfies `predicate`.
///
/// This is the typed Swift spelling of TLA+ `\\A value \\in domain : predicate`.
public func ForAll<Value: TLAValueType, Predicate: StateExprConvertible>(
    in domain: Expr<SetExpr<Value>>,
    where predicate: (WithValue<Value>) -> Predicate
) -> Expr<Bool> {
    let variable = FreshVarName.fresh()
    return Expr(.forAll(domain.raw, variable, predicate(WithValue(expression: .variable(variable))).stateExpr))
}

/// Tests a predicate for every pair of independently bound members.
public func ForAll<First: TLAValueType, Second: TLAValueType, Predicate: StateExprConvertible>(
    in first: Expr<SetExpr<First>>,
    and second: Expr<SetExpr<Second>>,
    where predicate: (WithValue<First>, WithValue<Second>) -> Predicate
) -> Expr<Bool> {
    ForAll(in: first) { firstValue in
        ForAll(in: second) { secondValue in
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
    where predicate: (WithValue<Value>) -> Predicate
) -> StateExpr {
    let variable = FreshVarName.fresh()
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
    where predicate: (WithValue<First>, WithValue<Second>) -> Predicate
) -> StateExpr {
    All(in: first) { firstValue in
        All(in: second) { secondValue in
            predicate(firstValue, secondValue)
        }
    }
}

/// Tests a predicate for every member of a declared finite domain.
///
/// This is the typed Swift spelling of a bounded TLA+ `\\A value \\in Type`
/// predicate. It is useful for properties over a PlusCal process family.
public func All<Value: FiniteDomainKey>(
    _ domain: FiniteDomain<Value>,
    where predicate: (WithValue<Value>) -> StateExpr
) -> StateExpr {
    let variable = FreshVarName.fresh()
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
    .equal(.variable("pc"), .value(.string("Done")))
}

/// True when one member of a process family has reached `Done`.
/// The program counter remains lowerer-owned; this avoids raw string-keyed
/// inspection of generated control state.
public func Finished<Value: FiniteDomainKey>(_ process: WithValue<Value>) -> StateExpr {
    .equal(
        .functionApply(.variable("pc"), process.stateExpr),
        .value(.string("Done"))
    )
}

/// True when the current `Each` process has reached `Done`.
public func Finished<Value: FiniteDomainKey>(_ process: ProcessIdentifier<Value>) -> StateExpr {
    .equal(
        .functionApply(.variable("pc"), process.stateExpr),
        .value(.string("Done"))
    )
}

/// True when one process is at a named PlusCal label.
///
/// This is the typed way to state properties about algorithm control flow.
/// The generated program counter remains an implementation detail.
public func At<Label: PlusCalLabel & RawRepresentable, Value: FiniteDomainKey>(
    _ label: Label,
    _ process: WithValue<Value>
) -> StateExpr where Label.RawValue == String {
    .equal(
        .functionApply(.variable("pc"), process.stateExpr),
        .value(.string(label.rawValue))
    )
}

/// True when the current `Each` process is at a named PlusCal label.
public func At<Label: PlusCalLabel & RawRepresentable, Value: FiniteDomainKey>(
    _ label: Label,
    _ process: ProcessIdentifier<Value>
) -> StateExpr where Label.RawValue == String {
    .equal(
        .functionApply(.variable("pc"), process.stateExpr),
        .value(.string(label.rawValue))
    )
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

/// Binds one member of a process-local formal set.
public func With<Value: TLAValueType>(
    _ source: LocalVariable<SetExpr<Value>>,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    With(source.expr, body)
}

/// Binds one member of a finite Swift domain. This is the most direct Swift
/// spelling of PlusCal `with (value \in Type)`.
public func With<Value: FiniteDomainKey>(
    _ source: FiniteDomain<Value>,
    @DoBuilder _ body: (WithValue<Value>) -> [StepStatement]
) -> StepStatement {
    let variable = FreshVarName.fresh()
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

public func Choose<Value: FiniteDomainKey>(
    _ domain: FiniteDomain<Value>,
    @DoBuilder _ body: (ProcessIdentifier<Value>) -> [StepStatement]
) -> StepStatement {
    let name = FreshVarName.fresh()
    let value = ProcessIdentifier<Value>(expression: .variable(name))
    return StepStatement(model: .choose(variable: name, domain: domain.values.map(\.tlaValue), body(value).map(\.model)))
}

/// Binds an ordered pair of values from finite domains. This lowers to nested
/// PlusCal choices, so the second binder is scoped inside the first.
public func Choose<First: FiniteDomainKey, Second: FiniteDomainKey>(
    _ firstDomain: FiniteDomain<First>,
    _ secondDomain: FiniteDomain<Second>,
    @DoBuilder _ body: (ProcessIdentifier<First>, ProcessIdentifier<Second>) -> [StepStatement]
) -> StepStatement {
    let firstName = FreshVarName.fresh()
    let secondName = FreshVarName.fresh()
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
/// when a TLC configuration supplies the finite range. The range is formal
/// data: the closure describes one choice branch, not a Swift loop.
public func Choose(
    _ domain: ClosedRange<Int>,
    @DoBuilder _ body: (WithValue<Int>) -> [StepStatement]
) -> StepStatement {
    let name = FreshVarName.fresh()
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
    @DoBuilder _ body: (WithValue<Int>, WithValue<Int>) -> [StepStatement]
) -> StepStatement {
    let firstName = FreshVarName.fresh()
    let secondName = FreshVarName.fresh()
    let first = WithValue<Int>(expression: .variable(firstName))
    let second = WithValue<Int>(expression: .variable(secondName))
    return StepStatement(model: .choose(
        variable: firstName,
        domain: firstDomain.map(TLAValue.int),
        [.choose(variable: secondName, domain: secondDomain.map(TLAValue.int), body(first, second).map(\.model))]
    ))
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
        diagnostics += AlgorithmProcedureValidator.procedureDiagnostics(for: model)

        // PlusCal has two distinct control shapes: a `begin` body with one
        // scalar pc, and a process set with a function-valued pc. Mixing them
        // would silently invent a third semantics, so reject it.
        if !model.processes.isEmpty, !model.sequentialSteps.isEmpty {
            diagnostics.append(AlgorithmDiagnostic(.invalidAlgorithmComponent, at: .algorithm))
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
                validate(process, index: index, diagnostics: &diagnostics)
            case .procedure:
                break
            case .invariant(let invariant):
                validateName(invariant.name, at: .algorithm, diagnostics: &diagnostics)
            case .temporal(let temporal):
                validateName(temporal.name, at: .algorithm, diagnostics: &diagnostics)
            case .fairness:
                break
            case .stateConstraint:
                break
            case .propertyBoundary:
                diagnostics.append(AlgorithmDiagnostic(.propertyBoundary, at: .algorithm))
            case .step(let step):
                validateSequential(step, labels: Set(model.sequentialSteps.map(\.label.name)), diagnostics: &diagnostics)
            case .local:
                diagnostics.append(AlgorithmDiagnostic(.invalidAlgorithmComponent, at: .algorithm))
            }
        }
        return diagnostics
    }

    private static func validateSequential(
        _ step: AlgorithmStepModel,
        labels: Set<String>,
        diagnostics: inout [AlgorithmDiagnostic]
    ) {
        let allSteps = labels
        validateName(step.label.name, at: .algorithm, diagnostics: &diagnostics)
        let paths = writePaths(step.statements)
        if paths.contains(where: { Set($0).count != $0.count }) {
            diagnostics.append(AlgorithmDiagnostic(.duplicateRootWrite, at: .algorithm))
        }
        validateStatements(step.statements, at: .algorithm, labels: allSteps, diagnostics: &diagnostics)
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
            case .invariant(let invariant):
                validateName(invariant.name, at: processAnchor, diagnostics: &diagnostics)
            case .temporal, .fairness, .stateConstraint, .propertyBoundary:
                diagnostics.append(AlgorithmDiagnostic(.propertyBoundary, at: processAnchor))
            case .shared, .process, .procedure:
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
            case .letBinding(_, _, let body), .with(_, _, let body):
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
            case .call, .return:
                break
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
            case .await, .assert, .goto, .call, .return, .stop, .skip:
                statementPaths = [[]]
            case .letBinding(_, _, let body), .with(_, _, let body):
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
