import SwiftTLA
import UpstreamParity
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args[0] == "list" {
    print("id\tdistinct\tupstream_match\tnotes")
    for e in ParityCatalog.all {
        let m = e.matchesUpstreamTLC ? "yes" : "no"
        print("\(e.id)\t\(e.expectedDistinct)\t\(m)\t\(e.notes)")
    }
    print("--- \(ParityCatalog.all.count) validated ports ---")
    exit(0)
}
if args[0] == "emit", args.count >= 2 {
    guard let e = ParityCatalog.entry(id: args[1]) else {
        fputs("unknown id: \(args[1])\n", stderr)
        exit(1)
    }
    print(e.spec.tlaModule, terminator: "")
    exit(0)
}
if args[0] == "check", args.count >= 2 {
    guard let e = ParityCatalog.entry(id: args[1]) else {
        fputs("unknown id: \(args[1])\n", stderr)
        exit(1)
    }
    do {
        let count = try ModelChecker(spec: e.spec, maxStates: 100_000).exploreGraph().states.count
        let ok = count == e.expectedDistinct
        print("\(e.id): \(count) (expected \(e.expectedDistinct)) \(ok ? "OK" : "FAIL")")
        exit(ok ? 0 : 2)
    } catch {
        fputs("error: \(error)\n", stderr)
        exit(1)
    }
}
fputs("""
Usage:
  examples list
  examples emit <id>
  examples check <id>
""", stderr)
exit(1)
