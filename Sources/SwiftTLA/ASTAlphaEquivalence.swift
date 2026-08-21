/// Compares parsed models by formal meaning.
///
/// All model declarations, action names, operators, literals, updates, and
/// free variables compare exactly. Only names introduced by a local binder
/// (`\A`, `\E`, `CHOOSE`, function literals, filters, and action-local
/// bindings) may differ.
public func _tlaAlphaEquivalent(_ lhs: TLASpec, _ rhs: TLASpec) -> Bool {
    guard lhs.variables.elementsEqual(rhs.variables, by: variablesEquivalent),
          lhs.actions.count == rhs.actions.count,
          lhs.invariants.count == rhs.invariants.count,
          lhs.temporalProperties.count == rhs.temporalProperties.count,
          lhs.fairness == rhs.fairness,
          lhs.imports.map(\.compilationFingerprint) == rhs.imports.map(\.compilationFingerprint),
          lhs.importConfigurations == rhs.importConfigurations,
          lhs.moduleInstances == rhs.moduleInstances,
          lhs.formalParameters == rhs.formalParameters,
          lhs.symmetrySets == rhs.symmetrySets,
          formalOperatorDefinitionsEquivalent(lhs.formalOperatorDefinitions, rhs.formalOperatorDefinitions),
          lhs.definitions == rhs.definitions,
          optionalStateEquivalent(lhs.constraint, rhs.constraint)
    else { return false }

    for (left, right) in zip(lhs.actions, rhs.actions) {
        guard left.name == right.name, left.bindings == right.bindings,
              alphaKey(left.body) == alphaKey(right.body)
        else { return false }
    }
    for (left, right) in zip(lhs.invariants, rhs.invariants) {
        guard left.name == right.name, alphaKey(left.body) == alphaKey(right.body) else { return false }
    }
    for (left, right) in zip(lhs.temporalProperties, rhs.temporalProperties) {
        guard left.name == right.name, alphaKey(left.expr) == alphaKey(right.expr) else { return false }
    }
    return true
}

/// Structured evidence for a parser-to-builder fidelity difference.
///
/// A failed comparison never changes the built specification. This value keeps
/// the first differing formal component intact so a macro diagnostic, test,
/// or caller can report more than an unqualified "tree mismatch".
public struct TLAParserFidelityDiagnostic: Error, Sendable, Hashable, CustomStringConvertible {
    public struct SourceSpan: Sendable, Hashable, CustomStringConvertible {
        public let utf8Offset: Int?
        public let utf8Length: Int?

        public init(utf8Offset: Int? = nil, utf8Length: Int? = nil) {
            self.utf8Offset = utf8Offset
            self.utf8Length = utf8Length
        }

        public var description: String {
            guard let utf8Offset, let utf8Length else { return "source span unavailable" }
            return "UTF-8 offset \(utf8Offset), length \(utf8Length)"
        }
    }

    public enum Location: Sendable, Hashable, CustomStringConvertible {
        /// Parser and builder trees do not retain SwiftSyntax nodes after
        /// expansion. The semantic path identifies the precise formal node.
        case semanticPath(String)

        public var description: String {
            switch self {
            case .semanticPath(let path): return path
            }
        }
    }

    public enum ChangeStatus: String, Sendable, Hashable {
        case noSpecificationWasCommitted
    }

    public let whatFailed: String
    public let location: Location
    public let sourceSpan: SourceSpan
    public let expected: String
    public let actual: String
    public let changeStatus: ChangeStatus
    public let nextSafeAction: String

    public init(
        whatFailed: String,
        location: Location,
        sourceSpan: SourceSpan = .init(),
        expected: String,
        actual: String,
        changeStatus: ChangeStatus = .noSpecificationWasCommitted,
        nextSafeAction: String
    ) {
        self.whatFailed = whatFailed
        self.location = location
        self.sourceSpan = sourceSpan
        self.expected = expected
        self.actual = actual
        self.changeStatus = changeStatus
        self.nextSafeAction = nextSafeAction
    }

