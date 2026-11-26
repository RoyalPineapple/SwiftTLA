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
            let Clients = scope.parameter(as: Set<Client>.self, in: Set<Set<Client>>([Set([.c1, .c2, .c3])]))
            let Resources = scope.parameter(as: Set<Resource>.self, in: Set<Set<Resource>>([Set([.r1, .r2])]))
            let choices = Subsets(of: Resources)
            let unsat = scope.sharedVar(initial: Dictionary<Client, Set<Resource>>.mapping(over: Clients) { _ in Set<Resource>() })
            let alloc = scope.sharedVar(initial: Dictionary<Client, Set<Resource>>.mapping(over: Clients) { _ in Set<Resource>() })
            let sched = scope.sharedVar(initial: [Client]())
            let positions = IntRange(1, through: sched.count)
            let waiting = Clients.filter { c in !unsat[c].isEmpty && !sched.contains(c) }

            Do(Step.request, over: Clients, choices) { client, requested in
                When(unsat[client].isEmpty && alloc[client].isEmpty && !requested.isEmpty)
                unsat[client].set(requested)
            }
            let allocate = Do(Step.allocate, over: Clients, choices) { client, granted in
                When(!granted.isEmpty && granted.isSubset(of: unsat[client]))
                When(Clients.allSatisfy { other in alloc[other].intersection(granted).isEmpty })
                With(positions) { i in
                    When(sched[i] == client)
                    When(IntRange(1, through: i - 1).allSatisfy { j in unsat[sched[j]].intersection(granted).isEmpty })
                    sched.set(If(granted == unsat[client], then: sched.removing(at: i), else: sched))
                    alloc[client].set(alloc[client].union(granted))
                    unsat[client].set(unsat[client].subtracting(granted))
                }
            }
            let giveBack = Do(Step.giveBack, over: Clients, choices) { client, returned in
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
                positions.allSatisfy { i in Clients.contains(sched[i]) }
                unsat.keys == Clients
                alloc.keys == Clients
                Clients.allSatisfy { client in
                    unsat[client].isSubset(of: Resources) && alloc[client].isSubset(of: Resources)
                }
            }
            let mutex = Invariant("ResourceMutex")
            mutex {
                Clients.allSatisfy { first in
                    Clients.allSatisfy { second in first == second || alloc[first].intersection(alloc[second]).isEmpty }
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
                        Clients.allSatisfy { client in !alloc[client].contains(resource) }
                            || IntRange(1, through: i - 1).contains { j in
                                unsat[sched[j]].contains(resource) || alloc[sched[j]].contains(resource)
                            }
                            || Clients.contains { client in !sched.contains(client) && alloc[client].contains(resource) }
                    }
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
            let simple = Instance(of: SimpleAllocatorModel.self) {
                Bind(\.Clients, projecting: Clients)
                Bind(\.Resources, projecting: Resources)
            }
            let SimpleAllocator = Refinement(instance: simple) {
                Map(\.unsat, projecting: unsat)
                Map(\.alloc, projecting: alloc)
            }

            Validation("published", label: "SchedulingAllocator") {
                Bind(Clients, to: Set<Client>([.c1, .c2, .c3]))
                Bind(Resources, to: Set<Resource>([.r1, .r2]))
            }.checking(only: [typeInvariant, mutex, allocatorInvariant, ClientsWillReturn, ClientsWillObtain, InfOftenSatisfied])
            Validation("refinement", label: "AllocatorRefinement") {
                Bind(Clients, to: Set<Client>([.c1, .c2, .c3]))
                Bind(Resources, to: Set<Resource>([.r1, .r2]))
            }.checking(only: [SimpleAllocator])
        }
    }
}
