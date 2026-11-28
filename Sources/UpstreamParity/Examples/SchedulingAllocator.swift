// A scheduler grants requests for resources and tracks which resources each client holds.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/allocator/SchedulingAllocator.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct SchedulingAllocatorModel: Sendable {
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
        case request = "Request", allocate = "Allocate", giveBack = "Return", schedule = "Schedule"
    }

    package static var spec: TLASpec {
        #spec("SchedulingAllocator") { scope in
            Extends(.finiteSets)
            Extends(.sequences)
            let clients = scope.parameter(tlaName: "Clients", as: Set<Client>.self, in: Set<Set<Client>>([Set([.c1, .c2, .c3])]))
            let resources = scope.parameter(tlaName: "Resources", as: Set<Resource>.self, in: Set<Set<Resource>>([Set([.r1, .r2])]))
            let choices = Subsets(of: resources)
            let unsat = scope.sharedVar(initial: Dictionary<Client, Set<Resource>>.mapping(over: clients) { _ in Set<Resource>() })
            let alloc = scope.sharedVar(initial: Dictionary<Client, Set<Resource>>.mapping(over: clients) { _ in Set<Resource>() })
            let sched = scope.sharedVar(initial: [Client]())
            let positions = IntRange(1, through: sched.count)
            let waiting = clients.filter { c in !unsat[c].isEmpty && !sched.contains(c) }

            Do(Step.request, over: clients, choices) { client, requested in
                When(unsat[client].isEmpty && alloc[client].isEmpty && !requested.isEmpty)
                unsat[client].set(requested)
            }
            let allocate = Do(Step.allocate, over: clients, choices) { client, granted in
                When(!granted.isEmpty && granted.isSubset(of: unsat[client]))
                When(clients.allSatisfy { other in alloc[other].intersection(granted).isEmpty })
                With(positions) { i in
                    When(sched[i] == client)
                    When(IntRange(1, through: i - 1).allSatisfy { j in unsat[sched[j]].intersection(granted).isEmpty })
                    sched.set(If(granted == unsat[client], then: sched.removing(at: i), else: sched))
                    alloc[client].set(alloc[client].union(granted))
                    unsat[client].set(unsat[client].subtracting(granted))
                }
            }
            let giveBack = Do(Step.giveBack, over: clients, choices) { client, returned in
                When(!returned.isEmpty && returned.isSubset(of: alloc[client]))
                alloc[client].set(alloc[client].subtracting(returned))
            }

            let schedule = Do(Step.schedule) {
                When(!waiting.isEmpty)
                With(Sequences(of: waiting, lengths: IntRange(waiting.count, through: waiting.count)).filter { order in
                    waiting.allSatisfy { client in order.contains(client) }
                }) { order in
                    sched.set(sched.concatenating(order))
                }
            }

            // On Return, this flag changes only for a full return with no outstanding request.
            WeakFairness(giveBack, on: unsat[Client.c1].isEmpty && alloc[Client.c1].isEmpty)
            WeakFairness(giveBack, on: unsat[Client.c2].isEmpty && alloc[Client.c2].isEmpty)
            WeakFairness(giveBack, on: unsat[Client.c3].isEmpty && alloc[Client.c3].isEmpty)
            WeakFairness(eachOf: [allocate])
            WeakFairness(schedule)

            let typeInvariant = Invariant("TypeInvariant")
            typeInvariant {
                positions.allSatisfy { i in clients.contains(sched[i]) }
                unsat.keys == clients
                alloc.keys == clients
                clients.allSatisfy { client in
                    unsat[client].isSubset(of: resources) && alloc[client].isSubset(of: resources)
                }
            }
            let mutex = Invariant("ResourceMutex")
            mutex {
                clients.allSatisfy { first in
                    clients.allSatisfy { second in first == second || alloc[first].intersection(alloc[second]).isEmpty }
                }
            }
            let allocatorInvariant = Invariant("AllocatorInvariant")
            allocatorInvariant {
                positions.allSatisfy { i in !unsat[sched[i]].isEmpty }
                waiting.allSatisfy { client in !unsat[client].isEmpty }
                positions.allSatisfy { i in
                    IntRange(1, through: i - 1).allSatisfy { j in alloc[sched[i]].intersection(unsat[sched[j]]).isEmpty }
                }
                positions.allSatisfy { i in
                    unsat[sched[i]].allSatisfy { resource in
                        clients.allSatisfy { client in !alloc[client].contains(resource) }
                            || IntRange(1, through: i - 1).contains { j in
                                unsat[sched[j]].contains(resource) || alloc[sched[j]].contains(resource)
                            }
                            || clients.contains { client in !sched.contains(client) && alloc[client].contains(resource) }
                    }
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
            let simple = Instance(of: SimpleAllocatorModel.self) {
                Bind(\.clients, projecting: clients)
                Bind(\.resources, projecting: resources)
            }
            let SimpleAllocator = Refinement(instance: simple) {
                Map(\.unsat, projecting: unsat)
                Map(\.alloc, projecting: alloc)
            }

            Validation("published", label: "SchedulingAllocator") {
                Bind(clients, to: Set<Client>([.c1, .c2, .c3]))
                Bind(resources, to: Set<Resource>([.r1, .r2]))
            }.checking(only: [typeInvariant, mutex, allocatorInvariant, ClientsWillReturn, ClientsWillObtain, InfOftenSatisfied])
            Validation("refinement", label: "AllocatorRefinement") {
                Bind(clients, to: Set<Client>([.c1, .c2, .c3]))
                Bind(resources, to: Set<Resource>([.r1, .r2]))
            }.checking(only: [SimpleAllocator])
        }
    }
}