    public var description: String {
        "Parser fidelity check did not agree. What failed: \(whatFailed). Where: \(location), \(sourceSpan). "
            + "Expected: \(expected). Actual: \(actual). "
            + "Change status: \(changeStatus.rawValue). Next safe action: \(nextSafeAction)"
    }
}

/// Returns the first semantic difference that remains after normalization.
///
/// The parser tree intentionally has no retained SwiftSyntax node at this
/// boundary, so `location` is a stable semantic path. Macro diagnostics still
/// point at the original declaration; callers can inspect this value for the
/// expected and actual formal trees without scraping text.
public func _tlaFidelityEvidence(
    _ expected: TLASpec,
    _ actual: TLASpec
) -> TLAParserFidelityDiagnostic? {
    func difference(
        _ whatFailed: String,
        at path: String,
        expected expectedValue: String,
        actual actualValue: String,
        next: String = "Inspect this declaration in the #spec body, then make the builder and parser spell the same formal construct."
    ) -> TLAParserFidelityDiagnostic {
        TLAParserFidelityDiagnostic(
            whatFailed: whatFailed,
            location: .semanticPath(path),
            expected: expectedValue,
            actual: actualValue,
            nextSafeAction: next
        )
    }

    guard expected.imports.map(\.compilationFingerprint) == actual.imports.map(\.compilationFingerprint) else {
        return difference("imported module list differs", at: "imports", expected: "\(expected.imports.map(\.name))", actual: "\(actual.imports.map(\.name))")
    }
    guard expected.importConfigurations == actual.importConfigurations else {
        return difference("import configuration differs", at: "importConfigurations", expected: "\(expected.importConfigurations)", actual: "\(actual.importConfigurations)")
    }
    guard expected.moduleInstances == actual.moduleInstances else {
        return difference("named module instance differs", at: "moduleInstances", expected: "\(expected.moduleInstances)", actual: "\(actual.moduleInstances)")
    }
    guard expected.formalParameters == actual.formalParameters else {
        return difference("formal module parameter differs", at: "formalParameters", expected: "\(expected.formalParameters)", actual: "\(actual.formalParameters)")
    }
    guard expected.symmetrySets == actual.symmetrySets else {
        return difference("symmetry set differs", at: "symmetrySets", expected: "\(expected.symmetrySets)", actual: "\(actual.symmetrySets)")
    }
    guard formalOperatorDefinitionsEquivalent(
        expected.formalOperatorDefinitions,
        actual.formalOperatorDefinitions
    ) else {
        let sharedCount = min(
            expected.formalOperatorDefinitions.count,
            actual.formalOperatorDefinitions.count
        )
        for index in 0..<sharedCount {
            let expectedDefinition = expected.formalOperatorDefinitions[index]
            let actualDefinition = actual.formalOperatorDefinitions[index]
            guard formalOperatorDefinitionEquivalent(expectedDefinition, actualDefinition) else {
                return difference(
                    "formal operator definition differs after alpha normalization",
                    at: "formalOperatorDefinitions[\(index)] (\(expectedDefinition.name))",
                    expected: formalOperatorDefinitionKey(expectedDefinition),
                    actual: formalOperatorDefinitionKey(actualDefinition),
                    next: "Inspect this FormalDefinition in the #spec body, then make its parameters and body match the parser's formal definition."
                )
            }
        }
        return difference(
            "formal operator definition count differs",
            at: "formalOperatorDefinitions",
            expected: "\(expected.formalOperatorDefinitions.count) definitions",
            actual: "\(actual.formalOperatorDefinitions.count) definitions",
            next: "Inspect FormalDefinition declarations in the #spec body and retain every formal operator in the builder tree."
        )
    }
    guard expected.definitions == actual.definitions else {
        return difference(
            "source-only definition differs",
            at: "definitions",
            expected: "\(expected.definitions)",
            actual: "\(actual.definitions)",
            next: "Inspect Definition declarations in the #spec body and retain each literal declaration."
        )
    }
    guard expected.variables.elementsEqual(actual.variables, by: variablesEquivalent) else {
        let sharedCount = min(expected.variables.count, actual.variables.count)
        for index in 0..<sharedCount {
            let expectedVariable = expected.variables[index]
            let actualVariable = actual.variables[index]
            guard variablesEquivalent(expectedVariable, actualVariable) else {
                return difference(
                    "variable declaration differs",
                    at: "variables[\(index)]",
                    expected: "name '\(expectedVariable.name)', initial \(expectedVariable.initial), domain \(String(describing: expectedVariable.initialSet))",
                    actual: "name '\(actualVariable.name)', initial \(actualVariable.initial), domain \(String(describing: actualVariable.initialSet))"
                )
            }
        }
        return difference("variable count differs", at: "variables", expected: "\(expected.variables.count) declarations", actual: "\(actual.variables.count) declarations")
    }
    guard expected.actions.count == actual.actions.count else {
        return difference("action count differs", at: "actions", expected: "\(expected.actions.count) actions", actual: "\(actual.actions.count) actions")
    }
    for (index, pair) in zip(expected.actions, actual.actions).enumerated() {
        let (left, right) = pair
        guard left.name == right.name else {
            return difference("action name or order differs", at: "actions[\(index)]", expected: "action '\(left.name)'", actual: "action '\(right.name)'")
        }
        guard left.bindings == right.bindings else {
            return difference("action finite bindings differ", at: "actions[\(index)].bindings", expected: "\(left.bindings)", actual: "\(right.bindings)")
        }
        let expectedKey = alphaKey(left.body)
        let actualKey = alphaKey(right.body)
        guard expectedKey == actualKey else {
            return difference("action body differs after alpha normalization", at: "actions[\(index)].body (\(left.name))", expected: expectedKey, actual: actualKey)
        }
    }
    guard expected.invariants.count == actual.invariants.count else {
        return difference("invariant count differs", at: "invariants", expected: "\(expected.invariants.count) invariants", actual: "\(actual.invariants.count) invariants")
    }
    for (index, pair) in zip(expected.invariants, actual.invariants).enumerated() {
        let (left, right) = pair
        guard left.name == right.name else {
            return difference("invariant name or order differs", at: "invariants[\(index)]", expected: "invariant '\(left.name)'", actual: "invariant '\(right.name)'")
        }
        let expectedKey = alphaKey(left.body)
        let actualKey = alphaKey(right.body)
        guard expectedKey == actualKey else {
            return difference("invariant body differs after alpha normalization", at: "invariants[\(index)].body (\(left.name))", expected: expectedKey, actual: actualKey)
        }
    }
    guard expected.temporalProperties.count == actual.temporalProperties.count else {
        return difference("temporal property count differs", at: "temporal", expected: "\(expected.temporalProperties.count) properties", actual: "\(actual.temporalProperties.count) properties")
    }
    for (index, pair) in zip(expected.temporalProperties, actual.temporalProperties).enumerated() {
        let (left, right) = pair
        guard left.name == right.name else {
            return difference("temporal property name or order differs", at: "temporal[\(index)]", expected: "property '\(left.name)'", actual: "property '\(right.name)'")
        }
        let expectedKey = alphaKey(left.expr)
        let actualKey = alphaKey(right.expr)
        guard expectedKey == actualKey else {
            return difference("temporal property differs after alpha normalization", at: "temporal[\(index)] (\(left.name))", expected: expectedKey, actual: actualKey)
        }
    }
    guard expected.fairness == actual.fairness else {
        return difference("fairness declarations differ", at: "fairness", expected: "\(expected.fairness)", actual: "\(actual.fairness)")
    }
    guard optionalStateEquivalent(expected.constraint, actual.constraint) else {
        return difference("state constraint differs after alpha normalization", at: "constraint", expected: "\(String(describing: expected.constraint))", actual: "\(String(describing: actual.constraint))")
    }
    return nil
}

