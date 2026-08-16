import Foundation

public enum FreshVarName {
    private static let _lock = NSLock()
    private nonisolated(unsafe) static var _counter = 0

    public static func fresh() -> String {
        let c = _lock.withLock { () -> Int in
            _counter += 1
            return _counter
        }
        return "x\(c)"
    }
    public static func resetCounter() { _lock.withLock { _counter = 0 } }
}

/// A local TLA+ operator declared inside a `LET … IN` expression.
///
/// Local operators are formal expressions, not Swift closures.  They remain
/// in the AST so the evaluator and the emitted module use the same scope.
public struct LocalOperator: Hashable, Sendable {
    public let name: String
    public let parameters: [String]
    public let body: StateExpr

    public init(_ name: String, parameters: [String] = [], body: StateExpr) {
        self.name = name
        self.parameters = parameters
        self.body = body
    }
}

/// A formal function body with named, scoped inputs.
///
/// This is syntax in the specification, not a Swift closure and never a state
/// value. The evaluator binds its inputs only while evaluating the formal
/// operator that receives it.
public struct FormalLambda: Hashable, Sendable {
    public let parameters: [String]
    public let body: StateExpr

    public init(parameters: [String], body: StateExpr) {
        precondition(!parameters.isEmpty, "A formal lambda needs at least one parameter.")
        precondition(Set(parameters).count == parameters.count, "A formal lambda cannot repeat a parameter name.")
        self.parameters = parameters
        self.body = body
    }
}

/// A formal operator passed or applied by the specification.
///
/// This is deliberately not a Swift closure. A lambda retains its parameter
/// names and body in the formal AST; a reference retains the TLA+ operator name
/// and its required arity. Both can therefore be emitted, checked, and applied
/// by the same formal runtime.
public indirect enum FormalOperator: Hashable, Sendable {
    case lambda(FormalLambda)
    case reference(String, arity: Int)

    public var arity: Int {
        switch self {
        case .lambda(let lambda): lambda.parameters.count
        case .reference(_, let arity): arity
        }
    }

    var tlaSource: String {
        switch self {
        case .lambda(let lambda):
            "LAMBDA \(lambda.parameters.joined(separator: ", ")) : \(lambda.body)"
        case .reference(let name, _):
            name
        }
    }
}

/// One argument supplied to a formal operator call.
///
/// TLA+ operators can receive ordinary expressions and other operators.  Keep
/// that distinction in the AST: a higher-order call is not a Swift closure
/// invocation and does not erase the operator that was supplied.
public indirect enum FormalCallArgument: Hashable, Sendable {
    case value(StateExpr)
    case `operator`(FormalOperator)
}

/// One ordered parameter of a formal operator definition.
///
/// The order is part of TLA+ operator application.  Keeping the kind beside
/// the name lets the evaluator reject a value where the source requires an
/// operator, or the reverse, before it evaluates the definition body.
public enum FormalParameter: Hashable, Sendable {
    case value(String)
    case `operator`(String, arity: Int)

    public var name: String {
        switch self {
        case .value(let name), .operator(let name, _): name
        }
    }
}

/// An executable formal definition, including higher-order parameters.
///
/// This is distinct from a Swift function: its body stays in `StateExpr`, so
/// the evaluator, alpha-equivalence checker, and TLA+ exporter all observe
/// the same operation and its supplied operators.
public struct FormalOperatorDefinition: Hashable, Sendable {
    public let name: String
    public let parameters: [FormalParameter]
    public let body: StateExpr

    public init(name: String, parameters: [FormalParameter], body: StateExpr) {
        precondition(!name.isEmpty, "A formal operator definition needs a name.")
        precondition(
            Set(parameters.map(\.name)).count == parameters.count,
            "A formal operator definition cannot repeat a parameter name."
        )
        self.name = name
        self.parameters = parameters
        self.body = body
    }
}

