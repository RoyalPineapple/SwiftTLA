import SwiftTLA
import UpstreamParity
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let name = args.first else {
    fputs("""
    Usage: tlc-validate <name>
      operators: arithmetic comparison logic sets tuples records functions casexpr choose forall
      parity:    list | <ParityCatalog id>
    """, stderr)
    exit(1)
}

if name == "list" {
    for e in ParityCatalog.all {
        let flag = e.matchesUpstreamTLC ? "UPSTREAM" : "SLICE"
        print("\(e.id)\t\(e.expectedDistinct)\t\(flag)\t\(e.notes)")
    }
    exit(0)
}

let output: String

switch name {
case "arithmetic":
    let x = Var<Int>("x", value: 0)
    output = TLASpec("arithmetic") {
        Variable(x, 0)
        Action("add") { x.becomes(x + 1).when(x < 2) }
        Action("sub") { x.becomes(x - 1).when(x > 0) }
        Action("mul") { x.becomes(x * 2).when(x == 1) }
        Action("div") { x.becomes(x / 2).when(x == 2) }
        Action("mod") { x.becomes(x % 3).when(x == 0) }
        Action("neg") { x.becomes(-x).when(x == 1) }
    }.tlaModule

case "comparison":
    let x = Var<Int>("x", value: 0)
    output = TLASpec("comparison") {
        Variable(x, 0)
        Action("eq") { x.becomes(1).when(x == 0) }
        Action("neq") { x.becomes(2).when(x != 0) || x.becomes(0).when(x == 1) }
        Action("lt") { x.becomes(3).when(x < 2) }
        Action("gt") { x.becomes(4).when(x > 1) || x.becomes(0).when(x == 3) }
    }.tlaModule

case "logic":
    let a = Var<Bool>("a", value: false)
    let b = Var<Bool>("b", value: false)
    output = TLASpec("logic") {
        Variable(a, false); Variable(b, false)
        Action("toggle") {
            (a == false) && (b == false) && a.becomes(true) ||
            (a == true) && a.becomes(false) && b.becomes(true)
        }
    }.tlaModule

case "sets":
    let s = Var<TLASetType>("s")
    output = TLASpec("sets") {
        Variable(s, TLAValue.set([.int(0), .int(1)]))
        Action("remove") {
            s.cardinality > 0
                && s.becomes(s.subtracting(StateExpr.singleton(0))).when(s.cardinality == 2)
        }
        Action("shrink") {
            s.cardinality == 1 && s.becomes(StateExpr.setLiteral([]))
        }
    }.tlaModule

case "tuples":
    let val = Var<Int>("val", value: 0)
    output = TLASpec("tuples") {
        Variable(val, 0)
        Action("set") { val.becomes(StateExpr.tuple([1, 2]).count).when(val == 0) }
        Action("access") { val.becomes(StateExpr.tuple([5, 6]).at(1)).when(val == 2) }
    }.tlaModule

case "records":
    let r = Var<Int>("r", value: 0)
    output = TLASpec("records") {
        Variable(r, 0)
        Action("set") {
            r.becomes(StateExpr.record(["a": 3, "b": 7]).domain.cardinality).when(r == 0)
        }
    }.tlaModule

case "functions":
    let f = Var<Int>("f", value: 0)
    output = TLASpec("functions") {
        Variable(f, 0)
        Action("apply") {
            f.becomes(StateExpr.function(domain: StateExpr.set([1]), 42).applying(1)).when(f == 0)
        }
    }.tlaModule

case "casexpr":
    let x = Var<Int>("x", value: 0)
    output = TLASpec("casexpr") {
        Variable(x, 0)
        Action("classify") {
            x.becomes(StateExpr.firstMatch(
                (when: x == 0, then: 10),
                (when: x == 1, then: 20),
                fallback: 99
            )).when(x < 2)
        }
    }.tlaModule

case "choose":
    let picked = Var<Int>("picked", value: 0)
    let q = Var<TLASetType>("q")
    output = TLASpec("choose") {
        Variable(picked, 0)
        Variable(q, TLAValue.set([.int(0), .int(1)]))
        Action("pick") {
            q.cardinality > 0
                && choose(picked, from: q)
                && q.becomes(q.subtracting(StateExpr.singleton(picked)))
        }
    }.tlaModule

case "forall":
    let ok = Var<Bool>("ok", value: false)
    let s = StateExpr.set([1, 2])
    output = TLASpec("forall") {
        Variable(ok, false)
        Action("check") { StateExpr.for(allIn: s, 1 >= 0) && ok.becomes(true) }
    }.tlaModule

default:
    if let entry = ParityCatalog.entry(id: name) {
        output = entry.spec.tlaModule
    } else {
        fputs("Unknown spec: \(name)\n", stderr)
        fputs("Run: tlc-validate list\n", stderr)
        exit(1)
    }
}

print(output, terminator: "")
