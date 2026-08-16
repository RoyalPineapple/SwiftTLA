import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

extension TLASpec {
  public var swiftSource: String {
    var lines: [String] = []
    lines.append("@TLAModel")
    lines.append("public struct \(name.replacingOccurrences(of: " ", with: "")) {")
    lines.append("    static var spec: TLASpec {")
    lines.append("        TLASpec(\"\(name)\") {")
    if extendsModules != "Integers" { lines.append("            Extends(\"\(extendsModules)\")") }
    for (k, v) in constants.sorted(by: { $0.key < $1.key }) {
      lines.append("            Constant(\"\(k)\", \(v.swiftLiteral))")
    }
    for v in variables {
      switch v.collectionType {
      case .set:
        lines.append("            Variable(\"\(v.name)\", .set([]))")
      case .array(let count):
        let values = Array(repeating: ".int(0)", count: count).joined(separator: ", ")
        lines.append("            Variable(\"\(v.name)\", .tuple([\(values)]))")
      case .dictionary(let scope):
        lines.append("            Variable(\"\(v.name)\", .function([:])) // former verification scope: \(scope)")
      case .scalar:
        lines.append("            Var<Int>(\"\(v.name)\", \(v.initial.swiftLiteral))")
      }
    }
    for action in actions {
      let parameters = action.bindings.map { binding in
        "ActionParameter(\"\(binding.name)\", values: [\(binding.values.map(\.swiftLiteral).joined(separator: ", "))])"
      }
      if parameters.isEmpty {
        lines.append("            Action(\"\(action.name)\") { \(action.body.swiftSource) }")
      } else {
        lines.append(
          "            Action(\"\(action.name)\", parameters: [\(parameters.joined(separator: ", "))]) { \(action.body.swiftSource) }"
        )
      }
    }
    for i in invariants {
      lines.append("            Invariant(\"\(i.name)\") { \(i.body.swiftSource) }")
    }
    for t in temporalProperties {
      lines.append("            Temporal(\"\(t.name)\") { \(t.expr.swiftSource) }")
    }
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    return lines.joined(separator: "\n")
  }
}

extension TLAValue {
  public var swiftLiteral: String {
    switch self {
    case .int(let n): return "\(n)"
    case .bool(let b): return "\(b)"
    case .string(let s): return "\"\(s)\""
    case .set(let s): return "StateExpr.set([\(s.map(\.swiftLiteral).joined(separator: ", "))])"
    case .tuple(let t): return "StateExpr.tuple([\(t.map(\.swiftLiteral).joined(separator: ", "))])"
    case .record(let r):
      return
        "StateExpr.record([\(r.sorted(by: { $0.key<$1.key }).map { "\"\($0.key)\": \($0.value.swiftLiteral)" }.joined(separator: ", "))])"
    case .function: return "StateExpr.function(domain: StateExpr.set([]), 0)"  // placeholder
    case .constant(let n): return "TLAValue.constant(\"\(n)\")"
    }
  }
}

extension ActionExpr {
  var swiftSource: String {
    switch self {
    case .assign(let v, let e): return "\(v).becomes(\(e.swiftSource))"
    case .unchanged(let v): return "\(v).stays"
    case .guard_(let e): return e.swiftSource
    case .chooseAction(let v, let s): return "ActionExpr.choose(\"\(v)\", from: \(s.swiftSource))"
    case .and(let a, let b): return "\(a.swiftSource) && \(b.swiftSource)"
    case .or(let a, let b): return "\(a.swiftSource) || \(b.swiftSource)"
    case .ifElse(let c, let t, let e):
      return "ActionExpr.ifElse(\(c.swiftSource), then: \(t.swiftSource), else: \(e.swiftSource))"
    case .define(let v, let exp, let b):
      return "ActionExpr.define(\"\(v)\", \(exp.swiftSource)) { \(b.swiftSource) }"
    case .existsAction(let v, let s, let b):
      return "ActionExpr.exists(\"\(v)\", from: \(s.swiftSource)) { _ in \(b.swiftSource) }"
    }
  }
}