@StateExprStructural
public indirect enum StateExpr: Hashable, Sendable, CustomStringConvertible {
    case value(TLAValue)
    case variable(String)

    case add(StateExpr, StateExpr)
    case subtract(StateExpr, StateExpr)
    case multiply(StateExpr, StateExpr)
    case divide(StateExpr, StateExpr)
    case modulo(StateExpr, StateExpr)
    case negate(StateExpr)
    case integerDivide(StateExpr, StateExpr)

    case equal(StateExpr, StateExpr)
    case notEqual(StateExpr, StateExpr)
    case lessThan(StateExpr, StateExpr)
    case lessOrEqual(StateExpr, StateExpr)
    case greaterThan(StateExpr, StateExpr)
    case greaterOrEqual(StateExpr, StateExpr)

    case and(StateExpr, StateExpr)
    case or(StateExpr, StateExpr)
    case not(StateExpr)

    case ifThenElse(StateExpr, StateExpr, StateExpr)

    case setLiteral([StateExpr])
    case `in`(StateExpr, StateExpr)
    case subset(StateExpr, StateExpr)
    case union(StateExpr, StateExpr)
    case intersection(StateExpr, StateExpr)
    case setDifference(StateExpr, StateExpr)
    case cardinality(StateExpr)
    case setFilter(StateExpr, String, StateExpr)
    case setMap(StateExpr, String, StateExpr)
    case powerSet(StateExpr)
    case unionAll(StateExpr)
    case integerRange(StateExpr, StateExpr)

    case tupleLiteral([StateExpr])
    case tupleAccess(StateExpr, Int)
    case tupleDynamicAccess(StateExpr, StateExpr)
    case tupleLength(StateExpr)
    case tupleAppend(StateExpr, StateExpr)
    case tupleHead(StateExpr)
    case tupleTail(StateExpr)
    case tupleConcatenate(StateExpr, StateExpr)

    case recordLiteral([String: StateExpr])
    case recordAccess(StateExpr, String)
    case domain(StateExpr)
    case functionLiteral(StateExpr, String, StateExpr)
    case functionApply(StateExpr, StateExpr)
    case except(StateExpr, StateExpr, StateExpr)
    case caseExpr([StateExpr], StateExpr?)

    case forAll(StateExpr, String, StateExpr)
    case exists(StateExpr, String, StateExpr)
    case choose(StateExpr, String, StateExpr)
    case enabledAction(String)

    case sequenceFromSet(StateExpr)
    case setSum(StateExpr, StateExpr)
    case functionSet(StateExpr, StateExpr)
    case foldFunction(FormalLambda, initial: StateExpr, sequence: StateExpr)

    case operatorApplication(FormalOperator, [FormalCallArgument])

    case recursiveCall(String, [StateExpr])
    /// A scoped formal value. This is TLA+ `LET name == value IN body`, not a
    /// Swift local and not a state update.
    case letValue(String, StateExpr, StateExpr)
    case letIn([LocalOperator], StateExpr)

    public var description: String {
        switch self {
        case .value(let v): return v.description
        case .variable(let n): return n
        case .add(let a, let b): return "(\(a) + \(b))"
        case .subtract(let a, let b): return "(\(a) - \(b))"
        case .multiply(let a, let b): return "(\(a) * \(b))"
        case .divide(let a, let b): return "(\(a) \\div \(b))"
        case .modulo(let a, let b): return "(\(a) % \(b))"
        case .negate(let a): return "(-\(a))"
        case .integerDivide(let a, let b): return "(\(a) \\div \(b))"
        case .equal(let a, let b): return "(\(a) = \(b))"
        case .notEqual(let a, let b): return "(\(a) /= \(b))"
        case .lessThan(let a, let b): return "(\(a) < \(b))"
        case .lessOrEqual(let a, let b): return "(\(a) <= \(b))"
        case .greaterThan(let a, let b): return "(\(a) > \(b))"
        case .greaterOrEqual(let a, let b): return "(\(a) >= \(b))"
        case .and(let a, let b): return "(\(a) /\\ \(b))"
        case .or(let a, let b): return "(\(a) \\/ \(b))"
        case .not(let a): return "(~\(a))"
        case .ifThenElse(let c, let t, let f): return "(IF \(c) THEN \(t) ELSE \(f))"
        case .setLiteral(let elems):
            if elems.isEmpty { return "{}" }
            return "{\(elems.map(\.description).joined(separator: ", "))}"
        case .in(let e, let s): return "(\(e) \\in \(s))"
        case .subset(let a, let b): return "(\(a) \\subseteq \(b))"
        case .union(let a, let b): return "(\(a) \\cup \(b))"
        case .intersection(let a, let b): return "(\(a) \\cap \(b))"
        case .setDifference(let a, let b): return "(\(a) \\ \(b))"
        case .cardinality(let s): return "Cardinality(\(s))"
        case .setFilter(let s, let qv, let p): return "{\(qv) \\in \(s) : \(p)}"
        case .setMap(let e, let qv, let s): return "{\(e) : \(qv) \\in \(s)}"
        case .powerSet(let s): return "SUBSET \(s)"
        case .unionAll(let s): return "UNION \(s)"
        case .integerRange(let lower, let upper): return "\(lower)..\(upper)"
        case .tupleLiteral(let elems): return "<<\(elems.map(\.description).joined(separator: ", "))>>"
        case .tupleAccess(let t, let i): return "\(t)[\(i)]"
        case .tupleDynamicAccess(let tuple, let index): return "\(tuple)[\(index)]"
        case .tupleLength(let t): return "Len(\(t))"
        case .tupleAppend(let t, let e): return "Append(\(t), \(e))"
        case .tupleHead(let t): return "Head(\(t))"
        case .tupleTail(let t): return "Tail(\(t))"
        case .tupleConcatenate(let a, let b): return "(\(a) \\o \(b))"
        case .recordLiteral(let fields):
            let orderedKeys: [String]
            if fields["procedure"] != nil, fields["pc"] != nil {
                orderedKeys = ["procedure", "pc"]
                    + fields.keys.filter { $0 != "procedure" && $0 != "pc" }.sorted()
            } else {
                orderedKeys = fields.keys.sorted()
            }
            let entries = orderedKeys.map { "\($0) |-> \(fields[$0]!)" }
            return "[\(entries.joined(separator: ", "))]"
        case .recordAccess(let r, let f): return "(\(r)).\(f)"
        case .domain(let f): return "DOMAIN \(f)"
        case .functionLiteral(let d, let qv, let e): return "[\(qv) \\in \(d) |-> \(e)]"
        case .functionApply(let f, let x): return "\(f)[\(x)]"
        case .except(let f, let x, let e):
            // Functions need ![key]; records accept !["field"] in TLC.
            return "[\(f) EXCEPT ![\(x)] = \(e)]"

        case .caseExpr(let pairs, let other):
            let cases = stride(from: 0, to: pairs.count, by: 2).map {
                "\(pairs[$0]) -> \(pairs[$0 + 1])"
            }.joined(separator: " [] ")
            if let o = other { return "CASE \(cases) [] OTHER -> \(o)" }
            return "CASE \(cases)"
        case .forAll(let s, let qv, let p): return "\\A \(qv) \\in \(s) : \(p)"
        case .exists(let s, let qv, let p): return "\\E \(qv) \\in \(s) : \(p)"
        case .choose(let s, let qv, let p): return "CHOOSE \(qv) \\in \(s) : \(p)"
        case .enabledAction(let a): return "ENABLED \(a)"
        case .sequenceFromSet(let s): return "SeqFromSet(\(s))"
        case .setSum(let f, let s): return "Sum(\(f), \(s))"
        case .functionSet(let d, let r): return "[\(d) -> \(r)]"
        case .foldFunction(let operation, let initial, let sequence):
            return "FoldFunction(LAMBDA \(operation.parameters.joined(separator: ", ")) : \(operation.body), \(initial), \(sequence))"
        case .operatorApplication(let operation, let arguments):
            let arguments = arguments.map(\.tlaSource).joined(separator: ", ")
            return operation.isLambda
                ? "(\(operation.tlaSource))(\(arguments))"
                : "\(operation.tlaSource)(\(arguments))"
        case .recursiveCall(let n, let a):
            return a.isEmpty ? n : "\(n)(\(a.map(\.description).joined(separator: ", ")))"
        case .letValue(let name, let value, let body):
            return "LET \(name) == \(value) IN \(body)"
        case .letIn(let operators, let body):
            let names = Set(operators.map(\.name))
            let recursiveNames = operators
                .flatMap { localOperatorCalls(in: $0.body) }
                .filter(names.contains)
            let recursiveDeclaration: String
            if recursiveNames.isEmpty {
                recursiveDeclaration = ""
            } else {
                recursiveDeclaration = "RECURSIVE " + operators
                    .filter { recursiveNames.contains($0.name) }
                    .map { operation in
                        let slots = operation.parameters.map { _ in "_" }.joined(separator: ", ")
                        return operation.parameters.isEmpty ? operation.name : "\(operation.name)(\(slots))"
                    }
                    .joined(separator: ", ") + "\n    "
            }
            let declarations = operators.map { operation in
                let parameters = operation.parameters.isEmpty ? "" : "(\(operation.parameters.joined(separator: ", ")))"
                return "\(operation.name)\(parameters) == \(operation.body)"
            }.joined(separator: "\n    ")
            return "LET \(recursiveDeclaration)\(declarations)\nIN \(body)"
        }
    }
}

