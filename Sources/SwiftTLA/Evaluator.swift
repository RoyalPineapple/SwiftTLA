public enum EvalError: Error, CustomStringConvertible {
    case undefinedVariable(String)
    case typeMismatch(String)
    case divisionByZero
    case indexOutOfBounds(Int, Int)

    public var description: String {
        switch self {
        case .undefinedVariable(let n): return "Undefined variable: \(n)"
        case .typeMismatch(let msg): return "Type mismatch: \(msg)"
        case .divisionByZero: return "Division by zero"
        case .indexOutOfBounds(let i, let c): return "Index \(i) out of bounds (1..\(c))"
        }
    }
}

public enum Evaluator {
    public static func evaluate(_ expr: StateExpr, in state: [String: TLAValue]) throws -> TLAValue {
        switch expr {
        case .value(let v): return v
        case .variable(let name):
            guard let val = state[name] else { throw EvalError.undefinedVariable(name) }
            return val

        case .add(let a, let b): return try intOp(a, b, +, in: state)
        case .subtract(let a, let b): return try intOp(a, b, -, in: state)
        case .multiply(let a, let b): return try intOp(a, b, *, in: state)
        case .divide(let a, let b): return try intOp(a, b, { guard $1 != 0 else { throw EvalError.divisionByZero }; return $0 / $1 }, in: state)
        case .modulo(let a, let b): return try intOp(a, b, { guard $1 != 0 else { throw EvalError.divisionByZero }; return $0 % $1 }, in: state)
        case .negate(let a): return try intUnary(a, -, in: state)
        case .integerDivide(let a, let b): return try intOp(a, b, { guard $1 != 0 else { throw EvalError.divisionByZero }; return $0 / $1 }, in: state)

        case .equal(let a, let b): return .bool(try evaluate(a, in: state) == evaluate(b, in: state))
        case .notEqual(let a, let b): return .bool(try evaluate(a, in: state) != evaluate(b, in: state))
        case .lessThan(let a, let b): return try intCmp(a, b, <, in: state)
        case .lessOrEqual(let a, let b): return try intCmp(a, b, <=, in: state)
        case .greaterThan(let a, let b): return try intCmp(a, b, >, in: state)
        case .greaterOrEqual(let a, let b): return try intCmp(a, b, >=, in: state)

        case .and(let a, let b):
            guard case .bool(let ba) = try evaluate(a, in: state) else { throw typeMismatch("∧", got: try evaluate(a, in: state)) }
            if !ba { return .bool(false) }
            guard case .bool(let bb) = try evaluate(b, in: state) else { throw typeMismatch("∧", got: try evaluate(b, in: state)) }
            return .bool(bb)

        case .or(let a, let b):
            guard case .bool(let ba) = try evaluate(a, in: state) else { throw typeMismatch("∨", got: try evaluate(a, in: state)) }
            if ba { return .bool(true) }
            guard case .bool(let bb) = try evaluate(b, in: state) else { throw typeMismatch("∨", got: try evaluate(b, in: state)) }
            return .bool(bb)

        case .not(let a):
            guard case .bool(let ba) = try evaluate(a, in: state) else { throw typeMismatch("¬", got: try evaluate(a, in: state)) }
            return .bool(!ba)

        case .ifThenElse(let c, let t, let f):
            guard case .bool(let bc) = try evaluate(c, in: state) else { throw typeMismatch("IF", got: try evaluate(c, in: state)) }
            return try evaluate(bc ? t : f, in: state)

        case .setLiteral(let elements):
            var result = Set<TLAValue>()
            for e in elements { result.insert(try evaluate(e, in: state)) }
            return .set(result)

        case .in(let elem, let s):
            let v = try evaluate(elem, in: state)
            guard case .set(let sv) = try evaluate(s, in: state) else { throw typeMismatch("∈", got: try evaluate(s, in: state)) }
            return .bool(sv.contains(v))

        case .subset(let a, let b):
            guard case .set(let sa) = try evaluate(a, in: state), case .set(let sb) = try evaluate(b, in: state) else {
                throw typeMismatch("⊆", got: try evaluate(a, in: state), try evaluate(b, in: state))
            }
            return .bool(sa.isSubset(of: sb))

        case .union(let a, let b):
            guard case .set(let sa) = try evaluate(a, in: state), case .set(let sb) = try evaluate(b, in: state) else {
                throw typeMismatch("∪", got: try evaluate(a, in: state), try evaluate(b, in: state))
            }
            return .set(sa.union(sb))

        case .intersection(let a, let b):
            guard case .set(let sa) = try evaluate(a, in: state), case .set(let sb) = try evaluate(b, in: state) else {
                throw typeMismatch("∩", got: try evaluate(a, in: state), try evaluate(b, in: state))
            }
            return .set(sa.intersection(sb))

        case .setDifference(let a, let b):
            guard case .set(let sa) = try evaluate(a, in: state), case .set(let sb) = try evaluate(b, in: state) else {
                throw typeMismatch("∖", got: try evaluate(a, in: state), try evaluate(b, in: state))
            }
            return .set(sa.subtracting(sb))

        case .cardinality(let s):
            guard case .set(let sv) = try evaluate(s, in: state) else { throw typeMismatch("cardinality", got: try evaluate(s, in: state)) }
            return .int(sv.count)

        case .setFilter(let s, let p):
            guard case .set(let sv) = try evaluate(s, in: state) else { throw typeMismatch("set filter", got: try evaluate(s, in: state)) }
            var result = Set<TLAValue>()
            for elem in sv {
                var boundState = state
                boundState["_x"] = elem
                let exprWithVar = substituteVariable("_x", elem, in: p)
                if case .bool(true) = try evaluate(exprWithVar, in: state) {
                    result.insert(elem)
                }
            }
            return .set(result)

        case .setMap(let e, let s):
            guard case .set(let sv) = try evaluate(s, in: state) else { throw typeMismatch("set map", got: try evaluate(s, in: state)) }
            var result = Set<TLAValue>()
            for elem in sv {
                let exprWithVar = substituteVariable("_x", elem, in: e)
                result.insert(try evaluate(exprWithVar, in: state))
            }
            return .set(result)

        case .powerSet(let s):
            guard case .set(let sv) = try evaluate(s, in: state) else { throw typeMismatch("SUBSET", got: try evaluate(s, in: state)) }
            let elems = Array(sv)
            var result = Set<TLAValue>()
            for mask in 0..<(1 << elems.count) {
                var subset = Set<TLAValue>()
                for i in 0..<elems.count where (mask >> i) & 1 == 1 {
                    subset.insert(elems[i])
                }
                result.insert(.set(subset))
            }
            return .set(result)

        case .unionAll(let s):
            guard case .set(let sv) = try evaluate(s, in: state) else { throw typeMismatch("UNION", got: try evaluate(s, in: state)) }
            var result = Set<TLAValue>()
            for elem in sv {
                guard case .set(let inner) = elem else { throw typeMismatch("UNION element not a set", got: elem) }
                result.formUnion(inner)
            }
            return .set(result)

        case .tupleLiteral(let elements):
            return .tuple(try elements.map { try evaluate($0, in: state) })

        case .tupleAccess(let t, let index):
            guard case .tuple(let tv) = try evaluate(t, in: state) else { throw typeMismatch("tuple access", got: try evaluate(t, in: state)) }
            guard index >= 1, index <= tv.count else { throw EvalError.indexOutOfBounds(index, tv.count) }
            return tv[index - 1]

        case .tupleLength(let t):
            guard case .tuple(let tv) = try evaluate(t, in: state) else { throw typeMismatch("Len", got: try evaluate(t, in: state)) }
            return .int(tv.count)

        case .tupleAppend(let t, let e):
            guard case .tuple(var tv) = try evaluate(t, in: state) else { throw typeMismatch("Append", got: try evaluate(t, in: state)) }
            tv.append(try evaluate(e, in: state))
            return .tuple(tv)

        case .tupleConcatenate(let a, let b):
            guard case .tuple(let ta) = try evaluate(a, in: state), case .tuple(let tb) = try evaluate(b, in: state) else {
                throw typeMismatch("tuple concat", got: try evaluate(a, in: state), try evaluate(b, in: state))
            }
            return .tuple(ta + tb)

        case .recordLiteral(let fields):
            var result: [String: TLAValue] = [:]
            for (key, expr) in fields { result[key] = try evaluate(expr, in: state) }
            return .record(result)

        case .recordAccess(let r, let field):
            guard case .record(let rv) = try evaluate(r, in: state) else { throw typeMismatch("record access", got: try evaluate(r, in: state)) }
            guard let val = rv[field] else { throw typeMismatch("record field '\(field)' not found") }
            return val

        case .domain(let f):
            let v = try evaluate(f, in: state)
            switch v {
            case .record(let rv): return .set(Set(rv.keys.map { .string($0) }))
            case .set(let sv):
                var keys = Set<TLAValue>()
                for elem in sv {
                    if case .record(let rv) = elem { keys.formUnion(rv.keys.map { .string($0) }) }
                    else if case .tuple(let tv) = elem { keys.formUnion(tv.enumerated().map { .int($0.offset + 1) }) }
                }
                return .set(keys)
            default: throw typeMismatch("DOMAIN", got: v)
            }

        case .functionLiteral(let d, let e):
            guard case .set(let domainSet) = try evaluate(d, in: state) else { throw typeMismatch("function domain", got: try evaluate(d, in: state)) }
            var result = Set<TLAValue>()
            for elem in domainSet {
                let exprWithVar = substituteVariable("_x", elem, in: e)
                let val = try evaluate(exprWithVar, in: state)
                if case .tuple(let pair) = elem, pair.count == 2 {
                    result.insert(.record([tlaValueToString(pair[0]): val]))
                } else {
                    result.insert(.record([tlaValueToString(elem): val]))
                }
            }
            return .set(result)

        case .functionApply(let f, let x):
            let funcVal = try evaluate(f, in: state)
            let argVal = try evaluate(x, in: state)
            guard case .set(let fset) = funcVal else { throw typeMismatch("function apply", got: funcVal) }
            let key = tlaValueToString(argVal)
            for elem in fset {
                if case .record(let rv) = elem, let v = rv[key] { return v }
            }
            throw typeMismatch("function apply: key not found '\(key)'")

        case .except(let f, let x, let e):
            let funcVal = try evaluate(f, in: state)
            let keyVal = try evaluate(x, in: state)
            let newVal = try evaluate(e, in: state)
            switch funcVal {
            case .record(var rv):
                rv[tlaValueToString(keyVal)] = newVal
                return .record(rv)
            case .set(let fset):
                let key = tlaValueToString(keyVal)
                var newSet = Set<TLAValue>()
                for elem in fset {
                    if case .record(var rv) = elem, rv.keys.contains(key) {
                        rv[key] = newVal
                        newSet.insert(.record(rv))
                    } else {
                        newSet.insert(elem)
                    }
                }
                return .set(newSet)
            default:
                throw typeMismatch("EXCEPT", got: funcVal)
            }

        case .forAll(let set, let predicate):
            guard case .set(let sv) = try evaluate(set, in: state) else { throw typeMismatch("∀", got: try evaluate(set, in: state)) }
            for elem in sv {
                var bound = state
                bound["_q"] = elem
                if case .bool(false) = try evaluate(predicate, in: bound) {
                    return .bool(false)
                }
            }
            return .bool(true)

        case .exists(let set, let predicate):
            guard case .set(let sv) = try evaluate(set, in: state) else { throw typeMismatch("∃", got: try evaluate(set, in: state)) }
            for elem in sv {
                var bound = state
                bound["_q"] = elem
                if case .bool(true) = try evaluate(predicate, in: bound) {
                    return .bool(true)
                }
            }
            return .bool(false)

        case .choose(let set, let predicate):
            guard case .set(let sv) = try evaluate(set, in: state) else { throw typeMismatch("CHOOSE", got: try evaluate(set, in: state)) }
            for elem in sv {
                var bound = state
                bound["_q"] = elem
                if case .bool(true) = try evaluate(predicate, in: bound) {
                    return elem
                }
            }
            throw typeMismatch("CHOOSE: no element satisfies predicate")

        case .enabledAction(let name):
            if let val = state["_enabled_\(name)"], case .bool(let b) = val { return .bool(b) }
            return .bool(false)

        case .caseExpr(let pairs, let other):
            for i in stride(from: 0, to: pairs.count, by: 2) {
                if case .bool(true) = try evaluate(pairs[i], in: state) {
                    return try evaluate(pairs[i + 1], in: state)
                }
            }
            if let other = other { return try evaluate(other, in: state) }
            throw typeMismatch("CASE: no branch matched")
        }
    }

