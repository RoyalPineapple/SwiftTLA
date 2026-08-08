import Foundation

public struct QuantVar: Hashable, Sendable, CustomStringConvertible {
    public let name: String
    public var description: String { name }
    public init(name: String) { self.name = name }

    public static func fresh() -> QuantVar {
        let c = _lock.withLock { () -> Int in
            _counter += 1
            return _counter
        }
        return QuantVar(name: "x\(c)")
    }
    public static func resetCounter() { _lock.withLock { _counter = 0 } }
    private static let _lock = NSLock()
    private nonisolated(unsafe) static var _counter = 0
}

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
    case setFilter(StateExpr, QuantVar, StateExpr)
    case setMap(StateExpr, QuantVar, StateExpr)
    case powerSet(StateExpr)
    case unionAll(StateExpr)

    case tupleLiteral([StateExpr])
    case tupleAccess(StateExpr, Int)
    case tupleLength(StateExpr)
    case tupleAppend(StateExpr, StateExpr)
    case tupleHead(StateExpr)
    case tupleTail(StateExpr)
    case tupleConcatenate(StateExpr, StateExpr)

    case recordLiteral([String: StateExpr])
    case recordAccess(StateExpr, String)
    case domain(StateExpr)
    case functionLiteral(StateExpr, QuantVar, StateExpr)
    case functionApply(StateExpr, StateExpr)
    case except(StateExpr, StateExpr, StateExpr)
    case caseExpr([StateExpr], StateExpr?)

    case forAll(StateExpr, QuantVar, StateExpr)
    case exists(StateExpr, QuantVar, StateExpr)
    case choose(StateExpr, QuantVar, StateExpr)
    case enabledAction(String)

    case sequenceFromSet(StateExpr)
    case setSum(StateExpr, StateExpr)
    case functionSet(StateExpr, StateExpr)

    case recursiveCall(String, [StateExpr])

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
        case .tupleLiteral(let elems): return "<<\(elems.map(\.description).joined(separator: ", "))>>"
        case .tupleAccess(let t, let i): return "\(t)[\(i)]"
        case .tupleLength(let t): return "Len(\(t))"
        case .tupleAppend(let t, let e): return "Append(\(t), \(e))"
        case .tupleHead(let t): return "Head(\(t))"
        case .tupleTail(let t): return "Tail(\(t))"
        case .tupleConcatenate(let a, let b): return "(\(a) \\o \(b))"
        case .recordLiteral(let fields):
            let entries = fields.sorted(by: { $0.key < $1.key }).map { "\($0.key) |-> \($0.value)" }
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
        case .recursiveCall(let n, let a): return "\(n)(\(a.map(\.description).joined(separator: ", ")))"
        }
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