private extension FormalOperator {
    var isLambda: Bool {
        if case .lambda = self { return true }
        return false
    }
}

private extension FormalCallArgument {
    var tlaSource: String {
        switch self {
        case .value(let expression): expression.description
        case .operator(let operation): operation.tlaSource
        }
    }

    var referencedLocalOperators: Set<String> {
        switch self {
        case .value(let expression): localOperatorCalls(in: expression)
        case .operator(.lambda(let lambda)): localOperatorCalls(in: lambda.body)
        case .operator(.reference): []
        }
    }
}

private func localOperatorCalls(in expression: StateExpr) -> Set<String> {
    switch expression {
    case .value, .variable, .enabledAction:
        return []
    case .recursiveCall(let name, let arguments):
        return Set([name]).union(
            arguments.reduce(into: Set<String>()) { $0.formUnion(localOperatorCalls(in: $1)) }
        )
    case .letValue(_, let value, let body):
        return localOperatorCalls(in: value).union(localOperatorCalls(in: body))
    case .letIn:
        // Nested scopes bring their own recursive declarations.
        return []
    case .negate(let value), .not(let value), .cardinality(let value), .powerSet(let value),
         .unionAll(let value), .tupleLength(let value), .tupleHead(let value), .tupleTail(let value),
         .domain(let value), .sequenceFromSet(let value):
        return localOperatorCalls(in: value)
    case .add(let lhs, let rhs), .subtract(let lhs, let rhs), .multiply(let lhs, let rhs),
         .divide(let lhs, let rhs), .modulo(let lhs, let rhs), .integerDivide(let lhs, let rhs),
         .equal(let lhs, let rhs), .notEqual(let lhs, let rhs), .lessThan(let lhs, let rhs),
         .lessOrEqual(let lhs, let rhs), .greaterThan(let lhs, let rhs), .greaterOrEqual(let lhs, let rhs),
         .and(let lhs, let rhs), .or(let lhs, let rhs), .in(let lhs, let rhs), .subset(let lhs, let rhs),
         .union(let lhs, let rhs), .intersection(let lhs, let rhs), .setDifference(let lhs, let rhs),
         .tupleDynamicAccess(let lhs, let rhs), .tupleAppend(let lhs, let rhs),
         .tupleConcatenate(let lhs, let rhs), .functionApply(let lhs, let rhs),
         .functionSet(let lhs, let rhs), .setSum(let lhs, let rhs):
        return localOperatorCalls(in: lhs).union(localOperatorCalls(in: rhs))
    case .ifThenElse(let condition, let then, let otherwise):
        return localOperatorCalls(in: condition)
            .union(localOperatorCalls(in: then))
            .union(localOperatorCalls(in: otherwise))
    case .setLiteral(let values), .tupleLiteral(let values):
        return values.reduce(into: Set<String>()) { $0.formUnion(localOperatorCalls(in: $1)) }
    case .tupleAccess(let tuple, _), .recordAccess(let tuple, _):
        return localOperatorCalls(in: tuple)
    case .recordLiteral(let fields):
        return fields.values.reduce(into: Set<String>()) { $0.formUnion(localOperatorCalls(in: $1)) }
    case .functionLiteral(let domain, _, let body), .setFilter(let domain, _, let body),
         .forAll(let domain, _, let body), .exists(let domain, _, let body), .choose(let domain, _, let body):
        return localOperatorCalls(in: domain).union(localOperatorCalls(in: body))
    case .setMap(let value, _, let domain):
        return localOperatorCalls(in: value).union(localOperatorCalls(in: domain))
    case .except(let function, let key, let value):
        return localOperatorCalls(in: function)
            .union(localOperatorCalls(in: key))
            .union(localOperatorCalls(in: value))
    case .caseExpr(let pairs, let fallback):
        return pairs.reduce(into: fallback.map(localOperatorCalls(in:)) ?? Set<String>()) {
            $0.formUnion(localOperatorCalls(in: $1))
        }
    case .integerRange(let lower, let upper):
        return localOperatorCalls(in: lower).union(localOperatorCalls(in: upper))
    case .foldFunction(let operation, let initial, let sequence):
        return localOperatorCalls(in: operation.body)
            .union(localOperatorCalls(in: initial))
            .union(localOperatorCalls(in: sequence))
    case .operatorApplication(let operation, let arguments):
        let operatorCalls: Set<String>
        switch operation {
        case .lambda(let lambda): operatorCalls = localOperatorCalls(in: lambda.body)
        case .reference: operatorCalls = []
        }
        return arguments.reduce(into: operatorCalls) { $0.formUnion($1.referencedLocalOperators) }
    }
}

extension StateExpr {
    public static func int(_ value: Int) -> StateExpr { .value(.int(value)) }
    public static func bool(_ value: Bool) -> StateExpr { .value(.bool(value)) }
}

extension StateExpr: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .value(.int(value)) }
}

extension StateExpr: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .value(.bool(value)) }
}

extension StateExpr: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .value(.string(value)) }
}
