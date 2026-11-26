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
            let clients = scope.parameter(tlaName: "Clients", as: Set<Client>.self, in: Set<Set<Client>>([Set([.c1, .c2, .c3])]))
            let resources = scope.parameter(tlaName: "Resources", as: Set<Resource>.self, in: Set<Set<Resource>>([Set([.r1, .r2])]))
            let choices = Subsets(of: resources)
            let unsat = scope.sharedVar(initial: Dictionary<Client, Set<Resource>>.mapping(over: clients) { _ in Set<Resource>() })
            let alloc = scope.sharedVar(initial: Dictionary<Client, Set<Resource>>.mapping(over: clients) { _ in Set<Resource>() })
            Do(Step.request, over: clients, choices) { client, requested in
                When(unsat[client].isEmpty && alloc[client].isEmpty && !requested.isEmpty)
                unsat[client].set(requested)
            }
            let allocate = Do(Step.allocate, over: clients, choices) { client, granted in
                When(!granted.isEmpty && granted.isSubset(of: unsat[client]))
                When(clients.allSatisfy { other in alloc[other].intersection(granted).isEmpty })
                alloc[client].set(alloc[client].union(granted))
                unsat[client].set(unsat[client].subtracting(granted))
            }
            let giveBack = Do(Step.giveBack, over: clients, choices) { client, returned in
                When(!returned.isEmpty && returned.isSubset(of: alloc[client]))
                alloc[client].set(alloc[client].subtracting(returned))
            }

            // A Return changes a client's emptiness flag exactly when that client returns everything.
            WeakFairness(giveBack, on: alloc[Client.c1].isEmpty)
            WeakFairness(giveBack, on: alloc[Client.c2].isEmpty)
            WeakFairness(giveBack, on: alloc[Client.c3].isEmpty)
            StrongFairness(eachOf: [allocate])

            Invariant("TypeInvariant") {
                unsat.keys == clients
                alloc.keys == clients
                clients.allSatisfy { client in
                    unsat[client].isSubset(of: resources) && alloc[client].isSubset(of: resources)
                }
            }
            Invariant("ResourceMutex") {
                clients.allSatisfy { first in
                    clients.allSatisfy { second in first == second || alloc[first].intersection(alloc[second]).isEmpty }
                }
            }
            let ClientsWillReturn = Temporal()
            ClientsWillReturn(forEach: clients) { client in .leadsTo(unsat[client].isEmpty, alloc[client].isEmpty) }
            let ClientsWillObtain = Temporal()
            ClientsWillObtain(forEach: clients) { client in .all([
                .leadsTo(unsat[client].contains(Resource.r1), alloc[client].contains(Resource.r1)),
                .leadsTo(unsat[client].contains(Resource.r2), alloc[client].contains(Resource.r2)),
            ]) }
            let InfOftenSatisfied = Temporal()
            InfOftenSatisfied(forEach: clients) { client in .alwaysEventually(unsat[client].isEmpty) }
            Validation("published", label: "SimpleAllocator") {
                Bind(clients, to: Set<Client>([.c1, .c2, .c3]))
                Bind(resources, to: Set<Resource>([.r1, .r2]))
            }
        }
    }
}