private func optionalStateEquivalent(_ lhs: StateExpr?, _ rhs: StateExpr?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
        true
    case let (.some(left), .some(right)):
        alphaKey(left) == alphaKey(right)
    case (nil, .some), (.some, nil):
        false
    }
}

private func variablesEquivalent(_ lhs: NamedVar, _ rhs: NamedVar) -> Bool {
    guard lhs.name == rhs.name,
          lhs.initial == rhs.initial,
          lhs.collectionType == rhs.collectionType,
          optionalStateEquivalent(lhs.initExpr, rhs.initExpr),
          optionalStateEquivalent(lhs.lazySet, rhs.lazySet)
    else { return false }
    switch (lhs.initialSet, rhs.initialSet) {
    case (nil, nil): return true
    case let (.some(left), .some(right)): return alphaKey(left) == alphaKey(right)
    case (nil, .some), (.some, nil): return false
    }
}

private func formalOperatorDefinitionsEquivalent(
    _ lhs: [FormalOperatorDefinition],
    _ rhs: [FormalOperatorDefinition]
) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { left, right in
        formalOperatorDefinitionEquivalent(left, right)
    }
}

private func formalOperatorDefinitionEquivalent(
    _ lhs: FormalOperatorDefinition,
    _ rhs: FormalOperatorDefinition
) -> Bool {
    formalOperatorDefinitionKey(lhs) == formalOperatorDefinitionKey(rhs)
}

