import SwiftTLA
import SwiftTLAMacros

package struct SimpleAllocatorModel: Sendable {
    package enum Client: String, CaseIterable, FiniteTLAValueDomain {
        case c1, c2, c3

        package static var defaultValue: Self { .c1 }
        package static let finiteValues = allCases
    }

    package enum Resource: String, CaseIterable, FiniteTLAValueDomain {
        case r1, r2

        package static var defaultValue: Self { .r1 }
        package static let finiteValues = allCases
    }

    private enum RequestedResources: CaseIterable, FiniteTLAValueDomain {
        case r1, r2, both

        static var defaultValue: Self { .r1 }
        static let finiteValues = allCases

        var tlaValue: TLAValue {
            switch self {
            case .r1: SetExpr<Resource>(.r1).tlaValue
            case .r2: SetExpr<Resource>(.r2).tlaValue
            case .both: SetExpr<Resource>(.r1, .r2).tlaValue
            }
        }

        init?(formalValue: TLAValue) {
            switch formalValue {
            case SetExpr<Resource>(.r1).tlaValue: self = .r1
            case SetExpr<Resource>(.r2).tlaValue: self = .r2
            case SetExpr<Resource>(.r1, .r2).tlaValue: self = .both
            default: return nil
            }
        }
    }

    package static var spec: TLASpec {
        let unsat = Var<Function<Client, SetExpr<Resource>>>("unsat")
        let alloc = Var<Function<Client, SetExpr<Resource>>>("alloc")
        let client = Expr<Client>(.variable("client"))
        let resources = Expr<SetExpr<Resource>>(.variable("resources"))
        let emptyAllocation = Function<Client, SetExpr<Resource>>.literal(
            (.c1, SetExpr<Resource>()),
            (.c2, SetExpr<Resource>()),
            (.c3, SetExpr<Resource>())
        )
        let available = SetExpr<Resource>.literal(.r1, .r2).raw.subtracting(
            alloc[.c1].raw.union(alloc[.c2]).union(alloc[.c3])
        )

        return #spec("SimpleAllocator") {
            Extends(.integers, .finiteSets)
            Variable(computed: unsat) { emptyAllocation.raw }
            Variable(computed: alloc) { emptyAllocation.raw }

            SwiftTLA.Action("Request", parameters: [
                ActionParameter("client", values: Client.finiteValues),
                ActionParameter("resources", values: RequestedResources.finiteValues)
            ]) {
                unsat[client].isEmpty && alloc[client].isEmpty
                    && unsat.becomes(unsat.updating(client, to: resources))
            }
            SwiftTLA.Action("Allocate", parameters: [
                ActionParameter("client", values: Client.finiteValues),
                ActionParameter("resources", values: RequestedResources.finiteValues)
            ]) {
                resources.cardinality > 0
                    && resources.isSubset(of: available.intersection(unsat[client]))
                    && alloc.becomes(alloc.updating(client, to: alloc[client].union(resources)))
                    && unsat.becomes(unsat.updating(
                        client,
                        to: Expr<SetExpr<Resource>>(unsat[client].raw.subtracting(resources))
                    ))
            }
            SwiftTLA.Action("Return", parameters: [
                ActionParameter("client", values: Client.finiteValues),
                ActionParameter("resources", values: RequestedResources.finiteValues)
            ]) {
                resources.cardinality > 0 && resources.isSubset(of: alloc[client])
                    && alloc.becomes(alloc.updating(
                        client,
                        to: Expr<SetExpr<Resource>>(alloc[client].raw.subtracting(resources))
                    ))
            }

            Invariant("TypeInvariant") {
                unsat[.c1].cardinality >= 0
            }
            Invariant("ResourceMutex") {
                alloc[.c1].intersection(alloc[.c2]).cardinality == 0
                    && alloc[.c1].intersection(alloc[.c3]).cardinality == 0
                    && alloc[.c2].intersection(alloc[.c3]).cardinality == 0
            }
        }
    }
}

extension Example {
    package static let simpleAllocator = Entry(
        id: "allocator/SimpleAllocator",
        upstreamSpec: "allocator",
        upstreamModule: "specifications/allocator/SimpleAllocator.tla",
        upstreamCfg: "specifications/allocator/SimpleAllocator.cfg",
        expectedDistinct: 400,
        spec: SimpleAllocatorModel.spec,
        notes: "Clients={c1,c2,c3} Resources={r1,r2}. Request/Allocate/Return. TLC = 400.",
    )
}
