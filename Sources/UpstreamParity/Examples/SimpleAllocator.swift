// Clients request resources, receive an allocation, and give resources back.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/allocator/SimpleAllocator.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct SimpleAllocatorModel: Sendable {
    package enum Client: String, CaseIterable, FiniteTLAValueDomain {
        case c1, c2, c3
        package static var defaultValue: Self { .c1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum Resource: String, CaseIterable, FiniteTLAValueDomain {
        case r1, r2
        package static var defaultValue: Self { .r1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case request = "Request", allocate = "Allocate", giveBack = "Return"
    }

    package static var spec: TLASpec {
        #spec("SimpleAllocator") { scope in
            Extends(.finiteSets)
            let Clients = scope.parameter(as: Set<Client>.self, in: Set<Set<Client>>([Set([.c1, .c2, .c3])]))
            let Resources = scope.parameter(as: Set<Resource>.self, in: Set<Set<Resource>>([Set([.r1, .r2])]))
            let choices = Subsets(of: Resources)
            let unsat = scope.sharedVar(initial: Dictionary<Client, Set<Resource>>.mapping(over: Clients) { _ in Set<Resource>() })
            let alloc = scope.sharedVar(initial: Dictionary<Client, Set<Resource>>.mapping(over: Clients) { _ in Set<Resource>() })
            Do(Step.request, over: Clients, choices) { client, requested in
                When(unsat[client].isEmpty && alloc[client].isEmpty && !requested.isEmpty)
                unsat[client].set(requested)
            }
            let allocate = Do(Step.allocate, over: Clients, choices) { client, granted in
                When(!granted.isEmpty && granted.isSubset(of: unsat[client]))
                When(Clients.allSatisfy { other in alloc[other].intersection(granted).isEmpty })
                alloc[client].set(alloc[client].union(granted))
                unsat[client].set(unsat[client].subtracting(granted))
            }
            let giveBack = Do(Step.giveBack, over: Clients, choices) { client, returned in
                When(!returned.isEmpty && returned.isSubset(of: alloc[client]))
                alloc[client].set(alloc[client].subtracting(returned))
            }

            // A Return changes a client's emptiness flag exactly when that client returns everything.
            WeakFairness(giveBack, on: alloc[Client.c1].isEmpty)
            WeakFairness(giveBack, on: alloc[Client.c2].isEmpty)
            WeakFairness(giveBack, on: alloc[Client.c3].isEmpty)
            StrongFairness(eachOf: [allocate])

            Invariant("TypeInvariant") {
                unsat.keys == Clients
                alloc.keys == Clients
                Clients.allSatisfy { client in
                    unsat[client].isSubset(of: Resources) && alloc[client].isSubset(of: Resources)
                }
            }
            Invariant("ResourceMutex") {
                Clients.allSatisfy { first in
                    Clients.allSatisfy { second in first == second || alloc[first].intersection(alloc[second]).isEmpty }
                }
            }
            let ClientsWillReturn = Temporal()
            ClientsWillReturn(forEach: Clients) { client in .leadsTo(unsat[client].isEmpty, alloc[client].isEmpty) }
            let ClientsWillObtain = Temporal()
            ClientsWillObtain(forEach: Clients) { client in .all([
                .leadsTo(unsat[client].contains(Resource.r1), alloc[client].contains(Resource.r1)),
                .leadsTo(unsat[client].contains(Resource.r2), alloc[client].contains(Resource.r2)),
            ]) }
            let InfOftenSatisfied = Temporal()
            InfOftenSatisfied(forEach: Clients) { client in .alwaysEventually(unsat[client].isEmpty) }
            Validation("published", label: "SimpleAllocator") {
                Bind(Clients, to: Set<Client>([.c1, .c2, .c3]))
                Bind(Resources, to: Set<Resource>([.r1, .r2]))
            }
        }
    }
}
