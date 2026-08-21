import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct SimpleAllocatorModel: Sendable {
    public static var spec: TLASpec {
        let clients = ["c1", "c2", "c3"]
        let nonemptySubsets: [TLAValue] = [
            .set([.string("r1")]),
            .set([.string("r2")]),
            .set([.string("r1"), .string("r2")])
        ]
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

        return #spec("SimpleAllocator") {
            Extends(.integers, .finiteSets)
            let unsat = Var<TLAValue>("unsat")
            let alloc = Var<TLAValue>("alloc")
            Variable(unsat, emptyFun)
            Variable(alloc, emptyFun)

            for c in clients {
                for (si, sVal) in nonemptySubsets.enumerated() {
                    let subset = StateExpr.value(sVal)
                    Action("Request_\(c)_S\(si)") {
                        unsatOf(c).cardinality == 0 && allocOf(c).cardinality == 0
                            && .assign(.named(unsat.name), unsat.stateExpr.updated(at: c, to: subset))
                    }
                    Action("Allocate_\(c)_S\(si)") {
                        subset.cardinality > 0
                            && subset.isSubset(of: available.intersection(unsatOf(c)))
                            && .assign(.named(alloc.name), alloc.stateExpr.updated(at: c, to: allocOf(c).union(subset)))
                            && .assign(.named(unsat.name), unsat.stateExpr.updated(at: c, to: unsatOf(c).subtracting(subset)))
                    }
                    Action("Return_\(c)_S\(si)") {
                        subset.cardinality > 0 && subset.isSubset(of: allocOf(c))
                            && .assign(.named(alloc.name), alloc.stateExpr.updated(at: c, to: allocOf(c).subtracting(subset)))
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

extension Example {
    public static let simpleAllocator = Entry(
        id: "allocator/SimpleAllocator",
        upstreamSpec: "allocator",
        upstreamModule: "specifications/allocator/SimpleAllocator.tla",
        upstreamCfg: "specifications/allocator/SimpleAllocator.cfg",
        expectedDistinct: 400,
        spec: SimpleAllocatorModel.spec,
        notes: "Clients={c1,c2,c3} Resources={r1,r2}. Request/Allocate/Return. TLC = 400.",
    )
}
