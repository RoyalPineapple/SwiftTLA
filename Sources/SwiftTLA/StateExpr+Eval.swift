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

extension StateExpr {
    public typealias RuntimeFunc = @Sendable ([TLAValue]) -> TLAValue

    private enum RecursiveFunction: String {
        case sum = "Sum"
        case seqFromSet = "SeqFromSet"
    }

    public func evaluate(in state: [String: TLAValue],
                          runtimeFuncs: [String: RuntimeFunc] = [:],
                          recursiveFuncs: [RecursiveFunc] = [],
                          maxDepth: Int = 1000) throws -> TLAValue {
        func tm(_ op: String, got: TLAValue...) -> EvalError {
            .typeMismatch("\(op): expected matching types, got \(got.map(\.description).joined(separator: ", "))")
        }
        func str(_ v: TLAValue) -> String {
            switch v {
            case .int(let n): return "\(n)"
            case .string(let s): return s
            case .bool(let b): return "\(b)"
            case .tuple, .record, .set, .function: return v.description
            case .constant(let name): return name
            }
        }
        func ev(_ expr: StateExpr) throws -> TLAValue {
            try expr.evaluate(in: state, runtimeFuncs: runtimeFuncs, recursiveFuncs: recursiveFuncs, maxDepth: maxDepth)
        }
        func evDepth(_ expr: StateExpr, _ depth: Int) throws -> TLAValue {
            try expr.evaluate(in: state, runtimeFuncs: runtimeFuncs, recursiveFuncs: recursiveFuncs, maxDepth: depth)
        }

        func intOp(_ a: StateExpr, _ b: StateExpr, _ op: (Int, Int) throws -> Int) throws -> TLAValue {
            guard case .int(let na) = try ev(a), case .int(let nb) = try ev(b) else {
                throw tm("arithmetic", got: try ev(a), try ev(b))
            }
            return .int(try op(na, nb))
        }
        func intUnary(_ a: StateExpr, _ op: (Int) -> Int) throws -> TLAValue {
            guard case .int(let n) = try ev(a) else { throw tm("unary", got: try ev(a)) }
            return .int(op(n))
        }
        func intCmp(_ a: StateExpr, _ b: StateExpr, _ op: (Int, Int) -> Bool) throws -> TLAValue {
            guard case .int(let na) = try ev(a), case .int(let nb) = try ev(b) else {
                throw tm("comparison", got: try ev(a), try ev(b))
            }
            return .bool(op(na, nb))
        }

        switch self {
        case .value(let v): return v
        case .variable(let name):
            guard let val = state[name] else { throw EvalError.undefinedVariable(name) }
            return val

        case .add(let a, let b): return try intOp(a, b, +)
        case .subtract(let a, let b): return try intOp(a, b, -)
        case .multiply(let a, let b): return try intOp(a, b, *)
        case .divide(let a, let b): return try intOp(a, b, { guard $1 != 0 else { throw EvalError.divisionByZero }; return $0 / $1 })
        case .modulo(let a, let b): return try intOp(a, b, { guard $1 != 0 else { throw EvalError.divisionByZero }; return $0 % $1 })
        case .negate(let a): return try intUnary(a, -)
        case .integerDivide(let a, let b): return try intOp(a, b, { guard $1 != 0 else { throw EvalError.divisionByZero }; return $0 / $1 })

        case .equal(let a, let b): return .bool(try ev(a) == ev(b))
        case .notEqual(let a, let b): return .bool(try ev(a) != ev(b))
        case .lessThan(let a, let b): return try intCmp(a, b, <)
        case .lessOrEqual(let a, let b): return try intCmp(a, b, <=)
        case .greaterThan(let a, let b): return try intCmp(a, b, >)
        case .greaterOrEqual(let a, let b): return try intCmp(a, b, >=)

        case .and(let a, let b):
            guard case .bool(let ba) = try ev(a) else { throw tm("∧", got: try ev(a)) }
            if !ba { return .bool(false) }
            guard case .bool(let bb) = try ev(b) else { throw tm("∧", got: try ev(b)) }
            return .bool(bb)

        case .or(let a, let b):
            guard case .bool(let ba) = try ev(a) else { throw tm("∨", got: try ev(a)) }
            if ba { return .bool(true) }
            guard case .bool(let bb) = try ev(b) else { throw tm("∨", got: try ev(b)) }
            return .bool(bb)

        case .not(let a):
            guard case .bool(let ba) = try ev(a) else { throw tm("¬", got: try ev(a)) }
            return .bool(!ba)

        case .ifThenElse(let c, let t, let f):
            guard case .bool(let bc) = try ev(c) else { throw tm("IF", got: try ev(c)) }
            return try ev(bc ? t : f)

        case .setLiteral(let elements):
            var result = Set<TLAValue>()
            for e in elements { result.insert(try ev(e)) }
            return .set(result)

        case .in(let elem, let s):
            let v = try ev(elem)
            guard case .set(let sv) = try ev(s) else { throw tm("∈", got: try ev(s)) }
            return .bool(sv.contains(v))

        case .subset(let a, let b):
            guard case .set(let sa) = try ev(a), case .set(let sb) = try ev(b) else {
                throw tm("⊆", got: try ev(a), try ev(b))
            }
            return .bool(sa.isSubset(of: sb))

        case .union(let a, let b):
            guard case .set(let sa) = try ev(a), case .set(let sb) = try ev(b) else {
                throw tm("∪", got: try ev(a), try ev(b))
            }
            return .set(sa.union(sb))

        case .intersection(let a, let b):
            guard case .set(let sa) = try ev(a), case .set(let sb) = try ev(b) else {
                throw tm("∩", got: try ev(a), try ev(b))
            }
            return .set(sa.intersection(sb))

        case .setDifference(let a, let b):
            guard case .set(let sa) = try ev(a), case .set(let sb) = try ev(b) else {
                throw tm("∖", got: try ev(a), try ev(b))
            }
            return .set(sa.subtracting(sb))

        case .cardinality(let s):
            guard case .set(let sv) = try ev(s) else { throw tm("cardinality", got: try ev(s)) }
            return .int(sv.count)

        case .setFilter(let s, let p):
            guard case .set(let sv) = try ev(s) else { throw tm("set filter", got: try ev(s)) }
            var result = Set<TLAValue>()
            for elem in sv {
                var boundState = state
                boundState["_x"] = elem
                let exprWithVar = Self.substituteVariable("_x", elem, in: p)
                if case .bool(true) = try ev(exprWithVar) {
                    result.insert(elem)
                }
            }
            return .set(result)

        case .setMap(let e, let s):
            guard case .set(let sv) = try ev(s) else { throw tm("set map", got: try ev(s)) }
            var result = Set<TLAValue>()
            for elem in sv {
                let exprWithVar = Self.substituteVariable("_x", elem, in: e)
                result.insert(try ev(exprWithVar))
            }
            return .set(result)

        case .powerSet(let s):
            guard case .set(let sv) = try ev(s) else { throw tm("SUBSET", got: try ev(s)) }
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
            guard case .set(let sv) = try ev(s) else { throw tm("UNION", got: try ev(s)) }
            var result = Set<TLAValue>()
            for elem in sv {
                guard case .set(let inner) = elem else { throw tm("UNION element not a set", got: elem) }
                result.formUnion(inner)
            }
            return .set(result)

        case .tupleLiteral(let elements):
            return .tuple(try elements.map { try ev($0) })

        case .tupleAccess(let t, let index):
            guard case .tuple(let tv) = try ev(t) else { throw tm("tuple access", got: try ev(t)) }
            guard index >= 1, index <= tv.count else { throw EvalError.indexOutOfBounds(index, tv.count) }
            return tv[index - 1]

        case .tupleLength(let t):
            guard case .tuple(let tv) = try ev(t) else { throw tm("Len", got: try ev(t)) }
            return .int(tv.count)

        case .tupleAppend(let t, let e):
            guard case .tuple(var tv) = try ev(t) else { throw tm("Append", got: try ev(t)) }
            tv.append(try ev(e))
            return .tuple(tv)

        case .tupleHead(let t):
            guard case .tuple(let tv) = try ev(t) else { throw tm("Head", got: try ev(t)) }
            guard !tv.isEmpty else { throw tm("Head of empty sequence") }
            return tv[0]
        case .tupleTail(let t):
            guard case .tuple(let tv) = try ev(t) else { throw tm("Tail", got: try ev(t)) }
            guard !tv.isEmpty else { throw tm("Tail of empty sequence") }
            return .tuple(Array(tv.dropFirst()))
        case .tupleConcatenate(let a, let b):
            guard case .tuple(let ta) = try ev(a), case .tuple(let tb) = try ev(b) else {
                throw tm("tuple concat", got: try ev(a), try ev(b))
            }
            return .tuple(ta + tb)

        case .recordLiteral(let fields):
            var result: [String: TLAValue] = [:]
            for (key, expr) in fields { result[key] = try ev(expr) }
            return .record(result)

        case .recordAccess(let r, let field):
            guard case .record(let rv) = try ev(r) else { throw tm("record access", got: try ev(r)) }
            guard let val = rv[field] else { throw tm("record field '\(field)' not found") }
            return val

        case .domain(let f):
            let value = try ev(f)
            switch value {
            case .function(let mapping): return .set(Set(mapping.keys))
            case .record(let record): return .set(Set(record.keys.map { .string($0) }))
            default: throw tm("DOMAIN", got: value)
            }

        case .functionLiteral(let domain, let body):
            guard case .set(let domainSet) = try ev(domain) else {
                throw tm("function domain", got: try ev(domain))
            }
            var mapping: [TLAValue: TLAValue] = [:]
            for element in domainSet {
                let substituted = Self.substituteVariable("_x", element, in: body)
                mapping[element] = try ev(substituted)
            }
            return .function(mapping)

        case .functionApply(let function, let argument):
            let functionValue = try ev(function)
            let key = try ev(argument)
            switch functionValue {
            case .function(let mapping):
                guard let result = mapping[key] else {
                    throw tm("function apply: key \(key) not found in domain")
                }
                return result
            case .record(let record):
                guard let result = record[str(key)] else {
                    throw tm("record field not found")
                }
                return result
            default:
                throw tm("function apply", got: functionValue)
            }

        case .except(let function, let keyExpr, let valueExpr):
            let functionValue = try ev(function)
            let key = try ev(keyExpr)
            let newValue = try ev(valueExpr)
            switch functionValue {
            case .function(var mapping):
                mapping[key] = newValue
                return .function(mapping)
            case .record(var record):
                record[str(key)] = newValue
                return .record(record)
            default:
                throw tm("EXCEPT", got: functionValue)
            }

        case .forAll(let set, let predicate):
            guard case .set(let sv) = try ev(set) else { throw tm("∀", got: try ev(set)) }
            for elem in sv {
                let substituted = Self.substituteVariable("_x", elem, in: predicate)
                if case .bool(false) = try ev(substituted) {
                    return .bool(false)
                }
            }
            return .bool(true)

        case .exists(let set, let predicate):
            guard case .set(let sv) = try ev(set) else { throw tm("∃", got: try ev(set)) }
            for elem in sv {
                let substituted = Self.substituteVariable("_x", elem, in: predicate)
                if case .bool(true) = try ev(substituted) {
                    return .bool(true)
                }
            }
            return .bool(false)

        case .choose(let set, let predicate):
            guard case .set(let sv) = try ev(set) else { throw tm("CHOOSE", got: try ev(set)) }
            for elem in sv {
                let substituted = Self.substituteVariable("_x", elem, in: predicate)
                if case .bool(true) = try ev(substituted) {
                    return elem
                }
            }
            throw tm("CHOOSE: no element satisfies predicate")

        case .enabledAction(let name):
            if let val = state["_enabled_\(name)"], case .bool(let b) = val { return .bool(b) }
            return .bool(false)

        case .sequenceFromSet(let s):
            guard case .set(let sv) = try ev(s) else { throw tm("SeqFromSet", got: try ev(s)) }
            return .tuple(sv.sorted())

        case .setSum(let f, let s):
            guard case .set(let sv) = try ev(s) else { throw tm("Sum set", got: try ev(s)) }
            let fval = try ev(f)
            guard case .function(let mapping) = fval else { throw tm("Sum function", got: fval) }
            var total = 0
            for elem in sv {
                guard let val = mapping[elem], case .int(let n) = val else { throw tm("Sum value", got: mapping[elem] ?? .bool(false)) }
                total += n
            }
            return .int(total)

        case .functionSet(let domain, let range):
            guard case .set(let domainSet) = try ev(domain) else { throw tm("functionSet domain", got: try ev(domain)) }
            guard case .set(let rangeSet) = try ev(range) else { throw tm("functionSet range", got: try ev(range)) }
            let domainArr = domainSet.sorted()
            let rangeArr = rangeSet.sorted()
            var result = Set<TLAValue>()
            func build(_ idx: Int, _ cur: [(TLAValue, TLAValue)]) {
                if idx == domainArr.count {
                    result.insert(.function(Dictionary(uniqueKeysWithValues: cur)))
                    return
                }
                for r in rangeArr {
                    build(idx + 1, cur + [(domainArr[idx], r)])
                }
            }
            if !domainArr.isEmpty { build(0, []) } else { result.insert(.function([:])) }
            return .set(result)

        case .caseExpr(let pairs, let other):
            for i in stride(from: 0, to: pairs.count, by: 2) {
                if case .bool(true) = try ev(pairs[i]) {
                    return try ev(pairs[i + 1])
                }
            }
            if let other = other { return try ev(other) }
            throw tm("CASE: no branch matched")

        case .recursiveCall(let name, let args):
            if let impl = runtimeFuncs[name] {
                let evald = try args.map { try ev($0) }
                return impl(evald)
            }
            if let def = recursiveFuncs.first(where: { $0.name == name }) {
                let evald = try args.map { try ev($0) }
                var body = def.body
                for (i, param) in def.params.enumerated() where i < evald.count {
                    body = Self.substituteVariable(param, evald[i], in: body)
                }
                guard maxDepth > 0 else { throw EvalError.typeMismatch("Recursion depth exceeded") }
                return try evDepth(body, maxDepth - 1)
            }
            guard let builtin = RecursiveFunction(rawValue: name) else {
                throw tm("Unknown recursive function: \(name)")
            }
            switch builtin {
            case .sum:
                guard args.count == 2 else { throw tm("Sum requires 2 args") }
                let fval = try ev(args[0])
                let sval = try ev(args[1])
                guard case .function(let mapping) = fval else { throw tm("Sum function", got: fval) }
                guard case .set(let sv) = sval else { throw tm("Sum set", got: sval) }
                var total = 0
                for elem in sv {
                    guard let v = mapping[elem], case .int(let n) = v else { throw tm("Sum value", got: mapping[elem] ?? .bool(false)) }
                    total += n
                }
                return .int(total)
            case .seqFromSet:
                guard args.count == 1 else { throw tm("SeqFromSet requires 1 arg") }
                guard case .set(let sv) = try ev(args[0]) else { throw tm("SeqFromSet", got: try ev(args[0])) }
                return .tuple(sv.sorted())
            }
        }
    }