private func formalOperatorDefinitionKey(_ definition: FormalOperatorDefinition) -> String {
    var next = 0
    var environment: [String: String] = [:]
    let parameters = definition.parameters.map { parameter -> String in
        let (canonical, extended) = fresh(parameter.name, environment: environment, next: &next)
        environment = extended
        switch parameter {
        case .value:
            return "value:\(canonical)"
        case .operator(_, let arity):
            return "operator:\(canonical)/\(arity)"
        }
    }
    return "definition(\(definition.name),parameters:[\(parameters.joined(separator: ","))],body:\(stateKey(definition.body, environment: environment, next: &next)))"
}

private func alphaKey(_ action: ActionExpr) -> String {
    var next = 0
    let branches = semanticBranches(action)
    return "or[\(branches.map { actionKey($0, environment: [:], next: &next) }.joined(separator: ","))]"
}

/// Gives action disjunction one canonical representation. In particular,
/// `(a \/ b) /\ c` and `(a /\ c) \/ (b /\ c)` are the same transition
/// relation, whether the disjunction originated as a Swift boolean guard or
/// as an `ActionBuilder` branch.
private func semanticBranches(_ action: ActionExpr) -> [ActionExpr] {
    switch action {
    case .or(let left, let right):
        return semanticBranches(left) + semanticBranches(right)
    case .guard_(let condition):
        return semanticStateBranches(condition).map(ActionExpr.guard_)
    case .and(let left, let right):
        return semanticBranches(left).flatMap { leftBranch in
            semanticBranches(right).map { rightBranch in .and(leftBranch, rightBranch) }
        }
    case .ifElse(let condition, let then, let otherwise):
        return semanticBranches(.and(.guard_(condition), then))
            + semanticBranches(.and(.guard_(.not(condition)), otherwise))
    case .existsAction(let variable, let set, let body):
        return semanticBranches(body).map { .existsAction(variable, set, $0) }
    case .define(let variable, let value, let body):
        return semanticBranches(body).map { .define(variable, value, $0) }
    default:
        return [action]
    }
}