    public static func evaluateBool(_ expr: StateExpr, in state: [String: TLAValue]) throws -> Bool {
        guard case .bool(let b) = try evaluate(expr, in: state) else {
            throw EvalError.typeMismatch("Expected boolean expression, got \(try evaluate(expr, in: state))")
        }
        return b
    }

    private static func substituteVariable(_ name: String, _ value: TLAValue, in expr: StateExpr) -> StateExpr {
        switch expr {
        case .variable(let n) where n == name: return .value(value)
        case .variable: return expr
        case .value: return expr
        default: return expr  // shallow substitution — only direct var refs for set filter/map
        }
    }

    private static func tlaValueToString(_ v: TLAValue) -> String {
        switch v {
        case .int(let n): return "\(n)"
        case .string(let s): return s
        case .bool(let b): return "\(b)"
        case .tuple, .record, .set: return v.description
        case .constant(let name): return name
        }
    }

    private static func intOp(_ a: StateExpr, _ b: StateExpr, _ op: (Int, Int) throws -> Int, in state: [String: TLAValue]) throws -> TLAValue {
        guard case .int(let na) = try evaluate(a, in: state), case .int(let nb) = try evaluate(b, in: state) else {
            throw typeMismatch("arithmetic", got: try evaluate(a, in: state), try evaluate(b, in: state))
        }
        return .int(try op(na, nb))
    }

    private static func intUnary(_ a: StateExpr, _ op: (Int) -> Int, in state: [String: TLAValue]) throws -> TLAValue {
        guard case .int(let n) = try evaluate(a, in: state) else { throw typeMismatch("unary", got: try evaluate(a, in: state)) }
        return .int(op(n))
    }

    private static func intCmp(_ a: StateExpr, _ b: StateExpr, _ op: (Int, Int) -> Bool, in state: [String: TLAValue]) throws -> TLAValue {
        guard case .int(let na) = try evaluate(a, in: state), case .int(let nb) = try evaluate(b, in: state) else {
            throw typeMismatch("comparison", got: try evaluate(a, in: state), try evaluate(b, in: state))
        }
        return .bool(op(na, nb))
    }

    private static func typeMismatch(_ op: String, got: TLAValue...) -> EvalError {
        .typeMismatch("\(op): expected matching types, got \(got.map(\.description).joined(separator: ", "))")
    }
}