    public func evaluateBool(in state: [String: TLAValue],
                              runtimeFuncs: [String: RuntimeFunc] = [:],
                              recursiveFuncs: [RecursiveFunc] = []) throws -> Bool {
        guard case .bool(let b) = try self.evaluate(in: state, runtimeFuncs: runtimeFuncs, recursiveFuncs: recursiveFuncs) else {
            throw EvalError.typeMismatch("Expected boolean expression, got \(try self.evaluate(in: state, runtimeFuncs: runtimeFuncs, recursiveFuncs: recursiveFuncs))")
        }
        return b
    }

    public static func substituteVariable(_ name: String, _ value: TLAValue, in expr: StateExpr) -> StateExpr {
        switch expr {
        case .variable(let n) where n == name: return .value(value)
        case .variable: return expr
        case .value, .enabledAction: return expr
        case .add(let l, let r): return .add(sub(l), sub(r))
        case .subtract(let l, let r): return .subtract(sub(l), sub(r))
        case .multiply(let l, let r): return .multiply(sub(l), sub(r))
        case .divide(let l, let r): return .divide(sub(l), sub(r))
        case .modulo(let l, let r): return .modulo(sub(l), sub(r))
        case .negate(let x): return .negate(sub(x))
        case .integerDivide(let l, let r): return .integerDivide(sub(l), sub(r))
        case .equal(let l, let r): return .equal(sub(l), sub(r))
        case .notEqual(let l, let r): return .notEqual(sub(l), sub(r))
        case .lessThan(let l, let r): return .lessThan(sub(l), sub(r))
        case .lessOrEqual(let l, let r): return .lessOrEqual(sub(l), sub(r))
        case .greaterThan(let l, let r): return .greaterThan(sub(l), sub(r))
        case .greaterOrEqual(let l, let r): return .greaterOrEqual(sub(l), sub(r))
        case .and(let l, let r): return .and(sub(l), sub(r))
        case .or(let l, let r): return .or(sub(l), sub(r))
        case .not(let x): return .not(sub(x))
        case .ifThenElse(let c, let t, let e): return .ifThenElse(sub(c), sub(t), sub(e))
        case .setLiteral(let es): return .setLiteral(es.map(sub))
        case .in(let e, let s): return .in(sub(e), sub(s))
        case .subset(let a, let b): return .subset(sub(a), sub(b))
        case .union(let a, let b): return .union(sub(a), sub(b))
        case .intersection(let a, let b): return .intersection(sub(a), sub(b))
        case .setDifference(let a, let b): return .setDifference(sub(a), sub(b))
        case .cardinality(let s): return .cardinality(sub(s))
        case .setFilter(let s, let p): return .setFilter(sub(s), sub(p))
        case .setMap(let e, let s): return .setMap(sub(e), sub(s))
        case .powerSet(let s): return .powerSet(sub(s))
        case .unionAll(let s): return .unionAll(sub(s))
        case .tupleLiteral(let es): return .tupleLiteral(es.map(sub))
        case .tupleAccess(let t, let i): return .tupleAccess(sub(t), i)
        case .tupleLength(let t): return .tupleLength(sub(t))
        case .tupleAppend(let t, let e): return .tupleAppend(sub(t), sub(e))
        case .tupleHead(let t): return .tupleHead(sub(t))
        case .tupleTail(let t): return .tupleTail(sub(t))
        case .tupleConcatenate(let a, let b): return .tupleConcatenate(sub(a), sub(b))
        case .recordLiteral(let fs): return .recordLiteral(fs.mapValues(sub))
        case .recordAccess(let r, let f): return .recordAccess(sub(r), f)
        case .domain(let f): return .domain(sub(f))
        case .functionLiteral(let d, let body): return .functionLiteral(sub(d), sub(body))
        case .functionApply(let f, let x): return .functionApply(sub(f), sub(x))
        case .except(let f, let x, let e): return .except(sub(f), sub(x), sub(e))
        case .caseExpr(let ps, let fb): return .caseExpr(ps.map(sub), fb.map(sub))
        case .forAll(let s, let p): return .forAll(sub(s), sub(p))
        case .exists(let s, let p): return .exists(sub(s), sub(p))
        case .choose(let s, let p): return .choose(sub(s), sub(p))
        case .sequenceFromSet(let s): return .sequenceFromSet(sub(s))
        case .setSum(let f, let s): return .setSum(sub(f), sub(s))
        case .functionSet(let d, let r): return .functionSet(sub(d), sub(r))
        case .recursiveCall(let n, let a): return .recursiveCall(n, a.map(sub))
        }

        func sub(_ e: StateExpr) -> StateExpr { Self.substituteVariable(name, value, in: e) }
    }
}
