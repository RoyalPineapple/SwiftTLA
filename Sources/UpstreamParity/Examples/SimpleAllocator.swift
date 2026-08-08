import SwiftTLA

extension Example {
    public static let simpleAllocator = Entry(
        id: "allocator/SimpleAllocator",
        upstreamSpec: "allocator",
        upstreamModule: "specifications/allocator/SimpleAllocator.tla",
        upstreamCfg: "specifications/allocator/SimpleAllocator.cfg",
        expectedDistinct: 400,
        spec: simpleAllocatorSpec(),
        notes: "Clients={c1,c2,c3} Resources={r1,r2}. Request/Allocate/Return. TLC = 400.",
    )

    /// Faithful SimpleAllocator (Stephan Merz) for the standard TLC constants.
static func simpleAllocatorSpec() -> TLASpec {
        let clients = ["c1", "c2", "c3"]
        let nonemptySubsets: [TLAValue] = [
            .set([.string("r1")]),
            .set([.string("r2")]),
            .set([.string("r1"), .string("r2")])
        ]
        let unsat = Var<TLAFunctionType>("unsat")
        let alloc = Var<TLAFunctionType>("alloc")
        let emptyFun = TLAValue.function([
            .string("c1"): .set([]),
            .string("c2"): .set([]),
            .string("c3"): .set([])
        ])

        func allocOf(_ c: String) -> StateExpr {
            .functionApply(.variable("alloc"), .value(.string(c)))
        }
        func unsatOf(_ c: String) -> StateExpr {
            .functionApply(.variable("unsat"), .value(.string(c)))
        }
        let resources: StateExpr = .setLiteral([
            .value(.string("r1")), .value(.string("r2"))
        ])
        let available = resources.subtracting(
            allocOf("c1").union(allocOf("c2")).union(allocOf("c3"))
        )

        return TLASpec("SimpleAllocator") {
            Extends("Integers, FiniteSets")
            Variable(unsat, emptyFun)
            Variable(alloc, emptyFun)

            for c in clients {
                for (si, sVal) in nonemptySubsets.enumerated() {
                    let subset = StateExpr.value(sVal)
                    Action("Request_\(c)_S\(si)") {
                        unsatOf(c).cardinality == 0 && allocOf(c).cardinality == 0
                            && unsat.becomes(unsat.updated(at: c, to: subset))
                    }
                    Action("Allocate_\(c)_S\(si)") {
                        subset.cardinality > 0
                            && subset.isSubset(of: available.intersection(unsatOf(c)))
                            && alloc.becomes(alloc.updated(at: c, to: allocOf(c).union(subset)))
                            && unsat.becomes(unsat.updated(at: c, to: unsatOf(c).subtracting(subset)))
                    }
                    Action("Return_\(c)_S\(si)") {
                        subset.cardinality > 0 && subset.isSubset(of: allocOf(c))
                            && alloc.becomes(alloc.updated(at: c, to: allocOf(c).subtracting(subset)))
                    }
                }
            }

            Invariant("TypeInvariant") {
                unsatOf("c1").cardinality >= 0
            }
            Invariant("ResourceMutex") {
                allocOf("c1").intersection(allocOf("c2")).cardinality == 0
                    && allocOf("c1").intersection(allocOf("c3")).cardinality == 0
                    && allocOf("c2").intersection(allocOf("c3")).cardinality == 0
            }
        }
    }

}