/// Splits only disjunctions that occur inside a Boolean guard. Swift can group
/// `a && (b || c)` into one `StateExpr` before that condition meets an action
/// update, while the syntax parser retains separate action guards. Both spell
/// the same transition relation.
private func semanticStateBranches(_ expression: StateExpr) -> [StateExpr] {
    switch expression {
    case .or(let left, let right):
        return semanticStateBranches(left) + semanticStateBranches(right)
    case .and(let left, let right):
        return semanticStateBranches(left).flatMap { leftBranch in
            semanticStateBranches(right).map { rightBranch in
                .and(leftBranch, rightBranch)
            }
        }
    default:
        return [expression]
    }
}

func alphaKey(_ expression: StateExpr) -> String {
    var next = 0
    return stateKey(expression, environment: [:], next: &next)
}

private func alphaKey(_ expression: TemporalExpr) -> String {
    switch expression {
    case .always(let state): return "always(\(alphaKey(state)))"
    case .eventually(let state): return "eventually(\(alphaKey(state)))"
    case .alwaysEventually(let state): return "alwaysEventually(\(alphaKey(state)))"
    case .eventuallyAlways(let state): return "eventuallyAlways(\(alphaKey(state)))"
    case .leadsTo(let from, let to): return "leadsTo(\(alphaKey(from)),\(alphaKey(to)))"
    }
}

func fresh(_ name: String, environment: [String: String], next: inout Int) -> (String, [String: String]) {
    let canonical = "@\(next)"
    next += 1
    var extended = environment
    extended[name] = canonical
    return (canonical, extended)
}

private func actionKey(_ action: ActionExpr, environment: [String: String], next: inout Int) -> String {
    func state(_ expression: StateExpr) -> String { stateKey(expression, environment: environment, next: &next) }
    func associative(_ operation: String, _ action: ActionExpr) -> String {
        func flatten(_ action: ActionExpr) -> [ActionExpr] {
            switch (operation, action) {
            case ("and", .and(let left, let right)), ("or", .or(let left, let right)):
                return flatten(left) + flatten(right)
            case ("and", .guard_(let condition)):
                return flattenGuard(condition)
            default:
                return [action]
            }
        }
        func flattenGuard(_ condition: StateExpr) -> [ActionExpr] {
            guard operation == "and", case .and(let left, let right) = condition else {
                return [.guard_(condition)]
            }
            return flattenGuard(left) + flattenGuard(right)
        }
        return "\(operation)[\(flatten(action).map { actionKey($0, environment: environment, next: &next) }.joined(separator: ","))]"
    }
    switch action {
    case .assign(let variable, let value): return "assign(\(variable),\(state(value)))"
    case .unchanged(let variable): return "unchanged(\(variable))"
    case .guard_(let condition): return "guard(\(state(condition)))"
    case .chooseAction(let variable, let set): return "chooseAction(\(variable),\(state(set)))"
    case .existsAction(let variable, let set, let body):
        let setKey = state(set)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "existsAction(\(canonical),\(setKey),\(actionKey(body, environment: extended, next: &next)))"
    case .define(let variable, let value, let body):
        let valueKey = state(value)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "define(\(canonical),\(valueKey),\(actionKey(body, environment: extended, next: &next)))"
    case .ifElse(let condition, let then, let otherwise):
        return "if(\(state(condition)),\(actionKey(then, environment: environment, next: &next)),\(actionKey(otherwise, environment: environment, next: &next)))"
    case .and: return associative("and", action)
    case .or: return associative("or", action)
    }
}