extension StateExpr {
  public var swiftSource: String {
    switch self {
    case .value(let v): return v.swiftLiteral
    case .variable(let n): return n
    case .add(let a, let b): return "\(a.swiftSource) + \(b.swiftSource)"
    case .subtract(let a, let b): return "\(a.swiftSource) - \(b.swiftSource)"
    case .multiply(let a, let b): return "\(a.swiftSource) * \(b.swiftSource)"
    case .divide(let a, let b): return "\(a.swiftSource) / \(b.swiftSource)"
    case .modulo(let a, let b): return "\(a.swiftSource) % \(b.swiftSource)"
    // Preserve a negation node instead of letting Swift parse a literal such
    // as `-1`; the distinction matters to the parser/builder fidelity gate.
    case .negate(let a): return "StateExpr.negate(\(a.swiftSource))"
    case .equal(let a, let b): return "\(a.swiftSource) == \(b.swiftSource)"
    case .notEqual(let a, let b): return "\(a.swiftSource) != \(b.swiftSource)"
    case .lessThan(let a, let b): return "\(a.swiftSource) < \(b.swiftSource)"
    case .lessOrEqual(let a, let b): return "\(a.swiftSource) <= \(b.swiftSource)"
    case .greaterThan(let a, let b): return "\(a.swiftSource) > \(b.swiftSource)"
    case .greaterOrEqual(let a, let b): return "\(a.swiftSource) >= \(b.swiftSource)"
    case .and(let a, let b): return "\(a.swiftSource) && \(b.swiftSource)"
    case .or(let a, let b): return "\(a.swiftSource) || \(b.swiftSource)"
    case .not(let a): return "!\(a.swiftSource)"
    case .in(let a, let b): return "\(a.swiftSource).isIn(\(b.swiftSource))"
    case .setLiteral(let es):
      return "StateExpr.set([\(es.map(\.swiftSource).joined(separator: ", "))])"
    case .ifThenElse(let c, let t, let f):
      return "StateExpr.if(\(c.swiftSource), then: \(t.swiftSource), else: \(f.swiftSource))"
    case .integerDivide(let a, let b):
      return "\(a.swiftSource).integerDivided(by: \(b.swiftSource))"
    case .subset(let a, let b): return "\(a.swiftSource).isSubset(of: \(b.swiftSource))"
    case .union(let a, let b): return "\(a.swiftSource).union(\(b.swiftSource))"
    case .intersection(let a, let b): return "\(a.swiftSource).intersection(\(b.swiftSource))"
    case .setDifference(let a, let b): return "\(a.swiftSource).subtracting(\(b.swiftSource))"
    case .cardinality(let e): return "\(e.swiftSource).cardinality"
    case .powerSet(let e): return "\(e.swiftSource).subsets"
    case .unionAll(let e): return "\(e.swiftSource).flattened"
    case .domain(let e): return "\(e.swiftSource).domain"
    case .functionApply(let f, let a): return "\(f.swiftSource).applying(\(a.swiftSource))"
    case .except(let f, let k, let v):
      return "\(f.swiftSource).updated(at: \(k.swiftSource), to: \(v.swiftSource))"
    case .tupleLiteral(let es):
      return "StateExpr.tuple([\(es.map(\.swiftSource).joined(separator: ", "))])"
    case .tupleAccess(let t, let i): return "\(t.swiftSource).at(\(i))"
    case .tupleDynamicAccess(let tuple, let index): return "\(tuple.swiftSource).at(\(index.swiftSource))"
    case .tupleLength(let t): return "\(t.swiftSource).count"
    case .tupleHead(let t): return "\(t.swiftSource).head"
    case .tupleTail(let t): return "\(t.swiftSource).tail"
    case .tupleAppend(let t, let e): return "\(t.swiftSource).appending(\(e.swiftSource))"
    case .tupleConcatenate(let a, let b): return "\(a.swiftSource).concatenating(\(b.swiftSource))"
    case .recordLiteral(let fields):
      let sorted = fields.sorted(by: { $0.key < $1.key })
      let args = sorted.map { "\($0.key): \($0.value.swiftSource)" }.joined(separator: ", ")
      return "StateExpr.record(\(args))"
    case .recordAccess(let r, let f): return "\(r.swiftSource).\(f)"
    // Preserve binder identity in the formal source codec. The ergonomic
    // closure helpers deliberately create fresh binders, so serializing
    // through them would turn a bound name into an accidental free variable.
    case .setFilter(let s, let binder, let p):
      return "StateExpr.setFilter(\(s.swiftSource), \(String(reflecting: binder)), \(p.swiftSource))"
    case .setMap(let e, let binder, let s):
      return "StateExpr.setMap(\(e.swiftSource), \(String(reflecting: binder)), \(s.swiftSource))"
    case .integerRange(let lower, let upper): return "IntRange(\(lower.swiftSource), through: \(upper.swiftSource))"
    case .forAll(let s, let binder, let p):
      return "StateExpr.forAll(\(s.swiftSource), \(String(reflecting: binder)), \(p.swiftSource))"
    case .exists(let s, let binder, let p):
      return "StateExpr.exists(\(s.swiftSource), \(String(reflecting: binder)), \(p.swiftSource))"
    case .choose(let s, let binder, let p):
      return "StateExpr.choose(\(s.swiftSource), \(String(reflecting: binder)), \(p.swiftSource))"
    case .functionLiteral(let d, let binder, let b):
      return "StateExpr.functionLiteral(\(d.swiftSource), \(String(reflecting: binder)), \(b.swiftSource))"
    case .caseExpr(let pairs, let fallback):
      var parts: [String] = []
      for i in stride(from: 0, to: pairs.count, by: 2) {
        parts.append("(\(pairs[i].swiftSource), \(pairs[i+1].swiftSource))")
      }
      if let fb = fallback { parts.append("fallback: \(fb.swiftSource)") }
      return "StateExpr.firstMatch(\(parts.joined(separator: ", ")))"
    case .enabledAction(let name): return "StateExpr.enabled(\"\(name)\")"
    case .sequenceFromSet(let e): return "StateExpr.sequenceFromSet(\(e.swiftSource))"
    case .setSum(let f, let s): return "StateExpr.setSum(\(f.swiftSource), \(s.swiftSource))"
    case .functionSet(let d, let r):
      return "StateExpr.functionSet(\(d.swiftSource), \(r.swiftSource))"
    case .foldFunction(let operation, let initial, let sequence):
      let parameters = operation.parameters.map { "\"\($0)\"" }.joined(separator: ", ")
      return "StateExpr.foldFunction(FormalLambda(parameters: [\(parameters)], body: \(operation.body.swiftSource)), initial: \(initial.swiftSource), sequence: \(sequence.swiftSource))"
    case .operatorApplication(let operation, let arguments):
      let operatorSource: String
      switch operation {
      case .lambda(let lambda):
        let parameters = lambda.parameters.map { "\"\($0)\"" }.joined(separator: ", ")
        operatorSource = ".lambda(FormalLambda(parameters: [\(parameters)], body: \(lambda.body.swiftSource)))"
      case .reference(let name, let arity):
        operatorSource = ".reference(\"\(name)\", arity: \(arity))"
      }
      return "StateExpr.operatorApplication(\(operatorSource), [\(arguments.map(\.swiftSource).joined(separator: ", "))])"
    case .recursiveCall(let name, let args):
      let argsStr = args.map(\.swiftSource).joined(separator: ", ")
      return "StateExpr.recursiveCall(\"\(name)\", [\(argsStr)])"
    case .letValue(let name, let value, let body):
      return "StateExpr.letValue(\"\(name)\", \(value.swiftSource), \(body.swiftSource))"
    case .letIn(let operators, let body):
      let definitions = operators.map { operation in
        let parameters = operation.parameters.map { "\"\($0)\"" }.joined(separator: ", ")
        let domain = operation.domain.map { ", domain: \($0.swiftSource)" } ?? ""
        return "LocalOperator(\"\(operation.name)\", parameters: [\(parameters)]\(domain), body: \(operation.body.swiftSource))"
      }.joined(separator: ", ")
      return "StateExpr.letIn([\(definitions)], \(body.swiftSource))"
    }
  }
}

private extension FormalCallArgument {
  var swiftSource: String {
    switch self {
    case .value(let expression): return ".value(\(expression.swiftSource))"
    case .operator(let operation):
      switch operation {
      case .lambda(let lambda):
        let parameters = lambda.parameters.map { "\"\($0)\"" }.joined(separator: ", ")
        return ".operator(.lambda(FormalLambda(parameters: [\(parameters)], body: \(lambda.body.swiftSource))))"
      case .reference(let name, let arity):
        return ".operator(.reference(\"\(name)\", arity: \(arity)))"
      }
    }
  }
}

extension TemporalExpr {
  var swiftSource: String {
    switch self {
    case .always(let p): return "always(\(p.swiftSource))"
    case .eventually(let p): return "eventually(\(p.swiftSource))"
    case .alwaysEventually(let p): return "alwaysEventually(\(p.swiftSource))"
    case .eventuallyAlways(let p): return "eventuallyAlways(\(p.swiftSource))"
    case .leadsTo(let p, let q): return "\(p.swiftSource).leadsTo(\(q.swiftSource))"
    }
  }
}
