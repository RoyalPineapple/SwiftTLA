public indirect enum StateExpr: Hashable, Codable, Sendable, CustomStringConvertible {
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
    case setFilter(StateExpr, StateExpr)
    case setMap(StateExpr, StateExpr)
    case powerSet(StateExpr)
    case unionAll(StateExpr)

    case tupleLiteral([StateExpr])
    case tupleAccess(StateExpr, Int)
    case tupleLength(StateExpr)
    case tupleAppend(StateExpr, StateExpr)
    case tupleConcatenate(StateExpr, StateExpr)

    case recordLiteral([String: StateExpr])
    case recordAccess(StateExpr, String)
    case domain(StateExpr)
    case functionLiteral(StateExpr, StateExpr)
    case functionApply(StateExpr, StateExpr)

    case forAll(StateExpr, StateExpr)
    case exists(StateExpr, StateExpr)
    case choose(StateExpr, StateExpr)
    case enabledAction(String)

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
        case .setFilter(let s, let p): return "{x \\in \(s) : \(p)}"
        case .setMap(let e, let s): return "{\(e) : x \\in \(s)}"
        case .powerSet(let s): return "SUBSET \(s)"
        case .unionAll(let s): return "UNION \(s)"
        case .tupleLiteral(let elems): return "<<\(elems.map(\.description).joined(separator: ", "))>>"
        case .tupleAccess(let t, let i): return "\(t)[\(i)]"
        case .tupleLength(let t): return "Len(\(t))"
        case .tupleAppend(let t, let e): return "Append(\(t), \(e))"
        case .tupleConcatenate(let a, let b): return "(\(a) \\o \(b))"
        case .recordLiteral(let fields):
            let entries = fields.sorted(by: { $0.key < $1.key }).map { "\($0.key) |-> \($0.value)" }
            return "[\(entries.joined(separator: ", "))]"
        case .recordAccess(let r, let f): return "\(r).\(f)"
        case .domain(let f): return "DOMAIN \(f)"
        case .functionLiteral(let d, let e): return "[x \\in \(d) |-> \(e)]"
        case .functionApply(let f, let x): return "\(f)[\(x)]"
        case .forAll(let s, let p): return "∀ x ∈ \(s) : \(p)"
        case .exists(let s, let p): return "∃ x ∈ \(s) : \(p)"
        case .choose(let s, let p): return "CHOOSE x ∈ \(s) : \(p)"
        case .enabledAction(let a): return "ENABLED \(a)"
        }
    }
}