func stateKey(_ expression: StateExpr, environment: [String: String], next: inout Int) -> String {
    func key(_ expression: StateExpr, environment: [String: String] = environment) -> String {
        stateKey(expression, environment: environment, next: &next)
    }
    func pair(_ name: String, _ left: StateExpr, _ right: StateExpr) -> String { "\(name)(\(key(left)),\(key(right)))" }
    func associative(_ operation: String, _ expression: StateExpr) -> String {
        func flatten(_ expression: StateExpr) -> [StateExpr] {
            switch (operation, expression) {
            case ("and", .and(let left, let right)), ("or", .or(let left, let right)):
                return flatten(left) + flatten(right)
            default:
                return [expression]
            }
        }
        return "\(operation)[\(flatten(expression).map { key($0) }.joined(separator: ","))]"
    }
    switch expression {
    case .value(let value): return "value(\(value))"
    case .variable(let name): return "var(\(environment[name] ?? name))"
    case .add(let a, let b): return pair("add", a, b)
    case .subtract(let a, let b): return pair("subtract", a, b)
    case .multiply(let a, let b): return pair("multiply", a, b)
    case .divide(let a, let b): return pair("divide", a, b)
    case .modulo(let a, let b): return pair("modulo", a, b)
    case .negate(let value): return "negate(\(key(value)))"
    case .integerDivide(let a, let b): return pair("integerDivide", a, b)
    case .equal(let a, let b): return pair("equal", a, b)
    case .notEqual(let a, let b): return pair("notEqual", a, b)
    case .lessThan(let a, let b): return pair("lessThan", a, b)
    case .lessOrEqual(let a, let b): return pair("lessOrEqual", a, b)
    case .greaterThan(let a, let b): return pair("greaterThan", a, b)
    case .greaterOrEqual(let a, let b): return pair("greaterOrEqual", a, b)
    case .and: return associative("and", expression)
    case .or: return associative("or", expression)
    case .not(let value): return "not(\(key(value)))"
    case .ifThenElse(let c, let t, let f): return "if(\(key(c)),\(key(t)),\(key(f)))"
    case .setLiteral(let values): return "set[\(values.map { key($0) }.sorted().joined(separator: ","))]"
    case .in(let a, let b): return pair("in", a, b)
    case .subset(let a, let b): return pair("subset", a, b)
    case .union(let a, let b): return pair("union", a, b)
    case .intersection(let a, let b): return pair("intersection", a, b)
    case .setDifference(let a, let b): return pair("difference", a, b)
    case .cardinality(let value): return "cardinality(\(key(value)))"
    case .setFilter(let set, let variable, let predicate):
        let setKey = key(set)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "filter(\(setKey),\(canonical),\(key(predicate, environment: extended)))"
    case .setMap(let mapped, let variable, let set):
        let setKey = key(set)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "map(\(key(mapped, environment: extended)),\(canonical),\(setKey))"
    case .powerSet(let value): return "powerSet(\(key(value)))"
    case .unionAll(let value): return "unionAll(\(key(value)))"
    case .integerRange(let lower, let upper): return pair("integerRange", lower, upper)
    case .tupleLiteral(let values): return "tuple[\(values.map { key($0) }.joined(separator: ","))]"
    case .tupleAccess(let tuple, let index): return "tupleAccess(\(key(tuple)),\(index))"
    case .tupleDynamicAccess(let tuple, let index): return pair("tupleDynamicAccess", tuple, index)
    case .tupleLength(let tuple): return "tupleLength(\(key(tuple)))"
    case .tupleAppend(let tuple, let value): return pair("tupleAppend", tuple, value)
    case .tupleHead(let tuple): return "tupleHead(\(key(tuple)))"
    case .tupleTail(let tuple): return "tupleTail(\(key(tuple)))"
    case .tupleConcatenate(let a, let b): return pair("tupleConcat", a, b)
    case .recordLiteral(let fields):
        return "record[\(fields.fields.map { "\($0.name):\(key($0.value))" }.joined(separator: ","))]"
    case .recordAccess(let record, let field): return "recordAccess(\(key(record)),\(field))"
    case .domain(let function): return "domain(\(key(function)))"
    case .functionLiteral(let domain, let variable, let body):
        let domainKey = key(domain)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "function(\(domainKey),\(canonical),\(key(body, environment: extended)))"
    case .functionApply(let function, let argument): return pair("apply", function, argument)
    case .except(let function, let keyExpression, let value): return "except(\(key(function)),\(key(keyExpression)),\(key(value)))"
    case .caseExpr(let cases, let fallback):
        return "case[\(cases.map { key($0) }.joined(separator: ","))]/\(fallback.map { key($0) } ?? "none")"
    case .forAll(let set, let variable, let predicate):
        let setKey = key(set)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "forall(\(setKey),\(canonical),\(key(predicate, environment: extended)))"
    case .exists(let set, let variable, let predicate):
        let setKey = key(set)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "exists(\(setKey),\(canonical),\(key(predicate, environment: extended)))"
    case .choose(let set, let variable, let predicate):
        let setKey = key(set)
        let (canonical, extended) = fresh(variable, environment: environment, next: &next)
        return "choose(\(setKey),\(canonical),\(key(predicate, environment: extended)))"
    case .enabledAction(let name): return "enabled(\(name))"
    case .sequenceFromSet(let value): return "sequence(\(key(value)))"
    case .setSum(let function, let set): return pair("sum", function, set)
    case .functionSet(let domain, let range): return pair("functionSet", domain, range)
    case .foldFunction(let operation, let initial, let sequence):
        var lambdaEnvironment = environment
        let parameters = operation.parameters.map { parameter -> String in
            let (canonical, extended) = fresh(parameter, environment: lambdaEnvironment, next: &next)
            lambdaEnvironment = extended
            return canonical
        }
        return "fold([\(parameters.joined(separator: ","))],\(key(operation.body, environment: lambdaEnvironment)),\(key(initial)),\(key(sequence)))"
    case .operatorApplication(let operation, let arguments):
        let operationKey: String
        switch operation {
        case .lambda(let lambda):
            var lambdaEnvironment = environment
            let parameters = lambda.parameters.map { parameter -> String in
                let (canonical, extended) = fresh(parameter, environment: lambdaEnvironment, next: &next)
                lambdaEnvironment = extended
                return canonical
            }
            operationKey = "lambda([\(parameters.joined(separator: ","))],\(key(lambda.body, environment: lambdaEnvironment)))"
        case .reference(let name, let arity):
            operationKey = "operator(\(environment[name] ?? name),\(arity))"
        }
        let argumentKeys = arguments.map { argument -> String in
            switch argument {
            case .value(let expression): return "value(\(key(expression)))"
            case .operator(.reference(let name, let arity)):
                return "operator(\(environment[name] ?? name),\(arity))"
            case .operator(.lambda(let lambda)):
                var lambdaEnvironment = environment
                let parameters = lambda.parameters.map { parameter -> String in
                    let (canonical, extended) = fresh(parameter, environment: lambdaEnvironment, next: &next)
                    lambdaEnvironment = extended
                    return canonical
                }
                return "operatorLambda([\(parameters.joined(separator: ","))],\(key(lambda.body, environment: lambdaEnvironment)))"
            }
    }
    return "apply(\(operationKey),[\(argumentKeys.joined(separator: ","))])"
    case .recursiveCall(let name, let arguments): return "recursive(\(name),\(arguments.map { key($0) }.joined(separator: ",")))"
    case .letValue(let name, let value, let body):
        let valueKey = key(value)
        let (canonical, extended) = fresh(name, environment: environment, next: &next)
        return "letValue(\(canonical),\(valueKey),\(key(body, environment: extended)))"
    case .letIn(let operators, let body):
        let declarations = operators.map { operation in
            var operatorEnvironment = environment
            let domainKey = operation.domain.map { key($0, environment: operatorEnvironment) } ?? "unbounded"
            let parameterNames = operation.parameters.map { parameter -> String in
                let (canonical, extended) = fresh(parameter, environment: operatorEnvironment, next: &next)
                operatorEnvironment = extended
                return canonical
            }
            return "local(\(operation.name),[\(parameterNames.joined(separator: ","))],\(domainKey),\(key(operation.body, environment: operatorEnvironment)))"
        }.joined(separator: ",")
        return "letIn([\(declarations)],\(key(body)))"
    }
}
